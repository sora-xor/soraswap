import { OraclePayload, PerpsEngineModel } from "../perps/engine";
import { RiskVaultModel } from "../shared/riskVault";

describe("Perps simulations", () => {
  test("scenario covers funding, liquidation, and telemetry-ready risk state", () => {
    const payload = PerpsEngineModel.runScenario() as any;

    expect(payload.fundingCorrectness.accrued).toBeGreaterThan(0);
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
    expect(payload.bucket.outstandingNotional).toBe(0);
    expect(payload.crossMarketCascade.riskState.totalOutstandingNotional).toBe(0);
  });

  test("guards openings when automation backlog or oracle quality degrade", () => {
    const vault = new RiskVaultModel();
    const engine = new PerpsEngineModel(vault);
    vault.deposit(1, 15_000);

    const marketId = engine.registerMarket({
      maxLeverageBps: 40_000,
      maintenanceMarginBps: 800,
      liquidationFeeBps: 900,
      openInterestCap: 20_000,
      fundingBps: 100,
      oracleStaleSlots: 3,
      backlogLimit: 1,
      utilisationClampBps: 8_000,
      liquidationStressLimit: 2
    });

    const oracle = (overrides: Partial<OraclePayload> = {}): OraclePayload => ({
      markPriceBps: 10_000,
      indexPriceBps: 9_900,
      confidenceBps: 90,
      oracleSlot: 8,
      currentSlot: 10,
      statusFlags: 0,
      attestationHash: 55,
      ...overrides
    });

    engine.heartbeat(2, false);
    expect(() => engine.openPosition("alice", marketId, 3_000, 900, oracle())).toThrow("engine backlog");

    engine.heartbeat(0, false);
    expect(() =>
      engine.openPosition("alice", marketId, 3_000, 900, oracle({ statusFlags: 1, attestationHash: 56 }))
    ).toThrow("oracle degraded");
  });
});
