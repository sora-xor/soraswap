import { writeTelemetrySnapshot } from "../shared/telemetry";

export type OptionKind = "shout" | "outperformance";

export type OptionsFactoryConfig = {
  oracleStaleSlots: number;
};

export type OptionsTreasuryState = {
  balance: number;
  reservedCollateral: number;
  surplus: number;
  premiumAccrued: number;
  settledPayouts: number;
};

type SeriesState = {
  seriesId: number;
  kind: OptionKind;
  status: "active" | "expired" | "settled";
  maxNotional: number;
  premiumBps: number;
  collateralMultiplierBps: number;
  expirySlot: number;
  strikeBps: number;
  openNotional: number;
  utilisationBps: number;
  bumpActivateBps: number;
  bumpDeactivateBps: number;
  pauseThresholdBps: number;
  bumpPercentBps: number;
  lastSettlementSlot: number;
  oracleSlot: number;
  attestationHash: number;
  finalMark: number;
  finalQuoteMark: number;
  finalBaseReturnBps: number;
  finalQuoteReturnBps: number;
  settlementReady: boolean;
};

type PositionState = {
  positionId: number;
  owner: string;
  seriesId: number;
  kind: OptionKind;
  notional: number;
  premiumPaid: number;
  collateralLocked: number;
  status: "active" | "closed";
  recordedPayout: number;
  settlementReady: boolean;
  shoutFloorBps: number;
  lastOracleMarkBps: number;
  lastOracleSlot: number;
  lastAttestationHash: number;
};

export class OptionsFactoryModel {
  private readonly series = new Map<number, SeriesState>();
  private readonly positions = new Map<number, PositionState>();
  private nextPositionId = 1;
  private withdrawalOnly = true;
  private automationBacklogCap = 0;
  private automationBacklog = 0;
  private automationSafeMode = false;
  private balance = 0;
  private reservedCollateral = 0;
  private premiumAccrued = 0;
  private settledPayouts = 0;

  constructor(private readonly config: OptionsFactoryConfig) {
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

  syncSeries(
    seriesId: number,
    input: {
      kind: OptionKind;
      maxNotional: number;
      premiumBps: number;
      collateralMultiplierBps: number;
      expirySlot: number;
      strikeBps: number;
    },
    currentSlot: number
  ): void {
    if (seriesId <= 0 || seriesId >= 1_000_000) {
      throw new Error("invalid series id");
    }
    this.assertPositive(input.maxNotional, "max notional");
    if (input.premiumBps <= 0 || input.premiumBps > 10_000) {
      throw new Error("invalid premium");
    }
    if (input.collateralMultiplierBps < 10_000) {
      throw new Error("invalid collateral");
    }
    if (input.expirySlot <= currentSlot) {
      throw new Error("invalid expiry");
    }
    if (input.strikeBps <= 0) {
      throw new Error("invalid strike");
    }
    const prior = this.series.get(seriesId);
    if (prior && prior.openNotional !== 0) {
      throw new Error("series capacity");
    }
    if (!prior && this.series.size >= 64) {
      throw new Error("series limit");
    }
    this.series.set(seriesId, {
      seriesId,
      ...input,
      status: "active",
      openNotional: 0,
      utilisationBps: 0,
      bumpActivateBps: prior?.bumpActivateBps ?? 8_000,
      bumpDeactivateBps: prior?.bumpDeactivateBps ?? 6_000,
      pauseThresholdBps: prior?.pauseThresholdBps ?? 9_500,
      bumpPercentBps: prior?.bumpPercentBps ?? 1_500,
      lastSettlementSlot: 0,
      oracleSlot: -1,
      attestationHash: 0,
      finalMark: 0,
      finalQuoteMark: 0,
      finalBaseReturnBps: 0,
      finalQuoteReturnBps: 0,
      settlementReady: false
    });
  }

  configureUtilisationGuard(
    seriesId: number,
    input: {
      bumpActivateBps: number;
      bumpDeactivateBps: number;
      pauseThresholdBps: number;
      bumpPercentBps: number;
    }
  ): void {
    const series = this.mustSeries(seriesId);
    if (
      input.bumpActivateBps < 0 || input.bumpActivateBps > 10_000 ||
      input.bumpDeactivateBps < 0 || input.bumpDeactivateBps > input.bumpActivateBps ||
      input.pauseThresholdBps < input.bumpActivateBps || input.pauseThresholdBps > 10_000 ||
      input.bumpPercentBps < 0 || input.bumpPercentBps > 10_000
    ) {
      throw new Error("invalid utilisation guard");
    }
    Object.assign(series, input);
  }

  buyShout(owner: string, seriesId: number, notional: number, currentSlot: number): number {
    return this.buyPosition(owner, seriesId, "shout", notional, currentSlot);
  }

  buyOutperformance(owner: string, seriesId: number, notional: number, currentSlot: number): number {
    return this.buyPosition(owner, seriesId, "outperformance", notional, currentSlot);
  }

  publishShoutMark(
    positionId: number,
    markPriceBps: number,
    oracleSlot: number,
    attestationHash: number,
    currentSlot: number
  ): void {
    const position = this.mustActivePosition(positionId);
    if (position.kind !== "shout") {
      throw new Error("position kind mismatch");
    }
    if (markPriceBps < 0) {
      throw new Error("invalid mark");
    }
    this.assertOraclePublication(oracleSlot, position.lastOracleSlot, attestationHash, currentSlot);
    position.shoutFloorBps = Math.max(position.shoutFloorBps, markPriceBps);
    position.lastOracleMarkBps = markPriceBps;
    position.lastOracleSlot = oracleSlot;
    position.lastAttestationHash = attestationHash;
  }

  settleOutperformanceSeries(
    seriesId: number,
    input: {
      finalMark: number;
      finalQuoteMark: number;
      baseReturnBps: number;
      quoteReturnBps: number;
      oracleSlot: number;
      attestationHash: number;
    },
    currentSlot: number
  ): void {
    const series = this.mustSeries(seriesId);
    if (series.kind !== "outperformance") {
      throw new Error("position kind mismatch");
    }
    if (series.status !== "active" && series.status !== "expired") {
      throw new Error("series inactive");
    }
    if (currentSlot < series.expirySlot) {
      throw new Error("series not expired");
    }
    if (input.finalMark < 0 || input.finalQuoteMark < 0) {
      throw new Error("invalid mark");
    }
    if (
      input.baseReturnBps < -1_000_000 || input.baseReturnBps > 1_000_000 ||
      input.quoteReturnBps < -1_000_000 || input.quoteReturnBps > 1_000_000
    ) {
      throw new Error("invalid mark");
    }
    this.assertOraclePublication(input.oracleSlot, series.oracleSlot, input.attestationHash, currentSlot);
    series.status = "settled";
    series.lastSettlementSlot = currentSlot;
    series.oracleSlot = input.oracleSlot;
    series.attestationHash = input.attestationHash;
    series.finalMark = input.finalMark;
    series.finalQuoteMark = input.finalQuoteMark;
    series.finalBaseReturnBps = input.baseReturnBps;
    series.finalQuoteReturnBps = input.quoteReturnBps;
    series.settlementReady = true;
  }

  exerciseShoutPosition(owner: string, positionId: number, currentSlot: number): number {
    const position = this.mustActivePosition(positionId);
    this.assertOwner(position, owner);
    if (position.kind !== "shout") {
      throw new Error("position kind mismatch");
    }
    if (position.lastAttestationHash <= 0) {
      throw new Error("attestation missing");
    }
    this.assertOracleFresh(position.lastOracleSlot, currentSlot);
    const series = this.mustSeries(position.seriesId);
    const effectiveMark = Math.max(position.shoutFloorBps, position.lastOracleMarkBps);
    const intrinsicBps = effectiveMark - series.strikeBps;
    const desiredPayout = intrinsicBps <= 0 ? 0 : Math.floor((position.notional * intrinsicBps) / 10_000);
    return this.closePosition(position, desiredPayout);
  }

  exerciseOutperformancePosition(owner: string, positionId: number): number {
    const position = this.mustActivePosition(positionId);
    this.assertOwner(position, owner);
    if (position.kind !== "outperformance") {
      throw new Error("position kind mismatch");
    }
    const series = this.mustSeries(position.seriesId);
    if (!series.settlementReady) {
      throw new Error("series not expired");
    }
    const positiveDifference = Math.max(series.finalBaseReturnBps - series.finalQuoteReturnBps, 0);
    const desiredPayout = Math.floor(
      (position.notional * positiveDifference * series.collateralMultiplierBps) / 10_000 / 10_000
    );
    return this.closePosition(position, desiredPayout);
  }

  runNativeLifecycle(currentSlot: number): number {
    let processed = 0;
    for (const series of this.series.values()) {
      if (series.status === "active" && currentSlot >= series.expirySlot) {
        series.status = "expired";
      }
      processed += 1;
    }
    return processed;
  }

  withdrawSurplus(amount: number): OptionsTreasuryState {
    this.assertPositive(amount, "surplus withdrawal");
    if (this.balance < this.reservedCollateral + amount) {
      throw new Error("insufficient reserve");
    }
    this.balance -= amount;
    return this.treasuryState();
  }

  treasuryState(): OptionsTreasuryState {
    return {
      balance: this.balance,
      reservedCollateral: this.reservedCollateral,
      surplus: this.balance - this.reservedCollateral,
      premiumAccrued: this.premiumAccrued,
      settledPayouts: this.settledPayouts
    };
  }

  seriesState(seriesId: number): SeriesState {
    return { ...this.mustSeries(seriesId) };
  }

  positionState(positionId: number): PositionState {
    return { ...this.mustPosition(positionId) };
  }

  assertInvariant(): void {
    if (this.balance < 0 || this.reservedCollateral < 0 || this.balance < this.reservedCollateral) {
      throw new Error("options reserve invariant");
    }
    const positionReserve = [...this.positions.values()]
      .filter((position) => position.status === "active")
      .reduce((total, position) => total + position.collateralLocked, 0);
    if (positionReserve !== this.reservedCollateral) {
      throw new Error("options collateral mismatch");
    }
  }

  static runScenario(): ReturnType<typeof writeTelemetrySnapshot>["payload"] {
    const options = new OptionsFactoryModel({ oracleStaleSlots: 4 });
    options.syncAutomation(8, false);
    options.heartbeat(2, false);
    options.exitWithdrawalOnly();
    options.syncSeries(1, {
      kind: "shout",
      maxNotional: 30_000,
      premiumBps: 450,
      collateralMultiplierBps: 10_000,
      expirySlot: 40,
      strikeBps: 10_200
    }, 10);
    options.syncSeries(2, {
      kind: "outperformance",
      maxNotional: 20_000,
      premiumBps: 600,
      collateralMultiplierBps: 10_000,
      expirySlot: 40,
      strikeBps: 10_000
    }, 10);

    const shoutPosition = options.buyShout("alice", 1, 6_000, 20);
    const outperformancePosition = options.buyOutperformance("bob", 2, 5_000, 20);
    options.publishShoutMark(shoutPosition, 11_400, 30, 301, 31);
    const shoutPayout = options.exerciseShoutPosition("alice", shoutPosition, 32);
    options.settleOutperformanceSeries(2, {
      finalMark: 18_000,
      finalQuoteMark: 10_500,
      baseReturnBps: 18_000,
      quoteReturnBps: 10_500,
      oracleSlot: 40,
      attestationHash: 402
    }, 40);
    const outperformancePayout = options.exerciseOutperformancePosition("bob", outperformancePosition);

    const stalePosition = options.buyShout("carol", 1, 4_000, 35);
    let staleOracleRejected = false;
    try {
      options.publishShoutMark(stalePosition, 10_400, 30, 501, 39);
    } catch {
      staleOracleRejected = true;
    }
    options.publishShoutMark(stalePosition, 10_000, 39, 502, 39);
    options.exerciseShoutPosition("carol", stalePosition, 39);
    options.assertInvariant();

    const payload = {
      shoutSeries: options.seriesState(1),
      outperformanceSeries: options.seriesState(2),
      shoutPosition: options.positionState(shoutPosition),
      outperformancePosition: options.positionState(outperformancePosition),
      shoutPayoff: {
        shoutFloorBps: options.positionState(shoutPosition).shoutFloorBps,
        payout: shoutPayout
      },
      outperformanceSettlement: {
        baseReturnBps: options.seriesState(2).finalBaseReturnBps,
        quoteReturnBps: options.seriesState(2).finalQuoteReturnBps,
        payout: outperformancePayout
      },
      staleOracleRejected,
      treasury: options.treasuryState()
    };

    writeTelemetrySnapshot("options_factory", payload);
    return payload;
  }

  private buyPosition(
    owner: string,
    seriesId: number,
    expectedKind: OptionKind,
    notional: number,
    currentSlot: number
  ): number {
    this.assertRiskOn();
    const series = this.mustSeries(seriesId);
    if (series.kind !== expectedKind) {
      throw new Error("position kind mismatch");
    }
    if (series.status !== "active") {
      throw new Error("series inactive");
    }
    if (currentSlot >= series.expirySlot) {
      throw new Error("series expired");
    }
    this.assertPositive(notional, "notional");
    const nextOpen = series.openNotional + notional;
    if (nextOpen > series.maxNotional) {
      throw new Error("series capacity");
    }
    const nextUtilisation = this.utilisationBps(series, nextOpen);
    if (nextUtilisation > series.pauseThresholdBps) {
      throw new Error("series paused by guard");
    }
    if (this.nextPositionId >= 1_000_000_000) {
      throw new Error("position limit");
    }
    const premium = this.requiredPremium(series, notional);
    const collateral = Math.floor((notional * series.collateralMultiplierBps) / 10_000);
    if (premium <= 0) {
      throw new Error("invalid premium");
    }
    if (collateral < notional) {
      throw new Error("invalid collateral");
    }
    this.assertReserveBacked();
    const funding = premium + collateral;
    if (this.balance + funding < this.reservedCollateral + collateral) {
      throw new Error("insufficient reserve");
    }

    const positionId = this.nextPositionId++;
    this.balance += funding;
    this.reservedCollateral += collateral;
    this.premiumAccrued += premium;
    series.openNotional = nextOpen;
    series.utilisationBps = nextUtilisation;
    this.positions.set(positionId, {
      positionId,
      owner,
      seriesId,
      kind: expectedKind,
      notional,
      premiumPaid: premium,
      collateralLocked: collateral,
      status: "active",
      recordedPayout: 0,
      settlementReady: false,
      shoutFloorBps: 0,
      lastOracleMarkBps: 0,
      lastOracleSlot: -1,
      lastAttestationHash: 0
    });
    return positionId;
  }

  private closePosition(position: PositionState, desiredPayout: number): number {
    if (this.reservedCollateral < position.collateralLocked) {
      throw new Error("reserve invariant");
    }
    const payout = Math.min(desiredPayout, position.collateralLocked);
    if (this.balance < payout) {
      throw new Error("insufficient reserve");
    }
    this.balance -= payout;
    this.reservedCollateral -= position.collateralLocked;
    this.settledPayouts += payout;
    position.collateralLocked = 0;
    position.recordedPayout = payout;
    position.settlementReady = true;
    position.status = "closed";
    const series = this.mustSeries(position.seriesId);
    if (series.openNotional < position.notional) {
      throw new Error("series index corrupt");
    }
    series.openNotional -= position.notional;
    series.utilisationBps = this.utilisationBps(series, series.openNotional);
    return payout;
  }

  private requiredPremium(series: SeriesState, notional: number): number {
    const basePremium = Math.floor((notional * series.premiumBps) / 10_000);
    if (series.bumpActivateBps > 0 && series.utilisationBps >= series.bumpActivateBps) {
      return basePremium + Math.floor((basePremium * series.bumpPercentBps) / 10_000);
    }
    return basePremium;
  }

  private utilisationBps(series: SeriesState, openNotional: number): number {
    return Math.ceil((openNotional * 10_000) / series.maxNotional);
  }

  private assertOraclePublication(
    oracleSlot: number,
    priorOracleSlot: number,
    attestationHash: number,
    currentSlot: number
  ): void {
    if (attestationHash <= 0) {
      throw new Error("attestation missing");
    }
    this.assertOracleFresh(oracleSlot, currentSlot);
    if (oracleSlot <= priorOracleSlot) {
      throw new Error("oracle slot replay");
    }
  }

  private assertOracleFresh(oracleSlot: number, currentSlot: number): void {
    if (oracleSlot < 0 || currentSlot < oracleSlot) {
      throw new Error("invalid oracle slot");
    }
    if (currentSlot - oracleSlot > this.config.oracleStaleSlots) {
      throw new Error("oracle stale");
    }
  }

  private assertRiskOn(): void {
    if (this.withdrawalOnly) {
      throw new Error("withdrawal-only mode");
    }
    if (this.automationSafeMode || this.automationBacklog > this.automationBacklogCap) {
      throw new Error("options automation unsafe");
    }
  }

  private assertReserveBacked(): void {
    if (this.balance < this.reservedCollateral) {
      throw new Error("insufficient reserve");
    }
  }

  private assertOwner(position: PositionState, owner: string): void {
    if (position.owner !== owner) {
      throw new Error("position owner mismatch");
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

  private mustSeries(seriesId: number): SeriesState {
    const series = this.series.get(seriesId);
    if (!series) {
      throw new Error(`series ${seriesId} missing`);
    }
    return series;
  }

  private mustPosition(positionId: number): PositionState {
    const position = this.positions.get(positionId);
    if (!position) {
      throw new Error(`position ${positionId} missing`);
    }
    return position;
  }

  private mustActivePosition(positionId: number): PositionState {
    const position = this.mustPosition(positionId);
    if (position.status !== "active") {
      throw new Error("position inactive");
    }
    return position;
  }
}
