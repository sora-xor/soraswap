#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

mode="${1:-local}"
config="$(client_config_or_default "$mode")"
ensure_client "$config"
ensure_authority "$config"

n3x_hub_contract="$(deployed_contract_id_for_env "$mode" n3x.n3x_hub)"
dlmm_router_contract="$(deployed_contract_id_for_env "$mode" dlmm.dlmm_router)"
dlmm_pool_contract="$(deployed_contract_id_for_env "$mode" dlmm.dlmm_pool)"
launchpad_sale_factory_contract="$(deployed_contract_id_for_env "$mode" launchpad.sale_factory)"
referral_registry_contract="$(deployed_contract_id_for_env "$mode" referral.registry)"
farms_farm_contract="$(deployed_contract_id_for_env "$mode" farms.farm)"
perps_engine_contract="$(deployed_contract_id_for_env "$mode" perps.perps_engine)"
options_series_manager_contract="$(deployed_contract_id_for_env "$mode" options.series_manager)"
cover_policy_manager_contract="$(deployed_contract_id_for_env "$mode" cover.policy_manager)"
automation_job_queue_contract="$(deployed_contract_id_for_env "$mode" automation.job_queue)"

vault_account="$(treasury_account_for_mode "$mode")"
pool_fee_pips="${SORASWAP_POOL_FEE_PIPS:-3000}"
pool_bin_step="${SORASWAP_POOL_BIN_STEP:-1}"
pool_active_bin="${SORASWAP_POOL_ACTIVE_BIN:-0}"
pool_seed_base="${SORASWAP_POOL_SEED_BASE:-1000}"
pool_seed_quote="${SORASWAP_POOL_SEED_QUOTE:-1000}"
pool_seed_next_base="${SORASWAP_POOL_SEED_NEXT_BASE:-1000}"
pool_seed_next_quote="${SORASWAP_POOL_SEED_NEXT_QUOTE:-1000}"
pool_seed_far_base="${SORASWAP_POOL_SEED_FAR_BASE:-1000}"
pool_seed_far_quote="${SORASWAP_POOL_SEED_FAR_QUOTE:-1000}"
pool_position_id="${SORASWAP_POOL_POSITION_ID:-smoke_dlmm_lp}"
pool_position_base="${SORASWAP_POOL_POSITION_BASE:-500}"
pool_position_quote="${SORASWAP_POOL_POSITION_QUOTE:-500}"
pool_position_min_shares_out="${SORASWAP_POOL_POSITION_MIN_SHARES_OUT:-1}"
pool_impact_cap_bps="${SORASWAP_POOL_IMPACT_CAP_BPS:-10000}"
pool_min_reserve_base="${SORASWAP_POOL_MIN_RESERVE_BASE:-0}"
pool_min_reserve_quote="${SORASWAP_POOL_MIN_RESERVE_QUOTE:-0}"
pool_max_bins_per_swap="${SORASWAP_POOL_MAX_BINS_PER_SWAP:-8}"
pool_bin_liquidity_cap="${SORASWAP_POOL_BIN_LIQUIDITY_CAP:-0}"
sale_name="${SORASWAP_SALE_NAME:-genesis_sale}"
series_name="${SORASWAP_SERIES_NAME:-genesis_series}"
policy_name="${SORASWAP_POLICY_NAME:-genesis_policy}"
bootstrap_scope="${SORASWAP_BOOTSTRAP_SCOPE:-full}"

xor_id="$(asset_definition_id_for_alias "$config" "$SORASWAP_BASE_ASSET_ALIAS")"
usdt_id="$(asset_definition_id_for_alias "$config" usdt#soraswap.universal)"
usdc_id="$(asset_definition_id_for_alias "$config" usdc#soraswap.universal)"
kusd_id="$(asset_definition_id_for_alias "$config" kusd#soraswap.universal)"
n3x_id="$(asset_definition_id_for_alias "$config" n3x#soraswap.universal)"

echo "bootstrap contract state via $config"

ensure_account_registered "$config" "$vault_account" soraswap

warm_view() {
  local contract_id="$1"
  local entrypoint="$2"
  local payload_json="${3:-null}"

  SORASWAP_CONTRACT_VIEW_MAX_TIME_SECS="${SORASWAP_WARM_VIEW_TIMEOUT_SECS:-5}" \
    submit_contract_view "$config" "$contract_id" "$entrypoint" "$SORASWAP_SMOKE_GAS_LIMIT" "$payload_json" \
    >/dev/null 2>&1 || true
}

view_result_json() {
  local contract_id="$1"
  local entrypoint="$2"
  local payload_json="${3:-null}"
  local response_json

  response_json="$(submit_contract_view "$config" "$contract_id" "$entrypoint" "$SORASWAP_SMOKE_GAS_LIMIT" "$payload_json")"
  contract_view_result_json "$response_json"
}

fail_bootstrap_diff() {
  local label="$1"
  local expected_json="$2"
  local actual_json="$3"
  local prior_json="${4:-null}"

  echo "bootstrap state mismatch for $label" >&2
  jq -n \
    --arg label "$label" \
    --argjson expected "$expected_json" \
    --argjson actual "$actual_json" \
    --argjson prior "$prior_json" \
    '{
      label: $label,
      expected: $expected,
      actual: $actual
    } + (if $prior == null then {} else {accepted_prior_state: $prior} end)' >&2
  return 1
}

ensure_init_or_skip() {
  local label="$1"
  local contract_id="$2"
  local view_entrypoint="$3"
  local view_payload_json="$4"
  local expected_json="$5"
  local init_entrypoint="$6"
  local init_payload_json="$7"
  local actual_json

  if actual_json="$(view_result_json "$contract_id" "$view_entrypoint" "$view_payload_json" 2>/dev/null)"; then
    if json_equals "$actual_json" "$expected_json"; then
      echo "bootstrap skip: $label already matches expected state"
      return 0
    fi
    fail_bootstrap_diff "$label" "$expected_json" "$actual_json"
  fi

  echo "bootstrap init: $label"
  call_contract_and_wait "$config" "$contract_id" "$init_entrypoint" "$init_payload_json" >/dev/null
  actual_json="$(view_result_json "$contract_id" "$view_entrypoint" "$view_payload_json")"
  if ! json_equals "$actual_json" "$expected_json"; then
    fail_bootstrap_diff "$label" "$expected_json" "$actual_json"
  fi
}

ensure_step_from_prior_or_skip() {
  local label="$1"
  local contract_id="$2"
  local view_entrypoint="$3"
  local view_payload_json="$4"
  local accepted_prior_json="$5"
  local expected_json="$6"
  local call_entrypoint="$7"
  local call_payload_json="$8"
  local actual_json

  actual_json="$(view_result_json "$contract_id" "$view_entrypoint" "$view_payload_json")"
  if json_equals "$actual_json" "$expected_json"; then
    echo "bootstrap skip: $label already matches expected state"
    return 0
  fi
  if ! json_equals "$actual_json" "$accepted_prior_json"; then
    fail_bootstrap_diff "$label" "$expected_json" "$actual_json" "$accepted_prior_json"
  fi

  echo "bootstrap apply: $label"
  call_contract_and_wait "$config" "$contract_id" "$call_entrypoint" "$call_payload_json" >/dev/null
  actual_json="$(view_result_json "$contract_id" "$view_entrypoint" "$view_payload_json")"
  if ! json_equals "$actual_json" "$expected_json"; then
    fail_bootstrap_diff "$label" "$expected_json" "$actual_json" "$accepted_prior_json"
  fi
}

dlmm_seed_snapshot_json() {
  local next_bin_id="$1"
  local far_bin_id="$2"
  local active_json next_json far_json position_json

  active_json="$(view_result_json "$dlmm_pool_contract" mirror_bin "$(jq -cn --argjson bin_id "$pool_active_bin" '{bin_id: $bin_id}')")"
  next_json="$(view_result_json "$dlmm_pool_contract" mirror_bin "$(jq -cn --argjson bin_id "$next_bin_id" '{bin_id: $bin_id}')")"
  far_json="$(view_result_json "$dlmm_pool_contract" mirror_bin "$(jq -cn --argjson bin_id "$far_bin_id" '{bin_id: $bin_id}')")"
  position_json="$(view_result_json "$dlmm_pool_contract" mirror_position "$(jq -cn --arg position_id "$pool_position_id" '{position_id: $position_id}')")"

  jq -cn \
    --argjson active_bin "$active_json" \
    --argjson next_bin "$next_json" \
    --argjson far_bin "$far_json" \
    --argjson position "$position_json" \
    '{
      active_bin: $active_bin,
      next_bin: $next_bin,
      far_bin: $far_bin,
      position: $position
    }'
}

ensure_dlmm_seed_state() {
  local next_bin_id="$1"
  local far_bin_id="$2"
  local empty_state_json="$3"
  local expected_state_json="$4"
  local actual_state_json seed_payload_json position_payload_json

  actual_state_json="$(dlmm_seed_snapshot_json "$next_bin_id" "$far_bin_id")"
  if json_equals "$actual_state_json" "$expected_state_json"; then
    echo "bootstrap skip: dlmm pool seed state already matches expected snapshot"
    return 0
  fi
  if ! json_equals "$actual_state_json" "$empty_state_json"; then
    fail_bootstrap_diff "dlmm pool seed state" "$expected_state_json" "$actual_state_json" "$empty_state_json"
  fi

  echo "bootstrap apply: dlmm pool seed state"

  seed_payload_json="$(jq -cn \
    --arg provider "$SORASWAP_AUTHORITY" \
    --arg vault "$vault_account" \
    --arg base_asset "$xor_id" \
    --arg quote_asset "$usdt_id" \
    --argjson bin_id "$pool_active_bin" \
    --argjson base_amount "$pool_seed_base" \
    --argjson quote_amount "$pool_seed_quote" \
    '{
      provider: $provider,
      vault: $vault,
      base_asset: $base_asset,
      quote_asset: $quote_asset,
      bin_id: $bin_id,
      base_amount: $base_amount,
      quote_amount: $quote_amount
    }')"
  call_contract_and_wait "$config" "$dlmm_pool_contract" seed_bin_with_assets "$seed_payload_json" >/dev/null

  seed_payload_json="$(jq -cn \
    --arg provider "$SORASWAP_AUTHORITY" \
    --arg vault "$vault_account" \
    --arg base_asset "$xor_id" \
    --arg quote_asset "$usdt_id" \
    --argjson bin_id "$next_bin_id" \
    --argjson base_amount "$pool_seed_next_base" \
    --argjson quote_amount "$pool_seed_next_quote" \
    '{
      provider: $provider,
      vault: $vault,
      base_asset: $base_asset,
      quote_asset: $quote_asset,
      bin_id: $bin_id,
      base_amount: $base_amount,
      quote_amount: $quote_amount
    }')"
  call_contract_and_wait "$config" "$dlmm_pool_contract" seed_bin_with_assets "$seed_payload_json" >/dev/null

  seed_payload_json="$(jq -cn \
    --arg provider "$SORASWAP_AUTHORITY" \
    --arg vault "$vault_account" \
    --arg base_asset "$xor_id" \
    --arg quote_asset "$usdt_id" \
    --argjson bin_id "$far_bin_id" \
    --argjson base_amount "$pool_seed_far_base" \
    --argjson quote_amount "$pool_seed_far_quote" \
    '{
      provider: $provider,
      vault: $vault,
      base_asset: $base_asset,
      quote_asset: $quote_asset,
      bin_id: $bin_id,
      base_amount: $base_amount,
      quote_amount: $quote_amount
    }')"
  call_contract_and_wait "$config" "$dlmm_pool_contract" seed_bin_with_assets "$seed_payload_json" >/dev/null

  position_payload_json="$(jq -cn \
    --arg position_id "$pool_position_id" \
    --arg provider "$SORASWAP_AUTHORITY" \
    --arg vault "$vault_account" \
    --arg base_asset "$xor_id" \
    --arg quote_asset "$usdt_id" \
    --argjson bin_id "$pool_active_bin" \
    --argjson base_amount "$pool_position_base" \
    --argjson quote_amount "$pool_position_quote" \
    --argjson min_shares_out "$pool_position_min_shares_out" \
    '{
      position_id: $position_id,
      provider: $provider,
      vault: $vault,
      base_asset: $base_asset,
      quote_asset: $quote_asset,
      bin_id: $bin_id,
      base_amount: $base_amount,
      quote_amount: $quote_amount,
      min_shares_out: $min_shares_out
    }')"
  call_contract_and_wait "$config" "$dlmm_pool_contract" add_position_liquidity_with_assets "$position_payload_json" >/dev/null

  actual_state_json="$(dlmm_seed_snapshot_json "$next_bin_id" "$far_bin_id")"
  if ! json_equals "$actual_state_json" "$expected_state_json"; then
    fail_bootstrap_diff "dlmm pool seed state" "$expected_state_json" "$actual_state_json" "$empty_state_json"
  fi
}

warmup_sale_payload="$(jq -cn --arg sale "warmup" '{sale: $sale}')"
warmup_member_payload="$(jq -cn --arg member "warmup" '{member: $member}')"
warmup_position_payload="$(jq -cn --arg position "warmup" '{position: $position}')"
warmup_ticket_payload="$(jq -cn --arg ticket "warmup" '{ticket: $ticket}')"
warmup_series_payload="$(jq -cn --arg series "warmup" '{series: $series}')"
warmup_policy_payload="$(jq -cn --arg policy "warmup" '{policy: $policy}')"
warmup_job_payload="$(jq -cn --arg job "warmup" '{job: $job}')"
warmup_quote_mint_payload='{"usdt_in":0,"usdc_in":0,"kusd_in":0}'
warmup_quote_direct_payload='{"reserve_in":1,"reserve_out":1,"amount_in":1,"fee_pips":0}'

# The first IVM execution against a freshly deployed debug localnet can be
# slow enough to trip the single-peer consensus timeout. Prewarm each contract
# with a lightweight view before the first mutating bootstrap call.
warm_view "$n3x_hub_contract" quote_mint "$warmup_quote_mint_payload"
warm_view "$dlmm_router_contract" quote_direct "$warmup_quote_direct_payload"
warm_view "$dlmm_pool_contract" pool_config
warm_view "$launchpad_sale_factory_contract" sale_config "$warmup_sale_payload"
warm_view "$referral_registry_contract" registry_config
warm_view "$farms_farm_contract" farm_config
warm_view "$perps_engine_contract" engine_config
warm_view "$options_series_manager_contract" series_config "$warmup_series_payload"
warm_view "$cover_policy_manager_contract" policy_config "$warmup_policy_payload"
warm_view "$automation_job_queue_contract" mirror_job "$warmup_job_payload"

n3x_expected_json="$(jq -cn \
  --arg usdt_asset "$usdt_id" \
  --arg usdc_asset "$usdc_id" \
  --arg kusd_asset "$kusd_id" \
  --arg n3x_asset "$n3x_id" \
  --arg vault_account "$vault_account" \
  '[ $usdt_asset, $usdc_asset, $kusd_asset, $n3x_asset, $vault_account, 0, 0, 3334, 3333, 3333 ]')"
n3x_init_payload="$(jq -cn \
  --arg usdt_asset "$usdt_id" \
  --arg usdc_asset "$usdc_id" \
  --arg kusd_asset "$kusd_id" \
  --arg n3x_asset "$n3x_id" \
  --arg vault_account "$vault_account" \
  '{
    usdt_asset: $usdt_asset,
    usdc_asset: $usdc_asset,
    kusd_asset: $kusd_asset,
    n3x_asset: $n3x_asset,
    vault_account: $vault_account
  }')"
ensure_init_or_skip \
  "n3x hub config" \
  "$n3x_hub_contract" \
  "hub_config" \
  null \
  "$n3x_expected_json" \
  "init_hub" \
  "$n3x_init_payload"

router_expected_json="$(jq -cn --arg base_asset "$xor_id" --argjson default_fee_pips "$pool_fee_pips" '[ $base_asset, $default_fee_pips ]')"
router_init_payload="$(jq -cn \
  --arg base_asset "$xor_id" \
  --argjson default_fee_pips "$pool_fee_pips" \
  '{ base_asset: $base_asset, default_fee_pips: $default_fee_pips }')"
ensure_init_or_skip \
  "dlmm router config" \
  "$dlmm_router_contract" \
  "router_config" \
  null \
  "$router_expected_json" \
  "init_router" \
  "$router_init_payload"

pool_expected_json="$(jq -cn \
  --arg base_asset "$xor_id" \
  --arg quote_asset "$usdt_id" \
  --arg vault_account "$vault_account" \
  --argjson fee_pips "$pool_fee_pips" \
  --argjson bin_step "$pool_bin_step" \
  --argjson active_bin "$pool_active_bin" \
  '[ $base_asset, $quote_asset, $vault_account, $fee_pips, $bin_step, $active_bin ]')"
pool_init_payload="$(jq -cn \
  --arg base_asset "$xor_id" \
  --arg quote_asset "$usdt_id" \
  --arg vault_account "$vault_account" \
  --argjson fee_pips "$pool_fee_pips" \
  --argjson bin_step "$pool_bin_step" \
  --argjson active_bin "$pool_active_bin" \
  '{
    base_asset: $base_asset,
    quote_asset: $quote_asset,
    vault_account: $vault_account,
    fee_pips: $fee_pips,
    bin_step: $bin_step,
    active_bin: $active_bin
  }')"
if ! view_result_json "$dlmm_pool_contract" pool_config null >/dev/null 2>&1; then
  call_contract_and_wait "$config" "$dlmm_pool_contract" warm_write null >/dev/null
fi
ensure_init_or_skip \
  "dlmm pool config" \
  "$dlmm_pool_contract" \
  "pool_config" \
  null \
  "$pool_expected_json" \
  "init_pool" \
  "$pool_init_payload"

pool_risk_prior_json='[10000,0,0,32,0]'
pool_risk_expected_json="$(jq -cn \
  --argjson impact_cap_bps "$pool_impact_cap_bps" \
  --argjson min_reserve_base "$pool_min_reserve_base" \
  --argjson min_reserve_quote "$pool_min_reserve_quote" \
  --argjson max_bins_per_swap "$pool_max_bins_per_swap" \
  --argjson bin_liquidity_cap "$pool_bin_liquidity_cap" \
  '[ $impact_cap_bps, $min_reserve_base, $min_reserve_quote, $max_bins_per_swap, $bin_liquidity_cap ]')"
pool_risk_payload="$(jq -cn \
  --argjson impact_cap_bps "$pool_impact_cap_bps" \
  --argjson min_reserve_base "$pool_min_reserve_base" \
  --argjson min_reserve_quote "$pool_min_reserve_quote" \
  --argjson max_bins_per_swap "$pool_max_bins_per_swap" \
  --argjson bin_liquidity_cap "$pool_bin_liquidity_cap" \
  '{
    impact_cap_bps: $impact_cap_bps,
    min_reserve_base: $min_reserve_base,
    min_reserve_quote: $min_reserve_quote,
    max_bins_per_swap: $max_bins_per_swap,
    bin_liquidity_cap: $bin_liquidity_cap
  }')"
ensure_step_from_prior_or_skip \
  "dlmm pool risk config" \
  "$dlmm_pool_contract" \
  "risk_config" \
  null \
  "$pool_risk_prior_json" \
  "$pool_risk_expected_json" \
  "set_risk_params" \
  "$pool_risk_payload"

next_bin_id=$(( pool_active_bin + pool_bin_step ))
far_bin_id=$(( pool_active_bin + (2 * pool_bin_step) ))
expected_active_share_supply=$(( pool_seed_base + pool_seed_quote + pool_position_base + pool_position_quote ))
expected_position_shares=$(( pool_position_base + pool_position_quote ))
dlmm_seed_empty_json='{"active_bin":[0,0,0,0,0],"next_bin":[0,0,0,0,0],"far_bin":[0,0,0,0,0],"position":[0,0,0,0,0,0,0]}'
dlmm_seed_expected_json="$(jq -cn \
  --argjson active_base "$(( pool_seed_base + pool_position_base ))" \
  --argjson active_quote "$(( pool_seed_quote + pool_position_quote ))" \
  --argjson active_share_supply "$expected_active_share_supply" \
  --argjson next_base "$pool_seed_next_base" \
  --argjson next_quote "$pool_seed_next_quote" \
  --argjson next_share_supply "$(( pool_seed_next_base + pool_seed_next_quote ))" \
  --argjson far_base "$pool_seed_far_base" \
  --argjson far_quote "$pool_seed_far_quote" \
  --argjson far_share_supply "$(( pool_seed_far_base + pool_seed_far_quote ))" \
  --argjson active_bin "$pool_active_bin" \
  --argjson position_shares "$expected_position_shares" \
  '{
    active_bin: [ $active_base, $active_quote, $active_share_supply, 0, 0 ],
    next_bin: [ $next_base, $next_quote, $next_share_supply, 0, 0 ],
    far_bin: [ $far_base, $far_quote, $far_share_supply, 0, 0 ],
    position: [ 1, $active_bin, $position_shares, 0, 0, 0, 0 ]
  }')"
ensure_dlmm_seed_state "$next_bin_id" "$far_bin_id" "$dlmm_seed_empty_json" "$dlmm_seed_expected_json"

if [[ "$bootstrap_scope" == "foundation" ]]; then
  echo "post-deploy foundation contract state initialized"
  exit 0
fi

sale_expected_json="$(jq -cn \
  --arg sale_asset "$n3x_id" \
  --arg payment_asset "$xor_id" \
  --arg treasury "$vault_account" \
  '[ $sale_asset, $payment_asset, $treasury, 1, 1, 100000, 0, 0 ]')"
sale_init_payload="$(jq -cn \
  --arg sale "$sale_name" \
  --arg sale_asset "$n3x_id" \
  --arg payment_asset "$xor_id" \
  --arg treasury "$vault_account" \
  --argjson unit_price 1 \
  --argjson hard_cap 100000 \
  '{
    sale: $sale,
    sale_asset: $sale_asset,
    payment_asset: $payment_asset,
    treasury: $treasury,
    unit_price: $unit_price,
    hard_cap: $hard_cap
  }')"
sale_view_payload="$(jq -cn --arg sale "$sale_name" '{sale: $sale}')"
ensure_init_or_skip \
  "launchpad sale config" \
  "$launchpad_sale_factory_contract" \
  "sale_config" \
  "$sale_view_payload" \
  "$sale_expected_json" \
  "init_sale" \
  "$sale_init_payload"

referral_expected_json="$(jq -cn --arg reward_asset "$xor_id" --arg treasury "$vault_account" '[ $reward_asset, $treasury, 1, 10000, 0 ]')"
referral_init_payload="$(jq -cn \
  --arg reward_asset "$xor_id" \
  --arg treasury "$vault_account" \
  '{ reward_asset: $reward_asset, treasury: $treasury }')"
ensure_init_or_skip \
  "referral registry config" \
  "$referral_registry_contract" \
  "registry_config" \
  null \
  "$referral_expected_json" \
  "init_registry" \
  "$referral_init_payload"

farm_expected_json="$(jq -cn --arg stake_asset "$n3x_id" --arg reward_asset "$xor_id" --arg treasury "$vault_account" '[ $stake_asset, $reward_asset, $treasury, 10 ]')"
farm_init_payload="$(jq -cn \
  --arg stake_asset "$n3x_id" \
  --arg reward_asset "$xor_id" \
  --arg treasury "$vault_account" \
  --argjson reward_rate 10 \
  '{
    stake_asset: $stake_asset,
    reward_asset: $reward_asset,
    treasury: $treasury,
    reward_rate: $reward_rate
  }')"
ensure_init_or_skip \
  "farm config" \
  "$farms_farm_contract" \
  "farm_config" \
  null \
  "$farm_expected_json" \
  "init_farm" \
  "$farm_init_payload"

engine_expected_json="$(jq -cn --arg collateral_asset "$xor_id" --arg vault_account "$vault_account" '[ $collateral_asset, $vault_account, 100, 50000, 500, 1000 ]')"
engine_init_payload="$(jq -cn \
  --arg collateral_asset "$xor_id" \
  --arg vault_account "$vault_account" \
  --argjson funding_bps 100 \
  '{
    collateral_asset: $collateral_asset,
    vault_account: $vault_account,
    funding_bps: $funding_bps
  }')"
ensure_init_or_skip \
  "perps engine config" \
  "$perps_engine_contract" \
  "engine_config" \
  null \
  "$engine_expected_json" \
  "init_engine" \
  "$engine_init_payload"

series_expected_json="$(jq -cn --arg underlying_asset "$xor_id" --arg settlement_asset "$usdt_id" --arg treasury "$vault_account" '[ $underlying_asset, $settlement_asset, $treasury, 2, 1, 0, 1 ]')"
series_init_payload="$(jq -cn \
  --arg series "$series_name" \
  --arg underlying_asset "$xor_id" \
  --arg settlement_asset "$usdt_id" \
  --arg treasury "$vault_account" \
  --argjson strike_price 2 \
  --argjson premium 1 \
  '{
    series: $series,
    underlying_asset: $underlying_asset,
    settlement_asset: $settlement_asset,
    treasury: $treasury,
    strike_price: $strike_price,
    premium: $premium
  }')"
series_view_payload="$(jq -cn --arg series "$series_name" '{series: $series}')"
ensure_init_or_skip \
  "options series config" \
  "$options_series_manager_contract" \
  "series_config" \
  "$series_view_payload" \
  "$series_expected_json" \
  "init_series" \
  "$series_init_payload"

policy_expected_json="$(jq -cn --arg settlement_asset "$usdt_id" --arg vault_account "$vault_account" '[ $settlement_asset, $vault_account, 10, 8000, 5 ]')"
policy_init_payload="$(jq -cn \
  --arg policy "$policy_name" \
  --arg settlement_asset "$usdt_id" \
  --arg vault_account "$vault_account" \
  --argjson duration_slots 10 \
  --argjson payout_bps 8000 \
  --argjson premium 5 \
  '{
    policy: $policy,
    settlement_asset: $settlement_asset,
    vault_account: $vault_account,
    duration_slots: $duration_slots,
    payout_bps: $payout_bps,
    premium: $premium
  }')"
policy_view_payload="$(jq -cn --arg policy "$policy_name" '{policy: $policy}')"
ensure_init_or_skip \
  "cover policy config" \
  "$cover_policy_manager_contract" \
  "policy_config" \
  "$policy_view_payload" \
  "$policy_expected_json" \
  "init_policy" \
  "$policy_init_payload"

echo "post-deploy contract state initialized"
