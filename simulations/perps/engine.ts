import { writeTelemetrySnapshot } from "../shared/telemetry";

export type MarketOraclePublication = {
  markPriceBps: number;
  indexPriceBps: number;
  confidenceBps: number;
  oracleSlot: number;
  currentSlot: number;
  statusFlags: number;
  attestationHash: number;
};

export type MarketConfig = {
  asset: string;
  maxLeverageBps: number;
  maintenanceMarginBps: number;
  liquidationFeeBps: number;
  openInterestCap: number;
  fundingBps: number;
  fundingIntervalSlots: number;
  oracleStaleSlots: number;
  backlogLimit: number;
  utilisationClampBps: number;
  liquidationStressLimit: number;
};

export type CollateralPoolState = {
  balance: number;
  reservedMargin: number;
  surplus: number;
  settledCollateral: number;
};

type MarketState = MarketConfig & {
  marketId: number;
  active: boolean;
  openInterest: number;
  queuedLiquidations: number;
  guardFlags: number;
  lastMarkPriceBps: number;
  lastIndexPriceBps: number;
  lastConfidenceBps: number;
  lastOracleSlot: number;
  lastOracleAttestationHash: number;
  scanCursor: number;
  lastPassScanned: number;
  lastPassQueued: number;
  lastPassRecovered: number;
  lastPassLiquidated: number;
};

type PositionState = {
  positionId: number;
  owner: string;
  marketId: number;
  size: number;
  margin: number;
  entryPriceBps: number;
  markPriceBps: number;
  indexPriceBps: number;
  fundingAccrued: number;
  realizedPnl: number;
  status: "open" | "queued" | "liquidated" | "closed";
  activeSlot: number;
  queuedSlot: number;
  lastKeeperReward: number;
  lastOwnerResidual: number;
};

function abs(value: number): number {
  return Math.abs(value);
}

function unrealizedPnl(position: PositionState, markPriceBps: number): number {
  return Math.trunc((position.size * (markPriceBps - position.entryPriceBps)) / 10_000);
}

export class PerpsEngineModel {
  private readonly markets = new Map<number, MarketState>();
  private readonly positions = new Map<number, PositionState>();
  private readonly activePositions = new Map<number, number[]>();
  private nextMarketId = 1;
  private nextPositionId = 1;
  private withdrawalOnly = true;
  private automationBacklogCap = 0;
  private automationBacklog = 0;
  private automationSafeMode = false;
  private collateralPoolBalance = 0;
  private reservedMargin = 0;
  private settledCollateral = 0;

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

  heartbeat(marketId: number, backlog: number, safeMode: boolean): void {
    this.mustMarket(marketId);
    this.assertNonNegative(backlog, "automation backlog");
    this.automationBacklog = backlog;
    this.automationSafeMode = safeMode;
  }

  fundCollateralPool(amount: number): CollateralPoolState {
    this.assertPositive(amount, "collateral funding");
    this.collateralPoolBalance += amount;
    return this.collateralPoolState();
  }

  withdrawCollateralSurplus(amount: number): CollateralPoolState {
    this.assertPositive(amount, "collateral withdrawal");
    if (!this.withdrawalOnly) {
      throw new Error("withdrawal-only mode required");
    }
    if (amount > this.collateralSurplus()) {
      throw new Error("collateral pool settle");
    }
    this.settleCollateral(amount);
    return this.collateralPoolState();
  }

  registerMarket(config: MarketConfig): number {
    this.assertMarketConfig(config);
    const marketId = this.nextMarketId++;
    this.markets.set(marketId, {
      marketId,
      ...config,
      active: true,
      openInterest: 0,
      queuedLiquidations: 0,
      guardFlags: 0,
      lastMarkPriceBps: 0,
      lastIndexPriceBps: 0,
      lastConfidenceBps: 0,
      lastOracleSlot: 0,
      lastOracleAttestationHash: 0,
      scanCursor: 0,
      lastPassScanned: 0,
      lastPassQueued: 0,
      lastPassRecovered: 0,
      lastPassLiquidated: 0
    });
    this.activePositions.set(marketId, []);
    return marketId;
  }

  publishMarketOracle(marketId: number, publication: MarketOraclePublication): number {
    const market = this.mustMarket(marketId);
    if (publication.markPriceBps <= 0) {
      throw new Error("invalid mark price");
    }
    if (publication.indexPriceBps <= 0) {
      throw new Error("invalid index price");
    }
    if (publication.confidenceBps < 0 || publication.confidenceBps > 2_500) {
      throw new Error("oracle confidence invalid");
    }
    if (publication.statusFlags !== 0) {
      throw new Error("oracle degraded");
    }
    if (publication.attestationHash <= 0) {
      throw new Error("attestation missing");
    }
    if (publication.oracleSlot <= 0 || publication.currentSlot < publication.oracleSlot) {
      throw new Error("oracle slot invalid");
    }
    if (publication.oracleSlot <= market.lastOracleSlot) {
      throw new Error("oracle slot replay");
    }
    if (publication.currentSlot - publication.oracleSlot > market.oracleStaleSlots) {
      throw new Error("oracle stale");
    }
    this.recordOracle(market, publication);
    return publication.oracleSlot;
  }

  openPosition(
    owner: string,
    marketId: number,
    size: number,
    margin: number,
    requestedLeverageBps: number,
    currentSlot: number
  ): number {
    this.assertRiskOn();
    const market = this.mustMarket(marketId);
    const oracle = this.freshMarketOracle(market, currentSlot);
    if (size === 0) {
      throw new Error("invalid size");
    }
    this.assertPositive(margin, "margin");
    if (requestedLeverageBps < 0) {
      throw new Error("invalid leverage");
    }
    const effectiveLeverage = requestedLeverageBps === 0 ? market.maxLeverageBps : requestedLeverageBps;
    if (effectiveLeverage > market.maxLeverageBps) {
      throw new Error("max leverage exceeded");
    }
    const requiredMargin = Math.ceil((abs(size) * 10_000) / effectiveLeverage);
    if (margin < requiredMargin) {
      throw new Error("insufficient initial margin");
    }
    const projectedOpenInterest = market.openInterest + abs(size);
    this.assertMarketAcceptsRisk(market, projectedOpenInterest);

    const positionId = this.nextPositionId++;
    this.collectCollateral(margin);
    this.reserveCollateral(margin);
    const position: PositionState = {
      positionId,
      owner,
      marketId,
      size,
      margin,
      entryPriceBps: oracle.markPriceBps,
      markPriceBps: oracle.markPriceBps,
      indexPriceBps: oracle.indexPriceBps,
      fundingAccrued: 0,
      realizedPnl: 0,
      status: "open",
      activeSlot: -1,
      queuedSlot: 0,
      lastKeeperReward: 0,
      lastOwnerResidual: 0
    };
    this.positions.set(positionId, position);
    this.appendActivePosition(marketId, positionId);
    market.openInterest = projectedOpenInterest;
    return positionId;
  }

  addMargin(owner: string, positionId: number, amount: number): PositionState {
    this.assertRiskOn();
    const position = this.mustManageablePosition(positionId);
    this.assertOwner(position, owner);
    this.assertPositive(amount, "margin");
    this.collectCollateral(amount);
    this.reserveCollateral(amount);
    position.margin += amount;
    return { ...position };
  }

  removeMargin(owner: string, positionId: number, amount: number, currentSlot: number): PositionState {
    this.assertRiskOn();
    const position = this.mustOpenPosition(positionId);
    this.assertOwner(position, owner);
    this.assertPositive(amount, "margin");
    const market = this.mustMarket(position.marketId);
    const oracle = this.freshMarketOracle(market, currentSlot);
    const nextMargin = position.margin - amount;
    if (nextMargin < 0) {
      throw new Error("margin exhausted");
    }
    const nextEquity = nextMargin + unrealizedPnl(position, oracle.markPriceBps);
    const maintenance = Math.ceil((abs(position.size) * market.maintenanceMarginBps) / 10_000);
    if (nextEquity < maintenance) {
      throw new Error("maintenance margin");
    }
    if (this.settleCollateral(amount) !== amount) {
      throw new Error("collateral pool settle");
    }
    this.releaseMarginReserve(amount);
    position.margin = nextMargin;
    position.markPriceBps = oracle.markPriceBps;
    position.indexPriceBps = oracle.indexPriceBps;
    return { ...position };
  }

  syncFunding(marketId: number, currentSlot: number): number {
    const market = this.mustMarket(marketId);
    const oracle = this.freshMarketOracle(market, currentSlot);
    return Math.trunc((market.fundingBps * (oracle.markPriceBps - oracle.indexPriceBps)) / 10_000);
  }

  runLiquidationPass(
    marketId: number,
    maxPositions: number,
    currentSlot: number,
    keeper = "keeper"
  ): { scanned: number; queued: number; recovered: number; liquidated: number } {
    const market = this.mustMarket(marketId);
    const oracle = this.freshMarketOracle(market, currentSlot);
    if (maxPositions <= 0 || maxPositions > 4) {
      throw new Error("scan size exceeds cap");
    }
    return this.scanLiquidations(market, maxPositions, currentSlot, oracle, keeper);
  }

  runNativeLifecyclePass(
    marketId: number,
    maxPositions: number,
    currentSlot: number
  ): { scanned: number; queued: number; recovered: number; liquidated: number } {
    const market = this.mustMarket(marketId);
    if (maxPositions <= 0 || maxPositions > 4) {
      throw new Error("native scan size exceeds cap");
    }
    if (this.automationSafeMode) {
      return { scanned: 0, queued: 0, recovered: 0, liquidated: 0 };
    }
    let oracle: Pick<MarketOraclePublication, "markPriceBps" | "indexPriceBps">;
    try {
      oracle = this.freshMarketOracle(market, currentSlot);
    } catch {
      market.lastPassScanned = 0;
      market.lastPassQueued = 0;
      market.lastPassRecovered = 0;
      market.lastPassLiquidated = 0;
      return { scanned: 0, queued: 0, recovered: 0, liquidated: 0 };
    }
    return this.scanLiquidations(market, maxPositions, currentSlot, oracle, undefined);
  }

  closePosition(owner: string, positionId: number, currentSlot: number): { payout: number; collateralPool: CollateralPoolState } {
    this.assertRiskOn();
    const position = this.mustManageablePosition(positionId);
    this.assertOwner(position, owner);
    const market = this.mustMarket(position.marketId);
    const oracle = this.freshMarketOracle(market, currentSlot);
    const equity = Math.max(0, position.margin + unrealizedPnl(position, oracle.markPriceBps));
    if (position.status === "queued") {
      const maintenance = Math.ceil((abs(position.size) * market.maintenanceMarginBps) / 10_000);
      if (position.margin + unrealizedPnl(position, oracle.markPriceBps) < maintenance) {
        throw new Error("position queued");
      }
      market.queuedLiquidations = Math.max(0, market.queuedLiquidations - 1);
      position.queuedSlot = 0;
    }

    const margin = position.margin;
    const payoutBudget = this.positionPayoutBudget(margin);
    const payout = this.settleCollateral(Math.min(equity, payoutBudget));
    this.releaseMarginReserve(margin);
    market.openInterest = Math.max(0, market.openInterest - abs(position.size));
    position.realizedPnl += payout - margin;
    position.size = 0;
    position.margin = 0;
    position.status = "closed";
    position.queuedSlot = 0;
    position.markPriceBps = oracle.markPriceBps;
    position.indexPriceBps = oracle.indexPriceBps;
    this.removeActivePosition(position.marketId, position.positionId);
    return { payout, collateralPool: this.collateralPoolState() };
  }

  collateralPoolState(): CollateralPoolState {
    return {
      balance: this.collateralPoolBalance,
      reservedMargin: this.reservedMargin,
      surplus: this.collateralSurplus(),
      settledCollateral: this.settledCollateral
    };
  }

  position(positionId: number): PositionState {
    return { ...this.mustPosition(positionId) };
  }

  market(marketId: number): MarketState {
    return { ...this.mustMarket(marketId) };
  }

  assertInvariant(): void {
    if (this.collateralPoolBalance < 0 || this.reservedMargin < 0) {
      throw new Error("collateral accounting negative");
    }
    if (this.collateralPoolBalance < this.reservedMargin) {
      throw new Error("collateral reserve unbacked");
    }
    const positionReserve = [...this.positions.values()]
      .filter((position) => position.status === "open" || position.status === "queued")
      .reduce((total, position) => total + position.margin, 0);
    if (positionReserve !== this.reservedMargin) {
      throw new Error("reserved margin mismatch");
    }
  }

  static runScenario(): ReturnType<typeof writeTelemetrySnapshot>["payload"] {
    const engine = new PerpsEngineModel();
    engine.syncAutomation(6, false);
    engine.exitWithdrawalOnly();
    engine.fundCollateralPool(20_000);

    const tonMarket = engine.registerMarket({
      asset: "ton#universal",
      maxLeverageBps: 50_000,
      maintenanceMarginBps: 600,
      liquidationFeeBps: 800,
      openInterestCap: 80_000,
      fundingBps: 120,
      fundingIntervalSlots: 4,
      oracleStaleSlots: 4,
      backlogLimit: 6,
      utilisationClampBps: 9_000,
      liquidationStressLimit: 4
    });
    const xorMarket = engine.registerMarket({
      asset: "xor#universal",
      maxLeverageBps: 50_000,
      maintenanceMarginBps: 900,
      liquidationFeeBps: 900,
      openInterestCap: 40_000,
      fundingBps: 80,
      fundingIntervalSlots: 4,
      oracleStaleSlots: 4,
      backlogLimit: 4,
      utilisationClampBps: 8_500,
      liquidationStressLimit: 3
    });
    const publish = (
      marketId: number,
      oracleSlot: number,
      currentSlot: number,
      overrides: Partial<MarketOraclePublication> = {}
    ) => engine.publishMarketOracle(marketId, {
      markPriceBps: 10_000,
      indexPriceBps: 9_900,
      confidenceBps: 120,
      oracleSlot,
      currentSlot,
      statusFlags: 0,
      attestationHash: 100 + oracleSlot,
      ...overrides
    });

    publish(tonMarket, 10, 12);
    const longId = engine.openPosition("alice", tonMarket, 8_000, 1_700, 50_000, 12);
    engine.addMargin("alice", longId, 150);
    publish(tonMarket, 11, 13, { markPriceBps: 11_300, indexPriceBps: 10_000 });
    const fundingDeltaBps = engine.syncFunding(tonMarket, 13);
    publish(tonMarket, 12, 14, { markPriceBps: 10_800, indexPriceBps: 10_100 });
    const closed = engine.closePosition("alice", longId, 14);

    publish(xorMarket, 20, 20, { attestationHash: 220 });
    const stressedId = engine.openPosition("bob", xorMarket, 10_000, 2_000, 50_000, 20);
    engine.heartbeat(xorMarket, 5, false);
    publish(xorMarket, 21, 21, { markPriceBps: 8_490, indexPriceBps: 8_490 });
    const queuePass = engine.runLiquidationPass(xorMarket, 4, 21);
    publish(xorMarket, 22, 22, { markPriceBps: 10_050, indexPriceBps: 10_000 });
    const recoverPass = engine.runLiquidationPass(xorMarket, 4, 22);
    publish(xorMarket, 23, 23, { markPriceBps: 8_490, indexPriceBps: 8_490 });
    const requeuePass = engine.runLiquidationPass(xorMarket, 4, 23);
    const liquidationPass = engine.runLiquidationPass(xorMarket, 4, 24);

    let staleOracleRejected = false;
    try {
      publish(tonMarket, 30, 40);
    } catch {
      staleOracleRejected = true;
    }

    engine.assertInvariant();
    const payload = {
      markets: {
        ton: engine.market(tonMarket),
        xor: engine.market(xorMarket)
      },
      closedPosition: engine.position(longId),
      liquidationPosition: engine.position(stressedId),
      fundingCorrectness: {
        fundingDeltaBps,
        payout: closed.payout
      },
      liquidationShock: {
        queuePass,
        recoverPass,
        requeuePass,
        liquidationPass,
        reward: engine.position(stressedId).lastKeeperReward,
        ownerResidual: engine.position(stressedId).lastOwnerResidual
      },
      backlogStress: {
        backlog: 5,
        globalCap: 6,
        marketLimit: engine.market(xorMarket).backlogLimit
      },
      staleOracleRejected,
      collateralPool: engine.collateralPoolState()
    };

    writeTelemetrySnapshot("perps_engine", payload);
    return payload;
  }

  private scanLiquidations(
    market: MarketState,
    maxPositions: number,
    currentSlot: number,
    oracle: Pick<MarketOraclePublication, "markPriceBps" | "indexPriceBps">,
    keeper: string | undefined
  ): { scanned: number; queued: number; recovered: number; liquidated: number } {
    const slots = this.mustActiveSlots(market.marketId);
    const activeCount = slots.length;
    const scanLimit = Math.min(maxPositions, activeCount);
    const cursor = activeCount === 0 || market.scanCursor >= activeCount ? 0 : market.scanCursor;
    const positionIds: number[] = [];
    for (let index = 0; index < scanLimit; index += 1) {
      positionIds.push(slots[(cursor + index) % activeCount]);
    }

    let queued = 0;
    let recovered = 0;
    let liquidated = 0;
    for (const positionId of positionIds) {
      const position = this.positions.get(positionId);
      if (!position || position.marketId !== market.marketId) {
        continue;
      }
      const action = this.processLiquidationCandidate(position, market, oracle, currentSlot, keeper);
      queued += action === "queued" ? 1 : 0;
      recovered += action === "recovered" ? 1 : 0;
      liquidated += action === "liquidated" ? 1 : 0;
    }

    const nextActiveCount = this.mustActiveSlots(market.marketId).length;
    market.scanCursor = nextActiveCount === 0 || cursor + scanLimit >= nextActiveCount ? 0 : cursor + scanLimit;
    market.lastPassScanned = scanLimit;
    market.lastPassQueued = queued;
    market.lastPassRecovered = recovered;
    market.lastPassLiquidated = liquidated;
    return { scanned: scanLimit, queued, recovered, liquidated };
  }

  private processLiquidationCandidate(
    position: PositionState,
    market: MarketState,
    oracle: Pick<MarketOraclePublication, "markPriceBps" | "indexPriceBps">,
    currentSlot: number,
    keeper: string | undefined
  ): "queued" | "recovered" | "liquidated" | "noop" {
    if (position.status !== "open" && position.status !== "queued") {
      return "noop";
    }
    position.markPriceBps = oracle.markPriceBps;
    position.indexPriceBps = oracle.indexPriceBps;
    const equity = position.margin + unrealizedPnl(position, oracle.markPriceBps);
    const maintenance = Math.ceil((abs(position.size) * market.maintenanceMarginBps) / 10_000);

    if (position.status === "open") {
      if (equity < maintenance) {
        position.status = "queued";
        position.queuedSlot = currentSlot;
        market.queuedLiquidations += 1;
        return "queued";
      }
      return "noop";
    }
    if (equity >= maintenance) {
      position.status = "open";
      position.queuedSlot = 0;
      market.queuedLiquidations = Math.max(0, market.queuedLiquidations - 1);
      return "recovered";
    }
    if (currentSlot <= position.queuedSlot) {
      return "noop";
    }

    const margin = position.margin;
    const payoutBudget = this.positionPayoutBudget(margin);
    const keeperRequest = keeper === undefined ? 0 : Math.floor((margin * market.liquidationFeeBps) / 10_000);
    const keeperReward = this.settleCollateral(Math.min(keeperRequest, margin, payoutBudget));
    const ownerResidualRequest = Math.max(equity - keeperReward, 0);
    const ownerResidual = this.settleCollateral(Math.min(ownerResidualRequest, payoutBudget - keeperReward));
    this.releaseMarginReserve(margin);

    market.openInterest = Math.max(0, market.openInterest - abs(position.size));
    market.queuedLiquidations = Math.max(0, market.queuedLiquidations - 1);
    position.realizedPnl += keeperReward + ownerResidual - margin;
    position.size = 0;
    position.margin = 0;
    position.status = "liquidated";
    position.queuedSlot = 0;
    position.lastKeeperReward = keeperReward;
    position.lastOwnerResidual = ownerResidual;
    this.removeActivePosition(position.marketId, position.positionId);
    return "liquidated";
  }

  private freshMarketOracle(
    market: MarketState,
    currentSlot: number
  ): Pick<MarketOraclePublication, "markPriceBps" | "indexPriceBps"> {
    if (market.lastMarkPriceBps <= 0 || market.lastIndexPriceBps <= 0 || market.lastOracleAttestationHash <= 0) {
      throw new Error("market oracle missing");
    }
    if (currentSlot < market.lastOracleSlot) {
      throw new Error("oracle slot invalid");
    }
    if (currentSlot - market.lastOracleSlot > market.oracleStaleSlots) {
      throw new Error("oracle stale");
    }
    return { markPriceBps: market.lastMarkPriceBps, indexPriceBps: market.lastIndexPriceBps };
  }

  private assertMarketAcceptsRisk(market: MarketState, projectedOpenInterest: number): void {
    if (!market.active) {
      throw new Error("market paused");
    }
    if (this.automationBacklogCap > 0 && this.automationBacklog > this.automationBacklogCap) {
      throw new Error("engine backlog");
    }
    if (market.backlogLimit > 0 && market.queuedLiquidations > market.backlogLimit) {
      throw new Error("market backlog");
    }
    if (market.guardFlags !== 0) {
      throw new Error("market guarded");
    }
    if (projectedOpenInterest > market.openInterestCap) {
      throw new Error("open interest cap");
    }
    const projectedUtilisation = Math.ceil((projectedOpenInterest * 10_000) / market.openInterestCap);
    if (market.utilisationClampBps > 0 && projectedUtilisation > market.utilisationClampBps) {
      throw new Error("utilisation clamp");
    }
    if (market.liquidationStressLimit > 0 && market.queuedLiquidations > market.liquidationStressLimit) {
      throw new Error("liquidation stress");
    }
  }

  private assertRiskOn(): void {
    if (this.withdrawalOnly) {
      throw new Error("withdrawal-only mode");
    }
    if (this.automationSafeMode) {
      throw new Error("engine safe mode");
    }
  }

  private assertMarketConfig(config: MarketConfig): void {
    if (!config.asset) {
      throw new Error("market asset missing");
    }
    if (config.maxLeverageBps <= 0 || config.maintenanceMarginBps <= 0 || config.liquidationFeeBps < 0) {
      throw new Error("market margin parameters invalid");
    }
    if (config.openInterestCap <= 0 || config.fundingIntervalSlots < 0 || config.oracleStaleSlots < 0) {
      throw new Error("market limits invalid");
    }
    if (config.backlogLimit < 0 || config.utilisationClampBps < 0 || config.utilisationClampBps > 10_000) {
      throw new Error("market guard invalid");
    }
    if (config.liquidationStressLimit < 0) {
      throw new Error("market liquidation stress invalid");
    }
  }

  private recordOracle(market: MarketState, publication: MarketOraclePublication): void {
    market.lastMarkPriceBps = publication.markPriceBps;
    market.lastIndexPriceBps = publication.indexPriceBps;
    market.lastConfidenceBps = publication.confidenceBps;
    market.lastOracleSlot = publication.oracleSlot;
    market.lastOracleAttestationHash = publication.attestationHash;
  }

  private collectCollateral(amount: number): void {
    this.assertPositive(amount, "collateral");
    this.collateralPoolBalance += amount;
  }

  private reserveCollateral(amount: number): void {
    const nextReserved = this.reservedMargin + amount;
    if (nextReserved > this.collateralPoolBalance) {
      throw new Error("collateral pool settle");
    }
    this.reservedMargin = nextReserved;
  }

  private releaseMarginReserve(amount: number): void {
    if (amount < 0 || amount > this.reservedMargin) {
      throw new Error("collateral pool settle");
    }
    this.reservedMargin -= amount;
    if (this.collateralPoolBalance < this.reservedMargin) {
      throw new Error("collateral pool settle");
    }
  }

  private settleCollateral(amount: number): number {
    this.assertNonNegative(amount, "collateral settlement");
    const settled = Math.min(amount, this.collateralPoolBalance);
    this.collateralPoolBalance -= settled;
    this.settledCollateral += settled;
    return settled;
  }

  private collateralSurplus(): number {
    if (this.collateralPoolBalance < this.reservedMargin) {
      throw new Error("collateral pool settle");
    }
    return this.collateralPoolBalance - this.reservedMargin;
  }

  private positionPayoutBudget(margin: number): number {
    return margin + this.collateralSurplus();
  }

  private appendActivePosition(marketId: number, positionId: number): void {
    const slots = this.mustActiveSlots(marketId);
    const position = this.mustPosition(positionId);
    position.activeSlot = slots.length;
    slots.push(positionId);
  }

  private removeActivePosition(marketId: number, positionId: number): void {
    const slots = this.mustActiveSlots(marketId);
    const position = this.mustPosition(positionId);
    if (position.activeSlot < 0 || position.activeSlot >= slots.length) {
      position.activeSlot = -1;
      return;
    }
    const slot = position.activeSlot;
    const lastSlot = slots.length - 1;
    if (slot !== lastSlot) {
      const movedPositionId = slots[lastSlot];
      slots[slot] = movedPositionId;
      this.mustPosition(movedPositionId).activeSlot = slot;
    }
    slots.pop();
    position.activeSlot = -1;
    const market = this.mustMarket(marketId);
    if (slots.length === 0 || market.scanCursor >= slots.length) {
      market.scanCursor = 0;
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

  private mustActiveSlots(marketId: number): number[] {
    const slots = this.activePositions.get(marketId);
    if (!slots) {
      throw new Error(`market ${marketId} active slots missing`);
    }
    return slots;
  }

  private mustMarket(marketId: number): MarketState {
    const market = this.markets.get(marketId);
    if (!market) {
      throw new Error(`market ${marketId} missing`);
    }
    return market;
  }

  private mustPosition(positionId: number): PositionState {
    const position = this.positions.get(positionId);
    if (!position) {
      throw new Error(`position ${positionId} missing`);
    }
    return position;
  }

  private mustOpenPosition(positionId: number): PositionState {
    const position = this.mustPosition(positionId);
    if (position.status !== "open") {
      throw new Error(`position ${positionId} not open`);
    }
    return position;
  }

  private mustManageablePosition(positionId: number): PositionState {
    const position = this.mustPosition(positionId);
    if (position.status !== "open" && position.status !== "queued") {
      throw new Error(`position ${positionId} not manageable`);
    }
    return position;
  }
}
