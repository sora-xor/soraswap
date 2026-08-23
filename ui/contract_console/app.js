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
  sccpRegistry: null,
  proofLookup: {
    bundle: null,
    proofRequest: null,
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
const clearOperatorStateButton = document.querySelector("#clear-operator-state");
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
const sccpRegistryPreview = document.querySelector("#sccp-registry-preview");
const proofLookupMessageIdInput = document.querySelector("#proof-lookup-message-id-input");
const recentProofLookupSelect = document.querySelector("#recent-proof-lookup-select");
const lookupSccpAllButton = document.querySelector("#lookup-sccp-all");
const lookupSccpBundleButton = document.querySelector("#lookup-sccp-bundle");
const lookupSccpProofRequestButton = document.querySelector("#lookup-sccp-proof-request");
const proofLookupSummary = document.querySelector("#proof-lookup-summary");
const sccpBundlePreview = document.querySelector("#sccp-bundle-preview");
const sccpProofRequestPreview = document.querySelector("#sccp-proof-request-preview");

const submissionSummary = document.querySelector("#submission-summary");
const buildProofSubmitTemplateButton = document.querySelector("#build-proof-submit-template");
const buildBridgeMessageTemplateButton = document.querySelector("#build-bridge-message-template");
const proofSubmitInput = document.querySelector("#proof-submit-input");
const bridgeMessageSubmitInput = document.querySelector("#bridge-message-submit-input");
const submitBridgeProofButton = document.querySelector("#submit-bridge-proof");
const submitBridgeMessageButton = document.querySelector("#submit-bridge-message");
const signedConfirmationDialog = document.querySelector("#signed-confirmation-dialog");
const confirmationDetailList = document.querySelector("#confirmation-detail-list");
const confirmationWarning = document.querySelector("#confirmation-warning");
const confirmationPayload = document.querySelector("#confirmation-payload");

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

const SENSITIVE_JSON_KEYS = new Set([
  "privatekey",
  "secret",
  "mnemonic",
  "token",
  "apitoken",
  "apikey",
  "authorization",
  "bearertoken",
  "password",
  "passphrase",
]);

function isSensitiveJsonKey(key) {
  return SENSITIVE_JSON_KEYS.has(String(key).toLowerCase().replace(/[^a-z0-9]/g, ""));
}

function sanitizeJsonForDisplay(value) {
  if (Array.isArray(value)) {
    return value.map((entry) => sanitizeJsonForDisplay(entry));
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .filter(([key]) => !isSensitiveJsonKey(key))
        .map(([key, entry]) => [key, sanitizeJsonForDisplay(entry)]),
    );
  }
  return value;
}

function confirmationValue(value) {
  if (value === undefined || value === null || value === "") {
    return "-";
  }
  return String(value);
}

function renderConfirmationDetails(rows) {
  confirmationDetailList.replaceChildren();
  rows.forEach(([label, value]) => {
    const term = document.createElement("dt");
    term.textContent = label;
    const detail = document.createElement("dd");
    detail.textContent = confirmationValue(value);
    confirmationDetailList.append(term, detail);
  });
}

function confirmSignedMutation(details) {
  if (!signedConfirmationDialog || typeof signedConfirmationDialog.showModal !== "function") {
    return Promise.resolve(window.confirm("Confirm signed call?"));
  }

  const rows = [
    ["Environment", details.environment],
    ["Authority", details.authority],
    ["Contract", details.contract],
    ["Address", details.contractAddress],
    ["Action", details.action],
    ["Entrypoint", details.entrypoint],
  ];
  if (details.gasLimit !== undefined && details.gasLimit !== null) {
    rows.push(["Gas Limit", details.gasLimit]);
  }
  if (details.requestPath) {
    rows.push(["Request Path", details.requestPath]);
  }
  renderConfirmationDetails(rows);

  confirmationPayload.textContent = prettyJson(sanitizeJsonForDisplay(details.payload ?? {}));
  if (details.warningText) {
    confirmationWarning.textContent = details.warningText;
    confirmationWarning.hidden = false;
  } else {
    confirmationWarning.textContent = "";
    confirmationWarning.hidden = true;
  }

  signedConfirmationDialog.returnValue = "";
  return new Promise((resolve) => {
    const handleClose = () => {
      signedConfirmationDialog.removeEventListener("close", handleClose);
      resolve(signedConfirmationDialog.returnValue === "confirm");
    };
    signedConfirmationDialog.addEventListener("close", handleClose);
    signedConfirmationDialog.showModal();
  });
}

function collectGenericPayloadWarnings(payload) {
  const blankStrings = [];
  const nullValues = [];
  const zeroNumbers = [];

  function visit(value, path) {
    const label = path || "payload";
    if (value === null) {
      nullValues.push(label);
      return;
    }
    if (typeof value === "string") {
      if (value.trim() === "") {
        blankStrings.push(label);
      }
      return;
    }
    if (typeof value === "number") {
      if (Object.is(value, 0)) {
        zeroNumbers.push(label);
      }
      return;
    }
    if (Array.isArray(value)) {
      value.forEach((entry, index) => visit(entry, `${label}[${index}]`));
      return;
    }
    if (value && typeof value === "object") {
      Object.entries(value).forEach(([key, entry]) => visit(entry, path ? `${path}.${key}` : key));
    }
  }

  visit(payload, "");
  const pieces = [];
  if (blankStrings.length) {
    pieces.push(`blank strings: ${blankStrings.slice(0, 6).join(", ")}`);
  }
  if (nullValues.length) {
    pieces.push(`null values: ${nullValues.slice(0, 6).join(", ")}`);
  }
  if (zeroNumbers.length) {
    pieces.push(`zero numeric fields: ${zeroNumbers.slice(0, 6).join(", ")}`);
  }
  return pieces.length
    ? `Review this ABI-shaped payload before signing; it contains ${pieces.join(" | ")}. The console does not block these values because optionality is not encoded in the ABI.`
    : "";
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
        .filter(([key]) => !isSensitiveJsonKey(key))
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

  return snapshot;
}

function buildRequestMetadataSnapshot(requestPayload) {
  if (!requestPayload || typeof requestPayload !== "object") {
    return null;
  }
  return {
    authority: requestPayload.authority || null,
    gasLimit: Number.isFinite(Number(requestPayload.gas_limit)) ? Number(requestPayload.gas_limit) : null,
    topLevelKeys: Object.keys(requestPayload).filter((key) => !isSensitiveJsonKey(key)).slice(0, 12),
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
  const lanes = state.sccpRegistry?.response_json?.lanes || [];
  const domainByNetwork = {
    ethereum_mainnet: 1,
    ethereum_sepolia: 1,
    bsc_mainnet: 2,
    bsc_testnet: 2,
    tron_mainnet: 5,
    tron_nile: 5,
    tron_shasta: 5,
  };
  return lanes.map((lane) => {
    const source = lane?.lane_id?.source;
    const target = lane?.lane_id?.target;
    const network = source === "sora_taira" ? target : source;
    return {
      chain: network,
      domain: domainByNetwork[network],
      counterparty_account_codec_key: String(network || "").startsWith("tron_")
        ? "tron_base58check"
        : "evm_hex",
      routes: Array.isArray(lane?.routes) ? lane.routes : [],
    };
  }).filter((entry) => Number.isInteger(entry.domain));
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
  if (direct && typeof direct === "object" && typeof direct.kind === "string") {
    return direct.kind;
  }
  if (result?.upstream_status === 404) {
    return "NotFound";
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
  return statusKind === "Queued" || statusKind === "NotFound" ? "warning" : "muted";
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
      const statusKind = statusKindFromResponse(result) || current.statusKind || "Queued";
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
    statusKind: statusKindFromResponse(result) || "Queued",
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
      const statusKind = statusKindFromTracker(tracker) || (record.txHashHex ? "Queued" : record.submitted ? "Prepared" : "Draft");
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
        const rejectionText = typeof tracker.rejectionReason === "string"
          ? tracker.rejectionReason
          : JSON.stringify(tracker.rejectionReason);
        line.textContent = `Rejection: ${rejectionText}`;
        meta.append(line);
      }
      if (tracker?.statusPayload?.status_summary) {
        const line = document.createElement("div");
        line.className = "record-line";
        line.textContent = `Status: ${tracker.statusPayload.status_summary}`;
        meta.append(line);
      }
      if (Array.isArray(tracker?.statusPayload?.status_diagnostics) && tracker.statusPayload.status_diagnostics.length) {
        const line = document.createElement("div");
        line.className = "record-line";
        line.textContent = `Diagnostics: ${JSON.stringify(tracker.statusPayload.status_diagnostics)}`;
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
    if (mode === "call") {
      const confirmed = await confirmSignedMutation({
        environment: preview.environment,
        authority: preview.authority || currentAuthority(),
        contract: state.currentContract?.contract_key || "Selected contract",
        contractAddress: preview.contract_address,
        action: "Run Call",
        entrypoint: preview.entrypoint,
        gasLimit: preview.gas_limit,
        requestPath: "/api/call",
        payload: preview.payload,
        warningText: collectGenericPayloadWarnings(preview.payload),
      });
      if (!confirmed) {
        setBanner(requestStatus, "Cancelled before submission. No signed call was sent.", "muted");
        responsePreview.textContent = prettyJson({});
        return;
      }
    }
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
  const counterparties = counterpartyCapabilities();

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

    const lines = [
      `Codec: ${counterparty.counterparty_account_codec_key}`,
      `Governed routes: ${counterparty.routes.length}`,
      `Active revisions: ${counterparty.routes.filter((route) => route.activation === "bidirectional").length}`,
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
  sccpRegistryPreview.textContent = prettyJson(state.sccpRegistry || {});
  renderCounterpartyInsights();

  const capabilitiesOk = Boolean(state.sccpCapabilities?.ok);
  const registryOk = Boolean(state.sccpRegistry?.ok);
  if (capabilitiesOk && registryOk) {
    const lanes = state.sccpRegistry.response_json?.lanes?.length || 0;
    const routes = (state.sccpRegistry.response_json?.lanes || [])
      .reduce((count, lane) => count + (lane.routes?.length || 0), 0);
    setBanner(
      proofStatusSummary,
      `Loaded SCCP V1 discovery for ${requestEnvironmentName()}: ${lanes} governed lanes, ${routes} retained route revisions.`,
      "success"
    );
  } else if (state.currentEnvironment) {
    setBanner(
      proofStatusSummary,
      `SCCP discovery is incomplete for ${requestEnvironmentName()}. Capabilities status: ${state.sccpCapabilities?.upstream_status || "-"} | registry status: ${state.sccpRegistry?.upstream_status || "-"}`,
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
    state.sccpRegistry = null;
    renderSccpDiscovery();
    return;
  }
  if (!silent) {
    setBanner(proofStatusSummary, "Refreshing SCCP discovery...", "muted");
  }
  const query = new URLSearchParams({ environment });
  try {
    const [capabilitiesResponse, registryResponse] = await Promise.all([
      requestJson(`/api/sccp/capabilities?${query.toString()}`),
      requestJson(`/api/sccp/registry?${query.toString()}`),
    ]);
    state.sccpCapabilities = capabilitiesResponse.result;
    state.sccpRegistry = registryResponse.result;
    renderSccpDiscovery();
    renderBridgeWorkspace();
  } catch (error) {
    state.sccpCapabilities = { ok: false, error: String(error) };
    state.sccpRegistry = { ok: false, error: String(error) };
    renderSccpDiscovery();
  }
}

function normalizeProofLookupMessageId() {
  const explicit = proofLookupMessageIdInput.value.trim();
  const bridgeValue = bridgeMessageIdInput.value.trim();
  const normalized = normalizeHexIdentifier(explicit || bridgeValue);
  return /^[0-9a-f]{64}$/.test(normalized) && !/^0{64}$/.test(normalized) ? normalized : "";
}

function buildProofSubmitTemplate() {
  return {
    authority: currentAuthority() || "i105...",
    destination_proof_b64: "REPLACE_WITH_CANONICAL_PADDED_BASE64_DESTINATION_PROOF",
  };
}

function buildBridgeMessageSubmitTemplate() {
  return {
    authority: currentAuthority() || "i105...",
    native_proof_b64: "REPLACE_WITH_CANONICAL_PADDED_BASE64_NATIVE_PROOF",
  };
}

function renderProofLookupResults() {
  sccpBundlePreview.textContent = prettyJson(state.proofLookup.bundle || {});
  sccpProofRequestPreview.textContent = prettyJson(state.proofLookup.proofRequest || {});

  const payloadKind = state.proofLookup.bundle?.response_json?.payload_kind || "transfer";
  const targetNetwork = state.proofLookup.proofRequest?.response_json?.target_network || null;
  const messageId = normalizeProofLookupMessageId();
  if (messageId && (state.proofLookup.bundle || state.proofLookup.proofRequest)) {
    setBanner(
      proofLookupSummary,
      `Loaded closed SCCP V1 proof surfaces for ${messageId} | payload=${payloadKind}${targetNetwork ? ` | target=${targetNetwork}` : ""}`,
      "success"
    );
  } else {
    setBanner(proofLookupSummary, "Enter a 64-character lowercase nonzero message id to load the canonical bundle and state-derived proof request.", "muted");
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
    proofRequest: `/api/sccp/proof-requests/${messageId}`,
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
  setBanner(proofLookupSummary, "Loading canonical bundle and proof request...", "muted");
  const query = new URLSearchParams({ environment });
  const [bundle, proofRequest] = await Promise.all([
    requestJson(`/api/sccp/proofs/message/${messageId}?${query.toString()}`),
    requestJson(`/api/sccp/proof-requests/${messageId}?${query.toString()}`),
  ]);
  state.proofLookup.bundle = bundle.result;
  state.proofLookup.proofRequest = proofRequest.result;
  if (bundle.result.ok || proofRequest.result.ok) {
    upsertBookmark("messageIds", messageId);
    rememberProofLookup(messageId, ["bundle", "proofRequest"]);
    renderBridgeBookmarks();
  }
  renderProofLookupResults();
}

function validateSubmitPayload(payload, type) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new Error(`${type} payload must be a JSON object.`);
  }
  const proofField = type === "bridge proof submit" ? "destination_proof_b64" : "native_proof_b64";
  const allowedFields = new Set(["authority", proofField]);
  const unsupportedFields = Object.keys(payload).filter((key) => !allowedFields.has(key));
  if (unsupportedFields.length) {
    throw new Error(`${type} contains retired or unsupported fields: ${unsupportedFields.sort().join(", ")}.`);
  }
  const encodedProof = payload[proofField];
  if (typeof encodedProof !== "string" || !/^[A-Za-z0-9+/]+={0,2}$/.test(encodedProof) || encodedProof.length % 4 !== 0) {
    throw new Error(`${proofField} must be non-empty canonical padded base64.`);
  }
  try {
    if (btoa(atob(encodedProof)) !== encodedProof) {
      throw new Error("non-canonical base64");
    }
  } catch (_error) {
    throw new Error(`${proofField} must be non-empty canonical padded base64.`);
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
    const meta = metaFactory(payload, localRequest);
    setRequestAndResponsePreview(localRequest, {});
    const confirmed = await confirmSignedMutation({
      environment,
      authority: localRequest.authority || currentAuthority(),
      contract: meta.contractKey || BRIDGE_CONTRACT_KEY,
      contractAddress: meta.contractAddress || bridgeContractForEnvironment(state.currentEnvironment)?.contract_address,
      action: type,
      entrypoint: meta.entrypoint,
      requestPath: path,
      payload: localRequest,
    });
    if (!confirmed) {
      setBanner(requestStatus, "Cancelled before submission. No signed call was sent.", "muted");
      setBanner(submissionSummary, `${type} cancelled before submission.`, "muted");
      return;
    }
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
    recordRequestFromResult(meta, localRequest, result);
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
  const repoLabel = result.repo_name || result.repo_root || "repository";
  setBanner(
    requestStatus,
    `Loaded ${state.environments.length} environment(s) from ${repoLabel}.`,
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

function clearOperatorState() {
  Object.keys(state.local.transactionStatuses).forEach((txHashHex) => {
    stopTransactionPolling(txHashHex);
  });
  state.local.recentRequests = [];
  state.local.transactionStatuses = {};
  state.local.bridgeBookmarks = defaultBridgeBookmarks();
  state.local.proofLookups = [];
  state.proofLookup = {
    bundle: null,
    artifact: null,
    job: null,
  };
  persistLocalState();
  renderTransactionTracker();
  renderBridgeBookmarks();
  renderProofLookupHistory();
  renderProofLookupResults();
  setBanner(requestStatus, "Cleared browser-local operator state.", "success");
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
clearOperatorStateButton.addEventListener("click", clearOperatorState);
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
lookupSccpProofRequestButton.addEventListener("click", () => {
  lookupSccpResource("proofRequest").catch((error) => {
    setBanner(proofLookupSummary, `Proof request lookup failed: ${error}`, "error");
  });
});

buildProofSubmitTemplateButton.addEventListener("click", () => {
  proofSubmitInput.value = prettyJson(buildProofSubmitTemplate());
  setBanner(submissionSummary, "Built the closed destination-proof DTO. Replace the placeholder with the canonical prover artifact base64 before submitting.", "success");
});
buildBridgeMessageTemplateButton.addEventListener("click", () => {
  bridgeMessageSubmitInput.value = prettyJson(buildBridgeMessageSubmitTemplate());
  setBanner(submissionSummary, "Built the closed native-proof DTO. Replace the placeholder with canonical native-proof base64 before submitting.", "success");
});
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
