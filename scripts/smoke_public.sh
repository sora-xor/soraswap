#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

public_env="${SORASWAP_PUBLIC_ENV:-testnet}"
case "$public_env" in
  testnet|production)
    ;;
  *)
    echo "smoke_public.sh only supports SORASWAP_PUBLIC_ENV=testnet|production; got $public_env" >&2
    exit 1
    ;;
esac

config="$(client_config_or_default "$public_env")"
ensure_client "$config"
ensure_authority "$config"
prepare_env_chain_state "$public_env" "$config"
ensure_public_signer_ready "$config" "$SORASWAP_AUTHORITY" readonly
ensure_deployment_records_current "$public_env" "$config"

n3x_hub_contract="$(deployed_contract_id_for_env "$public_env" n3x.n3x_hub)"
n3x_hub_dataspace="$(deployed_contract_dataspace_for_env "$public_env" n3x.n3x_hub)"
dlmm_pool_contract="$(deployed_contract_id_for_env "$public_env" dlmm.dlmm_pool)"
dlmm_pool_dataspace="$(deployed_contract_dataspace_for_env "$public_env" dlmm.dlmm_pool)"
dlmm_router_contract="$(deployed_contract_id_for_env "$public_env" dlmm.dlmm_router)"
dlmm_router_dataspace="$(deployed_contract_dataspace_for_env "$public_env" dlmm.dlmm_router)"
risk_vault_contract="$(deployed_contract_id_for_env "$public_env" risk.risk_vault)"
perps_engine_contract="$(deployed_contract_id_for_env "$public_env" perps.perps_engine)"
options_manager_contract="$(deployed_contract_id_for_env "$public_env" options.manager)"
options_factory_contract="$(deployed_contract_id_for_env "$public_env" options.factory)"
options_vault_contract="$(deployed_contract_id_for_env "$public_env" options.vault)"
options_shout_option_contract="$(deployed_contract_id_for_env "$public_env" options.shout_option)"
options_outperformance_option_contract="$(deployed_contract_id_for_env "$public_env" options.outperformance_option)"
cover_policy_manager_contract="$(deployed_contract_id_for_env "$public_env" cover.policy_manager)"
intents_settlement_router_contract="$(deployed_contract_id_for_env "$public_env" intents.settlement_router)"
vaults_manager_contract="$(deployed_contract_id_for_env "$public_env" vaults.manager)"
operators_registry_contract="$(deployed_contract_id_for_env "$public_env" operators.registry)"
margin_portfolio_margin_contract="$(deployed_contract_id_for_env "$public_env" margin.portfolio_margin)"
rwa_market_contract="$(deployed_contract_id_for_env "$public_env" rwa.market)"
dlmm_hooks_manager_contract="$(deployed_contract_id_for_env "$public_env" dlmm_hooks.hook_manager)"

report_dir="$(deployments_dir_for_env "$public_env")"
timestamp="$(env TZ=UTC date '+%Y%m%dT%H%M%SZ')"
latest_report="$report_dir/smoke.latest.json"
timestamped_report="$report_dir/smoke.${timestamp}.json"
mkdir -p "$report_dir"

contracts_json="$(deployment_records_json_for_env "$public_env")"

xor_id="$SORASWAP_XOR_ASSET_DEFINITION_ID"
if resolved_xor_id="$(asset_definition_id_for_alias "$config" "$SORASWAP_BASE_ASSET_ALIAS" 2>/dev/null)"; then
  xor_id="$resolved_xor_id"
else
  echo "$public_env smoke: base asset alias $SORASWAP_BASE_ASSET_ALIAS is not query-visible; using configured fallback $SORASWAP_XOR_ASSET_DEFINITION_ID" >&2
fi
if [[ "$xor_id" != "$SORASWAP_XOR_ASSET_DEFINITION_ID" ]]; then
  echo "unexpected XOR asset definition id for $SORASWAP_BASE_ASSET_ALIAS: $xor_id" >&2
  exit 1
fi

null_view_json='{"ok":true,"result":null}'

view_if_initialized() {
  local contract_id="$1"
  local entrypoint="$2"
  local payload_json="${3:-null}"

  if submit_contract_view "$config" "$contract_id" "$entrypoint" "$SORASWAP_SMOKE_GAS_LIMIT" "$payload_json" 2>/dev/null; then
    return 0
  fi

  printf '%s\n' "$null_view_json"
}

typeset -a contract_keys
typeset -a expected_contract_keys
expected_contract_keys=("${(@f)$(expected_contract_ids)}")
for contract_key in "${expected_contract_keys[@]}"; do
  contract_keys+=("$contract_key")
done

manifest_verified=0
for contract_key in "${contract_keys[@]}"; do
  record_path="$(deployment_record_path_for_env "$public_env" "$contract_key")"
  if [[ ! -f "$record_path" ]]; then
    echo "missing deployment record for $contract_key" >&2
    exit 1
  fi

  manifest_path="$report_dir/${contract_key}.manifest.json"
  expected_hash=""
  if [[ -f "$manifest_path" ]]; then
    expected_hash="$(manifest_code_hash_hex "$manifest_path")"
    manifest_verified=$(( manifest_verified + 1 ))
  fi

  if ! live_contract_deployment_from_record "$config" "$record_path" "$expected_hash" >/dev/null; then
    echo "deployment record could not be revalidated on current chain: $contract_key" >&2
    exit 1
  fi
done

usdt_id="$(asset_definition_id_for_alias "$config" usdt#soraswap.universal)"
pool_fee_pips="${SORASWAP_POOL_FEE_PIPS:-3000}"
pool_bin_step="${SORASWAP_POOL_BIN_STEP:-1}"
pool_impact_cap_bps="${SORASWAP_POOL_IMPACT_CAP_BPS:-10000}"
pool_min_reserve_base="${SORASWAP_POOL_MIN_RESERVE_BASE:-0}"
pool_min_reserve_quote="${SORASWAP_POOL_MIN_RESERVE_QUOTE:-0}"
pool_max_bins_per_swap="${SORASWAP_POOL_MAX_BINS_PER_SWAP:-8}"
pool_bin_liquidity_cap="${SORASWAP_POOL_BIN_LIQUIDITY_CAP:-0}"
pool_position_base="${SORASWAP_POOL_POSITION_BASE:-500}"
pool_position_quote="${SORASWAP_POOL_POSITION_QUOTE:-500}"
router_bin_quote_in="${SORASWAP_ROUTER_BIN_QUOTE_IN:-10}"
pool_quote_amount_in="${SORASWAP_POOL_SMOKE_SWAP_IN:-1500}"
soraswap_launch_vault_id="${SORASWAP_LAUNCH_VAULT_ID:-n3x_savings}"
soraswap_launch_operator_service="${SORASWAP_LAUNCH_OPERATOR_SERVICE:-solver}"
soraswap_launch_margin_market_id="${SORASWAP_LAUNCH_MARGIN_MARKET_ID:-portfolio}"
soraswap_launch_margin_account_key="${SORASWAP_LAUNCH_MARGIN_ACCOUNT_KEY:-bootstrap_account}"
soraswap_launch_rwa_market_id="${SORASWAP_LAUNCH_RWA_MARKET_ID:-tbill_2026}"
soraswap_launch_dlmm_hook_id="${SORASWAP_LAUNCH_DLMM_HOOK_ID:-dynamic_fee}"

n3x_quote_view_json="$(submit_contract_view "$config" "$n3x_hub_contract" quote_mint "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --argjson usdt_in 1 \
    --argjson usdc_in 2 \
    --argjson kusd_in 3 \
    '{
      usdt_in: $usdt_in,
      usdc_in: $usdc_in,
      kusd_in: $kusd_in
    }'
)")"

router_quote_view_json="$(submit_contract_view "$config" "$dlmm_router_contract" quote_bin "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --argjson reserve_base 1000 \
    --argjson reserve_quote 1000 \
    --argjson amount_in "$router_bin_quote_in" \
    --argjson fee_pips "$pool_fee_pips" \
    --argjson bin_id 0 \
    --argjson bin_step "$pool_bin_step" \
    --argjson input_is_base 1 \
    --argjson min_reserve_base "$pool_min_reserve_base" \
    --argjson min_reserve_quote "$pool_min_reserve_quote" \
    '{
      reserve_base: $reserve_base,
      reserve_quote: $reserve_quote,
      amount_in: $amount_in,
      fee_pips: $fee_pips
      ,
      bin_id: $bin_id,
      bin_step: $bin_step,
      input_is_base: $input_is_base,
      min_reserve_base: $min_reserve_base,
      min_reserve_quote: $min_reserve_quote
    }'
)")"

router_select_view_json="$(submit_contract_view "$config" "$dlmm_router_contract" select_best_quote "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --argjson direct_out 180 \
    --argjson via_base_out 200 \
    '{
      direct_out: $direct_out,
      via_base_out: $via_base_out
    }'
)")"

n3x_assert_view_json="$(submit_contract_view "$config" "$n3x_hub_contract" assert_initialized "$SORASWAP_SMOKE_GAS_LIMIT")"
n3x_mirror_view_json="$(submit_contract_view "$config" "$n3x_hub_contract" mirror_state "$SORASWAP_SMOKE_GAS_LIMIT")"
router_assert_view_json="$(submit_contract_view "$config" "$dlmm_router_contract" assert_router_config "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --argjson default_fee_pips "$pool_fee_pips" \
    '{ default_fee_pips: $default_fee_pips }'
)")"
router_mirror_view_json="$(submit_contract_view "$config" "$dlmm_router_contract" mirror_state "$SORASWAP_SMOKE_GAS_LIMIT")"
pool_mirror_view_json="$(submit_contract_view "$config" "$dlmm_pool_contract" mirror_state "$SORASWAP_SMOKE_GAS_LIMIT")"
risk_vault_bucket_1_view_json="$(view_if_initialized "$risk_vault_contract" bucket_state '{"bucket_id":1}')"
risk_vault_bucket_2_view_json="$(view_if_initialized "$risk_vault_contract" bucket_state '{"bucket_id":2}')"
risk_vault_bucket_3_view_json="$(view_if_initialized "$risk_vault_contract" bucket_state '{"bucket_id":3}')"
risk_vault_state_view_json="$(view_if_initialized "$risk_vault_contract" risk_state)"
perps_engine_config_view_json="$(view_if_initialized "$perps_engine_contract" engine_config)"
perps_market_state_view_json="$(view_if_initialized "$perps_engine_contract" market_state '{"market_id":1}')"
perps_risk_state_view_json="$(view_if_initialized "$perps_engine_contract" risk_state '{"market_id":1}')"
perps_automation_view_json="$(view_if_initialized "$perps_engine_contract" automation_state)"
options_manager_config_view_json="$(view_if_initialized "$options_manager_contract" manager_config)"
options_shout_template_view_json="$(view_if_initialized "$options_manager_contract" template_state '{"template_id":1}')"
options_outperformance_template_view_json="$(view_if_initialized "$options_manager_contract" template_state '{"template_id":2}')"
options_shout_series_view_json="$(view_if_initialized "$options_manager_contract" series_state '{"series_id":1}')"
options_outperformance_series_view_json="$(view_if_initialized "$options_manager_contract" series_state '{"series_id":2}')"
options_manager_automation_view_json="$(view_if_initialized "$options_manager_contract" automation_state)"
options_factory_config_view_json="$(view_if_initialized "$options_factory_contract" factory_config)"
options_factory_shout_series_view_json="$(view_if_initialized "$options_factory_contract" series_state '{"series_id":1}')"
options_factory_outperformance_series_view_json="$(view_if_initialized "$options_factory_contract" series_state '{"series_id":2}')"
options_factory_automation_view_json="$(view_if_initialized "$options_factory_contract" automation_state)"
options_vault_shout_view_json="$(view_if_initialized "$options_vault_contract" vault_state '{"series_id":1}')"
options_vault_outperformance_view_json="$(view_if_initialized "$options_vault_contract" vault_state '{"series_id":2}')"
options_shout_product_view_json="$(view_if_initialized "$options_shout_option_contract" series_state '{"series_id":1}')"
options_outperformance_product_view_json="$(view_if_initialized "$options_outperformance_option_contract" series_state '{"series_id":2}')"
cover_manager_config_view_json="$(view_if_initialized "$cover_policy_manager_contract" manager_config)"
cover_automation_view_json="$(view_if_initialized "$cover_policy_manager_contract" automation_state)"
launch_vault_state_view_json="$(view_if_initialized "$vaults_manager_contract" vault_state "$(jq -cn --arg vault_id "$soraswap_launch_vault_id" '{vault_id:$vault_id}')")"
launch_operator_state_view_json="$(view_if_initialized "$operators_registry_contract" operator_state "$(jq -cn --arg service "$soraswap_launch_operator_service" '{service:$service}')")"
launch_margin_market_view_json="$(view_if_initialized "$margin_portfolio_margin_contract" market_state "$(jq -cn --arg market_id "$soraswap_launch_margin_market_id" '{market_id:$market_id}')")"
launch_margin_account_view_json="$(view_if_initialized "$margin_portfolio_margin_contract" account_health "$(jq -cn --arg account_key "$soraswap_launch_margin_account_key" '{account_key:$account_key}')")"
launch_rwa_market_view_json="$(view_if_initialized "$rwa_market_contract" rwa_market_state "$(jq -cn --arg market_id "$soraswap_launch_rwa_market_id" '{market_id:$market_id}')")"
launch_dlmm_hook_policy_view_json="$(view_if_initialized "$dlmm_hooks_manager_contract" hook_policy "$(jq -cn --arg hook_id "$soraswap_launch_dlmm_hook_id" '{hook_id:$hook_id}')")"

decoded_state_ints='{}'
decoded_state_ints="$(jq -c '. + $add' \
  --argjson add "$(contract_view_result_object "$n3x_mirror_view_json" \
    soraswap_n3x_hub_initialized \
    soraswap_n3x_basket_usdt \
    soraswap_n3x_basket_usdc \
    soraswap_n3x_basket_kusd \
    soraswap_n3x_total_n3x \
    soraswap_n3x_mint_fee_bps \
    soraswap_n3x_redeem_fee_bps \
    soraswap_n3x_mint_fees_accrued \
    soraswap_n3x_redeem_fees_accrued \
    soraswap_n3x_target_usdt_bps \
    soraswap_n3x_target_usdc_bps \
    soraswap_n3x_target_kusd_bps)" \
  <<<"$decoded_state_ints")"
decoded_state_ints="$(jq -c '. + $add' \
  --argjson add "$(contract_view_result_object "$router_mirror_view_json" \
    soraswap_dlmm_router_initialized \
    soraswap_dlmm_router_default_fee_pips)" \
  <<<"$decoded_state_ints")"
decoded_state_ints="$(jq -c '. + $add' \
  --argjson add "$(contract_view_result_object "$pool_mirror_view_json" \
    soraswap_dlmm_pool_initialized \
    soraswap_dlmm_pool_active_bin \
    soraswap_dlmm_pool_fee_pips \
    soraswap_dlmm_pool_bin_step \
    soraswap_dlmm_pool_reserve_base \
    soraswap_dlmm_pool_reserve_quote \
    soraswap_dlmm_pool_active_liquidity \
    soraswap_dlmm_pool_active_share_supply \
    soraswap_dlmm_pool_impact_cap_bps \
    soraswap_dlmm_pool_min_reserve_base \
    soraswap_dlmm_pool_min_reserve_quote \
    soraswap_dlmm_pool_max_bins_per_swap \
    soraswap_dlmm_pool_bin_liquidity_cap)" \
  <<<"$decoded_state_ints")"

if [[ "${SORASWAP_ASSERT_BOOTSTRAP_STATE:-0}" == "1" ]]; then
  expected_active_bin="${SORASWAP_POOL_ACTIVE_BIN:-0}"
  expected_seed_base=$(( ${SORASWAP_POOL_SEED_BASE:-1000} + pool_position_base ))
  expected_seed_quote=$(( ${SORASWAP_POOL_SEED_QUOTE:-1000} + pool_position_quote ))
  expected_active_share_supply=$(( expected_seed_base + expected_seed_quote ))

  if ! jq -e \
    --argjson expected_fee_pips "$pool_fee_pips" \
    --argjson expected_bin_step "$pool_bin_step" \
    --argjson expected_active_bin "$expected_active_bin" \
    --argjson expected_seed_base "$expected_seed_base" \
    --argjson expected_seed_quote "$expected_seed_quote" \
    --argjson expected_active_liquidity "$(( expected_seed_base + expected_seed_quote ))" \
    --argjson expected_active_share_supply "$expected_active_share_supply" \
    --argjson expected_impact_cap_bps "$pool_impact_cap_bps" \
    --argjson expected_min_reserve_base "$pool_min_reserve_base" \
    --argjson expected_min_reserve_quote "$pool_min_reserve_quote" \
    --argjson expected_max_bins_per_swap "$pool_max_bins_per_swap" \
    --argjson expected_bin_liquidity_cap "$pool_bin_liquidity_cap" \
    '
      .soraswap_n3x_hub_initialized == 1 and
      .soraswap_n3x_basket_usdt == 0 and
      .soraswap_n3x_basket_usdc == 0 and
      .soraswap_n3x_basket_kusd == 0 and
      .soraswap_n3x_total_n3x == 0 and
      .soraswap_dlmm_pool_initialized == 1 and
      .soraswap_dlmm_pool_active_bin == $expected_active_bin and
      .soraswap_dlmm_pool_fee_pips == $expected_fee_pips and
      .soraswap_dlmm_pool_bin_step == $expected_bin_step and
      .soraswap_dlmm_pool_reserve_base == $expected_seed_base and
      .soraswap_dlmm_pool_reserve_quote == $expected_seed_quote and
      .soraswap_dlmm_pool_active_liquidity == $expected_active_liquidity and
      .soraswap_dlmm_pool_active_share_supply == $expected_active_share_supply and
      .soraswap_dlmm_pool_impact_cap_bps == $expected_impact_cap_bps and
      .soraswap_dlmm_pool_min_reserve_base == $expected_min_reserve_base and
      .soraswap_dlmm_pool_min_reserve_quote == $expected_min_reserve_quote and
      .soraswap_dlmm_pool_max_bins_per_swap == $expected_max_bins_per_swap and
      .soraswap_dlmm_pool_bin_liquidity_cap == $expected_bin_liquidity_cap and
      .soraswap_dlmm_router_initialized == 1 and
      .soraswap_dlmm_router_default_fee_pips == $expected_fee_pips
    ' <<<"$decoded_state_ints" >/dev/null; then
    echo "decoded contract state did not match expected bootstrap values" >&2
    jq '.' <<<"$decoded_state_ints" >&2
    exit 1
  fi
fi

report_json="$(jq -n \
  --arg generated_at "$timestamp" \
  --arg authority "$SORASWAP_AUTHORITY" \
  --arg client_config "$config" \
  --arg base_asset_alias "$SORASWAP_BASE_ASSET_ALIAS" \
  --arg xor_asset_id "$xor_id" \
  --arg usdt_asset_id "$usdt_id" \
  --argjson chain_fingerprint "${SORASWAP_CHAIN_FINGERPRINT_JSON:-null}" \
  --argjson manifest_verified "$manifest_verified" \
  --argjson contracts "$contracts_json" \
  --argjson n3x_quote_result "$(contract_view_result_json "$n3x_quote_view_json")" \
  --argjson router_quote_result "$(contract_view_result_json "$router_quote_view_json")" \
  --argjson router_select_result "$(contract_view_result_json "$router_select_view_json")" \
  --argjson n3x_assert_result "$(contract_view_result_json "$n3x_assert_view_json")" \
  --argjson router_assert_result "$(contract_view_result_json "$router_assert_view_json")" \
  --argjson n3x_mirror_result "$(contract_view_result_json "$n3x_mirror_view_json")" \
  --argjson router_mirror_result "$(contract_view_result_json "$router_mirror_view_json")" \
  --argjson pool_mirror_result "$(contract_view_result_json "$pool_mirror_view_json")" \
  --argjson risk_vault_bucket_1_result "$(contract_view_result_json "$risk_vault_bucket_1_view_json")" \
  --argjson risk_vault_bucket_2_result "$(contract_view_result_json "$risk_vault_bucket_2_view_json")" \
  --argjson risk_vault_bucket_3_result "$(contract_view_result_json "$risk_vault_bucket_3_view_json")" \
  --argjson risk_vault_state_result "$(contract_view_result_json "$risk_vault_state_view_json")" \
  --argjson perps_engine_config_result "$(contract_view_result_json "$perps_engine_config_view_json")" \
  --argjson perps_market_state_result "$(contract_view_result_json "$perps_market_state_view_json")" \
  --argjson perps_risk_state_result "$(contract_view_result_json "$perps_risk_state_view_json")" \
  --argjson perps_automation_result "$(contract_view_result_json "$perps_automation_view_json")" \
  --argjson options_manager_config_result "$(contract_view_result_json "$options_manager_config_view_json")" \
  --argjson options_shout_template_result "$(contract_view_result_json "$options_shout_template_view_json")" \
  --argjson options_outperformance_template_result "$(contract_view_result_json "$options_outperformance_template_view_json")" \
  --argjson options_shout_series_result "$(contract_view_result_json "$options_shout_series_view_json")" \
  --argjson options_outperformance_series_result "$(contract_view_result_json "$options_outperformance_series_view_json")" \
  --argjson options_manager_automation_result "$(contract_view_result_json "$options_manager_automation_view_json")" \
  --argjson options_factory_config_result "$(contract_view_result_json "$options_factory_config_view_json")" \
  --argjson options_factory_shout_series_result "$(contract_view_result_json "$options_factory_shout_series_view_json")" \
  --argjson options_factory_outperformance_series_result "$(contract_view_result_json "$options_factory_outperformance_series_view_json")" \
  --argjson options_factory_automation_result "$(contract_view_result_json "$options_factory_automation_view_json")" \
  --argjson options_vault_shout_result "$(contract_view_result_json "$options_vault_shout_view_json")" \
  --argjson options_vault_outperformance_result "$(contract_view_result_json "$options_vault_outperformance_view_json")" \
  --argjson options_shout_product_result "$(contract_view_result_json "$options_shout_product_view_json")" \
  --argjson options_outperformance_product_result "$(contract_view_result_json "$options_outperformance_product_view_json")" \
  --argjson cover_manager_config_result "$(contract_view_result_json "$cover_manager_config_view_json")" \
  --argjson cover_automation_result "$(contract_view_result_json "$cover_automation_view_json")" \
  --argjson launch_vault_state_result "$(contract_view_result_json "$launch_vault_state_view_json")" \
  --argjson launch_operator_state_result "$(contract_view_result_json "$launch_operator_state_view_json")" \
  --argjson launch_margin_market_result "$(contract_view_result_json "$launch_margin_market_view_json")" \
  --argjson launch_margin_account_result "$(contract_view_result_json "$launch_margin_account_view_json")" \
  --argjson launch_rwa_market_result "$(contract_view_result_json "$launch_rwa_market_view_json")" \
  --argjson launch_dlmm_hook_policy_result "$(contract_view_result_json "$launch_dlmm_hook_policy_view_json")" \
  --argjson decoded_state_ints "$decoded_state_ints" \
  '{
    generated_at: $generated_at,
    authority: $authority,
    client_config: $client_config,
    base_asset_alias: $base_asset_alias,
    xor_asset_id: $xor_asset_id,
    usdt_asset_id: $usdt_asset_id,
    chain_fingerprint: $chain_fingerprint,
    manifest_verified_count: $manifest_verified,
    contracts: $contracts,
    view_results: {
      n3x_quote_mint: $n3x_quote_result,
      dlmm_router_quote_bin: $router_quote_result,
      dlmm_router_select_best_quote: $router_select_result,
      n3x_assert_initialized: $n3x_assert_result,
      n3x_mirror_state: $n3x_mirror_result,
      dlmm_router_assert_config: $router_assert_result,
      dlmm_router_mirror_state: $router_mirror_result,
      dlmm_pool_mirror_state: $pool_mirror_result,
      risk_vault_bucket_1: $risk_vault_bucket_1_result,
      risk_vault_bucket_2: $risk_vault_bucket_2_result,
      risk_vault_bucket_3: $risk_vault_bucket_3_result,
      risk_vault_state: $risk_vault_state_result,
      perps_engine_config: $perps_engine_config_result,
      perps_market_state: $perps_market_state_result,
      perps_risk_state: $perps_risk_state_result,
      perps_automation_state: $perps_automation_result,
      options_manager_config: $options_manager_config_result,
      options_shout_template: $options_shout_template_result,
      options_outperformance_template: $options_outperformance_template_result,
      options_shout_series: $options_shout_series_result,
      options_outperformance_series: $options_outperformance_series_result,
      options_manager_automation: $options_manager_automation_result,
      options_factory_config: $options_factory_config_result,
      options_factory_shout_series: $options_factory_shout_series_result,
      options_factory_outperformance_series: $options_factory_outperformance_series_result,
      options_factory_automation: $options_factory_automation_result,
      options_vault_shout: $options_vault_shout_result,
      options_vault_outperformance: $options_vault_outperformance_result,
      options_shout_product: $options_shout_product_result,
      options_outperformance_product: $options_outperformance_product_result,
      cover_manager_config: $cover_manager_config_result,
      cover_automation_state: $cover_automation_result,
      launch_vault_state: $launch_vault_state_result,
      launch_operator_state: $launch_operator_state_result,
      launch_margin_market: $launch_margin_market_result,
      launch_margin_account: $launch_margin_account_result,
      launch_rwa_market: $launch_rwa_market_result,
      launch_dlmm_hook_policy: $launch_dlmm_hook_policy_result
    },
    decoded_state_ints: $decoded_state_ints
  }')"

printf '%s\n' "$report_json" > "$latest_report"
printf '%s\n' "$report_json" > "$timestamped_report"

echo "$public_env smoke report: $timestamped_report"
