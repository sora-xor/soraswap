import { writeTelemetrySnapshot } from "../shared/telemetry";

export type CoverManagerConfig = {
  defaultRequiredObservations: number;
  oracleStaleSlots: number;
};

export type CoverReserveState = {
  balance: number;
  reservedPayout: number;
  surplus: number;
  premiumCollected: number;
  settledPayouts: number;
};

type PolicyState = {
  policyId: number;
  owner: string;
  lowerBound: number;
  upperBound: number;
  payoutAmount: number;
  monitoringWindowSlots: number;
  requiredObservations: number;
  coveredNotional: number;
  premiumPaid: number;
  status: "active" | "claimable" | "claimed" | "expired";
  registrationSlot: number;
  breachStartSlot: number;
  breachElapsedSlots: number;
  observationCount: number;
  lastOracleSlot: number;
  lastObservedPrice: number;
  lastAttestationHash: number;
  claimPayout: number;
};

export class CoverManagerModel {
  private nextPolicyId = 1;
  private readonly policies = new Map<number, PolicyState>();
  private withdrawalOnly = true;
  private automationBacklogCap = 0;
  private automationBacklog = 0;
  private automationSafeMode = false;
  private balance = 0;
  private reservedPayout = 0;
  private premiumCollected = 0;
  private settledPayouts = 0;

  constructor(private readonly config: CoverManagerConfig) {
    if (config.defaultRequiredObservations <= 0) {
      throw new Error("invalid required observations");
    }
    if (config.oracleStaleSlots < 0) {
      throw new Error("invalid oracle stale slots");
    }
  }

  exitWithdrawalOnly(): void {
    this.withdrawalOnly = false;
  }

  enterWithdrawalOnly(): void {
    this.withdrawalOnly = true;
  }

  syncAutomation(backlogCap: number, safeMode: boolean): void {
    this.assertNonNegative(backlogCap, "automation backlog cap");
    if (this.automationBacklog > backlogCap) {
      throw new Error("automation backlog exceeds cap");
    }
    this.automationBacklogCap = backlogCap;
    this.automationSafeMode = safeMode;
  }

  heartbeat(backlog: number, safeMode: boolean): void {
    this.assertNonNegative(backlog, "automation backlog");
    if (backlog > this.automationBacklogCap) {
      throw new Error("automation backlog exceeds cap");
    }
    this.automationBacklog = backlog;
    this.automationSafeMode = safeMode;
  }

  fundReserve(amount: number): CoverReserveState {
    this.assertPositive(amount, "reserve funding");
    this.balance += amount;
    return this.reserveState();
  }

  withdrawSurplus(amount: number): CoverReserveState {
    this.assertPositive(amount, "surplus withdrawal");
    if (this.balance < this.reservedPayout + amount) {
      throw new Error("insufficient reserve");
    }
    this.balance -= amount;
    return this.reserveState();
  }

  registerPolicy(
    owner: string,
    input: {
      lowerBound: number;
      upperBound: number;
      payoutAmount: number;
      monitoringWindowSlots: number;
      requiredObservations: number;
      coveredNotional: number;
      premiumPaid: number;
    },
    currentSlot: number
  ): number {
    this.assertRiskOn();
    if (input.lowerBound < 0 || input.upperBound <= input.lowerBound) {
      throw new Error("invalid bounds");
    }
    this.assertPositive(input.payoutAmount, "payout");
    this.assertPositive(input.coveredNotional, "covered notional");
    this.assertPositive(input.premiumPaid, "premium");
    if (input.monitoringWindowSlots <= 0) {
      throw new Error("invalid monitoring window");
    }
    if (input.requiredObservations <= 0 || input.requiredObservations > 64) {
      throw new Error("invalid required observations");
    }
    if (this.nextPolicyId > 64) {
      throw new Error("policy limit");
    }
    this.assertReserveBacked();
    const nextReserved = this.reservedPayout + input.payoutAmount;
    if (this.balance + input.premiumPaid < nextReserved) {
      throw new Error("insufficient reserve");
    }

    const policyId = this.nextPolicyId++;
    this.balance += input.premiumPaid;
    this.reservedPayout = nextReserved;
    this.premiumCollected += input.premiumPaid;
    this.policies.set(policyId, {
      policyId,
      owner,
      ...input,
      status: "active",
      registrationSlot: currentSlot,
      breachStartSlot: 0,
      breachElapsedSlots: 0,
      observationCount: 0,
      lastOracleSlot: -1,
      lastObservedPrice: 0,
      lastAttestationHash: 0,
      claimPayout: 0
    });
    return policyId;
  }

  recordObservation(
    policyId: number,
    observedPrice: number,
    oracleSlot: number,
    statusFlags: number,
    attestationHash: number,
    currentSlot: number
  ): PolicyState {
    const policy = this.mustPolicy(policyId);
    if (policy.status !== "active") {
      throw new Error("policy not active");
    }
    if (this.automationSafeMode) {
      throw new Error("cover automation unsafe");
    }
    if (observedPrice < 0) {
      throw new Error("invalid observed price");
    }
    if (statusFlags !== 0) {
      throw new Error("invalid status flags");
    }
    if (attestationHash <= 0) {
      throw new Error("attestation missing");
    }
    if (oracleSlot < 0 || currentSlot < oracleSlot) {
      throw new Error("invalid oracle slot");
    }
    if (currentSlot - oracleSlot > this.config.oracleStaleSlots) {
      throw new Error("oracle stale");
    }
    const priorSlot = policy.lastOracleSlot;
    if (oracleSlot <= priorSlot) {
      throw new Error("oracle slot replay");
    }

    const breached = observedPrice < policy.lowerBound || observedPrice > policy.upperBound;
    if (breached) {
      if (
        priorSlot < 0 ||
        oracleSlot - priorSlot > this.config.oracleStaleSlots ||
        policy.observationCount === 0
      ) {
        policy.breachStartSlot = oracleSlot;
        policy.breachElapsedSlots = 0;
        policy.observationCount = 1;
      } else {
        policy.breachElapsedSlots += oracleSlot - priorSlot;
        policy.observationCount += 1;
      }
      if (
        policy.breachElapsedSlots >= policy.monitoringWindowSlots &&
        policy.observationCount >= policy.requiredObservations
      ) {
        policy.status = "claimable";
      }
    } else {
      this.resetBreach(policy);
    }
    policy.lastOracleSlot = oracleSlot;
    policy.lastObservedPrice = observedPrice;
    policy.lastAttestationHash = attestationHash;
    return { ...policy };
  }

  routeClaim(owner: string, policyId: number): number {
    const policy = this.mustPolicy(policyId);
    if (policy.owner !== owner) {
      throw new Error("policy owner mismatch");
    }
    if (policy.status !== "claimable") {
      throw new Error("policy not claimable");
    }
    if (policy.claimPayout !== 0) {
      throw new Error("policy already claimed");
    }
    if (this.reservedPayout < policy.payoutAmount) {
      throw new Error("reserve invariant");
    }
    if (this.balance < policy.payoutAmount) {
      throw new Error("insufficient reserve");
    }
    this.balance -= policy.payoutAmount;
    this.releasePolicyReserve(policy);
    this.settledPayouts += policy.payoutAmount;
    policy.claimPayout = policy.payoutAmount;
    policy.status = "claimed";
    return policy.claimPayout;
  }

  expirePolicy(policyId: number, currentSlot: number): void {
    const policy = this.mustPolicy(policyId);
    if (policy.status !== "active") {
      throw new Error("policy not active");
    }
    if (currentSlot < policy.registrationSlot + policy.monitoringWindowSlots) {
      throw new Error("policy live");
    }
    this.releasePolicyReserve(policy);
    policy.status = "expired";
  }

  reserveState(): CoverReserveState {
    return {
      balance: this.balance,
      reservedPayout: this.reservedPayout,
      surplus: this.balance - this.reservedPayout,
      premiumCollected: this.premiumCollected,
      settledPayouts: this.settledPayouts
    };
  }

  policy(policyId: number): PolicyState {
    return { ...this.mustPolicy(policyId) };
  }

  assertInvariant(): void {
    if (this.balance < 0 || this.reservedPayout < 0 || this.balance < this.reservedPayout) {
      throw new Error("cover reserve invariant");
    }
    const policyReserve = [...this.policies.values()]
      .filter((policy) => policy.status === "active" || policy.status === "claimable")
      .reduce((total, policy) => total + policy.payoutAmount, 0);
    if (policyReserve !== this.reservedPayout) {
      throw new Error("cover reserved payout mismatch");
    }
  }

  static runScenario(): ReturnType<typeof writeTelemetrySnapshot>["payload"] {
    const cover = new CoverManagerModel({ defaultRequiredObservations: 3, oracleStaleSlots: 4 });
    cover.syncAutomation(10, false);
    cover.heartbeat(1, false);
    cover.exitWithdrawalOnly();
    cover.fundReserve(15_000);

    const policyId = cover.registerPolicy("alice", {
      lowerBound: 9_500,
      upperBound: 10_500,
      payoutAmount: 2_800,
      monitoringWindowSlots: 4,
      requiredObservations: 3,
      coveredNotional: 4_000,
      premiumPaid: 120
    }, 0);

    cover.recordObservation(policyId, 11_000, 10, 0, 101, 10);
    cover.recordObservation(policyId, 11_200, 11, 0, 102, 11);
    cover.recordObservation(policyId, 10_100, 12, 0, 103, 12);
    const resetState = cover.policy(policyId);
    cover.recordObservation(policyId, 11_300, 13, 0, 104, 13);
    cover.recordObservation(policyId, 11_450, 15, 0, 105, 15);
    const claimableState = cover.recordObservation(policyId, 11_600, 17, 0, 106, 17);
    const payout = cover.routeClaim("alice", policyId);
    cover.assertInvariant();

    const payload = {
      policyId,
      resetState,
      claimableState,
      finalPolicy: cover.policy(policyId),
      claimRouting: { payout },
      oracleEvidence: {
        lastOracleSlot: cover.policy(policyId).lastOracleSlot,
        lastAttestationHash: cover.policy(policyId).lastAttestationHash
      },
      reserve: cover.reserveState()
    };

    writeTelemetrySnapshot("cover_manager", payload);
    return payload;
  }

  private releasePolicyReserve(policy: PolicyState): void {
    if (this.reservedPayout < policy.payoutAmount) {
      throw new Error("reserve invariant");
    }
    this.reservedPayout -= policy.payoutAmount;
  }

  private resetBreach(policy: PolicyState): void {
    policy.status = "active";
    policy.breachStartSlot = 0;
    policy.breachElapsedSlots = 0;
    policy.observationCount = 0;
  }

  private assertRiskOn(): void {
    if (this.withdrawalOnly) {
      throw new Error("withdrawal-only mode");
    }
    if (this.automationSafeMode || this.automationBacklog > this.automationBacklogCap) {
      throw new Error("cover automation unsafe");
    }
  }

  private assertReserveBacked(): void {
    if (this.balance < this.reservedPayout) {
      throw new Error("insufficient reserve");
    }
  }

  private assertPositive(value: number, name: string): void {
    if (!Number.isFinite(value) || value <= 0) {
      throw new Error(`${name} invalid`);
    }
  }

  private assertNonNegative(value: number, name: string): void {
    if (!Number.isFinite(value) || value < 0) {
      throw new Error(`${name} invalid`);
    }
  }

  private mustPolicy(policyId: number): PolicyState {
    const policy = this.policies.get(policyId);
    if (!policy) {
      throw new Error(`policy ${policyId} missing`);
    }
    return policy;
  }
}
