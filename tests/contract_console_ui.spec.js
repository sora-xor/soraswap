const { test, expect } = require("@playwright/test");

const LOCAL_BRIDGE_ADDRESS = "tairac1localbridge000000000000000000000000000000000000";
const TESTNET_BRIDGE_ADDRESS = "tairac1testnetbridge000000000000000000000000000000000";
const PRODUCTION_BRIDGE_ADDRESS = "prodc1bridge0000000000000000000000000000000000000000";
const CALL_TX_HASH = "c0".repeat(32);
const PROOF_TX_HASH = "d1".repeat(32);
const MESSAGE_TX_HASH = "e2".repeat(32);
const LOOKUP_MESSAGE_ID = "ab".repeat(32);
const DESTINATION_PROOF_B64 = Buffer.from("destination-proof-fixture").toString("base64");
const NATIVE_PROOF_B64 = Buffer.from("native-proof-fixture").toString("base64");
const RECENT_REQUESTS_KEY = "soraswap.contractConsole.recentRequests.v1";
const TRANSACTION_STATUSES_KEY = "soraswap.contractConsole.transactionStatuses.v1";
const BRIDGE_BOOKMARKS_KEY = "soraswap.contractConsole.bridgeBookmarks.v1";
const PROOF_LOOKUPS_KEY = "soraswap.contractConsole.proofLookups.v1";

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
        { name: "asset_key", type_name: "Name" },
      ],
      return_type: "MirrorAsset",
    },
    {
      name: "mirror_route",
      kind: "View",
      permission: "",
      params: [
        { name: "route", type_name: "Name" },
      ],
      return_type: "MirrorRoute",
    },
    {
      name: "register_bridge_asset",
      kind: "Kotoage",
      permission: "AssetOps",
      params: [
        { name: "asset_key", type_name: "Name" },
        { name: "asset", type_name: "AssetDefinitionId" },
        { name: "home_domain", type_name: "int" },
        { name: "decimals", type_name: "int" },
      ],
      return_type: "Unit",
    },
    {
      name: "bind_asset_vault",
      kind: "Kotoage",
      permission: "Entry",
      params: [
        { name: "asset_key", type_name: "Name" },
        { name: "vault_account", type_name: "AccountId" },
      ],
      return_type: "Unit",
    },
    {
      name: "activate_route",
      kind: "Kotoage",
      permission: "Entry",
      params: [
        { name: "route", type_name: "Name" },
        { name: "asset_key", type_name: "Name" },
        { name: "remote_domain", type_name: "int" },
      ],
      return_type: "Unit",
    },
    {
      name: "activate_route_governed",
      kind: "Kotoage",
      permission: "Entry",
      params: [
        { name: "message_id", type_name: "Name" },
        { name: "route", type_name: "Name" },
        { name: "asset_key", type_name: "Name" },
        { name: "remote_domain", type_name: "int" },
      ],
      return_type: "Unit",
    },
    {
      name: "pause_route",
      kind: "Kotoage",
      permission: "Entry",
      params: [
        { name: "route", type_name: "Name" },
      ],
      return_type: "Unit",
    },
    {
      name: "resume_route",
      kind: "Kotoage",
      permission: "Entry",
      params: [
        { name: "route", type_name: "Name" },
      ],
      return_type: "Unit",
    },
    {
      name: "lock_to_remote",
      kind: "Kotoage",
      permission: "AssetOps",
      params: [
        { name: "route", type_name: "Name" },
        { name: "transfer", type_name: "Name" },
        { name: "recipient", type_name: "Name" },
        { name: "amount", type_name: "quantity" },
      ],
      return_type: "int",
    },
    {
      name: "finalize_inbound",
      kind: "Kotoage",
      permission: "AssetOps",
      params: [
        { name: "route", type_name: "Name" },
        { name: "message_id", type_name: "Name" },
        { name: "recipient", type_name: "AccountId" },
        { name: "amount", type_name: "quantity" },
      ],
      return_type: "Unit",
    },
  ];
}

function makeBridgeContract(address, manifestPath) {
  return {
    contract_key: "bridge.sccp_bridge",
    contract_address: address,
    dataspace_alias: "universal",
    dataspace_id: "0",
    deploy_nonce: 7,
    verification: "verified",
    contract_source: "contracts/bridge/sccp_bridge.ko",
    manifest_path: manifestPath,
    entrypoints: bridgeEntrypoints(),
  };
}

function createCatalog() {
  return {
    repo_name: "soraswap",
    repo_root: "soraswap",
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
            dataspace_alias: "universal",
            dataspace_id: "0",
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
          source: "cli:taira.client.toml",
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
          source: "cli:production.client.toml",
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
  catalog.repo_name = `soraswap-${longToken}`;
  catalog.repo_root = `soraswap-${longToken}`;
  const local = catalog.environments[0];
  local.name = `local-${longToken}`;
  local.torii_url = `https://${longToken}.example.invalid/${longToken}`;
  local.chain_fingerprint.chain = `chain-${longToken}`;
  local.signer.source = `cli:${longToken}.client.toml`;
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
  const capabilities = {
    ok: true,
    upstream_status: 200,
    response_json: {
      version: 1,
      registry_path: "/v1/sccp/registry",
      message_bundle_path: "/v1/sccp/proofs/message/{message_id}",
      proof_request_path: "/v1/sccp/proof-requests/{message_id}",
      recent_messages_path: "/v1/sccp/messages/recent",
      proof_submit_path: "/v1/bridge/proofs/submit",
      native_message_submit_path: "/v1/bridge/messages",
    },
  };
  return {
    local: structuredClone(capabilities),
    testnet: structuredClone(capabilities),
    production: structuredClone(capabilities),
  };
}

function registryLane(target, routeId) {
  return {
    lane_id: { source: "sora_taira", target },
    native_trust_anchors: [],
    current_native_trust_anchor_hash: null,
    routes: [
      {
        lane_id: { source: "sora_taira", target },
        route_id: routeId,
        asset_key: "xor",
        revision: 1,
        activation: "bidirectional",
      },
    ],
  };
}

function registriesByEnvironment() {
  return {
    local: {
      ok: true,
      upstream_status: 200,
      response_json: {
        version: 1,
        lanes: [
          registryLane("ethereum_sepolia", "eth_lane"),
          registryLane("tron_nile", "tron_lane"),
        ],
      },
    },
    testnet: {
      ok: true,
      upstream_status: 200,
      response_json: {
        version: 1,
        lanes: [registryLane("ethereum_sepolia", "eth_testnet_lane")],
      },
    },
    production: {
      ok: true,
      upstream_status: 200,
      response_json: {
        version: 1,
        lanes: [registryLane("ethereum_mainnet", "eth_mainnet_lane")],
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
        target_domain: 1,
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
          dest_domain: 1,
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

function proofRequest() {
  return {
    ok: true,
    upstream_status: 200,
    response_json: {
      version: 1,
      backend: "ethereum_groth16_bn254",
      source_network: "sora_taira",
      target_network: "ethereum_sepolia",
      verifier_key_hash: "04".repeat(32),
      statement_hash: "05".repeat(32),
      request_hash: "06".repeat(32),
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
  const registryMap = overrides.registryMap || registriesByEnvironment();
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

    if (path.startsWith("/api/assets/definitions/")) {
      const selector = decodeURIComponent(path.slice("/api/assets/definitions/".length));
      const assetResponse = typeof overrides.assetDefinitionResponseFactory === "function"
        ? overrides.assetDefinitionResponseFactory({ selector, environment })
        : {
          ok: true,
          upstream_status: 200,
          response_json: {
            id: "6TEAJqbb8oEPmLncoNiMRbLEK6tw",
            alias: selector,
            spec: { scale: 9 },
            alias_binding: {
              alias: selector,
              status: "permanent",
              bound_at_ms: 1,
            },
          },
        };
      await fulfillJson(route, assetResponse, assetResponse.ok === true ? 200 : 502);
      return;
    }

    if (path === "/api/sccp/capabilities") {
      await fulfillJson(route, capabilityMap[environment] || capabilityMap.local);
      return;
    }

    if (path === "/api/sccp/registry") {
      await fulfillJson(route, registryMap[environment] || registryMap.local);
      return;
    }

    if (/^\/api\/sccp\/proofs\/message\/[0-9a-f]{64}$/.test(path)) {
      const messageId = path.split("/").pop();
      await fulfillJson(route, proofBundle(messageId));
      return;
    }

    if (/^\/api\/sccp\/proof-requests\/[0-9a-f]{64}$/.test(path)) {
      await fulfillJson(route, proofRequest());
      return;
    }

    if (path === "/api/pipeline/transactions/status") {
      const hash = url.searchParams.get("hash");
      const scope = url.searchParams.get("scope");
      apiState.statusLookups.push({ environment, hash, scope });
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
        status_scope: scope,
        status_resolved_from: "state",
        status_block_height: 91,
        response_json: {
          hash,
          status: { kind: "Committed", block_height: 91 },
          scope,
          resolved_from: "state",
        },
      });
      return;
    }

    if (path === "/api/bridge/inspect" && request.method() === "POST") {
      const body = JSON.parse(request.postData() || "{}");
      apiState.bridgeInspects.push(body);
      const bridgeInspectResponse = typeof overrides.bridgeInspectResponseFactory === "function"
        ? overrides.bridgeInspectResponseFactory({ body, attempt: apiState.bridgeInspects.length })
        : {
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
            response_json: [body.route || "eth_lane", 1],
          },
          {
            entrypoint: "route_config",
            response_json: {
              route: body.route || "eth_lane",
              enabled: true,
            },
          },
        ],
      };
      await fulfillJson(route, bridgeInspectResponse, bridgeInspectResponse.ok === true ? 200 : 502);
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
        status_kind: "Queued",
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
        status_kind: "Queued",
        detached_signing: {
          prepared: true,
          locally_signed: true,
          submitted: true,
          private_key_forwarded: false,
          fallback_used: false,
        },
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
        status_kind: "Queued",
        detached_signing: {
          prepared: true,
          locally_signed: true,
          submitted: true,
          private_key_forwarded: false,
          fallback_used: false,
        },
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
  await expect(page.locator("#contract-dataspace-display")).toHaveText("universal (0)");
  await expect(page.locator("#bridge-summary")).toContainText(`Bridge: ${LOCAL_BRIDGE_ADDRESS}`);
  await expect(page.locator("#proof-status-summary")).toContainText("Loaded SCCP V1 discovery for local: 2 governed lanes, 2 retained route revisions.");
  await expect(page.locator("#sccp-counterparty-list")).toContainText("ethereum_sepolia");
  await expect(page.locator("#sccp-counterparty-list")).toContainText("Codec: evm_hex");

  await page.locator("#environment-select").selectOption("testnet");

  await expect(page.locator("#environment-summary")).toContainText("Torii: https://taira.sora.org (deployment)");
  await expect(page.locator("#proof-status-summary")).toContainText("Loaded SCCP V1 discovery for testnet: 1 governed lanes, 1 retained route revisions.");
  await expect(page.locator("#transaction-summary")).toContainText("Remote history unavailable: tx_history_auth_unavailable");
  await expect(page.locator("#bridge-summary")).toContainText(`Bridge: ${TESTNET_BRIDGE_ADDRESS}`);

  await page.locator("#environment-select").selectOption("production");

  await expect(page.locator("#environment-summary")).toContainText("Torii: https://production.example.invalid (deployment)");
  await expect(page.locator("#environment-summary")).toContainText("Signer: configured (cli:production.client.toml)");
  await expect(page.locator("#proof-status-summary")).toContainText("Loaded SCCP V1 discovery for production: 1 governed lanes, 1 retained route revisions.");
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

  await page.locator("#entrypoint-select").selectOption("register_bridge_asset");
  await page.locator("#template-payload").click();
  expect(JSON.parse(await page.locator("#payload-input").inputValue())).toEqual({
    asset_key: "",
    asset: "",
    home_domain: "0",
    decimals: "0",
  });
  await page.locator("#payload-input").fill(prettyJsonForTest({
    asset_key: "",
    asset: null,
    home_domain: "0",
    decimals: "0",
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
    asset: null,
    home_domain: "0",
    decimals: "0",
  });
});

test("rejects malformed generic and bridge advanced payloads before confirmation", async ({ page }) => {
  const apiState = await bootConsole(page);

  await page.locator("#entrypoint-select").selectOption("register_bridge_asset");
  await page.locator("#payload-input").fill("{ not valid json");
  await page.locator("#run-request").click();
  await expect(page.locator("#request-status")).toContainText("Payload JSON must be valid JSON");
  await expect(page.locator("#signed-confirmation-dialog")).toBeHidden();
  expect(apiState.requests).toHaveLength(0);

  await page.locator("#proof-submit-input").fill("{}");
  await page.locator("#submit-bridge-proof").click();
  await expect(page.locator("#submission-summary")).toContainText("destination_proof_b64 must be non-empty canonical padded base64");
  await expect(page.locator("#signed-confirmation-dialog")).toBeHidden();
  expect(apiState.requests).toHaveLength(0);

  await page.locator("#bridge-message-submit-input").fill(prettyJsonForTest({
    message_bundle: {},
    settlement: "not-an-object",
  }));
  await page.locator("#submit-bridge-message").click();
  await expect(page.locator("#submission-summary")).toContainText("retired or unsupported fields: message_bundle, settlement");
  await expect(page.locator("#signed-confirmation-dialog")).toBeHidden();
  expect(apiState.requests).toHaveLength(0);
});

test("sanitizes sensitive fields in signed confirmation payloads", async ({ page }) => {
  const apiState = await bootConsole(page);

  await page.locator("#entrypoint-select").selectOption("register_bridge_asset");
  await page.locator("#payload-input").fill(prettyJsonForTest({
    asset_key: "xor",
    asset: "xor#universal",
    home_domain: "1",
    decimals: "18",
    private_key: "generic-secret-value",
    "private-key": "dash-secret-value",
    nested: {
      secret: "nested-secret-value",
      "private key": "space-secret-value",
      apiKey: "api-key-secret-value",
      authorization: "bearer-secret-value",
      password: "password-secret-value",
      visible: "safe-visible-value",
    },
  }));
  await page.locator("#run-request").click();
  await expect(page.locator("#signed-confirmation-dialog")).toBeVisible();
  await expect(page.locator("#confirmation-payload")).toContainText("safe-visible-value");
  await expect(page.locator("#confirmation-payload")).not.toContainText("generic-secret-value");
  await expect(page.locator("#confirmation-payload")).not.toContainText("dash-secret-value");
  await expect(page.locator("#confirmation-payload")).not.toContainText("space-secret-value");
  await expect(page.locator("#confirmation-payload")).not.toContainText("nested-secret-value");
  await expect(page.locator("#confirmation-payload")).not.toContainText("api-key-secret-value");
  await expect(page.locator("#confirmation-payload")).not.toContainText("bearer-secret-value");
  await expect(page.locator("#confirmation-payload")).not.toContainText("password-secret-value");
  await page.locator("#signed-confirmation-dialog").getByRole("button", { name: "Cancel", exact: true }).click();
  expect(apiState.requests).toHaveLength(0);

  await page.locator("#proof-submit-input").fill(prettyJsonForTest({
    authority: "i105localbridgeoperator@universal",
    private_key: "bridge-secret-value",
    destination_proof_b64: DESTINATION_PROOF_B64,
  }));
  await page.locator("#submit-bridge-proof").click();
  await expect(page.locator("#submission-summary")).toContainText("retired or unsupported fields: private_key");
  await expect(page.locator("#signed-confirmation-dialog")).toBeHidden();
  expect(apiState.requests).toHaveLength(0);
});

test("validates codec-specific recipients and builds bridge requests from labeled fields", async ({ page }) => {
  await bootConsole(page);

  await page.locator("#bridge-action-select").selectOption("lock_to_remote");
  await page.locator("#bridge-route-input").fill("eth_lane");
  await page.locator("#bridge-remote-domain-input").fill("1");
  await page.locator("#build-bridge-request").click();

  await expect(page.locator("#bridge-validation-summary")).toContainText("Transfer Id is required for lock_to_remote.");
  await expect(page.locator("#bridge-validation-summary")).toContainText("Amount must be a canonical positive quantity string for lock_to_remote.");

  await page.locator("#bridge-transfer-input").fill("xor_eth_0001");
  await page.locator("#bridge-amount-input").fill("0.25");
  await page.locator("#bridge-recipient-input").fill("not-an-evm-address");
  await page.locator("#build-bridge-request").click();

  await expect(page.locator("#bridge-validation-summary")).toContainText("Recipient must be a 0x-prefixed 20-byte hex address for the selected EVM lane.");

  await page.locator("#bridge-recipient-input").fill("0x1111111111111111111111111111111111111111");
  await page.locator("#build-bridge-request").click();

  await expect(page.locator("#bridge-summary")).toContainText("Built lock_to_remote from the bridge action form");
  await expect(page.locator("#contract-select")).toHaveValue("bridge.sccp_bridge");
  await expect(page.locator("#entrypoint-select")).toHaveValue("lock_to_remote");
  expect(JSON.parse(await page.locator("#payload-input").inputValue())).toEqual({
    route: "eth_lane",
    transfer: "xor_eth_0001",
    recipient: "0x1111111111111111111111111111111111111111",
    amount: "0.25",
  });

  await page.locator("#bridge-action-select").selectOption("register_bridge_asset");
  await page.locator("#bridge-asset-key-input").fill("xor");
  await page.locator("#bridge-asset-definition-input").fill("xor#universal");
  await page.locator("#bridge-home-domain-input").fill("0");
  await expect(page.locator("#bridge-decimals-input")).toHaveAttribute("readonly", "");
  await expect(page.locator("#bridge-decimals-input")).toHaveValue("9");
  await page.locator("#build-bridge-request").click();
  expect(JSON.parse(await page.locator("#payload-input").inputValue())).toEqual({
    asset_key: "xor",
    asset: "xor#universal",
    home_domain: "0",
    decimals: "9",
  });

  await page.locator("#bridge-action-select").selectOption("bind_asset_vault");
  await page.locator("#build-bridge-request").click();
  expect(JSON.parse(await page.locator("#payload-input").inputValue())).toEqual({
    asset_key: "xor",
    vault_account: "i105localbridgeoperator@universal",
  });

  await page.locator("#bridge-action-select").selectOption("activate_route");
  await page.locator("#build-bridge-request").click();
  expect(JSON.parse(await page.locator("#payload-input").inputValue())).toEqual({
    route: "eth_lane",
    asset_key: "xor",
    remote_domain: "1",
  });
});

test("retains a same-identity bridge snapshot when a routed refresh is incomplete", async ({ page }) => {
  await bootConsole(page, {
    bridgeInspectResponseFactory: ({ body, attempt }) => attempt === 1
      ? {
        ok: true,
        contract: { contract_address: LOCAL_BRIDGE_ADDRESS },
        requested_keys: {
          asset_key: body.asset_key || null,
          route: body.route || null,
          transfer: body.transfer || null,
          message_id: body.message_id || null,
        },
        views: [{ entrypoint: "mirror_route", response_json: [body.route || "eth_lane", 1] }],
      }
      : { ok: false, error: "incomplete routed read" },
  });

  await page.locator("#bridge-route-input").fill("eth_lane");
  await page.locator("#refresh-bridge-snapshot").click();
  await expect(page.locator("#bridge-summary")).toContainText("Bridge snapshot loaded");
  const completeSnapshot = await page.locator("#bridge-snapshot-preview").textContent();

  await page.locator("#refresh-bridge-snapshot").click();
  await expect(page.locator("#bridge-summary")).toContainText("retaining the last complete result");
  await expect(page.locator("#bridge-snapshot-preview")).toHaveText(completeSnapshot);
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
  await expect(page.locator("#transaction-history-list")).toContainText("Committed block: 91");
  await expect(page.locator("#transaction-history-list")).toContainText("Resolved from: state");
  await expect.poll(() => apiState.statusLookups.length).toBeGreaterThan(0);
  expect(apiState.statusLookups.every((lookup) => lookup.scope === "global")).toBe(true);
  await expect.poll(() => apiState.bridgeInspects.length).toBeGreaterThan(0);
  await expect(page.locator("#bridge-snapshot-preview")).toContainText('"route": "eth_lane"');

  await page.reload();
  await expect(page.locator("#request-status")).toContainText("Loaded 3 environment(s)");
  await expect(page.locator("#bookmark-route-select")).toContainText("eth_lane");
  await expect(page.locator("#bookmark-message-id-select")).toContainText(LOOKUP_MESSAGE_ID);
  await expect(page.locator("#transaction-history-list")).toContainText(`tx_hash_hex: ${CALL_TX_HASH}`);
  await expect(page.locator("#transaction-history-list")).toContainText("Committed");
});

test("clears browser-local operator state in one action", async ({ page }) => {
  await bootConsole(page);

  await page.locator("#bridge-route-input").fill("eth_lane");
  await page.locator("#bridge-message-id-input").fill(LOOKUP_MESSAGE_ID);
  await page.locator("#bridge-transfer-input").fill("xor_eth_clear_0001");
  await page.locator("#bridge-asset-key-input").fill("xor");
  await page.locator("#bookmark-current-bridge").click();

  await page.locator("#proof-lookup-message-id-input").fill(LOOKUP_MESSAGE_ID);
  await page.locator("#lookup-sccp-all").click();
  await expect(page.locator("#proof-lookup-summary")).toContainText(`Loaded closed SCCP V1 proof surfaces for ${LOOKUP_MESSAGE_ID}`);

  await page.locator("#bridge-action-select").selectOption("pause_route");
  await page.locator("#build-bridge-request").click();
  await page.locator("#run-request").click();
  await confirmSignedCall(page);
  await expect(page.locator("#transaction-history-list")).toContainText(`tx_hash_hex: ${CALL_TX_HASH}`);
  await expect(page.locator("#bookmark-route-select")).toContainText("eth_lane");
  await expect(page.locator("#recent-proof-lookup-select")).toContainText(LOOKUP_MESSAGE_ID);

  await page.locator("#clear-operator-state").click();

  await expect(page.locator("#request-status")).toContainText("Cleared browser-local operator state.");
  await expect(page.locator("#transaction-history-list")).toContainText("No signed actions have been recorded in this browser yet.");
  await expect(page.locator("#bookmark-route-select")).not.toContainText("eth_lane");
  await expect(page.locator("#recent-proof-lookup-select")).not.toContainText(LOOKUP_MESSAGE_ID);
  await expect(page.locator("#proof-lookup-summary")).toContainText("Enter a 64-character lowercase nonzero message id");

  await expect.poll(() => readLocalStorageJson(page, RECENT_REQUESTS_KEY)).toEqual([]);
  await expect.poll(() => readLocalStorageJson(page, TRANSACTION_STATUSES_KEY)).toEqual({});
  await expect.poll(() => readLocalStorageJson(page, BRIDGE_BOOKMARKS_KEY)).toEqual({
    assetKeys: [],
    routes: [],
    transfers: [],
    messageIds: [],
  });
  await expect.poll(() => readLocalStorageJson(page, PROOF_LOOKUPS_KEY)).toEqual([]);
});

test("renders canonical bundle and state-derived proof request from mocked SCCP responses", async ({ page }) => {
  await bootConsole(page);

  await page.locator("#bridge-route-input").fill("eth_lane");
  await page.locator("#bridge-message-id-input").fill(LOOKUP_MESSAGE_ID);
  await page.locator("#proof-lookup-message-id-input").fill(LOOKUP_MESSAGE_ID);
  await page.locator("#lookup-sccp-all").click();

  await expect(page.locator("#proof-lookup-summary")).toContainText(`Loaded closed SCCP V1 proof surfaces for ${LOOKUP_MESSAGE_ID}`);
  await expect(page.locator("#sccp-bundle-preview")).toContainText('"message_id":');
  await expect(page.locator("#sccp-proof-request-preview")).toContainText('"target_network": "ethereum_sepolia"');
  await expect(page.locator("#sccp-proof-request-preview")).toContainText('"request_hash":');
  await expect(page.locator("#recent-proof-lookup-select")).toContainText(LOOKUP_MESSAGE_ID);

  await page.locator("#build-proof-submit-template").click();
  await expect(page.locator("#proof-submit-input")).toHaveValue(/"destination_proof_b64":/);
  await expect(page.locator("#proof-submit-input")).not.toHaveValue(/message_bundle/);
  await page.locator("#build-bridge-message-template").click();
  await expect(page.locator("#bridge-message-submit-input")).toHaveValue(/"native_proof_b64":/);
  await expect(page.locator("#bridge-message-submit-input")).not.toHaveValue(/settlement/);
});

test("submits proof and bridge message payloads and persists request metadata", async ({ page }) => {
  const apiState = await bootConsole(page);

  await page.locator("#proof-submit-input").fill(prettyJsonForTest({
    authority: "i105localbridgeoperator@universal",
    destination_proof_b64: DESTINATION_PROOF_B64,
  }));
  await page.locator("#bridge-message-submit-input").fill(prettyJsonForTest({
    authority: "i105localbridgeoperator@universal",
    native_proof_b64: NATIVE_PROOF_B64,
  }));

  await page.locator("#submit-bridge-proof").click();
  await expect(page.locator("#signed-confirmation-dialog")).toBeVisible();
  await page.locator("#signed-confirmation-dialog").getByRole("button", { name: "Cancel", exact: true }).click();
  await expect(page.locator("#submission-summary")).toContainText("cancelled before submission");
  expect(apiState.requests).toHaveLength(0);

  await page.locator("#submit-bridge-proof").click();
  await confirmSignedCall(page);
  await expect(page.locator("#transaction-history-list")).toContainText(PROOF_TX_HASH);

  await page.locator("#submit-bridge-message").click();
  await confirmSignedCall(page);
  await expect(page.locator("#transaction-history-list")).toContainText(MESSAGE_TX_HASH);
  await expect.poll(() => apiState.requests.length).toBe(2);

  expect(apiState.requests.map((entry) => entry.path)).toEqual([
    "/api/bridge/proofs/submit",
    "/api/bridge/messages",
  ]);
  expect(apiState.requests[0].body.destination_proof_b64).toBe(DESTINATION_PROOF_B64);
  expect(apiState.requests[1].body.native_proof_b64).toBe(NATIVE_PROOF_B64);
  expect(apiState.requests[0].body).not.toHaveProperty("private_key");
  expect(apiState.requests[1].body).not.toHaveProperty("private_key");

  const recentRequests = await readLocalStorageJson(page, RECENT_REQUESTS_KEY);
  expect(recentRequests[0].requestPath).toBe("/api/bridge/messages");
  expect(recentRequests[0].requestMetadata.topLevelKeys).toContain("native_proof_b64");
  expect(recentRequests[0].requestMetadata.topLevelKeys).not.toContain("message_bundle");
  expect(recentRequests[0].requestMetadata.topLevelKeys).not.toContain("settlement");
});

test("marks tracked transactions as timed out when no terminal status arrives", async ({ page }) => {
  await page.addInitScript(() => {
    window.__SORASWAP_CONTRACT_CONSOLE_CONFIG__ = {
      transactionPollIntervalMs: 20,
      transactionPollTimeoutMs: 60,
    };
  });

  const apiState = await bootConsole(page, {
    statusResponseFactory: ({ hash }) => ({
      ok: true,
      upstream_status: 200,
      status_kind: "Queued",
      status_scope: "global",
      status_resolved_from: "queue",
      response_json: {
        hash,
        status: { kind: "Queued" },
        scope: "global",
        resolved_from: "queue",
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
  expect(apiState.statusLookups.every((lookup) => lookup.scope === "global")).toBe(true);

  const trackedStatuses = await readLocalStorageJson(page, TRANSACTION_STATUSES_KEY);
  expect(trackedStatuses[CALL_TX_HASH].statusKind).toBe("TimedOut");
  expect(trackedStatuses[CALL_TX_HASH].terminal).toBe(true);
  expect(trackedStatuses[CALL_TX_HASH].timedOut).toBe(true);
});
