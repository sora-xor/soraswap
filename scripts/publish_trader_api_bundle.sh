#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

public_env="${SORASWAP_PUBLIC_ENV:-testnet}"
case "$public_env" in
  testnet|production)
    ;;
  *)
    echo "publish_trader_api_bundle.sh only supports SORASWAP_PUBLIC_ENV=testnet|production; got $public_env" >&2
    exit 1
    ;;
esac

config="$(client_config_or_default "$public_env")"
ensure_client "$config"
ensure_authority "$config"
prepare_env_chain_state "$public_env" "$config"

check_deployment_records_current_readonly() {
  local env="$1"
  local config="$2"
  local record_path contract_key manifest_path expected_code_hash
  local -a expected_contract_keys issues

  expected_contract_keys=("${(@f)$(expected_contract_ids)}")
  for contract_key in "${expected_contract_keys[@]}"; do
    record_path="$(deployment_record_path_for_env "$env" "$contract_key")"
    manifest_path="$SORASWAP_ROOT/deployments/${env}/${contract_key}.manifest.json"
    expected_code_hash=""
    if [[ -f "$manifest_path" ]]; then
      expected_code_hash="$(manifest_code_hash_hex "$manifest_path")"
    fi

    if [[ ! -f "$record_path" ]]; then
      issues+=("$contract_key: missing deployment record at $record_path")
      continue
    fi
    if ! deployment_record_matches_current_chain "$record_path" "${SORASWAP_CHAIN_FINGERPRINT_JSON:-null}"; then
      issues+=("$contract_key: deployment record chain fingerprint is stale")
      continue
    fi
    if ! live_contract_deployment_from_record "$config" "$record_path" "$expected_code_hash" >/dev/null 2>&1; then
      issues+=("$contract_key: live contract no longer matches the recorded deployment")
    fi
  done

  refresh_deployment_records_snapshot_latest_for_env "$env" >/dev/null || true

  if (( ${#issues[@]} == 0 )); then
    echo "deployment records match the current chain fingerprint and live aliases"
    return 0
  fi

  printf '%s\n' "${issues[@]}"
  return 1
}

deployment_record_check_status="skipped"
deployment_record_check_output=""
if deployment_record_check_output="$(check_deployment_records_current_readonly "$public_env" "$config" 2>&1)"; then
  deployment_record_check_status="completed"
else
  deployment_record_check_status="degraded"
  echo "warning: deployment record freshness check is stale; publishing trader API bundle without recompiling contracts" >&2
  echo "$deployment_record_check_output" >&2
fi

torii_base="$(torii_base_from_config "$config")"
cid_probe_root="${SORASWAP_TRADER_API_PROBE_ROOT:-$torii_base}"
cid_probe_root="${cid_probe_root%/}"
timestamp="$(utc_timestamp)"
report_dir="$(deployments_dir_for_env "$public_env")"
artifact_dir="$SORASWAP_ROOT/artifacts/trader_api/$public_env/$timestamp"
latest_report="$report_dir/trader_api_bundle.latest.json"
timestamped_report="$report_dir/trader_api_bundle.$timestamp.json"
mkdir -p "$report_dir" "$artifact_dir"

ensure_sorafs_cli_bin() {
  local debug_bin="$SORASWAP_IROHA_ROOT/target/debug/sorafs_cli"
  if [[ -n "${SORASWAP_SORAFS_CLI_BIN:-}" && -x "$SORASWAP_SORAFS_CLI_BIN" ]]; then
    SORASWAP_ACTIVE_SORAFS_CLI_BIN="$SORASWAP_SORAFS_CLI_BIN"
    return 0
  fi
  if [[ -x "$debug_bin" ]]; then
    SORASWAP_ACTIVE_SORAFS_CLI_BIN="$debug_bin"
    return 0
  fi
  if [[ "${SORASWAP_SKIP_IROHA_CLI_BUILD:-0}" == "1" ]]; then
    echo "missing sorafs_cli binary at $debug_bin and SORASWAP_SKIP_IROHA_CLI_BUILD=1" >&2
    return 1
  fi
  (
    cd "$SORASWAP_IROHA_ROOT"
    NORITO_SKIP_BINDINGS_SYNC=1 CARGO_INCREMENTAL=0 \
      cargo build -p sorafs_orchestrator --bin sorafs_cli --features cli-orchestrator
  )
  SORASWAP_ACTIVE_SORAFS_CLI_BIN="$debug_bin"
}

sorafs_cli() {
  ensure_sorafs_cli_bin
  "$SORASWAP_ACTIVE_SORAFS_CLI_BIN" "$@"
}

content_cid_from_hex() {
  /usr/bin/python3 - "$1" <<'PY'
import base64
import sys

raw = bytes.fromhex(sys.argv[1].strip())
print("b" + base64.b32encode(raw).decode("ascii").lower().rstrip("="))
PY
}

routes_json="$(
  jq -cn '[
    {
      method: "POST",
      path: "/v1/contracts/view/batch",
      adapter: "contract.view_batch.v1"
    },
    {
      method: "GET",
      path: "/v1/contracts/rollups/swaps/fills",
      adapter: "contract.rollups.swaps_fills.v1",
      cache_ttl_ms: 2500
    },
    {
      method: "GET",
      path: "/v1/contracts/rollups/swaps/candles",
      adapter: "contract.rollups.swaps_candles.v1",
      cache_ttl_ms: 5000
    },
    {
      method: "GET",
      path: "/v1/contracts/rollups/trader/activity",
      adapter: "contract.rollups.trader_activity.v1",
      cache_ttl_ms: 2500
    },
    {
      method: "GET",
      path: "/v1/contracts/rollups/trader/account",
      adapter: "contract.rollups.trader_account.v1",
      cache_ttl_ms: 5000
    }
  ]'
)"

payload_dir="$artifact_dir/payload"
mkdir -p "$payload_dir"
api_manifest_path="$payload_dir/app-api.json"
jq -n \
  --arg app_id "${SORASWAP_TRADER_API_APP_ID:-soraswap.trader}" \
  --argjson routes "$routes_json" \
  '{
    schema_version: 1,
    app_id: $app_id,
    routes: $routes
  }' > "$api_manifest_path"

car_path="$artifact_dir/app-api.car"
plan_path="$artifact_dir/app-api.plan.json"
car_summary_path="$artifact_dir/app-api.car.summary.json"
manifest_path="$artifact_dir/app-api.manifest.to"
manifest_json_path="$artifact_dir/app-api.manifest.json"
pin_summary_path="$artifact_dir/app-api.pin.summary.json"
pin_response_path="$artifact_dir/app-api.pin.response.json"
registry_submit_summary_path="$artifact_dir/app-api.registry.submit.summary.json"
registry_submit_response_path="$artifact_dir/app-api.registry.submit.response.json"

sorafs_cli car pack \
  --input="$payload_dir" \
  --car-out="$car_path" \
  --plan-out="$plan_path" \
  --summary-out="$car_summary_path" >/dev/null

sorafs_cli manifest build \
  --summary="$car_summary_path" \
  --manifest-out="$manifest_path" \
  --manifest-json-out="$manifest_json_path" >/dev/null

sorafs_cli storage pin \
  --manifest="$manifest_path" \
  --payload="$payload_dir" \
  --torii-url="$torii_base" \
  --summary-out="$pin_summary_path" \
  --response-out="$pin_response_path" >/dev/null

sorafs_cli manifest submit \
  --manifest="$manifest_path" \
  --torii-url="$torii_base" \
  --resolve-submitted-epoch=true \
  --chunk-plan="$plan_path" \
  --authority="$SORASWAP_AUTHORITY" \
  --private-key="$(account_private_key_from_config "$config")" \
  --summary-out="$registry_submit_summary_path" \
  --response-out="$registry_submit_response_path" >/dev/null

pin_summary_json="$(cat "$pin_summary_path")"
registry_submit_json="$(cat "$registry_submit_summary_path")"
manifest_id_hex="$(jq -r '.manifest_id_hex' <<<"$pin_summary_json")"
manifest_digest_hex="$(jq -r '.manifest_digest_hex' <<<"$pin_summary_json")"
content_cid="$(content_cid_from_hex "$manifest_id_hex")"

binding_path="$artifact_dir/app-api.binding.json"
jq -n \
  --arg app_id "${SORASWAP_TRADER_API_APP_ID:-soraswap.trader}" \
  --arg content_cid "$content_cid" \
  --arg manifest_digest_hex "$manifest_digest_hex" \
  --argjson routes "$routes_json" \
  '{
    schema_version: 1,
    app_id: $app_id,
    content_cid: $content_cid,
    manifest_digest_hex: $manifest_digest_hex,
    routes: $routes
  }' > "$binding_path"

config_set_json='null'
config_set_status="skipped"
service_name="${SORASWAP_TRADER_API_SERVICE_NAME:-}"
if [[ "${SORASWAP_PUBLISH_TRADER_API_BINDING:-0}" == "1" ]]; then
  if [[ -z "$service_name" ]]; then
    echo "SORASWAP_PUBLISH_TRADER_API_BINDING=1 requires SORASWAP_TRADER_API_SERVICE_NAME" >&2
    exit 1
  fi
  api_token_args=()
  if [[ -n "${SORASWAP_TORII_API_TOKEN:-}" ]]; then
    api_token_args=(--api-token "$SORASWAP_TORII_API_TOKEN")
  fi
  config_set_output="$(iroha_cli_json \
    --config "$config" \
    app soracloud config-set \
    --service-name "$service_name" \
    --config-name torii/app_api_binding \
    --value-file "$binding_path" \
    --torii-url "$torii_base" \
    "${api_token_args[@]}" 2>&1)" || {
      config_set_json="$(jq -cn --arg status failed --arg output "$config_set_output" '{status: $status, output: $output}')"
      config_set_status="failed"
    }
  if [[ "$config_set_status" != "failed" ]]; then
    config_set_json="$(extract_last_json_object <<<"$config_set_output" || jq -cn --arg output "$config_set_output" '{output: $output}')"
    config_set_status="completed"
  fi
fi

cid_probe_body_path="$artifact_dir/app-api.cid_probe.body"
cid_probe_error_path="$artifact_dir/app-api.cid_probe.error"
cid_probe_attempts_path="$artifact_dir/app-api.cid_probe.attempts.jsonl"
cid_probe_http_code=""
cid_probe_json='null'
cid_probe_attempt_count="${SORASWAP_TRADER_API_PROBE_ATTEMPTS:-6}"
cid_probe_interval_secs="${SORASWAP_TRADER_API_PROBE_INTERVAL_SECS:-1}"
cid_probe_success_count=0
cid_probe_body=""
cid_probe_parsed='null'
cid_probe_last_body=""
: > "$cid_probe_attempts_path"
for ((cid_probe_attempt = 1; cid_probe_attempt <= cid_probe_attempt_count; cid_probe_attempt++)); do
  if cid_probe_http_code="$(curl -sS -o "$cid_probe_body_path" -w '%{http_code}' \
    --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
    -H 'Accept: application/json' \
    "$cid_probe_root/v1/app-api/cid/$content_cid" 2>"$cid_probe_error_path")"; then
    cid_probe_last_body="$(cat "$cid_probe_body_path")"
    if [[ "$cid_probe_http_code" == 2* ]]; then
      (( cid_probe_success_count += 1 ))
      if [[ "$cid_probe_parsed" == 'null' ]]; then
        cid_probe_body="$cid_probe_last_body"
        cid_probe_parsed="$(jq -c . <<<"$cid_probe_body" 2>/dev/null || echo null)"
        if [[ -z "${cid_probe_parsed//[$'\r\n\t ']}" ]]; then
          cid_probe_parsed='null'
        fi
      fi
    fi
    jq -cn \
      --argjson attempt "$cid_probe_attempt" \
      --arg http_code "$cid_probe_http_code" \
      '{attempt: $attempt, http_code: $http_code}' >> "$cid_probe_attempts_path"
  else
    cid_probe_last_body="$(cat "$cid_probe_error_path" 2>/dev/null || true)"
    jq -cn \
      --argjson attempt "$cid_probe_attempt" \
      --arg http_code "transport-error" \
      '{attempt: $attempt, http_code: $http_code}' >> "$cid_probe_attempts_path"
  fi

  if [[ "$cid_probe_attempt" -lt "$cid_probe_attempt_count" ]]; then
    sleep "$cid_probe_interval_secs"
  fi
done

if [[ "$cid_probe_parsed" == 'null' && -z "$cid_probe_body" ]]; then
  cid_probe_body="$cid_probe_last_body"
fi

cid_probe_attempts_json="$(jq -sc . "$cid_probe_attempts_path")"
if (( cid_probe_success_count == cid_probe_attempt_count )); then
  cid_probe_status="completed"
elif (( cid_probe_success_count > 0 )); then
  cid_probe_status="inconsistent"
else
  cid_probe_status="failed"
fi
cid_probe_json="$(jq -cn \
  --arg status "$cid_probe_status" \
  --arg http_code "$cid_probe_http_code" \
  --arg url "$cid_probe_root/v1/app-api/cid/$content_cid" \
  --arg body "$cid_probe_body" \
  --argjson parsed "$cid_probe_parsed" \
  --argjson success_count "$cid_probe_success_count" \
  --argjson attempt_count "$cid_probe_attempt_count" \
  --argjson attempts "$cid_probe_attempts_json" \
  '{
    status: $status,
    http_code: $http_code,
    url: $url,
    body: $body,
    parsed: $parsed,
    success_count: $success_count,
    attempt_count: $attempt_count,
    attempts: $attempts
  }')"

report_json="$(jq -n \
  --arg generated_at "$timestamp" \
  --arg environment "$public_env" \
  --arg client_config "$config" \
  --arg torii_url "$torii_base" \
  --arg content_cid "$content_cid" \
  --arg manifest_id_hex "$manifest_id_hex" \
  --arg manifest_digest_hex "$manifest_digest_hex" \
  --arg artifact_dir "$artifact_dir" \
  --arg api_manifest_path "$api_manifest_path" \
  --arg binding_path "$binding_path" \
  --arg deployment_record_check_status "$deployment_record_check_status" \
  --arg deployment_record_check_output "$deployment_record_check_output" \
  --arg config_set_status "$config_set_status" \
  --arg service_name "$service_name" \
  --argjson chain_fingerprint "${SORASWAP_CHAIN_FINGERPRINT_JSON:-null}" \
  --argjson pin_summary "$pin_summary_json" \
  --argjson registry_submit "$registry_submit_json" \
  --argjson routes "$routes_json" \
  --argjson cid_probe "$cid_probe_json" \
  --argjson config_set "$config_set_json" \
  '{
    generated_at: $generated_at,
    environment: $environment,
    client_config: $client_config,
    torii_url: $torii_url,
    chain_fingerprint: $chain_fingerprint,
    content_cid: $content_cid,
    manifest_id_hex: $manifest_id_hex,
    manifest_digest_hex: $manifest_digest_hex,
    artifact_dir: $artifact_dir,
    api_manifest_path: $api_manifest_path,
    binding_path: $binding_path,
    deployment_record_check: {
      status: $deployment_record_check_status,
      output: $deployment_record_check_output
    },
    routes: $routes,
    pin_summary: $pin_summary,
    registry_submit: $registry_submit,
    cid_probe: $cid_probe,
    binding: {
      status: $config_set_status,
      service_name: (if $service_name == "" then null else $service_name end),
      response: $config_set
    }
  }')"

printf '%s\n' "$report_json" > "$latest_report"
printf '%s\n' "$report_json" > "$timestamped_report"
printf '%s\n' "$report_json"

if [[ "$config_set_status" == "failed" ]]; then
  exit 1
fi
