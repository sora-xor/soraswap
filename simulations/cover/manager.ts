import { RiskVaultModel } from "../shared/riskVault";
import { writeTelemetrySnapshot } from "../shared/telemetry";

type PolicyState = {
  policyId: number;
  owner: string;
  lowerBound: number;
  upperBound: number;
  payoutAmount: number;
  monitoringWindowSlots: number;
  requiredObservations: number;
  coveredNotional: number;
  status: "active" | "breaching" | "claimable" | "claimed" | "expired";
  breachElapsedSlots: number;
  observationCount: number;
  lastObservedPrice: number;
  lastObservationSlot: number;
  premiumPaid: number;
  claimPayout: number;
};

export class CoverManagerModel {
  private nextPolicyId = 1;
  private readonly policies = new Map<number, PolicyState>();
  private automation = { backlogCap: 0, backlog: 0, safeMode: false };

  constructor(private readonly vault: RiskVaultModel, private readonly defaultRequiredObservations = 3) {}

  configureAutomation(backlogCap: number, backlog: number, safeMode: boolean): void {
    this.automation = { backlogCap, backlog, safeMode };
    this.vault.configureAutomation(3, { backlogCap, backlog, safeMode, cadenceSlots: 3 });
  }

  fundClaims(amount: number): void {
    this.vault.deposit(3, amount);
  }

  registerPolicy(input: {
    owner: string;
    lowerBound: number;
    upperBound: number;
    payoutAmount: number;
    monitoringWindowSlots: number;
    requiredObservations?: number;
    coveredNotional: number;
    premiumPaid: number;
  }): number {
    if (this.automation.safeMode) {
      throw new Error("cover safe mode");
    }
    const policyId = this.nextPolicyId++;
    const policy: PolicyState = {
      policyId,
      owner: input.owner,
      lowerBound: input.lowerBound,
      upperBound: input.upperBound,
      payoutAmount: input.payoutAmount,
      monitoringWindowSlots: input.monitoringWindowSlots,
      requiredObservations: input.requiredObservations ?? this.defaultRequiredObservations,
      coveredNotional: input.coveredNotional,
      status: "active",
      breachElapsedSlots: 0,
      observationCount: 0,
      lastObservedPrice: 0,
      lastObservationSlot: 0,
      premiumPaid: input.premiumPaid,
      claimPayout: 0
    };
    this.policies.set(policyId, policy);
    if (input.premiumPaid > 0) {
      this.vault.deposit(3, input.premiumPaid);
    }
    this.vault.lockLiability(3, policyId, {
      notional: input.coveredNotional,
      collateral: input.payoutAmount,
      backlog: this.automation.backlog
    });
    return policyId;
  }

  recordObservation(policyId: number, observedPrice: number, oracle: { oracleSlot: number; currentSlot: number; statusFlags: number }): PolicyState {
    const policy = this.mustPolicy(policyId);
    const previousSlot = policy.lastObservationSlot;
    policy.lastObservationSlot = oracle.currentSlot;
    policy.lastObservedPrice = observedPrice;

    if (oracle.statusFlags !== 0 || this.automation.safeMode) {
      this.resetPolicy(policy);
      return { ...policy };
    }

    const breached = observedPrice < policy.lowerBound || observedPrice > policy.upperBound;
    if (!breached) {
      this.resetPolicy(policy);
      return { ...policy };
    }

    const delta = previousSlot > 0 ? Math.max(1, oracle.currentSlot - previousSlot) : 1;
    policy.status = "breaching";
    policy.breachElapsedSlots += delta;
    policy.observationCount += 1;
    if (
      policy.breachElapsedSlots >= policy.monitoringWindowSlots &&
      policy.observationCount >= policy.requiredObservations
    ) {
      policy.status = "claimable";
    }
    return { ...policy };
  }

  routeClaim(policyId: number): number {
    const policy = this.mustPolicy(policyId);
    if (policy.status !== "claimable") {
      throw new Error("policy not claimable");
    }
    const payout = this.vault.settlePayout(3, policyId, policy.payoutAmount);
    this.vault.releaseLiability(3, policyId, this.automation.backlog);
    policy.claimPayout = payout;
    policy.status = "claimed";
    return payout;
  }

  expirePolicy(policyId: number): void {
    const policy = this.mustPolicy(policyId);
    if (policy.status === "active") {
      policy.status = "expired";
      this.vault.releaseLiability(3, policyId, this.automation.backlog);
    }
  }

  policy(policyId: number): PolicyState {
    return { ...this.mustPolicy(policyId) };
  }

  static runScenario(): ReturnType<typeof writeTelemetrySnapshot>["payload"] {
    const vault = new RiskVaultModel();
    const cover = new CoverManagerModel(vault, 3);
    cover.configureAutomation(10, 1, false);
    cover.fundClaims(15_000);

    const policyId = cover.registerPolicy({
      owner: "alice",
      lowerBound: 9_500,
      upperBound: 10_500,
      payoutAmount: 2_800,
      monitoringWindowSlots: 4,
      coveredNotional: 4_000,
      premiumPaid: 120
    });

    cover.recordObservation(policyId, 11_000, { oracleSlot: 1, currentSlot: 1, statusFlags: 0 });
    cover.recordObservation(policyId, 11_200, { oracleSlot: 2, currentSlot: 2, statusFlags: 0 });
    cover.recordObservation(policyId, 10_100, { oracleSlot: 3, currentSlot: 3, statusFlags: 1 });
    const resetState = cover.policy(policyId);
    cover.recordObservation(policyId, 11_300, { oracleSlot: 4, currentSlot: 4, statusFlags: 0 });
    cover.recordObservation(policyId, 11_450, { oracleSlot: 5, currentSlot: 6, statusFlags: 0 });
    const claimableState = cover.recordObservation(policyId, 11_600, { oracleSlot: 6, currentSlot: 8, statusFlags: 0 });
    const payout = cover.routeClaim(policyId);

    const payload = {
      policyId,
      resetState,
      claimableState,
      finalPolicy: cover.policy(policyId),
      claimRouting: {
        payout,
        bucket: vault.bucketState(3)
      },
      payoutCap: {
        configuredCapBps: vault.bucketState(3).payoutCapBps,
        requested: cover.policy(policyId).payoutAmount,
        settled: payout
      },
      backlogState: {
        backlogCap: 10,
        backlog: 1
      },
      riskState: vault.riskState()
    };

    writeTelemetrySnapshot("cover_shared_risk", payload);
    return payload;
  }

  private resetPolicy(policy: PolicyState): void {
    policy.status = "active";
    policy.breachElapsedSlots = 0;
    policy.observationCount = 0;
  }

  private mustPolicy(policyId: number): PolicyState {
    const policy = this.policies.get(policyId);
    if (!policy) {
      throw new Error(`policy ${policyId} missing`);
    }
    return policy;
  }
}
