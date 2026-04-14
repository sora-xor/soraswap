import { OptionsStackModel } from "../options/stack";
import { RiskVaultModel } from "../shared/riskVault";

describe("Options simulations", () => {
  test("scenario covers shout locking, outperformance settlement, and collateral conservation", () => {
    const payload = OptionsStackModel.runScenario() as any;

    expect(payload.shoutPayoffLocking.shoutFloorBps).toBeGreaterThan(0);
    expect(payload.shoutPayoffLocking.payout).toBeGreaterThan(0);
    expect(payload.outperformanceSettlement.settledPayout).toBeGreaterThan(0);
    expect(payload.outperformanceSettlement.exercisedPayout).toBeGreaterThan(0);
    expect(payload.staleOracleRejected).toBe(true);
    expect(payload.collateralConservation.bucket.outstandingNotional).toBe(0);
  });

  test("utilisation guard pauses new risk when the series is too full", () => {
    const vault = new RiskVaultModel();
    const options = new OptionsStackModel(vault);
    vault.deposit(2, 20_000);
    options.configureAutomation(5, 0, false);

    const templateId = options.registerTemplate("shout", 10_000, 10_000, 400);
    const seriesId = options.createSeries(templateId, 30, 10_000, 400);

    options.buyShout("alice", seriesId, 7_000, 280, 4_000);
    expect(() => options.buyShout("bob", seriesId, 1_000, 40, 1_000)).toThrow("premium below utilisation guard");
    expect(() => options.buyShout("carol", seriesId, 3_000, 160, 1_000)).toThrow("options utilisation pause");
  });
});
