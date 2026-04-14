const { test, expect } = require("@playwright/test");
const { spawn } = require("child_process");
const readline = require("readline");
const path = require("path");

const ITERATIONS = Number(process.env.CONTRACT_CONSOLE_SOAK_ITERATIONS || "3");

let fixtureServer;
let fixtureServerUrl;

async function startFixtureServer() {
  const serverPath = path.join(__dirname, "run_contract_console_fixture_server.py");
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
      reject(new Error("timed out waiting for fixture console server"));
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
      reject(new Error(`fixture console server exited early with code ${code}`));
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

function messageIdForIteration(index) {
  const nibble = (index % 16).toString(16);
  return nibble.repeat(64);
}

test.beforeAll(async () => {
  const started = await startFixtureServer();
  fixtureServer = started.child;
  fixtureServerUrl = started.metadata.url;
});

test.afterAll(async () => {
  await stopFixtureServer(fixtureServer);
});

test("keeps bookmarks, proof lookup, tracking, refresh, and timeout handling stable over a long session", async ({ page }) => {
  await page.addInitScript(() => {
    window.__SORASWAP_CONTRACT_CONSOLE_CONFIG__ = {
      transactionPollIntervalMs: 25,
      transactionPollTimeoutMs: 160,
    };
  });

  await page.goto(fixtureServerUrl);
  await expect(page.locator("#request-status")).toContainText("Loaded 1 environment(s)");

  for (let index = 0; index < ITERATIONS; index += 1) {
    const route = `fixture_lane_${index}`;
    const transfer = `fixture_transfer_${index}`;
    const messageId = messageIdForIteration(index + 1);

    await page.locator("#bridge-route-input").fill(route);
    await page.locator("#bridge-asset-key-input").fill("xor");
    await page.locator("#bridge-transfer-input").fill(transfer);
    await page.locator("#bridge-message-id-input").fill(messageId);
    await page.locator("#bookmark-current-bridge").click();
    await page.locator("#refresh-bridge-snapshot").click();

    await expect(page.locator("#bridge-summary")).toContainText("Bridge snapshot loaded");
    await expect(page.locator("#bridge-snapshot-preview")).toContainText(route);

    await page.locator("#proof-lookup-message-id-input").fill(messageId);
    await page.locator("#lookup-sccp-all").click();
    await expect(page.locator("#proof-lookup-summary")).toContainText(`Loaded proof surfaces for ${messageId}`);

    await page.locator("#load-looked-up-bundle").click();
    await page.locator("#submit-bridge-proof").click();
    await expect(page.locator("#transaction-history-list")).toContainText("bridge proof submit");

    await page.locator("#insert-settlement-helper").click();
    await page.locator("#submit-bridge-message").click();
    await expect(page.locator("#transaction-history-list")).toContainText("bridge message submit");
    await expect(page.locator("#transaction-history-list")).toContainText(route);

    await page.locator("#refresh-transaction-history").click();
    await expect(page.locator("#remote-transaction-history-preview")).toContainText('"items"');

    await page.reload();
    await expect(page.locator("#bookmark-route-select")).toContainText(route);
    await expect(page.locator("#bookmark-message-id-select")).toContainText(messageId);
    await expect(page.locator("#transaction-history-list")).toContainText("bridge message submit");
  }

  await page.locator("#bridge-action-select").selectOption("lock_to_remote");
  await page.locator("#bridge-route-input").fill("timeout_route");
  await page.locator("#bridge-transfer-input").fill("timeout_transfer");
  await page.locator("#bridge-remote-domain-input").fill("1000");
  await page.locator("#bridge-recipient-input").fill("0x1111111111111111111111111111111111111111");
  await page.locator("#bridge-amount-input").fill("25");
  await page.locator("#build-bridge-request").click();
  await page.locator("#run-request").click();

  await expect(page.locator("#transaction-history-list")).toContainText("TimedOut");
  await expect(page.locator("#transaction-history-list")).toContainText("Tracking timed out before a terminal transaction status was returned.");
  await expect(page.locator("#transaction-summary")).toContainText("Timed out: 1");
});
