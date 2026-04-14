const { test, expect } = require("@playwright/test");
const { spawn } = require("child_process");
const readline = require("readline");
const path = require("path");

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

test.beforeAll(async () => {
  const started = await startFixtureServer();
  fixtureServer = started.child;
  fixtureServerUrl = started.metadata.url;
});

test.afterAll(async () => {
  await stopFixtureServer(fixtureServer);
});

test("drives the real Python console server against a local mock Torii", async ({ page }) => {
  await page.goto(fixtureServerUrl);

  await expect(page.locator("#request-status")).toContainText("Loaded 1 environment(s)");
  await expect(page.locator("#environment-summary")).toContainText("Torii:");
  await expect(page.locator("#environment-summary")).toContainText("(deployment)");
  await expect(page.locator("#environment-summary")).toContainText("configured (explicit)");
  await expect(page.locator("#environment-summary")).toContainText("signer config torii_url");

  await expect(page.locator("#proof-status-summary")).toContainText("Loaded SCCP discovery for fixture: 1 counterparties, 1 manifests.");
  await expect(page.locator("#sccp-counterparty-list")).toContainText("eth-sepolia");
  await expect(page.locator("#remote-transaction-history-preview")).toContainText('"items"');

  await page.locator("#bridge-route-input").fill("fixture_lane");
  await page.locator("#bridge-asset-key-input").fill("xor");
  await page.locator("#bridge-transfer-input").fill("fixture_transfer_1");
  await page.locator("#bridge-message-id-input").fill("cd".repeat(32));
  await page.locator("#refresh-bridge-snapshot").click();
  await expect(page.locator("#bridge-summary")).toContainText("Bridge snapshot loaded");
  await expect(page.locator("#bridge-snapshot-preview")).toContainText('"mirror_route"');

  await page.locator("#bridge-action-select").selectOption("lock_to_remote");
  await page.locator("#bridge-remote-domain-input").fill("1000");
  await page.locator("#bridge-recipient-input").fill("0x1111111111111111111111111111111111111111");
  await page.locator("#bridge-amount-input").fill("25");
  await page.locator("#build-bridge-request").click();
  await page.locator("#run-request").click();

  await expect(page.locator("#transaction-history-list")).toContainText("contract call");
  await expect(page.locator("#transaction-history-list")).toContainText("Committed");
  await expect(page.locator("#request-status")).toContainText("Request succeeded");

  await page.locator("#proof-lookup-message-id-input").fill("cd".repeat(32));
  await page.locator("#lookup-sccp-all").click();
  await expect(page.locator("#proof-lookup-summary")).toContainText("Loaded proof surfaces");
  await expect(page.locator("#proof-submission-package-preview")).toContainText("0xFixtureVerifier");

  await page.locator("#load-looked-up-bundle").click();
  await page.locator("#submit-bridge-proof").click();
  await expect(page.locator("#transaction-history-list")).toContainText("bridge proof submit");

  await page.locator("#insert-settlement-helper").click();
  await page.locator("#submit-bridge-message").click();
  await expect(page.locator("#transaction-history-list")).toContainText("bridge message submit");
  await expect(page.locator("#transaction-history-list")).toContainText("fixture_lane");

  await page.locator("#refresh-transaction-history").click();
  await expect(page.locator("#transaction-summary")).toContainText("Remote history:");
  await expect(page.locator("#remote-transaction-history-preview")).toContainText('"status": "Committed"');
});
