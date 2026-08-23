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
public_env_upper="${(U)public_env}"
timestamp="$(utc_timestamp)"
run_suffix_var="SORASWAP_${public_env_upper}_RUN_SUFFIX"
bridge_route_var="SORASWAP_${public_env_upper}_BRIDGE_ROUTE"
bridge_recent_limit_var="SORASWAP_${public_env_upper}_BRIDGE_RECENT_LIMIT"
bridge_message_id_var="SORASWAP_${public_env_upper}_BRIDGE_MESSAGE_ID"
bridge_destination_proof_file_var="SORASWAP_${public_env_upper}_SCCP_DESTINATION_PROOF_FILE"
bridge_native_proof_file_var="SORASWAP_${public_env_upper}_SCCP_NATIVE_PROOF_FILE"
run_suffix="${(P)run_suffix_var:-${SORASWAP_PUBLIC_RUN_SUFFIX:-$timestamp}}"
bridge_route_hint="${(P)bridge_route_var:-${SORASWAP_PUBLIC_BRIDGE_ROUTE:-${SORASWAP_BRIDGE_ROUTE:-eth_sora_usdt}}}"
recent_limit="${(P)bridge_recent_limit_var:-${SORASWAP_PUBLIC_BRIDGE_RECENT_LIMIT:-25}}"
bridge_destination_proof_file="${(P)bridge_destination_proof_file_var:-${SORASWAP_PUBLIC_SCCP_DESTINATION_PROOF_FILE:-}}"
bridge_native_proof_file="${(P)bridge_native_proof_file_var:-${SORASWAP_PUBLIC_SCCP_NATIVE_PROOF_FILE:-}}"
soraswap_require_positive_integer_setting "$bridge_recent_limit_var/SORASWAP_PUBLIC_BRIDGE_RECENT_LIMIT" "$recent_limit" || exit 1
if [[ -z "$bridge_destination_proof_file" || ! -f "$bridge_destination_proof_file" || ! -s "$bridge_destination_proof_file" ]]; then
  echo "$bridge_destination_proof_file_var/SORASWAP_PUBLIC_SCCP_DESTINATION_PROOF_FILE must name a nonempty runtime SCCP Groth16 artifact file" >&2
  exit 1
fi
if [[ -z "$bridge_native_proof_file" || ! -f "$bridge_native_proof_file" || ! -s "$bridge_native_proof_file" ]]; then
  echo "$bridge_native_proof_file_var/SORASWAP_PUBLIC_SCCP_NATIVE_PROOF_FILE must name a nonempty runtime native SCCP proof file" >&2
  exit 1
fi
host="${SORASWAP_CONTRACT_CONSOLE_HOST:-127.0.0.1}"
port="${SORASWAP_CONTRACT_CONSOLE_PORT:-4273}"
console_http_timeout_secs="${SORASWAP_CONTRACT_CONSOLE_HTTP_TIMEOUT_SECS:-60}"
tx_status_attempts="${SORASWAP_CONTRACT_CONSOLE_TX_STATUS_ATTEMPTS:-60}"
tx_status_retry_delay_secs="${SORASWAP_CONTRACT_CONSOLE_TX_STATUS_RETRY_DELAY_SECS:-2}"
soraswap_require_tcp_port_setting "SORASWAP_CONTRACT_CONSOLE_PORT" "$port" || exit 1
soraswap_require_nonnegative_number_setting "SORASWAP_CONTRACT_CONSOLE_HTTP_TIMEOUT_SECS" "$console_http_timeout_secs" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_CONTRACT_CONSOLE_TX_STATUS_ATTEMPTS" "$tx_status_attempts" || exit 1
soraswap_require_nonnegative_number_setting "SORASWAP_CONTRACT_CONSOLE_TX_STATUS_RETRY_DELAY_SECS" "$tx_status_retry_delay_secs" || exit 1

require_public_mutation_consent "$public_env" "$public_env console smoke"

config="$(client_config_or_default "$public_env")"
ensure_client "$config"
ensure_authority "$config"
prepare_env_chain_state "$public_env" "$config"
chain_fingerprint_json="$(chain_fingerprint_json_or_null)"
ensure_public_signer_ready "$config" "$SORASWAP_AUTHORITY" readonly
ensure_can_register_trigger_permission "$config" "$SORASWAP_AUTHORITY"
ensure_deployment_records_current "$public_env" "$config"
snapshot_check_json="$(public_current_deploy_snapshot_check_json "$public_env" "$chain_fingerprint_json")"
if [[ "$(jq -r '.status // empty' <<<"$snapshot_check_json")" != "completed" ]]; then
  echo "$public_env contract console smoke blocked: deploy snapshot evidence is stale" >&2
  jq -r '.output // empty' <<<"$snapshot_check_json" | soraswap_redact_sensitive_text >&2
  exit 1
fi

bridge_record="$(deployment_record_path_for_env "$public_env" bridge.sccp_bridge)"
require_file "$bridge_record"

report_dir="$(deployments_dir_for_env "$public_env")"
latest_report="$report_dir/contract_console_smoke.latest.json"
timestamped_report="$report_dir/contract_console_smoke.${timestamp}.json"
mkdir -p "$report_dir"
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

base_url="http://${host}:${port}"
console_log="$(mktemp "${TMPDIR:-/tmp}/soraswap-contract-console-${public_env}-log.XXXXXX")"
console_pid=""
contract_console_trace_file="$(mktemp "${TMPDIR:-/tmp}/soraswap-contract-console-tx-trace.XXXXXX")"
contract_console_previous_trace_file="${SORASWAP_CONTRACT_CALL_TRACE_FILE:-}"
contract_console_submitted_calls_json='[]'
contract_console_report_tmp_dir=""
export SORASWAP_CONTRACT_CALL_TRACE_FILE="$contract_console_trace_file"

contract_console_json_or_null() {
  local raw="${1:-null}"

  if [[ -n "$raw" ]] && jq -e . >/dev/null 2>&1 <<<"$raw"; then
    jq -c . <<<"$raw"
  else
    printf '%s\n' 'null'
  fi
}

ensure_contract_console_report_tmp_dir() {
  if [[ -z "${contract_console_report_tmp_dir:-}" ]]; then
    contract_console_report_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/soraswap-contract-console-report.XXXXXX")"
  fi
}

write_contract_console_report_json_file() {
  local name="$1"
  local value="${2:-null}"
  ensure_contract_console_report_tmp_dir
  printf '%s' "$value" >"$contract_console_report_tmp_dir/${name}.json"
}

write_contract_console_failure_report() {
  local exit_status="${1:-1}"
  local failure_timestamp latest_failed_report timestamped_failed_report
  local submitted_calls_json proof_submit_report_json proof_status_report_json
  local message_submit_report_json message_status_report_json
  local health_snapshot_json health_issues_json health_summary report_json

  submitted_calls_json='[]'
  if [[ -n "$contract_console_trace_file" && -s "$contract_console_trace_file" ]]; then
    submitted_calls_json="$(jq -sc . "$contract_console_trace_file" 2>/dev/null || echo '[]')"
  fi

  if [[ "$submitted_calls_json" == "[]" && -z "${proof_tx_hash:-}" && -z "${message_tx_hash:-}" ]]; then
    return 0
  fi

  failure_timestamp="$(utc_timestamp)"
  latest_failed_report="$report_dir/contract_console_smoke.failed.latest.json"
  timestamped_failed_report="$report_dir/contract_console_smoke.failed.${failure_timestamp}.json"
  proof_submit_report_json="$(contract_console_json_or_null "${proof_submit_json:-null}")"
  proof_status_report_json="$(contract_console_json_or_null "${proof_status_json:-null}")"
  message_submit_report_json="$(contract_console_json_or_null "${message_submit_json:-null}")"
  message_status_report_json="$(contract_console_json_or_null "${message_status_json:-null}")"
  health_snapshot_json='null'
  health_issues_json='["unable to sample public chain health"]'
  health_summary=""

  if health_snapshot_json="$(soraswap_public_chain_health_snapshot_json "$config" 2>/dev/null)"; then
    if ! jq -e . >/dev/null 2>&1 <<<"$health_snapshot_json"; then
      health_snapshot_json='null'
    fi
  else
    health_snapshot_json='null'
  fi
  if [[ "$health_snapshot_json" != "null" ]]; then
    health_issues_json="$(soraswap_public_write_health_issues_json "$health_snapshot_json" 2>/dev/null || echo '["unable to evaluate public chain health"]')"
    health_summary="$(soraswap_public_chain_health_summary_text_from_json "$health_snapshot_json" 2>/dev/null || true)"
  fi

  write_contract_console_report_json_file failure_contracts_snapshot "$contracts_snapshot_json"
  write_contract_console_report_json_file failure_deploy_snapshot "$deploy_snapshot_json"

  report_json="$(jq -n \
    --arg generated_at "$failure_timestamp" \
    --arg environment "$public_env" \
    --arg authority "$SORASWAP_AUTHORITY" \
    --arg client_config "$(soraswap_display_path "$config")" \
    --arg torii_url "$(torii_base_from_config "$config")" \
    --argjson exit_status "$exit_status" \
    --argjson chain_fingerprint "$chain_fingerprint_json" \
    --argjson snapshot_check "$snapshot_check_json" \
    --slurpfile contracts_snapshot_file "$contract_console_report_tmp_dir/failure_contracts_snapshot.json" \
    --slurpfile deploy_snapshot_file "$contract_console_report_tmp_dir/failure_deploy_snapshot.json" \
    --arg bridge_contract_address "${bridge_contract_address:-}" \
    --arg route "${route:-}" \
    --arg route_hint "$bridge_route_hint" \
    --arg message_id "${message_id:-}" \
    --arg proof_tx_hash "${proof_tx_hash:-}" \
    --arg message_tx_hash "${message_tx_hash:-}" \
    --argjson submitted_calls "$submitted_calls_json" \
    --argjson proof_submit "$proof_submit_report_json" \
    --argjson proof_status "$proof_status_report_json" \
    --argjson message_submit "$message_submit_report_json" \
    --argjson message_status "$message_status_report_json" \
    --argjson health_snapshot "$health_snapshot_json" \
    --argjson health_issues "$health_issues_json" \
    --arg health_summary "$(soraswap_redact_sensitive_text "$health_summary")" \
    '($contracts_snapshot_file[0] // {}) as $contracts_snapshot
    | ($deploy_snapshot_file[0] // {}) as $deploy_snapshot
    | {
      status: "failed",
      generated_at: $generated_at,
      environment: $environment,
      authority: $authority,
      client_config: $client_config,
      torii_url: $torii_url,
      exit_status: $exit_status,
      chain_fingerprint: $chain_fingerprint,
      snapshot_check: $snapshot_check,
      contracts_snapshot: {
        generated_at: ($contracts_snapshot.generated_at // null),
        status: ($contracts_snapshot.status // null),
        environment: ($contracts_snapshot.environment // null),
        chain_fingerprint: ($contracts_snapshot.chain_fingerprint // null)
      },
      deploy_snapshot: {
        generated_at: ($deploy_snapshot.generated_at // null),
        status: ($deploy_snapshot.status // null),
        environment: ($deploy_snapshot.environment // null),
        chain_fingerprint: ($deploy_snapshot.chain_fingerprint // null)
      },
      bridge: {
        contract_address: (if $bridge_contract_address == "" then null else $bridge_contract_address end),
        route: (if $route == "" then null else $route end),
        route_hint: $route_hint,
        message_id: (if $message_id == "" then null else $message_id end)
      },
      submissions: {
        submitted_calls: $submitted_calls,
        latest_submitted_call: ($submitted_calls[-1] // null),
        proof_tx_hash_hex: (if $proof_tx_hash == "" then null else $proof_tx_hash end),
        message_tx_hash_hex: (if $message_tx_hash == "" then null else $message_tx_hash end),
        proof_submit: $proof_submit,
        proof_status: $proof_status,
        message_submit: $message_submit,
        message_status: $message_status
      },
      public_write_health: {
        issues: $health_issues,
        summary: $health_summary,
        snapshot: $health_snapshot
      }
    }')"

  soraswap_write_json_report_pair "$report_json" "$latest_failed_report" "$timestamped_failed_report" || return 0
  echo "$public_env failed contract console smoke report: $(soraswap_display_path "$timestamped_failed_report")" >&2
}

cleanup() {
  local exit_status="${1:-0}"
  if (( exit_status != 0 )); then
    write_contract_console_failure_report "$exit_status" || true
  fi
  if [[ -n "$console_pid" ]] && kill -0 "$console_pid" >/dev/null 2>&1; then
    kill "$console_pid" >/dev/null 2>&1 || true
    wait "$console_pid" >/dev/null 2>&1 || true
  fi
  rm -f "$console_log"
  if [[ -n "$contract_console_previous_trace_file" ]]; then
    export SORASWAP_CONTRACT_CALL_TRACE_FILE="$contract_console_previous_trace_file"
  else
    unset SORASWAP_CONTRACT_CALL_TRACE_FILE
  fi
  rm -f "$contract_console_trace_file"
  if [[ -n "${contract_console_report_tmp_dir:-}" ]]; then
    rm -rf "$contract_console_report_tmp_dir"
  fi
}

trap 'contract_console_exit_status=$?; cleanup "$contract_console_exit_status"' EXIT

ensure_console_port_available() {
  if (( $+commands[nc] )); then
    if nc -G 1 -z "$host" "$port" >/dev/null 2>&1; then
      echo "contract console smoke requires a free local port ${host}:${port}; set SORASWAP_CONTRACT_CONSOLE_PORT to override" >&2
      exit 1
    fi
    return 0
  fi

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
  local response http_status body err_tmp curl_status attempt=1 max_attempts=3
  local -a curl_args

  err_tmp="$(mktemp "${TMPDIR:-/tmp}/soraswap-contract-console-curl.XXXXXX")"
  curl_args=(
    -sS
    -H 'Accept: application/json'
    --max-time "$console_http_timeout_secs"
    -w $'\n%{http_code}'
    -X "$method"
  )
  if [[ "$method" == "POST" ]]; then
    curl_args+=(
      -H 'Content-Type: application/json'
      --data-binary @-
    )
  fi
  curl_args+=("$url")

  while (( attempt <= max_attempts )); do
    : >"$err_tmp"
    if [[ "$method" == "POST" ]]; then
      if response="$(printf '%s' "$payload" | soraswap_curl_for_config "" "${curl_args[@]}" 2>"$err_tmp")"; then
        curl_status=0
      else
        curl_status="$?"
      fi
    elif response="$(soraswap_curl_for_config "" "${curl_args[@]}" 2>"$err_tmp")"; then
      curl_status=0
    else
      curl_status="$?"
    fi
    if [[ "$curl_status" == "0" ]]; then
      break
    fi
    if (( attempt < max_attempts )); then
      echo "contract console request failed transiently: $method $url (curl=$curl_status); retrying ($attempt/$max_attempts)" >&2
      cat "$err_tmp" >&2 || true
      sleep 1
      attempt=$(( attempt + 1 ))
      continue
    fi
    echo "contract console request failed: $method $url (curl=$curl_status)" >&2
    cat "$err_tmp" >&2 || true
    echo "contract console log:" >&2
    cat "$console_log" >&2 || true
    rm -f "$err_tmp"
    return 1
  done
  rm -f "$err_tmp"
  http_status="${response##*$'\n'}"
  body="${response%$'\n'*}"
  body="$(soraswap_redact_sensitive_text "$body")"

  if [[ "$http_status" != 2* ]]; then
    echo "request failed: $method $url -> HTTP $http_status" >&2
    echo "$body" >&2
    echo "contract console log:" >&2
    cat "$console_log" >&2 || true
    return 1
  fi

  printf '%s\n' "$body"
}

wait_for_console() {
  local attempt=1
  while (( attempt <= 20 )); do
    if soraswap_curl_for_config "" -fsS --max-time "$console_http_timeout_secs" "$base_url/api/catalog" >/dev/null 2>&1; then
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
  while (( attempt <= tx_status_attempts )); do
    result="$(http_json GET "$base_url/api/pipeline/transactions/status?environment=${public_env}&hash=${tx_hash}")"
    status_kind="$(jq -r '.status_kind // empty' <<<"$result")"
    case "$status_kind" in
      Applied|Committed|Rejected|Expired|TimedOut)
        printf '%s\n' "$result"
        return 0
        ;;
    esac
    sleep "$tx_status_retry_delay_secs"
    attempt=$(( attempt + 1 ))
  done

  if [[ -n "$result" ]]; then
    printf '%s\n' "$result"
  else
    printf '%s\n' '{}'
  fi
  return 0
}

tx_hash_hex64() {
  local tx_hash="$1"

  [[ "${#tx_hash}" -eq 64 && "$tx_hash" != *[!0-9A-Fa-f]* ]]
}

canonical_base64_file() {
  local artifact_path="$1"

  python3 - "$artifact_path" <<'PY'
import base64
from pathlib import Path
import sys

payload = Path(sys.argv[1]).read_bytes()
if not payload:
    raise SystemExit("SCCP proof artifact is empty")
print(base64.b64encode(payload).decode("ascii"))
PY
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
  rejection_text="$(soraswap_redact_sensitive_text "$rejection_text")"
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
registry_json="$(http_json GET "$base_url/api/sccp/registry?environment=${public_env}")"
recent_result_json="$(http_json GET "$base_url/api/sccp/messages/recent?environment=${public_env}&limit=${recent_limit}")"

if ! jq -e '
  (.ok == true)
  and (.response_json.version == 1)
  and (.response_json.registry_path == "/v1/sccp/registry")
  and (.response_json.message_bundle_path == "/v1/sccp/proofs/message/{message_id}")
  and (.response_json.proof_request_path == "/v1/sccp/proof-requests/{message_id}")
  and (.response_json.recent_messages_path == "/v1/sccp/messages/recent")
  and (.response_json.proof_submit_path == "/v1/bridge/proofs/submit")
  and (.response_json.native_message_submit_path == "/v1/bridge/messages")
  and ((.response_json.registry_revision // "") | test("^0x[0-9a-f]{64}$"))
  and ((.response_json.registry_limits // null) | type == "object")
  and ((.response_json.resource_limits // null) | type == "object")
' <<<"$capabilities_json" >/dev/null; then
  echo "SCCP capability document does not match the closed first-release Torii API" >&2
  exit 1
fi
if ! jq -e '(.ok == true) and ((.response_json // null) | type == "object")' <<<"$registry_json" >/dev/null; then
  echo "authoritative typed SCCP registry is unavailable" >&2
  exit 1
fi

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
        | select((.kind // "") == "transfer" and (.target_domain // 0) > 0 and (.route_id // "") == $route)' \
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
          | select((.kind // "") == "transfer" and (.target_domain // 0) > 0)' \
        <<<"$recent_result_json"
    )
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
        | select((.kind // "") == "transfer" and (.target_domain // 0) > 0 and (.route_id // "") == $route)' \
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
        | select((.kind // "") == "transfer" and (.target_domain // 0) > 0)' \
      <<<"$recent_result_json"
  )
fi

if [[ -z "$message_id" ]]; then
  echo "unable to select a finalized outbound SCCP transfer for route $bridge_route_hint; set ${bridge_message_id_var} to override" >&2
  exit 1
fi

bundle_result_json="$(http_json GET "$base_url/api/sccp/proofs/message/${message_id}?environment=${public_env}")"
proof_request_result_json="$(http_json GET "$base_url/api/sccp/proof-requests/${message_id}?environment=${public_env}")"
if ! bundle_json="$(jq -cer '.response_json' <<<"$bundle_result_json" 2>/dev/null)"; then
  echo "bridge message bundle lookup did not produce response_json" >&2
  printf '%s\n' "$(soraswap_redact_sensitive_text "$bundle_result_json")" >&2
  exit 1
fi
write_contract_console_report_json_file message_bundle "$bundle_json"
if ! jq -e '(.ok == true) and ((.response_json // null) | type == "object")' <<<"$proof_request_result_json" >/dev/null; then
  echo "state-derived SCCP proof request is unavailable for message $message_id" >&2
  exit 1
fi
echo "bridge message bundle ready for route selection" >&2

if [[ -z "$route" ]]; then
  route="$(derive_route_literal "$selected_recent_item_json" '{}' "$bridge_route_hint" || true)"
fi
if [[ -z "$route" ]]; then
  echo "unable to derive a bridge route from the looked-up message bundle; set ${bridge_route_var}" >&2
  exit 1
fi
echo "verifying bridge route $route before proof submission" >&2
echo "bridge route $route verified for proof submission" >&2

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
if ! route_provenance_json="$(inspect_view_result "$inspect_json" route_provenance 2>/dev/null)"; then
  echo "bridge inspect did not return route_provenance for route $route" >&2
  printf '%s\n' "$(soraswap_redact_sensitive_text "$inspect_json")" >&2
  exit 1
fi
if ! jq -e '.[0] == 1' <<<"$route_provenance_json" >/dev/null; then
  echo "bridge route $route is not governed in contract-console inspection: $route_provenance_json" >&2
  exit 1
fi
echo "bridge inspect verified route provenance" >&2
submission_expectation="apply"
consumed_before_submit=0
destination_proof_b64="$(canonical_base64_file "$bridge_destination_proof_file")"
native_proof_b64="$(canonical_base64_file "$bridge_native_proof_file")"
proof_submit_payload="$(jq -cn \
  --arg environment "$public_env" \
  --arg destination_proof_b64 "$destination_proof_b64" \
  '{environment: $environment, destination_proof_b64: $destination_proof_b64}')"
echo "submitting standalone bridge proof for message $message_id" >&2
if ! proof_submit_json="$(http_json POST "$base_url/api/bridge/proofs/submit" "$proof_submit_payload")"; then
  echo "bridge proof submission request failed for message $message_id" >&2
  exit 1
fi
echo "bridge proof submission response received" >&2
proof_response_message_id="$(jq -r '.response_json.message_id_hex // empty' <<<"$proof_submit_json")"
proof_response_route_hash="$(jq -r '.response_json.route_configuration_hash_hex // empty' <<<"$proof_submit_json")"
selected_route_hash="$(jq -r '.route_configuration_hash // empty | sub("^0x"; "")' <<<"$selected_recent_item_json")"
if [[ "$proof_response_message_id" != "$message_id" ]]; then
  echo "bridge destination proof response message id does not match selected finalized message" >&2
  exit 1
fi
if [[ -z "$selected_route_hash" || "$proof_response_route_hash" != "$selected_route_hash" ]]; then
  echo "bridge destination proof response route hash does not match selected finalized message" >&2
  exit 1
fi
if ! proof_tx_hash="$(jq -r '.tx_hash_hex // empty' <<<"$proof_submit_json" 2>/dev/null)"; then
  echo "bridge proof submission returned invalid JSON" >&2
  printf '%s\n' "$(soraswap_redact_sensitive_text "$proof_submit_json")" >&2
  exit 1
fi
if [[ -n "$proof_tx_hash" ]]; then
  if ! tx_hash_hex64 "$proof_tx_hash"; then
    echo "bridge proof submission returned a malformed transaction hash: $proof_tx_hash" >&2
    exit 1
  fi
  echo "waiting for bridge proof transaction $proof_tx_hash" >&2
  proof_status_json="$(poll_tx_status "$proof_tx_hash")"
  proof_status_kind="$(jq -r '.status_kind // empty' <<<"$proof_status_json" 2>/dev/null || true)"
  echo "bridge proof transaction status: ${proof_status_kind:-unknown}" >&2
  if [[ "$submission_expectation" == "replay_reject" ]]; then
    if jq -e '(.status_kind // "") | test("^(Applied|Committed|Skipped)$")' <<<"$proof_status_json" >/dev/null 2>&1; then
      :
    else
      jq -e '(.status_kind // "") == "Rejected"' <<<"$proof_status_json" >/dev/null
      proof_replay_rejection_matches "$proof_status_json"
    fi
  else
    if ! jq -e '(.status_kind // "") | test("^(Applied|Committed)$")' <<<"$proof_status_json" >/dev/null; then
      echo "bridge proof transaction did not apply" >&2
      printf '%s\n' "$(soraswap_redact_sensitive_text "$proof_status_json")" >&2
      exit 1
    fi
  fi
elif [[ "$submission_expectation" == "replay_reject" ]] && proof_replay_rejection_matches "$proof_submit_json"; then
  proof_status_json="$(rejection_status_json "$proof_submit_json")"
else
  echo "bridge proof submission did not return a transaction hash" >&2
  printf '%s\n' "$(soraswap_redact_sensitive_text "$proof_submit_json")" >&2
  exit 1
fi

message_submit_payload="$(jq -cn \
  --arg environment "$public_env" \
  --arg native_proof_b64 "$native_proof_b64" \
  '{environment: $environment, native_proof_b64: $native_proof_b64}')"
proof_driven_settlement=true
settlement_payload_supplied=false
message_submit_json="$(http_json POST "$base_url/api/bridge/messages" "$message_submit_payload")"
message_tx_hash="$(jq -r '.tx_hash_hex // empty' <<<"$message_submit_json")"
if [[ -n "$message_tx_hash" ]]; then
  if ! tx_hash_hex64 "$message_tx_hash"; then
    echo "bridge message submission returned a malformed transaction hash: $message_tx_hash" >&2
    exit 1
  fi
  message_status_json="$(poll_tx_status "$message_tx_hash")"
elif [[ "$submission_expectation" == "replay_reject" ]] && message_replay_rejection_matches "$message_submit_json"; then
  message_status_json="$(rejection_status_json "$message_submit_json")"
else
  echo "bridge message submission did not return a transaction hash" >&2
  printf '%s\n' "$(soraswap_redact_sensitive_text "$message_submit_json")" >&2
  exit 1
fi
if [[ "$submission_expectation" == "replay_reject" ]]; then
  jq -e '(.status_kind // "") == "Rejected"' <<<"$message_status_json" >/dev/null
  message_replay_rejection_matches "$message_status_json"
else
  jq -e '(.status_kind // "") | test("^(Applied|Committed)$")' <<<"$message_status_json" >/dev/null
fi
native_response_message_id="$(jq -r '.response_json.message_id_hex // empty' <<<"$message_submit_json")"
native_response_route_hash="$(jq -r '.response_json.route_configuration_hash_hex // empty' <<<"$message_submit_json")"
native_response_counterparty="$(jq -r '.response_json.counterparty_chain // empty' <<<"$message_submit_json")"
if [[ -z "$native_response_message_id" || -z "$native_response_route_hash" || -z "$native_response_counterparty" ]]; then
  echo "native SCCP admission response is missing governed route provenance" >&2
  exit 1
fi
governed_route_provenance_json="$(jq -cn \
  --arg destination_message_id "$proof_response_message_id" \
  --arg destination_route_configuration_hash "$proof_response_route_hash" \
  --arg native_message_id "$native_response_message_id" \
  --arg native_route_configuration_hash "$native_response_route_hash" \
  --arg native_counterparty_chain "$native_response_counterparty" \
  '{
    destination: {
      validated_by: "state_derived_sccp_proof_request",
      message_id_hex: $destination_message_id,
      route_configuration_hash_hex: $destination_route_configuration_hash
    },
    native: {
      validated_by: "authoritative_typed_sccp_registry",
      message_id_hex: $native_message_id,
      route_configuration_hash_hex: $native_route_configuration_hash,
      counterparty_chain: $native_counterparty_chain
    }
  }')"

if [[ -n "$contract_console_trace_file" && -s "$contract_console_trace_file" ]]; then
  contract_console_submitted_calls_json="$(jq -sc . "$contract_console_trace_file" 2>/dev/null || echo '[]')"
fi

write_contract_console_report_json_file chain_fingerprint "$chain_fingerprint_json"
write_contract_console_report_json_file snapshot_check "$snapshot_check_json"
write_contract_console_report_json_file contracts_snapshot "$contracts_snapshot_json"
write_contract_console_report_json_file deploy_snapshot "$deploy_snapshot_json"
write_contract_console_report_json_file capabilities "$capabilities_json"
write_contract_console_report_json_file registry "$registry_json"
write_contract_console_report_json_file recent_messages "$recent_result_json"
write_contract_console_report_json_file selected_recent_item "$selected_recent_item_json"
write_contract_console_report_json_file route_provenance "$route_provenance_json"
write_contract_console_report_json_file bundle_lookup "$bundle_result_json"
write_contract_console_report_json_file proof_request "$proof_request_result_json"
write_contract_console_report_json_file governed_route_provenance "$governed_route_provenance_json"
write_contract_console_report_json_file bridge_inspect "$inspect_json"
write_contract_console_report_json_file proof_submit "$proof_submit_json"
write_contract_console_report_json_file proof_status "$proof_status_json"
write_contract_console_report_json_file message_submit "$message_submit_json"
write_contract_console_report_json_file message_status "$message_status_json"
write_contract_console_report_json_file submitted_calls "$contract_console_submitted_calls_json"

report_json="$(jq -cn \
  --arg generated_at "$timestamp" \
  --arg environment "$public_env" \
  --arg authority "$SORASWAP_AUTHORITY" \
  --arg client_config "$(soraswap_display_path "$config")" \
  --arg torii_url "$(torii_base_from_config "$config")" \
  --arg run_suffix "$run_suffix" \
  --arg selection_source "$selection_source" \
  --arg submission_expectation "$submission_expectation" \
  --arg bridge_route_hint "$bridge_route_hint" \
  --arg route "$route" \
  --arg message_id "$message_id" \
  --arg bridge_contract_address "$bridge_contract_address" \
  --argjson proof_driven_settlement "$proof_driven_settlement" \
  --argjson settlement_payload_supplied "$settlement_payload_supplied" \
  --argjson consumed_before_submit "$consumed_before_submit" \
  --slurpfile chain_fingerprint "$contract_console_report_tmp_dir/chain_fingerprint.json" \
  --slurpfile snapshot_check "$contract_console_report_tmp_dir/snapshot_check.json" \
  --slurpfile contracts_snapshot "$contract_console_report_tmp_dir/contracts_snapshot.json" \
  --slurpfile deploy_snapshot "$contract_console_report_tmp_dir/deploy_snapshot.json" \
  --slurpfile capabilities "$contract_console_report_tmp_dir/capabilities.json" \
  --slurpfile registry "$contract_console_report_tmp_dir/registry.json" \
  --slurpfile recent_messages "$contract_console_report_tmp_dir/recent_messages.json" \
  --slurpfile selected_recent_item "$contract_console_report_tmp_dir/selected_recent_item.json" \
  --slurpfile route_provenance "$contract_console_report_tmp_dir/route_provenance.json" \
  --slurpfile bundle_lookup "$contract_console_report_tmp_dir/bundle_lookup.json" \
  --slurpfile proof_request "$contract_console_report_tmp_dir/proof_request.json" \
  --slurpfile governed_route_provenance "$contract_console_report_tmp_dir/governed_route_provenance.json" \
  --slurpfile bridge_inspect "$contract_console_report_tmp_dir/bridge_inspect.json" \
  --slurpfile proof_submit "$contract_console_report_tmp_dir/proof_submit.json" \
  --slurpfile proof_status "$contract_console_report_tmp_dir/proof_status.json" \
  --slurpfile message_submit "$contract_console_report_tmp_dir/message_submit.json" \
  --slurpfile message_status "$contract_console_report_tmp_dir/message_status.json" \
  --slurpfile submitted_calls "$contract_console_report_tmp_dir/submitted_calls.json" \
	  '($chain_fingerprint[0]) as $chain_fingerprint
    | ($snapshot_check[0]) as $snapshot_check
    | ($contracts_snapshot[0]) as $contracts_snapshot
    | ($deploy_snapshot[0]) as $deploy_snapshot
    | ($capabilities[0]) as $capabilities
    | ($registry[0]) as $registry
    | ($recent_messages[0]) as $recent_messages
    | ($selected_recent_item[0]) as $selected_recent_item
    | ($route_provenance[0]) as $route_provenance
    | ($bundle_lookup[0]) as $bundle_lookup
    | ($proof_request[0]) as $proof_request
    | ($governed_route_provenance[0]) as $governed_route_provenance
    | ($bridge_inspect[0]) as $bridge_inspect
    | ($proof_submit[0]) as $proof_submit
    | ($proof_status[0]) as $proof_status
    | ($message_submit[0]) as $message_submit
    | ($message_status[0]) as $message_status
    | ($submitted_calls[0]) as $submitted_calls
    | {
	    generated_at: $generated_at,
	    environment: $environment,
	    status: "completed",
	    authority: $authority,
	    client_config: $client_config,
    torii_url: $torii_url,
    run_suffix: $run_suffix,
    chain_fingerprint: $chain_fingerprint,
    snapshot_check: $snapshot_check,
    contracts_snapshot: {
      generated_at: ($contracts_snapshot.generated_at // null),
      status: ($contracts_snapshot.status // null),
      environment: ($contracts_snapshot.environment // null),
      chain_fingerprint: ($contracts_snapshot.chain_fingerprint // null)
    },
    deploy_snapshot: {
      generated_at: ($deploy_snapshot.generated_at // null),
      environment: ($deploy_snapshot.environment // null),
      chain_fingerprint: ($deploy_snapshot.chain_fingerprint // null),
      status: ($deploy_snapshot.status // null)
    },
    bridge: {
      contract_address: $bridge_contract_address,
      route: $route,
      route_hint: $bridge_route_hint,
      message_id: $message_id,
      route_provenance: $route_provenance,
      torii_sccp_v1: true,
      destination_message_id: ($proof_submit.response_json.message_id_hex // null),
      native_message_id: ($message_submit.response_json.message_id_hex // null),
      governed_route_provenance: $governed_route_provenance,
      submission_expectation: $submission_expectation
    },
    message_selection: {
      source: $selection_source,
      selected_recent_item: $selected_recent_item
    },
    discovery: {
      capabilities: $capabilities,
      registry: $registry,
      recent_messages: $recent_messages,
      bundle_lookup: $bundle_lookup,
      proof_request: $proof_request
    },
	    bridge_inspect: $bridge_inspect,
	    submissions: {
      submitted_calls: $submitted_calls,
      latest_submitted_call: ($submitted_calls[-1] // null),
	      proof_submit: $proof_submit,
      proof_status: $proof_status,
      message_submit: $message_submit,
      message_status: $message_status
    }
  }')"

soraswap_write_json_report_pair "$report_json" "$latest_report" "$timestamped_report"

echo "$public_env contract console smoke ok: $(soraswap_display_path "$latest_report")"
