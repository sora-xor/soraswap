import { existsSync, readFileSync } from "fs";
import { join } from "path";

import { CoverManagerModel } from "../cover/manager";
import { OptionsFactoryModel } from "../options/factory";
import { PerpsEngineModel } from "../perps/engine";
import { runDefi2026Scenario } from "../system/defi2026";

function expectLaunchReadyDefi2026Telemetry(snapshot: any) {
  expect(snapshot.launchReady).toBe(true);
  expect(snapshot.intent.owner).toEqual(expect.any(String));
  expect(snapshot.intent.owner.length).toBeGreaterThan(0);
  expect(snapshot.intent.status).toBe("filled");
  expect(snapshot.intent.amountIn).toBeGreaterThan(0);
  expect(snapshot.intent.minOut).toBeGreaterThan(0);
  expect(snapshot.intent.amountOut).toBeGreaterThanOrEqual(snapshot.intent.minOut);
  expect(snapshot.intent.solverFeeBps).toBeGreaterThan(0);
  expect(snapshot.intent.solverFeeBps).toBeLessThanOrEqual(10_000);
  expect(snapshot.intent.deadlineSlot).toBeGreaterThan(0);
  expect(snapshot.intent.solver).toEqual(expect.any(String));
  expect(snapshot.intent.solver.length).toBeGreaterThan(0);

  expect(snapshot.vault.underlying).toBe("n3x");
  expect(snapshot.vault.shares).toBeGreaterThan(0);
  expect(snapshot.vault.assets).toBeGreaterThan(0);
  expect(snapshot.vault.pendingRedeems).toBeGreaterThanOrEqual(0);

  expect(snapshot.operator.service).toBe("solver");
  expect(snapshot.operator.bonded).toBeGreaterThanOrEqual(snapshot.operator.minBond);
  expect(snapshot.operator.healthBps).toBeGreaterThanOrEqual(5_000);
  expect(snapshot.operator.jailed).toBe(false);
  expect(snapshot.operator.feesAccrued).toBeGreaterThanOrEqual(0);

  expect(snapshot.hookOrder.amountIn).toBeGreaterThan(0);
  expect(snapshot.hookOrder.minOut).toBeGreaterThan(0);
  expect(snapshot.hookOrder.amountOut).toBeGreaterThanOrEqual(snapshot.hookOrder.minOut);
  expect(snapshot.hookOrder.feePips).toBeGreaterThan(0);

  expect(snapshot.margin.collateral).toBeGreaterThan(0);
  expect(snapshot.margin.exposure).toBeGreaterThan(0);
  expect(snapshot.margin.healthBps).toBeGreaterThanOrEqual(1_000);
  expect(snapshot.margin.liquidations).toBe(0);

  expect(snapshot.rwa.navPerShare).toBeGreaterThan(0);
  expect(snapshot.rwa.totalShares).toBeGreaterThan(0);
  expect(snapshot.rwa.redemptionQueue).toBeGreaterThanOrEqual(0);
  expect(snapshot.rwa.frozen).toBe(false);
}

describe("Simulation smoke", () => {
  test("runs all current product scenarios and writes first-release telemetry artifacts", () => {
    const perps = PerpsEngineModel.runScenario() as any;
    const options = OptionsFactoryModel.runScenario() as any;
    const cover = CoverManagerModel.runScenario() as any;
    const defi2026 = runDefi2026Scenario() as any;

    expect(perps.collateralPool.settledCollateral).toBeGreaterThan(0);
    expect(options.treasury.settledPayouts).toBeGreaterThan(0);
    expect(cover.reserve.settledPayouts).toBeGreaterThan(0);
    expect(defi2026.launchReady).toBe(true);
    expectLaunchReadyDefi2026Telemetry(defi2026);

    const telemetryDir = join(process.cwd(), "artifacts", "telemetry");
    const latestFiles = [
      "perps_engine_latest.json",
      "options_factory_latest.json",
      "cover_manager_latest.json",
      "defi_2026_primitives_latest.json"
    ];

    latestFiles.forEach((name) => {
      const path = join(telemetryDir, name);
      expect(existsSync(path)).toBe(true);
      const snapshot = JSON.parse(readFileSync(path, "utf8"));
      expect(snapshot.generated_at).toEqual(expect.any(String));
      expect(snapshot.generated_at.length).toBeGreaterThan(0);
      if (name === "defi_2026_primitives_latest.json") {
        expectLaunchReadyDefi2026Telemetry(snapshot);
      }
    });
  });
});
