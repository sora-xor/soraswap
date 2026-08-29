const { test, expect } = require("@playwright/test");
const { spawn } = require("child_process");
const readline = require("readline");
const path = require("path");

const SELECTED_ENVIRONMENT_KEY = "soraswap.trader.selectedEnvironment.v1";
const AUTHORITY_BY_ENVIRONMENT_KEY = "soraswap.trader.authorityByEnvironment.v1";
const LIVE_MODE_ENABLED_KEY = "soraswap.trader.liveModeEnabled.v1";
const TAIRA_CHAIN_ID = "fc56984b-2be7-431d-840e-21514d1883f0";
const TAIRA_XOR_ASSET_DEFINITION_ID = "6TEAJqbb8oEPmLncoNiMRbLEK6tw";

let fixtureServer;
let fixtureServerUrl;

async function startFixtureServer(options = {}) {
  const serverPath = path.join(__dirname, "run_trader_fixture_server.py");
  const child = spawn("python3", [serverPath], {
    cwd: path.join(__dirname, ".."),
    env: {
      ...process.env,
      ...(options.env || {}),
    },
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

async function readLocalStorageJson(page, key) {
  return page.evaluate((storageKey) => {
    const raw = window.localStorage.getItem(storageKey);
    return raw === null ? null : JSON.parse(raw);
  }, key);
}

async function readLocalStorageItems(page, keys) {
  return page.evaluate((storageKeys) => (
    Object.fromEntries(storageKeys.map((key) => [key, window.localStorage.getItem(key)]))
  ), keys);
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
  const dialog = page.locator("#signed-confirmation-dialog");
  for (let attempt = 0; attempt < 3; attempt += 1) {
    await submit.click();
    try {
      await expect(dialog, `confirmation did not open for preview: ${preview}`).toBeVisible({ timeout: 1500 });
      break;
    } catch (error) {
      if (attempt === 2) {
        throw error;
      }
      await expect(submit).toBeEnabled();
    }
  }
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

test("scopes the exact XOR identity guard to canonical Taira", async ({ page }) => {
  await page.goto(fixtureServerUrl);
  await expect(page.locator("#status-banner")).toContainText("Loaded 3 executed fills");

  await page.route("**/api/catalog", async (route) => {
    const response = await route.fetch();
    const catalog = await response.json();
    catalog.environments[0].chain_fingerprint.chain = TAIRA_CHAIN_ID;
    await route.fulfill({
      status: response.status(),
      contentType: "application/json",
      body: JSON.stringify(catalog),
    });
  });

  await page.reload();
  await expect(page.locator("#status-banner")).toContainText(
    "Base Taira XOR must resolve to its exact permanent asset definition with scale 9.",
  );

  await page.route("**/api/assets/definitions/xor%23universal?*", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        ok: true,
        response_json: {
          id: TAIRA_XOR_ASSET_DEFINITION_ID,
          alias: "xor#universal",
          spec: { scale: 9 },
          alias_binding: {
            alias: "xor#universal",
            status: "permanent",
            bound_at_ms: 1,
          },
        },
      }),
    });
  });

  await page.reload();
  await expect(page.locator("#status-banner")).toContainText("Loaded 3 executed fills");
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
  await page.getByLabel("Spend Base Amount").fill("0.1234567891");
  await expect(page.locator("#trade-submit")).toBeDisabled();
  await expect(page.locator("#trade-submit")).toHaveAttribute(
    "title",
    "Spend Base Amount exceeds the current XOR scale of 9 fractional digits.",
  );

  await page.getByLabel("Spend Base Amount").fill("0.123456789");
  await page.getByLabel("Minimum Quote Out").fill("0.1234567");
  await expect(page.locator("#trade-submit")).toBeDisabled();
  await expect(page.locator("#trade-submit")).toHaveAttribute(
    "title",
    "Minimum Quote Out exceeds the current USDT scale of 6 fractional digits.",
  );

  await page.getByLabel("Spend Base Amount").fill("0.5000");
  await page.getByLabel("Minimum Quote Out").fill("0.40");
  await expect(page.locator("#trade-preview")).toContainText('"amount_in": "0.5"');
  await expect(page.locator("#trade-preview")).toContainText('"min_out": "0.4"');
  await expect(page.locator("#trade-submit")).toBeEnabled();
  await page.locator("#trade-submit").click();
  await expect(page.locator("#signed-confirmation-dialog")).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.locator("#signed-confirmation-dialog")).toBeHidden();
  await expect(page.locator("#trade-result")).toContainText("Cancelled before submission");
  expect(callRequests).toHaveLength(0);
});

test("sanitizes sensitive fields in trader confirmation JSON", async ({ page }) => {
  await page.goto(fixtureServerUrl);

  const sanitizedJson = await page.evaluate(() => JSON.stringify(sanitizeJsonForDisplay({
    amount_in: 90,
    private_key: "snake-secret",
    "private-key": "dash-secret",
    nested: {
      "private key": "space-secret",
      privateKey: "camel-secret",
      secret: "nested-secret",
      mnemonic: "seed words",
      apiKey: "api-key-secret",
      authorization: "bearer-secret",
      password: "password-secret",
      passphrase: "passphrase-secret",
      visible: "safe-visible-value",
    },
  })));

  expect(sanitizedJson).toContain("safe-visible-value");
  expect(sanitizedJson).not.toContain("snake-secret");
  expect(sanitizedJson).not.toContain("dash-secret");
  expect(sanitizedJson).not.toContain("space-secret");
  expect(sanitizedJson).not.toContain("camel-secret");
  expect(sanitizedJson).not.toContain("nested-secret");
  expect(sanitizedJson).not.toContain("seed words");
  expect(sanitizedJson).not.toContain("api-key-secret");
  expect(sanitizedJson).not.toContain("bearer-secret");
  expect(sanitizedJson).not.toContain("password-secret");
  expect(sanitizedJson).not.toContain("passphrase-secret");
});

test("accepts only current proxy status and transaction hash fields", async ({ page }) => {
  await page.goto(fixtureServerUrl);

  const result = await page.evaluate(() => {
    const txHashHex = "ab".repeat(32);
    const errorMessage = (callback) => {
      try {
        callback();
        return null;
      } catch (error) {
        return error instanceof Error ? error.message : String(error);
      }
    };

    return {
      canonicalStatus: requireCurrentPipelineStatusKind({ status_kind: "Queued" }),
      canonicalHash: requireCurrentTransactionHash({ tx_hash_hex: txHashHex }),
      stringStatusError: errorMessage(() => requireCurrentPipelineStatusKind({
        response_json: { status: "Queued" },
      })),
      nestedStatusError: errorMessage(() => requireCurrentPipelineStatusKind({
        response_json: { content: { status: { kind: "Queued" } } },
      })),
      responseHashError: errorMessage(() => requireCurrentTransactionHash({
        response_json: { tx_hash_hex: txHashHex },
      })),
      entrypointHashError: errorMessage(() => requireCurrentTransactionHash({
        entrypoint_hash: txHashHex,
      })),
    };
  });

  expect(result.canonicalStatus).toBe("Queued");
  expect(result.canonicalHash).toBe("ab".repeat(32));
  expect(result.stringStatusError).toContain("current status_kind");
  expect(result.nestedStatusError).toContain("current status_kind");
  expect(result.responseHashError).toContain("current tx_hash_hex");
  expect(result.entrypointHashError).toContain("current tx_hash_hex");
});

test("clears browser-local trader preferences in one action", async ({ page }) => {
  await page.goto(fixtureServerUrl);
  await expect(page.locator("#status-banner")).toContainText("Loaded 3 executed fills");

  const environmentName = await page.locator("#environment-select").inputValue();
  const authority = "i105clear_trader_state@universal";
  await page.locator("#authority-input").fill(authority);
  await expect.poll(() => readLocalStorageJson(page, AUTHORITY_BY_ENVIRONMENT_KEY)).toEqual({
    [environmentName]: authority,
  });
  await expect.poll(() => readLocalStorageJson(page, SELECTED_ENVIRONMENT_KEY)).toBe(environmentName);

  await page.locator("#live-toggle").click();
  await expect(page.locator("#live-status")).toHaveText("Paused");
  await expect.poll(() => readLocalStorageJson(page, LIVE_MODE_ENABLED_KEY)).toBe(false);

  await page.locator("#clear-trader-state").click();

  await expect(page.locator("#status-banner")).toContainText("Cleared browser-local trader state.");
  await expect(page.locator("#authority-input")).toHaveValue("");
  await expect(page.locator("#trade-submit")).toBeDisabled();
  await expect(page.locator("#trade-submit")).toHaveAttribute(
    "title",
    "Enter an authority to load trader state and submit actions.",
  );
  await expect(page.locator("#recent-fills")).toContainText("No fills loaded yet.");
  await expect(page.locator("#live-toggle")).toHaveText("Pause Live");

  await expect.poll(() => readLocalStorageItems(page, [
    SELECTED_ENVIRONMENT_KEY,
    AUTHORITY_BY_ENVIRONMENT_KEY,
    LIVE_MODE_ENABLED_KEY,
  ])).toEqual({
    [SELECTED_ENVIRONMENT_KEY]: null,
    [AUTHORITY_BY_ENVIRONMENT_KEY]: null,
    [LIVE_MODE_ENABLED_KEY]: null,
  });
});

test("renders capped large history windows without layout overflow", async ({ page }) => {
  const started = await startFixtureServer({
    env: {
      SORASWAP_TRADER_FIXTURE_EXTRA_FILLS: "180",
    },
  });
  const requests = [];
  page.on("request", (request) => {
    const requestUrl = new URL(request.url());
    if (requestUrl.pathname.startsWith("/api/contracts/rollups/")) {
      requests.push({
        path: requestUrl.pathname,
        query: Object.fromEntries(requestUrl.searchParams.entries()),
      });
    }
  });

  try {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto(started.metadata.url);

    await expect(page.locator("#status-banner")).toContainText("Loaded 120 executed fills");
    await expect(page.locator("#history-count")).toHaveText("120");
    await expect(page.locator("#recent-fills .fill-card")).toHaveCount(6);
    await expect(page.locator("#journal-body tr")).toHaveCount(120);
    await expect(page.locator("#activity-body tr")).toHaveCount(28);
    await expect(page.locator("#chart-empty")).toBeHidden();
    await expectNoHorizontalOverflow(page);

    const queryFor = (path) => requests.find((request) => request.path === path)?.query || {};
    expect(queryFor("/api/contracts/rollups/trader/account")).toEqual({
      authority: "i105fixturetrader@universal",
      environment: "fixture",
    });
    expect(queryFor("/api/contracts/rollups/swaps/fills").limit).toBe("120");
    expect(queryFor("/api/contracts/rollups/swaps/candles")).toMatchObject({
      bucket_secs: "900",
      limit: "96",
    });
    expect(queryFor("/api/contracts/rollups/trader/activity").limit).toBe("28");
  } finally {
    await stopFixtureServer(started.child);
  }
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
  await expect(page.locator("#trade-preview")).toContainText('"requested_leverage_bps": "40000"');
  await expect(page.locator("#trade-preview")).not.toContainText('"position_id"');
  await page.getByLabel("Signed Size").fill("-520");
  await expect(page.locator("#trade-preview")).toContainText('"size": "-520"');
  await expect(page.locator("#trade-submit")).toBeEnabled();
  await page.locator("#trade-mode-bar").getByRole("button", { name: /^Modify$/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "modify_position"');
  await expect(page.locator("#trade-preview")).toContainText('"position_id": "7"');
  await expect(page.locator("#trade-preview")).toContainText('"requested_leverage_bps": "40000"');
  await page.getByLabel("Signed Size Delta").fill("-40");
  await page.getByLabel("Signed Margin Delta").fill("-10");
  await expect(page.locator("#trade-submit")).toBeEnabled();
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
  expect(callRequests[0].payload).toEqual({
    amount_in: "90",
    input_is_base: "1",
    min_out: "80",
  });

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
  await expect(page.locator("#trade-preview")).toContainText('"side": "1"');
  await submitTraderAction(page);
  await expect(page.locator("#trade-result")).toContainText("committed");
  await page.locator("#trade-mode-bar").getByRole("button", { name: /^Settle$/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "settle_order"');

  await page.locator("#module-grid").getByRole("button", { name: /Launchpad/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "contribute_recorded"');
  await submitTraderAction(page);
  await expect(page.locator("#trade-result")).toContainText("committed");

  await page.locator("#trade-mode-bar").getByRole("button", { name: /^Claim$/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "claim_allocation"');
  await expect(page.locator("#trade-preview")).toContainText('"allocation": "alloc-alpha"');
  await expect(page.locator("#trade-preview")).not.toContainText('"sale"');
  await submitTraderAction(page);
  await expect(page.locator("#trade-result")).toContainText("committed");
  expect(callRequests.at(-1).payload).toEqual({ allocation: "alloc-alpha" });

  await page.locator("#trade-mode-bar").getByRole("button", { name: /^Refund$/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "refund_allocation"');
  await expect(page.locator("#trade-preview")).toContainText('"allocation": "alloc-alpha"');
  await expect(page.locator("#trade-preview")).not.toContainText('"sale"');
  await submitTraderAction(page);
  await expect(page.locator("#trade-result")).toContainText("committed");
  expect(callRequests.at(-1).payload).toEqual({ allocation: "alloc-alpha" });

  await page.locator("#module-grid").getByRole("button", { name: /Options/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "buy_shout"');
  await expect(page.locator("#trade-preview")).not.toContainText('"position_id"');
  await expect(page.locator("#trade-preview")).not.toContainText('"premium_paid"');
  await submitTraderAction(page);
  await expect(page.locator("#trade-result")).toContainText("committed");
  expect(callRequests.at(-1).payload).toEqual({ series_id: "12", notional: "220" });

  await page.locator("#trade-mode-bar").getByRole("button", { name: /^Exercise Shout$/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "exercise_shout_position"');
  await submitTraderAction(page);
  await expect(page.locator("#trade-result")).toContainText("committed");
  expect(callRequests.at(-1).payload).toEqual({ position_id: "77" });

  await page.locator("#module-grid").getByRole("button", { name: /Cover/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "register_policy"');
  await expect(page.locator("#trade-preview")).not.toContainText('"policy_id"');
  await submitTraderAction(page);
  await expect(page.locator("#trade-result")).toContainText("committed");
  expect(callRequests.at(-1).payload).toEqual({
    lower_bound: "9000",
    upper_bound: "11000",
    payout_amount: "260",
    monitoring_window_slots: "3",
    required_observations: "2",
    covered_notional: "1100",
    premium_paid: "32",
  });

  await page.locator("#trade-mode-bar").getByRole("button", { name: /^Claim$/i }).click();
  await submitTraderAction(page);
  await expect(page.locator("#trade-result")).toContainText("committed");
  expect(callRequests.at(-1).payload).toEqual({ policy_id: "5" });

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
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "schedule_twamm"');
  await submitTraderAction(page);
  await expect(page.locator("#trade-result")).toContainText("committed");
  expect(callRequests.at(-1).payload).toEqual({
    order_id: "twamm-1",
    input_is_base: "1",
    total_in: "1000",
    slice_in: "100",
    min_total_out: "950",
    interval_slots: "2",
    start_slot: "1",
  });
  await page.locator("#trade-mode-bar").getByRole("button", { name: /^Claim TWAMM$/i }).click();
  await expect(page.locator("#trade-preview")).toContainText('"entrypoint": "claim_twamm"');
});
