const { test, expect } = require("@playwright/test");
const { spawn } = require("child_process");
const readline = require("readline");
const path = require("path");

let fixtureServer;
let fixtureServerUrl;

async function startFixtureServer() {
  const serverPath = path.join(__dirname, "run_trader_fixture_server.py");
  const child = spawn("python3", [serverPath], {
    cwd: path.join(__dirname, ".."),
    stdio: ["ignore", "pipe", "pipe"],
  });

  child.stderr.on("data", (chunk) => {
    process.stderr.write(chunk);
  });

  const rl = readline.createInterface({ input: child.stdout });
  const metadata = await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      reject(new Error("timed out waiting for fixture trader server"));
    }, 15000);

    rl.once("line", (line) => {
      clearTimeout(timeout);
      try {
        resolve(JSON.parse(line));
      } catch (error) {
        reject(error);
      }
    });

    child.once("exit", (code) => {
      clearTimeout(timeout);
      reject(new Error(`fixture trader server exited early with code ${code}`));
    });
  });

  return { child, metadata };
}

async function stopFixtureServer(child) {
  if (!child || child.killed) {
    return;
  }
  await new Promise((resolve) => {
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
    }, 5000);
    child.once("exit", () => {
      clearTimeout(timer);
      resolve();
    });
    child.kill("SIGTERM");
  });
}

test.beforeAll(async () => {
  const started = await startFixtureServer();
  fixtureServer = started.child;
  fixtureServerUrl = started.metadata.url;
});

test.afterAll(async () => {
  await stopFixtureServer(fixtureServer);
});

test("renders the trader cockpit and submits a routed swap through the real Python server", async ({ page }) => {
  await page.goto(fixtureServerUrl);

  await expect(page.locator("#status-banner")).toContainText("Loaded 3 executed fills");
  await expect(page.locator("#live-status")).toHaveText("Live");
  await expect(page.locator("#router-contract-label")).toContainText("dlmm.dlmm_router");
  await expect(page.locator("#router-call-access")).toContainText("Enabled");
  await expect(page.locator("#pair-symbol")).toContainText("XOR / USDT");
  await expect(page.locator("#history-head")).toHaveText("4");
  await expect(page.locator("#history-count")).toHaveText("3");
  await expect(page.locator("#recent-fills")).toContainText("Bought");
  await expect(page.locator("#recent-fills")).toContainText("Sold");
  await expect(page.locator("#module-radar")).toContainText("n3x");
  await expect(page.locator("#module-radar")).toContainText("Perps");
  await expect(page.locator("#module-grid")).toContainText("Launchpad");
  await expect(page.locator("#module-grid")).toContainText("Options");
  await expect(page.locator("#module-grid")).toContainText("Cover");
  await expect(page.locator("#journal-body")).toContainText("Buy Quote");
  await expect(page.locator("#journal-body")).toContainText("Sell Quote");
  await expect(page.locator("#activity-body")).toContainText("Minted n3x");
  await expect(page.locator("#activity-body")).toContainText("Opened perp");
  await expect(page.locator("#activity-body")).toContainText("Bought quote");
  await expect(page.locator("#focus-title")).toHaveText("Swaps");
  await expect(page.locator("#metric-avg-entry")).not.toHaveText("-");
  await expect(page.locator("#metric-total-pnl")).not.toHaveText("-");
  await expect(page.locator("#chart-empty")).toBeHidden();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "route_swap"');

  await page.locator("#module-grid").getByRole("button", { name: /Perps/i }).click();
  await expect(page.locator("#focus-title")).toHaveText("Perps");
  await expect(page.locator("#focus-feed")).toContainText("Opened perp");
  await expect(page.locator("#trade-title")).toHaveText("Perps Rails");
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "open_position"');
  await expect(page.locator("#activity-body")).toContainText("Opened perp");
  await expect(page.locator("#activity-body")).not.toContainText("Minted n3x");

  await page.locator("#activity-filter-bar").getByRole("button", { name: /All products/i }).click();
  await expect(page.locator("#activity-body")).toContainText("Minted n3x");
  await expect(page.locator("#activity-body")).toContainText("Opened perp");

  await page.locator("#module-grid").getByRole("button", { name: /Swaps/i }).click();
  await expect(page.locator("#trade-title")).toHaveText("Route Swap");
  await page.getByLabel("Spend Base Amount").fill("90");
  await page.getByLabel("Minimum Quote Out").fill("80");
  await page.locator("#trade-submit").click();

  await expect(page.locator("#trade-result")).toContainText("committed");
  await expect(page.locator("#status-banner")).toContainText("Loaded 4 executed fills");
  await expect(page.locator("#history-head")).toHaveText("5");
  await expect(page.locator("#history-count")).toHaveText("4");
  await expect(page.locator("#recent-fills")).toContainText("Bought 83 USDT");
  await expect(page.locator("#journal-body")).toContainText("83 USDT");
  await expect(page.locator("#activity-body")).toContainText("9 -> 83");
});
