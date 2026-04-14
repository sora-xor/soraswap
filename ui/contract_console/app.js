const BRIDGE_CONTRACT_KEY = "bridge.sccp_bridge";
const DEFAULT_GAS_LIMIT = 100000;
const DEFAULT_TRANSACTION_POLL_INTERVAL_MS = 4000;
const DEFAULT_TRANSACTION_POLL_TIMEOUT_MS = 5 * 60 * 1000;
const TRANSACTION_TIMEOUT_STATUS = "TimedOut";
const SUCCESS_STATUSES = new Set(["Approved", "Committed", "Applied"]);
const FAILURE_STATUSES = new Set(["Rejected", "Expired"]);
const STORAGE_KEYS = {
  recentRequests: "soraswap.contractConsole.recentRequests.v1",
  transactionStatuses: "soraswap.contractConsole.transactionStatuses.v1",
  bridgeBookmarks: "soraswap.contractConsole.bridgeBookmarks.v1",
  proofLookups: "soraswap.contractConsole.proofLookups.v1",
};

const state = {
  catalog: null,
  environments: [],
  currentEnvironment: null,
  currentContracts: [],
  filteredContracts: [],
  currentContract: null,
  currentEntrypoint: null,
  bridgeSnapshot: null,
  sccpCapabilities: null,
  sccpManifests: null,
  proofLookup: {
    bundle: null,
    artifact: null,
    job: null,
  },
  remoteTransactionHistory: null,
  pollTimers: new Map(),
  local: {
    recentRequests: loadStorage(STORAGE_KEYS.recentRequests, []),
    transactionStatuses: loadStorage(STORAGE_KEYS.transactionStatuses, {}),
    bridgeBookmarks: loadStorage(STORAGE_KEYS.bridgeBookmarks, defaultBridgeBookmarks()),
    proofLookups: loadStorage(STORAGE_KEYS.proofLookups, []),
  },
};

const environmentSelect = document.querySelector("#environment-select");
const environmentSummary = document.querySelector("#environment-summary");
const contractFilter = document.querySelector("#contract-filter");
const contractSelect = document.querySelector("#contract-select");
const contractAddressDisplay = document.querySelector("#contract-address-display");
const contractDataspaceDisplay = document.querySelector("#contract-dataspace-display");
const contractDeployNonceDisplay = document.querySelector("#contract-deploy-nonce-display");
const contractVerificationDisplay = document.querySelector("#contract-verification-display");
const contractSourceDisplay = document.querySelector("#contract-source-display");
const contractManifestDisplay = document.querySelector("#contract-manifest-display");
const entrypointSelect = document.querySelector("#entrypoint-select");
const entrypointSummary = document.querySelector("#entrypoint-summary");
const modeDisplay = document.querySelector("#mode-display");
const gasLimitInput = document.querySelector("#gas-limit-input");
const authorityInput = document.querySelector("#authority-input");
const contractAddressInput = document.querySelector("#contract-address-input");
const payloadInput = document.querySelector("#payload-input");
const requestStatus = document.querySelector("#request-status");
const requestPreview = document.querySelector("#request-preview");
const responsePreview = document.querySelector("#response-preview");
const refreshCatalogButton = document.querySelector("#refresh-catalog");
const templatePayloadButton = document.querySelector("#template-payload");
const clearPayloadButton = document.querySelector("#clear-payload");
const runRequestButton = document.querySelector("#run-request");
const copyRequestButton = document.querySelector("#copy-request");
const copyResponseButton = document.querySelector("#copy-response");

const transactionSummary = document.querySelector("#transaction-summary");
const refreshTransactionHistoryButton = document.querySelector("#refresh-transaction-history");
const clearLocalHistoryButton = document.querySelector("#clear-local-history");
const transactionHistoryList = document.querySelector("#transaction-history-list");
const remoteTransactionHistoryPreview = document.querySelector("#remote-transaction-history-preview");

const bridgeSummary = document.querySelector("#bridge-summary");
const bridgeAssetKeyInput = document.querySelector("#bridge-asset-key-input");
const bridgeRouteInput = document.querySelector("#bridge-route-input");
const bridgeTransferInput = document.querySelector("#bridge-transfer-input");
const bridgeMessageIdInput = document.querySelector("#bridge-message-id-input");
const bookmarkCurrentBridgeButton = document.querySelector("#bookmark-current-bridge");
const clearBridgeBookmarksButton = document.querySelector("#clear-bridge-bookmarks");
const bookmarkAssetKeySelect = document.querySelector("#bookmark-asset-key-select");
const bookmarkRouteSelect = document.querySelector("#bookmark-route-select");
const bookmarkTransferSelect = document.querySelector("#bookmark-transfer-select");
const bookmarkMessageIdSelect = document.querySelector("#bookmark-message-id-select");
const selectBridgeContractButton = document.querySelector("#select-bridge-contract");
const refreshBridgeSnapshotButton = document.querySelector("#refresh-bridge-snapshot");
const bridgeSnapshotPreview = document.querySelector("#bridge-snapshot-preview");
const copyBridgeSnapshotButton = document.querySelector("#copy-bridge-snapshot");
const bridgeTemplateButtons = Array.from(document.querySelectorAll("[data-bridge-template]"));
const bridgeActionSelect = document.querySelector("#bridge-action-select");
const bridgeAssetDefinitionInput = document.querySelector("#bridge-asset-definition-input");
const bridgeLocalAssetInput = document.querySelector("#bridge-local-asset-input");
const bridgeVaultAccountInput = document.querySelector("#bridge-vault-account-input");
const bridgeRegistrantInput = document.querySelector("#bridge-registrant-input");
const bridgeRecipientInput = document.querySelector("#bridge-recipient-input");
const bridgeHomeDomainInput = document.querySelector("#bridge-home-domain-input");
const bridgeRemoteDomainInput = document.querySelector("#bridge-remote-domain-input");
const bridgeDecimalsInput = document.querySelector("#bridge-decimals-input");
const bridgeAmountInput = document.querySelector("#bridge-amount-input");
const bridgeActionSummary = document.querySelector("#bridge-action-summary");
const bridgeValidationSummary = document.querySelector("#bridge-validation-summary");
const buildBridgeRequestButton = document.querySelector("#build-bridge-request");

const proofStatusSummary = document.querySelector("#proof-status-summary");
const refreshSccpDiscoveryButton = document.querySelector("#refresh-sccp-discovery");
const sccpCounterpartyList = document.querySelector("#sccp-counterparty-list");
const sccpCapabilitiesPreview = document.querySelector("#sccp-capabilities-preview");
const sccpManifestsPreview = document.querySelector("#sccp-manifests-preview");
const proofLookupMessageIdInput = document.querySelector("#proof-lookup-message-id-input");
const recentProofLookupSelect = document.querySelector("#recent-proof-lookup-select");
const lookupSccpAllButton = document.querySelector("#lookup-sccp-all");
const lookupSccpBundleButton = document.querySelector("#lookup-sccp-bundle");
const lookupSccpArtifactButton = document.querySelector("#lookup-sccp-artifact");
const lookupSccpJobButton = document.querySelector("#lookup-sccp-job");
const proofLookupSummary = document.querySelector("#proof-lookup-summary");
const sccpBundlePreview = document.querySelector("#sccp-bundle-preview");
const sccpArtifactPreview = document.querySelector("#sccp-artifact-preview");
const sccpJobPreview = document.querySelector("#sccp-job-preview");
const proofSubmissionPackagePreview = document.querySelector("#proof-submission-package-preview");

const submissionSummary = document.querySelector("#submission-summary");
const sccpMessageKindSelect = document.querySelector("#sccp-message-kind-select");
const sccpSourceDomainInput = document.querySelector("#sccp-source-domain-input");
const sccpDestDomainInput = document.querySelector("#sccp-dest-domain-input");
const sccpNonceInput = document.querySelector("#sccp-nonce-input");
const sccpMessageSenderInput = document.querySelector("#sccp-message-sender-input");
const sccpFinalityHeightInput = document.querySelector("#sccp-finality-height-input");
const loadLookedUpBundleButton = document.querySelector("#load-looked-up-bundle");
const buildProofSubmitTemplateButton = document.querySelector("#build-proof-submit-template");
const buildBridgeMessageTemplateButton = document.querySelector("#build-bridge-message-template");
const insertSettlementHelperButton = document.querySelector("#insert-settlement-helper");
const proofSubmitInput = document.querySelector("#proof-submit-input");
const bridgeMessageSubmitInput = document.querySelector("#bridge-message-submit-input");
const submitBridgeProofButton = document.querySelector("#submit-bridge-proof");
const submitBridgeMessageButton = document.querySelector("#submit-bridge-message");

function defaultBridgeBookmarks() {
  return {
    assetKeys: [],
    routes: [],
    transfers: [],
    messageIds: [],
  };
}

function loadStorage(key, fallback) {
  try {
    const raw = window.localStorage.getItem(key);
    if (!raw) {
      return cloneJson(fallback);
    }
    const parsed = JSON.parse(raw);
    return parsed == null ? cloneJson(fallback) : parsed;
  } catch (error) {
    return cloneJson(fallback);
  }
}

function saveStorage(key, value) {
  window.localStorage.setItem(key, JSON.stringify(value));
}

function persistLocalState() {
  saveStorage(STORAGE_KEYS.recentRequests, state.local.recentRequests);
  saveStorage(STORAGE_KEYS.transactionStatuses, state.local.transactionStatuses);
  saveStorage(STORAGE_KEYS.bridgeBookmarks, state.local.bridgeBookmarks);
  saveStorage(STORAGE_KEYS.proofLookups, state.local.proofLookups);
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function prettyJson(value) {
  return JSON.stringify(value, null, 2);
}

function runtimeConfig() {
  const value = window.__SORASWAP_CONTRACT_CONSOLE_CONFIG__;
  return value && typeof value === "object" ? value : {};
}

function positiveRuntimeNumber(key, fallback) {
  const raw = Number(runtimeConfig()[key]);
  return Number.isFinite(raw) && raw > 0 ? raw : fallback;
}

function transactionPollIntervalMs() {
  return positiveRuntimeNumber("transactionPollIntervalMs", DEFAULT_TRANSACTION_POLL_INTERVAL_MS);
}

function transactionPollTimeoutMs() {
  return positiveRuntimeNumber("transactionPollTimeoutMs", DEFAULT_TRANSACTION_POLL_TIMEOUT_MS);
}

function setBanner(element, text, kind = "muted") {
  element.textContent = text;
  element.className = `banner ${kind}`;
}

function setRequestAndResponsePreview(requestValue, responseValue) {
  requestPreview.textContent = prettyJson(requestValue ?? {});
  responsePreview.textContent = prettyJson(responseValue ?? {});
}

function bridgeContractForEnvironment(environment) {
  return (environment?.contracts || []).find((contract) => contract.contract_key === BRIDGE_CONTRACT_KEY) || null;
}

function selectedEnvironment() {
  return state.environments.find((environment) => environment.name === environmentSelect.value) || null;
}

function selectedContract() {
  return state.filteredContracts.find((contract) => contract.contract_key === contractSelect.value) || null;
}

function selectedEntrypoint() {
  return (state.currentContract?.entrypoints || []).find((entrypoint) => entrypoint.name === entrypointSelect.value) || null;
}

function formatTimestamp(value) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "-" : date.toLocaleString();
}

function inferDefaultValue(typeName) {
  const type = String(typeName || "").toLowerCase();
  if (!type) {
    return "";
  }
  if (type.includes("int") || type.includes("u32") || type.includes("u64") || type.includes("i32") || type.includes("i64")) {
    return 0;
  }
  if (type.includes("bool")) {
    return false;
  }
  if (type.includes("list<") || type.endsWith("[]")) {
    return [];
  }
  if (type.includes("map<")) {
    return {};
  }
  return "";
}

function buildPayloadTemplate(entrypoint) {
  const params = entrypoint?.params || [];
  if (!params.length) {
    return null;
  }

  return Object.fromEntries(
    params.map((param) => [param.name, inferDefaultValue(param.type_name)])
  );
}

function normalizeHexIdentifier(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replace(/^0x/, "");
}

function zeroHex(bytes = 32) {
  return "0".repeat(bytes * 2);
}

function truncateText(value, maxLength = 96) {
  const normalized = String(value ?? "");
  return normalized.length <= maxLength ? normalized : `${normalized.slice(0, maxLength - 3)}...`;
}

function summarizeJsonValue(value, depth = 0) {
  if (value == null || typeof value === "number" || typeof value === "boolean") {
    return value;
  }
  if (typeof value === "string") {
    return truncateText(value);
  }
  if (Array.isArray(value)) {
    if (depth >= 2) {
      return `[${value.length} item(s)]`;
    }
    return value.slice(0, 4).map((entry) => summarizeJsonValue(entry, depth + 1));
  }
  if (typeof value === "object") {
    if (depth >= 2) {
      return "{...}";
    }
    return Object.fromEntries(
      Object.entries(value)
        .filter(([key]) => key !== "private_key")
        .slice(0, 8)
        .map(([key, entry]) => [key, summarizeJsonValue(entry, depth + 1)])
    );
  }
  return truncateText(value);
}

function requestEnvironmentName() {
  return state.currentEnvironment?.name || "";
}

function currentAuthority() {
  return authorityInput.value.trim() || state.currentEnvironment?.signer?.authority || "";
}

function bridgeWorkspaceValues() {
  return {
    assetKey: bridgeAssetKeyInput.value.trim(),
    route: bridgeRouteInput.value.trim(),
    transfer: bridgeTransferInput.value.trim(),
    messageId: bridgeMessageIdInput.value.trim(),
    action: bridgeActionSelect.value,
    assetDefinition: bridgeAssetDefinitionInput.value.trim(),
    localAsset: bridgeLocalAssetInput.value.trim(),
    vaultAccount: bridgeVaultAccountInput.value.trim(),
    registrant: bridgeRegistrantInput.value.trim(),
    recipient: bridgeRecipientInput.value.trim(),
    homeDomain: Number(bridgeHomeDomainInput.value || 0),
    remoteDomain: Number(bridgeRemoteDomainInput.value || 0),
    decimals: Number(bridgeDecimalsInput.value || 0),
    amount: Number(bridgeAmountInput.value || 0),
  };
}

function sccpBuilderValues() {
  return {
    kind: sccpMessageKindSelect.value,
    sourceDomain: Number(sccpSourceDomainInput.value || 0),
    destDomain: Number(sccpDestDomainInput.value || 0),
    nonce: Number(sccpNonceInput.value || 0),
    sender: sccpMessageSenderInput.value.trim(),
    finalityHeight: Number(sccpFinalityHeightInput.value || 0),
  };
}

function bridgeBookmarksForCurrentEnvironment(bucketName) {
  const environment = requestEnvironmentName();
  return (state.local.bridgeBookmarks[bucketName] || []).filter((entry) => entry.environment === environment);
}

function upsertBookmarkForEnvironment(bucketName, value, environment) {
  const trimmed = String(value || "").trim();
  if (!trimmed || !environment) {
    return;
  }
  const bucket = state.local.bridgeBookmarks[bucketName] || [];
  const existingIndex = bucket.findIndex((entry) => entry.environment === environment && entry.value === trimmed);
  const nextEntry = {
    environment,
    value: trimmed,
    savedAtMs: Date.now(),
  };
  if (existingIndex >= 0) {
    bucket.splice(existingIndex, 1);
  }
  bucket.unshift(nextEntry);
  state.local.bridgeBookmarks[bucketName] = bucket.slice(0, 20);
}

function upsertBookmark(bucketName, value) {
  upsertBookmarkForEnvironment(bucketName, value, requestEnvironmentName());
}

function bookmarkCurrentBridgeValues() {
  const values = bridgeWorkspaceValues();
  upsertBookmark("assetKeys", values.assetKey);
  upsertBookmark("routes", values.route);
  upsertBookmark("transfers", values.transfer);
  upsertBookmark("messageIds", values.messageId);
  persistLocalState();
  renderBridgeBookmarks();
}

function rememberProofLookup(messageId, sources) {
  const normalized = normalizeHexIdentifier(messageId);
  const environment = requestEnvironmentName();
  if (!normalized || !environment) {
    return;
  }
  const nextEntry = {
    environment,
    messageId: normalized,
    sources: Array.from(new Set(sources)),
    lookedUpAtMs: Date.now(),
  };
  state.local.proofLookups = [
    nextEntry,
    ...state.local.proofLookups.filter((entry) => !(entry.environment === environment && entry.messageId === normalized)),
  ].slice(0, 20);
  persistLocalState();
  renderProofLookupHistory();
}

function addUniqueValue(target, value) {
  const trimmed = String(value || "").trim();
  if (!trimmed) {
    return;
  }
  if (!target.includes(trimmed)) {
    target.push(trimmed);
  }
}

function addBridgeIdentifiersFromBundle(bookmarkSnapshot, bundle) {
  if (!bundle || typeof bundle !== "object") {
    return;
  }
  addUniqueValue(bookmarkSnapshot.messageIds, bundle?.commitment?.message_id);
  const payload = bundle.payload;
  if (!payload || typeof payload !== "object") {
    return;
  }
  const transfer = payload.Transfer;
  if (transfer && typeof transfer === "object") {
    addUniqueValue(bookmarkSnapshot.routes, transfer.route_id);
    addUniqueValue(bookmarkSnapshot.assetKeys, transfer.asset_id);
  }
  const assetRegister = payload.AssetRegister;
  if (assetRegister && typeof assetRegister === "object") {
    addUniqueValue(bookmarkSnapshot.assetKeys, assetRegister.asset_id);
  }
  const routeActivate = payload.RouteActivate;
  if (routeActivate && typeof routeActivate === "object") {
    addUniqueValue(bookmarkSnapshot.routes, routeActivate.route_id);
    addUniqueValue(bookmarkSnapshot.assetKeys, routeActivate.asset_id);
  }
}

function extractBridgeBookmarkSnapshot(requestPayload) {
  const snapshot = {
    assetKeys: [],
    routes: [],
    transfers: [],
    messageIds: [],
  };
  if (!requestPayload || typeof requestPayload !== "object") {
    return snapshot;
  }

  const payload = requestPayload.payload;
  if (payload && typeof payload === "object") {
    addUniqueValue(snapshot.assetKeys, payload.asset_key);
    addUniqueValue(snapshot.routes, payload.route);
    addUniqueValue(snapshot.transfers, payload.transfer);
    addUniqueValue(snapshot.messageIds, payload.message_id);
  }

  addUniqueValue(snapshot.routes, requestPayload?.settlement?.route);
  addBridgeIdentifiersFromBundle(snapshot, requestPayload.message_bundle);
  addBridgeIdentifiersFromBundle(snapshot, requestPayload.burn_bundle);
  addBridgeIdentifiersFromBundle(snapshot, requestPayload.governance_bundle);

  return snapshot;
}

function buildRequestMetadataSnapshot(requestPayload) {
  if (!requestPayload || typeof requestPayload !== "object") {
    return null;
  }
  return {
    authority: requestPayload.authority || null,
    gasLimit: Number.isFinite(Number(requestPayload.gas_limit)) ? Number(requestPayload.gas_limit) : null,
    topLevelKeys: Object.keys(requestPayload).filter((key) => key !== "private_key").slice(0, 12),
    bridgeIds: extractBridgeBookmarkSnapshot(requestPayload),
    preview: summarizeJsonValue(requestPayload),
  };
}

function applyBridgeBookmarksSnapshot(environment, bookmarkSnapshot) {
  if (!environment || !bookmarkSnapshot) {
    return;
  }
  (bookmarkSnapshot.assetKeys || []).forEach((value) => upsertBookmarkForEnvironment("assetKeys", value, environment));
  (bookmarkSnapshot.routes || []).forEach((value) => upsertBookmarkForEnvironment("routes", value, environment));
  (bookmarkSnapshot.transfers || []).forEach((value) => upsertBookmarkForEnvironment("transfers", value, environment));
  (bookmarkSnapshot.messageIds || []).forEach((value) => upsertBookmarkForEnvironment("messageIds", value, environment));
  persistLocalState();
  if (environment === requestEnvironmentName()) {
    renderBridgeBookmarks();
  }
}

function formatBridgeBookmarkSummary(bookmarkSnapshot) {
  if (!bookmarkSnapshot) {
    return null;
  }
  const pieces = [];
  if (bookmarkSnapshot.assetKeys?.length) {
    pieces.push(`asset=${bookmarkSnapshot.assetKeys[0]}`);
  }
  if (bookmarkSnapshot.routes?.length) {
    pieces.push(`route=${bookmarkSnapshot.routes[0]}`);
  }
  if (bookmarkSnapshot.transfers?.length) {
    pieces.push(`transfer=${bookmarkSnapshot.transfers[0]}`);
  }
  if (bookmarkSnapshot.messageIds?.length) {
    pieces.push(`message=${truncateText(bookmarkSnapshot.messageIds[0], 20)}`);
  }
  return pieces.length ? pieces.join(" | ") : null;
}

function trackerStartedAtMs(txHashHex, tracker) {
  if (Number.isFinite(Number(tracker?.trackingStartedAtMs))) {
    return Number(tracker.trackingStartedAtMs);
  }
  const record = findRecentRequestByTxHash(txHashHex);
  if (record?.createdAtMs) {
    return Number(record.createdAtMs);
  }
  return Date.now();
}

function trackerTimeoutAtMs(txHashHex, tracker) {
  if (Number.isFinite(Number(tracker?.timeoutAtMs))) {
    return Number(tracker.timeoutAtMs);
  }
  return trackerStartedAtMs(txHashHex, tracker) + transactionPollTimeoutMs();
}

function trackerHasTimedOut(txHashHex, tracker, now = Date.now()) {
  return now >= trackerTimeoutAtMs(txHashHex, tracker);
}

function selectContractByKey(contractKey) {
  if (!contractKey) {
    return;
  }

  const matching = (state.currentEnvironment?.contracts || []).find((contract) => contract.contract_key === contractKey);
  if (!matching) {
    return;
  }

  const filterTerm = contractFilter.value.trim().toLowerCase();
  const matchesFilter = [matching.contract_key, matching.contract_address, matching.contract_source]
    .filter(Boolean)
    .join(" ")
    .toLowerCase()
    .includes(filterTerm);
  if (!matchesFilter && filterTerm) {
    contractFilter.value = "";
    applyContractFilter();
  }

  contractSelect.value = contractKey;
  state.currentContract = matching;
  renderContractMeta();
  renderEntrypoints();
  state.currentEntrypoint = selectedEntrypoint();
  renderEntrypointMeta();
}

function selectEntrypointByName(entrypointName) {
  if (!entrypointName) {
    return;
  }
  const entrypoint = (state.currentContract?.entrypoints || []).find((item) => item.name === entrypointName);
  if (!entrypoint) {
    return;
  }
  entrypointSelect.value = entrypointName;
  state.currentEntrypoint = entrypoint;
  renderEntrypointMeta();
}

function renderEnvironmentOptions() {
  environmentSelect.innerHTML = "";
  for (const environment of state.environments) {
    const option = document.createElement("option");
    option.value = environment.name;
    option.textContent = `${environment.name} (${environment.contracts.length})`;
    environmentSelect.append(option);
  }
  if (state.environments.length && !environmentSelect.value) {
    environmentSelect.value = state.environments[0].name;
  }
}

function renderEnvironmentSummary() {
  const environment = state.currentEnvironment;
  if (!environment) {
    setBanner(environmentSummary, "No deployment environments were found under deployments/.", "error");
    return;
  }

  const signer = environment.signer || {};
  const mutationPolicy = environment.mutation_policy || {};
  const mutationState = mutationPolicy.allowed ? "enabled" : "disabled";
  const pieces = [
    `Torii: ${environment.torii_url || "unconfigured"} (${environment.torii_url_source || "none"})`,
    `Chain: ${environment.chain_fingerprint?.chain || "unknown"}`,
    `Signer: ${signer.configured ? `configured (${signer.source || "unknown"})` : "not configured"}`,
    `Calls: ${signer.call_enabled ? "enabled" : "disabled"}`,
    `Mutations: ${mutationState} (${mutationPolicy.name || "unknown"})`,
  ];
  const warnings = [...(signer.warnings || [])];
  if (!mutationPolicy.allowed && mutationPolicy.reason) {
    warnings.push(mutationPolicy.reason);
  }
  const kind = warnings.length ? "warning" : "muted";
  const text = `${pieces.join(" | ")}${warnings.length ? ` | ${warnings.join(" | ")}` : ""}`;
  setBanner(environmentSummary, text, kind);
}

function applyContractFilter() {
  const term = contractFilter.value.trim().toLowerCase();
  const contracts = state.currentEnvironment?.contracts || [];
  state.currentContracts = contracts;
  state.filteredContracts = contracts.filter((contract) => {
    const haystack = [
      contract.contract_key,
      contract.contract_address,
      contract.contract_source,
    ]
      .filter(Boolean)
      .join(" ")
      .toLowerCase();
    return haystack.includes(term);
  });

  contractSelect.innerHTML = "";
  for (const contract of state.filteredContracts) {
    const option = document.createElement("option");
    option.value = contract.contract_key;
    option.textContent = `${contract.contract_key}  ${contract.contract_address || ""}`;
    contractSelect.append(option);
  }

  if (state.filteredContracts.length) {
    const currentKey = state.currentContract?.contract_key;
    const stillPresent = state.filteredContracts.some((contract) => contract.contract_key === currentKey);
    contractSelect.value = stillPresent ? currentKey : state.filteredContracts[0].contract_key;
  }
}

function renderContractMeta() {
  const contract = state.currentContract;
  contractAddressDisplay.textContent = contract?.contract_address || "-";
  contractDataspaceDisplay.textContent = contract?.dataspace || "-";
  contractDeployNonceDisplay.textContent = contract?.deploy_nonce ?? "-";
  contractVerificationDisplay.textContent = contract?.verification || "-";
  contractSourceDisplay.textContent = contract?.contract_source || "-";
  contractManifestDisplay.textContent = contract?.manifest_path || "-";
  contractAddressInput.value = contract?.contract_address || "";
}

function renderEntrypoints() {
  entrypointSelect.innerHTML = "";
  const entrypoints = state.currentContract?.entrypoints || [];
  for (const entrypoint of entrypoints) {
    const option = document.createElement("option");
    option.value = entrypoint.name;
    const permission = entrypoint.permission ? ` · ${entrypoint.permission}` : "";
    option.textContent = `[${entrypoint.kind}] ${entrypoint.name}${permission}`;
    entrypointSelect.append(option);
  }
  if (entrypoints.length) {
    const currentName = state.currentEntrypoint?.name;
    const stillPresent = entrypoints.some((entrypoint) => entrypoint.name === currentName);
    entrypointSelect.value = stillPresent ? currentName : entrypoints[0].name;
  }
}

function renderEntrypointMeta() {
  const entrypoint = state.currentEntrypoint;
  if (!entrypoint) {
    modeDisplay.value = "";
    setBanner(entrypointSummary, "No entrypoint selected.", "muted");
    runRequestButton.disabled = true;
    runRequestButton.textContent = "Run Request";
    return;
  }

  const environment = state.currentEnvironment;
  const canCall = Boolean(environment?.signer?.call_enabled);
  const mutationAllowed = Boolean(environment?.mutation_policy?.allowed ?? true);
  const params = entrypoint.params || [];
  const paramText = params.length
    ? params.map((param) => `${param.name}: ${param.type_name}`).join(", ")
    : "no payload params";
  const returnText = entrypoint.return_type || "void";
  const permission = entrypoint.permission ? ` | permission: ${entrypoint.permission}` : "";
  const mode = entrypoint.kind === "View" ? "view" : "call";

  setBanner(
    entrypointSummary,
    `${entrypoint.kind} | params: ${paramText} | returns: ${returnText}${permission}`,
    "muted"
  );

  modeDisplay.value = mode;
  if (mode === "call" && (!canCall || !mutationAllowed)) {
    runRequestButton.disabled = true;
    runRequestButton.textContent = "Call Disabled";
    const disabledReason = !canCall
      ? "no signer is configured for this environment"
      : (environment?.mutation_policy?.reason || "mutations are disabled for this environment");
    setBanner(
      entrypointSummary,
      `${entrypoint.kind} | params: ${paramText} | returns: ${returnText}${permission} | ${disabledReason}`,
      "warning"
    );
    return;
  }

  runRequestButton.disabled = false;
  runRequestButton.textContent = mode === "view" ? "Run View" : "Run Call";
}

function renderSelectFromEntries(selectElement, entries, placeholder) {
  selectElement.innerHTML = "";
  const placeholderOption = document.createElement("option");
  placeholderOption.value = "";
  placeholderOption.textContent = placeholder;
  selectElement.append(placeholderOption);
  for (const entry of entries) {
    const option = document.createElement("option");
    option.value = entry.value;
    option.textContent = `${entry.value} · ${formatTimestamp(entry.savedAtMs || entry.lookedUpAtMs)}`;
    selectElement.append(option);
  }
}

function renderBridgeBookmarks() {
  renderSelectFromEntries(bookmarkAssetKeySelect, bridgeBookmarksForCurrentEnvironment("assetKeys"), "Saved asset keys");
  renderSelectFromEntries(bookmarkRouteSelect, bridgeBookmarksForCurrentEnvironment("routes"), "Saved routes");
  renderSelectFromEntries(bookmarkTransferSelect, bridgeBookmarksForCurrentEnvironment("transfers"), "Saved transfer ids");
  renderSelectFromEntries(bookmarkMessageIdSelect, bridgeBookmarksForCurrentEnvironment("messageIds"), "Saved message ids");
}

function renderProofLookupHistory() {
  const environment = requestEnvironmentName();
  const entries = state.local.proofLookups.filter((entry) => entry.environment === environment);
  renderSelectFromEntries(recentProofLookupSelect, entries.map((entry) => ({
    value: entry.messageId,
    savedAtMs: entry.lookedUpAtMs,
  })), "Recent proof lookups");
}

function counterpartyCapabilities() {
  return state.sccpCapabilities?.response_json?.counterparties || [];
}

function sccpCounterpartyForDomain(domain) {
  return counterpartyCapabilities().find((entry) => Number(entry.domain) === Number(domain)) || null;
}

function sccpCounterpartyCodecKeyForDomain(domain) {
  return sccpCounterpartyForDomain(domain)?.counterparty_account_codec_key || null;
}

function deriveRouteRemoteDomain(route) {
  if (!route || !state.bridgeSnapshot?.requested_keys?.route || state.bridgeSnapshot.requested_keys.route !== route) {
    return null;
  }
  const mirrorRoute = (state.bridgeSnapshot.views || []).find((entry) => entry.entrypoint === "mirror_route");
  const responseJson = mirrorRoute?.response_json;
  if (Array.isArray(responseJson) && responseJson.length >= 2) {
    const maybeDomain = Number(responseJson[1]);
    return Number.isFinite(maybeDomain) ? maybeDomain : null;
  }
  return null;
}

function validateRecipientForCodec(value, codecKey) {
  const recipient = String(value || "").trim();
  if (!recipient) {
    return "Recipient is required.";
  }
  switch (codecKey) {
    case "text_utf8":
      return null;
    case "evm_hex":
      return /^0x[0-9a-fA-F]{40}$/.test(recipient)
        ? null
        : "Recipient must be a 0x-prefixed 20-byte hex address for the selected EVM lane.";
    case "solana_base58":
      return /^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(recipient)
        ? null
        : "Recipient must be a Solana base58 public key for the selected lane.";
    case "ton_raw":
      return /^-?\d+:[0-9a-fA-F]{64}$/.test(recipient)
        ? null
        : "Recipient must be a TON raw address in workchain:account_hex form.";
    case "tron_base58check":
      return /^T[1-9A-HJ-NP-Za-km-z]{33}$/.test(recipient)
        ? null
        : "Recipient must be a Tron base58check address beginning with T.";
    default:
      return null;
  }
}

function validateBridgeAction() {
  const values = bridgeWorkspaceValues();
  const authority = currentAuthority();
  const errors = [];
  const warnings = [];
  let counterparty = null;

  switch (values.action) {
    case "register_asset":
      if (!values.assetKey) errors.push("Asset Key is required for register_asset.");
      if (!values.assetDefinition) errors.push("Asset Definition is required for register_asset.");
      if (!(values.decimals >= 0)) errors.push("Decimals must be zero or greater.");
      if (!values.registrant && !authority) warnings.push("Registrant will fall back to the current authority.");
      break;
    case "activate_route":
      if (!values.route) errors.push("Route is required for activate_route.");
      if (!values.assetKey) errors.push("Asset Key is required for activate_route.");
      if (!(values.remoteDomain > 0)) errors.push("Remote Domain must be greater than zero for activate_route.");
      if (!(values.localAsset || values.assetDefinition)) errors.push("Local Asset or Asset Definition is required for activate_route.");
      if (!values.vaultAccount && !authority) warnings.push("Vault Account will fall back to the current authority.");
      counterparty = sccpCounterpartyForDomain(values.remoteDomain);
      break;
    case "pause_route":
    case "resume_route":
      if (!values.route) errors.push(`Route is required for ${values.action}.`);
      break;
    case "lock_to_remote": {
      if (!values.route) errors.push("Route is required for lock_to_remote.");
      if (!values.transfer) errors.push("Transfer Id is required for lock_to_remote.");
      if (!(values.amount > 0)) errors.push("Amount must be greater than zero for lock_to_remote.");
      const remoteDomain = values.remoteDomain > 0 ? values.remoteDomain : deriveRouteRemoteDomain(values.route);
      if (!remoteDomain) {
        warnings.push("Remote Domain is unknown; recipient validation will be skipped until SCCP discovery or a bridge snapshot resolves the route.");
      } else {
        counterparty = sccpCounterpartyForDomain(remoteDomain);
      }
      if (counterparty) {
        const recipientError = validateRecipientForCodec(values.recipient, counterparty.counterparty_account_codec_key);
        if (recipientError) {
          errors.push(recipientError);
        }
      } else if (!values.recipient) {
        errors.push("Recipient is required for lock_to_remote.");
      }
      break;
    }
    case "finalize_inbound":
      if (!values.route) errors.push("Route is required for finalize_inbound.");
      if (!values.messageId) errors.push("Inbound Message Id is required for finalize_inbound.");
      if (!(values.amount > 0)) errors.push("Amount must be greater than zero for finalize_inbound.");
      if (!(values.recipient || authority)) errors.push("Recipient or Authority is required for finalize_inbound.");
      break;
    default:
      warnings.push("Select a supported bridge action.");
  }

  if (values.remoteDomain > 0 && !counterparty) {
    counterparty = sccpCounterpartyForDomain(values.remoteDomain);
  }

  return { values, authority, errors, warnings, counterparty };
}

function renderBridgeActionSummary() {
  const { values, warnings, counterparty } = validateBridgeAction();
  const summaries = {
    register_asset: "register_asset uses Asset Key, Asset Definition, Registrant, Home Domain, and Decimals.",
    activate_route: "activate_route uses Route, Asset Key, Remote Domain, Local Asset, and Vault Account.",
    pause_route: "pause_route only needs Route.",
    resume_route: "resume_route only needs Route.",
    lock_to_remote: "lock_to_remote uses Route, Transfer Id, Recipient, Amount, and current Authority as sender.",
    finalize_inbound: "finalize_inbound uses Route, Inbound Message Id, Recipient, and Amount.",
  };
  setBanner(bridgeActionSummary, summaries[values.action] || "Select a bridge action.", "muted");
  if (counterparty) {
    setBanner(
      bridgeValidationSummary,
      `Selected lane: ${counterparty.chain} / domain ${counterparty.domain} / recipient codec ${counterparty.counterparty_account_codec_key}${warnings.length ? ` | ${warnings.join(" | ")}` : ""}`,
      warnings.length ? "warning" : "success"
    );
    return;
  }
  setBanner(
    bridgeValidationSummary,
    warnings.length ? warnings.join(" | ") : "Recipient validation is inactive until a counterparty lane is selected or discovered.",
    warnings.length ? "warning" : "muted"
  );
}

function renderBridgeWorkspace() {
  const environment = state.currentEnvironment;
  const bridgeContract = bridgeContractForEnvironment(environment);
  const authority = currentAuthority();

  renderBridgeBookmarks();
  renderBridgeActionSummary();

  if (!environment) {
    setBanner(bridgeSummary, "Select an environment to inspect bridge state.", "muted");
    selectBridgeContractButton.disabled = true;
    refreshBridgeSnapshotButton.disabled = true;
    buildBridgeRequestButton.disabled = true;
    bookmarkCurrentBridgeButton.disabled = true;
    clearBridgeBookmarksButton.disabled = true;
    bridgeTemplateButtons.forEach((button) => {
      button.disabled = true;
    });
    submitBridgeProofButton.disabled = true;
    submitBridgeMessageButton.disabled = true;
    return;
  }

  if (!bridgeContract) {
    setBanner(bridgeSummary, "This environment has no deployed bridge.sccp_bridge contract.", "warning");
    selectBridgeContractButton.disabled = true;
    refreshBridgeSnapshotButton.disabled = true;
    buildBridgeRequestButton.disabled = true;
    bookmarkCurrentBridgeButton.disabled = true;
    clearBridgeBookmarksButton.disabled = false;
    bridgeTemplateButtons.forEach((button) => {
      button.disabled = true;
    });
    submitBridgeProofButton.disabled = true;
    submitBridgeMessageButton.disabled = true;
    bridgeSnapshotPreview.textContent = prettyJson({});
    return;
  }

  if (!bridgeRegistrantInput.value.trim() && authority) {
    bridgeRegistrantInput.value = authority;
  }
  if (!bridgeVaultAccountInput.value.trim() && authority) {
    bridgeVaultAccountInput.value = authority;
  }

  const pieces = [
    `Bridge: ${bridgeContract.contract_address}`,
    `Authority: ${authority || "not set"}`,
    `Calls: ${environment.signer?.call_enabled ? "enabled" : "disabled"}`,
    `Mutations: ${environment.mutation_policy?.allowed ? "enabled" : "disabled"}`,
  ];
  const warnings = [];
  if (!authority) {
    warnings.push("bridge snapshot requests need an authority");
  }
  if (!environment.mutation_policy?.allowed && environment.mutation_policy?.reason) {
    warnings.push(environment.mutation_policy.reason);
  }
  const bridgeMutationsEnabled = Boolean(environment.signer?.call_enabled) && Boolean(environment.mutation_policy?.allowed ?? true);
  const kind = warnings.length ? "warning" : "muted";
  setBanner(bridgeSummary, `${pieces.join(" | ")}${warnings.length ? ` | ${warnings.join(" | ")}` : ""}`, kind);
  selectBridgeContractButton.disabled = false;
  refreshBridgeSnapshotButton.disabled = false;
  buildBridgeRequestButton.disabled = false;
  bookmarkCurrentBridgeButton.disabled = false;
  clearBridgeBookmarksButton.disabled = false;
  bridgeTemplateButtons.forEach((button) => {
    button.disabled = false;
  });
  submitBridgeProofButton.disabled = !bridgeMutationsEnabled;
  submitBridgeMessageButton.disabled = !bridgeMutationsEnabled;
}

function renderSelectionState() {
  state.currentEnvironment = selectedEnvironment();
  renderEnvironmentSummary();

  applyContractFilter();
  state.currentContract = selectedContract();
  renderContractMeta();

  renderEntrypoints();
  state.currentEntrypoint = selectedEntrypoint();
  renderEntrypointMeta();

  authorityInput.value = authorityInput.value || state.currentEnvironment?.signer?.authority || "";
  renderBridgeWorkspace();
  renderProofLookupHistory();
  renderTransactionTracker();
}

function fillPayloadTemplate() {
  const template = buildPayloadTemplate(state.currentEntrypoint);
  payloadInput.value = template ? prettyJson(template) : "";
}

function parseJsonInput(element, label) {
  const raw = element.value.trim();
  if (!raw) {
    return null;
  }
  try {
    return JSON.parse(raw);
  } catch (error) {
    throw new Error(`${label} must be valid JSON: ${error.message}`);
  }
}

function currentRequestPreview() {
  const payload = parseJsonInput(payloadInput, "Payload JSON");
  return {
    environment: requestEnvironmentName(),
    contract_address: contractAddressInput.value.trim(),
    entrypoint: state.currentEntrypoint?.name,
    authority: authorityInput.value.trim() || undefined,
    gas_limit: Number(gasLimitInput.value || DEFAULT_GAS_LIMIT),
    payload,
  };
}

function bridgeTemplatePayload(templateName) {
  const values = bridgeWorkspaceValues();
  const authority = currentAuthority();
  switch (templateName) {
    case "register_asset":
      return {
        entrypoint: "register_asset",
        payload: {
          asset_key: values.assetKey,
          registrant: authority,
          asset: "",
          home_domain: 0,
          decimals: 18,
        },
      };
    case "activate_route":
      return {
        entrypoint: "activate_route",
        payload: {
          route: values.route,
          asset_key: values.assetKey,
          remote_domain: 0,
          local_asset: "",
          vault_account: authority,
        },
      };
    case "pause_route":
      return {
        entrypoint: "pause_route",
        payload: {
          route: values.route,
        },
      };
    case "resume_route":
      return {
        entrypoint: "resume_route",
        payload: {
          route: values.route,
        },
      };
    case "lock_to_remote":
      return {
        entrypoint: "lock_to_remote",
        payload: {
          route: values.route,
          transfer: values.transfer,
          sender: authority,
          recipient: "",
          amount: 0,
        },
      };
    case "finalize_inbound":
      return {
        entrypoint: "finalize_inbound",
        payload: {
          route: values.route,
          message_id: values.messageId,
          recipient: authority,
          amount: 0,
        },
      };
    default:
      return null;
  }
}

function buildBridgeAction(templateName) {
  const { values, authority } = validateBridgeAction();
  switch (templateName) {
    case "register_asset":
      return {
        entrypoint: "register_asset",
        payload: {
          asset_key: values.assetKey,
          registrant: values.registrant || authority,
          asset: values.assetDefinition,
          home_domain: values.homeDomain,
          decimals: values.decimals,
        },
      };
    case "activate_route":
      return {
        entrypoint: "activate_route",
        payload: {
          route: values.route,
          asset_key: values.assetKey,
          remote_domain: values.remoteDomain,
          local_asset: values.localAsset || values.assetDefinition,
          vault_account: values.vaultAccount || authority,
        },
      };
    case "pause_route":
      return {
        entrypoint: "pause_route",
        payload: {
          route: values.route,
        },
      };
    case "resume_route":
      return {
        entrypoint: "resume_route",
        payload: {
          route: values.route,
        },
      };
    case "lock_to_remote":
      return {
        entrypoint: "lock_to_remote",
        payload: {
          route: values.route,
          transfer: values.transfer,
          sender: authority,
          recipient: values.recipient,
          amount: values.amount,
        },
      };
    case "finalize_inbound":
      return {
        entrypoint: "finalize_inbound",
        payload: {
          route: values.route,
          message_id: values.messageId,
          recipient: values.recipient || authority,
          amount: values.amount,
        },
      };
    default:
      return null;
  }
}

function applyBridgeTemplate(templateName) {
  const bridgeContract = bridgeContractForEnvironment(state.currentEnvironment);
  if (!bridgeContract) {
    setBanner(bridgeSummary, "No bridge contract is deployed in the selected environment.", "error");
    return;
  }

  const template = bridgeTemplatePayload(templateName);
  if (!template) {
    return;
  }

  selectContractByKey(BRIDGE_CONTRACT_KEY);
  selectEntrypointByName(template.entrypoint);
  contractAddressInput.value = bridgeContract.contract_address || "";
  payloadInput.value = prettyJson(template.payload);
  if (!authorityInput.value.trim() && state.currentEnvironment?.signer?.authority) {
    authorityInput.value = state.currentEnvironment.signer.authority;
  }
  setBanner(
    bridgeSummary,
    `Bridge template loaded for ${template.entrypoint}. Complete any blank fields, then run the request.`,
    "success"
  );
}

function buildBridgeRequestFromForm() {
  const bridgeContract = bridgeContractForEnvironment(state.currentEnvironment);
  if (!bridgeContract) {
    setBanner(bridgeSummary, "No bridge contract is deployed in the selected environment.", "error");
    return;
  }

  const validation = validateBridgeAction();
  if (validation.errors.length) {
    setBanner(bridgeValidationSummary, validation.errors.join(" | "), "error");
    return;
  }
  if (validation.warnings.length) {
    setBanner(bridgeValidationSummary, validation.warnings.join(" | "), "warning");
  }

  const action = buildBridgeAction(bridgeActionSelect.value);
  if (!action) {
    setBanner(bridgeSummary, "Select a supported bridge action before building a request.", "error");
    return;
  }

  selectContractByKey(BRIDGE_CONTRACT_KEY);
  selectEntrypointByName(action.entrypoint);
  contractAddressInput.value = bridgeContract.contract_address || "";
  payloadInput.value = prettyJson(action.payload);
  if (!authorityInput.value.trim() && state.currentEnvironment?.signer?.authority) {
    authorityInput.value = state.currentEnvironment.signer.authority;
  }
  setBanner(
    bridgeSummary,
    `Built ${action.entrypoint} from the bridge action form and loaded it into the invocation panel.`,
    "success"
  );
}

async function requestJson(url, options = {}) {
  const response = await fetch(url, options);
  const text = await response.text();
  if (!text) {
    return { response, result: {} };
  }
  try {
    return { response, result: JSON.parse(text) };
  } catch (error) {
    return {
      response,
      result: {
        ok: false,
        error: `Invalid JSON response: ${error.message}`,
        response_text: text,
      },
    };
  }
}

function recordRecentRequest(record) {
  state.local.recentRequests = [
    record,
    ...state.local.recentRequests.filter((entry) => entry.id !== record.id),
  ].slice(0, 30);
  persistLocalState();
  renderTransactionTracker();
}

function updateTrackedStatus(txHashHex, patch) {
  const current = state.local.transactionStatuses[txHashHex] || {};
  state.local.transactionStatuses[txHashHex] = {
    ...current,
    ...patch,
    txHashHex,
  };
  persistLocalState();
  renderTransactionTracker();
}

function statusKindFromTracker(tracker) {
  return tracker?.statusKind || tracker?.status_kind || null;
}

function statusKindFromResponse(result) {
  if (typeof result?.status_kind === "string" && result.status_kind) {
    return result.status_kind;
  }
  const direct = result?.response_json?.status;
  if (typeof direct === "string" && direct) {
    return direct;
  }
  if (direct && typeof direct === "object" && typeof direct.kind === "string") {
    return direct.kind;
  }
  const nested = result?.response_json?.content?.status;
  if (typeof nested === "string" && nested) {
    return nested;
  }
  if (nested && typeof nested === "object" && typeof nested.kind === "string") {
    return nested.kind;
  }
  if (result?.upstream_status === 404) {
    return "Pending";
  }
  return null;
}

function statusPillKind(statusKind) {
  if (SUCCESS_STATUSES.has(statusKind)) {
    return "success";
  }
  if (FAILURE_STATUSES.has(statusKind)) {
    return "error";
  }
  if (statusKind === TRANSACTION_TIMEOUT_STATUS) {
    return "warning";
  }
  return statusKind === "Pending" || statusKind === "NotFound" ? "warning" : "muted";
}

function findRecentRequestByTxHash(txHashHex) {
  return state.local.recentRequests.find((entry) => entry.txHashHex === txHashHex) || null;
}

function stopTransactionPolling(txHashHex) {
  const timer = state.pollTimers.get(txHashHex);
  if (timer) {
    clearTimeout(timer);
    state.pollTimers.delete(txHashHex);
  }
}

function maybeRefreshBridgeAfterTrackedWrite(tracker) {
  if (!tracker.bridgeRelated || tracker.environment !== requestEnvironmentName()) {
    return;
  }
  if (!bridgeContractForEnvironment(state.currentEnvironment)) {
    return;
  }
  refreshBridgeSnapshot({ silent: true }).catch((error) => {
    console.error("bridge snapshot refresh failed", error);
  });
}

async function pollTransactionStatus(txHashHex, { immediate = false } = {}) {
  const tracker = state.local.transactionStatuses[txHashHex];
  if (!tracker) {
    stopTransactionPolling(txHashHex);
    return;
  }
  if (tracker.terminal) {
    stopTransactionPolling(txHashHex);
    return;
  }
  if (state.pollTimers.has(txHashHex) && !immediate) {
    return;
  }

  const executePoll = async () => {
    const current = state.local.transactionStatuses[txHashHex];
    if (!current || current.terminal) {
      stopTransactionPolling(txHashHex);
      return;
    }
    const startedAtMs = trackerStartedAtMs(txHashHex, current);
    const timeoutAtMs = trackerTimeoutAtMs(txHashHex, current);
    if (trackerHasTimedOut(txHashHex, current)) {
      updateTrackedStatus(txHashHex, {
        statusKind: TRANSACTION_TIMEOUT_STATUS,
        trackingStartedAtMs: startedAtMs,
        timeoutAtMs,
        timedOut: true,
        lastUpdatedAtMs: Date.now(),
        terminal: true,
      });
      stopTransactionPolling(txHashHex);
      return;
    }

    try {
      const query = new URLSearchParams({
        environment: current.environment,
        hash: txHashHex,
        scope: current.scope || "auto",
      });
      const { result } = await requestJson(`/api/pipeline/transactions/status?${query.toString()}`);
      const statusKind = statusKindFromResponse(result) || current.statusKind || "Pending";
      const terminal = SUCCESS_STATUSES.has(statusKind) || FAILURE_STATUSES.has(statusKind);
      updateTrackedStatus(txHashHex, {
        statusKind,
        statusPayload: result,
        rejectionReason: result.rejection_reason || current.rejectionReason || null,
        trackingStartedAtMs: startedAtMs,
        timeoutAtMs,
        lastUpdatedAtMs: Date.now(),
        attempts: (current.attempts || 0) + 1,
        terminal,
      });
      if (terminal) {
        stopTransactionPolling(txHashHex);
        if (SUCCESS_STATUSES.has(statusKind)) {
          maybeRefreshBridgeAfterTrackedWrite(current);
        }
        return;
      }
    } catch (error) {
      updateTrackedStatus(txHashHex, {
        trackingStartedAtMs: startedAtMs,
        timeoutAtMs,
        lastUpdatedAtMs: Date.now(),
        attempts: (current.attempts || 0) + 1,
        lastError: String(error),
      });
    }

    const delayMs = Math.max(1, Math.min(transactionPollIntervalMs(), timeoutAtMs - Date.now()));
    const next = window.setTimeout(() => {
      state.pollTimers.delete(txHashHex);
      pollTransactionStatus(txHashHex, { immediate: true }).catch((error) => {
        console.error("transaction poll failed", error);
      });
    }, delayMs);
    state.pollTimers.set(txHashHex, next);
  };

  if (immediate) {
    await executePoll();
    return;
  }

  const timer = window.setTimeout(() => {
    state.pollTimers.delete(txHashHex);
    executePoll().catch((error) => {
      console.error("transaction poll failed", error);
    });
  }, 0);
  state.pollTimers.set(txHashHex, timer);
}

function enqueueTransactionTracking(record, result) {
  if (!record.txHashHex) {
    return;
  }
  const startedAtMs = Date.now();
  updateTrackedStatus(record.txHashHex, {
    environment: record.environment,
    actionType: record.actionType,
    bridgeRelated: record.bridgeRelated,
    scope: "auto",
    statusKind: statusKindFromResponse(result) || "Pending",
    statusPayload: result,
    trackingStartedAtMs: startedAtMs,
    timeoutAtMs: startedAtMs + transactionPollTimeoutMs(),
    lastUpdatedAtMs: Date.now(),
    attempts: 0,
    terminal: false,
  });
  pollTransactionStatus(record.txHashHex, { immediate: true }).catch((error) => {
    console.error("transaction poll failed", error);
  });
}

function renderTransactionTracker() {
  const pendingCount = Object.values(state.local.transactionStatuses).filter((entry) => !entry.terminal).length;
  const remoteStatus = state.remoteTransactionHistory;
  const pieces = [
    `Local signed actions: ${state.local.recentRequests.length}`,
    `Tracked transactions: ${Object.keys(state.local.transactionStatuses).length}`,
    `Pending: ${pendingCount}`,
  ];
  const timedOutCount = Object.values(state.local.transactionStatuses).filter((entry) => entry.statusKind === TRANSACTION_TIMEOUT_STATUS).length;
  if (timedOutCount) {
    pieces.push(`Timed out: ${timedOutCount}`);
  }
  if (remoteStatus) {
    if (remoteStatus.available) {
      const itemCount = Array.isArray(remoteStatus.response_json?.items) ? remoteStatus.response_json.items.length : 0;
      pieces.push(`Remote history: ${itemCount} item(s)`);
    } else {
      pieces.push(`Remote history unavailable: ${remoteStatus.unsupported_reason || remoteStatus.error_code || remoteStatus.upstream_status}`);
    }
  }
  setBanner(transactionSummary, pieces.join(" | "), remoteStatus && !remoteStatus.available ? "warning" : "muted");

  transactionHistoryList.innerHTML = "";
  if (!state.local.recentRequests.length) {
    const empty = document.createElement("div");
    empty.className = "record-card";
    empty.textContent = "No signed actions have been recorded in this browser yet.";
    transactionHistoryList.append(empty);
  } else {
    for (const record of state.local.recentRequests) {
      const tracker = record.txHashHex ? state.local.transactionStatuses[record.txHashHex] : null;
      const card = document.createElement("div");
      card.className = "record-card";

      const heading = document.createElement("div");
      heading.className = "field-row";
      const title = document.createElement("h4");
      title.textContent = `${record.actionType.replaceAll("_", " ")} · ${record.environment}`;
      const pill = document.createElement("span");
      const statusKind = statusKindFromTracker(tracker) || (record.txHashHex ? "Pending" : record.submitted ? "Prepared" : "Draft");
      pill.className = `status-pill ${statusPillKind(statusKind)}`;
      pill.textContent = statusKind;
      heading.append(title, pill);
      card.append(heading);

      const lines = [
        record.contractKey ? `Contract: ${record.contractKey}` : null,
        record.entrypoint ? `Entrypoint: ${record.entrypoint}` : null,
        record.txHashHex ? `tx_hash_hex: ${record.txHashHex}` : "No tx hash returned",
        record.requestMetadata?.gasLimit ? `Gas Limit: ${record.requestMetadata.gasLimit}` : null,
        formatBridgeBookmarkSummary(record.requestMetadata?.bridgeIds)
          ? `IDs: ${formatBridgeBookmarkSummary(record.requestMetadata?.bridgeIds)}`
          : null,
        `Saved: ${formatTimestamp(record.createdAtMs)}`,
      ].filter(Boolean);

      const meta = document.createElement("div");
      meta.className = "record-meta";
      for (const lineText of lines) {
        const line = document.createElement("div");
        line.className = "record-line";
        line.textContent = lineText;
        meta.append(line);
      }
      if (tracker?.rejectionReason) {
        const line = document.createElement("div");
        line.className = "record-line";
        line.textContent = `Rejection: ${tracker.rejectionReason}`;
        meta.append(line);
      }
      if (tracker?.statusKind === TRANSACTION_TIMEOUT_STATUS) {
        const line = document.createElement("div");
        line.className = "record-line";
        line.textContent = "Tracking timed out before a terminal transaction status was returned.";
        meta.append(line);
      }
      if (tracker?.lastError) {
        const line = document.createElement("div");
        line.className = "record-line";
        line.textContent = `Poll Error: ${truncateText(tracker.lastError)}`;
        meta.append(line);
      }
      card.append(meta);
      transactionHistoryList.append(card);
    }
  }

  remoteTransactionHistoryPreview.textContent = prettyJson(state.remoteTransactionHistory || {});
}

async function refreshRemoteTransactionHistory({ silent = false } = {}) {
  const environment = requestEnvironmentName();
  if (!environment) {
    state.remoteTransactionHistory = null;
    renderTransactionTracker();
    return;
  }
  if (!silent) {
    setBanner(transactionSummary, "Refreshing remote transaction history...", "muted");
  }
  const query = new URLSearchParams({
    environment,
    limit: "10",
  });
  try {
    const { result } = await requestJson(`/api/transactions/history?${query.toString()}`);
    state.remoteTransactionHistory = result;
    renderTransactionTracker();
  } catch (error) {
    state.remoteTransactionHistory = {
      ok: false,
      available: false,
      supported: false,
      error: String(error),
    };
    renderTransactionTracker();
  }
}

function recordRequestFromResult(meta, requestPayload, result) {
  const requestMetadata = buildRequestMetadataSnapshot(requestPayload);
  const record = {
    id: `${Date.now()}-${Math.random().toString(16).slice(2, 8)}`,
    createdAtMs: Date.now(),
    actionType: meta.actionType,
    environment: meta.environment,
    contractKey: meta.contractKey || null,
    contractAddress: meta.contractAddress || null,
    entrypoint: meta.entrypoint || null,
    requestPath: meta.requestPath || null,
    txHashHex: result.tx_hash_hex || null,
    submitted: result.submitted ?? Boolean(result.tx_hash_hex),
    bridgeRelated: meta.bridgeRelated === true,
    metadata: meta.metadata || null,
    requestMetadata,
  };
  recordRecentRequest(record);
  if (record.bridgeRelated) {
    applyBridgeBookmarksSnapshot(record.environment, requestMetadata?.bridgeIds);
  }
  if (record.txHashHex) {
    enqueueTransactionTracking(record, result);
  }
}

async function runRequest() {
  try {
    const preview = currentRequestPreview();
    requestPreview.textContent = prettyJson(preview);
    const mode = modeDisplay.value || "view";
    setBanner(requestStatus, `Submitting ${mode} request...`, "muted");

    const { response, result } = await requestJson(mode === "call" ? "/api/call" : "/api/view", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(preview),
    });
    responsePreview.textContent = prettyJson(result);

    if (!response.ok || !result.ok) {
      setBanner(
        requestStatus,
        `Request failed with upstream status ${result.upstream_status || response.status}.`,
        "error"
      );
      return;
    }

    setBanner(
      requestStatus,
      `Request succeeded with upstream status ${result.upstream_status}.`,
      "success"
    );

    if (mode === "call") {
      recordRequestFromResult(
        {
          actionType: "contract_call",
          environment: preview.environment,
          contractKey: state.currentContract?.contract_key,
          contractAddress: preview.contract_address,
          entrypoint: preview.entrypoint,
          requestPath: "/api/call",
          bridgeRelated: state.currentContract?.contract_key === BRIDGE_CONTRACT_KEY,
        },
        preview,
        result
      );
    }
  } catch (error) {
    responsePreview.textContent = prettyJson({
      ok: false,
      error: String(error),
    });
    setBanner(requestStatus, `Request failed: ${error}`, "error");
  }
}

async function copyText(value) {
  await navigator.clipboard.writeText(value);
}

async function refreshBridgeSnapshot({ silent = false } = {}) {
  const environment = state.currentEnvironment;
  const bridgeContract = bridgeContractForEnvironment(environment);
  if (!environment || !bridgeContract) {
    setBanner(bridgeSummary, "No bridge contract is available for the selected environment.", "error");
    return;
  }

  const authority = currentAuthority();
  if (!authority) {
    setBanner(bridgeSummary, "Set an authority before requesting a bridge snapshot.", "error");
    return;
  }

  const requestBody = {
    environment: environment.name,
    authority,
    gas_limit: Number(gasLimitInput.value || DEFAULT_GAS_LIMIT),
    asset_key: bridgeAssetKeyInput.value.trim() || undefined,
    route: bridgeRouteInput.value.trim() || undefined,
    transfer: bridgeTransferInput.value.trim() || undefined,
    message_id: bridgeMessageIdInput.value.trim() || undefined,
  };

  bridgeSnapshotPreview.textContent = prettyJson(requestBody);
  if (!silent) {
    setBanner(bridgeSummary, "Refreshing bridge snapshot...", "muted");
  }
  try {
    const { response, result } = await requestJson("/api/bridge/inspect", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(requestBody),
    });
    state.bridgeSnapshot = result;
    bridgeSnapshotPreview.textContent = prettyJson(result);

    if (!response.ok || !result.ok) {
      setBanner(
        bridgeSummary,
        `Bridge snapshot failed${result.error ? `: ${result.error}` : "."}`,
        "error"
      );
      return;
    }

    bookmarkCurrentBridgeValues();
    setBanner(
      bridgeSummary,
      `Bridge snapshot loaded from ${result.views.length} view call(s) for ${result.contract.contract_address}.`,
      "success"
    );
  } catch (error) {
    bridgeSnapshotPreview.textContent = prettyJson({
      ok: false,
      error: String(error),
    });
    setBanner(bridgeSummary, `Bridge snapshot failed: ${error}`, "error");
  }
}

function renderCounterpartyInsights() {
  sccpCounterpartyList.innerHTML = "";
  const capabilities = state.sccpCapabilities?.response_json;
  const manifests = state.sccpManifests?.response_json;
  const counterparties = capabilities?.counterparties || [];

  if (!counterparties.length) {
    const card = document.createElement("div");
    card.className = "insight-card";
    card.textContent = "No live SCCP capability data is loaded for the selected environment.";
    sccpCounterpartyList.append(card);
    return;
  }

  for (const counterparty of counterparties) {
    const card = document.createElement("div");
    card.className = "insight-card";
    const heading = document.createElement("h4");
    heading.textContent = `${counterparty.chain} · domain ${counterparty.domain}`;
    card.append(heading);

    const manifest = (manifests?.manifests || []).find((entry) => Number(entry.counterparty_domain) === Number(counterparty.domain));
    const lines = [
      `Codec: ${counterparty.counterparty_account_codec_key}`,
      `Message backend: ${counterparty.message_backend}`,
      `Registry backend: ${counterparty.registry_backend}`,
      manifest ? `Verifier target: ${manifest.verifier_target}` : null,
      manifest ? `Finality model: ${manifest.finality_model}` : null,
      manifest ? `Submission encoding: ${manifest.submission_template?.encoding || "-"}` : null,
    ].filter(Boolean);
    for (const lineText of lines) {
      const line = document.createElement("p");
      line.textContent = lineText;
      card.append(line);
    }
    sccpCounterpartyList.append(card);
  }
}

function renderSccpDiscovery() {
  sccpCapabilitiesPreview.textContent = prettyJson(state.sccpCapabilities || {});
  sccpManifestsPreview.textContent = prettyJson(state.sccpManifests || {});
  renderCounterpartyInsights();

  const capabilitiesOk = Boolean(state.sccpCapabilities?.ok);
  const manifestsOk = Boolean(state.sccpManifests?.ok);
  if (capabilitiesOk && manifestsOk) {
    const counterparties = state.sccpCapabilities.response_json?.counterparties?.length || 0;
    const manifests = state.sccpManifests.response_json?.manifests?.length || 0;
    setBanner(
      proofStatusSummary,
      `Loaded SCCP discovery for ${requestEnvironmentName()}: ${counterparties} counterparties, ${manifests} manifests.`,
      "success"
    );
  } else if (state.currentEnvironment) {
    setBanner(
      proofStatusSummary,
      `SCCP discovery is incomplete for ${requestEnvironmentName()}. Capabilities status: ${state.sccpCapabilities?.upstream_status || "-"} | manifests status: ${state.sccpManifests?.upstream_status || "-"}`,
      "warning"
    );
  } else {
    setBanner(proofStatusSummary, "Select an environment to inspect SCCP discovery.", "muted");
  }
}

async function refreshSccpDiscovery({ silent = false } = {}) {
  const environment = requestEnvironmentName();
  if (!environment) {
    state.sccpCapabilities = null;
    state.sccpManifests = null;
    renderSccpDiscovery();
    return;
  }
  if (!silent) {
    setBanner(proofStatusSummary, "Refreshing SCCP discovery...", "muted");
  }
  const query = new URLSearchParams({ environment });
  try {
    const [capabilitiesResponse, manifestsResponse] = await Promise.all([
      requestJson(`/api/sccp/capabilities?${query.toString()}`),
      requestJson(`/api/sccp/manifests?${query.toString()}`),
    ]);
    state.sccpCapabilities = capabilitiesResponse.result;
    state.sccpManifests = manifestsResponse.result;
    renderSccpDiscovery();
    renderBridgeWorkspace();
  } catch (error) {
    state.sccpCapabilities = { ok: false, error: String(error) };
    state.sccpManifests = { ok: false, error: String(error) };
    renderSccpDiscovery();
  }
}

function normalizeProofLookupMessageId() {
  const explicit = proofLookupMessageIdInput.value.trim();
  const bridgeValue = bridgeMessageIdInput.value.trim();
  return normalizeHexIdentifier(explicit || bridgeValue);
}

function activeLookedUpBundle() {
  const bundle = state.proofLookup.bundle?.response_json;
  const requestedMessageId = normalizeProofLookupMessageId();
  const bundleMessageId = normalizeHexIdentifier(bundle?.commitment?.message_id);
  if (bundle && (!requestedMessageId || requestedMessageId === bundleMessageId)) {
    return cloneJson(bundle);
  }
  return null;
}

function placeholderRecipientForCodec(codecKey) {
  switch (codecKey) {
    case "evm_hex":
      return "0x1111111111111111111111111111111111111111";
    case "solana_base58":
      return "11111111111111111111111111111111";
    case "ton_raw":
      return "0:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    case "tron_base58check":
      return "TQ9e5rL5aXoaZySUdkGFUTkqJCJSy9FHn5";
    default:
      return "logical-recipient";
  }
}

function codecIdForCodecKey(codecKey) {
  switch (codecKey) {
    case "text_utf8":
      return 1;
    case "evm_hex":
      return 2;
    case "solana_base58":
      return 3;
    case "ton_raw":
      return 4;
    case "tron_base58check":
      return 5;
    default:
      return 1;
  }
}

function buildMessageBundleTemplate() {
  const authority = currentAuthority();
  const builder = sccpBuilderValues();
  const values = bridgeWorkspaceValues();
  const liveCounterparty = sccpCounterpartyForDomain(builder.destDomain) || sccpCounterpartyForDomain(values.remoteDomain);
  const codecKey = liveCounterparty?.counterparty_account_codec_key || "text_utf8";
  const recipient = values.recipient || placeholderRecipientForCodec(codecKey);
  const route = values.route || "bridge_route";
  const assetId = values.assetDefinition || values.assetKey || "xor#universal";
  const sender = builder.sender || authority || "nexus:soraswap";
  const messageId = normalizeProofLookupMessageId() || zeroHex(32);

  const payloadMap = {
    asset_register: {
      AssetRegister: {
        version: 1,
        home_domain: values.homeDomain,
        target_domain: builder.destDomain,
        asset_id_codec: 1,
        asset_id: assetId,
        local_asset_definition: values.localAsset || assetId,
        decimals: values.decimals,
      },
    },
    route_activate: {
      RouteActivate: {
        version: 1,
        source_domain: builder.sourceDomain,
        target_domain: builder.destDomain,
        route_id_codec: 1,
        route_id: route,
        asset_id_codec: 1,
        asset_id: assetId,
        local_asset_definition: values.localAsset || assetId,
        vault_account: values.vaultAccount || authority || "i105...",
      },
    },
    transfer: {
      Transfer: {
        version: 1,
        source_domain: builder.sourceDomain,
        dest_domain: builder.destDomain,
        nonce: builder.nonce,
        asset_home_domain: values.homeDomain,
        asset_id_codec: 1,
        asset_id: assetId,
        amount: values.amount || 1,
        sender_codec: 1,
        sender,
        recipient_codec: codecIdForCodecKey(codecKey),
        recipient,
        route_id_codec: 1,
        route_id: route,
      },
    },
  };

  return {
    version: 1,
    commitment_root: zeroHex(32),
    commitment: {
      version: 1,
      kind: builder.kind === "asset_register" ? "AssetRegister" : builder.kind === "route_activate" ? "RouteActivate" : "Transfer",
      target_domain: builder.destDomain,
      message_id: messageId,
      payload_hash: zeroHex(32),
      parliament_certificate_hash: null,
    },
    merkle_proof: {
      steps: [],
    },
    payload: payloadMap[builder.kind],
    finality_proof: "",
  };
}

function currentBundleForSubmissionBuilders() {
  return activeLookedUpBundle() || buildMessageBundleTemplate();
}

function buildProofSubmitTemplate() {
  return {
    authority: currentAuthority() || "i105...",
    message_bundle: currentBundleForSubmissionBuilders(),
  };
}

function buildBridgeMessageSubmitTemplate() {
  const payload = {
    authority: currentAuthority() || "i105...",
    message_bundle: currentBundleForSubmissionBuilders(),
  };
  const route = bridgeRouteInput.value.trim();
  const bridgeContract = bridgeContractForEnvironment(state.currentEnvironment);
  if (bridgeContract && route) {
    payload.settlement = {
      contract_address: bridgeContract.contract_address,
      entrypoint: "finalize_inbound",
      route,
    };
  }
  return payload;
}

function loadLookedUpBundleIntoEditors() {
  const bundle = activeLookedUpBundle();
  if (!bundle) {
    setBanner(submissionSummary, "Look up a live SCCP message bundle first, then load it into the submission builders.", "warning");
    return;
  }
  proofSubmitInput.value = prettyJson({
    authority: currentAuthority() || "i105...",
    message_bundle: bundle,
  });
  bridgeMessageSubmitInput.value = prettyJson({
    authority: currentAuthority() || "i105...",
    message_bundle: bundle,
  });
  setBanner(submissionSummary, "Loaded the looked-up SCCP message bundle into both advanced JSON editors.", "success");
}

function insertSettlementHelper() {
  const bridgeContract = bridgeContractForEnvironment(state.currentEnvironment);
  if (!bridgeContract) {
    setBanner(submissionSummary, "No bridge contract is deployed in the selected environment.", "error");
    return;
  }
  const route = bridgeRouteInput.value.trim();
  if (!route) {
    setBanner(submissionSummary, "Set Route before inserting the settlement helper.", "error");
    return;
  }

  let payload;
  try {
    payload = parseJsonInput(bridgeMessageSubmitInput, "Bridge Message Submit JSON") || buildBridgeMessageSubmitTemplate();
  } catch (error) {
    setBanner(submissionSummary, String(error), "error");
    return;
  }
  payload.authority = payload.authority || currentAuthority() || "i105...";
  payload.message_bundle = payload.message_bundle || currentBundleForSubmissionBuilders();
  payload.settlement = {
    contract_address: bridgeContract.contract_address,
    entrypoint: "finalize_inbound",
    route,
  };
  bridgeMessageSubmitInput.value = prettyJson(payload);
  setBanner(
    submissionSummary,
    "Inserted a finalize_inbound settlement helper. Leave payload empty to let Torii auto-build the settlement object for transfer messages.",
    "success"
  );
}

function renderProofLookupResults() {
  sccpBundlePreview.textContent = prettyJson(state.proofLookup.bundle || {});
  sccpArtifactPreview.textContent = prettyJson(state.proofLookup.artifact || {});
  sccpJobPreview.textContent = prettyJson(state.proofLookup.job || {});

  const submissionPackage = state.proofLookup.job?.response_json?.submission_package
    || state.proofLookup.artifact?.response_json?.submission_package
    || {};
  const submissionTemplate = state.proofLookup.job?.response_json?.submission_template
    || state.sccpManifests?.response_json?.manifests?.find((entry) => {
      const domain = state.proofLookup.job?.response_json?.counterparty_domain || state.proofLookup.artifact?.response_json?.counterparty_domain;
      return Number(entry.counterparty_domain) === Number(domain);
    })?.submission_template;
  proofSubmissionPackagePreview.textContent = prettyJson({
    submission_template: submissionTemplate || null,
    submission_package: submissionPackage || null,
  });

  const bundlePayloadKind = state.proofLookup.job?.response_json?.payload_kind
    || Object.keys(state.proofLookup.bundle?.response_json?.payload || {})[0]
    || null;
  const chain = state.proofLookup.job?.response_json?.chain
    || state.proofLookup.artifact?.response_json?.bundle?.payload?.chain
    || state.proofLookup.artifact?.response_json?.counterparty_domain
    || null;
  const messageId = normalizeProofLookupMessageId();
  if (messageId && (state.proofLookup.bundle || state.proofLookup.artifact || state.proofLookup.job)) {
    setBanner(
      proofLookupSummary,
      `Loaded proof surfaces for ${messageId}${bundlePayloadKind ? ` | payload=${bundlePayloadKind}` : ""}${chain ? ` | chain=${chain}` : ""}`,
      "success"
    );
  } else {
    setBanner(proofLookupSummary, "Enter a message id to load the raw bundle, artifact, and normalized proof job.", "muted");
  }
}

async function lookupSccpResource(kind) {
  const environment = requestEnvironmentName();
  const messageId = normalizeProofLookupMessageId();
  if (!environment) {
    setBanner(proofLookupSummary, "Select an environment before looking up SCCP proof surfaces.", "error");
    return;
  }
  if (!messageId) {
    setBanner(proofLookupSummary, "Message Id is required for proof lookup.", "error");
    return;
  }

  const pathMap = {
    bundle: `/api/sccp/proofs/message/${messageId}`,
    artifact: `/api/sccp/artifacts/message/${messageId}`,
    job: `/api/sccp/jobs/message/${messageId}`,
  };
  const query = new URLSearchParams({ environment });
  setBanner(proofLookupSummary, `Loading ${kind}...`, "muted");
  const { result } = await requestJson(`${pathMap[kind]}?${query.toString()}`);
  state.proofLookup[kind] = result;
  if (result.ok) {
    upsertBookmark("messageIds", messageId);
    rememberProofLookup(messageId, [kind]);
    renderBridgeBookmarks();
  }
  renderProofLookupResults();
}

async function lookupAllSccpResources() {
  const environment = requestEnvironmentName();
  const messageId = normalizeProofLookupMessageId();
  if (!environment || !messageId) {
    setBanner(proofLookupSummary, "Select an environment and message id before running a full proof lookup.", "error");
    return;
  }
  setBanner(proofLookupSummary, "Loading bundle, artifact, and job...", "muted");
  const query = new URLSearchParams({ environment });
  const [bundle, artifact, job] = await Promise.all([
    requestJson(`/api/sccp/proofs/message/${messageId}?${query.toString()}`),
    requestJson(`/api/sccp/artifacts/message/${messageId}?${query.toString()}`),
    requestJson(`/api/sccp/jobs/message/${messageId}?${query.toString()}`),
  ]);
  state.proofLookup.bundle = bundle.result;
  state.proofLookup.artifact = artifact.result;
  state.proofLookup.job = job.result;
  if (bundle.result.ok || artifact.result.ok || job.result.ok) {
    upsertBookmark("messageIds", messageId);
    rememberProofLookup(messageId, ["bundle", "artifact", "job"]);
    renderBridgeBookmarks();
  }
  renderProofLookupResults();
}

function validateSubmitPayload(payload, type) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new Error(`${type} payload must be a JSON object.`);
  }
  if (type === "bridge proof submit") {
    const bundleKeys = ["burn_bundle", "governance_bundle", "message_bundle"].filter((key) => payload[key] && typeof payload[key] === "object");
    if (bundleKeys.length !== 1) {
      throw new Error("Bridge proof submit JSON must include exactly one of burn_bundle, governance_bundle, or message_bundle.");
    }
  }
  if (type === "bridge message submit") {
    if (!payload.message_bundle || typeof payload.message_bundle !== "object") {
      throw new Error("Bridge message submit JSON must include a message_bundle object.");
    }
    if (payload.settlement !== undefined && payload.settlement !== null && typeof payload.settlement !== "object") {
      throw new Error("settlement must be an object when provided.");
    }
  }
}

async function submitAdvancedPayload(path, editor, type, metaFactory) {
  try {
    const payload = parseJsonInput(editor, type);
    validateSubmitPayload(payload, type);
    const environment = requestEnvironmentName();
    if (!environment) {
      throw new Error("Select an environment before submitting.");
    }
    const localRequest = {
      environment,
      ...payload,
    };
    setRequestAndResponsePreview(localRequest, {});
    setBanner(requestStatus, `Submitting ${type}...`, "muted");
    const { response, result } = await requestJson(path, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(localRequest),
    });
    setRequestAndResponsePreview(localRequest, result);
    if (!response.ok || !result.ok) {
      setBanner(requestStatus, `${type} failed with upstream status ${result.upstream_status || response.status}.`, "error");
      setBanner(submissionSummary, result.error || `${type} failed.`, "error");
      return;
    }
    setBanner(requestStatus, `${type} succeeded with upstream status ${result.upstream_status}.`, "success");
    setBanner(submissionSummary, `${type} succeeded.`, "success");
    recordRequestFromResult(metaFactory(payload), localRequest, result);
  } catch (error) {
    setBanner(requestStatus, `${type} failed: ${error}`, "error");
    setBanner(submissionSummary, String(error), "error");
  }
}

async function fetchCatalog() {
  setBanner(requestStatus, "Loading deployment catalog...", "muted");
  const { result } = await requestJson("/api/catalog");
  state.catalog = result;
  state.environments = result.environments || [];
  renderEnvironmentOptions();
  renderSelectionState();
  initializeEditors();
  requestPreview.textContent = prettyJson({});
  responsePreview.textContent = prettyJson({});
  bridgeSnapshotPreview.textContent = prettyJson({});
  state.bridgeSnapshot = null;
  state.proofLookup = {
    bundle: null,
    artifact: null,
    job: null,
  };
  renderProofLookupResults();
  await Promise.all([
    refreshRemoteTransactionHistory({ silent: true }),
    refreshSccpDiscovery({ silent: true }),
  ]);
  setBanner(
    requestStatus,
    `Loaded ${state.environments.length} environment(s) from ${result.repo_root}.`,
    "success"
  );
}

function clearLocalHistory() {
  Object.keys(state.local.transactionStatuses).forEach((txHashHex) => {
    stopTransactionPolling(txHashHex);
  });
  state.local.recentRequests = [];
  state.local.transactionStatuses = {};
  persistLocalState();
  renderTransactionTracker();
}

function clearBridgeBookmarks() {
  const environment = requestEnvironmentName();
  for (const key of Object.keys(state.local.bridgeBookmarks)) {
    state.local.bridgeBookmarks[key] = (state.local.bridgeBookmarks[key] || []).filter((entry) => entry.environment !== environment);
  }
  persistLocalState();
  renderBridgeBookmarks();
}

function applyBookmarkValue(inputElement, value) {
  if (!value) {
    return;
  }
  inputElement.value = value;
  renderBridgeWorkspace();
}

function initializeEditors() {
  proofSubmitInput.value = prettyJson(buildProofSubmitTemplate());
  bridgeMessageSubmitInput.value = prettyJson(buildBridgeMessageSubmitTemplate());
}

function resumeTrackedTransactions() {
  for (const [txHashHex, tracker] of Object.entries(state.local.transactionStatuses)) {
    if (!tracker.terminal) {
      pollTransactionStatus(txHashHex, { immediate: true }).catch((error) => {
        console.error("transaction poll failed", error);
      });
    }
  }
}

environmentSelect.addEventListener("change", async () => {
  authorityInput.value = "";
  state.bridgeSnapshot = null;
  state.remoteTransactionHistory = null;
  state.proofLookup = {
    bundle: null,
    artifact: null,
    job: null,
  };
  renderSelectionState();
  renderProofLookupResults();
  initializeEditors();
  await Promise.all([
    refreshRemoteTransactionHistory({ silent: true }),
    refreshSccpDiscovery({ silent: true }),
  ]);
});

contractFilter.addEventListener("input", () => {
  state.currentContract = null;
  state.currentEntrypoint = null;
  renderSelectionState();
});

contractSelect.addEventListener("change", () => {
  state.currentContract = selectedContract();
  renderContractMeta();
  renderEntrypoints();
  state.currentEntrypoint = selectedEntrypoint();
  renderEntrypointMeta();
});

entrypointSelect.addEventListener("change", () => {
  state.currentEntrypoint = selectedEntrypoint();
  renderEntrypointMeta();
});

authorityInput.addEventListener("input", () => {
  renderBridgeWorkspace();
});

bridgeActionSelect.addEventListener("change", renderBridgeWorkspace);

[
  bridgeAssetKeyInput,
  bridgeRouteInput,
  bridgeTransferInput,
  bridgeMessageIdInput,
  bridgeAssetDefinitionInput,
  bridgeLocalAssetInput,
  bridgeVaultAccountInput,
  bridgeRegistrantInput,
  bridgeRecipientInput,
  bridgeHomeDomainInput,
  bridgeRemoteDomainInput,
  bridgeDecimalsInput,
  bridgeAmountInput,
  sccpMessageKindSelect,
  sccpSourceDomainInput,
  sccpDestDomainInput,
  sccpNonceInput,
  sccpMessageSenderInput,
  sccpFinalityHeightInput,
].forEach((element) => {
  element.addEventListener("input", () => {
    renderBridgeWorkspace();
  });
});

proofLookupMessageIdInput.addEventListener("input", () => {
  const normalized = normalizeHexIdentifier(proofLookupMessageIdInput.value);
  if (normalized) {
    proofLookupMessageIdInput.value = normalized;
  }
});

refreshCatalogButton.addEventListener("click", () => {
  fetchCatalog().catch((error) => {
    setBanner(requestStatus, `Failed to refresh catalog: ${error}`, "error");
  });
});

refreshTransactionHistoryButton.addEventListener("click", () => {
  refreshRemoteTransactionHistory().catch((error) => {
    setBanner(transactionSummary, `Failed to refresh remote transaction history: ${error}`, "error");
  });
});

clearLocalHistoryButton.addEventListener("click", clearLocalHistory);
bookmarkCurrentBridgeButton.addEventListener("click", bookmarkCurrentBridgeValues);
clearBridgeBookmarksButton.addEventListener("click", clearBridgeBookmarks);

bookmarkAssetKeySelect.addEventListener("change", () => applyBookmarkValue(bridgeAssetKeyInput, bookmarkAssetKeySelect.value));
bookmarkRouteSelect.addEventListener("change", () => applyBookmarkValue(bridgeRouteInput, bookmarkRouteSelect.value));
bookmarkTransferSelect.addEventListener("change", () => applyBookmarkValue(bridgeTransferInput, bookmarkTransferSelect.value));
bookmarkMessageIdSelect.addEventListener("change", () => {
  applyBookmarkValue(bridgeMessageIdInput, bookmarkMessageIdSelect.value);
  proofLookupMessageIdInput.value = bookmarkMessageIdSelect.value;
});
recentProofLookupSelect.addEventListener("change", () => {
  proofLookupMessageIdInput.value = recentProofLookupSelect.value;
});

templatePayloadButton.addEventListener("click", fillPayloadTemplate);
clearPayloadButton.addEventListener("click", () => {
  payloadInput.value = "";
});
runRequestButton.addEventListener("click", runRequest);
copyRequestButton.addEventListener("click", () => copyText(requestPreview.textContent));
copyResponseButton.addEventListener("click", () => copyText(responsePreview.textContent));

selectBridgeContractButton.addEventListener("click", () => {
  selectContractByKey(BRIDGE_CONTRACT_KEY);
});
refreshBridgeSnapshotButton.addEventListener("click", () => {
  refreshBridgeSnapshot().catch((error) => {
    setBanner(bridgeSummary, `Bridge snapshot failed: ${error}`, "error");
  });
});
copyBridgeSnapshotButton.addEventListener("click", () => copyText(bridgeSnapshotPreview.textContent));
buildBridgeRequestButton.addEventListener("click", buildBridgeRequestFromForm);
bridgeTemplateButtons.forEach((button) => {
  button.addEventListener("click", () => {
    applyBridgeTemplate(button.dataset.bridgeTemplate);
  });
});

refreshSccpDiscoveryButton.addEventListener("click", () => {
  refreshSccpDiscovery().catch((error) => {
    setBanner(proofStatusSummary, `Failed to refresh SCCP discovery: ${error}`, "error");
  });
});
lookupSccpAllButton.addEventListener("click", () => {
  lookupAllSccpResources().catch((error) => {
    setBanner(proofLookupSummary, `Proof lookup failed: ${error}`, "error");
  });
});
lookupSccpBundleButton.addEventListener("click", () => {
  lookupSccpResource("bundle").catch((error) => {
    setBanner(proofLookupSummary, `Bundle lookup failed: ${error}`, "error");
  });
});
lookupSccpArtifactButton.addEventListener("click", () => {
  lookupSccpResource("artifact").catch((error) => {
    setBanner(proofLookupSummary, `Artifact lookup failed: ${error}`, "error");
  });
});
lookupSccpJobButton.addEventListener("click", () => {
  lookupSccpResource("job").catch((error) => {
    setBanner(proofLookupSummary, `Job lookup failed: ${error}`, "error");
  });
});

loadLookedUpBundleButton.addEventListener("click", loadLookedUpBundleIntoEditors);
buildProofSubmitTemplateButton.addEventListener("click", () => {
  proofSubmitInput.value = prettyJson(buildProofSubmitTemplate());
  setBanner(submissionSummary, "Built a bridge proof submit template from the current bridge fields and live proof lookup state.", "success");
});
buildBridgeMessageTemplateButton.addEventListener("click", () => {
  bridgeMessageSubmitInput.value = prettyJson(buildBridgeMessageSubmitTemplate());
  setBanner(submissionSummary, "Built a bridge message submit template from the current bridge fields and live proof lookup state.", "success");
});
insertSettlementHelperButton.addEventListener("click", insertSettlementHelper);
submitBridgeProofButton.addEventListener("click", () => {
  submitAdvancedPayload("/api/bridge/proofs/submit", proofSubmitInput, "bridge proof submit", () => ({
    actionType: "bridge_proof_submit",
    environment: requestEnvironmentName(),
    contractKey: BRIDGE_CONTRACT_KEY,
    contractAddress: bridgeContractForEnvironment(state.currentEnvironment)?.contract_address,
    entrypoint: "SubmitBridgeProof",
    requestPath: "/api/bridge/proofs/submit",
    bridgeRelated: true,
  }));
});
submitBridgeMessageButton.addEventListener("click", () => {
  submitAdvancedPayload("/api/bridge/messages", bridgeMessageSubmitInput, "bridge message submit", () => ({
    actionType: "bridge_message_submit",
    environment: requestEnvironmentName(),
    contractKey: BRIDGE_CONTRACT_KEY,
    contractAddress: bridgeContractForEnvironment(state.currentEnvironment)?.contract_address,
    entrypoint: "SubmitBridgeMessage",
    requestPath: "/api/bridge/messages",
    bridgeRelated: true,
  }));
});

initializeEditors();
renderBridgeWorkspace();
renderSccpDiscovery();
renderProofLookupResults();
renderTransactionTracker();
resumeTrackedTransactions();

fetchCatalog().catch((error) => {
  setBanner(requestStatus, `Failed to load catalog: ${error}`, "error");
  responsePreview.textContent = prettyJson({
    ok: false,
    error: String(error),
  });
});
