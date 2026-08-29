import { CoverManagerModel } from "../cover/manager";

describe("Cover simulations", () => {
  test("scenario covers typed Parisian observations and fully backed claim routing", () => {
    const payload = CoverManagerModel.runScenario() as any;

    expect(payload.resetState.status).toBe("active");
    expect(payload.resetState.breachElapsedSlots).toBe(0);
    expect(payload.claimableState.status).toBe("claimable");
    expect(payload.claimRouting.payout).toBeGreaterThan(0);
    expect(payload.finalPolicy.status).toBe("claimed");
    expect(payload.reserve.reservedPayout).toBe(0);
    expect(payload.reserve.settledPayouts).toBe(payload.claimRouting.payout);
  });

  test("safe mode blocks new policies and degraded oracle observations are rejected", () => {
    const cover = new CoverManagerModel({ defaultRequiredObservations: 2, oracleStaleSlots: 4 });
    cover.syncAutomation(5, false);
    cover.exitWithdrawalOnly();
    cover.fundReserve(10_000);
    cover.heartbeat(0, true);
    expect(() => cover.registerPolicy("alice", {
      lowerBound: 9_500,
      upperBound: 10_500,
      payoutAmount: 1_000,
      monitoringWindowSlots: 4,
      requiredObservations: 2,
      coveredNotional: 2_000,
      premiumPaid: 50
    }, 0)).toThrow("cover automation unsafe");

    cover.heartbeat(0, false);
    const policyId = cover.registerPolicy("alice", {
      lowerBound: 9_500,
      upperBound: 10_500,
      payoutAmount: 1_000,
      monitoringWindowSlots: 4,
      requiredObservations: 2,
      coveredNotional: 2_000,
      premiumPaid: 50
    }, 0);
    expect(() => cover.recordObservation(policyId, 11_000, 1, 1, 100, 1)).toThrow("invalid status flags");
  });
});
