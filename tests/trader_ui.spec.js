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

async function expectNoHorizontalOverflow(page) {
  const dimensions = await page.evaluate(() => ({
    viewportWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth,
  }));
  expect(dimensions.scrollWidth).toBeLessThanOrEqual(dimensions.viewportWidth + 1);
}

async function workspaceColumnCount(page) {
  return page.evaluate(() => {
    const columns = window.getComputedStyle(document.querySelector(".workspace")).gridTemplateColumns;
    return columns.split(" ").filter(Boolean).length;
  });
}

async function confirmSignedCall(page) {
  const dialog = page.locator("#signed-confirmation-dialog");
  await expect(dialog).toBeVisible();
  await expect(dialog).toContainText("Confirm Call");
  await expect(dialog).toContainText("Confirm signed call");
  await dialog.getByRole("button", { name: "Confirm signed call" }).click();
  await expect(dialog).toBeHidden();
}

async function submitTraderAction(page) {
  const submit = page.locator("#trade-submit");
  const preview = await page.locator("#trade-preview").textContent();
  await expect(submit).toBeEnabled();
  await expect(submit).toHaveAttribute("title", "");
  await submit.click();
  const dialog = page.locator("#signed-confirmation-dialog");
  await expect(dialog, `confirmation did not open for preview: ${preview}`).toBeVisible();
  await expect(dialog).toContainText("Confirm Call");
  await expect(dialog).toContainText("Confirm signed call");
  await dialog.getByRole("button", { name: "Confirm signed call" }).click();
  await expect(dialog).toBeHidden();
}

test.beforeAll(async () => {
  const started = await startFixtureServer();
  fixtureServer = started.child;
  fixtureServerUrl = started.metadata.url;
});

test.afterAll(async () => {
  await stopFixtureServer(fixtureServer);
});

test("keeps the trader cockpit viewport-safe on mobile", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(fixtureServerUrl);

  await expect(page.locator("#status-banner")).toContainText("Loaded 3 executed fills");
  await expectNoHorizontalOverflow(page);
  await expect(page.locator("#module-grid")).not.toContainText("T+");
  await expect(page.locator("#module-grid")).toContainText("UTC");
  const railPositions = await page.evaluate(() => ({
    actionTop: document.querySelector(".action-rail").getBoundingClientRect().top,
    leftTop: document.querySelector(".left-rail").getBoundingClientRect().top,
    centerTop: document.querySelector(".center-stage").getBoundingClientRect().top,
  }));
  expect(railPositions.actionTop).toBeLessThan(railPositions.leftTop);
  expect(railPositions.actionTop).toBeLessThan(railPositions.centerTop);

  await page.locator("#authority-input").fill(`i105${"x".repeat(420)}@universal`);
  await expectNoHorizontalOverflow(page);
});

test("keeps the action submit reachable in the 1280px cockpit", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.goto(fixtureServerUrl);

  await expect(page.locator("#status-banner")).toContainText("Loaded 3 executed fills");
  expect(await workspaceColumnCount(page)).toBe(3);
  await expect(page.locator("#trade-submit")).toBeInViewport();
  await page.locator("#trade-submit").click();
  await expect(page.locator("#signed-confirmation-dialog")).toBeVisible();
  await page.locator("#signed-confirmation-dialog").getByRole("button", { name: "Cancel", exact: true }).click();
  await expect(page.locator("#trade-result")).toContainText("Cancelled before submission");
});

test("does not submit or confirm invalid trader mutations", async ({ page }) => {
  const callRequests = [];
  await page.route("**/api/call", async (route) => {
    callRequests.push(JSON.parse(route.request().postData() || "{}"));
    await route.continue();
  });

  await page.goto(fixtureServerUrl);
  await expect(page.locator("#status-banner")).toContainText("Loaded 3 executed fills");

  await page.locator("#trade-gas-limit-input").fill("0");
  await expect(page.locator("#trade-submit")).toBeDisabled();
  await expect(page.locator("#trade-submit")).toHaveAttribute("title", "Gas limit must be a positive integer.");
  await expect(page.locator("#signed-confirmation-dialog")).toBeHidden();
  expect(callRequests).toHaveLength(0);

  await page.locator("#trade-gas-limit-input").fill("100000");
  await expect(page.locator("#trade-submit")).toBeEnabled();
  await page.locator("#trade-submit").click();
  await expect(page.locator("#signed-confirmation-dialog")).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.locator("#signed-confirmation-dialog")).toBeHidden();
  await expect(page.locator("#trade-result")).toContainText("Cancelled before submission");
  expect(callRequests).toHaveLength(0);
});

test("renders the trader cockpit and submits a routed swap through the real Python server", async ({ page }) => {
  const callRequests = [];
  await page.route("**/api/call", async (route) => {
    callRequests.push(JSON.parse(route.request().postData() || "{}"));
    await route.continue();
  });
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
  await expect(page.locator("#module-grid")).toContainText("Batch Auction");
  await expect(page.locator("#module-grid")).toContainText("Launchpad");
  await expect(page.locator("#module-grid")).toContainText("Options");
  await expect(page.locator("#module-grid")).toContainText("Cover");
  await expect(page.locator("#module-grid")).toContainText("Intents");
  await expect(page.locator("#module-grid")).toContainText("Vaults");
  await expect(page.locator("#module-grid")).toContainText("Escrow");
  await expect(page.locator("#module-grid")).toContainText("Operators");
  await expect(page.locator("#module-grid")).toContainText("Margin");
  await expect(page.locator("#module-grid")).toContainText("RWA");
  await expect(page.locator("#module-grid")).toContainText("DLMM Hooks");
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
  await expect(page.locator("#module-grid")).not.toContainText("T+");

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
  await expect(page.locator("#signed-confirmation-dialog")).toBeVisible();
  await expect(page.locator("#signed-confirmation-dialog")).toContainText("fixture");
  await expect(page.locator("#signed-confirmation-dialog")).toContainText("route_swap");
  await page.locator("#signed-confirmation-dialog").getByRole("button", { name: "Cancel", exact: true }).click();
  await expect(page.locator("#trade-result")).toContainText("Cancelled before submission");
  expect(callRequests).toHaveLength(0);

  await submitTraderAction(page);
  await expect.poll(() => callRequests.length).toBe(1);

  await expect(page.locator("#trade-result")).toContainText("committed");
  await expect(page.locator("#status-banner")).toContainText("Loaded 4 executed fills");
  await expect(page.locator("#history-head")).toHaveText("5");
  await expect(page.locator("#history-count")).toHaveText("4");
  await expect(page.locator("#recent-fills")).toContainText("Bought 83 USDT");
  await expect(page.locator("#journal-body")).toContainText("83 USDT");
  await expect(page.locator("#activity-body")).toContainText("9 -> 83");

  await page.locator("#module-grid").getByRole("button", { name: /Batch Auction/i }).click();
  await expect(page.locator("#trade-title")).toHaveText("Epoch Auction");
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "submit_order"');
  await expect(page.locator("#trade-preview")).toContainText('"side": 1');
  await submitTraderAction(page);
  await expect(page.locator("#trade-result")).toContainText("committed");
  await page.locator("#trade-mode-bar").getByRole("button", { name: /^Settle$/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "settle_order"');

  await page.locator("#module-grid").getByRole("button", { name: /Launchpad/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "contribute_recorded"');
  await submitTraderAction(page);
  await expect(page.locator("#trade-result")).toContainText("committed");

  await page.locator("#module-grid").getByRole("button", { name: /Intents/i }).click();
  await page.locator("#trade-mode-bar").getByRole("button", { name: /^Fill$/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "fill_intent"');
  await submitTraderAction(page);
  await expect(page.locator("#trade-result")).toContainText("committed");

  await page.locator("#module-grid").getByRole("button", { name: /Vaults/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "deposit"');
  await submitTraderAction(page);
  await expect(page.locator("#trade-result")).toContainText("committed");
  await page.locator("#trade-mode-bar").getByRole("button", { name: /^Redeem$/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "request_redeem"');
  await submitTraderAction(page);
  await expect(page.locator("#trade-result")).toContainText("committed");

  await page.locator("#module-grid").getByRole("button", { name: /Escrow/i }).click();
  await expect(page.locator("#trade-title")).toHaveText("Conditional Escrow");
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "open_escrow"');
  await submitTraderAction(page);
  await expect(page.locator("#trade-result")).toContainText("committed");
  await page.locator("#trade-mode-bar").getByRole("button", { name: /^Accept$/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "accept_escrow"');
  await submitTraderAction(page);
  await expect(page.locator("#trade-result")).toContainText("committed");

  await page.locator("#module-grid").getByRole("button", { name: /Operators/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "bond"');
  await submitTraderAction(page);
  await expect(page.locator("#trade-result")).toContainText("committed");

  await page.locator("#module-grid").getByRole("button", { name: /^Margin/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "deposit_collateral"');
  await submitTraderAction(page);
  await expect(page.locator("#trade-result")).toContainText("committed");

  await page.locator("#module-grid").getByRole("button", { name: /RWA/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "issue_lot"');
  await submitTraderAction(page);
  await expect(page.locator("#trade-result")).toContainText("committed");
  await page.locator("#trade-mode-bar").getByRole("button", { name: /^Redeem$/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "request_redemption"');
  await submitTraderAction(page);
  await expect(page.locator("#trade-result")).toContainText("committed");

  await page.locator("#module-grid").getByRole("button", { name: /DLMM Hooks/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "place_limit_order"');
  await page.locator("#trade-mode-bar").getByRole("button", { name: /^TWAMM$/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "schedule_twamm_v2"');
  await submitTraderAction(page);
  await expect(page.locator("#trade-result")).toContainText("committed");
  await page.locator("#trade-mode-bar").getByRole("button", { name: /^Claim TWAMM$/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "claim_twamm"');
});
