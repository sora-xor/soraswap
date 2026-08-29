import { CoverManagerModel } from "../cover/manager";
import { OptionsFactoryModel } from "../options/factory";
import { PerpsEngineModel } from "../perps/engine";

describe("Product-owned reserves", () => {
  test("perps collateral and options premiums cannot subsidize the cover reserve", () => {
    const perps = new PerpsEngineModel();
    perps.fundCollateralPool(10_000);

    const options = new OptionsFactoryModel({ oracleStaleSlots: 4 });
    options.syncAutomation(4, false);
    options.exitWithdrawalOnly();
    options.syncSeries(1, {
      kind: "shout",
      maxNotional: 10_000,
      premiumBps: 500,
      collateralMultiplierBps: 10_000,
      expirySlot: 20,
      strikeBps: 10_000
    }, 1);
    options.buyShout("alice", 1, 2_000, 2);

    const cover = new CoverManagerModel({ defaultRequiredObservations: 2, oracleStaleSlots: 4 });
    cover.syncAutomation(4, false);
    cover.exitWithdrawalOnly();
    const registerCover = () => cover.registerPolicy("bob", {
      lowerBound: 9_500,
      upperBound: 10_500,
      payoutAmount: 1_000,
      monitoringWindowSlots: 4,
      requiredObservations: 2,
      coveredNotional: 1_500,
      premiumPaid: 50
    }, 1);

    expect(registerCover).toThrow("insufficient reserve");
    expect(perps.collateralPoolState()).toMatchObject({ balance: 10_000, reservedMargin: 0 });
    expect(options.treasuryState()).toMatchObject({ balance: 2_100, reservedCollateral: 2_000 });

    cover.fundReserve(950);
    expect(registerCover()).toBe(1);
    expect(cover.reserveState()).toMatchObject({ balance: 1_000, reservedPayout: 1_000 });
    expect(perps.collateralPoolState().balance).toBe(10_000);
    expect(options.treasuryState().balance).toBe(2_100);
  });
});
