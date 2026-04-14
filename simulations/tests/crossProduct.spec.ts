import { runCrossProductStressScenario } from "../system/crossProduct";

describe("Cross-product shared risk stress", () => {
  test("keeps shared vault accounting solvent across perps, options, and cover", () => {
    const payload = runCrossProductStressScenario();

    expect(payload.payouts.perps).toBeGreaterThan(0);
    expect(payload.payouts.options).toBeGreaterThan(0);
    expect(payload.payouts.cover).toBeGreaterThan(0);
    expect(payload.afterShock.totalDeposits).toBeGreaterThanOrEqual(payload.afterShock.totalReservedCollateral);
    expect(payload.afterShock.unsafeBuckets).toHaveLength(0);
    expect(payload.solvency.maxUtilisationBps).toBeLessThan(10_000);
  });
});
