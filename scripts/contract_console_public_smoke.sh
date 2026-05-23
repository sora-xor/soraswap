#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

public_env="${SORASWAP_PUBLIC_ENV:-testnet}"
case "$public_env" in
  testnet|production)
    ;;
  *)
    echo "contract_console_public_smoke.sh only supports SORASWAP_PUBLIC_ENV=testnet|production; got $public_env" >&2
    exit 1
    ;;
esac

if [[ "${SORASWAP_ALLOW_TESTNET_MUTATIONS:-0}" != "1" ]]; then
  echo "$public_env console smoke is mutation-gated; export SORASWAP_ALLOW_TESTNET_MUTATIONS=1 to continue" >&2
  exit 1
fi

config="$(client_config_or_default "$public_env")"
ensure_client "$config"
ensure_authority "$config"
prepare_env_chain_state "$public_env" "$config"
ensure_public_signer_ready "$config" "$SORASWAP_AUTHORITY" readonly
ensure_can_register_trigger_permission "$config" "$SORASWAP_AUTHORITY"
ensure_deployment_records_current "$public_env" "$config"

bridge_record="$(deployment_record_path_for_env "$public_env" bridge.sccp_bridge)"
require_file "$bridge_record"

report_dir="$(deployments_dir_for_env "$public_env")"
timestamp="$(utc_timestamp)"
latest_report="$report_dir/contract_console_smoke.latest.json"
timestamped_report="$report_dir/contract_console_smoke.${timestamp}.json"
mkdir -p "$report_dir"
public_env_upper="${(U)public_env}"
run_suffix_var="SORASWAP_${public_env_upper}_RUN_SUFFIX"
bridge_route_var="SORASWAP_${public_env_upper}_BRIDGE_ROUTE"
bridge_recent_limit_var="SORASWAP_${public_env_upper}_BRIDGE_RECENT_LIMIT"
bridge_message_id_var="SORASWAP_${public_env_upper}_BRIDGE_MESSAGE_ID"
bridge_auto_seed_var="SORASWAP_${public_env_upper}_BRIDGE_AUTO_SEED"
run_suffix="${(P)run_suffix_var:-${SORASWAP_PUBLIC_RUN_SUFFIX:-$timestamp}}"
bridge_route_hint="${(P)bridge_route_var:-${SORASWAP_PUBLIC_BRIDGE_ROUTE:-${SORASWAP_BRIDGE_ROUTE:-eth_sora_usdt}}}"
recent_limit="${(P)bridge_recent_limit_var:-${SORASWAP_PUBLIC_BRIDGE_RECENT_LIMIT:-25}}"
bridge_auto_seed="${(P)bridge_auto_seed_var:-${SORASWAP_PUBLIC_BRIDGE_AUTO_SEED:-auto}}"
contracts_latest_path="$report_dir/contracts.latest.json"
deploy_latest_path="$report_dir/deploy.latest.json"
contracts_snapshot_json='null'
deploy_snapshot_json='null'
cached_console_report_json='null'
cached_console_report_path=""

select_cached_console_report_path() {
  local report_dir="$1"
  local route_hint="$2"
  local candidate_path candidate_route
  local -a candidate_paths

  if [[ -f "$latest_report" ]]; then
    printf '%s\n' "$latest_report"
    return 0
  fi

  candidate_paths=("${(@f)$(find "$report_dir" -type f -name 'contract_console_smoke.*.json' ! -name 'contract_console_smoke.latest.json' 2>/dev/null | LC_ALL=C sort -r)}")
  for candidate_path in "${candidate_paths[@]}"; do
    [[ -f "$candidate_path" ]] || continue
    candidate_route="$(jq -r '.bridge.route_hint // .bridge.route // empty' "$candidate_path" 2>/dev/null || true)"
    if [[ -n "$candidate_route" && "$candidate_route" == "$route_hint" ]]; then
      printf '%s\n' "$candidate_path"
      return 0
    fi
  done

  if (( ${#candidate_paths[@]} > 0 )); then
    printf '%s\n' "${candidate_paths[1]}"
  fi
}

if [[ -f "$contracts_latest_path" ]]; then
  contracts_snapshot_json="$(cat "$contracts_latest_path")"
fi
if [[ -f "$deploy_latest_path" ]]; then
  deploy_snapshot_json="$(cat "$deploy_latest_path")"
fi
cached_console_report_path="$(select_cached_console_report_path "$report_dir" "$bridge_route_hint" || true)"
if [[ -n "$cached_console_report_path" ]] && [[ -f "$cached_console_report_path" ]]; then
  cached_console_report_json="$(cat "$cached_console_report_path")"
fi

host="${SORASWAP_CONTRACT_CONSOLE_HOST:-127.0.0.1}"
port="${SORASWAP_CONTRACT_CONSOLE_PORT:-4273}"
base_url="http://${host}:${port}"
console_log="$(mktemp -t "soraswap-contract-console-${public_env}-log")"
console_pid=""

cleanup() {
  if [[ -n "$console_pid" ]] && kill -0 "$console_pid" >/dev/null 2>&1; then
    kill "$console_pid" >/dev/null 2>&1 || true
    wait "$console_pid" >/dev/null 2>&1 || true
  fi
  rm -f "$console_log"
}

trap cleanup EXIT

ensure_console_port_available() {
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "contract console smoke requires a free local port ${host}:${port}; set SORASWAP_CONTRACT_CONSOLE_PORT to override" >&2
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >&2 || true
    exit 1
  fi
}

http_json() {
  local method="$1"
  local url="$2"
  local payload="${3:-}"
  local response http_status body
  local -a curl_args

  curl_args=(
    -sS
    -H 'Accept: application/json'
    -w $'\n%{http_code}'
    -X "$method"
  )
  if [[ "$method" == "POST" ]]; then
    curl_args+=(
      -H 'Content-Type: application/json'
      -d "$payload"
    )
  fi
  curl_args+=("$url")

  response="$(curl "${curl_args[@]}")"
  http_status="${response##*$'\n'}"
  body="${response%$'\n'*}"

  if [[ "$http_status" != 2* ]]; then
    echo "request failed: $method $url -> HTTP $http_status" >&2
    echo "$body" >&2
    return 1
  fi

  printf '%s\n' "$body"
}

wait_for_console() {
  local attempt=1
  while (( attempt <= 20 )); do
    if curl -fsS "$base_url/api/catalog" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    attempt=$(( attempt + 1 ))
  done

  echo "timed out waiting for contract console at $base_url" >&2
  cat "$console_log" >&2 || true
  return 1
}

poll_tx_status() {
  local tx_hash="$1"
  local attempt=1
  local result status_kind
  while (( attempt <= 20 )); do
    result="$(http_json GET "$base_url/api/pipeline/transactions/status?environment=${public_env}&hash=${tx_hash}")"
    status_kind="$(jq -r '.status_kind // empty' <<<"$result")"
    case "$status_kind" in
      Applied|Committed|Rejected|Expired|NotFound|TimedOut)
        printf '%s\n' "$result"
        return 0
        ;;
    esac
    sleep 1
    attempt=$(( attempt + 1 ))
  done

  printf '%s\n' "${result:-{}}"
  return 0
}

inspect_view_result() {
  local inspect_json="$1"
  local entrypoint="$2"

  jq -cer \
    --arg entrypoint "$entrypoint" \
    '.views[]
      | select(.entrypoint == $entrypoint)
      | if .ok == true then .response_json.result else error("bridge inspect entrypoint failed") end' \
    <<<"$inspect_json"
}

rejection_signal_text() {
  local payload_json="$1"
  python3 - "$payload_json" <<'PY'
import base64
import json
import re
import sys

payload = json.loads(sys.argv[1])
values = [
    payload.get("rejection_reason"),
    (payload.get("response_json") or {}).get("rejection_reason"),
    ((payload.get("response_json") or {}).get("status") or {}).get("rejection_reason"),
    payload.get("response_text"),
]
parts = []
for value in values:
    if not isinstance(value, str) or not value:
        continue
    parts.append(value)
    try:
        raw = base64.b64decode(value, validate=False)
    except Exception:
        continue
    printable = b" ".join(re.findall(rb"[ -~]{4,}", raw))
    if printable:
        parts.append(printable.decode("utf-8", "ignore"))
print(" ".join(parts).lower())
PY
}

message_replay_rejection_matches() {
  local payload_json="$1"
  local rejection_text
  rejection_text="$(rejection_signal_text "$payload_json")"
  [[ "$rejection_text" == *"message consumed"* ]] \
    || [[ "$rejection_text" == *"already"* ]] \
    || [[ "$rejection_text" == *"duplicate"* ]] \
    || [[ "$rejection_text" == *"replay"* ]] \
    || [[ "$rejection_text" == *"assertion failed (constraint violation)"* ]] \
    || [[ "$rejection_text" == *"constraint violation"* ]] \
    || [[ "$rejection_text" == *"proof range overlaps existing proof"* ]] \
    || [[ "$rejection_text" == *"bridge proof range overlaps existing proof"* ]] \
    || [[ "$rejection_text" == *"range overlaps existing proof"* ]]
}

proof_replay_rejection_matches() {
  local payload_json="$1"
  local rejection_text
  rejection_text="$(rejection_signal_text "$payload_json")"
  [[ "$rejection_text" == *"already"* ]] \
    || [[ "$rejection_text" == *"duplicate"* ]] \
    || [[ "$rejection_text" == *"replay"* ]] \
    || [[ "$rejection_text" == *"proof range overlaps existing proof"* ]] \
    || [[ "$rejection_text" == *"bridge proof range overlaps existing proof"* ]] \
    || [[ "$rejection_text" == *"range overlaps existing proof"* ]]
}

rejection_status_json() {
  local payload_json="$1"
  local rejection_text
  rejection_text="$(rejection_signal_text "$payload_json")"
  jq -cn \
    --arg rejection_reason "${rejection_text:-rejected}" \
    '{status_kind: "Rejected", rejection_reason: $rejection_reason, immediate: true}'
}

derive_route_literal() {
  local selected_recent_item_json="$1"
  local job_result_json="$2"
  local route_hint="$3"
  local route_literal

  route_literal="$(
    jq -r '
      .route_id
      // .payload_projection.Transfer.route_id.TextUtf8.value
      // .payload_projection.Transfer.route_id.value
      // .response_json.payload_projection.Transfer.route_id.TextUtf8.value
      // .response_json.payload_projection.Transfer.route_id.value
      // empty
    ' <<<"$selected_recent_item_json" 2>/dev/null || true
  )"
  if [[ -n "$route_literal" && "$route_literal" != "null" ]]; then
    printf '%s\n' "$route_literal"
    return 0
  fi

  route_literal="$(
    jq -r '
      .response_json.payload_projection.Transfer.route_id.TextUtf8.value
      // .response_json.payload_projection.Transfer.route_id.value
      // empty
    ' <<<"$job_result_json" 2>/dev/null || true
  )"
  if [[ -n "$route_literal" && "$route_literal" != "null" ]]; then
    printf '%s\n' "$route_literal"
    return 0
  fi

  if [[ -n "$route_hint" ]]; then
    printf '%s\n' "$route_hint"
    return 0
  fi

  return 1
}

lookup_has_response_json() {
  local lookup_json="$1"
  jq -e '(.ok == true) and (.response_json != null)' <<<"$lookup_json" >/dev/null 2>&1
}

prefer_cached_lookup_result() {
  local current_lookup_json="$1"
  local cached_lookup_json="$2"

  if lookup_has_response_json "$current_lookup_json"; then
    printf '%s\n' "$current_lookup_json"
    return 0
  fi
  if lookup_has_response_json "$cached_lookup_json"; then
    printf '%s\n' "$cached_lookup_json"
    return 0
  fi
  printf '%s\n' "$current_lookup_json"
}

auto_seed_bridge_inventory_enabled() {
  case "$bridge_auto_seed" in
    1|true|yes|on)
      return 0
      ;;
    auto)
      [[ "$public_env" == "testnet" ]]
      return
      ;;
    *)
      return 1
      ;;
  esac
}

bridge_inventory_nonce() {
  local nonce_var="SORASWAP_${public_env_upper}_BRIDGE_NONCE"
  local nonce="${(P)nonce_var:-${SORASWAP_PUBLIC_BRIDGE_NONCE:-}}"
  if [[ -n "$nonce" ]]; then
    printf '%s\n' "$nonce"
    return 0
  fi
  python3 - <<'PY'
import time
print(time.time_ns() & ((1 << 64) - 1))
PY
}

seed_sccp_bridge_transfer_inventory() {
  local gov_bin gas_asset_id nonce output
  local source_domain dest_domain asset_home_domain asset_id_codec asset_id amount
  local sender_codec sender recipient_codec route_id_codec
  local sender_var="SORASWAP_${public_env_upper}_BRIDGE_SENDER"
  local amount_var="SORASWAP_${public_env_upper}_BRIDGE_AMOUNT"

  if ! auto_seed_bridge_inventory_enabled; then
    return 1
  fi

  gov_bin="$(gov_instruction_bin)"
  gas_asset_id="$(gas_metadata_asset_id_for_config "$config")"
  nonce="$(bridge_inventory_nonce)"
  source_domain="${SORASWAP_PUBLIC_BRIDGE_SOURCE_DOMAIN:-1}"
  dest_domain="${SORASWAP_PUBLIC_BRIDGE_DEST_DOMAIN:-0}"
  asset_home_domain="${SORASWAP_PUBLIC_BRIDGE_ASSET_HOME_DOMAIN:-1}"
  asset_id_codec="${SORASWAP_PUBLIC_BRIDGE_ASSET_ID_CODEC:-1}"
  asset_id="${SORASWAP_PUBLIC_BRIDGE_ASSET_ID:-genesis_bridge_asset}"
  amount="${(P)amount_var:-${SORASWAP_PUBLIC_BRIDGE_AMOUNT:-1}}"
  sender_codec="${SORASWAP_PUBLIC_BRIDGE_SENDER_CODEC:-2}"
  sender="${(P)sender_var:-${SORASWAP_PUBLIC_BRIDGE_SENDER:-0x52908400098527886E0F7030069857D2E4169EE7}}"
  recipient_codec="${SORASWAP_PUBLIC_BRIDGE_RECIPIENT_CODEC:-1}"
  route_id_codec="${SORASWAP_PUBLIC_BRIDGE_ROUTE_ID_CODEC:-1}"

  echo "no unconsumed SCCP transfer found for route $bridge_route_hint; creating a proof-gated testnet transfer message" >&2
  output="$("$gov_bin" record-sccp-transfer-ivm-proved \
    --config "$config" \
    --gas-asset-id "$gas_asset_id" \
    --gas-limit "${SORASWAP_SCCP_IVM_GAS_LIMIT:-50000000}" \
    --source-domain "$source_domain" \
    --dest-domain "$dest_domain" \
    --nonce "$nonce" \
    --asset-home-domain "$asset_home_domain" \
    --asset-id-codec "$asset_id_codec" \
    --asset-id "$asset_id" \
    --amount "$amount" \
    --sender-codec "$sender_codec" \
    --sender "$sender" \
    --recipient-codec "$recipient_codec" \
    --recipient "$SORASWAP_AUTHORITY" \
    --route-id-codec "$route_id_codec" \
    --route-id "$bridge_route_hint")"
  printf '%s\n' "$output"
}

ensure_console_port_available
python3 "$SORASWAP_ROOT/scripts/serve_contract_console.py" \
  --host "$host" \
  --port "$port" \
  --signer "${public_env}=${config}" \
  --authority "${public_env}=${SORASWAP_AUTHORITY}" \
  >"$console_log" 2>&1 &
console_pid="$!"
wait_for_console

catalog_json="$(http_json GET "$base_url/api/catalog")"
jq -e --arg environment "$public_env" '.environments[] | select(.name == $environment)' <<<"$catalog_json" >/dev/null
bridge_contract_address="$(jq -er --arg environment "$public_env" '.environments[] | select(.name == $environment) | .contracts[] | select(.contract_key == "bridge.sccp_bridge") | .contract_address' <<<"$catalog_json")"
jq -e --arg environment "$public_env" '.environments[] | select(.name == $environment) | .mutation_policy.allowed == true' <<<"$catalog_json" >/dev/null

capabilities_json="$(http_json GET "$base_url/api/sccp/capabilities?environment=${public_env}")"
manifests_json="$(http_json GET "$base_url/api/sccp/manifests?environment=${public_env}")"
recent_result_json="$(http_json GET "$base_url/api/sccp/messages/recent?environment=${public_env}&limit=${recent_limit}")"

message_id="${(P)bridge_message_id_var:-${SORASWAP_PUBLIC_BRIDGE_MESSAGE_ID:-}}"
selection_source="recent_messages"
selected_recent_item_json='null'
inspect_json=""
route=""
if [[ -n "$message_id" ]]; then
  selection_source="env_override"
  selected_recent_item_json="$(jq -cr --arg message_id "$message_id" '
    first(.response_json.items[]? | select((.message_id_hex // "") == $message_id)) // null
  ' <<<"$recent_result_json")"
else
  while IFS= read -r candidate_item_json; do
    [[ -n "$candidate_item_json" ]] || continue
    candidate_message_id="$(jq -r '.message_id_hex // empty' <<<"$candidate_item_json")"
    candidate_route="$(jq -r '.route_id // empty' <<<"$candidate_item_json")"
    candidate_inspect_payload="$(jq -cn \
      --arg environment "$public_env" \
      --arg route "$candidate_route" \
      --arg message_id "$candidate_message_id" \
      '{
        environment: $environment,
        route: $route,
        message_id: $message_id
      }')"
    if ! candidate_inspect_json="$(http_json POST "$base_url/api/bridge/inspect" "$candidate_inspect_payload" 2>/dev/null)"; then
      continue
    fi
    if ! candidate_consumed="$(inspect_view_result "$candidate_inspect_json" inbound_consumed 2>/dev/null)"; then
      continue
    fi
    if [[ "$candidate_consumed" == "0" ]]; then
      message_id="$candidate_message_id"
      route="$candidate_route"
      selected_recent_item_json="$candidate_item_json"
      inspect_json="$candidate_inspect_json"
      break
    fi
  done < <(
    jq -cr \
      --arg route "$bridge_route_hint" \
      '.response_json.items[]?
        | select((.kind // "") == "transfer" and (.target_domain // -1) == 0 and (.route_id // "") == $route)' \
      <<<"$recent_result_json"
  )

  if [[ -z "$message_id" ]]; then
    selection_source="recent_messages_any_route"
    while IFS= read -r candidate_item_json; do
      [[ -n "$candidate_item_json" ]] || continue
      candidate_message_id="$(jq -r '.message_id_hex // empty' <<<"$candidate_item_json")"
      candidate_route="$(jq -r '.route_id // empty' <<<"$candidate_item_json")"
      candidate_inspect_payload="$(jq -cn \
        --arg environment "$public_env" \
        --arg route "$candidate_route" \
        --arg message_id "$candidate_message_id" \
        '{
          environment: $environment,
          route: $route,
          message_id: $message_id
        }')"
      if ! candidate_inspect_json="$(http_json POST "$base_url/api/bridge/inspect" "$candidate_inspect_payload" 2>/dev/null)"; then
        continue
      fi
      if ! candidate_consumed="$(inspect_view_result "$candidate_inspect_json" inbound_consumed 2>/dev/null)"; then
        continue
      fi
      if [[ "$candidate_consumed" == "0" ]]; then
        message_id="$candidate_message_id"
        route="$candidate_route"
        selected_recent_item_json="$candidate_item_json"
        inspect_json="$candidate_inspect_json"
        break
      fi
    done < <(
      jq -cr \
        '.response_json.items[]?
          | select((.kind // "") == "transfer" and (.target_domain // -1) == 0)' \
        <<<"$recent_result_json"
    )
  fi
fi

if [[ -z "$message_id" ]]; then
  if auto_seed_bridge_inventory_enabled; then
    if ! seeded_result_json="$(seed_sccp_bridge_transfer_inventory)"; then
      echo "failed to create a proof-gated SCCP transfer message for route $bridge_route_hint" >&2
      exit 1
    fi
    seeded_message_id="$(jq -r '.message_id // empty' <<<"$seeded_result_json" 2>/dev/null || true)"
    if [[ -n "$seeded_message_id" ]]; then
      selection_source="seeded_sccp_transfer"
      message_id="$seeded_message_id"
      route="$bridge_route_hint"
      recent_result_json="$(http_json GET "$base_url/api/sccp/messages/recent?environment=${public_env}&limit=${recent_limit}")"
      selected_recent_item_json="$(jq -cr --arg message_id "$message_id" '
        first(.response_json.items[]? | select((.message_id_hex // "") == $message_id)) // null
      ' <<<"$recent_result_json" 2>/dev/null || printf 'null')"
    fi
  fi
fi

if [[ -z "$message_id" ]]; then
  cached_message_id="$(jq -r '.bridge.message_id // empty' <<<"$cached_console_report_json" 2>/dev/null || true)"
  cached_route="$(jq -r '.bridge.route // empty' <<<"$cached_console_report_json" 2>/dev/null || true)"
  if [[ -n "$cached_message_id" ]]; then
    candidate_inspect_payload="$(jq -cn \
      --arg environment "$public_env" \
      --arg route "$cached_route" \
      --arg message_id "$cached_message_id" \
      '{
        environment: $environment,
        route: $route,
        message_id: $message_id
      }')"
    if candidate_inspect_json="$(http_json POST "$base_url/api/bridge/inspect" "$candidate_inspect_payload" 2>/dev/null)" \
      && inspect_view_result "$candidate_inspect_json" inbound_consumed >/dev/null 2>&1; then
      selection_source="cached_evidence"
      message_id="$cached_message_id"
      route="$cached_route"
      inspect_json="$candidate_inspect_json"
      selected_recent_item_json="$(jq -c '.message_selection.selected_recent_item // null' <<<"$cached_console_report_json" 2>/dev/null || printf 'null')"
    fi
  fi
fi

if [[ -z "$message_id" ]]; then
  selection_source="recent_messages_replay_route"
  while IFS= read -r candidate_item_json; do
    [[ -n "$candidate_item_json" ]] || continue
    candidate_message_id="$(jq -r '.message_id_hex // empty' <<<"$candidate_item_json")"
    candidate_route="$(jq -r '.route_id // empty' <<<"$candidate_item_json")"
    candidate_inspect_payload="$(jq -cn \
      --arg environment "$public_env" \
      --arg route "$candidate_route" \
      --arg message_id "$candidate_message_id" \
      '{
        environment: $environment,
        route: $route,
        message_id: $message_id
      }')"
    if ! candidate_inspect_json="$(http_json POST "$base_url/api/bridge/inspect" "$candidate_inspect_payload" 2>/dev/null)"; then
      continue
    fi
    if ! inspect_view_result "$candidate_inspect_json" inbound_consumed >/dev/null 2>&1; then
      continue
    fi
    message_id="$candidate_message_id"
    route="$candidate_route"
    selected_recent_item_json="$candidate_item_json"
    inspect_json="$candidate_inspect_json"
    break
  done < <(
    jq -cr \
      --arg route "$bridge_route_hint" \
      '.response_json.items[]?
        | select((.kind // "") == "transfer" and (.target_domain // -1) == 0 and (.route_id // "") == $route)' \
      <<<"$recent_result_json"
  )
fi

if [[ -z "$message_id" ]]; then
  selection_source="recent_messages_replay_any_route"
  while IFS= read -r candidate_item_json; do
    [[ -n "$candidate_item_json" ]] || continue
    candidate_message_id="$(jq -r '.message_id_hex // empty' <<<"$candidate_item_json")"
    candidate_route="$(jq -r '.route_id // empty' <<<"$candidate_item_json")"
    candidate_inspect_payload="$(jq -cn \
      --arg environment "$public_env" \
      --arg route "$candidate_route" \
      --arg message_id "$candidate_message_id" \
      '{
        environment: $environment,
        route: $route,
        message_id: $message_id
      }')"
    if ! candidate_inspect_json="$(http_json POST "$base_url/api/bridge/inspect" "$candidate_inspect_payload" 2>/dev/null)"; then
      continue
    fi
    if ! inspect_view_result "$candidate_inspect_json" inbound_consumed >/dev/null 2>&1; then
      continue
    fi
    message_id="$candidate_message_id"
    route="$candidate_route"
    selected_recent_item_json="$candidate_item_json"
    inspect_json="$candidate_inspect_json"
    break
  done < <(
    jq -cr \
      '.response_json.items[]?
        | select((.kind // "") == "transfer" and (.target_domain // -1) == 0)' \
      <<<"$recent_result_json"
  )
fi

if [[ -z "$message_id" ]]; then
  echo "unable to auto-select an unconsumed SORA-targeted bridge transfer for route $bridge_route_hint; set ${bridge_message_id_var} to override" >&2
  exit 1
fi

bundle_result_json="$(http_json GET "$base_url/api/sccp/proofs/message/${message_id}?environment=${public_env}")"
artifact_result_json="$(http_json GET "$base_url/api/sccp/artifacts/message/${message_id}?environment=${public_env}")"
job_result_json="$(http_json GET "$base_url/api/sccp/jobs/message/${message_id}?environment=${public_env}")"
cached_bundle_result_json="$(jq -c '.discovery.bundle_lookup // null' <<<"$cached_console_report_json" 2>/dev/null || printf 'null')"
cached_artifact_result_json="$(jq -c '.discovery.artifact_lookup // null' <<<"$cached_console_report_json" 2>/dev/null || printf 'null')"
cached_job_result_json="$(jq -c '.discovery.job_lookup // null' <<<"$cached_console_report_json" 2>/dev/null || printf 'null')"
bundle_result_json="$(prefer_cached_lookup_result "$bundle_result_json" "$cached_bundle_result_json")"
artifact_result_json="$(prefer_cached_lookup_result "$artifact_result_json" "$cached_artifact_result_json")"
job_result_json="$(prefer_cached_lookup_result "$job_result_json" "$cached_job_result_json")"
bundle_json="$(jq -cer '.response_json' <<<"$bundle_result_json")"

if [[ -z "$route" ]]; then
  route="$(derive_route_literal "$selected_recent_item_json" "$job_result_json" "$bridge_route_hint" || true)"
fi
if [[ -z "$route" ]]; then
  echo "unable to derive a bridge route from the looked-up message bundle; set ${bridge_route_var}" >&2
  exit 1
fi

if [[ -z "$inspect_json" ]]; then
  inspect_payload="$(jq -cn \
    --arg environment "$public_env" \
    --arg route "$route" \
    --arg message_id "$message_id" \
    '{
      environment: $environment,
      route: $route,
      message_id: $message_id
    }')"
  inspect_json="$(http_json POST "$base_url/api/bridge/inspect" "$inspect_payload")"
fi
consumed_before_submit="$(inspect_view_result "$inspect_json" inbound_consumed)"
route_provenance_json="$(inspect_view_result "$inspect_json" route_provenance)"
jq -e '.[0] == 1' <<<"$route_provenance_json" >/dev/null
submission_expectation="apply"
if [[ "$consumed_before_submit" != "0" ]]; then
  if [[ "$selection_source" == "cached_evidence" || "$selection_source" == recent_messages_replay* ]]; then
    submission_expectation="replay_reject"
  else
    echo "selected bridge message $message_id is already consumed on the deployed bridge route $route" >&2
    exit 1
  fi
fi

proof_submit_payload="$(jq -cn \
  --arg environment "$public_env" \
  --argjson message_bundle "$bundle_json" \
  '{
    environment: $environment,
    message_bundle: $message_bundle
  }')"
proof_submit_json="$(http_json POST "$base_url/api/bridge/proofs/submit" "$proof_submit_payload")"
proof_tx_hash="$(jq -r '.tx_hash_hex // empty' <<<"$proof_submit_json")"
if [[ -n "$proof_tx_hash" ]]; then
  proof_status_json="$(poll_tx_status "$proof_tx_hash")"
  if [[ "$submission_expectation" == "replay_reject" ]]; then
    if jq -e '(.status_kind // "") | test("Applied|Committed|Skipped")' <<<"$proof_status_json" >/dev/null 2>&1; then
      :
    else
      jq -e '(.status_kind // "") == "Rejected"' <<<"$proof_status_json" >/dev/null
      proof_replay_rejection_matches "$proof_status_json"
    fi
  else
    jq -e '(.status_kind // "") | test("Applied|Committed")' <<<"$proof_status_json" >/dev/null
  fi
elif [[ "$submission_expectation" == "replay_reject" ]] && proof_replay_rejection_matches "$proof_submit_json"; then
  proof_status_json="$(rejection_status_json "$proof_submit_json")"
elif jq -e '.skipped == true' <<<"$proof_submit_json" >/dev/null 2>&1; then
  proof_skip_reason="$(jq -r '.reason // "bridge proof submission skipped"' <<<"$proof_submit_json")"
  if [[ "${SORASWAP_REQUIRE_STANDALONE_BRIDGE_PROOF:-0}" == "1" ]]; then
    echo "standalone bridge proof submission was skipped by the current Taira app-api: ${proof_skip_reason}" >&2
    exit 1
  fi
  proof_status_json="$(jq -cn \
    --arg reason "$proof_skip_reason" \
    '{status_kind: "Skipped", reason: $reason}')"
else
  echo "bridge proof submission did not return a transaction hash or an explicit skip result" >&2
  echo "$proof_submit_json" >&2
  exit 1
fi

message_submit_payload="$(jq -cn \
  --arg environment "$public_env" \
  --argjson message_bundle "$bundle_json" \
  --arg contract_address "$bridge_contract_address" \
  --arg route "$route" \
  '{
    environment: $environment,
    message_bundle: $message_bundle,
    settlement: {
      contract_address: $contract_address,
      entrypoint: "finalize_inbound",
      route: $route
    }
  }')"
message_submit_json="$(http_json POST "$base_url/api/bridge/messages" "$message_submit_payload")"
message_tx_hash="$(jq -r '.tx_hash_hex // empty' <<<"$message_submit_json")"
if [[ -n "$message_tx_hash" ]]; then
  message_status_json="$(poll_tx_status "$message_tx_hash")"
elif [[ "$submission_expectation" == "replay_reject" ]] && message_replay_rejection_matches "$message_submit_json"; then
  message_status_json="$(rejection_status_json "$message_submit_json")"
else
  echo "bridge message submission did not return a transaction hash" >&2
  echo "$message_submit_json" >&2
  exit 1
fi
if [[ "$submission_expectation" == "replay_reject" ]]; then
  jq -e '(.status_kind // "") == "Rejected"' <<<"$message_status_json" >/dev/null
  message_replay_rejection_matches "$message_status_json"
else
  jq -e '(.status_kind // "") | test("Applied|Committed")' <<<"$message_status_json" >/dev/null
fi

report_json="$(jq -cn \
  --arg generated_at "$timestamp" \
  --arg environment "$public_env" \
  --arg authority "$SORASWAP_AUTHORITY" \
  --arg client_config "$config" \
  --arg torii_url "$(torii_base_from_config "$config")" \
  --arg run_suffix "$run_suffix" \
  --arg selection_source "$selection_source" \
  --arg submission_expectation "$submission_expectation" \
  --arg bridge_route_hint "$bridge_route_hint" \
  --arg route "$route" \
  --arg message_id "$message_id" \
  --arg bridge_contract_address "$bridge_contract_address" \
  --argjson consumed_before_submit "$consumed_before_submit" \
  --argjson chain_fingerprint "${SORASWAP_CHAIN_FINGERPRINT_JSON:-null}" \
  --argjson contracts_snapshot "$contracts_snapshot_json" \
  --argjson deploy_snapshot "$deploy_snapshot_json" \
  --argjson capabilities "$capabilities_json" \
  --argjson manifests "$manifests_json" \
  --argjson recent_messages "$recent_result_json" \
  --argjson selected_recent_item "$selected_recent_item_json" \
  --argjson route_provenance "$route_provenance_json" \
  --argjson bundle_lookup "$bundle_result_json" \
  --argjson artifact_lookup "$artifact_result_json" \
  --argjson job_lookup "$job_result_json" \
  --argjson bridge_inspect "$inspect_json" \
  --argjson proof_submit "$proof_submit_json" \
  --argjson proof_status "$proof_status_json" \
  --argjson message_submit "$message_submit_json" \
  --argjson message_status "$message_status_json" \
  '{
    generated_at: $generated_at,
    environment: $environment,
    authority: $authority,
    client_config: $client_config,
    torii_url: $torii_url,
    run_suffix: $run_suffix,
    chain_fingerprint: $chain_fingerprint,
    contracts_snapshot: {
      generated_at: ($contracts_snapshot.generated_at // null)
    },
    deploy_snapshot: {
      generated_at: ($deploy_snapshot.generated_at // null),
      status: ($deploy_snapshot.status // null)
    },
    bridge: {
      contract_address: $bridge_contract_address,
      route: $route,
      route_hint: $bridge_route_hint,
      message_id: $message_id,
      route_provenance: $route_provenance,
      consumed_before_submit: $consumed_before_submit,
      submission_expectation: $submission_expectation
    },
    message_selection: {
      source: $selection_source,
      selected_recent_item: $selected_recent_item
    },
    discovery: {
      capabilities: $capabilities,
      manifests: $manifests,
      recent_messages: $recent_messages,
      bundle_lookup: $bundle_lookup,
      artifact_lookup: $artifact_lookup,
      job_lookup: $job_lookup
    },
    bridge_inspect: $bridge_inspect,
    submissions: {
      proof_submit: $proof_submit,
      proof_status: $proof_status,
      message_submit: $message_submit,
      message_status: $message_status
    }
  }')"

printf '%s\n' "$report_json" > "$latest_report"
printf '%s\n' "$report_json" > "$timestamped_report"

echo "$public_env contract console smoke ok: $latest_report"
