import { OptionsFactoryModel } from "../options/factory";

describe("Options factory simulations", () => {
  test("scenario covers typed shout marks, outperformance settlement, and local collateral conservation", () => {
    const payload = OptionsFactoryModel.runScenario() as any;

    expect(payload.shoutPayoff.shoutFloorBps).toBeGreaterThan(0);
    expect(payload.shoutPayoff.payout).toBeGreaterThan(0);
    expect(payload.outperformanceSettlement.baseReturnBps).toBeGreaterThan(
      payload.outperformanceSettlement.quoteReturnBps
    );
    expect(payload.outperformanceSettlement.payout).toBeGreaterThan(0);
    expect(payload.staleOracleRejected).toBe(true);
    expect(payload.treasury.reservedCollateral).toBe(0);
    expect(payload.treasury.balance).toBe(payload.treasury.surplus);
  });

  test("computes the premium and collateral in the factory and pauses a saturated series", () => {
    const options = new OptionsFactoryModel({ oracleStaleSlots: 4 });
    options.syncAutomation(5, false);
    options.exitWithdrawalOnly();
    options.syncSeries(1, {
      kind: "shout",
      maxNotional: 10_000,
      premiumBps: 400,
      collateralMultiplierBps: 10_000,
      expirySlot: 30,
      strikeBps: 10_000
    }, 10);

    options.buyShout("alice", 1, 8_000, 20);
    const bumpedPosition = options.buyShout("bob", 1, 1_000, 20);
    expect(options.positionState(bumpedPosition)).toMatchObject({
      premiumPaid: 46,
      collateralLocked: 1_000
    });
    expect(() => options.buyShout("carol", 1, 1_000, 20)).toThrow("series paused by guard");
  });
});
