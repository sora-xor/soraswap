import { MarketOraclePublication, PerpsEngineModel } from "../perps/engine";

describe("Perps simulations", () => {
  test("scenario covers stored oracle state, funding, liquidation, and local collateral accounting", () => {
    const payload = PerpsEngineModel.runScenario() as any;

    expect(payload.fundingCorrectness.fundingDeltaBps).toBeGreaterThan(0);
    expect(payload.fundingCorrectness.payout).toBeGreaterThan(0);
    expect(payload.liquidationShock.queuePass.queued).toBe(1);
    expect(payload.liquidationShock.queuePass.liquidated).toBe(0);
    expect(payload.liquidationShock.recoverPass.recovered).toBe(1);
    expect(payload.liquidationShock.requeuePass.queued).toBe(1);
    expect(payload.liquidationShock.liquidationPass.liquidated).toBe(1);
    expect(payload.liquidationShock.reward).toBeGreaterThan(0);
    expect(payload.liquidationShock.ownerResidual).toBeGreaterThan(0);
    expect(payload.liquidationPosition.status).toBe("liquidated");
    expect(payload.markets.xor.queuedLiquidations).toBe(0);
    expect(payload.staleOracleRejected).toBe(true);
    expect(payload.collateralPool.reservedMargin).toBe(0);
    expect(payload.collateralPool.balance).toBe(payload.collateralPool.surplus);
  });

  test("publishes oracle state separately and guards risk when the automation backlog is unsafe", () => {
    const engine = new PerpsEngineModel();
    engine.syncAutomation(1, false);
    engine.exitWithdrawalOnly();
    engine.fundCollateralPool(15_000);
    const marketId = engine.registerMarket({
      asset: "xor#universal",
      maxLeverageBps: 40_000,
      maintenanceMarginBps: 800,
      liquidationFeeBps: 900,
      openInterestCap: 20_000,
      fundingBps: 100,
      fundingIntervalSlots: 3,
      oracleStaleSlots: 3,
      backlogLimit: 1,
      utilisationClampBps: 8_000,
      liquidationStressLimit: 2
    });
    const publication = (overrides: Partial<MarketOraclePublication> = {}): MarketOraclePublication => ({
      markPriceBps: 10_000,
      indexPriceBps: 9_900,
      confidenceBps: 90,
      oracleSlot: 8,
      currentSlot: 10,
      statusFlags: 0,
      attestationHash: 55,
      ...overrides
    });

    engine.publishMarketOracle(marketId, publication());
    engine.heartbeat(marketId, 2, false);
    expect(() => engine.openPosition("alice", marketId, 3_000, 900, 40_000, 10)).toThrow("engine backlog");

    engine.heartbeat(marketId, 0, false);
    expect(() => engine.publishMarketOracle(marketId, publication({
      oracleSlot: 9,
      currentSlot: 10,
      statusFlags: 1,
      attestationHash: 56
    }))).toThrow("oracle degraded");
    expect(engine.openPosition("alice", marketId, 3_000, 900, 40_000, 10)).toBe(1);
  });
});
