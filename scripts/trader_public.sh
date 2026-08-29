#!/bin/zsh
set -euo pipefail

SORASWAP_TORII_READ_MAX_TIME_SECS="${SORASWAP_TORII_READ_MAX_TIME_SECS:-60}"
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

mode="${1:-readonly}"
case "$mode" in
  readonly|mutating)
    ;;
  *)
    echo "usage: $(basename "$0") readonly|mutating" >&2
    exit 1
    ;;
esac

public_env="${SORASWAP_PUBLIC_ENV:-testnet}"
case "$public_env" in
  testnet|production)
    ;;
  *)
    echo "trader_public.sh only supports SORASWAP_PUBLIC_ENV=testnet|production; got $public_env" >&2
    exit 1
    ;;
esac

require_positive_json_number_setting() {
  local name="$1"
  local value="$2"
  if ! jq -en --argjson value "$value" '$value | type == "number" and . > 0' >/dev/null 2>&1; then
    echo "$name must be a positive JSON number; got '$value'" >&2
    exit 1
  fi
}

if [[ "$mode" == "mutating" ]]; then
  require_public_mutation_consent "$public_env" "$public_env trader smoke"
  trader_smoke_swap_in="${SORASWAP_TRADER_SMOKE_SWAP_IN:-10}"
  require_positive_json_number_setting "SORASWAP_TRADER_SMOKE_SWAP_IN" "$trader_smoke_swap_in"
fi
trader_response_body_max_chars="${SORASWAP_TRADER_PUBLIC_RESPONSE_BODY_MAX_CHARS:-8192}"
soraswap_require_positive_integer_setting "SORASWAP_TRADER_PUBLIC_RESPONSE_BODY_MAX_CHARS" "$trader_response_body_max_chars" || exit 1
trader_route_probe_attempts="${SORASWAP_TRADER_PUBLIC_ROUTE_PROBE_ATTEMPTS:-3}"
trader_route_probe_retry_delay_secs="${SORASWAP_TRADER_PUBLIC_ROUTE_PROBE_RETRY_DELAY_SECS:-2}"
soraswap_require_positive_integer_setting "SORASWAP_TRADER_PUBLIC_ROUTE_PROBE_ATTEMPTS" "$trader_route_probe_attempts" || exit 1
soraswap_require_nonnegative_number_setting "SORASWAP_TRADER_PUBLIC_ROUTE_PROBE_RETRY_DELAY_SECS" "$trader_route_probe_retry_delay_secs" || exit 1

config="$(client_config_or_default "$public_env")"
soraswap_validate_torii_read_max_time || exit 1
ensure_client "$config"
ensure_authority "$config"
prepare_env_chain_state "$public_env" "$config"
chain_fingerprint_json="$(chain_fingerprint_json_or_null)"
ensure_deployment_records_current "$public_env" "$config"

torii_base="$(torii_base_from_config "$config")"
timestamp="$(utc_timestamp)"
report_dir="$(deployments_dir_for_env "$public_env")"
report_prefix="trader_readonly"
if [[ "$mode" == "mutating" ]]; then
  report_prefix="trader"
fi
latest_report="$report_dir/${report_prefix}.latest.json"
timestamped_report="$report_dir/${report_prefix}.${timestamp}.json"
mkdir -p "$report_dir"

contracts_snapshot_json="$(cat "$(contracts_snapshot_latest_path_for_env "$public_env")")"
deploy_snapshot_path="$(deploy_report_latest_path_for_env "$public_env")"
deploy_snapshot_json='null'
if [[ -f "$deploy_snapshot_path" ]]; then
  deploy_snapshot_json="$(cat "$deploy_snapshot_path")"
fi

report_status="completed"
blocked_reason=""
trader_contract_trace_file=""
trader_previous_contract_trace_file="${SORASWAP_CONTRACT_CALL_TRACE_FILE:-}"
trader_report_tmp_dir=""

cleanup_trader_tmp_files() {
  if [[ -n "$trader_previous_contract_trace_file" ]]; then
    export SORASWAP_CONTRACT_CALL_TRACE_FILE="$trader_previous_contract_trace_file"
  else
    unset SORASWAP_CONTRACT_CALL_TRACE_FILE
  fi
  [[ -z "$trader_contract_trace_file" ]] || rm -f "$trader_contract_trace_file"
  [[ -z "${trader_report_tmp_dir:-}" ]] || rm -rf "$trader_report_tmp_dir"
}

trap cleanup_trader_tmp_files EXIT

if [[ "$mode" == "mutating" ]]; then
  trader_contract_trace_file="$(mktemp "${TMPDIR:-/tmp}/soraswap-trader-tx-trace.XXXXXX")"
  export SORASWAP_CONTRACT_CALL_TRACE_FILE="$trader_contract_trace_file"
fi

snapshot_check_json="$(public_current_deploy_snapshot_check_json "$public_env" "$chain_fingerprint_json" "$(contracts_snapshot_latest_path_for_env "$public_env")" "$deploy_snapshot_path")"
if [[ "$(jq -r '.status // empty' <<<"$snapshot_check_json")" != "completed" ]]; then
  report_status="blocked"
  blocked_reason="public ${public_env} trader snapshot evidence is stale"
  echo "$(soraswap_redact_sensitive_text "$blocked_reason")" >&2
  jq -r '.output // empty' <<<"$snapshot_check_json" | soraswap_redact_sensitive_text >&2
fi

router_contract="$(deployed_contract_id_for_env "$public_env" dlmm.dlmm_router)"
n3x_contract="$(deployed_contract_id_for_env "$public_env" n3x.n3x_hub)"
perps_contract="$(deployed_contract_id_for_env "$public_env" perps.perps_engine)"
farms_contract="$(deployed_contract_id_for_env "$public_env" farms.farm)"
launchpad_contract="$(deployed_contract_id_for_env "$public_env" launchpad.sale_factory)"
options_contract="$(deployed_contract_id_for_env "$public_env" options.factory)"
cover_contract="$(deployed_contract_id_for_env "$public_env" cover.policy_manager)"
xor_id="$(asset_definition_id_for_alias "$config" "$SORASWAP_BASE_ASSET_ALIAS")"
usdt_id="$(asset_definition_id_for_alias "$config" usdt#soraswap.universal)"
encoded_authority="$(uri_encode "$SORASWAP_AUTHORITY")"

trader_public_report_text() {
  local raw="${1:-}"
  local redacted

  redacted="$(soraswap_redact_sensitive_text "$raw")"
  if (( ${#redacted} > trader_response_body_max_chars )); then
    printf '%s...[truncated %s chars]\n' "${redacted[1,$trader_response_body_max_chars]}" "${#redacted}"
  else
    printf '%s\n' "$redacted"
  fi
}

trader_public_route_probe_retryable() {
  local curl_status="$1"
  local http_code="$2"

  if [[ "$curl_status" != "0" ]]; then
    return 0
  fi

  case "$http_code" in
    0|502|503|504)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

request_json() {
  local method="$1"
  local request_path="$2"
  local body="${3:-}"
  local tmp err_tmp http_code response_body response_json='null' curl_status=0 curl_error="" attempt=1

  tmp="$(mktemp "${TMPDIR:-/tmp}/soraswap-trader-public-response.XXXXXX")"
  err_tmp="$(mktemp "${TMPDIR:-/tmp}/soraswap-trader-public-error.XXXXXX")"
  while (( attempt <= trader_route_probe_attempts )); do
    : >"$tmp"
    : >"$err_tmp"
    if [[ "$method" == "POST" ]]; then
      if [[ "$request_path" != "/v1/contracts/view/batch" ]]; then
        echo "unsupported authenticated trader POST route: $request_path" >"$err_tmp"
        curl_status=2
        http_code=0
      elif printf '%s' "$body" | python3 "$SORASWAP_ROOT/scripts/current_torii_contract.py" \
        --config "$config" \
        --environment "$public_env" \
        --authority "$SORASWAP_AUTHORITY" \
        --torii-url "$torii_base" \
        --timeout "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
        view-batch >"$tmp" 2>"$err_tmp"; then
        curl_status=0
        http_code=200
      else
        curl_status="$?"
        http_code=0
      fi
    else
      if http_code="$(soraswap_curl_for_config "$config" -sS \
        --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
        -o "$tmp" \
        -w '%{http_code}' \
        -H 'Accept: application/json' \
        "$torii_base$request_path" 2>"$err_tmp")"; then
        curl_status=0
      else
        curl_status="$?"
      fi
    fi

    if [[ "$http_code" == <-> ]]; then
      http_code="$((10#$http_code))"
    else
      http_code=0
    fi
    curl_error="$(trader_public_report_text "$(cat "$err_tmp")")"
    if trader_public_route_probe_retryable "$curl_status" "$http_code" && (( attempt < trader_route_probe_attempts )); then
      echo "public ${public_env} trader route probe ${method} ${request_path} failed transiently (curl=$curl_status http=$http_code); retrying ($attempt/$trader_route_probe_attempts)" | soraswap_redact_sensitive_text >&2
      sleep "$trader_route_probe_retry_delay_secs"
      attempt=$(( attempt + 1 ))
      continue
    fi
    break
  done
  response_body="$(trader_public_report_text "$(cat "$tmp")")"
  rm -f "$tmp" "$err_tmp"

  if [[ -n "${response_body//[$'\r\n\t ']}" ]] && jq -e . >/dev/null 2>&1 <<<"$response_body"; then
    response_json="$(jq -c . <<<"$response_body")"
  fi

  jq -cn \
    --arg method "$method" \
    --arg path "$request_path" \
    --argjson http_code "${http_code:-0}" \
    --argjson curl_status "$curl_status" \
    --argjson attempts "$attempt" \
    --arg curl_error "$curl_error" \
    --argjson response_json "$response_json" \
    --arg response_body "$response_body" \
    '{
      method: $method,
      path: $path,
      http_code: $http_code,
      curl_status: $curl_status,
      attempts: $attempts,
      transport_error: ($curl_status != 0),
      error: (if $curl_error == "" then null else $curl_error end),
      ok: ($http_code == 200),
      response_json: (if $response_json == null then null else $response_json end),
      response_body: (if $response_json == null then $response_body else null end)
    }'
}

required_routes_json="$(
  jq -cn \
    --argjson view_batch "$(request_json POST "/v1/contracts/view/batch" "$(
      jq -cn \
        --arg authority "$SORASWAP_AUTHORITY" \
        --arg contract_address "$router_contract" \
        '{
          authority: $authority,
          items: [
            {
              contract_address: $contract_address,
              entrypoint: "mirror_state"
            }
          ]
        }'
    )")" \
    --argjson swaps_fills "$(request_json GET "/v1/contracts/rollups/swaps/fills?authority=${encoded_authority}&limit=5")" \
    --argjson swaps_candles "$(request_json GET "/v1/contracts/rollups/swaps/candles?authority=${encoded_authority}&limit=5&bucket_secs=3600")" \
    --argjson trader_activity "$(request_json GET "/v1/contracts/rollups/trader/activity?authority=${encoded_authority}&limit=5")" \
    --argjson trader_account "$(request_json GET "/v1/contracts/rollups/trader/account?authority=${encoded_authority}")" \
    --argjson intents "$(request_json GET "/v1/contracts/rollups/intents?authority=${encoded_authority}&limit=5")" \
    --argjson vault_positions "$(request_json GET "/v1/contracts/rollups/vaults/positions?authority=${encoded_authority}&limit=5")" \
    --argjson operators_status "$(request_json GET "/v1/contracts/rollups/operators/status?authority=${encoded_authority}&limit=5")" \
    --argjson margin_health "$(request_json GET "/v1/contracts/rollups/margin/health?authority=${encoded_authority}&limit=5")" \
    --argjson rwa_lots "$(request_json GET "/v1/contracts/rollups/rwa/lots?authority=${encoded_authority}&limit=5")" \
    --argjson dlmm_hooks "$(request_json GET "/v1/contracts/rollups/dlmm/hooks?authority=${encoded_authority}&limit=5")" \
    '{
      view_batch: $view_batch,
      swaps_fills: $swaps_fills,
      swaps_candles: $swaps_candles,
      trader_activity: $trader_activity,
      trader_account: $trader_account,
      intents: $intents,
      vault_positions: $vault_positions,
      operators_status: $operators_status,
      margin_health: $margin_health,
      rwa_lots: $rwa_lots,
      dlmm_hooks: $dlmm_hooks
    }'
)"

generic_routes_before_json="$(
  jq -cn \
    --argjson activity "$(request_json GET "/v1/contracts/activity?authority=${encoded_authority}&limit=5")" \
    --argjson events "$(request_json GET "/v1/contracts/events?authority=${encoded_authority}&limit=5")" \
    '{
      activity: $activity,
      events: $events
    }'
)"

required_routes_missing_json="$(jq -c 'to_entries | map(select(.value.http_code != 200) | .key)' <<<"$required_routes_json")"
required_routes_transport_missing_json="$(jq -c 'to_entries | map(select(.value.transport_error == true or .value.http_code == 0) | .key)' <<<"$required_routes_json")"
required_routes_available=true
if [[ "$required_routes_missing_json" != "[]" ]]; then
  required_routes_available=false
fi

signer_ready_json='null'
swap_json='null'
required_routes_after_json='null'
required_routes_after_missing_json='null'
generic_routes_after_json='null'
submitted_calls_json='[]'
public_write_health_json='null'

if [[ "$required_routes_available" != true ]]; then
  report_status="blocked"
  if [[ -z "$blocked_reason" ]]; then
    if [[ "$required_routes_transport_missing_json" != "[]" ]]; then
      blocked_reason="public ${public_env} Torii trader routes timed out or failed transport: $(jq -r 'join(", ")' <<<"$required_routes_transport_missing_json")"
    else
      blocked_reason="public ${public_env} Torii trader routes returned non-200 responses: $(jq -r 'join(", ")' <<<"$required_routes_missing_json")"
    fi
  fi
fi

if [[ "$mode" == "mutating" && "$report_status" == "completed" ]]; then
  if signer_ready_output="$(ensure_public_signer_ready "$config" "$SORASWAP_AUTHORITY" autofund 2>&1)"; then
    signer_ready_output="$(soraswap_redact_sensitive_text "$signer_ready_output")"
    signer_ready_json="$(jq -cn \
      --arg status "completed" \
      --arg output "$signer_ready_output" \
      '{status: $status, output: $output}')"
  else
    signer_ready_output="$(soraswap_redact_sensitive_text "$signer_ready_output")"
    signer_ready_json="$(jq -cn \
      --arg status "blocked" \
      --arg output "$signer_ready_output" \
      '{status: $status, output: $output}')"
    report_status="blocked"
    if [[ -z "$blocked_reason" ]]; then
      blocked_reason="public ${public_env} signer funding failed"
    fi
  fi

  if jq -e '.status == "completed"' >/dev/null <<<"$signer_ready_json"; then
    swap_amount_in="$trader_smoke_swap_in"
    xor_before="$(asset_value_for_account_id "$config" "$xor_id" "$SORASWAP_AUTHORITY")"
    usdt_before="$(asset_value_for_account_id "$config" "$usdt_id" "$SORASWAP_AUTHORITY")"
    if swap_output="$(call_contract_and_wait "$config" "$router_contract" route_swap "$(
      jq -cn \
        --arg amount_in "$swap_amount_in" \
        --arg input_is_base "1" \
        --arg min_out "0" \
        '{
          amount_in: $amount_in,
          input_is_base: $input_is_base,
          min_out: $min_out
        }'
    )" 2>&1)"; then
      swap_json="$(jq -cn \
        --arg status "completed" \
        --arg tx_hash "$swap_output" \
        --arg contract_address "$router_contract" \
        --argjson amount_in "$swap_amount_in" \
        --arg xor_before "$xor_before" \
        --arg usdt_before "$usdt_before" \
        --arg xor_after "$(asset_value_for_account_id "$config" "$xor_id" "$SORASWAP_AUTHORITY")" \
        --arg usdt_after "$(asset_value_for_account_id "$config" "$usdt_id" "$SORASWAP_AUTHORITY")" \
        '{
          status: $status,
          tx_hash: $tx_hash,
          contract_address: $contract_address,
          entrypoint: "route_swap",
          amount_in: $amount_in,
          input_is_base: 1,
          min_out: 0,
          balances_before: {
            xor: $xor_before,
            usdt: $usdt_before
          },
          balances_after: {
            xor: $xor_after,
            usdt: $usdt_after
          }
        }')"
    else
      swap_output="$(soraswap_redact_sensitive_text "$swap_output")"
      swap_json="$(jq -cn \
        --arg status "failed" \
        --arg error "$swap_output" \
        --arg contract_address "$router_contract" \
        --argjson amount_in "$swap_amount_in" \
        --arg xor_before "$xor_before" \
        --arg usdt_before "$usdt_before" \
        --arg xor_after "$(asset_value_for_account_id "$config" "$xor_id" "$SORASWAP_AUTHORITY")" \
        --arg usdt_after "$(asset_value_for_account_id "$config" "$usdt_id" "$SORASWAP_AUTHORITY")" \
        '{
          status: $status,
          error: $error,
          contract_address: $contract_address,
          entrypoint: "route_swap",
          amount_in: $amount_in,
          input_is_base: 1,
          min_out: 0,
          balances_before: {
            xor: $xor_before,
            usdt: $usdt_before
          },
          balances_after: {
            xor: $xor_after,
            usdt: $usdt_after
          }
        }')"
      if [[ "$report_status" == "completed" ]]; then
        report_status="failed"
        blocked_reason="trader swap probe failed"
      fi
    fi

    required_routes_after_json="$(
      jq -cn \
        --argjson view_batch "$(request_json POST "/v1/contracts/view/batch" "$(
          jq -cn \
            --arg authority "$SORASWAP_AUTHORITY" \
            --arg contract_address "$router_contract" \
            '{
              authority: $authority,
              items: [
                {
                  contract_address: $contract_address,
                  entrypoint: "mirror_state"
                }
              ]
            }'
        )")" \
        --argjson swaps_fills "$(request_json GET "/v1/contracts/rollups/swaps/fills?authority=${encoded_authority}&limit=5")" \
        --argjson swaps_candles "$(request_json GET "/v1/contracts/rollups/swaps/candles?authority=${encoded_authority}&limit=5&bucket_secs=3600")" \
        --argjson trader_activity "$(request_json GET "/v1/contracts/rollups/trader/activity?authority=${encoded_authority}&limit=5")" \
        --argjson trader_account "$(request_json GET "/v1/contracts/rollups/trader/account?authority=${encoded_authority}")" \
        --argjson intents "$(request_json GET "/v1/contracts/rollups/intents?authority=${encoded_authority}&limit=5")" \
        --argjson vault_positions "$(request_json GET "/v1/contracts/rollups/vaults/positions?authority=${encoded_authority}&limit=5")" \
        --argjson operators_status "$(request_json GET "/v1/contracts/rollups/operators/status?authority=${encoded_authority}&limit=5")" \
        --argjson margin_health "$(request_json GET "/v1/contracts/rollups/margin/health?authority=${encoded_authority}&limit=5")" \
        --argjson rwa_lots "$(request_json GET "/v1/contracts/rollups/rwa/lots?authority=${encoded_authority}&limit=5")" \
        --argjson dlmm_hooks "$(request_json GET "/v1/contracts/rollups/dlmm/hooks?authority=${encoded_authority}&limit=5")" \
        '{
          view_batch: $view_batch,
          swaps_fills: $swaps_fills,
          swaps_candles: $swaps_candles,
          trader_activity: $trader_activity,
          trader_account: $trader_account,
          intents: $intents,
          vault_positions: $vault_positions,
          operators_status: $operators_status,
          margin_health: $margin_health,
          rwa_lots: $rwa_lots,
          dlmm_hooks: $dlmm_hooks
        }'
    )"
    required_routes_after_missing_json="$(jq -c 'to_entries | map(select(.value.http_code != 200) | .key)' <<<"$required_routes_after_json")"
    required_routes_after_transport_missing_json="$(jq -c 'to_entries | map(select(.value.transport_error == true or .value.http_code == 0) | .key)' <<<"$required_routes_after_json")"
    if [[ "$required_routes_after_missing_json" != "[]" && "$report_status" == "completed" ]]; then
      report_status="failed"
      if [[ "$required_routes_after_transport_missing_json" != "[]" ]]; then
        blocked_reason="public ${public_env} Torii trader routes timed out or failed transport after mutation: $(jq -r 'join(", ")' <<<"$required_routes_after_transport_missing_json")"
      else
        blocked_reason="public ${public_env} Torii trader routes returned non-200 responses after mutation: $(jq -r 'join(", ")' <<<"$required_routes_after_missing_json")"
      fi
    fi
    generic_routes_after_json="$(
      jq -cn \
        --argjson activity "$(request_json GET "/v1/contracts/activity?authority=${encoded_authority}&limit=10")" \
        --argjson events "$(request_json GET "/v1/contracts/events?authority=${encoded_authority}&limit=10")" \
        '{
          activity: $activity,
          events: $events
        }'
    )"
  fi
fi

if [[ "$mode" == "mutating" ]]; then
  if [[ -n "$trader_contract_trace_file" && -s "$trader_contract_trace_file" ]]; then
    submitted_calls_json="$(jq -sc . "$trader_contract_trace_file" 2>/dev/null || echo '[]')"
  fi

  if [[ "$report_status" != "completed" || "$submitted_calls_json" != "[]" ]]; then
    trader_health_snapshot_json='null'
    trader_health_issues_json='["unable to sample public chain health"]'
    trader_health_summary=""
    if trader_health_snapshot_json="$(soraswap_public_chain_health_snapshot_json "$config" 2>/dev/null)"; then
      if ! jq -e . >/dev/null 2>&1 <<<"$trader_health_snapshot_json"; then
        trader_health_snapshot_json='null'
      fi
    else
      trader_health_snapshot_json='null'
    fi
    if [[ "$trader_health_snapshot_json" != "null" ]]; then
      trader_health_issues_json="$(soraswap_public_write_health_issues_json "$trader_health_snapshot_json" 2>/dev/null || echo '["unable to evaluate public chain health"]')"
      trader_health_summary="$(soraswap_public_chain_health_summary_text_from_json "$trader_health_snapshot_json" 2>/dev/null || true)"
    fi
    public_write_health_json="$(jq -cn \
      --argjson issues "$trader_health_issues_json" \
      --arg summary "$(soraswap_redact_sensitive_text "$trader_health_summary")" \
      --argjson snapshot "$trader_health_snapshot_json" \
      '{
        issues: $issues,
        summary: $summary,
        snapshot: $snapshot
      }')"
  fi
fi

trader_report_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/soraswap-trader-report-json.XXXXXX")"
contracts_snapshot_json_path="$trader_report_tmp_dir/contracts_snapshot.json"
deploy_snapshot_json_path="$trader_report_tmp_dir/deploy_snapshot.json"
printf '%s' "$contracts_snapshot_json" >"$contracts_snapshot_json_path"
printf '%s' "$deploy_snapshot_json" >"$deploy_snapshot_json_path"

report_json="$(jq -n \
  --arg generated_at "$timestamp" \
  --arg environment "$public_env" \
  --arg mode "$mode" \
  --arg status "$report_status" \
  --arg authority "$SORASWAP_AUTHORITY" \
  --arg client_config "$(soraswap_display_path "$config")" \
  --arg torii_url "$torii_base" \
  --argjson chain_fingerprint "$chain_fingerprint_json" \
  --argjson snapshot_check "$snapshot_check_json" \
  --slurpfile contracts_snapshot_file "$contracts_snapshot_json_path" \
  --slurpfile deploy_snapshot_file "$deploy_snapshot_json_path" \
  --argjson required_routes "$required_routes_json" \
  --argjson required_routes_missing "$required_routes_missing_json" \
  --argjson generic_routes_before "$generic_routes_before_json" \
  --argjson required_routes_after "$required_routes_after_json" \
  --argjson required_routes_after_missing "$required_routes_after_missing_json" \
  --argjson generic_routes_after "$generic_routes_after_json" \
  --argjson signer_ready "$signer_ready_json" \
  --argjson swap "$swap_json" \
  --argjson submitted_calls "$submitted_calls_json" \
  --argjson public_write_health "$public_write_health_json" \
  --arg blocked_reason "$blocked_reason" \
  --arg router_contract "$router_contract" \
  --arg n3x_contract "$n3x_contract" \
  --arg perps_contract "$perps_contract" \
  --arg farms_contract "$farms_contract" \
  --arg launchpad_contract "$launchpad_contract" \
  --arg options_contract "$options_contract" \
  --arg cover_contract "$cover_contract" \
  '($contracts_snapshot_file[0] // {}) as $contracts_snapshot
  | ($deploy_snapshot_file[0] // {}) as $deploy_snapshot
  | {
    generated_at: $generated_at,
    environment: $environment,
    mode: $mode,
    status: $status,
    blocked_reason: (if $blocked_reason == "" then null else $blocked_reason end),
    authority: $authority,
    client_config: $client_config,
    torii_url: $torii_url,
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
    contracts: {
      swaps: $router_contract,
      n3x: $n3x_contract,
      perps: $perps_contract,
      farms: $farms_contract,
      launchpad: $launchpad_contract,
      options: $options_contract,
      cover: $cover_contract
    },
    route_probes: {
      required_before: $required_routes,
      required_missing: $required_routes_missing,
      generic_before: $generic_routes_before,
      required_after: (if $required_routes_after == null then null else $required_routes_after end),
      required_after_missing: (if $required_routes_after_missing == null then null else $required_routes_after_missing end),
      generic_after: (if $generic_routes_after == null then null else $generic_routes_after end)
    },
    mutation: {
      signer_ready: (if $signer_ready == null then null else $signer_ready end),
      swap: (if $swap == null then null else $swap end),
      submitted_calls: $submitted_calls,
      latest_submitted_call: ($submitted_calls[-1] // null)
    },
    public_write_health: (if $public_write_health == null then null else $public_write_health end)
  }'
)"

soraswap_write_json_report_pair "$report_json" "$latest_report" "$timestamped_report"
rm -rf "$trader_report_tmp_dir"
trader_report_tmp_dir=""
printf '%s\n' "$report_json"

if [[ "$report_status" != "completed" ]]; then
  exit 1
fi
