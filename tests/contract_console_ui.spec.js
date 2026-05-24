const { test, expect } = require("@playwright/test");

const LOCAL_BRIDGE_ADDRESS = "tairac1localbridge000000000000000000000000000000000000";
const TESTNET_BRIDGE_ADDRESS = "tairac1testnetbridge000000000000000000000000000000000";
const PRODUCTION_BRIDGE_ADDRESS = "prodc1bridge0000000000000000000000000000000000000000";
const CALL_TX_HASH = "c0".repeat(32);
const PROOF_TX_HASH = "d1".repeat(32);
const MESSAGE_TX_HASH = "e2".repeat(32);
const LOOKUP_MESSAGE_ID = "ab".repeat(32);
const RECENT_REQUESTS_KEY = "soraswap.contractConsole.recentRequests.v1";
const TRANSACTION_STATUSES_KEY = "soraswap.contractConsole.transactionStatuses.v1";

function bridgeEntrypoints() {
  return [
    {
      name: "listing_config",
      kind: "View",
      permission: "",
      params: [],
      return_type: "ListingConfig",
    },
    {
      name: "mirror_asset",
      kind: "View",
      permission: "",
      params: [
        { name: "asset_key", type_name: "String" },
      ],
      return_type: "MirrorAsset",
    },
    {
      name: "mirror_route",
      kind: "View",
      permission: "",
      params: [
        { name: "route", type_name: "String" },
      ],
      return_type: "MirrorRoute",
    },
    {
      name: "register_asset",
      kind: "Call",
      permission: "Operator",
      params: [
        { name: "asset_key", type_name: "String" },
        { name: "registrant", type_name: "AccountId" },
        { name: "asset", type_name: "String" },
        { name: "home_domain", type_name: "u32" },
        { name: "decimals", type_name: "u32" },
      ],
      return_type: "Unit",
    },
    {
      name: "activate_route",
      kind: "Call",
      permission: "Operator",
      params: [
        { name: "route", type_name: "String" },
        { name: "asset_key", type_name: "String" },
        { name: "remote_domain", type_name: "u32" },
        { name: "local_asset", type_name: "String" },
        { name: "vault_account", type_name: "AccountId" },
      ],
      return_type: "Unit",
    },
    {
      name: "pause_route",
      kind: "Call",
      permission: "Operator",
      params: [
        { name: "route", type_name: "String" },
      ],
      return_type: "Unit",
    },
    {
      name: "resume_route",
      kind: "Call",
      permission: "Operator",
      params: [
        { name: "route", type_name: "String" },
      ],
      return_type: "Unit",
    },
    {
      name: "lock_to_remote",
      kind: "Call",
      permission: "Operator",
      params: [
        { name: "route", type_name: "String" },
        { name: "transfer", type_name: "String" },
        { name: "sender", type_name: "AccountId" },
        { name: "recipient", type_name: "String" },
        { name: "amount", type_name: "u64" },
      ],
      return_type: "Unit",
    },
    {
      name: "finalize_inbound",
      kind: "Call",
      permission: "Operator",
      params: [
        { name: "route", type_name: "String" },
        { name: "message_id", type_name: "String" },
        { name: "recipient", type_name: "String" },
        { name: "amount", type_name: "u64" },
      ],
      return_type: "Unit",
    },
  ];
}

function makeBridgeContract(address, manifestPath) {
  return {
    contract_key: "bridge.sccp_bridge",
    contract_address: address,
    dataspace: "universal",
    deploy_nonce: 7,
    verification: "verified",
    contract_source: "contracts/bridge/sccp_bridge.ko",
    manifest_path: manifestPath,
    entrypoints: bridgeEntrypoints(),
  };
}

function createCatalog() {
  return {
    repo_root: "/Users/takemiyamakoto/dev/soraswap",
    environments: [
      {
        name: "local",
        torii_url: "http://127.0.0.1:8080",
        torii_url_source: "deployment",
        chain_fingerprint: {
          chain: "local-fingerprint",
        },
        signer: {
          configured: true,
          source: "auto:tmp/iroha-localnet/client.toml",
          call_enabled: true,
          authority: "i105localbridgeoperator@universal",
          warnings: [],
        },
        contracts: [
          makeBridgeContract(LOCAL_BRIDGE_ADDRESS, "artifacts/local/bridge.sccp_bridge.manifest.json"),
          {
            contract_key: "n3x",
            contract_address: "tairac1localn3x000000000000000000000000000000000000000",
            dataspace: "universal",
            deploy_nonce: 3,
            verification: "verified",
            contract_source: "contracts/n3x/n3x.ko",
            manifest_path: "artifacts/local/n3x.manifest.json",
            entrypoints: [
              {
                name: "quote_redeem",
                kind: "View",
                permission: "",
                params: [
                  { name: "shares", type_name: "u64" },
                ],
                return_type: "RedeemQuote",
              },
            ],
          },
        ],
      },
      {
        name: "testnet",
        torii_url: "https://taira.sora.org",
        torii_url_source: "deployment",
        chain_fingerprint: {
          chain: "taira-public-fingerprint",
        },
        signer: {
          configured: true,
          source: "cli:/tmp/taira.client.toml",
          call_enabled: true,
          authority: "i105testnetbridgeoperator@universal",
          warnings: [],
        },
        contracts: [
          makeBridgeContract(TESTNET_BRIDGE_ADDRESS, "artifacts/testnet/bridge.sccp_bridge.manifest.json"),
        ],
      },
      {
        name: "production",
        torii_url: "https://production.example.invalid",
        torii_url_source: "deployment",
        chain_fingerprint: {
          chain: "production-public-fingerprint",
        },
        signer: {
          configured: true,
          source: "cli:/tmp/production.client.toml",
          call_enabled: true,
          authority: "i105productionbridgeoperator@universal",
          warnings: [],
        },
        contracts: [
          makeBridgeContract(PRODUCTION_BRIDGE_ADDRESS, "artifacts/production/bridge.sccp_bridge.manifest.json"),
        ],
      },
    ],
  };
}

function createAdversarialCatalog() {
  const catalog = createCatalog();
  const longToken = "x".repeat(420);
  catalog.repo_root = `/Users/takemiyamakoto/dev/soraswap/${longToken}`;
  const local = catalog.environments[0];
  local.name = `local-${longToken}`;
  local.torii_url = `https://${longToken}.example.invalid/${longToken}`;
  local.chain_fingerprint.chain = `chain-${longToken}`;
  local.signer.source = `cli:/tmp/${longToken}.client.toml`;
  local.signer.authority = `i105${longToken}@universal`;
  local.signer.warnings = [`warning-${longToken}`];
  local.mutation_policy = {
    allowed: true,
    name: `policy-${longToken}`,
  };
  local.contracts[0] = {
    ...local.contracts[0],
    contract_address: `tairac1${longToken}`,
    contract_source: `contracts/bridge/${longToken}/sccp_bridge.ko`,
    manifest_path: `artifacts/local/${longToken}/bridge.sccp_bridge.manifest.json`,
  };
  return catalog;
}

function capabilitiesByEnvironment() {
  return {
    local: {
      ok: true,
      upstream_status: 200,
      response_json: {
        counterparties: [
          {
            domain: 1000,
            chain: "eth-sepolia",
            counterparty_account_codec_key: "evm_hex",
            message_backend: "sccp",
            registry_backend: "sccp",
          },
          {
            domain: 2000,
            chain: "ton-testnet",
            counterparty_account_codec_key: "ton_raw",
            message_backend: "sccp",
            registry_backend: "sccp",
          },
        ],
      },
    },
    testnet: {
      ok: true,
      upstream_status: 200,
      response_json: {
        counterparties: [
          {
            domain: 3000,
            chain: "solana-devnet",
            counterparty_account_codec_key: "solana_base58",
            message_backend: "sccp",
            registry_backend: "sccp",
          },
        ],
      },
    },
    production: {
      ok: true,
      upstream_status: 200,
      response_json: {
        counterparties: [
          {
            domain: 4000,
            chain: "ethereum-mainnet",
            counterparty_account_codec_key: "evm_hex",
            message_backend: "sccp",
            registry_backend: "sccp",
          },
        ],
      },
    },
  };
}

function manifestsByEnvironment() {
  return {
    local: {
      ok: true,
      upstream_status: 200,
      response_json: {
        manifests: [
          {
            counterparty_domain: 1000,
            verifier_target: "0xVerifierETH",
            finality_model: "safe_block_depth",
            submission_template: {
              encoding: "abi_json",
            },
          },
          {
            counterparty_domain: 2000,
            verifier_target: "ton:verifier",
            finality_model: "light_client",
            submission_template: {
              encoding: "boc_json",
            },
          },
        ],
      },
    },
    testnet: {
      ok: true,
      upstream_status: 200,
      response_json: {
        manifests: [
          {
            counterparty_domain: 3000,
            verifier_target: "solana-program:bridge",
            finality_model: "slot_depth",
            submission_template: {
              encoding: "json",
            },
          },
        ],
      },
    },
    production: {
      ok: true,
      upstream_status: 200,
      response_json: {
        manifests: [
          {
            counterparty_domain: 4000,
            verifier_target: "0xVerifierMainnet",
            finality_model: "finalized_block_depth",
            submission_template: {
              encoding: "abi_json",
            },
          },
        ],
      },
    },
  };
}

function historyByEnvironment() {
  return {
    local: {
      ok: true,
      available: true,
      supported: true,
      upstream_status: 200,
      response_json: {
        items: [
          {
            hash: "11".repeat(32),
            status: "Committed",
          },
        ],
      },
    },
    testnet: {
      ok: false,
      available: false,
      supported: false,
      upstream_status: 503,
      error_code: "tx_history_auth_unavailable",
      unsupported_reason: "tx_history_auth_unavailable",
      response_json: {
        error: "tx_history_auth_unavailable",
      },
    },
    production: {
      ok: true,
      available: true,
      supported: true,
      upstream_status: 200,
      response_json: {
        items: [
          {
            hash: "22".repeat(32),
            status: "Queued",
          },
        ],
      },
    },
  };
}

function proofBundle(messageId) {
  return {
    ok: true,
    upstream_status: 200,
    response_json: {
      version: 1,
      commitment_root: "01".repeat(32),
      commitment: {
        version: 1,
        kind: "Transfer",
        target_domain: 1000,
        message_id: messageId,
        payload_hash: "02".repeat(32),
        parliament_certificate_hash: null,
      },
      merkle_proof: {
        steps: [
          {
            direction: "left",
            hash: "03".repeat(32),
          },
        ],
      },
      payload: {
        Transfer: {
          version: 1,
          source_domain: 0,
          dest_domain: 1000,
          nonce: 42,
          asset_home_domain: 0,
          asset_id_codec: 1,
          asset_id: "xor#universal",
          amount: 25,
          sender_codec: 1,
          sender: "nexus:soraswap",
          recipient_codec: 2,
          recipient: "0x1111111111111111111111111111111111111111",
          route_id_codec: 1,
          route_id: "eth_lane",
        },
      },
      finality_proof: "0xdeadbeef",
    },
  };
}

function proofArtifact() {
  return {
    ok: true,
    upstream_status: 200,
    response_json: {
      counterparty_domain: 1000,
      bundle: {
        payload: {
          chain: "eth-sepolia",
        },
      },
      submission_package: {
        verifier_target: "0xVerifierETH",
        expected_finality: "safe",
      },
    },
  };
}

function proofJob() {
  return {
    ok: true,
    upstream_status: 200,
    response_json: {
      counterparty_domain: 1000,
      chain: "eth-sepolia",
      payload_kind: "Transfer",
      submission_package: {
        verifier_target: "0xVerifierETH",
        finality_checkpoint: "12345",
      },
      submission_template: {
        encoding: "abi_json",
        verifier_target: "0xVerifierETH",
        fields: ["commitment_root", "merkle_proof", "finality_proof"],
      },
    },
  };
}

function createApiState(overrides = {}) {
  return {
    bridgeInspects: [],
    requests: [],
    statusLookups: [],
    ...overrides,
  };
}

async function fulfillJson(route, body, status = 200) {
  await route.fulfill({
    status,
    contentType: "application/json",
    body: JSON.stringify(body),
  });
}

async function installApiMocks(page, apiState, overrides = {}) {
  const catalog = overrides.catalog || createCatalog();
  const capabilityMap = overrides.capabilityMap || capabilitiesByEnvironment();
  const manifestMap = overrides.manifestMap || manifestsByEnvironment();
  const historyMap = overrides.historyMap || historyByEnvironment();

  await page.route("**/api/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    const path = url.pathname;
    const environment = url.searchParams.get("environment");

    if (path === "/api/catalog") {
      await fulfillJson(route, catalog);
      return;
    }

    if (path === "/api/transactions/history") {
      await fulfillJson(route, historyMap[environment] || historyMap.local);
      return;
    }

    if (path === "/api/sccp/capabilities") {
      await fulfillJson(route, capabilityMap[environment] || capabilityMap.local);
      return;
    }

    if (path === "/api/sccp/manifests") {
      await fulfillJson(route, manifestMap[environment] || manifestMap.local);
      return;
    }

    if (/^\/api\/sccp\/proofs\/message\/[0-9a-f]+$/.test(path)) {
      const messageId = path.split("/").pop();
      await fulfillJson(route, proofBundle(messageId));
      return;
    }

    if (/^\/api\/sccp\/artifacts\/message\/[0-9a-f]+$/.test(path)) {
      await fulfillJson(route, proofArtifact());
      return;
    }

    if (/^\/api\/sccp\/jobs\/message\/[0-9a-f]+$/.test(path)) {
      await fulfillJson(route, proofJob());
      return;
    }

    if (path === "/api/pipeline/transactions/status") {
      const hash = url.searchParams.get("hash");
      apiState.statusLookups.push({ environment, hash });
      if (typeof overrides.statusResponseFactory === "function") {
        await fulfillJson(route, overrides.statusResponseFactory({
          environment,
          hash,
          attempt: apiState.statusLookups.length,
        }));
        return;
      }
      await fulfillJson(route, {
        ok: true,
        upstream_status: 200,
        status_kind: "Committed",
        response_json: {
          status: {
            kind: "Committed",
          },
        },
      });
      return;
    }

    if (path === "/api/bridge/inspect" && request.method() === "POST") {
      const body = JSON.parse(request.postData() || "{}");
      apiState.bridgeInspects.push(body);
      await fulfillJson(route, {
        ok: true,
        contract: {
          contract_address: {
            local: LOCAL_BRIDGE_ADDRESS,
            testnet: TESTNET_BRIDGE_ADDRESS,
            production: PRODUCTION_BRIDGE_ADDRESS,
          }[body.environment] || LOCAL_BRIDGE_ADDRESS,
        },
        requested_keys: {
          asset_key: body.asset_key || null,
          route: body.route || null,
          transfer: body.transfer || null,
          message_id: body.message_id || null,
        },
        views: [
          {
            entrypoint: "mirror_route",
            response_json: [body.route || "eth_lane", 1000],
          },
          {
            entrypoint: "route_config",
            response_json: {
              route: body.route || "eth_lane",
              enabled: true,
            },
          },
        ],
      });
      return;
    }

    if (path === "/api/call" && request.method() === "POST") {
      const body = JSON.parse(request.postData() || "{}");
      apiState.requests.push({
        path,
        body,
      });
      await fulfillJson(route, {
        ok: true,
        upstream_status: 200,
        submitted: true,
        tx_hash_hex: CALL_TX_HASH,
        status_kind: "Pending",
        response_json: {
          accepted: true,
        },
      });
      return;
    }

    if (path === "/api/bridge/proofs/submit" && request.method() === "POST") {
      const body = JSON.parse(request.postData() || "{}");
      apiState.requests.push({
        path,
        body,
      });
      await fulfillJson(route, {
        ok: true,
        upstream_status: 200,
        submitted: true,
        tx_hash_hex: PROOF_TX_HASH,
        status_kind: "Pending",
        response_json: {
          accepted: true,
        },
      });
      return;
    }

    if (path === "/api/bridge/messages" && request.method() === "POST") {
      const body = JSON.parse(request.postData() || "{}");
      apiState.requests.push({
        path,
        body,
      });
      await fulfillJson(route, {
        ok: true,
        upstream_status: 200,
        submitted: true,
        tx_hash_hex: MESSAGE_TX_HASH,
        status_kind: "Pending",
        response_json: {
          accepted: true,
        },
      });
      return;
    }

    if (path === "/api/view") {
      await fulfillJson(route, {
        ok: true,
        upstream_status: 200,
        response_json: {},
      });
      return;
    }

    await fulfillJson(route, {
      ok: false,
      error: `unhandled mock route: ${path}`,
    }, 404);
  });
}

async function bootConsole(page, overrides = {}) {
  const apiState = createApiState(overrides.apiState);
  const catalog = overrides.catalog || createCatalog();
  await installApiMocks(page, apiState, { ...overrides, catalog });
  await page.goto("/");
  await expect(page.locator("#request-status")).toContainText(`Loaded ${catalog.environments.length} environment(s)`);
  return apiState;
}

async function readLocalStorageJson(page, key) {
  return page.evaluate((storageKey) => {
    const raw = window.localStorage.getItem(storageKey);
    return raw ? JSON.parse(raw) : null;
  }, key);
}

function prettyJsonForTest(value) {
  return JSON.stringify(value, null, 2);
}

async function expectNoHorizontalOverflow(page) {
  const dimensions = await page.evaluate(() => ({
    viewportWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth,
  }));
  expect(dimensions.scrollWidth).toBeLessThanOrEqual(dimensions.viewportWidth + 1);
}

async function confirmSignedCall(page) {
  const dialog = page.locator("#signed-confirmation-dialog");
  await expect(dialog).toBeVisible();
  await expect(dialog).toContainText("Confirm Call");
  await expect(dialog).toContainText("Confirm signed call");
  await dialog.getByRole("button", { name: "Confirm signed call" }).click();
  await expect(dialog).toBeHidden();
}

test("loads catalog, SCCP discovery, and environment-specific history state", async ({ page }) => {
  await bootConsole(page);

  await expect(page.locator("h1")).toHaveText("Bridge Operator Console");
  await expect(page.locator("#environment-select option")).toHaveCount(3);
  await expect(page.locator("#environment-summary")).toContainText("Torii: http://127.0.0.1:8080 (deployment)");
  await expect(page.locator("#environment-summary")).toContainText("Signer: configured (auto:tmp/iroha-localnet/client.toml)");
  await expect(page.locator("#bridge-summary")).toContainText(`Bridge: ${LOCAL_BRIDGE_ADDRESS}`);
  await expect(page.locator("#proof-status-summary")).toContainText("Loaded SCCP discovery for local: 2 counterparties, 2 manifests.");
  await expect(page.locator("#sccp-counterparty-list")).toContainText("eth-sepolia");
  await expect(page.locator("#sccp-counterparty-list")).toContainText("Codec: evm_hex");

  await page.locator("#environment-select").selectOption("testnet");

  await expect(page.locator("#environment-summary")).toContainText("Torii: https://taira.sora.org (deployment)");
  await expect(page.locator("#proof-status-summary")).toContainText("Loaded SCCP discovery for testnet: 1 counterparties, 1 manifests.");
  await expect(page.locator("#transaction-summary")).toContainText("Remote history unavailable: tx_history_auth_unavailable");
  await expect(page.locator("#bridge-summary")).toContainText(`Bridge: ${TESTNET_BRIDGE_ADDRESS}`);

  await page.locator("#environment-select").selectOption("production");

  await expect(page.locator("#environment-summary")).toContainText("Torii: https://production.example.invalid (deployment)");
  await expect(page.locator("#environment-summary")).toContainText("Signer: configured (cli:/tmp/production.client.toml)");
  await expect(page.locator("#proof-status-summary")).toContainText("Loaded SCCP discovery for production: 1 counterparties, 1 manifests.");
  await expect(page.locator("#bridge-summary")).toContainText(`Bridge: ${PRODUCTION_BRIDGE_ADDRESS}`);
});

test("keeps the contract console viewport-safe on mobile", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await bootConsole(page, { catalog: createAdversarialCatalog() });

  await expectNoHorizontalOverflow(page);
});

test("confirms only generic signed calls and warns on ambiguous ABI defaults", async ({ page }) => {
  const apiState = await bootConsole(page);

  await page.locator("#entrypoint-select").selectOption("listing_config");
  await page.locator("#run-request").click();
  await expect(page.locator("#signed-confirmation-dialog")).toBeHidden();
  await expect(page.locator("#request-status")).toContainText("Request succeeded");

  await page.locator("#entrypoint-select").selectOption("register_asset");
  await page.locator("#payload-input").fill(prettyJsonForTest({
    asset_key: "",
    registrant: null,
    asset: "",
    home_domain: 0,
    decimals: 0,
  }));
  await page.locator("#run-request").click();

  const dialog = page.locator("#signed-confirmation-dialog");
  await expect(dialog).toBeVisible();
  await expect(dialog).toContainText("blank strings");
  await expect(dialog).toContainText("null values");
  await expect(dialog).toContainText("zero numeric fields");
  await dialog.getByRole("button", { name: "Cancel", exact: true }).click();
  await expect(page.locator("#request-status")).toContainText("Cancelled before submission");
  expect(apiState.requests).toHaveLength(0);

  await page.locator("#run-request").click();
  await confirmSignedCall(page);
  await expect.poll(() => apiState.requests.length).toBe(1);
  expect(apiState.requests[0].path).toBe("/api/call");
  expect(apiState.requests[0].body.payload).toMatchObject({
    asset_key: "",
    registrant: null,
    asset: "",
    home_domain: 0,
    decimals: 0,
  });
});

test("rejects malformed generic and bridge advanced payloads before confirmation", async ({ page }) => {
  const apiState = await bootConsole(page);

  await page.locator("#entrypoint-select").selectOption("register_asset");
  await page.locator("#payload-input").fill("{ not valid json");
  await page.locator("#run-request").click();
  await expect(page.locator("#request-status")).toContainText("Payload JSON must be valid JSON");
  await expect(page.locator("#signed-confirmation-dialog")).toBeHidden();
  expect(apiState.requests).toHaveLength(0);

  await page.locator("#proof-submit-input").fill("{}");
  await page.locator("#submit-bridge-proof").click();
  await expect(page.locator("#submission-summary")).toContainText("must include exactly one");
  await expect(page.locator("#signed-confirmation-dialog")).toBeHidden();
  expect(apiState.requests).toHaveLength(0);

  await page.locator("#bridge-message-submit-input").fill(prettyJsonForTest({
    message_bundle: {},
    settlement: "not-an-object",
  }));
  await page.locator("#submit-bridge-message").click();
  await expect(page.locator("#submission-summary")).toContainText("settlement must be an object");
  await expect(page.locator("#signed-confirmation-dialog")).toBeHidden();
  expect(apiState.requests).toHaveLength(0);
});

test("sanitizes sensitive fields in signed confirmation payloads", async ({ page }) => {
  const apiState = await bootConsole(page);

  await page.locator("#entrypoint-select").selectOption("register_asset");
  await page.locator("#payload-input").fill(prettyJsonForTest({
    asset_key: "xor",
    registrant: "i105localbridgeoperator@universal",
    asset: "xor#universal",
    home_domain: 1,
    decimals: 18,
    private_key: "generic-secret-value",
    nested: {
      secret: "nested-secret-value",
      visible: "safe-visible-value",
    },
  }));
  await page.locator("#run-request").click();
  await expect(page.locator("#signed-confirmation-dialog")).toBeVisible();
  await expect(page.locator("#confirmation-payload")).toContainText("safe-visible-value");
  await expect(page.locator("#confirmation-payload")).not.toContainText("generic-secret-value");
  await expect(page.locator("#confirmation-payload")).not.toContainText("nested-secret-value");
  await page.locator("#signed-confirmation-dialog").getByRole("button", { name: "Cancel", exact: true }).click();
  expect(apiState.requests).toHaveLength(0);

  await page.locator("#proof-submit-input").fill(prettyJsonForTest({
    authority: "i105localbridgeoperator@universal",
    private_key: "bridge-secret-value",
    message_bundle: proofBundle(LOOKUP_MESSAGE_ID).response_json,
  }));
  await page.locator("#submit-bridge-proof").click();
  await expect(page.locator("#signed-confirmation-dialog")).toBeVisible();
  await expect(page.locator("#confirmation-payload")).toContainText(LOOKUP_MESSAGE_ID);
  await expect(page.locator("#confirmation-payload")).not.toContainText("bridge-secret-value");
  await page.locator("#signed-confirmation-dialog").getByRole("button", { name: "Cancel", exact: true }).click();
  expect(apiState.requests).toHaveLength(0);
});

test("validates codec-specific recipients and builds bridge requests from labeled fields", async ({ page }) => {
  await bootConsole(page);

  await page.locator("#bridge-action-select").selectOption("lock_to_remote");
  await page.locator("#bridge-route-input").fill("eth_lane");
  await page.locator("#bridge-remote-domain-input").fill("1000");
  await page.locator("#build-bridge-request").click();

  await expect(page.locator("#bridge-validation-summary")).toContainText("Transfer Id is required for lock_to_remote.");
  await expect(page.locator("#bridge-validation-summary")).toContainText("Amount must be greater than zero for lock_to_remote.");

  await page.locator("#bridge-transfer-input").fill("xor_eth_0001");
  await page.locator("#bridge-amount-input").fill("25");
  await page.locator("#bridge-recipient-input").fill("not-an-evm-address");
  await page.locator("#build-bridge-request").click();

  await expect(page.locator("#bridge-validation-summary")).toContainText("Recipient must be a 0x-prefixed 20-byte hex address for the selected EVM lane.");

  await page.locator("#bridge-recipient-input").fill("0x1111111111111111111111111111111111111111");
  await page.locator("#build-bridge-request").click();

  await expect(page.locator("#bridge-summary")).toContainText("Built lock_to_remote from the bridge action form");
  await expect(page.locator("#contract-select")).toHaveValue("bridge.sccp_bridge");
  await expect(page.locator("#entrypoint-select")).toHaveValue("lock_to_remote");
  await expect(page.locator("#payload-input")).toHaveValue(/"route": "eth_lane"/);
  await expect(page.locator("#payload-input")).toHaveValue(/"transfer": "xor_eth_0001"/);
  await expect(page.locator("#payload-input")).toHaveValue(/"amount": 25/);
});

test("persists bridge bookmarks and signed transaction tracking across reloads", async ({ page }) => {
  const apiState = await bootConsole(page);

  await page.locator("#bridge-route-input").fill("eth_lane");
  await page.locator("#bridge-message-id-input").fill(LOOKUP_MESSAGE_ID);
  await page.locator("#bridge-transfer-input").fill("xor_eth_pause_0001");
  await page.locator("#bridge-asset-key-input").fill("xor");
  await page.locator("#bookmark-current-bridge").click();

  await expect(page.locator("#bookmark-route-select")).toContainText("eth_lane");
  await expect(page.locator("#bookmark-message-id-select")).toContainText(LOOKUP_MESSAGE_ID);

  await page.locator("#bridge-action-select").selectOption("pause_route");
  await page.locator("#build-bridge-request").click();
  await page.locator("#run-request").click();
  await expect(page.locator("#signed-confirmation-dialog")).toBeVisible();
  await page.locator("#signed-confirmation-dialog").getByRole("button", { name: "Cancel", exact: true }).click();
  await expect(page.locator("#request-status")).toContainText("Cancelled before submission");
  expect(apiState.requests).toHaveLength(0);

  await page.locator("#run-request").click();
  await confirmSignedCall(page);

  await expect(page.locator("#transaction-history-list")).toContainText(`tx_hash_hex: ${CALL_TX_HASH}`);
  await expect(page.locator("#transaction-history-list")).toContainText("Committed");
  await expect.poll(() => apiState.bridgeInspects.length).toBeGreaterThan(0);
  await expect(page.locator("#bridge-snapshot-preview")).toContainText('"route": "eth_lane"');

  await page.reload();
  await expect(page.locator("#request-status")).toContainText("Loaded 3 environment(s)");
  await expect(page.locator("#bookmark-route-select")).toContainText("eth_lane");
  await expect(page.locator("#bookmark-message-id-select")).toContainText(LOOKUP_MESSAGE_ID);
  await expect(page.locator("#transaction-history-list")).toContainText(`tx_hash_hex: ${CALL_TX_HASH}`);
  await expect(page.locator("#transaction-history-list")).toContainText("Committed");
});

test("renders proof lookups and submission helpers from mocked SCCP responses", async ({ page }) => {
  await bootConsole(page);

  await page.locator("#bridge-route-input").fill("eth_lane");
  await page.locator("#bridge-message-id-input").fill(LOOKUP_MESSAGE_ID);
  await page.locator("#proof-lookup-message-id-input").fill(LOOKUP_MESSAGE_ID);
  await page.locator("#lookup-sccp-all").click();

  await expect(page.locator("#proof-lookup-summary")).toContainText(`Loaded proof surfaces for ${LOOKUP_MESSAGE_ID}`);
  await expect(page.locator("#sccp-bundle-preview")).toContainText('"message_id":');
  await expect(page.locator("#sccp-artifact-preview")).toContainText("0xVerifierETH");
  await expect(page.locator("#sccp-job-preview")).toContainText('"payload_kind": "Transfer"');
  await expect(page.locator("#proof-submission-package-preview")).toContainText('"finality_checkpoint": "12345"');
  await expect(page.locator("#recent-proof-lookup-select")).toContainText(LOOKUP_MESSAGE_ID);

  await page.locator("#load-looked-up-bundle").click();
  await expect(page.locator("#proof-submit-input")).toHaveValue(new RegExp(LOOKUP_MESSAGE_ID));
  await expect(page.locator("#bridge-message-submit-input")).toHaveValue(new RegExp(LOOKUP_MESSAGE_ID));

  await page.locator("#insert-settlement-helper").click();
  await expect(page.locator("#bridge-message-submit-input")).toHaveValue(/"entrypoint": "finalize_inbound"/);
  await expect(page.locator("#bridge-message-submit-input")).toHaveValue(new RegExp(LOCAL_BRIDGE_ADDRESS));
});

test("submits proof and bridge message payloads and persists request metadata", async ({ page }) => {
  const apiState = await bootConsole(page);

  await page.locator("#bridge-route-input").fill("eth_lane");
  await page.locator("#bridge-message-id-input").fill(LOOKUP_MESSAGE_ID);
  await page.locator("#proof-lookup-message-id-input").fill(LOOKUP_MESSAGE_ID);
  await page.locator("#lookup-sccp-all").click();
  await page.locator("#load-looked-up-bundle").click();

  await page.locator("#submit-bridge-proof").click();
  await expect(page.locator("#signed-confirmation-dialog")).toBeVisible();
  await page.locator("#signed-confirmation-dialog").getByRole("button", { name: "Cancel", exact: true }).click();
  await expect(page.locator("#submission-summary")).toContainText("cancelled before submission");
  expect(apiState.requests).toHaveLength(0);

  await page.locator("#submit-bridge-proof").click();
  await confirmSignedCall(page);
  await expect(page.locator("#transaction-history-list")).toContainText(PROOF_TX_HASH);

  await page.locator("#insert-settlement-helper").click();
  await page.locator("#submit-bridge-message").click();
  await confirmSignedCall(page);
  await expect(page.locator("#transaction-history-list")).toContainText(MESSAGE_TX_HASH);
  await expect.poll(() => apiState.requests.length).toBe(2);

  expect(apiState.requests.map((entry) => entry.path)).toEqual([
    "/api/bridge/proofs/submit",
    "/api/bridge/messages",
  ]);
  expect(apiState.requests[1].body.settlement.route).toBe("eth_lane");
  expect(apiState.requests[1].body.message_bundle.commitment.message_id).toBe(LOOKUP_MESSAGE_ID);

  await expect(page.locator("#bookmark-route-select")).toContainText("eth_lane");
  await expect(page.locator("#bookmark-message-id-select")).toContainText(LOOKUP_MESSAGE_ID);

  const recentRequests = await readLocalStorageJson(page, RECENT_REQUESTS_KEY);
  expect(recentRequests[0].requestPath).toBe("/api/bridge/messages");
  expect(recentRequests[0].requestMetadata.bridgeIds.routes[0]).toBe("eth_lane");
  expect(recentRequests[0].requestMetadata.bridgeIds.messageIds[0]).toBe(LOOKUP_MESSAGE_ID);
  expect(recentRequests[0].requestMetadata.topLevelKeys).toContain("message_bundle");
  expect(recentRequests[0].requestMetadata.topLevelKeys).toContain("settlement");
});

test("marks tracked transactions as timed out when no terminal status arrives", async ({ page }) => {
  await page.addInitScript(() => {
    window.__SORASWAP_CONTRACT_CONSOLE_CONFIG__ = {
      transactionPollIntervalMs: 20,
      transactionPollTimeoutMs: 60,
    };
  });

  const apiState = await bootConsole(page, {
    statusResponseFactory: () => ({
      ok: true,
      upstream_status: 200,
      status_kind: "Pending",
      response_json: {
        status: "Pending",
      },
    }),
  });

  await page.locator("#bridge-action-select").selectOption("pause_route");
  await page.locator("#bridge-route-input").fill("timeout_route");
  await page.locator("#build-bridge-request").click();
  await page.locator("#run-request").click();
  await confirmSignedCall(page);

  await expect(page.locator("#transaction-history-list")).toContainText(CALL_TX_HASH);
  await expect(page.locator("#transaction-history-list")).toContainText("TimedOut");
  await expect(page.locator("#transaction-history-list")).toContainText("Tracking timed out before a terminal transaction status was returned.");
  await expect(page.locator("#transaction-summary")).toContainText("Timed out: 1");
  await expect.poll(() => apiState.statusLookups.length).toBeGreaterThan(0);

  const trackedStatuses = await readLocalStorageJson(page, TRANSACTION_STATUSES_KEY);
  expect(trackedStatuses[CALL_TX_HASH].statusKind).toBe("TimedOut");
  expect(trackedStatuses[CALL_TX_HASH].terminal).toBe(true);
  expect(trackedStatuses[CALL_TX_HASH].timedOut).toBe(true);
});
