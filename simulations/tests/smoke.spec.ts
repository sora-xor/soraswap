import { existsSync, readFileSync } from "fs";
import { join } from "path";

import { CoverManagerModel } from "../cover/manager";
import { OptionsStackModel } from "../options/stack";
import { PerpsEngineModel } from "../perps/engine";
import { runDefi2026Scenario } from "../system/defi2026";
import { runCrossProductStressScenario } from "../system/crossProduct";

describe("Simulation smoke", () => {
  test("runs all scenario entrypoints and writes telemetry artifacts", () => {
    const perps = PerpsEngineModel.runScenario() as any;
    const options = OptionsStackModel.runScenario() as any;
    const cover = CoverManagerModel.runScenario() as any;
    const cross = runCrossProductStressScenario() as any;
    const defi2026 = runDefi2026Scenario() as any;

    expect(perps.bucket.settledPayouts).toBeGreaterThan(0);
    expect(options.collateralConservation.bucket.settledPayouts).toBeGreaterThan(0);
    expect(cover.claimRouting.payout).toBeGreaterThan(0);
    expect(cross.solvency.totalSettledPayouts).toBeGreaterThan(0);
    expect(defi2026.launchReady).toBe(true);

    const telemetryDir = join(process.cwd(), "artifacts", "telemetry");
    const latestFiles = [
      "perps_shared_risk_latest.json",
      "options_shared_risk_latest.json",
      "cover_shared_risk_latest.json",
      "cross_product_shared_risk_latest.json",
      "defi_2026_primitives_latest.json"
    ];

    latestFiles.forEach((name) => {
      const path = join(telemetryDir, name);
      expect(existsSync(path)).toBe(true);
      expect(() => JSON.parse(readFileSync(path, "utf8"))).not.toThrow();
    });
  });
});
