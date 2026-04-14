import { CoverManagerModel } from "../cover/manager";
import { RiskVaultModel } from "../shared/riskVault";

describe("Cover simulations", () => {
  test("scenario covers Parisian breach resets, claim routing, and payout caps", () => {
    const payload = CoverManagerModel.runScenario() as any;

    expect(payload.resetState.status).toBe("active");
    expect(payload.resetState.breachElapsedSlots).toBe(0);
    expect(payload.claimableState.status).toBe("claimable");
    expect(payload.claimRouting.payout).toBeGreaterThan(0);
    expect(payload.claimRouting.payout).toBeLessThanOrEqual(payload.payoutCap.requested);
    expect(payload.finalPolicy.status).toBe("claimed");
  });

  test("safe mode blocks new cover policies", () => {
    const vault = new RiskVaultModel();
    const cover = new CoverManagerModel(vault, 2);
    cover.configureAutomation(5, 0, true);

    expect(() =>
      cover.registerPolicy({
        owner: "alice",
        lowerBound: 9_500,
        upperBound: 10_500,
        payoutAmount: 1_000,
        monitoringWindowSlots: 4,
        coveredNotional: 2_000,
        premiumPaid: 50
      })
    ).toThrow("cover safe mode");
  });
});
