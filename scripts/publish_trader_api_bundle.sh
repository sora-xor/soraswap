#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"
source "$SORASWAP_ROOT/scripts/sorafs_publish_summary_validation.sh"

public_env="${SORASWAP_PUBLIC_ENV:-testnet}"
case "$public_env" in
  testnet|production)
    ;;
  *)
    echo "publish_trader_api_bundle.sh only supports SORASWAP_PUBLIC_ENV=testnet|production; got $public_env" >&2
    exit 1
    ;;
esac

require_public_mutation_consent "$public_env" "$public_env trader API publication"

cid_probe_attempt_count="${SORASWAP_TRADER_API_PROBE_ATTEMPTS:-6}"
cid_probe_interval_secs="${SORASWAP_TRADER_API_PROBE_INTERVAL_SECS:-1}"
cid_probe_body_max_chars="${SORASWAP_TRADER_API_PROBE_BODY_MAX_CHARS:-8192}"
registry_visibility_attempt_count="${SORASWAP_TRADER_API_REGISTRY_VISIBILITY_ATTEMPTS:-30}"
registry_visibility_retry_delay_secs="${SORASWAP_TRADER_API_REGISTRY_VISIBILITY_RETRY_DELAY_SECS:-2}"
gateway_propagation_attempt_count="${SORASWAP_TRADER_API_GATEWAY_PROPAGATION_ATTEMPTS:-8}"
gateway_propagation_retry_delay_secs="${SORASWAP_TRADER_API_GATEWAY_PROPAGATION_RETRY_DELAY_SECS:-2}"
binding_publish="${SORASWAP_PUBLISH_TRADER_API_BINDING:-0}"
soraswap_require_positive_integer_setting "SORASWAP_TRADER_API_PROBE_ATTEMPTS" "$cid_probe_attempt_count" || exit 1
soraswap_require_nonnegative_number_setting "SORASWAP_TRADER_API_PROBE_INTERVAL_SECS" "$cid_probe_interval_secs" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_TRADER_API_PROBE_BODY_MAX_CHARS" "$cid_probe_body_max_chars" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_TRADER_API_REGISTRY_VISIBILITY_ATTEMPTS" "$registry_visibility_attempt_count" || exit 1
soraswap_require_nonnegative_number_setting "SORASWAP_TRADER_API_REGISTRY_VISIBILITY_RETRY_DELAY_SECS" "$registry_visibility_retry_delay_secs" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_TRADER_API_GATEWAY_PROPAGATION_ATTEMPTS" "$gateway_propagation_attempt_count" || exit 1
soraswap_require_nonnegative_number_setting "SORASWAP_TRADER_API_GATEWAY_PROPAGATION_RETRY_DELAY_SECS" "$gateway_propagation_retry_delay_secs" || exit 1
soraswap_require_binary_integer_setting "SORASWAP_PUBLISH_TRADER_API_BINDING" "$binding_publish" || exit 1
soraswap_require_binary_integer_setting "SORASWAP_SKIP_IROHA_CLI_BUILD" "${SORASWAP_SKIP_IROHA_CLI_BUILD:-0}" || exit 1

config="$(client_config_or_default "$public_env")"
ensure_client "$config"
ensure_authority "$config"
prepare_env_chain_state "$public_env" "$config"
chain_fingerprint_json="$(chain_fingerprint_json_or_null)"
manifest_network_id="$(network_id_from_config "$config")" || exit 1
manifest_network_prefix="$(chain_discriminant_for_env_config "$public_env" "$config")" || exit 1
ensure_public_signer_ready "$config" "$SORASWAP_AUTHORITY" verify-only || exit 1
if [[ "$public_env" == "production" ]]; then
  require_production_operator_permissions "$config" "$SORASWAP_AUTHORITY" || exit 1
fi
soraswap_require_public_submit_health_ready_for_config "$config" "$public_env trader API publication" || exit 1

check_deployment_records_current_readonly() {
  local env="$1"
  local config="$2"
  local chain_fingerprint_json="$3"
  local record_path contract_key manifest_path expected_code_hash
  local -a expected_contract_keys issues

  expected_contract_keys=("${(@f)$(expected_contract_ids)}")
  for contract_key in "${expected_contract_keys[@]}"; do
    record_path="$(deployment_record_path_for_env "$env" "$contract_key")"
    manifest_path="$SORASWAP_ROOT/deployments/${env}/${contract_key}.manifest.json"
    expected_code_hash=""
    if [[ ! -f "$manifest_path" ]]; then
      issues+=("$contract_key: missing deployment manifest at $(soraswap_display_path "$manifest_path")")
      continue
    fi
    if ! deployment_manifest_matches_environment "$manifest_path" "$env" "$contract_key"; then
      issues+=("$contract_key: deployment manifest metadata is incomplete or stale")
      continue
    fi
    expected_code_hash="$(manifest_code_hash_hex "$manifest_path")"
    if [[ -z "$expected_code_hash" ]]; then
      issues+=("$contract_key: deployment manifest is missing code_hash")
      continue
    fi

    if [[ ! -f "$record_path" ]]; then
      issues+=("$contract_key: missing deployment record at $(soraswap_display_path "$record_path")")
      continue
    fi
    if ! deployment_record_matches_current_chain "$record_path" "$chain_fingerprint_json" "$env"; then
      issues+=("$contract_key: deployment record chain fingerprint is stale")
      continue
    fi
    if ! deployment_record_matches_environment "$record_path" "$env"; then
      issues+=("$contract_key: deployment record environment is not $env")
      continue
    fi
    if ! live_contract_deployment_from_record "$config" "$record_path" "$expected_code_hash" "$env" >/dev/null 2>&1; then
      issues+=("$contract_key: live contract no longer matches the recorded deployment")
    fi
  done

  refresh_deployment_records_snapshot_latest_for_env "$env" >/dev/null || true

  if (( ${#issues[@]} == 0 )); then
    echo "deployment records match the selected environment, current chain fingerprint, and live aliases"
    return 0
  fi

  printf '%s\n' "${issues[@]}"
  return 1
}

deployment_record_check_status="skipped"
deployment_record_check_output=""
if deployment_record_check_output="$(check_deployment_records_current_readonly "$public_env" "$config" "$chain_fingerprint_json" 2>&1)"; then
  deployment_record_check_output="$(soraswap_redact_sensitive_text "$deployment_record_check_output")"
  deployment_record_check_status="completed"
else
  deployment_record_check_output="$(soraswap_redact_sensitive_text "$deployment_record_check_output")"
  deployment_record_check_status="degraded"
  echo "warning: deployment record freshness check is stale; publishing trader API bundle without recompiling contracts" >&2
  echo "$deployment_record_check_output" >&2
  if [[ "$public_env" == "production" ]]; then
    echo "production trader API publication requires current live deployment records" >&2
    exit 1
  fi
fi

torii_base="$(torii_base_from_config "$config")"
cid_probe_root="${SORASWAP_TRADER_API_PROBE_ROOT:-$torii_base}"
cid_probe_root="${cid_probe_root%/}"
cid_probe_client_config=""
if [[ "$cid_probe_root" == "$torii_base" ]]; then
  cid_probe_client_config="$config"
fi
timestamp="$(utc_timestamp)"
report_dir="$(deployments_dir_for_env "$public_env")"
artifact_dir="$SORASWAP_ROOT/artifacts/trader_api/$public_env/$timestamp"
latest_report="$report_dir/trader_api_bundle.latest.json"
timestamped_report="$report_dir/trader_api_bundle.$timestamp.json"
mkdir -p "$report_dir" "$artifact_dir"
trader_api_report_tmp_dir=""
publisher_private_key_file=""
api_token_file=""
api_token_value=""
config_set_stderr_file=""

cleanup_trader_api_report_tmp_dir() {
  local cleanup_status=0
  [[ -z "${trader_api_report_tmp_dir:-}" ]] || rm -rf "$trader_api_report_tmp_dir"
  if [[ -n "${publisher_private_key_file:-}" ]] \
    && ! soraswap_secure_unlink_owned_file "$publisher_private_key_file"; then
    cleanup_status=1
  fi
  if [[ -n "${api_token_file:-}" ]] \
    && ! soraswap_secure_unlink_owned_file "$api_token_file"; then
    cleanup_status=1
  fi
  if [[ -n "${config_set_stderr_file:-}" ]] \
    && ! soraswap_secure_unlink_owned_file "$config_set_stderr_file"; then
    cleanup_status=1
  fi
  api_token_value=""
  return "$cleanup_status"
}

trap cleanup_trader_api_report_tmp_dir EXIT

contracts_snapshot_json='null'
deploy_snapshot_json='null'
contracts_snapshot_path="$(contracts_snapshot_latest_path_for_env "$public_env")"
deploy_snapshot_path="$(deploy_report_latest_path_for_env "$public_env")"
snapshot_check_json="$(public_current_deploy_snapshot_check_json "$public_env" "$chain_fingerprint_json" "$contracts_snapshot_path" "$deploy_snapshot_path")"
snapshot_check_status="$(jq -r '.status // empty' <<<"$snapshot_check_json")"
snapshot_check_output="$(jq -r '.output // empty' <<<"$snapshot_check_json")"
snapshot_check_output="$(soraswap_redact_sensitive_text "$snapshot_check_output")"
[[ "$snapshot_check_status" == "completed" ]] || snapshot_check_status="degraded"
if [[ "$snapshot_check_status" != "completed" ]]; then
  echo "warning: trader API snapshot freshness check is stale; publishing diagnostic bundle evidence" >&2
  echo "$snapshot_check_output" >&2
  if [[ "$public_env" == "production" ]]; then
    echo "production trader API publication requires a current deploy/contracts snapshot" >&2
    exit 1
  fi
fi
if [[ -f "$contracts_snapshot_path" ]]; then
  contracts_snapshot_json="$(cat "$contracts_snapshot_path")"
fi
if [[ -f "$deploy_snapshot_path" ]]; then
  deploy_snapshot_json="$(cat "$deploy_snapshot_path")"
fi

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
    echo "missing sorafs_cli binary at $(soraswap_display_path "$debug_bin") and SORASWAP_SKIP_IROHA_CLI_BUILD=1" >&2
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

run_sorafs_cli_checked() {
  local stdout_mode="$1"
  shift
  local output="" exit_code=1 stderr_file="" stderr_output="" redacted_output redacted_stderr_output arg file_path
  local cleanup_status=0
  local -a secret_file_paths

  case "$stdout_mode" in
    raw|redacted)
      ;;
    *)
      echo "internal error: invalid sorafs_cli stdout mode: $stdout_mode" >&2
      return 1
      ;;
  esac

  secret_file_paths=()

  for arg in "$@"; do
    case "$arg" in
      --private-key=*|--private-key|--api-token=*|--api-token)
        echo "refusing inline secret option for sorafs_cli: ${arg%%=*}" >&2
        return 1
        ;;
      --private-key-file=*)
        file_path="${arg#*=}"
        if [[ -z "$file_path" || "$file_path" != /* || "${file_path:A}" != "$file_path" ]]; then
          echo "refusing a non-canonical file-backed secret/config path for sorafs_cli: ${arg%%=*}" >&2
          return 1
        fi
        secret_file_paths+=("$file_path")
        ;;
    esac
  done

  stderr_file="$(soraswap_secure_temp_file sorafs-stderr)" || return 1
  set +e
  {
    output="$(sorafs_cli "$@" 2>"$stderr_file")"
    exit_code=$?
    stderr_output="$(cat "$stderr_file" 2>/dev/null || true)"
  } always {
    set -e
    if ! soraswap_secure_unlink_owned_file "$stderr_file"; then
      cleanup_status=1
    fi
    stderr_file=""
  }
  (( cleanup_status == 0 )) || return 1

  if ! printf '%s\n%s' "$output" "$stderr_output" \
    | soraswap_assert_client_output_clean "$config" "${secret_file_paths[@]}"; then
    echo "sorafs_cli credential echo was suppressed" >&2
    return 1
  fi

  redacted_output="$(soraswap_redact_sensitive_text "$output")"
  redacted_stderr_output="$(soraswap_redact_sensitive_text "$stderr_output")"
  if [[ -n "$redacted_stderr_output" ]]; then
    printf '%s\n' "$redacted_stderr_output" >&2
  fi
  if (( exit_code != 0 )); then
    if [[ "$stderr_output$output" == *"--private-key-file"* && "$stderr_output$output" == *("unrecognised option"|"unexpected argument"|"unknown option")* ]]; then
      echo "sorafs_cli lacks required --private-key-file support; refusing inline private key fallback" >&2
    fi
    if [[ -n "$redacted_output" ]]; then
      printf '%s\n' "$redacted_output" >&2
    fi
    return "$exit_code"
  fi
  if [[ -n "$output" ]]; then
    if [[ "$stdout_mode" == "raw" ]]; then
      printf '%s\n' "$output"
    else
      printf '%s\n' "$redacted_output"
    fi
  fi
  return 0
}

run_sorafs_cli_redacted() {
  run_sorafs_cli_checked redacted "$@"
}

run_sorafs_cli_raw_stdout() {
  run_sorafs_cli_checked raw "$@"
}

trader_api_redact_artifact_file_in_place() {
  local path="$1"
  local raw redacted

  [[ -f "$path" ]] || return 0
  raw="$(cat "$path" 2>/dev/null || true)"
  redacted="$(soraswap_redact_sensitive_text "$raw")"
  printf '%s\n' "$redacted" > "$path"
}

content_cid_from_hex() {
  /usr/bin/python3 - "$1" <<'PY'
import base64
import sys

raw = bytes.fromhex(sys.argv[1].strip())
print("b" + base64.b32encode(raw).decode("ascii").lower().rstrip("="))
PY
}

wait_for_trader_api_paid_pin_record() {
  local manifest_digest_hex="$1"
  local record_path="$2"
  local attempts_path="$3"
  local body_path="$4"
  local error_path="$5"
  local attempt http_code body status_text

  : > "$attempts_path"
  for ((attempt = 1; attempt <= registry_visibility_attempt_count; attempt++)); do
    if http_code="$(soraswap_curl_for_config "$config" -sS -o "$body_path" -w '%{http_code}' \
      --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
      -H 'Accept: application/json' \
      "$torii_base/v1/sorafs/pin/$manifest_digest_hex" 2>"$error_path")"; then
      body="$(cat "$body_path" 2>/dev/null || true)"
      if [[ "$http_code" == 2* ]] && jq -e --arg digest "$manifest_digest_hex" '
          ((.manifest.digest_hex // "") | ascii_downcase) == ($digest | ascii_downcase)
          and ((.manifest.status.state // "") | ascii_downcase) == "approved"
        ' <<<"$body" >/dev/null 2>&1; then
        printf '%s\n' "$(soraswap_redact_sensitive_text "$body")" > "$record_path"
        jq -cn \
          --argjson attempt "$attempt" \
          --arg http_code "$http_code" \
          '{attempt: $attempt, http_code: $http_code, visible: true}' >> "$attempts_path"
        return 0
      fi
      status_text="$(jq -r '.error // .manifest.status.state // empty' <<<"$body" 2>/dev/null || true)"
      status_text="$(soraswap_redact_sensitive_text "$status_text")"
      jq -cn \
        --argjson attempt "$attempt" \
        --arg http_code "$http_code" \
        --arg status "$status_text" \
        '{attempt: $attempt, http_code: $http_code, visible: false, status: $status}' >> "$attempts_path"
    else
      status_text="$(cat "$error_path" 2>/dev/null || true)"
      status_text="$(soraswap_redact_sensitive_text "$status_text")"
      jq -cn \
        --argjson attempt "$attempt" \
        --arg http_code "transport-error" \
        --arg status "$status_text" \
        '{attempt: $attempt, http_code: $http_code, visible: false, status: $status}' >> "$attempts_path"
    fi

    if [[ "$attempt" -lt "$registry_visibility_attempt_count" ]]; then
      sleep "$registry_visibility_retry_delay_secs"
    fi
  done

  echo "paid SoraFS registry record for manifest $manifest_digest_hex was not visible after $registry_visibility_attempt_count attempts" >&2
  return 1
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
    },
    {
      method: "GET",
      path: "/v1/contracts/rollups/intents",
      adapter: "contract.rollups.intents.v1",
      cache_ttl_ms: 2500
    },
    {
      method: "GET",
      path: "/v1/contracts/rollups/vaults/positions",
      adapter: "contract.rollups.vault_positions.v1",
      cache_ttl_ms: 5000
    },
    {
      method: "GET",
      path: "/v1/contracts/rollups/operators/status",
      adapter: "contract.rollups.operators_status.v1",
      cache_ttl_ms: 5000
    },
    {
      method: "GET",
      path: "/v1/contracts/rollups/margin/health",
      adapter: "contract.rollups.margin_health.v1",
      cache_ttl_ms: 2500
    },
    {
      method: "GET",
      path: "/v1/contracts/rollups/rwa/lots",
      adapter: "contract.rollups.rwa_lots.v1",
      cache_ttl_ms: 5000
    },
    {
      method: "GET",
      path: "/v1/contracts/rollups/dlmm/hooks",
      adapter: "contract.rollups.dlmm_hooks.v1",
      cache_ttl_ms: 2500
    }
  ]'
)"

trader_api_manifest_matches_expected() {
  local parsed_json="$1"
  jq -e \
    --arg app_id "${SORASWAP_TRADER_API_APP_ID:-soraswap.trader}" \
    --arg content_cid "$content_cid" \
    --arg manifest_digest_hex "$manifest_digest_hex" \
    'def has_route($routes; $method; $path; $adapter):
        any(($routes // [])[];
          (.method // "") == $method
          and (.path // "") == $path
          and (.adapter // "") == $adapter
        );

      def has_required_routes($routes):
        (($routes // []) | length) == 11
        and has_route($routes; "POST"; "/v1/contracts/view/batch"; "contract.view_batch.v1")
        and has_route($routes; "GET"; "/v1/contracts/rollups/swaps/fills"; "contract.rollups.swaps_fills.v1")
        and has_route($routes; "GET"; "/v1/contracts/rollups/swaps/candles"; "contract.rollups.swaps_candles.v1")
        and has_route($routes; "GET"; "/v1/contracts/rollups/trader/activity"; "contract.rollups.trader_activity.v1")
        and has_route($routes; "GET"; "/v1/contracts/rollups/trader/account"; "contract.rollups.trader_account.v1")
        and has_route($routes; "GET"; "/v1/contracts/rollups/intents"; "contract.rollups.intents.v1")
        and has_route($routes; "GET"; "/v1/contracts/rollups/vaults/positions"; "contract.rollups.vault_positions.v1")
        and has_route($routes; "GET"; "/v1/contracts/rollups/operators/status"; "contract.rollups.operators_status.v1")
        and has_route($routes; "GET"; "/v1/contracts/rollups/margin/health"; "contract.rollups.margin_health.v1")
        and has_route($routes; "GET"; "/v1/contracts/rollups/rwa/lots"; "contract.rollups.rwa_lots.v1")
        and has_route($routes; "GET"; "/v1/contracts/rollups/dlmm/hooks"; "contract.rollups.dlmm_hooks.v1");

      type == "object"
      and ((.schema_version // 0) == 1)
      and ((.app_id // "") == $app_id)
      and ((.content_cid // "") == $content_cid)
      and ((.manifest_digest_hex // "") == $manifest_digest_hex)
      and has_required_routes(.routes // [])' <<<"$parsed_json" >/dev/null
}

trader_api_probe_report_text() {
  local raw="${1:-}"
  local redacted

  redacted="$(soraswap_redact_sensitive_text "$raw")"
  if (( ${#redacted} > cid_probe_body_max_chars )); then
    printf '%s...[truncated %s chars]\n' "${redacted[1,$cid_probe_body_max_chars]}" "${#redacted}"
  else
    printf '%s\n' "$redacted"
  fi
}

trader_api_probe_report_parsed() {
  local parsed_json="${1:-null}"
  local manifest_match="${2:-false}"
  local redacted_json

  if [[ -z "${parsed_json//[$'\r\n\t ']}" || "$parsed_json" == "null" ]]; then
    echo 'null'
    return 0
  fi

  if [[ "$manifest_match" == "true" ]]; then
    jq -c '{
      schema_version,
      app_id,
      content_cid,
      manifest_digest_hex,
      routes: ((.routes // []) | map({
        method: (.method // null),
        path: (.path // null),
        adapter: (.adapter // null),
        cache_ttl_ms: (.cache_ttl_ms // null)
      } | with_entries(select(.value != null))))
    }' \
      <<<"$parsed_json" 2>/dev/null || echo 'null'
    return 0
  fi

  redacted_json="$(soraswap_redact_sensitive_text "$parsed_json")"
  if [[ -z "${redacted_json//[$'\r\n\t ']}" ]] || ! jq -e . >/dev/null 2>&1 <<<"$redacted_json"; then
    echo 'null'
    return 0
  fi
  if (( ${#redacted_json} <= cid_probe_body_max_chars )); then
    jq -c . <<<"$redacted_json"
    return 0
  fi

  jq -c '{
    truncated: true,
    redacted: true,
    schema_version: (.schema_version // null),
    app_id: (.app_id // null),
    content_cid: (.content_cid // null),
    manifest_digest_hex: (.manifest_digest_hex // null),
    route_count: (if ((.routes // null) | type) == "array" then (.routes | length) else null end)
  }' <<<"$redacted_json"
}

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
expected_payload_file_count=1
api_manifest_size="$(LC_ALL=C wc -c <"$api_manifest_path" | tr -d '[:space:]')"
soraswap_require_positive_integer_setting "trader API manifest byte size" "$api_manifest_size" || exit 1

car_path="$artifact_dir/app-api.car"
plan_path="$artifact_dir/app-api.plan.json"
car_summary_path="$artifact_dir/app-api.car.summary.json"
manifest_path="$artifact_dir/app-api.manifest.to"
manifest_json_path="$artifact_dir/app-api.manifest.json"
manifest_build_summary_path="$artifact_dir/app-api.manifest.summary.json"
provider_payload_path="$artifact_dir/app-api.provider.payload.bin"
provider_files_path="$artifact_dir/app-api.provider.files.json"
provider_prepare_summary_path="$artifact_dir/app-api.provider.prepare.summary.json"
registry_submit_summary_path="$artifact_dir/app-api.registry.submit.summary.json"
registry_submit_response_path="$artifact_dir/app-api.registry.submit.response.json"
registry_visibility_path="$artifact_dir/app-api.registry.visibility.json"
registry_visibility_attempts_path="$artifact_dir/app-api.registry.visibility.attempts.jsonl"
registry_visibility_body_path="$artifact_dir/app-api.registry.visibility.body"
registry_visibility_error_path="$artifact_dir/app-api.registry.visibility.error"

run_sorafs_cli_redacted car pack \
  --input="$payload_dir" \
  --car-out="$car_path" \
  --chunker-handle=sorafs.sf1@1.0.0 \
  --plan-out="$plan_path" \
  --summary-out="$car_summary_path" >/dev/null
if [[ ! -s "$car_path" || ! -s "$plan_path" || ! -s "$car_summary_path" ]]; then
  echo "current SoraFS car pack did not create every required output artifact" >&2
  exit 1
fi
car_size_bytes="$(LC_ALL=C wc -c <"$car_path" | tr -d '[:space:]')"
soraswap_require_positive_integer_setting "SoraFS CAR byte size" "$car_size_bytes" || exit 1
if ! car_summary_json="$(soraswap_validate_sorafs_car_directory_summary \
  "$car_summary_path" \
  "$payload_dir" \
  "$car_path" \
  "$expected_payload_file_count" \
  "$car_size_bytes" \
  "$api_manifest_size" 2>/dev/null)"; then
  echo "current SoraFS car pack summary is missing, invalid, or mismatched" >&2
  exit 1
fi
car_chunk_count="$(jq -r '.chunk_count' <<<"$car_summary_json")"
car_digest_hex="$(jq -r '.car_digest_hex' <<<"$car_summary_json")"
car_chunk_digest_sha3_hex="$(jq -r '.chunk_digest_sha3_256_hex' <<<"$car_summary_json")"

manifest_build_summary_raw="$(run_sorafs_cli_raw_stdout manifest build \
  --summary="$car_summary_path" \
  --manifest-out="$manifest_path" \
  --manifest-json-out="$manifest_json_path" \
  --pin-min-replicas=1 \
  --pin-storage-class=hot \
  --pin-retention-epoch=86400)"
if [[ ! -s "$manifest_path" || ! -s "$manifest_json_path" ]]; then
  echo "current SoraFS manifest build did not create every required output artifact" >&2
  exit 1
fi
if ! manifest_build_summary_json="$(soraswap_validate_sorafs_manifest_build_summary \
  <(printf '%s\n' "$manifest_build_summary_raw") \
  "$manifest_path" \
  "$manifest_json_path" \
  "$car_summary_json" 2>/dev/null)"; then
  echo "current SoraFS manifest build summary is missing, invalid, or mismatched" >&2
  exit 1
fi
printf '%s\n' "$(soraswap_redact_sensitive_text "$manifest_build_summary_json")" > "$manifest_build_summary_path"
manifest_digest_hex="$(jq -r '.manifest_digest_hex' <<<"$manifest_build_summary_json")"

provider_prepare_raw="$(run_sorafs_cli_raw_stdout storage prepare \
  --manifest="$manifest_path" \
  --payload="$payload_dir" \
  --payload-out="$provider_payload_path" \
  --files-out="$provider_files_path" \
  --summary-out="$provider_prepare_summary_path")"
if [[ ! -s "$provider_payload_path" || ! -s "$provider_files_path" || ! -s "$provider_prepare_summary_path" ]]; then
  echo "current SoraFS storage prepare did not create every required output artifact" >&2
  exit 1
fi
if ! provider_prepare_file_json="$(jq -ce . "$provider_prepare_summary_path" 2>/dev/null)" \
  || ! provider_prepare_stdout_json="$(jq -ce . <<<"$provider_prepare_raw" 2>/dev/null)" \
  || [[ "$provider_prepare_file_json" != "$provider_prepare_stdout_json" ]]; then
  echo "current SoraFS storage prepare stdout does not match its summary artifact" >&2
  exit 1
fi
provider_payload_size="$(LC_ALL=C wc -c <"$provider_payload_path" | tr -d '[:space:]')"
soraswap_require_positive_integer_setting "SoraFS provider payload byte size" "$provider_payload_size" || exit 1
if ! provider_prepare_json="$(soraswap_validate_sorafs_storage_prepare_summary \
  "$provider_prepare_summary_path" \
  "$manifest_path" \
  "$payload_dir" \
  "$provider_payload_path" \
  "$provider_files_path" \
  "$manifest_build_summary_json" \
  "$car_summary_json" \
  "$provider_payload_size" 2>/dev/null)"; then
  echo "current SoraFS storage prepare summary is missing, invalid, or mismatched" >&2
  exit 1
fi
if ! soraswap_validate_sorafs_storage_directory_files \
  "$provider_files_path" \
  "${api_manifest_path:t}" \
  "$api_manifest_size" >/dev/null 2>&1; then
  echo "current SoraFS storage prepare file index is missing, invalid, or mismatched" >&2
  exit 1
fi
if ! cmp -s "$provider_payload_path" "$api_manifest_path"; then
  echo "current SoraFS storage prepare payload does not match the published API manifest" >&2
  exit 1
fi
printf '%s\n' "$provider_prepare_json" > "$provider_prepare_summary_path"
manifest_id_hex="$(jq -r '.manifest_id_hex' <<<"$provider_prepare_json")"
provider_chunker_handle="$(jq -r '.chunker_handle' <<<"$provider_prepare_json")"
provider_prepare_json="$(soraswap_redact_sensitive_text "$provider_prepare_json")"
trader_api_redact_artifact_file_in_place "$car_summary_path"
trader_api_redact_artifact_file_in_place "$provider_prepare_summary_path"

publisher_private_key_file="$(soraswap_config_private_key_temp_file "$config" trader-api-publisher-key)" || exit 1
publisher_submit_status=0
if ! run_sorafs_cli_redacted manifest submit \
  --manifest="$manifest_path" \
  --torii-url="$torii_base" \
  --network-id="$manifest_network_id" \
  --network-prefix="$manifest_network_prefix" \
  --chunk-plan="$plan_path" \
  --authority="$SORASWAP_AUTHORITY" \
  --private-key-file="$publisher_private_key_file" \
  --summary-out="$registry_submit_summary_path" \
  --response-out="$registry_submit_response_path" >/dev/null; then
  publisher_submit_status=1
fi
if ! soraswap_secure_unlink_owned_file "$publisher_private_key_file"; then
  publisher_submit_status=1
fi
publisher_private_key_file=""
(( publisher_submit_status == 0 )) || exit 1
wait_for_trader_api_paid_pin_record \
  "$manifest_digest_hex" \
  "$registry_visibility_path" \
  "$registry_visibility_attempts_path" \
  "$registry_visibility_body_path" \
  "$registry_visibility_error_path"
if ! registry_visibility_json="$(jq -ce --arg digest "$manifest_digest_hex" '
    select(
      type == "object"
      and .manifest.digest_hex == $digest
      and .manifest.status.state == "approved"
    )
  ' "$registry_visibility_path" 2>/dev/null)"; then
  echo "current SoraFS manifest visibility response is missing, invalid, or mismatched" >&2
  exit 1
fi
if ! registry_submit_response_json="$(jq -ce --arg digest "$manifest_digest_hex" '
    select(
      type == "object"
      and keys == ["manifest_digest_hex", "status", "tx_hash_hex"]
      and .status == "submitted"
      and .manifest_digest_hex == $digest
      and ((.tx_hash_hex | type) == "string")
      and (.tx_hash_hex | test("^[0-9a-f]{64}$"))
    )
  ' "$registry_submit_response_path" 2>/dev/null)"; then
  echo "current SoraFS manifest submit response is missing, invalid, or mismatched" >&2
  exit 1
fi
registry_submit_expected_endpoint="${torii_base%/}/v1/sorafs/pin/register"
if ! registry_submit_json="$(jq -ce \
    --arg torii_url "$torii_base" \
    --arg endpoint "$registry_submit_expected_endpoint" \
    --arg authority "$SORASWAP_AUTHORITY" \
    --arg manifest_digest_hex "$manifest_digest_hex" \
    --arg manifest_path "$manifest_path" \
    --arg chunk_plan "$plan_path" \
    --arg manifest_car_digest_hex "$car_digest_hex" \
    --arg chunk_digest_sha3_hex "$car_chunk_digest_sha3_hex" \
    --arg chunker_handle "$provider_chunker_handle" \
    --argjson chunk_plan_chunk_count "$car_chunk_count" \
    --argjson response "$registry_submit_response_json" '
    select(
      type == "object"
      and keys == [
        "authority",
        "chunk_digest_sha3_hex",
        "chunk_plan",
        "chunk_plan_chunk_count",
        "chunker_handle",
        "manifest_car_digest_hex",
        "manifest_digest_hex",
        "manifest_path",
        "pin_policy",
        "status",
        "submission_mode",
        "torii_endpoint",
        "torii_endpoint_requested",
        "torii_response",
        "torii_url"
      ]
      and .status == 202
      and .torii_url == $torii_url
      and .torii_endpoint == $endpoint
      and .torii_endpoint_requested == $endpoint
      and .authority == $authority
      and .submission_mode == "pin_register_http"
      and .manifest_digest_hex == $manifest_digest_hex
      and .manifest_path == $manifest_path
      and .manifest_car_digest_hex == $manifest_car_digest_hex
      and .chunk_digest_sha3_hex == $chunk_digest_sha3_hex
      and .chunker_handle == $chunker_handle
      and .chunk_plan == $chunk_plan
      and .chunk_plan_chunk_count == $chunk_plan_chunk_count
      and (.pin_policy | keys) == ["min_replicas", "retention_epoch", "storage_class"]
      and .pin_policy.min_replicas == 1
      and .pin_policy.storage_class == "hot"
      and .pin_policy.retention_epoch == 86400
      and .torii_response == $response
    )
  ' "$registry_submit_summary_path" 2>/dev/null)"; then
  echo "current SoraFS manifest submit summary is missing, invalid, or mismatched" >&2
  exit 1
fi
registry_submit_json="$(soraswap_redact_sensitive_text "$registry_submit_json")"
trader_api_redact_artifact_file_in_place "$registry_submit_summary_path"
trader_api_redact_artifact_file_in_place "$registry_submit_response_path"
registry_submit_json="$(jq -ce \
  --arg visibility_attempts_path "$(soraswap_display_path "$registry_visibility_attempts_path")" \
  --argjson visibility "$registry_visibility_json" '
  . + {
    visibility_probe: {
      status: "completed",
      attempts_path: $visibility_attempts_path,
      record: $visibility
    }
  }
' <<<"$registry_submit_json")"
printf '%s\n' "$registry_submit_json" > "$registry_submit_summary_path"
provider_ingest_json="$(jq -cn \
  --argjson prepare "$provider_prepare_json" \
  '{
    state: "awaiting_finalized_provider_assignment",
    queued: false,
    direct_http_ingest: false,
    prepare: $prepare
  }')"
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
if [[ "$binding_publish" == "1" ]]; then
  if [[ -z "$service_name" ]]; then
    echo "SORASWAP_PUBLISH_TRADER_API_BINDING=1 requires SORASWAP_TRADER_API_SERVICE_NAME" >&2
    exit 1
  fi
  config_set_xtrace_enabled=0
  if [[ -o xtrace ]]; then
    config_set_xtrace_enabled=1
    set +x
  fi
  api_token_args=()
  api_token_file=""
  api_token_value="${SORASWAP_TORII_API_TOKEN:-}"
  if [[ -n "$api_token_value" ]]; then
    api_token_file="$(printf '%s\n' "$api_token_value" \
      | soraswap_secret_temp_from_stdin trader-api-token)" || exit 1
    api_token_args=(--api-token "$api_token_value")
  fi
  config_set_stderr_file="$(soraswap_secure_temp_file soracloud-config-set-stderr)" || exit 1
  config_set_stderr_raw=""
  config_set_cleanup_status=0
  config_set_command_status=0
  set +e
  {
    config_set_output_raw="$(SORASWAP_TORII_API_TOKEN= iroha_cli_json \
      --config "$config" \
      soracloud service config-set \
      --service-name "$service_name" \
      --config-name torii/app_api_binding \
      --value-file "$binding_path" \
      --torii-url "$torii_base" \
      "${api_token_args[@]}" 2>"$config_set_stderr_file")"
    config_set_command_status=$?
    config_set_stderr_raw="$(cat "$config_set_stderr_file" 2>/dev/null || true)"
  } always {
    set -e
    if ! soraswap_secure_unlink_owned_file "$config_set_stderr_file"; then
      config_set_cleanup_status=1
    fi
    config_set_stderr_file=""
  }
  if (( config_set_cleanup_status != 0 )); then
    config_set_command_status=1
  fi
  if ! printf '%s\n%s' "$config_set_output_raw" "$config_set_stderr_raw" \
    | soraswap_assert_client_output_clean "$config" "$api_token_file"; then
    config_set_output_raw=""
    config_set_stderr_raw=""
    config_set_command_status=1
    echo "SoraCloud config-set credential echo was suppressed" >&2
  fi
  if [[ -n "$api_token_file" ]] && ! soraswap_secure_unlink_owned_file "$api_token_file"; then
    config_set_command_status=1
  fi
  api_token_file=""
  api_token_args=()
  api_token_value=""
  config_set_output="$(soraswap_redact_sensitive_text "$config_set_output_raw")"
  config_set_stderr="$(soraswap_redact_sensitive_text "$config_set_stderr_raw")"
  if (( config_set_command_status != 0 )); then
    config_set_json="$(jq -cn \
      --arg status failed \
      --arg output "$config_set_output" \
      --arg stderr "$config_set_stderr" \
      '{
        status: $status,
        output: $output,
        stderr: $stderr
      }')"
    config_set_status="failed"
  fi
  if [[ "$config_set_status" != "failed" ]]; then
    if config_set_json="$(jq -ce 'select(type == "object")' <<<"$config_set_output" 2>/dev/null)"; then
      config_set_status="completed"
    else
      config_set_json="$(jq -cn \
        --arg status failed \
        --arg output "$config_set_output" \
        --arg stderr "$config_set_stderr" \
        '{
          status: $status,
          error: "current Iroha CLI returned a non-object config-set response",
          output: $output,
          stderr: $stderr
        }')"
      config_set_status="failed"
      echo "current SoraCloud config-set response is missing or invalid" >&2
    fi
  fi
  if (( config_set_xtrace_enabled )); then
    set -x
  fi
fi

cid_probe_body_path="$artifact_dir/app-api.cid_probe.body"
cid_probe_error_path="$artifact_dir/app-api.cid_probe.error"
soraswap_validate_torii_read_max_time || exit 1
cid_probe_http_code=""
cid_probe_json='null'
cid_probe_status="failed"
cid_probe_success_count=0
cid_probe_manifest_match_count=0
cid_probe_propagation_attempt=0
cid_probe_attempts_json='[]'
cid_probe_body=""
cid_probe_parsed='null'
for ((cid_probe_round = 1; cid_probe_round <= gateway_propagation_attempt_count; cid_probe_round++)); do
  cid_probe_attempts_path="$artifact_dir/app-api.cid_probe.attempts.${cid_probe_round}.jsonl"
  cid_probe_success_count=0
  cid_probe_manifest_match_count=0
  cid_probe_captured_success=0
  cid_probe_captured_match=0
  cid_probe_body=""
  cid_probe_parsed='null'
  cid_probe_last_body=""
  cid_probe_last_report_body=""
  : > "$cid_probe_attempts_path"
  for ((cid_probe_attempt = 1; cid_probe_attempt <= cid_probe_attempt_count; cid_probe_attempt++)); do
    cid_probe_attempt_manifest_match=false
    if cid_probe_http_code="$(soraswap_curl_for_config "$cid_probe_client_config" -sS -o "$cid_probe_body_path" -w '%{http_code}' \
      --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
      -H 'Accept: application/json' \
      "$cid_probe_root/v1/app-api/cid/$content_cid" 2>"$cid_probe_error_path")"; then
      cid_probe_last_body="$(cat "$cid_probe_body_path")"
      cid_probe_last_report_body="$(trader_api_probe_report_text "$cid_probe_last_body")"
      printf '%s\n' "$cid_probe_last_report_body" > "$cid_probe_body_path"
      if [[ "$cid_probe_http_code" == 2* ]]; then
        (( cid_probe_success_count += 1 ))
        cid_probe_attempt_parsed="$(jq -c . <<<"$cid_probe_last_body" 2>/dev/null || echo null)"
        if [[ -z "${cid_probe_attempt_parsed//[$'\r\n\t ']}" ]]; then
          cid_probe_attempt_parsed='null'
        fi
        if trader_api_manifest_matches_expected "$cid_probe_attempt_parsed"; then
          (( cid_probe_manifest_match_count += 1 ))
          cid_probe_attempt_manifest_match=true
        fi
        cid_probe_attempt_report_parsed="$(trader_api_probe_report_parsed "$cid_probe_attempt_parsed" "$cid_probe_attempt_manifest_match")"
        if (( cid_probe_captured_success == 0 )); then
          cid_probe_body="$cid_probe_last_report_body"
          cid_probe_parsed="$cid_probe_attempt_report_parsed"
          cid_probe_captured_success=1
        fi
        if [[ "$cid_probe_attempt_manifest_match" == "true" ]] && (( cid_probe_captured_match == 0 )); then
          cid_probe_body="$cid_probe_last_report_body"
          cid_probe_parsed="$cid_probe_attempt_report_parsed"
          cid_probe_captured_match=1
        fi
      fi
      jq -cn \
        --argjson round "$cid_probe_round" \
        --argjson attempt "$cid_probe_attempt" \
        --arg http_code "$cid_probe_http_code" \
        --argjson manifest_match "$cid_probe_attempt_manifest_match" \
        '{propagation_attempt: $round, attempt: $attempt, http_code: $http_code, manifest_match: $manifest_match}' >> "$cid_probe_attempts_path"
    else
      cid_probe_last_body="$(cat "$cid_probe_error_path" 2>/dev/null || true)"
      cid_probe_last_report_body="$(trader_api_probe_report_text "$cid_probe_last_body")"
      printf '%s\n' "$cid_probe_last_report_body" > "$cid_probe_error_path"
      jq -cn \
        --argjson round "$cid_probe_round" \
        --argjson attempt "$cid_probe_attempt" \
        --arg http_code "transport-error" \
        --argjson manifest_match "$cid_probe_attempt_manifest_match" \
        '{propagation_attempt: $round, attempt: $attempt, http_code: $http_code, manifest_match: $manifest_match}' >> "$cid_probe_attempts_path"
    fi

    if [[ "$cid_probe_attempt" -lt "$cid_probe_attempt_count" ]]; then
      sleep "$cid_probe_interval_secs"
    fi
  done

  if [[ "$cid_probe_parsed" == 'null' && -z "$cid_probe_body" ]]; then
    cid_probe_body="$cid_probe_last_report_body"
  fi

  cid_probe_attempts_json="$(jq -sc . "$cid_probe_attempts_path")"
  if (( cid_probe_success_count == cid_probe_attempt_count && cid_probe_manifest_match_count == cid_probe_attempt_count )); then
    cid_probe_status="completed"
  elif (( cid_probe_success_count > 0 )); then
    cid_probe_status="inconsistent"
  else
    cid_probe_status="failed"
  fi
  cid_probe_propagation_attempt="$cid_probe_round"
  if [[ "$cid_probe_status" == "completed" ]]; then
    break
  fi

  if [[ "$cid_probe_round" -lt "$gateway_propagation_attempt_count" ]]; then
    sleep "$gateway_propagation_retry_delay_secs"
  fi
done
cid_probe_json="$(jq -cn \
  --arg status "$cid_probe_status" \
  --arg http_code "$cid_probe_http_code" \
  --arg url "$cid_probe_root/v1/app-api/cid/$content_cid" \
  --arg body "$cid_probe_body" \
  --argjson parsed "$cid_probe_parsed" \
  --argjson success_count "$cid_probe_success_count" \
  --argjson manifest_match_count "$cid_probe_manifest_match_count" \
  --argjson attempt_count "$cid_probe_attempt_count" \
  --argjson propagation_attempt "$cid_probe_propagation_attempt" \
  --argjson propagation_attempt_count "$gateway_propagation_attempt_count" \
  --argjson attempts "$cid_probe_attempts_json" \
  '{
    status: $status,
    http_code: $http_code,
    url: $url,
    body: $body,
    parsed: $parsed,
    success_count: $success_count,
    manifest_match_count: $manifest_match_count,
    attempt_count: $attempt_count,
    propagation_attempt: $propagation_attempt,
    propagation_attempt_count: $propagation_attempt_count,
    attempts: $attempts
  }')"

report_status="completed"
if [[ "$deployment_record_check_status" != "completed" || "$snapshot_check_status" != "completed" || "$cid_probe_status" != "completed" ]]; then
  report_status="degraded"
fi
if [[ "$cid_probe_status" == "failed" || "$config_set_status" == "failed" ]]; then
  report_status="failed"
fi

trader_api_report_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/soraswap-trader-api-report-json.XXXXXX")"
contracts_snapshot_json_path="$trader_api_report_tmp_dir/contracts_snapshot.json"
deploy_snapshot_json_path="$trader_api_report_tmp_dir/deploy_snapshot.json"
printf '%s' "$contracts_snapshot_json" >"$contracts_snapshot_json_path"
printf '%s' "$deploy_snapshot_json" >"$deploy_snapshot_json_path"

report_json="$(jq -n \
  --arg generated_at "$timestamp" \
  --arg environment "$public_env" \
  --arg status "$report_status" \
  --arg app_id "${SORASWAP_TRADER_API_APP_ID:-soraswap.trader}" \
  --arg client_config "$(soraswap_display_path "$config")" \
  --arg torii_url "$torii_base" \
  --arg content_cid "$content_cid" \
  --arg manifest_id_hex "$manifest_id_hex" \
  --arg manifest_digest_hex "$manifest_digest_hex" \
  --arg artifact_dir "$(soraswap_display_path "$artifact_dir")" \
  --arg api_manifest_path "$(soraswap_display_path "$api_manifest_path")" \
  --arg binding_path "$(soraswap_display_path "$binding_path")" \
  --arg deployment_record_check_status "$deployment_record_check_status" \
  --arg deployment_record_check_output "$deployment_record_check_output" \
  --arg snapshot_check_status "$snapshot_check_status" \
  --arg snapshot_check_output "$snapshot_check_output" \
  --arg config_set_status "$config_set_status" \
  --arg service_name "$service_name" \
  --argjson chain_fingerprint "$chain_fingerprint_json" \
  --argjson provider_ingest "$provider_ingest_json" \
  --argjson registry_submit "$registry_submit_json" \
  --argjson routes "$routes_json" \
  --slurpfile contracts_snapshot_file "$contracts_snapshot_json_path" \
  --slurpfile deploy_snapshot_file "$deploy_snapshot_json_path" \
  --argjson cid_probe "$cid_probe_json" \
  --argjson config_set "$config_set_json" \
  '($contracts_snapshot_file[0] // {}) as $contracts_snapshot
  | ($deploy_snapshot_file[0] // {}) as $deploy_snapshot
  | {
    generated_at: $generated_at,
    environment: $environment,
    status: $status,
    app_id: $app_id,
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
    snapshot_check: {
      status: $snapshot_check_status,
      output: $snapshot_check_output
    },
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
    routes: $routes,
    provider_ingest: $provider_ingest,
    registry_submit: $registry_submit,
    cid_probe: $cid_probe,
    binding: {
      status: $config_set_status,
      service_name: (if $service_name == "" then null else $service_name end),
      response: $config_set
    }
  }')"

soraswap_write_json_report_pair "$report_json" "$latest_report" "$timestamped_report"
cleanup_trader_api_report_tmp_dir
trader_api_report_tmp_dir=""
printf '%s\n' "$report_json"

if [[ "$report_status" != "completed" ]]; then
  echo "trader API publication did not complete cleanly: $report_status" >&2
  exit 1
fi
