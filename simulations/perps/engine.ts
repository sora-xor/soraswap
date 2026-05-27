import { BucketSnapshot, RiskVaultModel } from "../shared/riskVault";
import { writeTelemetrySnapshot } from "../shared/telemetry";

export type OraclePayload = {
  markPriceBps: number;
  indexPriceBps: number;
  confidenceBps: number;
  oracleSlot: number;
  currentSlot: number;
  statusFlags: number;
  attestationHash: number;
};

export type MarketConfig = {
  maxLeverageBps: number;
  maintenanceMarginBps: number;
  liquidationFeeBps: number;
  openInterestCap: number;
  fundingBps: number;
  oracleStaleSlots: number;
  backlogLimit: number;
  utilisationClampBps: number;
  liquidationStressLimit: number;
};

type MarketState = MarketConfig & {
  marketId: number;
  openInterest: number;
  queuedLiquidations: number;
  guardFlags: number;
  lastMarkPriceBps: number;
  lastIndexPriceBps: number;
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
  return Math.floor((position.size * (markPriceBps - position.entryPriceBps)) / 10_000);
}

export class PerpsEngineModel {
  private readonly markets = new Map<number, MarketState>();
  private readonly positions = new Map<number, PositionState>();
  private readonly activePositions = new Map<number, number[]>();
  private nextMarketId = 1;
  private nextPositionId = 1;
  private automationBacklog = 0;
  private automationSafeMode = false;

  constructor(private readonly vault: RiskVaultModel) {}

  registerMarket(config: MarketConfig): number {
    const marketId = this.nextMarketId++;
    this.markets.set(marketId, {
      marketId,
      ...config,
      openInterest: 0,
      queuedLiquidations: 0,
      guardFlags: 0,
      lastMarkPriceBps: 0,
      lastIndexPriceBps: 0,
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

  heartbeat(backlog: number, safeMode: boolean): void {
    this.automationBacklog = backlog;
    this.automationSafeMode = safeMode;
    this.vault.reportAutomation(1, backlog, safeMode);
  }

  openPosition(owner: string, marketId: number, size: number, margin: number, oracle: OraclePayload): number {
    const market = this.mustMarket(marketId);
    this.assertOracle(market, oracle);
    this.assertRiskAllowed(market, market.openInterest + abs(size));

    const leverage = Math.ceil((abs(size) * 10_000) / margin);
    if (leverage > market.maxLeverageBps) {
      throw new Error("max leverage exceeded");
    }

    this.vault.deposit(1, margin);
    const positionId = this.nextPositionId++;
    this.vault.lockLiability(1, positionId, {
      notional: abs(size),
      collateral: margin,
      backlog: this.automationBacklog
    });

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
      activeSlot: 0,
      queuedSlot: 0,
      lastKeeperReward: 0,
      lastOwnerResidual: 0
    };
    this.positions.set(positionId, position);
    this.appendActivePosition(marketId, positionId);
    market.openInterest += abs(size);
    this.recordOracle(market, oracle);
    return positionId;
  }

  addMargin(positionId: number, amount: number): PositionState {
    const position = this.mustManageablePosition(positionId);
    this.vault.deposit(1, amount);
    position.margin += amount;
    this.vault.lockLiability(1, positionId, {
      notional: abs(position.size),
      collateral: position.margin,
      backlog: this.automationBacklog
    });
    return { ...position };
  }

  removeMargin(positionId: number, amount: number, oracle: OraclePayload): PositionState {
    const position = this.mustOpenPosition(positionId);
    const market = this.mustMarket(position.marketId);
    this.assertOracle(market, oracle);
    const nextMargin = position.margin - amount;
    if (nextMargin <= 0) {
      throw new Error("margin exhausted");
    }
    const nextEquity = nextMargin + unrealizedPnl(position, oracle.markPriceBps);
    const maintenance = Math.ceil((abs(position.size) * market.maintenanceMarginBps) / 10_000);
    if (nextEquity < maintenance) {
      throw new Error("maintenance margin");
    }

    position.margin = nextMargin;
    position.markPriceBps = oracle.markPriceBps;
    position.indexPriceBps = oracle.indexPriceBps;
    this.vault.lockLiability(1, positionId, {
      notional: abs(position.size),
      collateral: nextMargin,
      backlog: this.automationBacklog
    });
    this.vault.withdraw(1, amount);
    this.recordOracle(market, oracle);
    return { ...position };
  }

  syncFunding(marketId: number, oracle: OraclePayload): number {
    const market = this.mustMarket(marketId);
    this.assertOracle(market, oracle);
    this.recordOracle(market, oracle);
    return Math.floor((market.fundingBps * (oracle.markPriceBps - oracle.indexPriceBps)) / 10_000);
  }

  applyFunding(positionId: number, oracle: OraclePayload): PositionState {
    const position = this.mustOpenPosition(positionId);
    const market = this.mustMarket(position.marketId);
    this.assertOracle(market, oracle);
    const fundingPayment = Math.floor(
      (position.size * (oracle.markPriceBps - oracle.indexPriceBps) * market.fundingBps) / 10_000 / 10_000
    );
    position.margin -= fundingPayment;
    position.fundingAccrued += fundingPayment;
    position.markPriceBps = oracle.markPriceBps;
    position.indexPriceBps = oracle.indexPriceBps;
    if (position.margin < 0) {
      position.margin = 0;
    }
    this.vault.lockLiability(1, positionId, {
      notional: abs(position.size),
      collateral: position.margin,
      backlog: this.automationBacklog
    });
    this.recordOracle(market, oracle);
    return { ...position };
  }

  runLiquidationPass(
    marketId: number,
    maxPositions: number,
    oracle: OraclePayload,
    keeper = "keeper"
  ): { scanned: number; queued: number; recovered: number; liquidated: number } {
    const market = this.mustMarket(marketId);
    this.assertOracle(market, oracle);
    if (maxPositions <= 0 || maxPositions > 32) {
      throw new Error("scan size exceeds cap");
    }

    const slots = this.mustActiveSlots(marketId);
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
      if (!position || position.marketId !== marketId) {
        continue;
      }
      const action = this.processLiquidationCandidate(position, market, oracle, keeper);
      if (action === "queued") {
        queued += 1;
      }
      if (action === "recovered") {
        recovered += 1;
      }
      if (action === "liquidated") {
        liquidated += 1;
      }
    }

    const nextActiveCount = this.mustActiveSlots(marketId).length;
    market.scanCursor = nextActiveCount === 0 || cursor + scanLimit >= nextActiveCount ? 0 : cursor + scanLimit;
    market.lastPassScanned = scanLimit;
    market.lastPassQueued = queued;
    market.lastPassRecovered = recovered;
    market.lastPassLiquidated = liquidated;
    this.recordOracle(market, oracle);

    return { scanned: scanLimit, queued, recovered, liquidated };
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
    if (
      market.lastMarkPriceBps <= 0 ||
      market.lastIndexPriceBps <= 0 ||
      market.lastOracleSlot <= 0 ||
      currentSlot < market.lastOracleSlot ||
      currentSlot - market.lastOracleSlot > market.oracleStaleSlots
    ) {
      market.lastPassScanned = 0;
      market.lastPassQueued = 0;
      market.lastPassRecovered = 0;
      market.lastPassLiquidated = 0;
      return { scanned: 0, queued: 0, recovered: 0, liquidated: 0 };
    }

    const oracle: OraclePayload = {
      markPriceBps: market.lastMarkPriceBps,
      indexPriceBps: market.lastIndexPriceBps,
      confidenceBps: 0,
      oracleSlot: market.lastOracleSlot,
      currentSlot,
      statusFlags: 0,
      attestationHash: market.lastOracleAttestationHash
    };

    const slots = this.mustActiveSlots(marketId);
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
      if (!position || position.marketId !== marketId) {
        continue;
      }
      const action = this.processNativeLiquidationCandidate(position, market, oracle);
      if (action === "queued") {
        queued += 1;
      }
      if (action === "recovered") {
        recovered += 1;
      }
      if (action === "liquidated") {
        liquidated += 1;
      }
    }

    const nextActiveCount = this.mustActiveSlots(marketId).length;
    market.scanCursor = nextActiveCount === 0 || cursor + scanLimit >= nextActiveCount ? 0 : cursor + scanLimit;
    market.lastPassScanned = scanLimit;
    market.lastPassQueued = queued;
    market.lastPassRecovered = recovered;
    market.lastPassLiquidated = liquidated;

    return { scanned: scanLimit, queued, recovered, liquidated };
  }

  closePosition(positionId: number, oracle: OraclePayload): { payout: number; bucket: BucketSnapshot } {
    const position = this.mustManageablePosition(positionId);
    const market = this.mustMarket(position.marketId);
    this.assertOracle(market, oracle);

    const equity = Math.max(0, position.margin + unrealizedPnl(position, oracle.markPriceBps));
    if (position.status === "queued") {
      const maintenance = Math.ceil((abs(position.size) * market.maintenanceMarginBps) / 10_000);
      if (position.margin + unrealizedPnl(position, oracle.markPriceBps) < maintenance) {
        throw new Error("position queued");
      }
      market.queuedLiquidations = Math.max(0, market.queuedLiquidations - 1);
      position.queuedSlot = 0;
    }

    const payout = this.vault.settlePayout(1, positionId, equity);
    this.vault.releaseLiability(1, positionId, this.automationBacklog);

    market.openInterest -= abs(position.size);
    position.realizedPnl += payout - position.margin;
    position.size = 0;
    position.margin = 0;
    position.status = "closed";
    position.queuedSlot = 0;
    position.markPriceBps = oracle.markPriceBps;
    position.indexPriceBps = oracle.indexPriceBps;
    this.removeActivePosition(position.marketId, position.positionId);
    this.recordOracle(market, oracle);
    return { payout, bucket: this.vault.bucketState(1) };
  }

  position(positionId: number): PositionState {
    return { ...this.mustPosition(positionId) };
  }

  market(marketId: number): MarketState {
    return { ...this.mustMarket(marketId) };
  }

  static runScenario(): ReturnType<typeof writeTelemetrySnapshot>["payload"] {
    const vault = new RiskVaultModel();
    const engine = new PerpsEngineModel(vault);
    vault.deposit(1, 20_000);
    vault.configureAutomation(1, { backlogCap: 6, cadenceSlots: 4, safeMode: false });

    const tonMarket = engine.registerMarket({
      maxLeverageBps: 50_000,
      maintenanceMarginBps: 600,
      liquidationFeeBps: 800,
      openInterestCap: 80_000,
      fundingBps: 120,
      oracleStaleSlots: 4,
      backlogLimit: 6,
      utilisationClampBps: 9_000,
      liquidationStressLimit: 4
    });
    const xorMarket = engine.registerMarket({
      maxLeverageBps: 50_000,
      maintenanceMarginBps: 900,
      liquidationFeeBps: 900,
      openInterestCap: 40_000,
      fundingBps: 80,
      oracleStaleSlots: 4,
      backlogLimit: 4,
      utilisationClampBps: 8_500,
      liquidationStressLimit: 3
    });

    const oracle = (overrides: Partial<OraclePayload> = {}): OraclePayload => ({
      markPriceBps: 10_000,
      indexPriceBps: 9_900,
      confidenceBps: 120,
      oracleSlot: 10,
      currentSlot: 12,
      statusFlags: 0,
      attestationHash: 101,
      ...overrides
    });

    const longId = engine.openPosition("alice", tonMarket, 8_000, 1_700, oracle());
    engine.addMargin(longId, 150);
    engine.applyFunding(longId, oracle({ markPriceBps: 11_300, indexPriceBps: 10_000 }));
    const closed = engine.closePosition(longId, oracle({ markPriceBps: 10_800, indexPriceBps: 10_100 }));

    const stressedId = engine.openPosition("bob", xorMarket, 10_000, 2_000, oracle({ attestationHash: 202 }));
    engine.heartbeat(5, false);
    const queuePass = engine.runLiquidationPass(
      xorMarket,
      4,
      oracle({ markPriceBps: 8_490, indexPriceBps: 8_490, oracleSlot: 20, currentSlot: 20, attestationHash: 303 })
    );
    const recoverPass = engine.runLiquidationPass(
      xorMarket,
      4,
      oracle({ markPriceBps: 10_050, indexPriceBps: 10_000, oracleSlot: 21, currentSlot: 21, attestationHash: 304 })
    );
    const requeuePass = engine.runLiquidationPass(
      xorMarket,
      4,
      oracle({ markPriceBps: 8_490, indexPriceBps: 8_490, oracleSlot: 22, currentSlot: 22, attestationHash: 305 })
    );
    const liquidationPass = engine.runLiquidationPass(
      xorMarket,
      4,
      oracle({ markPriceBps: 8_490, indexPriceBps: 8_490, oracleSlot: 23, currentSlot: 23, attestationHash: 306 })
    );

    let staleOracleRejected = false;
    try {
      engine.openPosition("carol", tonMarket, 2_000, 500, oracle({ oracleSlot: 1, currentSlot: 10, attestationHash: 404 }));
    } catch {
      staleOracleRejected = true;
    }

    vault.assertInvariant();

    const payload = {
      markets: {
        ton: engine.market(tonMarket),
        xor: engine.market(xorMarket)
      },
      closedPosition: engine.position(longId),
      liquidationPosition: engine.position(stressedId),
      fundingCorrectness: {
        accrued: engine.position(longId).fundingAccrued,
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
        limit: engine.market(xorMarket).backlogLimit
      },
      staleOracleRejected,
      crossMarketCascade: {
        totalOpenInterest: engine.market(tonMarket).openInterest + engine.market(xorMarket).openInterest,
        riskState: vault.riskState()
      },
      bucket: vault.bucketState(1)
    };

    writeTelemetrySnapshot("perps_shared_risk", payload);
    return payload;
  }

  private processLiquidationCandidate(
    position: PositionState,
    market: MarketState,
    oracle: OraclePayload,
    keeper: string
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
        position.queuedSlot = oracle.currentSlot;
        market.queuedLiquidations += 1;
        this.recordOracle(market, oracle);
        return "queued";
      }
      return "noop";
    }

    if (equity >= maintenance) {
      position.status = "open";
      position.queuedSlot = 0;
      market.queuedLiquidations = Math.max(0, market.queuedLiquidations - 1);
      this.recordOracle(market, oracle);
      return "recovered";
    }

    if (oracle.currentSlot > position.queuedSlot) {
      const rewardRequest = Math.floor((position.margin * market.liquidationFeeBps) / 10_000);
      const reward = this.vault.settlePayout(1, position.positionId, rewardRequest);
      const ownerResidual = this.vault.settlePayout(1, position.positionId, Math.max(equity - reward, 0));
      this.vault.releaseLiability(1, position.positionId, this.automationBacklog);

      market.openInterest -= abs(position.size);
      market.queuedLiquidations = Math.max(0, market.queuedLiquidations - 1);
      position.realizedPnl += reward + ownerResidual - position.margin;
      position.size = 0;
      position.margin = 0;
      position.status = "liquidated";
      position.queuedSlot = 0;
      position.lastKeeperReward = reward;
      position.lastOwnerResidual = ownerResidual;
      position.markPriceBps = oracle.markPriceBps;
      position.indexPriceBps = oracle.indexPriceBps;
      this.removeActivePosition(position.marketId, position.positionId);
      this.recordOracle(market, oracle);
      void keeper;
      return "liquidated";
    }

    return "noop";
  }

  private processNativeLiquidationCandidate(
    position: PositionState,
    market: MarketState,
    oracle: OraclePayload
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
        position.queuedSlot = oracle.currentSlot;
        market.queuedLiquidations += 1;
        this.recordOracle(market, oracle);
        return "queued";
      }
      return "noop";
    }

    if (equity >= maintenance) {
      position.status = "open";
      position.queuedSlot = 0;
      market.queuedLiquidations = Math.max(0, market.queuedLiquidations - 1);
      this.recordOracle(market, oracle);
      return "recovered";
    }

    if (oracle.currentSlot > position.queuedSlot) {
      const ownerResidual = this.vault.settlePayout(1, position.positionId, Math.max(equity, 0));
      this.vault.releaseLiability(1, position.positionId, this.automationBacklog);

      market.openInterest -= abs(position.size);
      market.queuedLiquidations = Math.max(0, market.queuedLiquidations - 1);
      position.realizedPnl += ownerResidual - position.margin;
      position.size = 0;
      position.margin = 0;
      position.status = "liquidated";
      position.queuedSlot = 0;
      position.lastKeeperReward = 0;
      position.lastOwnerResidual = ownerResidual;
      position.markPriceBps = oracle.markPriceBps;
      position.indexPriceBps = oracle.indexPriceBps;
      this.removeActivePosition(position.marketId, position.positionId);
      this.recordOracle(market, oracle);
      return "liquidated";
    }

    return "noop";
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
    if (slots.length === 0) {
      market.scanCursor = 0;
    } else if (market.scanCursor >= slots.length) {
      market.scanCursor = 0;
    } else if (market.scanCursor === lastSlot) {
      market.scanCursor = slot;
    }
  }

  private assertOracle(market: MarketState, oracle: OraclePayload): void {
    if (oracle.statusFlags !== 0) {
      throw new Error("oracle degraded");
    }
    if (oracle.currentSlot < oracle.oracleSlot) {
      throw new Error("oracle slot invalid");
    }
    if (oracle.currentSlot - oracle.oracleSlot > market.oracleStaleSlots) {
      throw new Error("oracle stale");
    }
    if (oracle.attestationHash <= 0) {
      throw new Error("attestation missing");
    }
  }

  private assertRiskAllowed(market: MarketState, projectedOpenInterest: number): void {
    if (this.automationSafeMode) {
      throw new Error("engine safe mode");
    }
    if (this.automationBacklog > market.backlogLimit) {
      throw new Error("engine backlog");
    }
    if (market.guardFlags !== 0) {
      throw new Error("market guarded");
    }
    if (projectedOpenInterest > market.openInterestCap) {
      throw new Error("open interest cap");
    }
    const projectedUtil = Math.ceil((projectedOpenInterest * 10_000) / market.openInterestCap);
    if (projectedUtil > market.utilisationClampBps) {
      throw new Error("utilisation clamp");
    }
    if (market.queuedLiquidations > market.liquidationStressLimit) {
      throw new Error("liquidation stress");
    }
  }

  private recordOracle(market: MarketState, oracle: OraclePayload): void {
    market.lastMarkPriceBps = oracle.markPriceBps;
    market.lastIndexPriceBps = oracle.indexPriceBps;
    market.lastOracleSlot = oracle.oracleSlot;
    market.lastOracleAttestationHash = oracle.attestationHash;
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
