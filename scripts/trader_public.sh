#!/bin/zsh
set -euo pipefail

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

if [[ "$mode" == "mutating" && "${SORASWAP_ALLOW_TESTNET_MUTATIONS:-0}" != "1" ]]; then
  echo "$public_env trader smoke is mutation-gated; export SORASWAP_ALLOW_TESTNET_MUTATIONS=1 to continue" >&2
  exit 1
fi

config="$(client_config_or_default "$public_env")"
ensure_client "$config"
ensure_authority "$config"
prepare_env_chain_state "$public_env" "$config"
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

request_json() {
  local method="$1"
  local request_path="$2"
  local body="${3:-}"
  local tmp http_code response_body response_json='null'

  tmp="$(/usr/bin/mktemp)"
  if [[ "$method" == "POST" ]]; then
    http_code="$(curl -sS \
      --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
      -o "$tmp" \
      -w '%{http_code}' \
      -H 'Accept: application/json' \
      -H 'Content-Type: application/json' \
      -H "X-Iroha-API-Version: $SORASWAP_TORII_API_VERSION" \
      -X POST \
      "$torii_base$request_path" \
      -d "$body" || true)"
  else
    http_code="$(curl -sS \
      --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
      -o "$tmp" \
      -w '%{http_code}' \
      -H 'Accept: application/json' \
      -H "X-Iroha-API-Version: $SORASWAP_TORII_API_VERSION" \
      "$torii_base$request_path" || true)"
  fi
  response_body="$(cat "$tmp")"
  rm -f "$tmp"

  if [[ -n "${response_body//[$'\r\n\t ']}" ]] && jq -e . >/dev/null 2>&1 <<<"$response_body"; then
    response_json="$(jq -c . <<<"$response_body")"
  fi

  jq -cn \
    --arg method "$method" \
    --arg path "$request_path" \
    --argjson http_code "${http_code:-0}" \
    --argjson response_json "$response_json" \
    --arg response_body "$response_body" \
    '{
      method: $method,
      path: $path,
      http_code: $http_code,
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

legacy_routes_before_json="$(
  jq -cn \
    --argjson activity "$(request_json GET "/v1/contracts/activity?authority=${encoded_authority}&limit=5")" \
    --argjson events "$(request_json GET "/v1/contracts/events?authority=${encoded_authority}&limit=5")" \
    '{
      activity: $activity,
      events: $events
    }'
)"

required_routes_missing_json="$(jq -c 'to_entries | map(select(.value.http_code != 200) | .key)' <<<"$required_routes_json")"
required_routes_available=true
if [[ "$required_routes_missing_json" != "[]" ]]; then
  required_routes_available=false
fi

signer_ready_json='null'
swap_json='null'
required_routes_after_json='null'
legacy_routes_after_json='null'
report_status="completed"
blocked_reason=""

if [[ "$required_routes_available" != true ]]; then
  report_status="blocked"
  blocked_reason="public ${public_env} Torii is missing trader routes: $(jq -r 'join(", ")' <<<"$required_routes_missing_json")"
fi

if [[ "$mode" == "mutating" ]]; then
  if signer_ready_output="$(ensure_public_signer_ready "$config" "$SORASWAP_AUTHORITY" autofund 2>&1)"; then
    signer_ready_json="$(jq -cn \
      --arg status "completed" \
      --arg output "$signer_ready_output" \
      '{status: $status, output: $output}')"
  else
    signer_ready_json="$(jq -cn \
      --arg status "blocked" \
      --arg output "$signer_ready_output" \
      '{status: $status, output: $output}')"
    report_status="blocked"
    if [[ -z "$blocked_reason" ]]; then
      blocked_reason="testnet signer funding failed"
    fi
  fi

  if jq -e '.status == "completed"' >/dev/null <<<"$signer_ready_json"; then
    swap_amount_in="${SORASWAP_TRADER_SMOKE_SWAP_IN:-10}"
    xor_before="$(asset_value_for_account_id "$config" "$xor_id" "$SORASWAP_AUTHORITY")"
    usdt_before="$(asset_value_for_account_id "$config" "$usdt_id" "$SORASWAP_AUTHORITY")"
    if swap_output="$(call_contract_and_wait "$config" "$router_contract" route_swap "$(
      jq -cn \
        --argjson amount_in "$swap_amount_in" \
        --argjson input_is_base 1 \
        --argjson min_out 0 \
        '{
          amount_in: $amount_in,
          input_is_base: $input_is_base,
          min_out: $min_out
        }'
    )" 2>&1)"; then
      swap_json="$(jq -cn \
        --arg status "completed" \
        --arg tx_hash "$swap_output" \
        --argjson amount_in "$swap_amount_in" \
        --arg xor_before "$xor_before" \
        --arg usdt_before "$usdt_before" \
        --arg xor_after "$(asset_value_for_account_id "$config" "$xor_id" "$SORASWAP_AUTHORITY")" \
        --arg usdt_after "$(asset_value_for_account_id "$config" "$usdt_id" "$SORASWAP_AUTHORITY")" \
        '{
          status: $status,
          tx_hash: $tx_hash,
          amount_in: $amount_in,
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
      swap_json="$(jq -cn \
        --arg status "failed" \
        --arg error "$swap_output" \
        --argjson amount_in "$swap_amount_in" \
        --arg xor_before "$xor_before" \
        --arg usdt_before "$usdt_before" \
        --arg xor_after "$(asset_value_for_account_id "$config" "$xor_id" "$SORASWAP_AUTHORITY")" \
        --arg usdt_after "$(asset_value_for_account_id "$config" "$usdt_id" "$SORASWAP_AUTHORITY")" \
        '{
          status: $status,
          error: $error,
          amount_in: $amount_in,
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
        --argjson swaps_fills "$(request_json GET "/v1/contracts/rollups/swaps/fills?authority=${encoded_authority}&limit=5")" \
        --argjson trader_activity "$(request_json GET "/v1/contracts/rollups/trader/activity?authority=${encoded_authority}&limit=5")" \
        --argjson trader_account "$(request_json GET "/v1/contracts/rollups/trader/account?authority=${encoded_authority}")" \
        --argjson intents "$(request_json GET "/v1/contracts/rollups/intents?authority=${encoded_authority}&limit=5")" \
        --argjson vault_positions "$(request_json GET "/v1/contracts/rollups/vaults/positions?authority=${encoded_authority}&limit=5")" \
        --argjson operators_status "$(request_json GET "/v1/contracts/rollups/operators/status?authority=${encoded_authority}&limit=5")" \
        --argjson margin_health "$(request_json GET "/v1/contracts/rollups/margin/health?authority=${encoded_authority}&limit=5")" \
        --argjson rwa_lots "$(request_json GET "/v1/contracts/rollups/rwa/lots?authority=${encoded_authority}&limit=5")" \
        --argjson dlmm_hooks "$(request_json GET "/v1/contracts/rollups/dlmm/hooks?authority=${encoded_authority}&limit=5")" \
        '{
          swaps_fills: $swaps_fills,
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
    legacy_routes_after_json="$(
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

report_json="$(jq -n \
  --arg generated_at "$timestamp" \
  --arg environment "$public_env" \
  --arg mode "$mode" \
  --arg status "$report_status" \
  --arg authority "$SORASWAP_AUTHORITY" \
  --arg client_config "$config" \
  --arg torii_url "$torii_base" \
  --argjson chain_fingerprint "${SORASWAP_CHAIN_FINGERPRINT_JSON:-null}" \
  --argjson contracts_snapshot "$contracts_snapshot_json" \
  --argjson deploy_snapshot "$deploy_snapshot_json" \
  --argjson required_routes "$required_routes_json" \
  --argjson required_routes_missing "$required_routes_missing_json" \
  --argjson legacy_routes_before "$legacy_routes_before_json" \
  --argjson required_routes_after "$required_routes_after_json" \
  --argjson legacy_routes_after "$legacy_routes_after_json" \
  --argjson signer_ready "$signer_ready_json" \
  --argjson swap "$swap_json" \
  --arg blocked_reason "$blocked_reason" \
  --arg router_contract "$router_contract" \
  --arg n3x_contract "$n3x_contract" \
  --arg perps_contract "$perps_contract" \
  --arg farms_contract "$farms_contract" \
  --arg launchpad_contract "$launchpad_contract" \
  --arg options_contract "$options_contract" \
  --arg cover_contract "$cover_contract" \
  '{
    generated_at: $generated_at,
    environment: $environment,
    mode: $mode,
    status: $status,
    blocked_reason: (if $blocked_reason == "" then null else $blocked_reason end),
    authority: $authority,
    client_config: $client_config,
    torii_url: $torii_url,
    chain_fingerprint: $chain_fingerprint,
    contracts_snapshot: {
      generated_at: ($contracts_snapshot.generated_at // null)
    },
    deploy_snapshot: {
      generated_at: ($deploy_snapshot.generated_at // null),
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
      legacy_before: $legacy_routes_before,
      required_after: (if $required_routes_after == null then null else $required_routes_after end),
      legacy_after: (if $legacy_routes_after == null then null else $legacy_routes_after end)
    },
    mutation: {
      signer_ready: (if $signer_ready == null then null else $signer_ready end),
      swap: (if $swap == null then null else $swap end)
    }
  }'
)"

printf '%s\n' "$report_json" > "$latest_report"
printf '%s\n' "$report_json" > "$timestamped_report"
printf '%s\n' "$report_json"

if [[ "$report_status" != "completed" ]]; then
  exit 1
fi
