#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

export SORASWAP_BLOCK_WAIT_ATTEMPTS="${SORASWAP_SMOKE_BLOCK_WAIT_ATTEMPTS:-900}"
export SORASWAP_BLOCK_WAIT_TICK="${SORASWAP_SMOKE_BLOCK_WAIT_TICK:-1}"

config="$(client_config_or_default local)"
ensure_client "$config"
ensure_authority "$config"

n3x_hub_contract="$(deployed_contract_id_for_env local n3x.n3x_hub)"
n3x_hub_dataspace="$(deployed_contract_dataspace_for_env local n3x.n3x_hub)"
dlmm_pool_contract="$(deployed_contract_id_for_env local dlmm.dlmm_pool)"
dlmm_pool_dataspace="$(deployed_contract_dataspace_for_env local dlmm.dlmm_pool)"
dlmm_router_contract="$(deployed_contract_id_for_env local dlmm.dlmm_router)"
dlmm_router_dataspace="$(deployed_contract_dataspace_for_env local dlmm.dlmm_router)"
batch_epoch_auction_contract="$(deployed_contract_id_for_env local batch_amm.epoch_auction)"
launchpad_liquidity_executor_contract="$(deployed_contract_id_for_env local launchpad.liquidity_executor)"
launchpad_sale_factory_contract="$(deployed_contract_id_for_env local launchpad.sale_factory)"
referral_registry_contract="$(deployed_contract_id_for_env local referral.registry)"
farms_farm_contract="$(deployed_contract_id_for_env local farms.farm)"
risk_vault_contract="$(deployed_contract_id_for_env local risk.risk_vault)"
perps_engine_contract="$(deployed_contract_id_for_env local perps.perps_engine)"
options_manager_contract="$(deployed_contract_id_for_env local options.manager)"
options_factory_contract="$(deployed_contract_id_for_env local options.factory)"
options_vault_contract="$(deployed_contract_id_for_env local options.vault)"
options_shout_option_contract="$(deployed_contract_id_for_env local options.shout_option)"
options_outperformance_option_contract="$(deployed_contract_id_for_env local options.outperformance_option)"
cover_policy_manager_contract="$(deployed_contract_id_for_env local cover.policy_manager)"
automation_job_queue_contract="$(deployed_contract_id_for_env local automation.job_queue)"
intents_settlement_router_contract="$(deployed_contract_id_for_env local intents.settlement_router)"
vaults_manager_contract="$(deployed_contract_id_for_env local vaults.manager)"
operators_registry_contract="$(deployed_contract_id_for_env local operators.registry)"
margin_portfolio_margin_contract="$(deployed_contract_id_for_env local margin.portfolio_margin)"
rwa_market_contract="$(deployed_contract_id_for_env local rwa.market)"
dlmm_hooks_manager_contract="$(deployed_contract_id_for_env local dlmm_hooks.hook_manager)"
escrow_conditional_escrow_contract="$(deployed_contract_id_for_env local escrow.conditional_escrow)"
risk_vault_contract_subject="$(contract_subject_account_for_literal "$config" "$risk_vault_contract")"
perps_engine_contract_subject="$(contract_subject_account_for_literal "$config" "$perps_engine_contract")"
risk_vault_contract_blob_hex="0x$(printf '%s' "$risk_vault_contract" | xxd -p -c 256 | tr -d '\n')"

if ! base_asset_definition_json="$(iroha_cli_json --config "$config" ledger asset definition get --alias "$SORASWAP_BASE_ASSET_ALIAS" 2>/dev/null)"; then
  echo "local smoke: base asset alias $SORASWAP_BASE_ASSET_ALIAS is not query-visible; using configured fallback $SORASWAP_XOR_ASSET_DEFINITION_ID" >&2
  base_asset_definition_json="$(iroha_cli_json --config "$config" ledger asset definition get --id "$SORASWAP_XOR_ASSET_DEFINITION_ID")"
fi
jq -e --arg id "$SORASWAP_XOR_ASSET_DEFINITION_ID" '.id == $id and ((.name // "") | ascii_downcase) == "xor"' \
  >/dev/null <<<"$base_asset_definition_json"

vault_account="$(treasury_account_for_mode local)"
xor_id="$(asset_definition_id_for_alias "$config" "$SORASWAP_BASE_ASSET_ALIAS")"
usdt_id="$(asset_definition_id_for_alias "$config" usdt#soraswap.universal)"
usdc_id="$(asset_definition_id_for_alias "$config" usdc#soraswap.universal)"
kusd_id="$(asset_definition_id_for_alias "$config" kusd#soraswap.universal)"
n3x_id="$(asset_definition_id_for_alias "$config" n3x#soraswap.universal)"
launchpad_sale_asset_id="${SORASWAP_LAUNCHPAD_SALE_ASSET_ID:-$usdt_id}"
n3x_usdt_in="${SORASWAP_N3X_SMOKE_USDT_IN:-100}"
n3x_usdc_in="${SORASWAP_N3X_SMOKE_USDC_IN:-200}"
n3x_kusd_in="${SORASWAP_N3X_SMOKE_KUSD_IN:-300}"
n3x_target_usdt_bps="${SORASWAP_N3X_TARGET_USDT_BPS:-3334}"
n3x_target_usdc_bps="${SORASWAP_N3X_TARGET_USDC_BPS:-3333}"
n3x_target_kusd_bps="${SORASWAP_N3X_TARGET_KUSD_BPS:-3333}"
n3x_mint_fee_bps="${SORASWAP_N3X_MINT_FEE_BPS:-100}"
n3x_redeem_fee_bps="${SORASWAP_N3X_REDEEM_FEE_BPS:-100}"
smoke_run_id="${SORASWAP_SMOKE_RUN_ID:-$(date +%s)_$$}"
sale_name="${SORASWAP_SALE_NAME:-genesis_sale_${smoke_run_id}}"
launchpad_payment_amount="${SORASWAP_LAUNCHPAD_SMOKE_PAYMENT_AMOUNT:-10}"
launchpad_allocation_id="${SORASWAP_LAUNCHPAD_SMOKE_ALLOCATION_ID:-smoke_launchpad_allocation_${smoke_run_id}}"
launchpad_claim_inventory_amount="${SORASWAP_LAUNCHPAD_CLAIM_INVENTORY_AMOUNT:-$launchpad_payment_amount}"
launchpad_claim_slot="${SORASWAP_LAUNCHPAD_CLAIM_SLOT:-0}"
launchpad_seed_position_id="${SORASWAP_LAUNCHPAD_SEED_POSITION_ID:-smoke_launchpad_seed_lp_${smoke_run_id}}"
launchpad_seed_payment_amount="${SORASWAP_LAUNCHPAD_SEED_PAYMENT_AMOUNT:-4}"
launchpad_seed_sale_amount="${SORASWAP_LAUNCHPAD_SEED_SALE_AMOUNT:-6}"
launchpad_seed_bin_id="${SORASWAP_LAUNCHPAD_SEED_BIN_ID:-0}"
refund_sale_name="${SORASWAP_REFUND_SALE_NAME:-refund_sale_${smoke_run_id}}"
refund_allocation_id="${SORASWAP_REFUND_ALLOCATION_ID:-smoke_refund_allocation_${smoke_run_id}}"
refund_payment_amount="${SORASWAP_REFUND_PAYMENT_AMOUNT:-10}"
refund_soft_cap="${SORASWAP_REFUND_SOFT_CAP:-20}"
series_name="${SORASWAP_SERIES_NAME:-genesis_series}"
policy_name="${SORASWAP_POLICY_NAME:-genesis_policy}"
referral_member="${SORASWAP_REFERRAL_SMOKE_MEMBER:-smoke_referrer_${smoke_run_id}}"
referral_parent_member="${SORASWAP_REFERRAL_SMOKE_PARENT_MEMBER:-smoke_referral_parent_${smoke_run_id}}"
referral_claim_threshold="${SORASWAP_REFERRAL_SMOKE_CLAIM_THRESHOLD:-3}"
referral_accrual_amount="${SORASWAP_REFERRAL_SMOKE_ACCRUAL:-7}"
referral_direct_share_bps="${SORASWAP_REFERRAL_SMOKE_DIRECT_SHARE_BPS:-7000}"
referral_parent_share_bps="${SORASWAP_REFERRAL_SMOKE_PARENT_SHARE_BPS:-3000}"
farm_position="${SORASWAP_FARM_SMOKE_POSITION:-smoke_farm_position_${smoke_run_id}}"
farm_reward_fund_amount="${SORASWAP_FARM_SMOKE_REWARD_FUND:-100}"
farm_stake_amount="${SORASWAP_FARM_SMOKE_STAKE_AMOUNT:-3}"
farm_unstake_amount="${SORASWAP_FARM_SMOKE_UNSTAKE_AMOUNT:-1}"
farm_claim_slot="${SORASWAP_FARM_SMOKE_CLAIM_SLOT:-4}"
farm_unstake_slot="${SORASWAP_FARM_SMOKE_UNSTAKE_SLOT:-6}"
perps_position="${SORASWAP_PERPS_SMOKE_POSITION:-smoke_perps_position}"
perps_size="${SORASWAP_PERPS_SMOKE_SIZE:-1000}"
perps_initial_collateral="${SORASWAP_PERPS_SMOKE_COLLATERAL:-250}"
perps_add_collateral="${SORASWAP_PERPS_SMOKE_ADD_COLLATERAL:-50}"
perps_remove_collateral="${SORASWAP_PERPS_SMOKE_REMOVE_COLLATERAL:-40}"
perps_requested_leverage_bps="${SORASWAP_PERPS_SMOKE_REQUESTED_LEVERAGE_BPS:-40000}"
perps_liquidation_requested_leverage_bps="${SORASWAP_PERPS_SMOKE_LIQUIDATION_REQUESTED_LEVERAGE_BPS:-50000}"
perps_funding_bps="${SORASWAP_PERPS_SMOKE_FUNDING_BPS:-100}"
perps_max_leverage_bps="${SORASWAP_PERPS_SMOKE_MAX_LEVERAGE_BPS:-50000}"
perps_maintenance_margin_bps="${SORASWAP_PERPS_SMOKE_MAINTENANCE_MARGIN_BPS:-500}"
perps_liquidation_fee_bps="${SORASWAP_PERPS_SMOKE_LIQUIDATION_FEE_BPS:-1000}"
perps_entry_price_bps="${SORASWAP_PERPS_SMOKE_ENTRY_PRICE_BPS:-10000}"
perps_funding_mark_price_bps="${SORASWAP_PERPS_SMOKE_FUNDING_MARK_PRICE_BPS:-11000}"
perps_funding_index_price_bps="${SORASWAP_PERPS_SMOKE_FUNDING_INDEX_PRICE_BPS:-10000}"
perps_exit_mark_price_bps="${SORASWAP_PERPS_SMOKE_EXIT_MARK_PRICE_BPS:-10200}"
perps_liquidation_collateral="${SORASWAP_PERPS_SMOKE_LIQUIDATION_COLLATERAL:-200}"
perps_liquidation_stress_mark_price_bps="${SORASWAP_PERPS_SMOKE_LIQUIDATION_STRESS_MARK_PRICE_BPS:-8490}"
perps_liquidation_healthy_mark_price_bps="${SORASWAP_PERPS_SMOKE_LIQUIDATION_HEALTHY_MARK_PRICE_BPS:-10050}"
perps_liquidation_scan_limit="${SORASWAP_PERPS_SMOKE_LIQUIDATION_SCAN_LIMIT:-4}"
options_shout_notional="${SORASWAP_OPTIONS_SHOUT_SMOKE_NOTIONAL:-100}"
options_shout_premium_paid="${SORASWAP_OPTIONS_SHOUT_SMOKE_PREMIUM_PAID:-5}"
options_shout_collateral_locked="${SORASWAP_OPTIONS_SHOUT_SMOKE_COLLATERAL_LOCKED:-100}"
options_shout_record_mark_bps="${SORASWAP_OPTIONS_SHOUT_SMOKE_RECORD_MARK_BPS:-10800}"
options_shout_exercise_mark_bps="${SORASWAP_OPTIONS_SHOUT_SMOKE_EXERCISE_MARK_BPS:-10600}"
options_outperformance_notional="${SORASWAP_OPTIONS_OUTPERFORMANCE_SMOKE_NOTIONAL:-50}"
options_outperformance_premium_paid="${SORASWAP_OPTIONS_OUTPERFORMANCE_SMOKE_PREMIUM_PAID:-3}"
options_outperformance_collateral_locked="${SORASWAP_OPTIONS_OUTPERFORMANCE_SMOKE_COLLATERAL_LOCKED:-50}"
options_outperformance_final_mark_bps="${SORASWAP_OPTIONS_OUTPERFORMANCE_FINAL_MARK_BPS:-1200}"
options_outperformance_final_quote_mark_bps="${SORASWAP_OPTIONS_OUTPERFORMANCE_FINAL_QUOTE_MARK_BPS:-200}"
cover_notional="${SORASWAP_COVER_SMOKE_NOTIONAL:-10}"
cover_payout_amount="${SORASWAP_COVER_SMOKE_PAYOUT_AMOUNT:-7}"
cover_premium_paid="${SORASWAP_COVER_SMOKE_PREMIUM_PAID:-10}"
cover_lower_bound="${SORASWAP_COVER_SMOKE_LOWER_BOUND:-90}"
cover_upper_bound="${SORASWAP_COVER_SMOKE_UPPER_BOUND:-110}"
cover_trigger_price="${SORASWAP_COVER_SMOKE_TRIGGER_PRICE:-120}"
cover_monitoring_window_slots="${SORASWAP_COVER_SMOKE_WINDOW_SLOTS:-2}"
cover_policy_required_observations="${SORASWAP_COVER_SMOKE_POLICY_REQUIRED_OBSERVATIONS:-3}"
risk_bucket_1_bootstrap_deposit="${SORASWAP_RISK_BUCKET_1_BOOTSTRAP_DEPOSIT:-200}"
risk_bucket_2_bootstrap_deposit="${SORASWAP_RISK_BUCKET_2_BOOTSTRAP_DEPOSIT:-0}"
risk_bucket_3_bootstrap_deposit="${SORASWAP_RISK_BUCKET_3_BOOTSTRAP_DEPOSIT:-0}"
risk_bucket_1_automation_expected_json='[1,101,4,6,0,0,0]'
risk_bucket_2_automation_expected_json='[1,102,5,8,0,0,0]'
risk_bucket_3_automation_expected_json='[1,103,3,10,0,0,0]'
perps_open_interest_cap="${SORASWAP_PERPS_MARKET_OPEN_INTEREST_CAP:-80000}"
perps_funding_interval_slots="${SORASWAP_PERPS_MARKET_FUNDING_INTERVAL_SLOTS:-4}"
perps_oracle_stale_slots="${SORASWAP_PERPS_MARKET_ORACLE_STALE_SLOTS:-4}"
perps_backlog_limit="${SORASWAP_PERPS_MARKET_BACKLOG_LIMIT:-6}"
perps_utilisation_clamp_bps="${SORASWAP_PERPS_MARKET_UTILISATION_CLAMP_BPS:-9000}"
perps_liquidation_stress_limit="${SORASWAP_PERPS_MARKET_LIQUIDATION_STRESS_LIMIT:-4}"
options_shout_tenor_slots="${SORASWAP_OPTIONS_SHOUT_TENOR_SLOTS:-40}"
options_outperformance_tenor_slots="${SORASWAP_OPTIONS_OUTPERFORMANCE_TENOR_SLOTS:-40}"
options_shout_strike_bps="${SORASWAP_OPTIONS_SHOUT_STRIKE_BPS:-10200}"
options_outperformance_strike_bps="${SORASWAP_OPTIONS_OUTPERFORMANCE_STRIKE_BPS:-10000}"
options_collateral_multiplier_bps="${SORASWAP_OPTIONS_COLLATERAL_MULTIPLIER_BPS:-10000}"
options_shout_base_premium_bps="${SORASWAP_OPTIONS_SHOUT_BASE_PREMIUM_BPS:-450}"
options_outperformance_base_premium_bps="${SORASWAP_OPTIONS_OUTPERFORMANCE_BASE_PREMIUM_BPS:-600}"
options_shout_expiry_slot="${SORASWAP_OPTIONS_SHOUT_EXPIRY_SLOT:-40}"
options_outperformance_expiry_slot="${SORASWAP_OPTIONS_OUTPERFORMANCE_EXPIRY_SLOT:-40}"
options_shout_max_notional="${SORASWAP_OPTIONS_SHOUT_MAX_NOTIONAL:-30000}"
options_outperformance_max_notional="${SORASWAP_OPTIONS_OUTPERFORMANCE_MAX_NOTIONAL:-20000}"
options_factory_bump_activate_bps="${SORASWAP_OPTIONS_GUARD_BUMP_ACTIVATE_BPS:-8000}"
options_factory_bump_deactivate_bps="${SORASWAP_OPTIONS_GUARD_BUMP_DEACTIVATE_BPS:-6000}"
options_factory_pause_threshold_bps="${SORASWAP_OPTIONS_GUARD_PAUSE_THRESHOLD_BPS:-9500}"
options_factory_bump_percent_bps="${SORASWAP_OPTIONS_GUARD_BUMP_PERCENT_BPS:-1500}"
cover_required_observations="${SORASWAP_COVER_REQUIRED_OBSERVATIONS:-3}"
cover_policy_required_observations="${SORASWAP_COVER_SMOKE_POLICY_REQUIRED_OBSERVATIONS:-$cover_required_observations}"
cover_oracle_stale_slots="${SORASWAP_COVER_ORACLE_STALE_SLOTS:-4}"
job_name="${SORASWAP_AUTOMATION_SMOKE_JOB:-smoke_job_${smoke_run_id}}"
automation_executor="${SORASWAP_AUTOMATION_SMOKE_EXECUTOR:-$vault_account}"
automation_next_slot="${SORASWAP_AUTOMATION_SMOKE_NEXT_SLOT:-5}"
automation_resume_slot="${SORASWAP_AUTOMATION_SMOKE_RESUME_SLOT:-6}"
automation_retry_delay_slots="${SORASWAP_AUTOMATION_SMOKE_RETRY_DELAY_SLOTS:-3}"
automation_max_retries="${SORASWAP_AUTOMATION_SMOKE_MAX_RETRIES:-2}"
automation_cron_interval_slots="${SORASWAP_AUTOMATION_SMOKE_CRON_INTERVAL_SLOTS:-4}"
intent_smoke_id="${SORASWAP_INTENT_SMOKE_ID:-smoke_intent_${smoke_run_id}}"
intent_amount_in="${SORASWAP_INTENT_SMOKE_AMOUNT_IN:-10}"
intent_min_out="${SORASWAP_INTENT_SMOKE_MIN_OUT:-9}"
intent_amount_out="${SORASWAP_INTENT_SMOKE_AMOUNT_OUT:-10}"
intent_solver_fee_bps="${SORASWAP_INTENT_SMOKE_SOLVER_FEE_BPS:-30}"
intent_deadline_slot="${SORASWAP_INTENT_SMOKE_DEADLINE_SLOT:-}"
intent_deadline_offset_slots="${SORASWAP_INTENT_SMOKE_DEADLINE_OFFSET_SLOTS:-100}"
intent_nonce="${SORASWAP_INTENT_SMOKE_NONCE:-1}"
vault_smoke_id="${SORASWAP_VAULT_SMOKE_ID:-smoke_n3x_savings_${smoke_run_id}}"
vault_position_id="${SORASWAP_VAULT_SMOKE_POSITION_ID:-smoke_vault_position_${smoke_run_id}}"
vault_redeem_request_id="${SORASWAP_VAULT_SMOKE_REDEEM_REQUEST_ID:-smoke_vault_redeem_${smoke_run_id}}"
vault_strategy_code="${SORASWAP_VAULT_SMOKE_STRATEGY_CODE:-1}"
vault_async_redeem="${SORASWAP_VAULT_SMOKE_ASYNC_REDEEM:-1}"
vault_deposit_amount="${SORASWAP_VAULT_SMOKE_DEPOSIT_AMOUNT:-25}"
vault_redeem_shares="${SORASWAP_VAULT_SMOKE_REDEEM_SHARES:-10}"
vault_claim_slot="${SORASWAP_VAULT_SMOKE_CLAIM_SLOT:-}"
vault_claim_delay_slots="${SORASWAP_VAULT_SMOKE_CLAIM_DELAY_SLOTS:-1}"
operator_service="${SORASWAP_OPERATOR_SMOKE_SERVICE:-smoke_solver_${smoke_run_id}}"
operator_unregistered_service="${SORASWAP_OPERATOR_SMOKE_UNREGISTERED_SERVICE:-smoke_unbonded_operator_${smoke_run_id}}"
operator_min_bond="${SORASWAP_OPERATOR_SMOKE_MIN_BOND:-100}"
operator_bond_amount="${SORASWAP_OPERATOR_SMOKE_BOND_AMOUNT:-125}"
operator_heartbeat_slot="${SORASWAP_OPERATOR_SMOKE_HEARTBEAT_SLOT:-11}"
operator_health_bps="${SORASWAP_OPERATOR_SMOKE_HEALTH_BPS:-8000}"
operator_fees_accrued="${SORASWAP_OPERATOR_SMOKE_FEES_ACCRUED:-7}"
margin_market_id="${SORASWAP_MARGIN_SMOKE_MARKET_ID:-smoke_portfolio_${smoke_run_id}}"
margin_account_key="${SORASWAP_MARGIN_SMOKE_ACCOUNT_KEY:-smoke_account_${smoke_run_id}}"
margin_risk_weight_bps="${SORASWAP_MARGIN_SMOKE_RISK_WEIGHT_BPS:-8000}"
margin_liquidation_threshold_bps="${SORASWAP_MARGIN_SMOKE_LIQUIDATION_THRESHOLD_BPS:-1000}"
margin_collateral_amount="${SORASWAP_MARGIN_SMOKE_COLLATERAL:-100}"
margin_exposure_amount="${SORASWAP_MARGIN_SMOKE_EXPOSURE:-2000}"
margin_rejected_withdraw_amount="${SORASWAP_MARGIN_SMOKE_REJECT_WITHDRAW:-1}"
rwa_market_id="${SORASWAP_RWA_SMOKE_MARKET_ID:-smoke_tbill_2026_${smoke_run_id}}"
rwa_redemption_id="${SORASWAP_RWA_SMOKE_REDEMPTION_ID:-smoke_rwa_redeem_${smoke_run_id}}"
rwa_initial_nav_per_share="${SORASWAP_RWA_SMOKE_INITIAL_NAV:-100}"
rwa_report_nav_per_share="${SORASWAP_RWA_SMOKE_REPORT_NAV:-105}"
rwa_initial_total_shares="${SORASWAP_RWA_SMOKE_INITIAL_SHARES:-1000}"
rwa_report_total_shares="${SORASWAP_RWA_SMOKE_REPORT_SHARES:-900}"
rwa_redeem_shares="${SORASWAP_RWA_SMOKE_REDEEM_SHARES:-100}"
dlmm_hook_id="${SORASWAP_DLMM_HOOK_SMOKE_ID:-smoke_dynamic_fee_${smoke_run_id}}"
dlmm_disabled_hook_id="${SORASWAP_DLMM_HOOK_DISABLED_SMOKE_ID:-smoke_disabled_hook_${smoke_run_id}}"
dlmm_limit_order_id="${SORASWAP_DLMM_HOOK_LIMIT_ORDER_ID:-smoke_limit_order_${smoke_run_id}}"
dlmm_twamm_order_id="${SORASWAP_DLMM_HOOK_TWAMM_ORDER_ID:-smoke_twamm_order_${smoke_run_id}}"
dlmm_hook_phase="${SORASWAP_DLMM_HOOK_SMOKE_PHASE:-1}"
dlmm_hook_max_fee_pips="${SORASWAP_DLMM_HOOK_SMOKE_MAX_FEE_PIPS:-5000}"
dlmm_hook_amount_in="${SORASWAP_DLMM_HOOK_SMOKE_AMOUNT_IN:-20}"
dlmm_hook_min_out="${SORASWAP_DLMM_HOOK_SMOKE_MIN_OUT:-18}"
dlmm_hook_amount_out="${SORASWAP_DLMM_HOOK_SMOKE_AMOUNT_OUT:-19}"
dlmm_hook_interval_slots="${SORASWAP_DLMM_HOOK_SMOKE_INTERVAL_SLOTS:-4}"
conditional_escrow_id="${SORASWAP_CONDITIONAL_ESCROW_SMOKE_ID:-smoke_conditional_escrow_${smoke_run_id}}"
conditional_escrow_amount="${SORASWAP_CONDITIONAL_ESCROW_SMOKE_AMOUNT:-5}"
conditional_escrow_condition_code="${SORASWAP_CONDITIONAL_ESCROW_SMOKE_CONDITION_CODE:-7}"
conditional_escrow_expiry_offset_slots="${SORASWAP_CONDITIONAL_ESCROW_SMOKE_EXPIRY_OFFSET_SLOTS:-100}"
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
pool_position_remove_shares="${SORASWAP_POOL_POSITION_REMOVE_SHARES:-500}"
pool_impact_cap_bps="${SORASWAP_POOL_IMPACT_CAP_BPS:-10000}"
pool_min_reserve_base="${SORASWAP_POOL_MIN_RESERVE_BASE:-0}"
pool_min_reserve_quote="${SORASWAP_POOL_MIN_RESERVE_QUOTE:-0}"
pool_max_bins_per_swap="${SORASWAP_POOL_MAX_BINS_PER_SWAP:-8}"
pool_bin_liquidity_cap="${SORASWAP_POOL_BIN_LIQUIDITY_CAP:-0}"
router_bin_quote_in="${SORASWAP_ROUTER_BIN_QUOTE_IN:-10}"
swap_amount_in="${SORASWAP_POOL_SMOKE_SWAP_IN:-1500}"
smoke_scope="${SORASWAP_SMOKE_SCOPE:-full}"

dlmm_price_ppm() {
  local bin_id="$1"
  local bin_step="$2"
  local scale=1000000

  if (( bin_id >= 0 )); then
    echo $(( scale + bin_id * bin_step ))
    return 0
  fi

  local abs_bin=$(( -bin_id ))
  echo $(( (scale * scale) / (scale + abs_bin * bin_step) ))
}

dlmm_gross_from_net() {
  local net_amount="$1"
  local fee_pips="$2"
  local scale=1000000

  if (( net_amount <= 0 )); then
    echo 0
    return 0
  fi

  local gross=$(( (net_amount * scale + (scale - fee_pips) - 1) / (scale - fee_pips) ))
  local effective=$(( gross * (scale - fee_pips) / scale ))
  if (( effective < net_amount )); then
    gross=$(( gross + 1 ))
  fi
  echo "$gross"
}

assert_view_result_equals() {
  local label="$1"
  local view_json="$2"
  local expected_json="$3"
  local actual_json

  actual_json="$(contract_view_result_json "$view_json")"
  if json_equals "$actual_json" "$expected_json"; then
    return 0
  fi

  echo "local smoke view mismatch for $label" >&2
  jq -n \
    --arg label "$label" \
    --argjson expected "$expected_json" \
    --argjson actual "$actual_json" \
    '{ label: $label, expected: $expected, actual: $actual }' >&2
  exit 1
}

next_cover_policy_id() {
  local candidate=1
  local max_scan="${1:-256}"
  local view_json result_json

  while (( candidate <= max_scan )); do
    view_json="$(submit_contract_view "$config" "$cover_policy_manager_contract" policy_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
      jq -cn \
        --argjson policy_id "$candidate" \
        '{ policy_id: $policy_id }'
    )")"
    result_json="$(contract_view_result_json "$view_json")"
    if jq -e '.[0] == 0' <<<"$result_json" >/dev/null; then
      echo "$candidate"
      return 0
    fi
    candidate=$(( candidate + 1 ))
  done

  echo "local smoke could not discover next cover policy id within scan limit $max_scan" >&2
  return 1
}

print_smoke_tx() {
  local label="$1"
  local tx_hash="${2:-}"

  if [[ -n "$tx_hash" ]]; then
    echo "local smoke committed $label tx: $tx_hash"
    return 0
  fi

  echo "local smoke committed $label tx: skipped"
}

expect_contract_call_rejection() {
  local label="$1"
  local contract_id="$2"
  local entrypoint="$3"
  local payload_json="${4:-null}"
  local output call_status

  set +e
  output="$(call_contract_and_wait "$config" "$contract_id" "$entrypoint" "$payload_json" 2>&1)"
  call_status=$?
  set -e

  if (( call_status == 0 )); then
    echo "local smoke expected $label to reject, but it committed tx $output" >&2
    exit 1
  fi

  printf '%s\n' "$output"
}

before_n3x="$(asset_value_for_account "$config" n3x#soraswap.universal "$SORASWAP_AUTHORITY")"
n3x_config_tx_hash=""
n3x_quote_view_json="$(submit_contract_view "$config" "$n3x_hub_contract" quote_mint "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --argjson usdt_in "$n3x_usdt_in" \
    --argjson usdc_in "$n3x_usdc_in" \
    --argjson kusd_in "$n3x_kusd_in" \
    '{
      usdt_in: $usdt_in,
      usdc_in: $usdc_in,
      kusd_in: $kusd_in
    }'
)")"

n3x_gross_in=$(( n3x_usdt_in + n3x_usdc_in + n3x_kusd_in ))
n3x_expected_mint_fee_usdt=$(( n3x_usdt_in * n3x_mint_fee_bps / 10000 ))
n3x_expected_mint_fee_usdc=$(( n3x_usdc_in * n3x_mint_fee_bps / 10000 ))
n3x_expected_mint_fee_kusd=$(( n3x_kusd_in * n3x_mint_fee_bps / 10000 ))
n3x_expected_mint_fee=$(( n3x_expected_mint_fee_usdt + n3x_expected_mint_fee_usdc + n3x_expected_mint_fee_kusd ))
n3x_expected_minted=$(( n3x_gross_in - n3x_expected_mint_fee ))
if (( referral_direct_share_bps + referral_parent_share_bps != 10000 )); then
  echo "invalid referral share split: direct + parent must equal 10000 bps" >&2
  exit 1
fi
referral_expected_member_share=$(( referral_accrual_amount * referral_direct_share_bps / 10000 ))
referral_expected_parent_share=$(( referral_accrual_amount - referral_expected_member_share ))
if (( referral_expected_member_share <= 0 || referral_expected_parent_share <= 0 )); then
  echo "invalid referral routed accrual split for smoke: both child and parent shares must be positive" >&2
  exit 1
fi
if (( referral_expected_member_share < referral_claim_threshold || referral_expected_parent_share < referral_claim_threshold )); then
  echo "invalid referral routed accrual split for smoke: both child and parent shares must satisfy the claim threshold" >&2
  exit 1
fi
if (( automation_cron_interval_slots <= 0 )); then
  echo "invalid automation cron interval for smoke: must be positive" >&2
  exit 1
fi
if (( farm_claim_slot <= 0 || farm_unstake_slot < farm_claim_slot )); then
  echo "invalid farm slot configuration for smoke: claim slot must be positive and unstake slot must not precede claim" >&2
  exit 1
fi
if (( perps_entry_price_bps <= 0 || perps_funding_mark_price_bps <= 0 || perps_funding_index_price_bps <= 0 || perps_exit_mark_price_bps <= 0 || perps_liquidation_stress_mark_price_bps <= 0 || perps_liquidation_healthy_mark_price_bps <= 0 )); then
  echo "invalid perps price configuration for smoke: all prices must be positive" >&2
  exit 1
fi
if (( perps_funding_mark_price_bps <= perps_funding_index_price_bps )); then
  echo "invalid perps funding configuration for smoke: funding mark price must exceed index price" >&2
  exit 1
fi
if (( perps_initial_collateral + perps_add_collateral <= perps_remove_collateral )); then
  echo "invalid perps collateral configuration for smoke: removal must leave positive margin" >&2
  exit 1
fi
if (( perps_requested_leverage_bps <= 0 || perps_requested_leverage_bps > perps_max_leverage_bps || perps_liquidation_requested_leverage_bps <= 0 || perps_liquidation_requested_leverage_bps > perps_max_leverage_bps )); then
  echo "invalid perps leverage configuration for smoke: requested leverage must be positive and within market max leverage" >&2
  exit 1
fi
if (( perps_liquidation_collateral <= 0 || perps_liquidation_scan_limit <= 0 || perps_liquidation_scan_limit > 32 )); then
  echo "invalid perps liquidation configuration for smoke: collateral must be positive and scan limit must be 1..32" >&2
  exit 1
fi
if (( options_shout_notional <= 0 || options_outperformance_notional <= 0 || options_shout_collateral_locked <= 0 || options_outperformance_collateral_locked <= 0 )); then
  echo "invalid options sizing for smoke: notionals and collateral must be positive" >&2
  exit 1
fi
if (( options_shout_premium_paid < (options_shout_notional * options_shout_base_premium_bps / 10000) || options_outperformance_premium_paid < (options_outperformance_notional * options_outperformance_base_premium_bps / 10000) )); then
  echo "invalid options premium configuration for smoke: premium must satisfy the current series floor" >&2
  exit 1
fi
if (( cover_payout_amount <= 0 || cover_premium_paid <= 0 || cover_lower_bound >= cover_upper_bound || cover_monitoring_window_slots <= 0 )); then
  echo "invalid cover configuration for smoke: bounds, payout, premium, and monitoring window must be valid" >&2
  exit 1
fi
if (( cover_policy_required_observations != 3 )); then
  echo "invalid cover observation configuration for smoke: local shell smoke currently expects exactly 3 required observations" >&2
  exit 1
fi
if [[ -n "$intent_deadline_slot" && "$intent_deadline_slot" != <-> ]]; then
  echo "invalid intent deadline slot for smoke: $intent_deadline_slot" >&2
  exit 1
fi
if [[ "$intent_deadline_offset_slots" != <-> || "$intent_deadline_offset_slots" -le 0 ]]; then
  echo "invalid intent deadline offset for smoke: $intent_deadline_offset_slots" >&2
  exit 1
fi
if (( intent_amount_in <= 0 || intent_min_out <= 0 || intent_amount_out < intent_min_out || intent_solver_fee_bps < 0 || intent_solver_fee_bps > 10000 )); then
  echo "invalid intent smoke configuration" >&2
  exit 1
fi
if [[ -n "$vault_claim_slot" && "$vault_claim_slot" != <-> ]]; then
  echo "invalid vault claim slot for smoke: $vault_claim_slot" >&2
  exit 1
fi
if [[ "$vault_claim_delay_slots" != <-> ]]; then
  echo "invalid vault claim delay for smoke: $vault_claim_delay_slots" >&2
  exit 1
fi
if (( vault_deposit_amount <= 0 || vault_redeem_shares <= 0 || vault_redeem_shares > vault_deposit_amount || vault_async_redeem < 0 || vault_async_redeem > 1 )); then
  echo "invalid vault smoke configuration" >&2
  exit 1
fi
if (( operator_min_bond <= 0 || operator_bond_amount <= 0 || operator_health_bps < 0 || operator_health_bps > 10000 || operator_fees_accrued < 0 )); then
  echo "invalid operator smoke configuration" >&2
  exit 1
fi
if (( margin_risk_weight_bps < 0 || margin_risk_weight_bps > 10000 || margin_liquidation_threshold_bps < 0 || margin_liquidation_threshold_bps > 10000 || margin_collateral_amount <= 0 || margin_exposure_amount <= 0 || margin_rejected_withdraw_amount <= 0 )); then
  echo "invalid margin smoke configuration" >&2
  exit 1
fi
if (( (margin_collateral_amount * 10000 / margin_exposure_amount) >= margin_liquidation_threshold_bps )); then
  echo "invalid margin smoke configuration: exposure must make the account liquidatable" >&2
  exit 1
fi
if (( rwa_initial_nav_per_share <= 0 || rwa_report_nav_per_share <= 0 || rwa_initial_total_shares <= 0 || rwa_report_total_shares < 0 || rwa_redeem_shares <= 0 )); then
  echo "invalid RWA smoke configuration" >&2
  exit 1
fi
if (( dlmm_hook_max_fee_pips < 0 || dlmm_hook_amount_in <= 0 || dlmm_hook_min_out <= 0 || dlmm_hook_amount_out < dlmm_hook_min_out || dlmm_hook_interval_slots <= 0 )); then
  echo "invalid DLMM hook smoke configuration" >&2
  exit 1
fi

mint_tx_hash="$(call_contract_and_wait "$config" "$n3x_hub_contract" deposit_and_mint "$(
  jq -cn \
    --argjson usdt_in "$n3x_usdt_in" \
    --argjson usdc_in "$n3x_usdc_in" \
    --argjson kusd_in "$n3x_kusd_in" \
    '{
      usdt_in: $usdt_in,
      usdc_in: $usdc_in,
      kusd_in: $kusd_in
    }'
)")"
expected_after_mint=$(( before_n3x + n3x_expected_minted ))
after_mint_n3x="$(wait_for_asset_balance "$config" n3x#soraswap.universal "$SORASWAP_AUTHORITY" "$expected_after_mint" 15 1 || true)"
if (( after_mint_n3x != expected_after_mint )); then
  echo "unexpected n3x balance after mint: expected $expected_after_mint, got $after_mint_n3x" >&2
  exit 1
fi

redeem_quote_view_json="$(submit_contract_view "$config" "$n3x_hub_contract" quote_redeem "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --argjson n3x_amount "$n3x_expected_minted" \
    '{ n3x_amount: $n3x_amount }'
)")"
burn_tx_hash="$(call_contract_and_wait "$config" "$n3x_hub_contract" burn_and_redeem "$(
  jq -cn \
    --argjson n3x_amount "$n3x_expected_minted" \
    '{
      n3x_amount: $n3x_amount
    }'
)")"
after_burn_n3x="$(wait_for_asset_balance "$config" n3x#soraswap.universal "$SORASWAP_AUTHORITY" "$before_n3x" 15 1 || true)"
if (( after_burn_n3x != before_n3x )); then
  echo "unexpected n3x balance after burn: expected $before_n3x, got $after_burn_n3x" >&2
  exit 1
fi

router_bin_quote_view_json="$(submit_contract_view "$config" "$dlmm_router_contract" quote_bin "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --argjson reserve_base "$pool_seed_base" \
    --argjson reserve_quote "$pool_seed_quote" \
    --argjson amount_in "$router_bin_quote_in" \
    --argjson fee_pips "$pool_fee_pips" \
    --argjson bin_id "$pool_active_bin" \
    --argjson bin_step "$pool_bin_step" \
    --argjson input_is_base 1 \
    --argjson min_reserve_base "$pool_min_reserve_base" \
    --argjson min_reserve_quote "$pool_min_reserve_quote" \
    '{
      reserve_base: $reserve_base,
      reserve_quote: $reserve_quote,
      amount_in: $amount_in,
      fee_pips: $fee_pips,
      bin_id: $bin_id,
      bin_step: $bin_step,
      input_is_base: $input_is_base,
      min_reserve_base: $min_reserve_base,
      min_reserve_quote: $min_reserve_quote
    }'
)")"
dlmm_swap_tx_hash="$(call_contract_and_wait "$config" "$dlmm_router_contract" route_swap "$(
  jq -cn \
    --argjson amount_in "$swap_amount_in" \
    --argjson input_is_base 1 \
    --argjson min_out 1 \
    '{
      amount_in: $amount_in,
      input_is_base: $input_is_base,
      min_out: $min_out
    }'
)")"
dlmm_collect_position_fees_tx_hash=""
dlmm_position_after_swap_view_json="$(submit_contract_view "$config" "$dlmm_pool_contract" mirror_position "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --arg position_id "$pool_position_id" \
    '{
      position_id: $position_id
    }'
)")"
dlmm_pending_position_fees_view_json="$(submit_contract_view "$config" "$dlmm_pool_contract" quote_position_fees "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --arg position_id "$pool_position_id" \
    '{
      position_id: $position_id
    }'
)")"
dlmm_pending_position_fees_result="$(contract_view_result_json "$dlmm_pending_position_fees_view_json")"
dlmm_pending_position_fee_base="$(jq -r '.[0] // 0' <<<"$dlmm_pending_position_fees_result")"
dlmm_pending_position_fee_quote="$(jq -r '.[1] // 0' <<<"$dlmm_pending_position_fees_result")"
if (( dlmm_pending_position_fee_base > 0 || dlmm_pending_position_fee_quote > 0 )); then
  dlmm_collect_position_fees_tx_hash="$(call_contract_and_wait "$config" "$dlmm_pool_contract" collect_position_fees "$(
    jq -cn \
      --arg position_id "$pool_position_id" \
      '{
        position_id: $position_id
      }'
  )")"
else
  echo "local smoke skip: dlmm position has no pending fees; skipping collect_position_fees"
fi
dlmm_remove_position_tx_hash="$(call_contract_and_wait "$config" "$dlmm_pool_contract" remove_position_liquidity "$(
  jq -cn \
    --arg position_id "$pool_position_id" \
    --argjson shares "$pool_position_remove_shares" \
    '{
      position_id: $position_id,
      shares: $shares
    }'
)")"

intent_current_slot="$(soraswap_current_block_height "$config")"
if [[ -z "$intent_current_slot" || "$intent_current_slot" == "null" || "$intent_current_slot" != <-> ]]; then
  intent_current_slot=0
fi
if [[ -z "$intent_deadline_slot" ]]; then
  intent_deadline_slot=$(( intent_current_slot + intent_deadline_offset_slots ))
fi
if (( intent_deadline_slot <= intent_current_slot )); then
  echo "invalid intent deadline for smoke: deadline $intent_deadline_slot is not after current block $intent_current_slot" >&2
  exit 1
fi

intent_open_payload_json="$(
  jq -cn \
    --arg intent_id "$intent_smoke_id" \
    --arg input_asset "$xor_id" \
    --arg output_asset "$usdt_id" \
    --argjson amount_in "$intent_amount_in" \
    --argjson min_out "$intent_min_out" \
    --argjson solver_fee_bps "$intent_solver_fee_bps" \
    --argjson deadline_slot "$intent_deadline_slot" \
    --argjson nonce "$intent_nonce" \
    '{
      intent_id: $intent_id,
      input_asset: $input_asset,
      output_asset: $output_asset,
      amount_in: $amount_in,
      min_out: $min_out,
      solver_fee_bps: $solver_fee_bps,
      deadline_slot: $deadline_slot,
      nonce: $nonce
    }'
)"
intent_open_tx_hash="$(call_contract_and_wait "$config" "$intents_settlement_router_contract" open_intent "$intent_open_payload_json")"
intent_replay_rejection="$(expect_contract_call_rejection "intent replay" "$intents_settlement_router_contract" open_intent "$intent_open_payload_json")"
intent_fill_tx_hash="$(call_contract_and_wait "$config" "$intents_settlement_router_contract" fill_intent "$(
  jq -cn \
    --arg intent_id "$intent_smoke_id" \
    --argjson amount_out "$intent_amount_out" \
    '{
      intent_id: $intent_id,
      amount_out: $amount_out
    }'
)")"
intent_state_view_json="$(submit_contract_view "$config" "$intents_settlement_router_contract" intent_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --arg intent_id "$intent_smoke_id" '{ intent_id: $intent_id }'
)")"

vault_register_tx_hash="$(call_contract_and_wait "$config" "$vaults_manager_contract" register_vault "$(
  jq -cn \
    --arg vault_id "$vault_smoke_id" \
    --arg underlying_asset "$n3x_id" \
    --arg share_asset "$n3x_id" \
    --argjson strategy_code "$vault_strategy_code" \
    --argjson async_redeem "$vault_async_redeem" \
    '{
      vault_id: $vault_id,
      underlying_asset: $underlying_asset,
      share_asset: $share_asset,
      strategy_code: $strategy_code,
      async_redeem: $async_redeem
    }'
)")"
vault_deposit_tx_hash="$(call_contract_and_wait "$config" "$vaults_manager_contract" deposit "$(
  jq -cn \
    --arg vault_id "$vault_smoke_id" \
    --arg position_id "$vault_position_id" \
    --argjson amount "$vault_deposit_amount" \
    '{
      vault_id: $vault_id,
      position_id: $position_id,
      amount: $amount
    }'
)")"
if [[ -z "$vault_claim_slot" ]]; then
  vault_current_slot="$(soraswap_current_block_height "$config")"
  if [[ -z "$vault_current_slot" || "$vault_current_slot" == "null" || "$vault_current_slot" != <-> ]]; then
    vault_current_slot=0
  fi
  vault_claim_slot=$(( vault_current_slot + vault_claim_delay_slots ))
fi
vault_request_redeem_tx_hash="$(call_contract_and_wait "$config" "$vaults_manager_contract" request_redeem "$(
  jq -cn \
    --arg vault_id "$vault_smoke_id" \
    --arg request_id "$vault_redeem_request_id" \
    --arg position_id "$vault_position_id" \
    --argjson shares "$vault_redeem_shares" \
    --argjson claim_slot "$vault_claim_slot" \
    '{
      vault_id: $vault_id,
      request_id: $request_id,
      position_id: $position_id,
      shares: $shares,
      claim_slot: $claim_slot
    }'
)")"
soraswap_wait_for_block_height_at_least "$config" "$vault_claim_slot" "vault redeem claim"
vault_claim_redeem_tx_hash="$(call_contract_and_wait "$config" "$vaults_manager_contract" claim_redeem "$(
  jq -cn \
    --arg request_id "$vault_redeem_request_id" \
    '{
      request_id: $request_id
    }'
)")"
vault_state_view_json="$(submit_contract_view "$config" "$vaults_manager_contract" vault_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --arg vault_id "$vault_smoke_id" '{ vault_id: $vault_id }'
)")"
vault_position_view_json="$(submit_contract_view "$config" "$vaults_manager_contract" position_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --arg position_id "$vault_position_id" '{ position_id: $position_id }'
)")"

operator_unbonded_rejection="$(expect_contract_call_rejection "unregistered operator heartbeat" "$operators_registry_contract" heartbeat "$(
  jq -cn \
    --arg service "$operator_unregistered_service" \
    --argjson slot "$operator_heartbeat_slot" \
    --argjson health_bps "$operator_health_bps" \
    --argjson fees_accrued 0 \
    '{
      service: $service,
      slot: $slot,
      health_bps: $health_bps,
      fees_accrued: $fees_accrued
    }'
)")"
operator_register_tx_hash="$(call_contract_and_wait "$config" "$operators_registry_contract" register_operator "$(
  jq -cn \
    --arg service "$operator_service" \
    --arg bond_asset "$xor_id" \
    --argjson min_bond "$operator_min_bond" \
    '{
      service: $service,
      bond_asset: $bond_asset,
      min_bond: $min_bond
    }'
)")"
operator_bond_tx_hash="$(call_contract_and_wait "$config" "$operators_registry_contract" bond "$(
  jq -cn \
    --arg service "$operator_service" \
    --argjson amount "$operator_bond_amount" \
    '{
      service: $service,
      amount: $amount
    }'
)")"
operator_heartbeat_tx_hash="$(call_contract_and_wait "$config" "$operators_registry_contract" heartbeat "$(
  jq -cn \
    --arg service "$operator_service" \
    --argjson slot "$operator_heartbeat_slot" \
    --argjson health_bps "$operator_health_bps" \
    --argjson fees_accrued "$operator_fees_accrued" \
    '{
      service: $service,
      slot: $slot,
      health_bps: $health_bps,
      fees_accrued: $fees_accrued
    }'
)")"
operator_claim_fees_tx_hash="$(call_contract_and_wait "$config" "$operators_registry_contract" claim_fees "$(
  jq -cn --arg service "$operator_service" '{ service: $service }'
)")"
operator_state_view_json="$(submit_contract_view "$config" "$operators_registry_contract" operator_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --arg service "$operator_service" '{ service: $service }'
)")"

margin_register_market_tx_hash="$(call_contract_and_wait "$config" "$margin_portfolio_margin_contract" register_market "$(
  jq -cn \
    --arg market_id "$margin_market_id" \
    --argjson risk_weight_bps "$margin_risk_weight_bps" \
    --argjson liquidation_threshold_bps "$margin_liquidation_threshold_bps" \
    '{
      market_id: $market_id,
      risk_weight_bps: $risk_weight_bps,
      liquidation_threshold_bps: $liquidation_threshold_bps
    }'
)")"
margin_deposit_collateral_tx_hash="$(call_contract_and_wait "$config" "$margin_portfolio_margin_contract" deposit_collateral "$(
  jq -cn \
    --arg account_key "$margin_account_key" \
    --argjson amount "$margin_collateral_amount" \
    '{
      account_key: $account_key,
      amount: $amount
    }'
)")"
margin_lock_exposure_tx_hash="$(call_contract_and_wait "$config" "$margin_portfolio_margin_contract" lock_exposure "$(
  jq -cn \
    --arg market_id "$margin_market_id" \
    --arg account_key "$margin_account_key" \
    --argjson exposure_delta "$margin_exposure_amount" \
    '{
      market_id: $market_id,
      account_key: $account_key,
      exposure_delta: $exposure_delta
    }'
)")"
margin_unhealthy_withdraw_rejection="$(expect_contract_call_rejection "unhealthy margin withdraw" "$margin_portfolio_margin_contract" withdraw_collateral "$(
  jq -cn \
    --arg account_key "$margin_account_key" \
    --argjson amount "$margin_rejected_withdraw_amount" \
    '{
      account_key: $account_key,
      amount: $amount
    }'
)")"
margin_liquidate_account_tx_hash="$(call_contract_and_wait "$config" "$margin_portfolio_margin_contract" liquidate_account "$(
  jq -cn --arg account_key "$margin_account_key" '{ account_key: $account_key }'
)")"
margin_account_health_view_json="$(submit_contract_view "$config" "$margin_portfolio_margin_contract" account_health "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --arg account_key "$margin_account_key" '{ account_key: $account_key }'
)")"

rwa_issue_lot_payload_json="$(
  jq -cn \
    --arg market_id "$rwa_market_id" \
    --arg share_asset "$n3x_id" \
    --arg nav_asset "$usdt_id" \
    --argjson initial_nav_per_share "$rwa_initial_nav_per_share" \
    --argjson total_shares "$rwa_initial_total_shares" \
    '{
      market_id: $market_id,
      share_asset: $share_asset,
      nav_asset: $nav_asset,
      initial_nav_per_share: $initial_nav_per_share,
      total_shares: $total_shares
    }'
)"
rwa_issue_lot_tx_hash="$(call_contract_and_wait "$config" "$rwa_market_contract" issue_lot "$rwa_issue_lot_payload_json")"
rwa_duplicate_issue_rejection="$(expect_contract_call_rejection "duplicate RWA lot" "$rwa_market_contract" issue_lot "$rwa_issue_lot_payload_json")"
rwa_bind_share_asset_tx_hash="$(call_contract_and_wait "$config" "$rwa_market_contract" bind_share_asset "$(
  jq -cn \
    --arg market_id "$rwa_market_id" \
    --arg share_asset "$n3x_id" \
    '{
      market_id: $market_id,
      share_asset: $share_asset
    }'
)")"
rwa_report_nav_tx_hash="$(call_contract_and_wait "$config" "$rwa_market_contract" report_nav "$(
  jq -cn \
    --arg market_id "$rwa_market_id" \
    --argjson nav_per_share "$rwa_report_nav_per_share" \
    --argjson total_shares "$rwa_report_total_shares" \
    --argjson status 1 \
    '{
      market_id: $market_id,
      nav_per_share: $nav_per_share,
      total_shares: $total_shares,
      status: $status
    }'
)")"
rwa_request_redemption_tx_hash="$(call_contract_and_wait "$config" "$rwa_market_contract" request_redemption "$(
  jq -cn \
    --arg market_id "$rwa_market_id" \
    --arg redemption_id "$rwa_redemption_id" \
    --argjson shares "$rwa_redeem_shares" \
    '{
      market_id: $market_id,
      redemption_id: $redemption_id,
      shares: $shares
    }'
)")"
rwa_settle_redemption_tx_hash="$(call_contract_and_wait "$config" "$rwa_market_contract" settle_redemption "$(
  jq -cn --arg redemption_id "$rwa_redemption_id" '{ redemption_id: $redemption_id }'
)")"
rwa_market_state_view_json="$(submit_contract_view "$config" "$rwa_market_contract" rwa_market_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --arg market_id "$rwa_market_id" '{ market_id: $market_id }'
)")"

dlmm_disabled_hook_rejection="$(expect_contract_call_rejection "disabled DLMM hook" "$dlmm_hooks_manager_contract" place_limit_order "$(
  jq -cn \
    --arg order_id "${dlmm_limit_order_id}_disabled" \
    --arg hook_id "$dlmm_disabled_hook_id" \
    --argjson amount_in "$dlmm_hook_amount_in" \
    --argjson min_out "$dlmm_hook_min_out" \
    '{
      order_id: $order_id,
      hook_id: $hook_id,
      amount_in: $amount_in,
      min_out: $min_out
    }'
)")"
dlmm_configure_hook_tx_hash="$(call_contract_and_wait "$config" "$dlmm_hooks_manager_contract" configure_hook_policy "$(
  jq -cn \
    --arg hook_id "$dlmm_hook_id" \
    --argjson phase "$dlmm_hook_phase" \
    --argjson max_fee_pips "$dlmm_hook_max_fee_pips" \
    --argjson enabled 1 \
    '{
      hook_id: $hook_id,
      phase: $phase,
      max_fee_pips: $max_fee_pips,
      enabled: $enabled
    }'
)")"
dlmm_place_limit_order_tx_hash="$(call_contract_and_wait "$config" "$dlmm_hooks_manager_contract" place_limit_order "$(
  jq -cn \
    --arg order_id "$dlmm_limit_order_id" \
    --arg hook_id "$dlmm_hook_id" \
    --argjson amount_in "$dlmm_hook_amount_in" \
    --argjson min_out "$dlmm_hook_min_out" \
    '{
      order_id: $order_id,
      hook_id: $hook_id,
      amount_in: $amount_in,
      min_out: $min_out
    }'
)")"
dlmm_schedule_twamm_tx_hash="$(call_contract_and_wait "$config" "$dlmm_hooks_manager_contract" schedule_twamm "$(
  jq -cn \
    --arg order_id "$dlmm_twamm_order_id" \
    --arg hook_id "$dlmm_hook_id" \
    --argjson amount_in "$dlmm_hook_amount_in" \
    --argjson min_out "$dlmm_hook_min_out" \
    --argjson interval_slots "$dlmm_hook_interval_slots" \
    '{
      order_id: $order_id,
      hook_id: $hook_id,
      amount_in: $amount_in,
      min_out: $min_out,
      interval_slots: $interval_slots
    }'
)")"
dlmm_record_execution_tx_hash="$(call_contract_and_wait "$config" "$dlmm_hooks_manager_contract" record_execution "$(
  jq -cn \
    --arg order_id "$dlmm_limit_order_id" \
    --argjson amount_in "$dlmm_hook_amount_in" \
    --argjson amount_out "$dlmm_hook_amount_out" \
    '{
      order_id: $order_id,
      amount_in: $amount_in,
      amount_out: $amount_out
    }'
)")"
dlmm_hook_quote_view_json="$(submit_contract_view "$config" "$dlmm_hooks_manager_contract" quote_hooked_swap "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --arg order_id "$dlmm_limit_order_id" '{ order_id: $order_id }'
)")"

launchpad_tx_hash=""
launchpad_config_vesting_tx_hash=""
launchpad_close_tx_hash=""
launchpad_claim_inventory_tx_hash=""
launchpad_claim_tx_hash=""
launchpad_seed_inventory_tx_hash=""
launchpad_register_seed_tx_hash=""
launchpad_seed_liquidity_tx_hash=""
launchpad_finalize_activation_tx_hash=""
launchpad_mirror_view_json='{"ok":true,"result":null}'
launchpad_mirror_accounting_view_json='{"ok":true,"result":null}'
launchpad_activation_view_json='{"ok":true,"result":null}'
refund_sale_init_tx_hash=""
refund_sale_config_tx_hash=""
refund_sale_contribute_tx_hash=""
refund_sale_close_tx_hash=""
refund_sale_refund_tx_hash=""
refund_allocation_mirror_view_json='{"ok":true,"result":null}'
referral_config_tx_hash=""
referral_tiers_tx_hash=""
referral_parent_bind_tx_hash=""
referral_bind_tx_hash=""
referral_accrue_tx_hash=""
referral_claim_tx_hash=""
referral_parent_claim_tx_hash=""
referral_mirror_view_json='{"ok":true,"result":null}'
farm_config_tx_hash=""
farm_fund_tx_hash=""
farm_stake_tx_hash=""
farm_sync_claim_tx_hash=""
farm_claim_tx_hash=""
farm_sync_unstake_tx_hash=""
farm_unstake_tx_hash=""
farm_mirror_view_json='{"ok":true,"result":null}'
perps_open_tx_hash=""
perps_funding_tx_hash=""
perps_add_margin_tx_hash=""
perps_remove_margin_tx_hash=""
perps_close_tx_hash=""
perps_liquidation_open_tx_hash=""
perps_liquidation_queue_tx_hash=""
perps_liquidation_recover_tx_hash=""
perps_liquidation_requeue_tx_hash=""
perps_liquidation_execute_tx_hash=""
options_shout_buy_tx_hash=""
options_shout_record_tx_hash=""
options_shout_exercise_tx_hash=""
options_outperformance_buy_tx_hash=""
options_outperformance_settle_tx_hash=""
options_outperformance_exercise_tx_hash=""
cover_register_tx_hash=""
cover_stale_reset_tx_hash=""
cover_trigger_1_tx_hash=""
cover_trigger_2_tx_hash=""
cover_trigger_3_tx_hash=""
cover_trigger_4_tx_hash=""
cover_claim_tx_hash=""
risk_bucket_1_view_json='{"ok":true,"result":null}'
risk_bucket_2_view_json='{"ok":true,"result":null}'
risk_bucket_3_view_json='{"ok":true,"result":null}'
risk_vault_state_view_json='{"ok":true,"result":null}'
risk_bucket_1_liability_view_json='{"ok":true,"result":null}'
risk_bucket_1_liquidation_liability_view_json='{"ok":true,"result":null}'
risk_bucket_2_shout_liability_view_json='{"ok":true,"result":null}'
risk_bucket_2_outperformance_liability_view_json='{"ok":true,"result":null}'
risk_bucket_3_liability_view_json='{"ok":true,"result":null}'
risk_bucket_1_automation_view_json='{"ok":true,"result":null}'
risk_bucket_2_automation_view_json='{"ok":true,"result":null}'
risk_bucket_3_automation_view_json='{"ok":true,"result":null}'
perps_engine_config_view_json='{"ok":true,"result":null}'
perps_market_state_view_json='{"ok":true,"result":null}'
perps_market_risk_view_json='{"ok":true,"result":null}'
perps_automation_view_json='{"ok":true,"result":null}'
perps_position_state_view_json='{"ok":true,"result":null}'
perps_recovery_position_state_view_json='{"ok":true,"result":null}'
perps_recovery_position_liquidation_view_json='{"ok":true,"result":null}'
perps_liquidation_position_state_view_json='{"ok":true,"result":null}'
perps_liquidation_position_liquidation_view_json='{"ok":true,"result":null}'
perps_liquidation_state_view_json='{"ok":true,"result":null}'
options_manager_config_view_json='{"ok":true,"result":null}'
options_shout_template_view_json='{"ok":true,"result":null}'
options_outperformance_template_view_json='{"ok":true,"result":null}'
options_shout_series_view_json='{"ok":true,"result":null}'
options_outperformance_series_view_json='{"ok":true,"result":null}'
options_manager_automation_view_json='{"ok":true,"result":null}'
options_factory_config_view_json='{"ok":true,"result":null}'
options_factory_shout_series_view_json='{"ok":true,"result":null}'
options_factory_outperformance_series_view_json='{"ok":true,"result":null}'
options_factory_automation_view_json='{"ok":true,"result":null}'
options_factory_shout_position_view_json='{"ok":true,"result":null}'
options_factory_outperformance_position_view_json='{"ok":true,"result":null}'
options_vault_shout_state_view_json='{"ok":true,"result":null}'
options_vault_outperformance_state_view_json='{"ok":true,"result":null}'
options_vault_shout_position_view_json='{"ok":true,"result":null}'
options_vault_outperformance_position_view_json='{"ok":true,"result":null}'
options_shout_product_view_json='{"ok":true,"result":null}'
options_outperformance_product_view_json='{"ok":true,"result":null}'
options_shout_product_position_view_json='{"ok":true,"result":null}'
options_outperformance_product_position_view_json='{"ok":true,"result":null}'
cover_manager_config_view_json='{"ok":true,"result":null}'
cover_automation_view_json='{"ok":true,"result":null}'
cover_policy_view_json='{"ok":true,"result":null}'
trigger_registration_evidence_json='{"registered_triggers":[],"registered_trigger_ids":[],"active_trigger_ids":[],"expected_trigger_ids":[],"expected_trigger_details":[],"missing_expected_trigger_ids":[]}'
epoch_auction_native_close_evidence_json='{"ok":false}'
epoch_auction_state_view_json='{"ok":true,"result":null}'
dlmm_range_governor_view_json='{"ok":true,"result":null}'
twamm_trigger_state_view_json='{"ok":true,"result":null}'
options_manager_lifecycle_view_json='{"ok":true,"result":null}'
options_factory_lifecycle_view_json='{"ok":true,"result":null}'
cover_lifecycle_view_json='{"ok":true,"result":null}'
launchpad_lifecycle_view_json='{"ok":true,"result":null}'
vault_lifecycle_view_json='{"ok":true,"result":null}'
perps_lifecycle_view_json='{"ok":true,"result":null}'
conditional_escrow_open_tx_hash=""
conditional_escrow_execute_tx_hash=""
conditional_escrow_state_view_json='{"ok":true,"result":null}'
job_enqueue_tx_hash=""
job_config_tx_hash=""
job_assign_executor_tx_hash=""
job_cron_tx_hash=""
job_dispatch_tx_hash=""
job_pause_tx_hash=""
job_resume_tx_hash=""
job_retry_tx_hash=""
job_retry_dispatch_tx_hash=""
job_complete_tx_hash=""
job_mirror_view_json='{"ok":true,"result":null}'

if [[ "$smoke_scope" != "foundation" ]]; then
perps_position_id="$(submit_contract_view "$config" "$perps_engine_contract" engine_config "$SORASWAP_SMOKE_GAS_LIMIT" | jq -er '.result[4]')"
perps_liquidation_position_id=$(( perps_position_id + 1 ))
options_factory_next_position_id="$(submit_contract_view "$config" "$options_factory_contract" factory_config "$SORASWAP_SMOKE_GAS_LIMIT" | jq -er '.result[2]')"
options_shout_position_id="$options_factory_next_position_id"
options_outperformance_position_id=$(( options_shout_position_id + 1 ))
cover_policy_id="$(next_cover_policy_id)"
launchpad_config_vesting_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" init_sale "$(
  jq -cn \
    --arg sale "$sale_name" \
    --arg sale_asset "$launchpad_sale_asset_id" \
    --arg payment_asset "$xor_id" \
    --arg treasury "$vault_account" \
    --argjson unit_price 1 \
    --argjson soft_cap 1 \
    --argjson hard_cap 100000 \
    --argjson claim_start_slot 0 \
    --argjson claim_end_slot 0 \
    '{
      sale: $sale,
      sale_asset: $sale_asset,
      payment_asset: $payment_asset,
      treasury: $treasury,
      unit_price: $unit_price,
      soft_cap: $soft_cap,
      hard_cap: $hard_cap,
      claim_start_slot: $claim_start_slot,
      claim_end_slot: $claim_end_slot
    }'
  )")"
launchpad_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" contribute_recorded "$(
  jq -cn \
    --arg sale "$sale_name" \
    --arg allocation "$launchpad_allocation_id" \
    --argjson payment_amount "$launchpad_payment_amount" \
    '{
      sale: $sale,
      allocation: $allocation,
      payment_amount: $payment_amount
    }'
)")"
launchpad_seed_inventory_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" deposit_seed_inventory "$(
  jq -cn \
    --arg sale "$sale_name" \
    --argjson amount "$launchpad_seed_sale_amount" \
    '{
      sale: $sale,
      amount: $amount
    }'
)")"
launchpad_register_seed_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" register_seed_liquidity "$(
  jq -cn \
    --arg sale "$sale_name" \
    --arg position_id "$launchpad_seed_position_id" \
    --arg vault_account "$vault_account" \
    --argjson bin_id "$launchpad_seed_bin_id" \
    --argjson payment_amount "$launchpad_seed_payment_amount" \
    --argjson sale_amount "$launchpad_seed_sale_amount" \
    '{
      sale: $sale,
      position_id: $position_id,
      vault_account: $vault_account,
      bin_id: $bin_id,
      payment_amount: $payment_amount,
      sale_amount: $sale_amount
    }'
)")"
launchpad_finalize_activation_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" finalize_sale_activation "$(
  jq -cn \
    --arg sale "$sale_name" \
    --argjson claim_inventory_amount "$launchpad_claim_inventory_amount" \
    '{
      sale: $sale,
      claim_inventory_amount: $claim_inventory_amount
    }'
)")"
launchpad_claim_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" claim_allocation "$(
  jq -cn \
    --arg allocation "$launchpad_allocation_id" \
    '{
      allocation: $allocation
    }'
)")"
refund_sale_init_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" init_sale "$(
  jq -cn \
    --arg sale "$refund_sale_name" \
    --arg sale_asset "$launchpad_sale_asset_id" \
    --arg payment_asset "$xor_id" \
    --arg treasury "$vault_account" \
    --argjson unit_price 1 \
    --argjson soft_cap "$refund_soft_cap" \
    --argjson hard_cap 100000 \
    --argjson claim_start_slot 0 \
    --argjson claim_end_slot 0 \
    '{
      sale: $sale,
      sale_asset: $sale_asset,
      payment_asset: $payment_asset,
      treasury: $treasury,
      unit_price: $unit_price,
      soft_cap: $soft_cap,
      hard_cap: $hard_cap,
      claim_start_slot: $claim_start_slot,
      claim_end_slot: $claim_end_slot
    }'
)")"
refund_sale_config_tx_hash=""
refund_sale_contribute_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" contribute_recorded "$(
  jq -cn \
    --arg sale "$refund_sale_name" \
    --arg allocation "$refund_allocation_id" \
    --argjson payment_amount "$refund_payment_amount" \
    '{
      sale: $sale,
      allocation: $allocation,
      payment_amount: $payment_amount
    }'
)")"
refund_sale_close_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" close_sale "$(
  jq -cn \
    --arg sale "$refund_sale_name" \
    '{ sale: $sale }'
)")"
refund_sale_refund_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" refund_allocation "$(
  jq -cn \
    --arg allocation "$refund_allocation_id" \
    '{
      allocation: $allocation
    }'
)")"
refund_allocation_mirror_view_json="$(submit_contract_view "$config" "$launchpad_sale_factory_contract" mirror_allocation "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --arg allocation "$refund_allocation_id" \
    '{ allocation: $allocation }'
)")"

referral_config_tx_hash=""
referral_tiers_tx_hash=""
referral_parent_bind_tx_hash="$(call_contract_and_wait "$config" "$referral_registry_contract" bind_member "$(
  jq -cn \
    --arg member "$referral_parent_member" \
    '{
      member: $member
    }'
)")"
referral_bind_tx_hash="$(call_contract_and_wait "$config" "$referral_registry_contract" bind_member_with_parent "$(
  jq -cn \
    --arg member "$referral_member" \
    --arg parent_member "$referral_parent_member" \
    '{
      member: $member,
      parent_member: $parent_member
    }'
)")"
referral_accrue_tx_hash="$(call_contract_and_wait "$config" "$referral_registry_contract" accrue "$(
  jq -cn \
    --arg member "$referral_member" \
    --argjson amount "$referral_accrual_amount" \
    '{
      member: $member,
      amount: $amount
    }'
)")"
referral_claim_tx_hash="$(call_contract_and_wait "$config" "$referral_registry_contract" claim "$(
  jq -cn \
    --arg member "$referral_member" \
    '{
      member: $member
    }'
)")"
referral_parent_claim_tx_hash="$(call_contract_and_wait "$config" "$referral_registry_contract" claim "$(
  jq -cn \
    --arg member "$referral_parent_member" \
    '{
      member: $member
    }'
)")"
referral_mirror_view_json="$(submit_contract_view "$config" "$referral_registry_contract" mirror_member "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --arg member "$referral_member" \
    '{ member: $member }'
)")"

farm_config_tx_hash=""
farm_state_before_view_json="$(submit_contract_view "$config" "$farms_farm_contract" farm_state "$SORASWAP_SMOKE_GAS_LIMIT" null)"
farm_before_mirror_view_json="$(submit_contract_view "$config" "$farms_farm_contract" mirror_position "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --arg position "$farm_position" \
    '{ position: $position }'
)")"
farm_state_before_result="$(contract_view_result_json "$farm_state_before_view_json")"
farm_before_mirror_result="$(contract_view_result_json "$farm_before_mirror_view_json")"
farm_baseline_position_registered="$(jq -r '.[0] // 0' <<<"$farm_before_mirror_result")"
farm_baseline_total_staked="$(jq -r '.[4] // 0' <<<"$farm_before_mirror_result")"
farm_baseline_reward_budget="$(jq -r '.[5] // 0' <<<"$farm_before_mirror_result")"
farm_baseline_reward_distributed="$(jq -r '.[6] // 0' <<<"$farm_before_mirror_result")"
farm_reward_rate_live="$(jq -r '.[7] // 0' <<<"$farm_before_mirror_result")"
farm_baseline_global_reward_index="$(jq -r '.[2] // 0' <<<"$farm_state_before_result")"
farm_baseline_reward_index_remainder="$(jq -r '.[3] // 0' <<<"$farm_state_before_result")"
farm_reward_index_scale=1000000000
if (( farm_baseline_position_registered != 0 )); then
  echo "local smoke farm position unexpectedly already exists: $farm_position" >&2
  exit 1
fi
farm_current_slot_before="$(jq -r '.result[0] // 0' <<<"$farm_state_before_view_json")"
farm_min_unstake_gap=$(( farm_unstake_slot - farm_claim_slot ))
if (( farm_min_unstake_gap < 1 )); then
  farm_min_unstake_gap=1
fi
if (( farm_claim_slot <= farm_current_slot_before )); then
  farm_claim_slot=$(( farm_current_slot_before + 1 ))
fi
farm_reward_budget_after_fund_preview=$(( farm_baseline_reward_budget + farm_reward_fund_amount ))
farm_total_staked_after_stake_preview=$(( farm_baseline_total_staked + farm_stake_amount ))
farm_claim_min_elapsed=1
while (( farm_total_staked_after_stake_preview > 0 && farm_reward_budget_after_fund_preview > 0 )); do
  farm_claim_candidate_emitted=$(( farm_claim_min_elapsed * farm_reward_rate_live ))
  if (( farm_claim_candidate_emitted > farm_reward_budget_after_fund_preview )); then
    farm_claim_candidate_emitted="$farm_reward_budget_after_fund_preview"
  fi
  farm_claim_candidate_scaled=$(( farm_claim_candidate_emitted * farm_reward_index_scale + farm_baseline_reward_index_remainder ))
  farm_claim_candidate_delta=$(( farm_claim_candidate_scaled / farm_total_staked_after_stake_preview ))
  farm_claim_candidate_reward=$(( farm_stake_amount * farm_claim_candidate_delta / farm_reward_index_scale ))
  if (( farm_claim_candidate_reward > 0 )); then
    break
  fi
  if (( farm_claim_candidate_emitted >= farm_reward_budget_after_fund_preview )); then
    echo "local smoke cannot accrue a positive farm claim; raise SORASWAP_FARM_SMOKE_REWARD_FUND or stake amount" >&2
    exit 1
  fi
  farm_claim_min_elapsed=$(( farm_claim_min_elapsed + 1 ))
done
farm_claim_min_slot=$(( farm_current_slot_before + farm_claim_min_elapsed ))
if (( farm_claim_slot < farm_claim_min_slot )); then
  farm_claim_slot="$farm_claim_min_slot"
fi
farm_claim_elapsed_preview=$(( farm_claim_slot - farm_current_slot_before ))
farm_claim_emitted_preview=$(( farm_claim_elapsed_preview * farm_reward_rate_live ))
if (( farm_claim_emitted_preview > farm_reward_budget_after_fund_preview )); then
  farm_claim_emitted_preview="$farm_reward_budget_after_fund_preview"
fi
farm_claim_scaled_preview=$(( farm_claim_emitted_preview * farm_reward_index_scale + farm_baseline_reward_index_remainder ))
farm_claim_index_delta_preview=$(( farm_claim_scaled_preview / farm_total_staked_after_stake_preview ))
farm_reward_index_remainder_after_claim_preview=$(( farm_claim_scaled_preview - farm_claim_index_delta_preview * farm_total_staked_after_stake_preview ))
farm_reward_budget_after_claim_preview=$(( farm_reward_budget_after_fund_preview - farm_claim_emitted_preview ))
farm_unstake_min_gap_required=1
while (( farm_total_staked_after_stake_preview > 0 && farm_reward_budget_after_claim_preview > 0 )); do
  farm_unstake_candidate_emitted=$(( farm_unstake_min_gap_required * farm_reward_rate_live ))
  if (( farm_unstake_candidate_emitted > farm_reward_budget_after_claim_preview )); then
    farm_unstake_candidate_emitted="$farm_reward_budget_after_claim_preview"
  fi
  farm_unstake_candidate_scaled=$(( farm_unstake_candidate_emitted * farm_reward_index_scale + farm_reward_index_remainder_after_claim_preview ))
  farm_unstake_candidate_delta=$(( farm_unstake_candidate_scaled / farm_total_staked_after_stake_preview ))
  farm_unstake_candidate_reward=$(( farm_stake_amount * farm_unstake_candidate_delta / farm_reward_index_scale ))
  if (( farm_unstake_candidate_reward > 0 )); then
    break
  fi
  if (( farm_unstake_candidate_emitted >= farm_reward_budget_after_claim_preview )); then
    echo "local smoke cannot accrue a positive post-claim farm remainder; raise SORASWAP_FARM_SMOKE_REWARD_FUND or stake amount" >&2
    exit 1
  fi
  farm_unstake_min_gap_required=$(( farm_unstake_min_gap_required + 1 ))
done
if (( farm_min_unstake_gap < farm_unstake_min_gap_required )); then
  farm_min_unstake_gap="$farm_unstake_min_gap_required"
fi
if (( farm_unstake_slot < farm_claim_slot + farm_min_unstake_gap )); then
  farm_unstake_slot=$(( farm_claim_slot + farm_min_unstake_gap ))
fi
farm_fund_tx_hash="$(call_contract_and_wait "$config" "$farms_farm_contract" fund_rewards "$(
  jq -cn \
    --argjson amount "$farm_reward_fund_amount" \
    '{
      amount: $amount
    }'
)")"
farm_stake_tx_hash="$(call_contract_and_wait "$config" "$farms_farm_contract" stake "$(
  jq -cn \
    --arg position "$farm_position" \
    --argjson amount "$farm_stake_amount" \
    '{
      position: $position,
      amount: $amount
    }'
)")"
farm_sync_claim_tx_hash="$(call_contract_and_wait "$config" "$farms_farm_contract" sync_slot "$(
  jq -cn \
    --argjson current_slot "$farm_claim_slot" \
    '{ current_slot: $current_slot }'
)")"
farm_claim_tx_hash="$(call_contract_and_wait "$config" "$farms_farm_contract" claim "$(
  jq -cn \
    --arg position "$farm_position" \
    '{
      position: $position
    }'
)")"
farm_sync_unstake_tx_hash="$(call_contract_and_wait "$config" "$farms_farm_contract" sync_slot "$(
  jq -cn \
    --argjson current_slot "$farm_unstake_slot" \
    '{ current_slot: $current_slot }'
)")"
farm_unstake_tx_hash="$(call_contract_and_wait "$config" "$farms_farm_contract" unstake "$(
  jq -cn \
    --arg position "$farm_position" \
    --argjson amount "$farm_unstake_amount" \
    '{
      position: $position,
      amount: $amount
    }'
)")"
farm_mirror_view_json="$(submit_contract_view "$config" "$farms_farm_contract" mirror_position "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --arg position "$farm_position" \
    '{ position: $position }'
)")"
launchpad_activation_view_json="$(submit_contract_view "$config" "$launchpad_sale_factory_contract" activation_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --arg sale "$sale_name" \
    '{ sale: $sale }'
)")"

perps_open_payload_json="$(
  jq -cn \
    --argjson market_id 1 \
    --argjson size "$perps_size" \
    --argjson margin "$perps_initial_collateral" \
    --argjson requested_leverage_bps "$perps_requested_leverage_bps" \
    --argjson oracle "$(soraswap_perps_oracle_fields_json "$config" 1 "$perps_entry_price_bps" "$perps_entry_price_bps" 25 101)" \
    '{
      market_id: $market_id,
      size: $size,
      margin: $margin,
      requested_leverage_bps: $requested_leverage_bps,
      oracle_payload: $oracle.oracle_payload,
      oracle_signature: $oracle.oracle_signature
    }'
)"
perps_open_output=""
perps_open_status=0
set +e
perps_open_output="$(call_contract_and_wait "$config" "$perps_engine_contract" open_position "$perps_open_payload_json" 2>&1)"
perps_open_status=$?
set -e
if (( perps_open_status == 0 )); then
  perps_open_tx_hash="$perps_open_output"
else
  echo "local smoke perps open diagnostics:" >&2
  echo "  call output: $perps_open_output" >&2
  echo "  payload: $perps_open_payload_json" >&2
  echo "  user xor balance: $(asset_value_for_account_id "$config" "$xor_id" "$vault_account")" >&2
  echo "  user usdt balance: $(asset_value_for_account_id "$config" "$usdt_id" "$vault_account")" >&2
  echo "  user n3x balance: $(asset_value_for_account_id "$config" "$n3x_id" "$vault_account")" >&2
  echo "  risk vault subject usdt balance: $(asset_value_for_account_id "$config" "$usdt_id" "$risk_vault_contract_subject")" >&2
  echo "  perps subject usdt balance: $(asset_value_for_account_id "$config" "$usdt_id" "$perps_engine_contract_subject")" >&2
  echo "  risk bucket state: $(contract_view_result_json "$(submit_contract_view "$config" "$risk_vault_contract" bucket_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"bucket_id":1}')")" >&2
  echo "  perps engine config: $(contract_view_result_json "$(submit_contract_view "$config" "$perps_engine_contract" engine_config "$SORASWAP_SMOKE_GAS_LIMIT" null)")" >&2
  echo "  perps market state: $(contract_view_result_json "$(submit_contract_view "$config" "$perps_engine_contract" market_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"market_id":1}')")" >&2
  exit 1
fi
perps_funding_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" sync_funding "$(
	  jq -cn \
	    --argjson market_id 1 \
	    --argjson oracle "$(soraswap_perps_oracle_fields_json "$config" 1 "$perps_funding_mark_price_bps" "$perps_funding_index_price_bps" 25 102)" \
	    '{
	      market_id: $market_id,
	      oracle_payload: $oracle.oracle_payload,
	      oracle_signature: $oracle.oracle_signature
	    }'
	)")"
perps_add_margin_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" add_margin "$(
  jq -cn \
    --argjson position_id "$perps_position_id" \
    --argjson amount "$perps_add_collateral" \
    '{
      position_id: $position_id,
      amount: $amount
    }'
)")"
perps_remove_margin_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" remove_margin "$(
	  jq -cn \
	    --argjson position_id "$perps_position_id" \
	    --argjson amount "$perps_remove_collateral" \
	    --argjson oracle "$(soraswap_perps_oracle_fields_json "$config" 1 "$perps_entry_price_bps" "$perps_entry_price_bps" 25 103)" \
	    '{
	      position_id: $position_id,
	      amount: $amount,
	      oracle_payload: $oracle.oracle_payload,
	      oracle_signature: $oracle.oracle_signature
	    }'
	)")"
perps_close_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" close_position "$(
	  jq -cn \
	    --argjson position_id "$perps_position_id" \
	    --argjson oracle "$(soraswap_perps_oracle_fields_json "$config" 1 "$perps_exit_mark_price_bps" "$perps_exit_mark_price_bps" 25 104)" \
	    '{
	      position_id: $position_id,
	      oracle_payload: $oracle.oracle_payload,
	      oracle_signature: $oracle.oracle_signature
	    }'
	)")"
perps_liquidation_open_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" open_position "$(
  jq -cn \
	    --argjson market_id 1 \
	    --argjson size "$perps_size" \
	    --argjson margin "$perps_liquidation_collateral" \
	    --argjson requested_leverage_bps "$perps_liquidation_requested_leverage_bps" \
	    --argjson oracle "$(soraswap_perps_oracle_fields_json "$config" 1 "$perps_entry_price_bps" "$perps_entry_price_bps" 25 170)" \
	    '{
	      market_id: $market_id,
	      size: $size,
	      margin: $margin,
	      requested_leverage_bps: $requested_leverage_bps,
	      oracle_payload: $oracle.oracle_payload,
	      oracle_signature: $oracle.oracle_signature
	    }'
	)")"
perps_liquidation_queue_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" run_liquidation_pass "$(
	  jq -cn \
	    --argjson market_id 1 \
	    --argjson max_positions "$perps_liquidation_scan_limit" \
	    --argjson oracle "$(soraswap_perps_oracle_fields_json "$config" 1 "$perps_liquidation_stress_mark_price_bps" "$perps_liquidation_stress_mark_price_bps" 25 171)" \
	    '{
	      market_id: $market_id,
	      max_positions: $max_positions,
	      oracle_payload: $oracle.oracle_payload,
	      oracle_signature: $oracle.oracle_signature
	    }'
	)")"
perps_liquidation_recover_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" run_liquidation_pass "$(
	  jq -cn \
	    --argjson market_id 1 \
	    --argjson max_positions "$perps_liquidation_scan_limit" \
	    --argjson oracle "$(soraswap_perps_oracle_fields_json "$config" 1 "$perps_liquidation_healthy_mark_price_bps" "$perps_liquidation_healthy_mark_price_bps" 25 172)" \
	    '{
	      market_id: $market_id,
	      max_positions: $max_positions,
	      oracle_payload: $oracle.oracle_payload,
	      oracle_signature: $oracle.oracle_signature
	    }'
	)")"
perps_recovery_position_state_view_json="$(submit_contract_view "$config" "$perps_engine_contract" position_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --argjson position_id "$perps_liquidation_position_id" '{ position_id: $position_id }'
)")"
perps_recovery_position_liquidation_view_json="$(submit_contract_view "$config" "$perps_engine_contract" position_liquidation_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --argjson position_id "$perps_liquidation_position_id" '{ position_id: $position_id }'
)")"
perps_liquidation_requeue_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" run_liquidation_pass "$(
	  jq -cn \
	    --argjson market_id 1 \
	    --argjson max_positions "$perps_liquidation_scan_limit" \
	    --argjson oracle "$(soraswap_perps_oracle_fields_json "$config" 1 "$perps_liquidation_stress_mark_price_bps" "$perps_liquidation_stress_mark_price_bps" 25 173)" \
	    '{
	      market_id: $market_id,
	      max_positions: $max_positions,
	      oracle_payload: $oracle.oracle_payload,
	      oracle_signature: $oracle.oracle_signature
	    }'
	)")"
perps_liquidation_execute_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" run_liquidation_pass "$(
	  jq -cn \
	    --argjson market_id 1 \
	    --argjson max_positions "$perps_liquidation_scan_limit" \
	    --argjson oracle "$(soraswap_perps_oracle_fields_json "$config" 1 "$perps_liquidation_stress_mark_price_bps" "$perps_liquidation_stress_mark_price_bps" 25 174)" \
	    '{
	      market_id: $market_id,
	      max_positions: $max_positions,
	      oracle_payload: $oracle.oracle_payload,
	      oracle_signature: $oracle.oracle_signature
	    }'
	)")"

options_shout_buy_tx_hash="$(call_contract_and_wait "$config" "$options_factory_contract" buy_shout "$(
  jq -cn \
    --argjson series_id 1 \
    --argjson notional "$options_shout_notional" \
    --argjson premium_paid "$options_shout_premium_paid" \
    --argjson collateral_locked "$options_shout_collateral_locked" \
    '{
      series_id: $series_id,
      notional: $notional,
      premium_paid: $premium_paid,
      collateral_locked: $collateral_locked
    }'
)")"
options_shout_record_tx_hash="$(call_contract_and_wait "$config" "$options_factory_contract" record_shout "$(
  jq -cn \
    --argjson position_id "$options_shout_position_id" \
    --argjson oracle "$(soraswap_shout_oracle_fields_json "$config" "$options_shout_position_id" "$options_shout_record_mark_bps" 201)" \
    '{
      position_id: $position_id,
      oracle_payload: $oracle.oracle_payload,
      oracle_signature: $oracle.oracle_signature
    }'
)")"
options_shout_exercise_tx_hash="$(call_contract_and_wait "$config" "$options_factory_contract" exercise_shout_position "$(
  jq -cn \
    --argjson position_id "$options_shout_position_id" \
    --argjson oracle "$(soraswap_shout_oracle_fields_json "$config" "$options_shout_position_id" "$options_shout_exercise_mark_bps" 202)" \
    '{
      position_id: $position_id,
      oracle_payload: $oracle.oracle_payload,
      oracle_signature: $oracle.oracle_signature
    }'
)")"
options_outperformance_buy_tx_hash="$(call_contract_and_wait "$config" "$options_factory_contract" buy_outperformance "$(
  jq -cn \
    --argjson series_id 2 \
    --argjson notional "$options_outperformance_notional" \
    --argjson premium_paid "$options_outperformance_premium_paid" \
    --argjson collateral_locked "$options_outperformance_collateral_locked" \
    '{
      series_id: $series_id,
      notional: $notional,
      premium_paid: $premium_paid,
      collateral_locked: $collateral_locked
    }'
)")"
options_outperformance_settle_tx_hash="$(call_contract_and_wait "$config" "$options_factory_contract" settle_series "$(
  jq -cn \
    --argjson series_id 2 \
    --argjson oracle "$(soraswap_options_series_oracle_fields_json "$config" 2 "$options_outperformance_final_mark_bps" "$options_outperformance_final_quote_mark_bps" 203)" \
    '{
      series_id: $series_id,
      oracle_payload: $oracle.oracle_payload,
      oracle_signature: $oracle.oracle_signature
    }'
)")"
options_outperformance_exercise_tx_hash="$(call_contract_and_wait "$config" "$options_factory_contract" exercise_outperformance_position "$(
  jq -cn \
    --argjson position_id "$options_outperformance_position_id" \
    '{
      position_id: $position_id
    }'
)")"

cover_register_tx_hash="$(call_contract_and_wait "$config" "$cover_policy_manager_contract" register_policy "$(
  jq -cn \
    --argjson lower_bound "$cover_lower_bound" \
    --argjson upper_bound "$cover_upper_bound" \
    --argjson payout_amount "$cover_payout_amount" \
    --argjson monitoring_window_slots "$cover_monitoring_window_slots" \
    --argjson required_observations "$cover_policy_required_observations" \
    --argjson covered_notional "$cover_notional" \
    --argjson premium_paid "$cover_premium_paid" \
    '{
      lower_bound: $lower_bound,
      upper_bound: $upper_bound,
      payout_amount: $payout_amount,
      monitoring_window_slots: $monitoring_window_slots,
      required_observations: $required_observations,
      covered_notional: $covered_notional,
      premium_paid: $premium_paid
    }'
)")"
cover_trigger_1_tx_hash="$(call_contract_and_wait "$config" "$cover_policy_manager_contract" record_observation "$(
  jq -cn \
    --argjson policy_id "$cover_policy_id" \
    --argjson oracle "$(soraswap_cover_oracle_fields_json "$config" "$cover_policy_id" "$cover_trigger_price" 301)" \
    '{
      policy_id: $policy_id,
      oracle_payload: $oracle.oracle_payload,
      oracle_signature: $oracle.oracle_signature
    }'
)")"
cover_stale_reset_tx_hash="$(call_contract_and_wait "$config" "$cover_policy_manager_contract" record_observation "$(
  jq -cn \
    --argjson policy_id "$cover_policy_id" \
    --argjson oracle "$(soraswap_cover_oracle_fields_json "$config" "$cover_policy_id" "$cover_trigger_price" 302 1)" \
    '{
      policy_id: $policy_id,
      oracle_payload: $oracle.oracle_payload,
      oracle_signature: $oracle.oracle_signature
    }'
)")"
cover_trigger_2_tx_hash="$(call_contract_and_wait "$config" "$cover_policy_manager_contract" record_observation "$(
  jq -cn \
    --argjson policy_id "$cover_policy_id" \
    --argjson oracle "$(soraswap_cover_oracle_fields_json "$config" "$cover_policy_id" "$cover_trigger_price" 303)" \
    '{
      policy_id: $policy_id,
      oracle_payload: $oracle.oracle_payload,
      oracle_signature: $oracle.oracle_signature
    }'
)")"
cover_trigger_3_tx_hash="$(call_contract_and_wait "$config" "$cover_policy_manager_contract" record_observation "$(
  jq -cn \
    --argjson policy_id "$cover_policy_id" \
    --argjson oracle "$(soraswap_cover_oracle_fields_json "$config" "$cover_policy_id" "$cover_trigger_price" 304)" \
    '{
      policy_id: $policy_id,
      oracle_payload: $oracle.oracle_payload,
      oracle_signature: $oracle.oracle_signature
    }'
)")"
cover_trigger_4_tx_hash="$(call_contract_and_wait "$config" "$cover_policy_manager_contract" record_observation "$(
  jq -cn \
    --argjson policy_id "$cover_policy_id" \
    --argjson oracle "$(soraswap_cover_oracle_fields_json "$config" "$cover_policy_id" "$cover_trigger_price" 305)" \
    '{
      policy_id: $policy_id,
      oracle_payload: $oracle.oracle_payload,
      oracle_signature: $oracle.oracle_signature
    }'
)")"
cover_claim_tx_hash="$(call_contract_and_wait "$config" "$cover_policy_manager_contract" route_claim "$(
  jq -cn \
    --argjson policy_id "$cover_policy_id" \
    '{
      policy_id: $policy_id
    }'
)")"

risk_bucket_1_view_json="$(submit_contract_view "$config" "$risk_vault_contract" bucket_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"bucket_id":1}')"
risk_bucket_2_view_json="$(submit_contract_view "$config" "$risk_vault_contract" bucket_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"bucket_id":2}')"
risk_bucket_3_view_json="$(submit_contract_view "$config" "$risk_vault_contract" bucket_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"bucket_id":3}')"
risk_vault_state_view_json="$(submit_contract_view "$config" "$risk_vault_contract" risk_state "$SORASWAP_SMOKE_GAS_LIMIT")"
risk_bucket_1_liability_view_json="$(submit_contract_view "$config" "$risk_vault_contract" liability_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --argjson exposure_id "$perps_position_id" '{ bucket_id: 1, exposure_id: $exposure_id }'
)")"
risk_bucket_1_liquidation_liability_view_json="$(submit_contract_view "$config" "$risk_vault_contract" liability_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --argjson exposure_id "$perps_liquidation_position_id" '{ bucket_id: 1, exposure_id: $exposure_id }'
)")"
risk_bucket_2_shout_liability_view_json="$(submit_contract_view "$config" "$risk_vault_contract" liability_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --argjson exposure_id "$options_shout_position_id" '{ bucket_id: 2, exposure_id: $exposure_id }'
)")"
risk_bucket_2_outperformance_liability_view_json="$(submit_contract_view "$config" "$risk_vault_contract" liability_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --argjson exposure_id "$options_outperformance_position_id" '{ bucket_id: 2, exposure_id: $exposure_id }'
)")"
risk_bucket_3_liability_view_json="$(submit_contract_view "$config" "$risk_vault_contract" liability_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --argjson exposure_id "$cover_policy_id" '{ bucket_id: 3, exposure_id: $exposure_id }'
)")"
risk_bucket_1_automation_view_json="$(submit_contract_view "$config" "$risk_vault_contract" automation_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"bucket_id":1}')"
risk_bucket_2_automation_view_json="$(submit_contract_view "$config" "$risk_vault_contract" automation_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"bucket_id":2}')"
risk_bucket_3_automation_view_json="$(submit_contract_view "$config" "$risk_vault_contract" automation_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"bucket_id":3}')"
perps_engine_config_view_json="$(submit_contract_view "$config" "$perps_engine_contract" engine_config "$SORASWAP_SMOKE_GAS_LIMIT")"
perps_market_state_view_json="$(submit_contract_view "$config" "$perps_engine_contract" market_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"market_id":1}')"
perps_market_risk_view_json="$(submit_contract_view "$config" "$perps_engine_contract" risk_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"market_id":1}')"
perps_automation_view_json="$(submit_contract_view "$config" "$perps_engine_contract" automation_state "$SORASWAP_SMOKE_GAS_LIMIT")"
perps_position_state_view_json="$(submit_contract_view "$config" "$perps_engine_contract" position_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --argjson position_id "$perps_position_id" '{ position_id: $position_id }'
)")"
perps_liquidation_position_state_view_json="$(submit_contract_view "$config" "$perps_engine_contract" position_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --argjson position_id "$perps_liquidation_position_id" '{ position_id: $position_id }'
)")"
perps_liquidation_position_liquidation_view_json="$(submit_contract_view "$config" "$perps_engine_contract" position_liquidation_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --argjson position_id "$perps_liquidation_position_id" '{ position_id: $position_id }'
)")"
perps_liquidation_state_view_json="$(submit_contract_view "$config" "$perps_engine_contract" liquidation_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"market_id":1}')"
options_manager_config_view_json="$(submit_contract_view "$config" "$options_manager_contract" manager_config "$SORASWAP_SMOKE_GAS_LIMIT")"
options_shout_template_view_json="$(submit_contract_view "$config" "$options_manager_contract" template_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"template_id":1}')"
options_outperformance_template_view_json="$(submit_contract_view "$config" "$options_manager_contract" template_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"template_id":2}')"
options_shout_series_view_json="$(submit_contract_view "$config" "$options_manager_contract" series_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"series_id":1}')"
options_outperformance_series_view_json="$(submit_contract_view "$config" "$options_manager_contract" series_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"series_id":2}')"
options_manager_automation_view_json="$(submit_contract_view "$config" "$options_manager_contract" automation_state "$SORASWAP_SMOKE_GAS_LIMIT")"
options_factory_config_view_json="$(submit_contract_view "$config" "$options_factory_contract" factory_config "$SORASWAP_SMOKE_GAS_LIMIT")"
options_factory_shout_series_view_json="$(submit_contract_view "$config" "$options_factory_contract" series_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"series_id":1}')"
options_factory_outperformance_series_view_json="$(submit_contract_view "$config" "$options_factory_contract" series_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"series_id":2}')"
options_factory_automation_view_json="$(submit_contract_view "$config" "$options_factory_contract" automation_state "$SORASWAP_SMOKE_GAS_LIMIT")"
options_factory_shout_position_view_json="$(submit_contract_view "$config" "$options_factory_contract" position_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --argjson position_id "$options_shout_position_id" '{ position_id: $position_id }'
)")"
options_factory_outperformance_position_view_json="$(submit_contract_view "$config" "$options_factory_contract" position_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --argjson position_id "$options_outperformance_position_id" '{ position_id: $position_id }'
)")"
options_vault_shout_state_view_json="$(submit_contract_view "$config" "$options_vault_contract" vault_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"series_id":1}')"
options_vault_outperformance_state_view_json="$(submit_contract_view "$config" "$options_vault_contract" vault_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"series_id":2}')"
options_vault_shout_position_view_json="$(submit_contract_view "$config" "$options_vault_contract" position_accounting "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --argjson position_id "$options_shout_position_id" '{ position_id: $position_id }'
)")"
options_vault_outperformance_position_view_json="$(submit_contract_view "$config" "$options_vault_contract" position_accounting "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --argjson position_id "$options_outperformance_position_id" '{ position_id: $position_id }'
)")"
options_shout_product_view_json="$(submit_contract_view "$config" "$options_shout_option_contract" series_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"series_id":1}')"
options_outperformance_product_view_json="$(submit_contract_view "$config" "$options_outperformance_option_contract" series_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"series_id":2}')"
options_shout_product_position_view_json="$(submit_contract_view "$config" "$options_shout_option_contract" position_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --argjson position_id "$options_shout_position_id" '{ position_id: $position_id }'
)")"
options_outperformance_product_position_view_json="$(submit_contract_view "$config" "$options_outperformance_option_contract" position_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --argjson position_id "$options_outperformance_position_id" '{ position_id: $position_id }'
)")"
cover_manager_config_view_json="$(submit_contract_view "$config" "$cover_policy_manager_contract" manager_config "$SORASWAP_SMOKE_GAS_LIMIT")"
cover_automation_view_json="$(submit_contract_view "$config" "$cover_policy_manager_contract" automation_state "$SORASWAP_SMOKE_GAS_LIMIT")"
cover_policy_view_json="$(submit_contract_view "$config" "$cover_policy_manager_contract" policy_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn --argjson policy_id "$cover_policy_id" '{ policy_id: $policy_id }'
)")"

job_enqueue_tx_hash="$(call_contract_and_wait "$config" "$automation_job_queue_contract" enqueue "$(
  jq -cn \
    --arg job "$job_name" \
    --argjson payload_hash 123456 \
    '{
      job: $job,
      payload_hash: $payload_hash
    }'
)")"
job_config_tx_hash="$(call_contract_and_wait "$config" "$automation_job_queue_contract" configure_job "$(
  jq -cn \
    --arg job "$job_name" \
    --argjson next_slot "$automation_next_slot" \
    --argjson max_retries "$automation_max_retries" \
    --argjson retry_delay_slots "$automation_retry_delay_slots" \
    '{
      job: $job,
      next_slot: $next_slot,
      max_retries: $max_retries,
      retry_delay_slots: $retry_delay_slots
    }'
)")"
job_assign_executor_tx_hash="$(call_contract_and_wait "$config" "$automation_job_queue_contract" assign_executor "$(
  jq -cn \
    --arg job "$job_name" \
    --arg executor "$automation_executor" \
    '{
      job: $job,
      executor: $executor
    }'
)")"
job_cron_tx_hash="$(call_contract_and_wait "$config" "$automation_job_queue_contract" configure_cron "$(
  jq -cn \
    --arg job "$job_name" \
    --argjson interval_slots "$automation_cron_interval_slots" \
    '{
      job: $job,
      interval_slots: $interval_slots
    }'
)")"
soraswap_wait_for_block_height_at_least "$config" "$automation_next_slot" "automation initial dispatch"
job_dispatch_tx_hash="$(call_contract_and_wait "$config" "$automation_job_queue_contract" dispatch_job "$(
  jq -cn \
    --arg job "$job_name" \
    '{ job: $job }'
)")"
job_pause_tx_hash="$(call_contract_and_wait "$config" "$automation_job_queue_contract" pause_job "$(
  jq -cn \
    --arg job "$job_name" \
    '{ job: $job }'
)")"
job_resume_tx_hash="$(call_contract_and_wait "$config" "$automation_job_queue_contract" resume_job "$(
  jq -cn \
    --arg job "$job_name" \
    '{ job: $job }'
)")"
job_retry_tx_hash="$(call_contract_and_wait "$config" "$automation_job_queue_contract" retry "$(
  jq -cn \
    --arg job "$job_name" \
    '{ job: $job }'
)")"
job_retry_state_view_json="$(submit_contract_view "$config" "$automation_job_queue_contract" mirror_job "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --arg job "$job_name" \
    '{ job: $job }'
)")"
automation_retry_ready_slot="$(contract_view_result_json "$job_retry_state_view_json" | jq -er '.[5]')"
soraswap_wait_for_block_height_at_least "$config" "$automation_retry_ready_slot" "automation retry dispatch"
job_retry_dispatch_tx_hash="$(call_contract_and_wait "$config" "$automation_job_queue_contract" dispatch_job "$(
  jq -cn \
    --arg job "$job_name" \
    '{ job: $job }'
)")"
job_complete_tx_hash="$(call_contract_and_wait "$config" "$automation_job_queue_contract" complete_run "$(
  jq -cn \
    --arg job "$job_name" \
    '{ job: $job }'
)")"
job_mirror_view_json="$(submit_contract_view "$config" "$automation_job_queue_contract" mirror_job "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --arg job "$job_name" \
    '{ job: $job }'
)")"
fi

trigger_registration_evidence_json="$(soraswap_collect_trigger_registration_evidence "$config")"
soraswap_assert_expected_triggers_registered "$trigger_registration_evidence_json"
current_smoke_slot="$(soraswap_current_block_height "$config")"
if [[ -z "$current_smoke_slot" || "$current_smoke_slot" == "null" || "$current_smoke_slot" != <-> ]]; then
  current_smoke_slot=0
fi
conditional_escrow_expiry_slot=$(( current_smoke_slot + conditional_escrow_expiry_offset_slots ))
ensure_can_execute_trigger_permission "$config" "$SORASWAP_AUTHORITY" "soraswap_escrow_settle"
conditional_escrow_open_tx_hash="$(call_contract_and_wait "$config" "$escrow_conditional_escrow_contract" open_escrow "$(
  jq -cn \
    --arg escrow_id "$conditional_escrow_id" \
    --arg taker "$SORASWAP_AUTHORITY" \
    --arg asset "$usdt_id" \
    --argjson amount "$conditional_escrow_amount" \
    --argjson expiry_slot "$conditional_escrow_expiry_slot" \
    --argjson condition_code "$conditional_escrow_condition_code" \
    '{
      escrow_id: $escrow_id,
      taker: $taker,
      asset: $asset,
      amount: $amount,
      expiry_slot: $expiry_slot,
      condition_code: $condition_code
    }'
)")"
conditional_escrow_execute_args_json="$(
  jq -cn \
    --arg escrow_id "$conditional_escrow_id" \
    --argjson condition_code "$conditional_escrow_condition_code" \
    '{ escrow_id: $escrow_id, condition_code: $condition_code }'
)"
conditional_escrow_completion_timeout_ms="${SORASWAP_TRIGGER_COMPLETION_TIMEOUT_MS:-30000}"
conditional_escrow_completion_file="$(mktemp "${TMPDIR:-/tmp}/soraswap-escrow-completion.XXXXXX")"
conditional_escrow_completion_err_file="$(mktemp "${TMPDIR:-/tmp}/soraswap-escrow-completion-err.XXXXXX")"
soraswap_start_trigger_completion_capture \
  "$config" \
  "soraswap_escrow_settle" \
  "$conditional_escrow_completion_timeout_ms" \
  1 \
  "$conditional_escrow_completion_file" \
  "$conditional_escrow_completion_err_file"
conditional_escrow_completion_pid="$SORASWAP_TRIGGER_COMPLETION_CAPTURE_PID"
sleep "${SORASWAP_TRIGGER_COMPLETION_CAPTURE_WARMUP_SECONDS:-1}"
conditional_escrow_execute_tx_hash="$(soraswap_execute_trigger "$config" "soraswap_escrow_settle" "$conditional_escrow_execute_args_json")"
conditional_escrow_completion_json_file="$(mktemp "${TMPDIR:-/tmp}/soraswap-escrow-completion-json.XXXXXX")"
soraswap_finish_trigger_completion_capture \
  "$conditional_escrow_completion_pid" \
  "soraswap_escrow_settle" \
  "$conditional_escrow_completion_timeout_ms" \
  1 \
  "$conditional_escrow_completion_file" \
  "$conditional_escrow_completion_err_file" \
  > "$conditional_escrow_completion_json_file"
conditional_escrow_completion_json="$(cat "$conditional_escrow_completion_json_file")"
rm -f "$conditional_escrow_completion_json_file"
conditional_escrow_state_view_json="$(submit_contract_view "$config" "$escrow_conditional_escrow_contract" escrow_state "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --arg escrow_id "$conditional_escrow_id" \
    '{ escrow_id: $escrow_id }'
)")"
epoch_auction_native_close_evidence_json="$(soraswap_prove_epoch_auction_native_close "$config" "$batch_epoch_auction_contract" "$SORASWAP_SMOKE_GAS_LIMIT")"
epoch_auction_state_view_json="$(submit_contract_view "$config" "$batch_epoch_auction_contract" epoch_state "$SORASWAP_SMOKE_GAS_LIMIT")"
dlmm_range_governor_view_json="$(submit_contract_view "$config" "$dlmm_pool_contract" range_governor_state "$SORASWAP_SMOKE_GAS_LIMIT")"
twamm_trigger_state_view_json="$(submit_contract_view "$config" "$dlmm_hooks_manager_contract" twamm_trigger_state "$SORASWAP_SMOKE_GAS_LIMIT")"
options_manager_lifecycle_view_json="$(submit_contract_view "$config" "$options_manager_contract" trigger_lifecycle_state "$SORASWAP_SMOKE_GAS_LIMIT")"
options_factory_lifecycle_view_json="$(submit_contract_view "$config" "$options_factory_contract" trigger_lifecycle_state "$SORASWAP_SMOKE_GAS_LIMIT")"
cover_lifecycle_view_json="$(submit_contract_view "$config" "$cover_policy_manager_contract" trigger_lifecycle_state "$SORASWAP_SMOKE_GAS_LIMIT")"
launchpad_lifecycle_view_json="$(submit_contract_view "$config" "$launchpad_sale_factory_contract" trigger_lifecycle_state "$SORASWAP_SMOKE_GAS_LIMIT")"
vault_lifecycle_view_json="$(submit_contract_view "$config" "$vaults_manager_contract" trigger_lifecycle_state "$SORASWAP_SMOKE_GAS_LIMIT")"
perps_lifecycle_view_json="$(submit_contract_view "$config" "$perps_engine_contract" trigger_lifecycle_state "$SORASWAP_SMOKE_GAS_LIMIT")"

n3x_assert_view_json="$(submit_contract_view "$config" "$n3x_hub_contract" assert_initialized "$SORASWAP_SMOKE_GAS_LIMIT")"
n3x_mirror_view_json="$(submit_contract_view "$config" "$n3x_hub_contract" mirror_state "$SORASWAP_SMOKE_GAS_LIMIT")"
router_assert_view_json="$(submit_contract_view "$config" "$dlmm_router_contract" assert_router_config "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --argjson default_fee_pips "$pool_fee_pips" \
    '{ default_fee_pips: $default_fee_pips }'
)")"
router_contract_binding_view_json="$(submit_contract_view "$config" "$dlmm_router_contract" contract_binding "$SORASWAP_SMOKE_GAS_LIMIT")"
router_execution_view_json="$(submit_contract_view "$config" "$dlmm_router_contract" execution_binding "$SORASWAP_SMOKE_GAS_LIMIT")"
router_mirror_view_json="$(submit_contract_view "$config" "$dlmm_router_contract" mirror_state "$SORASWAP_SMOKE_GAS_LIMIT")"
pool_mirror_view_json="$(submit_contract_view "$config" "$dlmm_pool_contract" mirror_state "$SORASWAP_SMOKE_GAS_LIMIT")"

if [[ "$smoke_scope" != "foundation" ]]; then
launchpad_mirror_view_json="$(submit_contract_view "$config" "$launchpad_sale_factory_contract" mirror_sale "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --arg sale "$sale_name" \
    '{ sale: $sale }'
)")"
launchpad_mirror_accounting_view_json="$(submit_contract_view "$config" "$launchpad_sale_factory_contract" mirror_sale_accounting "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --arg sale "$sale_name" \
    '{ sale: $sale }'
)")"
fi

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
if [[ "$smoke_scope" != "foundation" ]]; then
  decoded_state_ints="$(jq -c '. + $add' \
    --argjson add "$(contract_view_result_object "$launchpad_mirror_view_json" \
      soraswap_launchpad_seed_registered \
      soraswap_launchpad_raised \
      soraswap_launchpad_sold \
      soraswap_launchpad_closed \
      soraswap_launchpad_successful \
      soraswap_launchpad_seeded \
      soraswap_launchpad_seed_inventory \
      soraswap_launchpad_seed_bin_id \
      soraswap_launchpad_seed_payment_amount \
      soraswap_launchpad_seed_sale_amount \
      soraswap_launchpad_claim_inventory \
      soraswap_launchpad_claim_start_slot \
      soraswap_launchpad_claim_end_slot)" \
    <<<"$decoded_state_ints")"
  decoded_state_ints="$(jq -c '. + $add' \
    --argjson add "$(contract_view_result_object "$launchpad_mirror_accounting_view_json" \
      soraswap_launchpad_seed_payment_used \
      soraswap_launchpad_seed_sale_used \
      soraswap_launchpad_claimed_supply \
      soraswap_launchpad_refunded_payment)" \
    <<<"$decoded_state_ints")"
  decoded_state_ints="$(jq -c '. + $add' \
    --argjson add "$(contract_view_result_object "$launchpad_activation_view_json" \
      soraswap_launchpad_seed_executor_bound \
      soraswap_launchpad_seed_activation_value)" \
    <<<"$decoded_state_ints")"
  decoded_state_ints="$(jq -c '. + $add' \
    --argjson add "$(contract_view_result_object "$refund_allocation_mirror_view_json" \
      soraswap_launchpad_allocation_registered \
      soraswap_launchpad_allocation_payment_amount \
      soraswap_launchpad_allocation_sale_amount \
      soraswap_launchpad_allocation_claimed \
      soraswap_launchpad_allocation_refunded)" \
    <<<"$decoded_state_ints")"
  decoded_state_ints="$(jq -c '. + $add' \
    --argjson add "$(contract_view_result_object "$referral_mirror_view_json" \
      soraswap_referral_bound \
      soraswap_referral_claim_threshold \
      soraswap_referral_direct_share_bps \
      soraswap_referral_parent_share_bps \
      soraswap_referral_accrued \
      soraswap_referral_total_accrued \
      soraswap_referral_total_claimed \
      soraswap_referral_claim_count \
      soraswap_referral_parent_bound \
      soraswap_referral_parent_accrued \
      soraswap_referral_parent_total_accrued \
      soraswap_referral_parent_total_claimed \
      soraswap_referral_parent_claim_count)" \
    <<<"$decoded_state_ints")"
  decoded_state_ints="$(jq -c '. + $add' \
    --argjson add "$(contract_view_result_object "$farm_mirror_view_json" \
      soraswap_farm_position_registered \
      soraswap_farm_stake \
      soraswap_farm_accrued \
      soraswap_farm_claimed \
      soraswap_farm_total_staked \
      soraswap_farm_reward_budget \
      soraswap_farm_reward_distributed \
      soraswap_farm_reward_rate)" \
    <<<"$decoded_state_ints")"
  decoded_state_ints="$(jq -c '. + $add' \
    --argjson add "$(contract_view_result_object "$job_mirror_view_json" \
      soraswap_automation_job_registered \
      soraswap_automation_executor_bound \
      soraswap_automation_job_payload_hash \
      soraswap_automation_job_status \
      soraswap_automation_retry_count \
      soraswap_automation_next_slot \
      soraswap_automation_cron_interval_slots \
      soraswap_automation_max_retries \
      soraswap_automation_retry_delay_slots \
      soraswap_automation_last_run_slot \
      soraswap_automation_run_count)" \
    <<<"$decoded_state_ints")"
fi

scale_ppm=1000000
fee_growth_scale=1000000000
next_bin_id=$(( pool_active_bin + pool_bin_step ))
far_bin_id=$(( pool_active_bin + (2 * pool_bin_step) ))
price_active="$(dlmm_price_ppm "$pool_active_bin" "$pool_bin_step")"
price_next="$(dlmm_price_ppm "$next_bin_id" "$pool_bin_step")"
position_seed_shares=$(( pool_position_base + pool_position_quote ))
active_seed_base=$(( pool_seed_base + pool_position_base ))
active_seed_quote=$(( pool_seed_quote + pool_position_quote ))
active_seed_share_supply=$(( pool_seed_base + pool_seed_quote + position_seed_shares ))
next_seed_share_supply=$(( pool_seed_next_base + pool_seed_next_quote ))
far_seed_share_supply=$(( pool_seed_far_base + pool_seed_far_quote ))
available_quote_active=$(( active_seed_quote - pool_min_reserve_quote ))
net_needed_active=$(( (available_quote_active * scale_ppm + price_active - 1) / price_active ))
gross_needed_active="$(dlmm_gross_from_net "$net_needed_active" "$pool_fee_pips")"
expected_active_bin="$pool_active_bin"
expected_swap_out=0
expected_pool_reserve_base="$active_seed_base"
expected_pool_reserve_quote="$active_seed_quote"
expected_position_fee_base=0
expected_active_share_supply="$active_seed_share_supply"

if (( swap_amount_in <= gross_needed_active )); then
  effective_used_active=$(( swap_amount_in * (scale_ppm - pool_fee_pips) / scale_ppm ))
  out_active=$(( effective_used_active * price_active / scale_ppm ))
  expected_swap_out="$out_active"
  expected_pool_reserve_base=$(( active_seed_base + swap_amount_in ))
  expected_pool_reserve_quote=$(( active_seed_quote - out_active ))
  expected_position_fee_base=$(( swap_amount_in - effective_used_active ))
  if (( expected_pool_reserve_quote <= pool_min_reserve_quote )); then
    expected_active_bin="$next_bin_id"
    expected_active_share_supply="$next_seed_share_supply"
  fi
else
  effective_used_active=$(( gross_needed_active * (scale_ppm - pool_fee_pips) / scale_ppm ))
  expected_swap_out="$available_quote_active"
  expected_pool_reserve_base=$(( active_seed_base + gross_needed_active ))
  expected_pool_reserve_quote="$pool_min_reserve_quote"
  expected_position_fee_base=$(( gross_needed_active - effective_used_active ))
  expected_active_bin="$next_bin_id"
  expected_active_share_supply="$next_seed_share_supply"

  remaining_input=$(( swap_amount_in - gross_needed_active ))
  available_quote_next=$(( pool_seed_next_quote - pool_min_reserve_quote ))
  effective_used_next=$(( remaining_input * (scale_ppm - pool_fee_pips) / scale_ppm ))
  out_next=$(( effective_used_next * price_next / scale_ppm ))
  if (( out_next > available_quote_next )); then
    out_next="$available_quote_next"
  fi

  expected_swap_out=$(( expected_swap_out + out_next ))
  expected_pool_reserve_base=$(( pool_seed_next_base + remaining_input ))
  expected_pool_reserve_quote=$(( pool_seed_next_quote - out_next ))

  if (( out_next >= available_quote_next )); then
    expected_active_bin="$far_bin_id"
    expected_pool_reserve_base="$pool_seed_far_base"
    expected_pool_reserve_quote="$pool_seed_far_quote"
    expected_active_share_supply="$far_seed_share_supply"
  fi
fi

if (( expected_active_bin == pool_active_bin )); then
  fee_growth_delta_active=$(( expected_position_fee_base * fee_growth_scale / active_seed_share_supply ))
  collected_position_base=$(( position_seed_shares * fee_growth_delta_active / fee_growth_scale ))
  if (( collected_position_base < 0 )); then
    collected_position_base=0
  fi
  post_collect_active_base=$(( expected_pool_reserve_base - collected_position_base ))
  post_collect_active_quote="$expected_pool_reserve_quote"
  removed_position_base=$(( post_collect_active_base * pool_position_remove_shares / active_seed_share_supply ))
  removed_position_quote=$(( post_collect_active_quote * pool_position_remove_shares / active_seed_share_supply ))
  expected_pool_reserve_base=$(( post_collect_active_base - removed_position_base ))
  expected_pool_reserve_quote=$(( post_collect_active_quote - removed_position_quote ))
  expected_active_share_supply=$(( active_seed_share_supply - pool_position_remove_shares ))
fi

expected_active_liquidity=$(( expected_pool_reserve_base + expected_pool_reserve_quote ))
launchpad_expected_activation_value=$(( launchpad_seed_payment_amount + launchpad_seed_sale_amount ))
if [[ "$smoke_scope" != "foundation" ]] && (( launchpad_seed_bin_id == expected_active_bin )); then
  launchpad_seed_minted_shares="$launchpad_expected_activation_value"
  if (( expected_active_share_supply > 0 && expected_active_liquidity > 0 )); then
    launchpad_seed_minted_shares=$(( launchpad_expected_activation_value * expected_active_share_supply / expected_active_liquidity ))
  fi
  expected_pool_reserve_base=$(( expected_pool_reserve_base + launchpad_seed_sale_amount ))
  expected_pool_reserve_quote=$(( expected_pool_reserve_quote + launchpad_seed_payment_amount ))
  expected_active_share_supply=$(( expected_active_share_supply + launchpad_seed_minted_shares ))
  expected_active_liquidity=$(( expected_pool_reserve_base + expected_pool_reserve_quote ))
fi
farm_reward_budget_after_fund=$(( farm_baseline_reward_budget + farm_reward_fund_amount ))
farm_total_staked_after_stake=$(( farm_baseline_total_staked + farm_stake_amount ))
farm_position_reward_debt_after_stake="$farm_baseline_global_reward_index"
farm_claim_elapsed=$(( farm_claim_slot - farm_current_slot_before ))
farm_claim_emitted=$(( farm_claim_elapsed * farm_reward_rate_live ))
if (( farm_claim_emitted > farm_reward_budget_after_fund )); then
  farm_claim_emitted="$farm_reward_budget_after_fund"
fi
farm_claim_scaled=$(( farm_claim_emitted * farm_reward_index_scale + farm_baseline_reward_index_remainder ))
farm_claim_index_delta=0
farm_reward_index_remainder_after_claim="$farm_baseline_reward_index_remainder"
if (( farm_total_staked_after_stake > 0 )); then
  farm_claim_index_delta=$(( farm_claim_scaled / farm_total_staked_after_stake ))
  farm_reward_index_remainder_after_claim=$(( farm_claim_scaled - farm_claim_index_delta * farm_total_staked_after_stake ))
fi
farm_global_reward_index_after_claim=$(( farm_baseline_global_reward_index + farm_claim_index_delta ))
farm_reward_budget_after_claim=$(( farm_reward_budget_after_fund - farm_claim_emitted ))
farm_expected_claim=$(( farm_stake_amount * (farm_global_reward_index_after_claim - farm_position_reward_debt_after_stake) / farm_reward_index_scale ))
if (( farm_expected_claim < 0 )); then
  farm_expected_claim=0
fi
farm_position_reward_debt_after_claim="$farm_global_reward_index_after_claim"
farm_expected_stake=$(( farm_stake_amount - farm_unstake_amount ))
farm_unstake_emitted=$(( (farm_unstake_slot - farm_claim_slot) * farm_reward_rate_live ))
if (( farm_unstake_emitted > farm_reward_budget_after_claim )); then
  farm_unstake_emitted="$farm_reward_budget_after_claim"
fi
farm_unstake_scaled=$(( farm_unstake_emitted * farm_reward_index_scale + farm_reward_index_remainder_after_claim ))
farm_unstake_index_delta=0
if (( farm_total_staked_after_stake > 0 )); then
  farm_unstake_index_delta=$(( farm_unstake_scaled / farm_total_staked_after_stake ))
fi
farm_global_reward_index_after_unstake=$(( farm_global_reward_index_after_claim + farm_unstake_index_delta ))
farm_expected_accrued=$(( farm_stake_amount * (farm_global_reward_index_after_unstake - farm_position_reward_debt_after_claim) / farm_reward_index_scale ))
if (( farm_expected_accrued < 0 )); then
  farm_expected_accrued=0
fi
farm_expected_total_staked=$(( farm_baseline_total_staked + farm_expected_stake ))
farm_expected_reward_budget=$(( farm_reward_budget_after_claim - farm_unstake_emitted ))
farm_expected_reward_distributed=$(( farm_baseline_reward_distributed + farm_expected_claim ))
perps_expected_funding_sync=$(( perps_funding_bps * (perps_funding_mark_price_bps - perps_funding_index_price_bps) / 10000 ))
if (( perps_expected_funding_sync <= 0 )); then
  echo "invalid perps smoke parameters: funding settlement rounded to zero" >&2
  exit 1
fi
perps_abs_size="$perps_size"
if (( perps_abs_size < 0 )); then
  perps_abs_size=$(( 0 - perps_abs_size ))
fi
perps_expected_realized_pnl=$(( perps_size * (perps_exit_mark_price_bps - perps_entry_price_bps) / 10000 ))
perps_margin_after_remove=$(( perps_initial_collateral + perps_add_collateral - perps_remove_collateral ))
perps_bucket_payout_cap=$(( perps_abs_size * 8000 / 10000 ))
perps_expected_remove_payout="$perps_remove_collateral"
perps_bucket_1_deposits_after_funding=$(( risk_bucket_1_bootstrap_deposit + perps_initial_collateral + perps_add_collateral ))
if (( perps_expected_remove_payout > perps_bucket_payout_cap )); then
  perps_expected_remove_payout="$perps_bucket_payout_cap"
fi
if (( perps_expected_remove_payout > perps_bucket_1_deposits_after_funding )); then
  perps_expected_remove_payout="$perps_bucket_1_deposits_after_funding"
fi
perps_expected_close_payout=$(( perps_margin_after_remove + perps_expected_realized_pnl ))
if (( perps_expected_close_payout < 0 )); then
  perps_expected_close_payout=0
fi
perps_bucket_1_deposits_before_close=$(( perps_bucket_1_deposits_after_funding - perps_expected_remove_payout ))
if (( perps_expected_close_payout > perps_bucket_payout_cap )); then
  perps_expected_close_payout="$perps_bucket_payout_cap"
fi
if (( perps_expected_close_payout > perps_bucket_1_deposits_before_close )); then
  perps_expected_close_payout="$perps_bucket_1_deposits_before_close"
fi
perps_expected_realized_pnl=$(( perps_expected_close_payout - perps_margin_after_remove ))
perps_position_1_expected_payouts=$(( perps_expected_remove_payout + perps_expected_close_payout ))
perps_liquidation_unrealized_pnl=$(( perps_size * (perps_liquidation_stress_mark_price_bps - perps_entry_price_bps) / 10000 ))
perps_liquidation_equity=$(( perps_liquidation_collateral + perps_liquidation_unrealized_pnl ))
perps_liquidation_maintenance=$(( (perps_abs_size * perps_maintenance_margin_bps + 9999) / 10000 ))
if (( perps_liquidation_equity < 0 || perps_liquidation_equity >= perps_liquidation_maintenance )); then
  echo "invalid perps liquidation configuration for smoke: stress pass must leave non-negative equity below maintenance" >&2
  exit 1
fi
perps_liquidation_keeper_reward=$(( perps_liquidation_collateral * perps_liquidation_fee_bps / 10000 ))
if (( perps_liquidation_keeper_reward > perps_liquidation_collateral )); then
  perps_liquidation_keeper_reward="$perps_liquidation_collateral"
fi
perps_liquidation_owner_residual=$(( perps_liquidation_equity - perps_liquidation_keeper_reward ))
if (( perps_liquidation_owner_residual < 0 )); then
  perps_liquidation_owner_residual=0
fi
perps_bucket_1_deposits_after_close=$(( perps_bucket_1_deposits_before_close - perps_expected_close_payout ))
perps_liquidation_payout_cap="$perps_bucket_payout_cap"
perps_liquidation_payouts=$(( perps_liquidation_keeper_reward + perps_liquidation_owner_residual ))
if (( perps_liquidation_payouts > perps_liquidation_payout_cap )); then
  perps_liquidation_payouts="$perps_liquidation_payout_cap"
fi
perps_bucket_1_deposits_after_liquidation_open=$(( perps_bucket_1_deposits_after_close + perps_liquidation_collateral ))
if (( perps_liquidation_payouts > perps_bucket_1_deposits_after_liquidation_open )); then
  perps_liquidation_payouts="$perps_bucket_1_deposits_after_liquidation_open"
fi
if (( perps_liquidation_keeper_reward > perps_liquidation_payouts )); then
  perps_liquidation_keeper_reward="$perps_liquidation_payouts"
fi
perps_liquidation_owner_residual=$(( perps_liquidation_payouts - perps_liquidation_keeper_reward ))
perps_liquidation_realized_pnl=$(( perps_liquidation_payouts - perps_liquidation_collateral ))
perps_bucket_1_expected_deposits=$(( perps_bucket_1_deposits_after_liquidation_open - perps_liquidation_payouts ))
perps_bucket_1_expected_payouts=$(( perps_position_1_expected_payouts + perps_liquidation_payouts ))

options_shout_floor_bps="$options_shout_record_mark_bps"
if (( options_shout_exercise_mark_bps > options_shout_floor_bps )); then
  options_shout_floor_bps="$options_shout_exercise_mark_bps"
fi
options_shout_intrinsic_bps=$(( options_shout_floor_bps - options_shout_strike_bps ))
options_shout_desired_payout=0
if (( options_shout_intrinsic_bps > 0 )); then
  options_shout_desired_payout=$(( options_shout_notional * options_shout_intrinsic_bps / 10000 ))
fi
options_bucket_2_after_shout_buy=$(( risk_bucket_2_bootstrap_deposit + options_shout_premium_paid + options_shout_collateral_locked ))
options_shout_payout_cap=$(( options_shout_notional * 10000 / 10000 ))
options_shout_settled_payout="$options_shout_desired_payout"
if (( options_shout_settled_payout > options_shout_payout_cap )); then
  options_shout_settled_payout="$options_shout_payout_cap"
fi
if (( options_shout_settled_payout > options_bucket_2_after_shout_buy )); then
  options_shout_settled_payout="$options_bucket_2_after_shout_buy"
fi
options_bucket_2_after_shout_exercise=$(( options_bucket_2_after_shout_buy - options_shout_settled_payout ))

options_outperformance_delta_bps=$(( options_outperformance_final_mark_bps - options_outperformance_final_quote_mark_bps ))
if (( options_outperformance_delta_bps < 0 )); then
  options_outperformance_delta_bps=0
fi
options_outperformance_desired_payout=$(( options_outperformance_notional * options_outperformance_delta_bps * options_collateral_multiplier_bps / 10000 / 10000 ))
options_bucket_2_after_outperformance_buy=$(( options_bucket_2_after_shout_exercise + options_outperformance_premium_paid + options_outperformance_collateral_locked ))
options_outperformance_payout_cap=$(( options_outperformance_notional * 10000 / 10000 ))
options_outperformance_settled_payout="$options_outperformance_desired_payout"
if (( options_outperformance_settled_payout > options_outperformance_payout_cap )); then
  options_outperformance_settled_payout="$options_outperformance_payout_cap"
fi
if (( options_outperformance_settled_payout > options_bucket_2_after_outperformance_buy )); then
  options_outperformance_settled_payout="$options_bucket_2_after_outperformance_buy"
fi
options_bucket_2_expected_deposits=$(( options_bucket_2_after_outperformance_buy - options_outperformance_settled_payout ))
options_bucket_2_expected_payouts=$(( options_shout_settled_payout + options_outperformance_settled_payout ))

cover_expected_claim_payout="$cover_payout_amount"
cover_bucket_3_after_register=$(( risk_bucket_3_bootstrap_deposit + cover_premium_paid ))
cover_payout_cap=$(( cover_notional * 7000 / 10000 ))
if (( cover_expected_claim_payout > cover_payout_cap )); then
  cover_expected_claim_payout="$cover_payout_cap"
fi
if (( cover_expected_claim_payout > cover_bucket_3_after_register )); then
  cover_expected_claim_payout="$cover_bucket_3_after_register"
fi
cover_bucket_3_expected_deposits=$(( cover_bucket_3_after_register - cover_expected_claim_payout ))

risk_bucket_1_expected_json="$(jq -cn \
  --argjson deposits "$perps_bucket_1_expected_deposits" \
  --argjson payouts "$perps_bucket_1_expected_payouts" \
  '[ 1, $deposits, 0, 0, 8000, 0, 1500, $payouts, 0, $deposits, 0, 0 ]')"
risk_bucket_2_expected_json="$(jq -cn \
  --argjson deposits "$options_bucket_2_expected_deposits" \
  --argjson payouts "$options_bucket_2_expected_payouts" \
  '[ 1, $deposits, 0, 0, 10000, 10000, 10000, $payouts, 0, $deposits, 0, 0 ]')"
risk_bucket_3_expected_json="$(jq -cn \
  --argjson deposits "$cover_bucket_3_expected_deposits" \
  --argjson payouts "$cover_expected_claim_payout" \
  '[ 1, $deposits, 0, 0, 7000, 10000, 10000, $payouts, 0, $deposits, 0, 0 ]')"
risk_vault_state_expected_json="$(jq -cn \
  --argjson total_deposits $(( perps_bucket_1_expected_deposits + options_bucket_2_expected_deposits + cover_bucket_3_expected_deposits )) \
  --argjson total_payouts $(( perps_bucket_1_expected_payouts + options_bucket_2_expected_payouts + cover_expected_claim_payout )) \
  '[ $total_deposits, 0, 0, $total_payouts, 0, 0, 0, 3 ]')"
job_mirror_result_json="$(contract_view_result_json "$job_mirror_view_json")"
automation_retry_run_slot="$(jq -er '.[9]' <<<"$job_mirror_result_json")"
automation_expected_next_slot="$(jq -er '.[5]' <<<"$job_mirror_result_json")"
automation_min_next_slot=$(( automation_retry_run_slot + automation_cron_interval_slots ))
if (( automation_expected_next_slot < automation_min_next_slot )); then
  echo "local automation next slot $automation_expected_next_slot is before minimum cron slot $automation_min_next_slot" >&2
  exit 1
fi
automation_expected_run_count=2
n3x_expected_net_usdt=$(( n3x_usdt_in - n3x_expected_mint_fee_usdt ))
n3x_expected_net_usdc=$(( n3x_usdc_in - n3x_expected_mint_fee_usdc ))
n3x_expected_net_kusd=$(( n3x_kusd_in - n3x_expected_mint_fee_kusd ))
n3x_expected_redeem_fee_usdt=$(( n3x_expected_net_usdt * n3x_redeem_fee_bps / 10000 ))
n3x_expected_redeem_fee_usdc=$(( n3x_expected_net_usdc * n3x_redeem_fee_bps / 10000 ))
n3x_expected_redeem_fee_kusd=$(( n3x_expected_net_kusd * n3x_redeem_fee_bps / 10000 ))
n3x_expected_basket_usdt=0
n3x_expected_basket_usdc=0
n3x_expected_basket_kusd=0
n3x_expected_redeem_fees=$(( n3x_expected_redeem_fee_usdt + n3x_expected_redeem_fee_usdc + n3x_expected_redeem_fee_kusd ))

if ! jq -e \
  --argjson expected_fee_pips "$pool_fee_pips" \
  --argjson expected_bin_step "$pool_bin_step" \
  --argjson expected_active_bin "$expected_active_bin" \
  --argjson expected_active_liquidity "$expected_active_liquidity" \
  --argjson expected_active_share_supply "$expected_active_share_supply" \
  --argjson expected_pool_reserve_base "$expected_pool_reserve_base" \
  --argjson expected_pool_reserve_quote "$expected_pool_reserve_quote" \
  --argjson expected_impact_cap_bps "$pool_impact_cap_bps" \
  --argjson expected_min_reserve_base "$pool_min_reserve_base" \
  --argjson expected_min_reserve_quote "$pool_min_reserve_quote" \
  --argjson expected_max_bins_per_swap "$pool_max_bins_per_swap" \
  --argjson expected_bin_liquidity_cap "$pool_bin_liquidity_cap" \
  --argjson expected_n3x_basket_usdt "$n3x_expected_basket_usdt" \
  --argjson expected_n3x_basket_usdc "$n3x_expected_basket_usdc" \
  --argjson expected_n3x_basket_kusd "$n3x_expected_basket_kusd" \
  --argjson expected_n3x_mint_fee_bps "$n3x_mint_fee_bps" \
  --argjson expected_n3x_redeem_fee_bps "$n3x_redeem_fee_bps" \
  --argjson expected_n3x_mint_fees "$n3x_expected_mint_fee" \
  --argjson expected_n3x_redeem_fees "$n3x_expected_redeem_fees" \
  --argjson expected_n3x_target_usdt_bps "$n3x_target_usdt_bps" \
  --argjson expected_n3x_target_usdc_bps "$n3x_target_usdc_bps" \
  --argjson expected_n3x_target_kusd_bps "$n3x_target_kusd_bps" \
  '
    .soraswap_n3x_hub_initialized == 1 and
    .soraswap_n3x_basket_usdt == $expected_n3x_basket_usdt and
    .soraswap_n3x_basket_usdc == $expected_n3x_basket_usdc and
    .soraswap_n3x_basket_kusd == $expected_n3x_basket_kusd and
    .soraswap_n3x_total_n3x == 0 and
    .soraswap_n3x_mint_fee_bps == $expected_n3x_mint_fee_bps and
    .soraswap_n3x_redeem_fee_bps == $expected_n3x_redeem_fee_bps and
    .soraswap_n3x_mint_fees_accrued == $expected_n3x_mint_fees and
    .soraswap_n3x_redeem_fees_accrued == $expected_n3x_redeem_fees and
    .soraswap_n3x_target_usdt_bps == $expected_n3x_target_usdt_bps and
    .soraswap_n3x_target_usdc_bps == $expected_n3x_target_usdc_bps and
    .soraswap_n3x_target_kusd_bps == $expected_n3x_target_kusd_bps and
    .soraswap_dlmm_pool_initialized == 1 and
    .soraswap_dlmm_pool_active_bin == $expected_active_bin and
    .soraswap_dlmm_pool_fee_pips == $expected_fee_pips and
    .soraswap_dlmm_pool_bin_step == $expected_bin_step and
    .soraswap_dlmm_pool_reserve_base >= $expected_min_reserve_base and
    .soraswap_dlmm_pool_reserve_quote >= $expected_min_reserve_quote and
    (.soraswap_dlmm_pool_reserve_base + .soraswap_dlmm_pool_reserve_quote) == $expected_active_liquidity and
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
  echo "local decoded contract state did not match expected post-smoke values" >&2
  jq '.' <<<"$decoded_state_ints" >&2
  exit 1
fi

assert_view_result_equals "dlmm router contract binding" "$router_contract_binding_view_json" '1'
assert_view_result_equals "dlmm router execution binding" "$router_execution_view_json" '1'

if [[ "$smoke_scope" != "foundation" ]]; then
if ! jq -e \
  --argjson expected_launchpad_payment "$launchpad_payment_amount" \
  --argjson expected_launchpad_sale "$launchpad_payment_amount" \
  --argjson expected_launchpad_claim_inventory 0 \
  --argjson expected_launchpad_claimed_supply "$launchpad_payment_amount" \
  --argjson expected_launchpad_refunded_payment 0 \
  --argjson expected_launchpad_seed_executor_bound 1 \
  --argjson expected_launchpad_activation_value "$launchpad_expected_activation_value" \
  --argjson expected_launchpad_claim_start_slot 0 \
  --argjson expected_launchpad_claim_end_slot 0 \
  --argjson expected_seed_bin_id "$launchpad_seed_bin_id" \
  --argjson expected_seed_payment_amount "$launchpad_seed_payment_amount" \
  --argjson expected_seed_sale_amount "$launchpad_seed_sale_amount" \
  --argjson expected_refund_payment_amount "$refund_payment_amount" \
  --argjson expected_referral_claim_threshold "$referral_claim_threshold" \
  --argjson expected_referral_direct_share_bps "$referral_direct_share_bps" \
  --argjson expected_referral_parent_share_bps "$referral_parent_share_bps" \
  --argjson expected_referral_member_total "$referral_expected_member_share" \
  --argjson expected_referral_parent_total "$referral_expected_parent_share" \
  --argjson expected_farm_accrued "$farm_expected_accrued" \
  --argjson expected_farm_stake "$farm_expected_stake" \
  --argjson expected_farm_claim "$farm_expected_claim" \
  --argjson expected_farm_total_staked "$farm_expected_total_staked" \
  --argjson expected_farm_reward_budget "$farm_expected_reward_budget" \
  --argjson expected_farm_reward_distributed "$farm_expected_reward_distributed" \
  --argjson expected_farm_reward_rate "$farm_reward_rate_live" \
  --argjson expected_automation_next_slot "$automation_expected_next_slot" \
  --argjson expected_automation_retry_run_slot "$automation_retry_run_slot" \
  --argjson expected_automation_max_retries "$automation_max_retries" \
  --argjson expected_automation_cron_interval_slots "$automation_cron_interval_slots" \
  --argjson expected_automation_retry_delay_slots "$automation_retry_delay_slots" \
  --argjson expected_automation_run_count "$automation_expected_run_count" \
  '
    .soraswap_launchpad_seed_registered == 1 and
    .soraswap_launchpad_raised == $expected_launchpad_payment and
    .soraswap_launchpad_sold == $expected_launchpad_sale and
    .soraswap_launchpad_closed == 1 and
    .soraswap_launchpad_successful == 1 and
    .soraswap_launchpad_seeded == 1 and
    .soraswap_launchpad_seed_inventory == 0 and
    .soraswap_launchpad_seed_bin_id == $expected_seed_bin_id and
    .soraswap_launchpad_seed_payment_amount == $expected_seed_payment_amount and
    .soraswap_launchpad_seed_sale_amount == $expected_seed_sale_amount and
    .soraswap_launchpad_seed_payment_used == $expected_seed_payment_amount and
    .soraswap_launchpad_seed_sale_used == $expected_seed_sale_amount and
    .soraswap_launchpad_claim_inventory == $expected_launchpad_claim_inventory and
    .soraswap_launchpad_claimed_supply == $expected_launchpad_claimed_supply and
    .soraswap_launchpad_refunded_payment == $expected_launchpad_refunded_payment and
    .soraswap_launchpad_seed_executor_bound == $expected_launchpad_seed_executor_bound and
    .soraswap_launchpad_seed_activation_value == $expected_launchpad_activation_value and
    .soraswap_launchpad_claim_start_slot == $expected_launchpad_claim_start_slot and
    .soraswap_launchpad_claim_end_slot == $expected_launchpad_claim_end_slot and
    .soraswap_launchpad_allocation_registered == 1 and
    .soraswap_launchpad_allocation_payment_amount == $expected_refund_payment_amount and
    .soraswap_launchpad_allocation_sale_amount == $expected_refund_payment_amount and
    .soraswap_launchpad_allocation_claimed == 0 and
    .soraswap_launchpad_allocation_refunded == 1 and
    .soraswap_referral_bound == 1 and
    .soraswap_referral_parent_bound == 1 and
    .soraswap_referral_claim_threshold == $expected_referral_claim_threshold and
    .soraswap_referral_direct_share_bps == $expected_referral_direct_share_bps and
    .soraswap_referral_parent_share_bps == $expected_referral_parent_share_bps and
    .soraswap_referral_accrued == 0 and
    .soraswap_referral_total_accrued == $expected_referral_member_total and
    .soraswap_referral_total_claimed == $expected_referral_member_total and
    .soraswap_referral_claim_count == 1 and
    .soraswap_referral_parent_accrued == 0 and
    .soraswap_referral_parent_total_accrued == $expected_referral_parent_total and
    .soraswap_referral_parent_total_claimed == $expected_referral_parent_total and
    .soraswap_referral_parent_claim_count == 1 and
    .soraswap_farm_position_registered == 1 and
    .soraswap_farm_stake == $expected_farm_stake and
    .soraswap_farm_accrued == $expected_farm_accrued and
    .soraswap_farm_claimed == $expected_farm_claim and
    .soraswap_farm_total_staked == $expected_farm_total_staked and
    .soraswap_farm_reward_budget == $expected_farm_reward_budget and
    .soraswap_farm_reward_distributed == $expected_farm_reward_distributed and
    .soraswap_farm_reward_rate == $expected_farm_reward_rate and
    .soraswap_automation_job_registered == 1 and
    .soraswap_automation_executor_bound == 1 and
    .soraswap_automation_job_payload_hash == 123456 and
    .soraswap_automation_job_status == 1 and
    .soraswap_automation_retry_count == 1 and
    .soraswap_automation_next_slot == $expected_automation_next_slot and
    .soraswap_automation_cron_interval_slots == $expected_automation_cron_interval_slots and
    .soraswap_automation_max_retries == $expected_automation_max_retries and
    .soraswap_automation_retry_delay_slots == $expected_automation_retry_delay_slots and
    .soraswap_automation_last_run_slot == $expected_automation_retry_run_slot and
    .soraswap_automation_run_count == $expected_automation_run_count
  ' <<<"$decoded_state_ints" >/dev/null; then
  echo "local decoded full-scope contract state did not match expected post-smoke values" >&2
  jq '.' <<<"$decoded_state_ints" >&2
  exit 1
fi

assert_view_result_equals "risk bucket 1" "$risk_bucket_1_view_json" "$risk_bucket_1_expected_json"
assert_view_result_equals "risk bucket 2" "$risk_bucket_2_view_json" "$risk_bucket_2_expected_json"
assert_view_result_equals "risk bucket 3" "$risk_bucket_3_view_json" "$risk_bucket_3_expected_json"
assert_view_result_equals "risk bucket 1 automation" "$risk_bucket_1_automation_view_json" "$risk_bucket_1_automation_expected_json"
assert_view_result_equals "risk bucket 2 automation" "$risk_bucket_2_automation_view_json" "$risk_bucket_2_automation_expected_json"
assert_view_result_equals "risk bucket 3 automation" "$risk_bucket_3_automation_view_json" "$risk_bucket_3_automation_expected_json"
assert_view_result_equals "risk vault state" "$risk_vault_state_view_json" "$risk_vault_state_expected_json"
assert_view_result_equals "risk bucket 1 liability" "$risk_bucket_1_liability_view_json" "$(jq -cn --argjson payouts "$perps_position_1_expected_payouts" '[ 2, 0, 0, $payouts ]')"
assert_view_result_equals "risk bucket 1 liquidation liability" "$risk_bucket_1_liquidation_liability_view_json" "$(jq -cn --argjson payouts "$perps_liquidation_payouts" '[ 2, 0, 0, $payouts ]')"
assert_view_result_equals "risk bucket 2 shout liability" "$risk_bucket_2_shout_liability_view_json" "$(jq -cn --argjson payouts "$options_shout_settled_payout" '[ 2, 0, 0, $payouts ]')"
assert_view_result_equals "risk bucket 2 outperformance liability" "$risk_bucket_2_outperformance_liability_view_json" "$(jq -cn --argjson payouts "$options_outperformance_settled_payout" '[ 2, 0, 0, $payouts ]')"
assert_view_result_equals "risk bucket 3 liability" "$risk_bucket_3_liability_view_json" "$(jq -cn --argjson payouts "$cover_expected_claim_payout" '[ 2, 0, 0, $payouts ]')"
assert_view_result_equals "perps engine config" "$perps_engine_config_view_json" "$(jq -cn --arg settlement_asset "$usdt_id" --arg risk_vault "$risk_vault_contract_blob_hex" --argjson next_position_id $(( perps_position_id + 2 )) '[ $settlement_asset, $risk_vault, 0, 2, $next_position_id, 201, 202, 6 ]')"
assert_view_result_equals "perps market state" "$perps_market_state_view_json" "$(jq -cn --argjson open_interest_cap "$perps_open_interest_cap" --argjson max_leverage_bps "$perps_max_leverage_bps" --argjson maintenance_margin_bps "$perps_maintenance_margin_bps" --argjson liquidation_fee_bps "$perps_liquidation_fee_bps" --argjson funding_bps "$perps_funding_bps" --argjson funding_interval_slots "$perps_funding_interval_slots" --argjson oracle_stale_slots "$perps_oracle_stale_slots" --argjson backlog_limit "$perps_backlog_limit" '[ 1, 1, 0, $open_interest_cap, $max_leverage_bps, $maintenance_margin_bps, $liquidation_fee_bps, $funding_bps, $funding_interval_slots, $oracle_stale_slots, 0, 0, $backlog_limit ]')"
assert_view_result_equals "perps risk state" "$perps_market_risk_view_json" "$(jq -cn --argjson open_interest_cap "$perps_open_interest_cap" '[ 0, $open_interest_cap, 0, 0, 0, 0, 0, 0 ]')"
assert_view_result_equals "perps automation" "$perps_automation_view_json" '[1,201,202,4,6,0,0]'
assert_view_result_equals "perps position state" "$perps_position_state_view_json" "$(jq -cn --argjson realized_pnl "$perps_expected_realized_pnl" --argjson exit_price "$perps_exit_mark_price_bps" '[ 1, 2, 1, 0, 0, 0, $realized_pnl, 10000, $exit_price, $exit_price, 0 ]')"
assert_view_result_equals "perps recovery position state" "$perps_recovery_position_state_view_json" "$(jq -cn --argjson size "$perps_size" --argjson margin "$perps_liquidation_collateral" --argjson price "$perps_liquidation_healthy_mark_price_bps" '[ 1, 1, 1, $size, $margin, 0, 0, 10000, $price, $price, 0 ]')"
assert_view_result_equals "perps recovery position liquidation state" "$perps_recovery_position_liquidation_view_json" '[0,0,0]'
assert_view_result_equals "perps liquidation position state" "$perps_liquidation_position_state_view_json" "$(jq -cn --argjson realized_pnl "$perps_liquidation_realized_pnl" --argjson price "$perps_liquidation_stress_mark_price_bps" '[ 1, 4, 1, 0, 0, 0, $realized_pnl, 10000, $price, $price, 0 ]')"
assert_view_result_equals "perps liquidation position liquidation state" "$perps_liquidation_position_liquidation_view_json" "$(jq -cn --argjson keeper_reward "$perps_liquidation_keeper_reward" --argjson owner_residual "$perps_liquidation_owner_residual" '[ 0, $keeper_reward, $owner_residual ]')"
assert_view_result_equals "perps liquidation state" "$perps_liquidation_state_view_json" '[0,0,0,1,0,0,1]'
assert_view_result_equals "options manager config" "$options_manager_config_view_json" "$(jq -cn --arg settlement_asset "$usdt_id" '[ $settlement_asset, 1, 3, 3, 211, 212, 5, 8, 0 ]')"
assert_view_result_equals "options shout template" "$options_shout_template_view_json" "$(jq -cn --argjson tenor "$options_shout_tenor_slots" --argjson strike "$options_shout_strike_bps" --argjson collateral_multiplier "$options_collateral_multiplier_bps" --argjson base_premium "$options_shout_base_premium_bps" '[ 1, 1, $tenor, $strike, $collateral_multiplier, $base_premium, 1, 1 ]')"
assert_view_result_equals "options outperformance template" "$options_outperformance_template_view_json" "$(jq -cn --argjson tenor "$options_outperformance_tenor_slots" --argjson strike "$options_outperformance_strike_bps" --argjson collateral_multiplier "$options_collateral_multiplier_bps" --argjson base_premium "$options_outperformance_base_premium_bps" '[ 1, 2, $tenor, $strike, $collateral_multiplier, $base_premium, 1, 1 ]')"
assert_view_result_equals "options shout series" "$options_shout_series_view_json" "$(jq -cn --argjson expiry_slot "$options_shout_expiry_slot" --argjson max_notional "$options_shout_max_notional" --argjson premium_bps "$options_shout_base_premium_bps" --argjson strike_bps "$options_shout_strike_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" '[ 1, 1, 1, $expiry_slot, $max_notional, $premium_bps, $strike_bps, $collateral_multiplier_bps, 1, 0, 0 ]')"
assert_view_result_equals "options outperformance series" "$options_outperformance_series_view_json" "$(jq -cn --argjson expiry_slot "$options_outperformance_expiry_slot" --argjson max_notional "$options_outperformance_max_notional" --argjson premium_bps "$options_outperformance_base_premium_bps" --argjson strike_bps "$options_outperformance_strike_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" --argjson final_mark "$options_outperformance_final_mark_bps" --argjson final_quote_mark "$options_outperformance_final_quote_mark_bps" '[ 1, 2, 2, $expiry_slot, $max_notional, $premium_bps, $strike_bps, $collateral_multiplier_bps, 3, $final_mark, $final_quote_mark ]')"
assert_view_result_equals "options manager automation" "$options_manager_automation_view_json" '[1,211,212,5,8,0,0]'
options_factory_outperformance_last_settlement_slot="$(contract_view_result_json "$options_factory_outperformance_series_view_json" | jq -er '.[9]')"
if (( options_factory_outperformance_last_settlement_slot < options_outperformance_expiry_slot )); then
  echo "local smoke options factory outperformance settlement slot precedes expiry: settlement=$options_factory_outperformance_last_settlement_slot expiry=$options_outperformance_expiry_slot" >&2
  exit 1
fi
assert_view_result_equals "options factory config" "$options_factory_config_view_json" "$(jq -cn --arg settlement_asset "$usdt_id" --argjson next_position_id $(( options_outperformance_position_id + 1 )) '[ $settlement_asset, 0, $next_position_id, 213, 5, 8, 0 ]')"
assert_view_result_equals "options factory shout series" "$options_factory_shout_series_view_json" "$(jq -cn --argjson max_notional "$options_shout_max_notional" --argjson premium_bps "$options_shout_base_premium_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" --argjson pause_threshold_bps "$options_factory_pause_threshold_bps" --argjson bump_percent_bps "$options_factory_bump_percent_bps" '[ 1, 1, $max_notional, $premium_bps, $collateral_multiplier_bps, 0, 0, $pause_threshold_bps, $bump_percent_bps, 0 ]')"
assert_view_result_equals "options factory outperformance series" "$options_factory_outperformance_series_view_json" "$(jq -cn --argjson max_notional "$options_outperformance_max_notional" --argjson premium_bps "$options_outperformance_base_premium_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" --argjson pause_threshold_bps "$options_factory_pause_threshold_bps" --argjson bump_percent_bps "$options_factory_bump_percent_bps" --argjson last_settlement_slot "$options_factory_outperformance_last_settlement_slot" '[ 1, 2, $max_notional, $premium_bps, $collateral_multiplier_bps, 0, 0, $pause_threshold_bps, $bump_percent_bps, $last_settlement_slot ]')"
assert_view_result_equals "options factory automation" "$options_factory_automation_view_json" '[1,213,5,8,0,0,0]'
assert_view_result_equals "options factory shout position" "$options_factory_shout_position_view_json" "$(jq -cn --argjson premium "$options_shout_premium_paid" --argjson collateral_locked "$options_shout_collateral_locked" --argjson payout "$options_shout_settled_payout" --argjson notional "$options_shout_notional" '[ 1, 1, 1, $notional, $premium, $collateral_locked, 3, $payout, 1 ]')"
assert_view_result_equals "options factory outperformance position" "$options_factory_outperformance_position_view_json" "$(jq -cn --argjson premium "$options_outperformance_premium_paid" --argjson collateral_locked "$options_outperformance_collateral_locked" --argjson payout "$options_outperformance_settled_payout" --argjson notional "$options_outperformance_notional" '[ 1, 2, 2, $notional, $premium, $collateral_locked, 3, $payout, 1 ]')"
assert_view_result_equals "options vault shout state" "$options_vault_shout_state_view_json" "$(jq -cn --argjson collateral_locked $(( options_shout_collateral_locked - options_shout_settled_payout )) --argjson payout "$options_shout_settled_payout" '[ 1, $collateral_locked, 0, $payout, 0 ]')"
assert_view_result_equals "options vault outperformance state" "$options_vault_outperformance_state_view_json" "$(jq -cn --argjson collateral_locked $(( options_outperformance_collateral_locked - options_outperformance_settled_payout )) --argjson payout "$options_outperformance_settled_payout" '[ 1, $collateral_locked, 0, $payout, 0 ]')"
assert_view_result_equals "options vault shout position" "$options_vault_shout_position_view_json" "$(jq -cn --argjson collateral_locked $(( options_shout_collateral_locked - options_shout_settled_payout )) --argjson payout "$options_shout_settled_payout" '[ 1, 1, $collateral_locked, 0, $payout, 2 ]')"
assert_view_result_equals "options vault outperformance position" "$options_vault_outperformance_position_view_json" "$(jq -cn --argjson collateral_locked $(( options_outperformance_collateral_locked - options_outperformance_settled_payout )) --argjson payout "$options_outperformance_settled_payout" '[ 1, 2, $collateral_locked, 0, $payout, 2 ]')"
options_outperformance_product_settlement_slot="$(contract_view_result_json "$options_outperformance_product_view_json" | jq -er '.[1]')"
if (( options_outperformance_product_settlement_slot < options_outperformance_expiry_slot )); then
  echo "local smoke options outperformance product settlement slot precedes expiry: settlement=$options_outperformance_product_settlement_slot expiry=$options_outperformance_expiry_slot" >&2
  exit 1
fi
assert_view_result_equals "options shout product" "$options_shout_product_view_json" "$(jq -cn --argjson expiry_slot "$options_shout_expiry_slot" --argjson strike_bps "$options_shout_strike_bps" '[ 1, $expiry_slot, $strike_bps, 1 ]')"
assert_view_result_equals "options outperformance product" "$options_outperformance_product_view_json" "$(jq -cn --argjson settlement_slot "$options_outperformance_product_settlement_slot" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" '[ 1, $settlement_slot, $collateral_multiplier_bps, 2 ]')"
assert_view_result_equals "options shout product position" "$options_shout_product_position_view_json" "$(jq -cn --argjson notional "$options_shout_notional" --argjson strike_bps "$options_shout_strike_bps" --argjson shout_floor "$options_shout_floor_bps" --argjson last_mark "$options_shout_exercise_mark_bps" --argjson payout "$options_shout_desired_payout" '[ 1, 1, $notional, $strike_bps, $shout_floor, $last_mark, $payout, 2 ]')"
assert_view_result_equals "options outperformance product position" "$options_outperformance_product_position_view_json" "$(jq -cn --argjson notional "$options_outperformance_notional" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" --argjson final_mark "$options_outperformance_final_mark_bps" --argjson final_quote_mark "$options_outperformance_final_quote_mark_bps" --argjson payout "$options_outperformance_desired_payout" '[ 1, 2, $notional, $collateral_multiplier_bps, $final_mark, $final_quote_mark, $payout, 2 ]')"
assert_view_result_equals "cover manager config" "$cover_manager_config_view_json" "$(jq -cn --arg settlement_asset "$usdt_id" --arg risk_vault "$risk_vault_contract_blob_hex" --argjson required_observations "$cover_required_observations" --argjson stale_slots "$cover_oracle_stale_slots" '[ $settlement_asset, $risk_vault, 0, $required_observations, $stale_slots, 301, 3, 10, 0 ]')"
assert_view_result_equals "cover automation" "$cover_automation_view_json" '[1,301,3,10,0,0,0]'
cover_breach_elapsed_actual="$(contract_view_result_json "$cover_policy_view_json" | jq -er '.[8]')"
if (( cover_breach_elapsed_actual < cover_monitoring_window_slots )); then
  echo "local smoke cover breach elapsed $cover_breach_elapsed_actual is below monitoring window $cover_monitoring_window_slots" >&2
  exit 1
fi
assert_view_result_equals "cover policy" "$cover_policy_view_json" "$(jq -cn --argjson lower_bound "$cover_lower_bound" --argjson upper_bound "$cover_upper_bound" --argjson payout_amount "$cover_payout_amount" --argjson monitoring_window_slots "$cover_monitoring_window_slots" --argjson required_observations "$cover_policy_required_observations" --argjson covered_notional "$cover_notional" --argjson breach_elapsed "$cover_breach_elapsed_actual" --argjson last_observed_price "$cover_trigger_price" --argjson claim_payout "$cover_expected_claim_payout" '[ 1, 4, $lower_bound, $upper_bound, $payout_amount, $monitoring_window_slots, $required_observations, $covered_notional, $breach_elapsed, 3, $last_observed_price, $claim_payout ]')"
fi

assert_view_result_equals "intent state" "$intent_state_view_json" "$(jq -cn --argjson amount_in "$intent_amount_in" --argjson min_out "$intent_min_out" --argjson solver_fee_bps "$intent_solver_fee_bps" --argjson deadline_slot "$intent_deadline_slot" --argjson nonce "$intent_nonce" --argjson amount_out "$intent_amount_out" '[ 1, 2, $amount_in, $min_out, $solver_fee_bps, $deadline_slot, $nonce, 1, $amount_out ]')"
assert_view_result_equals "vault state" "$vault_state_view_json" "$(jq -cn --argjson strategy_code "$vault_strategy_code" --argjson async_redeem "$vault_async_redeem" --argjson assets "$(( vault_deposit_amount - vault_redeem_shares ))" '[ 1, $strategy_code, $async_redeem, $assets, $assets ]')"
assert_view_result_equals "vault position" "$vault_position_view_json" "$(( vault_deposit_amount - vault_redeem_shares ))"
assert_view_result_equals "operator state" "$operator_state_view_json" "$(jq -cn --argjson min_bond "$operator_min_bond" --argjson bonded "$operator_bond_amount" --argjson health "$operator_health_bps" --argjson slot "$operator_heartbeat_slot" '[ 1, $min_bond, $bonded, $health, $slot, 0, 0 ]')"
assert_view_result_equals "margin account health" "$margin_account_health_view_json" '[0,0,10000,1]'
assert_view_result_equals "rwa market state" "$rwa_market_state_view_json" "$(jq -cn --argjson nav "$rwa_report_nav_per_share" --argjson shares "$rwa_report_total_shares" '[ 1, $nav, $shares, 1 ]')"
assert_view_result_equals "dlmm hook quote" "$dlmm_hook_quote_view_json" "$(jq -cn --argjson amount_in "$dlmm_hook_amount_in" --argjson min_out "$dlmm_hook_min_out" --argjson amount_out "$dlmm_hook_amount_out" '[ 1, $amount_in, $min_out, $amount_in, $amount_out ]')"

report_dir="$SORASWAP_ROOT/deployments/local"
timestamp="$(env TZ=UTC date '+%Y%m%dT%H%M%SZ')"
latest_report="$report_dir/smoke.latest.json"
timestamped_report="$report_dir/smoke.${timestamp}.json"
mkdir -p "$report_dir"

report_json="$(jq -n \
  --arg generated_at "$timestamp" \
  --arg authority "$SORASWAP_AUTHORITY" \
  --arg client_config "$config" \
  --arg base_asset_alias "$SORASWAP_BASE_ASSET_ALIAS" \
  --arg xor_asset_id "$xor_id" \
  --arg usdt_asset_id "$usdt_id" \
  --argjson before_n3x "$before_n3x" \
  --argjson after_mint_n3x "$after_mint_n3x" \
  --argjson after_burn_n3x "$after_burn_n3x" \
  --argjson expected_swap_out "$expected_swap_out" \
  --argjson expected_active_bin "$expected_active_bin" \
  --argjson expected_active_liquidity "$expected_active_liquidity" \
  --argjson expected_active_share_supply "$expected_active_share_supply" \
  --argjson expected_pool_reserve_base "$expected_pool_reserve_base" \
  --argjson expected_pool_reserve_quote "$expected_pool_reserve_quote" \
  --argjson expected_launchpad_activation_value "$launchpad_expected_activation_value" \
  --argjson expected_referral_member_total "$referral_expected_member_share" \
  --argjson expected_referral_parent_total "$referral_expected_parent_share" \
  --argjson expected_farm_accrued "$farm_expected_accrued" \
  --argjson expected_farm_stake "$farm_expected_stake" \
  --argjson expected_farm_claim "$farm_expected_claim" \
  --argjson expected_perps_funding_sync "$perps_expected_funding_sync" \
  --argjson expected_perps_remove_payout "$perps_expected_remove_payout" \
  --argjson expected_perps_realized_pnl "$perps_expected_realized_pnl" \
  --argjson expected_perps_close_payout "$perps_expected_close_payout" \
  --argjson expected_perps_liquidation_keeper_reward "$perps_liquidation_keeper_reward" \
  --argjson expected_perps_liquidation_owner_residual "$perps_liquidation_owner_residual" \
  --argjson expected_perps_liquidation_realized_pnl "$perps_liquidation_realized_pnl" \
  --argjson expected_perps_liquidation_payout "$perps_liquidation_payouts" \
  --argjson expected_options_shout_payout "$options_shout_settled_payout" \
  --argjson expected_options_outperformance_payout "$options_outperformance_settled_payout" \
  --argjson expected_cover_claim_payout "$cover_expected_claim_payout" \
  --argjson expected_risk_bucket_1 "$(jq -c . <<<"$risk_bucket_1_expected_json")" \
  --argjson expected_risk_bucket_2 "$(jq -c . <<<"$risk_bucket_2_expected_json")" \
  --argjson expected_risk_bucket_3 "$(jq -c . <<<"$risk_bucket_3_expected_json")" \
  --argjson expected_risk_vault_state "$(jq -c . <<<"$risk_vault_state_expected_json")" \
  --argjson expected_automation_next_slot "$automation_expected_next_slot" \
  --argjson expected_automation_retry_run_slot "$automation_retry_run_slot" \
  --argjson expected_automation_cron_interval_slots "$automation_cron_interval_slots" \
  --argjson expected_automation_run_count "$automation_expected_run_count" \
  --argjson expected_n3x_mint_fee "$n3x_expected_mint_fee" \
  --argjson expected_n3x_redeem_fees "$n3x_expected_redeem_fees" \
  --arg n3x_config_tx_hash "$n3x_config_tx_hash" \
  --arg mint_tx_hash "$mint_tx_hash" \
  --arg burn_tx_hash "$burn_tx_hash" \
  --arg dlmm_swap_tx_hash "$dlmm_swap_tx_hash" \
  --arg dlmm_collect_position_fees_tx_hash "$dlmm_collect_position_fees_tx_hash" \
  --arg dlmm_remove_position_tx_hash "$dlmm_remove_position_tx_hash" \
  --arg launchpad_tx_hash "$launchpad_tx_hash" \
  --arg launchpad_config_vesting_tx_hash "$launchpad_config_vesting_tx_hash" \
  --arg launchpad_close_tx_hash "$launchpad_close_tx_hash" \
  --arg launchpad_claim_inventory_tx_hash "$launchpad_claim_inventory_tx_hash" \
  --arg launchpad_claim_tx_hash "$launchpad_claim_tx_hash" \
  --arg launchpad_seed_inventory_tx_hash "$launchpad_seed_inventory_tx_hash" \
  --arg launchpad_register_seed_tx_hash "$launchpad_register_seed_tx_hash" \
  --arg launchpad_seed_liquidity_tx_hash "$launchpad_seed_liquidity_tx_hash" \
  --arg launchpad_finalize_activation_tx_hash "$launchpad_finalize_activation_tx_hash" \
  --arg referral_config_tx_hash "$referral_config_tx_hash" \
  --arg referral_tiers_tx_hash "$referral_tiers_tx_hash" \
  --arg referral_parent_bind_tx_hash "$referral_parent_bind_tx_hash" \
  --arg referral_bind_tx_hash "$referral_bind_tx_hash" \
  --arg referral_accrue_tx_hash "$referral_accrue_tx_hash" \
  --arg referral_claim_tx_hash "$referral_claim_tx_hash" \
  --arg referral_parent_claim_tx_hash "$referral_parent_claim_tx_hash" \
  --arg farm_config_tx_hash "$farm_config_tx_hash" \
  --arg farm_fund_tx_hash "$farm_fund_tx_hash" \
  --arg farm_stake_tx_hash "$farm_stake_tx_hash" \
  --arg farm_sync_claim_tx_hash "$farm_sync_claim_tx_hash" \
  --arg farm_claim_tx_hash "$farm_claim_tx_hash" \
  --arg farm_sync_unstake_tx_hash "$farm_sync_unstake_tx_hash" \
  --arg farm_unstake_tx_hash "$farm_unstake_tx_hash" \
  --arg perps_open_tx_hash "$perps_open_tx_hash" \
  --arg perps_funding_tx_hash "$perps_funding_tx_hash" \
  --arg perps_add_margin_tx_hash "$perps_add_margin_tx_hash" \
  --arg perps_remove_margin_tx_hash "$perps_remove_margin_tx_hash" \
  --arg perps_close_tx_hash "$perps_close_tx_hash" \
  --arg perps_liquidation_open_tx_hash "$perps_liquidation_open_tx_hash" \
  --arg perps_liquidation_queue_tx_hash "$perps_liquidation_queue_tx_hash" \
  --arg perps_liquidation_recover_tx_hash "$perps_liquidation_recover_tx_hash" \
  --arg perps_liquidation_requeue_tx_hash "$perps_liquidation_requeue_tx_hash" \
  --arg perps_liquidation_execute_tx_hash "$perps_liquidation_execute_tx_hash" \
  --arg options_shout_buy_tx_hash "$options_shout_buy_tx_hash" \
  --arg options_shout_record_tx_hash "$options_shout_record_tx_hash" \
  --arg options_shout_exercise_tx_hash "$options_shout_exercise_tx_hash" \
  --arg options_outperformance_buy_tx_hash "$options_outperformance_buy_tx_hash" \
  --arg options_outperformance_settle_tx_hash "$options_outperformance_settle_tx_hash" \
  --arg options_outperformance_exercise_tx_hash "$options_outperformance_exercise_tx_hash" \
  --arg cover_register_tx_hash "$cover_register_tx_hash" \
  --arg cover_stale_reset_tx_hash "$cover_stale_reset_tx_hash" \
  --arg cover_trigger_1_tx_hash "$cover_trigger_1_tx_hash" \
  --arg cover_trigger_2_tx_hash "$cover_trigger_2_tx_hash" \
  --arg cover_trigger_3_tx_hash "$cover_trigger_3_tx_hash" \
  --arg cover_trigger_4_tx_hash "$cover_trigger_4_tx_hash" \
  --arg cover_claim_tx_hash "$cover_claim_tx_hash" \
  --arg job_enqueue_tx_hash "$job_enqueue_tx_hash" \
  --arg job_config_tx_hash "$job_config_tx_hash" \
  --arg job_assign_executor_tx_hash "$job_assign_executor_tx_hash" \
  --arg job_cron_tx_hash "$job_cron_tx_hash" \
  --arg job_dispatch_tx_hash "$job_dispatch_tx_hash" \
  --arg job_pause_tx_hash "$job_pause_tx_hash" \
  --arg job_resume_tx_hash "$job_resume_tx_hash" \
  --arg job_retry_tx_hash "$job_retry_tx_hash" \
  --arg job_retry_dispatch_tx_hash "$job_retry_dispatch_tx_hash" \
  --arg job_complete_tx_hash "$job_complete_tx_hash" \
  --arg refund_sale_init_tx_hash "$refund_sale_init_tx_hash" \
  --arg refund_sale_config_tx_hash "$refund_sale_config_tx_hash" \
  --arg refund_sale_contribute_tx_hash "$refund_sale_contribute_tx_hash" \
  --arg refund_sale_close_tx_hash "$refund_sale_close_tx_hash" \
  --arg refund_sale_refund_tx_hash "$refund_sale_refund_tx_hash" \
  --arg intent_open_tx_hash "$intent_open_tx_hash" \
  --arg intent_fill_tx_hash "$intent_fill_tx_hash" \
  --arg intent_replay_rejection "$intent_replay_rejection" \
  --arg vault_register_tx_hash "$vault_register_tx_hash" \
  --arg vault_deposit_tx_hash "$vault_deposit_tx_hash" \
  --arg vault_request_redeem_tx_hash "$vault_request_redeem_tx_hash" \
  --arg vault_claim_redeem_tx_hash "$vault_claim_redeem_tx_hash" \
  --arg operator_register_tx_hash "$operator_register_tx_hash" \
  --arg operator_bond_tx_hash "$operator_bond_tx_hash" \
  --arg operator_heartbeat_tx_hash "$operator_heartbeat_tx_hash" \
  --arg operator_claim_fees_tx_hash "$operator_claim_fees_tx_hash" \
  --arg operator_unbonded_rejection "$operator_unbonded_rejection" \
  --arg margin_register_market_tx_hash "$margin_register_market_tx_hash" \
  --arg margin_deposit_collateral_tx_hash "$margin_deposit_collateral_tx_hash" \
  --arg margin_lock_exposure_tx_hash "$margin_lock_exposure_tx_hash" \
  --arg margin_liquidate_account_tx_hash "$margin_liquidate_account_tx_hash" \
  --arg margin_unhealthy_withdraw_rejection "$margin_unhealthy_withdraw_rejection" \
  --arg rwa_issue_lot_tx_hash "$rwa_issue_lot_tx_hash" \
  --arg rwa_bind_share_asset_tx_hash "$rwa_bind_share_asset_tx_hash" \
  --arg rwa_report_nav_tx_hash "$rwa_report_nav_tx_hash" \
  --arg rwa_request_redemption_tx_hash "$rwa_request_redemption_tx_hash" \
  --arg rwa_settle_redemption_tx_hash "$rwa_settle_redemption_tx_hash" \
  --arg rwa_duplicate_issue_rejection "$rwa_duplicate_issue_rejection" \
  --arg dlmm_configure_hook_tx_hash "$dlmm_configure_hook_tx_hash" \
  --arg dlmm_place_limit_order_tx_hash "$dlmm_place_limit_order_tx_hash" \
  --arg dlmm_schedule_twamm_tx_hash "$dlmm_schedule_twamm_tx_hash" \
  --arg dlmm_record_execution_tx_hash "$dlmm_record_execution_tx_hash" \
  --arg dlmm_disabled_hook_rejection "$dlmm_disabled_hook_rejection" \
  --arg conditional_escrow_open_tx_hash "$conditional_escrow_open_tx_hash" \
  --arg conditional_escrow_execute_tx_hash "$conditional_escrow_execute_tx_hash" \
  --argjson trigger_registration_evidence "$trigger_registration_evidence_json" \
  --argjson conditional_escrow_completion "$conditional_escrow_completion_json" \
  --argjson epoch_auction_native_close_evidence "$epoch_auction_native_close_evidence_json" \
  --argjson n3x_quote_result "$(contract_view_result_json "$n3x_quote_view_json")" \
  --argjson redeem_quote_result "$(contract_view_result_json "$redeem_quote_view_json")" \
  --argjson router_bin_quote_result "$(contract_view_result_json "$router_bin_quote_view_json")" \
  --argjson n3x_assert_result "$(contract_view_result_json "$n3x_assert_view_json")" \
  --argjson n3x_mirror_result "$(contract_view_result_json "$n3x_mirror_view_json")" \
  --argjson router_assert_result "$(contract_view_result_json "$router_assert_view_json")" \
  --argjson router_contract_binding_result "$(contract_view_result_json "$router_contract_binding_view_json")" \
  --argjson router_execution_result "$(contract_view_result_json "$router_execution_view_json")" \
  --argjson router_mirror_result "$(contract_view_result_json "$router_mirror_view_json")" \
  --argjson pool_mirror_result "$(contract_view_result_json "$pool_mirror_view_json")" \
  --argjson launchpad_mirror_result "$(contract_view_result_json "$launchpad_mirror_view_json")" \
  --argjson launchpad_mirror_accounting_result "$(contract_view_result_json "$launchpad_mirror_accounting_view_json")" \
  --argjson launchpad_activation_result "$(contract_view_result_json "$launchpad_activation_view_json")" \
  --argjson refund_allocation_mirror_result "$(contract_view_result_json "$refund_allocation_mirror_view_json")" \
  --argjson referral_mirror_result "$(contract_view_result_json "$referral_mirror_view_json")" \
  --argjson farm_mirror_result "$(contract_view_result_json "$farm_mirror_view_json")" \
  --argjson risk_bucket_1_result "$(contract_view_result_json "$risk_bucket_1_view_json")" \
  --argjson risk_bucket_2_result "$(contract_view_result_json "$risk_bucket_2_view_json")" \
  --argjson risk_bucket_3_result "$(contract_view_result_json "$risk_bucket_3_view_json")" \
  --argjson risk_vault_state_result "$(contract_view_result_json "$risk_vault_state_view_json")" \
  --argjson risk_bucket_1_liability_result "$(contract_view_result_json "$risk_bucket_1_liability_view_json")" \
  --argjson risk_bucket_1_liquidation_liability_result "$(contract_view_result_json "$risk_bucket_1_liquidation_liability_view_json")" \
  --argjson risk_bucket_2_shout_liability_result "$(contract_view_result_json "$risk_bucket_2_shout_liability_view_json")" \
  --argjson risk_bucket_2_outperformance_liability_result "$(contract_view_result_json "$risk_bucket_2_outperformance_liability_view_json")" \
  --argjson risk_bucket_3_liability_result "$(contract_view_result_json "$risk_bucket_3_liability_view_json")" \
  --argjson risk_bucket_1_automation_result "$(contract_view_result_json "$risk_bucket_1_automation_view_json")" \
  --argjson risk_bucket_2_automation_result "$(contract_view_result_json "$risk_bucket_2_automation_view_json")" \
  --argjson risk_bucket_3_automation_result "$(contract_view_result_json "$risk_bucket_3_automation_view_json")" \
  --argjson perps_engine_config_result "$(contract_view_result_json "$perps_engine_config_view_json")" \
  --argjson perps_market_state_result "$(contract_view_result_json "$perps_market_state_view_json")" \
  --argjson perps_market_risk_result "$(contract_view_result_json "$perps_market_risk_view_json")" \
  --argjson perps_automation_result "$(contract_view_result_json "$perps_automation_view_json")" \
  --argjson perps_position_state_result "$(contract_view_result_json "$perps_position_state_view_json")" \
  --argjson perps_recovery_position_state_result "$(contract_view_result_json "$perps_recovery_position_state_view_json")" \
  --argjson perps_recovery_position_liquidation_result "$(contract_view_result_json "$perps_recovery_position_liquidation_view_json")" \
  --argjson perps_liquidation_position_state_result "$(contract_view_result_json "$perps_liquidation_position_state_view_json")" \
  --argjson perps_liquidation_position_liquidation_result "$(contract_view_result_json "$perps_liquidation_position_liquidation_view_json")" \
  --argjson perps_liquidation_state_result "$(contract_view_result_json "$perps_liquidation_state_view_json")" \
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
  --argjson options_factory_shout_position_result "$(contract_view_result_json "$options_factory_shout_position_view_json")" \
  --argjson options_factory_outperformance_position_result "$(contract_view_result_json "$options_factory_outperformance_position_view_json")" \
  --argjson options_vault_shout_result "$(contract_view_result_json "$options_vault_shout_state_view_json")" \
  --argjson options_vault_outperformance_result "$(contract_view_result_json "$options_vault_outperformance_state_view_json")" \
  --argjson options_vault_shout_position_result "$(contract_view_result_json "$options_vault_shout_position_view_json")" \
  --argjson options_vault_outperformance_position_result "$(contract_view_result_json "$options_vault_outperformance_position_view_json")" \
  --argjson options_shout_product_result "$(contract_view_result_json "$options_shout_product_view_json")" \
  --argjson options_outperformance_product_result "$(contract_view_result_json "$options_outperformance_product_view_json")" \
  --argjson options_shout_product_position_result "$(contract_view_result_json "$options_shout_product_position_view_json")" \
  --argjson options_outperformance_product_position_result "$(contract_view_result_json "$options_outperformance_product_position_view_json")" \
  --argjson cover_manager_config_result "$(contract_view_result_json "$cover_manager_config_view_json")" \
  --argjson cover_automation_result "$(contract_view_result_json "$cover_automation_view_json")" \
  --argjson cover_policy_result "$(contract_view_result_json "$cover_policy_view_json")" \
  --argjson job_mirror_result "$job_mirror_result_json" \
  --argjson intent_state_result "$(contract_view_result_json "$intent_state_view_json")" \
  --argjson vault_state_result "$(contract_view_result_json "$vault_state_view_json")" \
  --argjson vault_position_result "$(contract_view_result_json "$vault_position_view_json")" \
  --argjson operator_state_result "$(contract_view_result_json "$operator_state_view_json")" \
  --argjson margin_account_health_result "$(contract_view_result_json "$margin_account_health_view_json")" \
  --argjson rwa_market_state_result "$(contract_view_result_json "$rwa_market_state_view_json")" \
  --argjson dlmm_hook_quote_result "$(contract_view_result_json "$dlmm_hook_quote_view_json")" \
  --argjson epoch_auction_state_result "$(contract_view_result_json "$epoch_auction_state_view_json")" \
  --argjson dlmm_range_governor_result "$(contract_view_result_json "$dlmm_range_governor_view_json")" \
  --argjson twamm_trigger_state_result "$(contract_view_result_json "$twamm_trigger_state_view_json")" \
  --argjson options_manager_lifecycle_result "$(contract_view_result_json "$options_manager_lifecycle_view_json")" \
  --argjson options_factory_lifecycle_result "$(contract_view_result_json "$options_factory_lifecycle_view_json")" \
  --argjson cover_lifecycle_result "$(contract_view_result_json "$cover_lifecycle_view_json")" \
  --argjson launchpad_lifecycle_result "$(contract_view_result_json "$launchpad_lifecycle_view_json")" \
  --argjson vault_lifecycle_result "$(contract_view_result_json "$vault_lifecycle_view_json")" \
  --argjson perps_lifecycle_result "$(contract_view_result_json "$perps_lifecycle_view_json")" \
  --argjson conditional_escrow_state_result "$(contract_view_result_json "$conditional_escrow_state_view_json")" \
  --argjson decoded_state_ints "$decoded_state_ints" \
  '
    def nullable_tx:
      if . == "" then null else . end;

    {
    generated_at: $generated_at,
    authority: $authority,
    client_config: $client_config,
    base_asset_alias: $base_asset_alias,
    xor_asset_id: $xor_asset_id,
    usdt_asset_id: $usdt_asset_id,
    balances: {
      n3x_before: $before_n3x,
      n3x_after_mint: $after_mint_n3x,
      n3x_after_burn: $after_burn_n3x
    },
    expectations: {
      expected_swap_out: $expected_swap_out,
      expected_active_bin: $expected_active_bin,
      expected_active_liquidity: $expected_active_liquidity,
      expected_active_share_supply: $expected_active_share_supply,
      expected_pool_reserve_base: $expected_pool_reserve_base,
      expected_pool_reserve_quote: $expected_pool_reserve_quote,
      expected_launchpad_activation_value: $expected_launchpad_activation_value,
      expected_referral_member_total: $expected_referral_member_total,
      expected_referral_parent_total: $expected_referral_parent_total,
      expected_farm_accrued: $expected_farm_accrued,
      expected_farm_stake: $expected_farm_stake,
      expected_farm_claim: $expected_farm_claim,
      expected_perps_funding_sync: $expected_perps_funding_sync,
      expected_perps_remove_payout: $expected_perps_remove_payout,
      expected_perps_realized_pnl: $expected_perps_realized_pnl,
      expected_perps_close_payout: $expected_perps_close_payout,
      expected_perps_liquidation_keeper_reward: $expected_perps_liquidation_keeper_reward,
      expected_perps_liquidation_owner_residual: $expected_perps_liquidation_owner_residual,
      expected_perps_liquidation_realized_pnl: $expected_perps_liquidation_realized_pnl,
      expected_perps_liquidation_payout: $expected_perps_liquidation_payout,
      expected_options_shout_payout: $expected_options_shout_payout,
      expected_options_outperformance_payout: $expected_options_outperformance_payout,
      expected_cover_claim_payout: $expected_cover_claim_payout,
      expected_risk_bucket_1: $expected_risk_bucket_1,
      expected_risk_bucket_2: $expected_risk_bucket_2,
      expected_risk_bucket_3: $expected_risk_bucket_3,
      expected_risk_vault_state: $expected_risk_vault_state,
      expected_automation_next_slot: $expected_automation_next_slot,
      expected_automation_retry_run_slot: $expected_automation_retry_run_slot,
      expected_automation_cron_interval_slots: $expected_automation_cron_interval_slots,
      expected_automation_run_count: $expected_automation_run_count,
      expected_n3x_mint_fee: $expected_n3x_mint_fee,
      expected_n3x_redeem_fees: $expected_n3x_redeem_fees,
      expected_intent_state: $intent_state_result,
      expected_vault_state: $vault_state_result,
      expected_operator_state: $operator_state_result,
      expected_margin_account_health: $margin_account_health_result,
      expected_rwa_market_state: $rwa_market_state_result,
      expected_dlmm_hook_quote: $dlmm_hook_quote_result
    },
    tx_hashes: {
      n3x_init_only_config: ($n3x_config_tx_hash | nullable_tx),
      n3x_deposit_and_mint: ($mint_tx_hash | nullable_tx),
      n3x_burn_and_redeem: ($burn_tx_hash | nullable_tx),
      dlmm_router_route_swap: ($dlmm_swap_tx_hash | nullable_tx),
      dlmm_pool_collect_position_fees: ($dlmm_collect_position_fees_tx_hash | nullable_tx),
      dlmm_pool_remove_position_liquidity: ($dlmm_remove_position_tx_hash | nullable_tx),
      launchpad_contribute: ($launchpad_tx_hash | nullable_tx),
      launchpad_init_only_vesting: ($launchpad_config_vesting_tx_hash | nullable_tx),
      launchpad_close: ($launchpad_close_tx_hash | nullable_tx),
      launchpad_deposit_claim_inventory: ($launchpad_claim_inventory_tx_hash | nullable_tx),
      launchpad_claim_allocation: ($launchpad_claim_tx_hash | nullable_tx),
      launchpad_deposit_seed_inventory: ($launchpad_seed_inventory_tx_hash | nullable_tx),
      launchpad_register_seed_liquidity: ($launchpad_register_seed_tx_hash | nullable_tx),
      launchpad_seed_liquidity: ($launchpad_seed_liquidity_tx_hash | nullable_tx),
      launchpad_finalize_activation: ($launchpad_finalize_activation_tx_hash | nullable_tx),
      launchpad_refund_sale_init: ($refund_sale_init_tx_hash | nullable_tx),
      launchpad_refund_sale_init_only_config: ($refund_sale_config_tx_hash | nullable_tx),
      launchpad_refund_sale_contribute: ($refund_sale_contribute_tx_hash | nullable_tx),
      launchpad_refund_sale_close: ($refund_sale_close_tx_hash | nullable_tx),
      launchpad_refund_allocation: ($refund_sale_refund_tx_hash | nullable_tx),
      referral_init_only_config: ($referral_config_tx_hash | nullable_tx),
      referral_init_only_tiers: ($referral_tiers_tx_hash | nullable_tx),
      referral_bind_parent: ($referral_parent_bind_tx_hash | nullable_tx),
      referral_bind: ($referral_bind_tx_hash | nullable_tx),
      referral_accrue: ($referral_accrue_tx_hash | nullable_tx),
      referral_claim: ($referral_claim_tx_hash | nullable_tx),
      referral_parent_claim: ($referral_parent_claim_tx_hash | nullable_tx),
      farms_init_only_config: ($farm_config_tx_hash | nullable_tx),
      farms_fund_rewards: ($farm_fund_tx_hash | nullable_tx),
      farms_stake: ($farm_stake_tx_hash | nullable_tx),
      farms_sync_claim_slot: ($farm_sync_claim_tx_hash | nullable_tx),
      farms_claim: ($farm_claim_tx_hash | nullable_tx),
      farms_sync_unstake_slot: ($farm_sync_unstake_tx_hash | nullable_tx),
      farms_unstake: ($farm_unstake_tx_hash | nullable_tx),
      perps_open_position: ($perps_open_tx_hash | nullable_tx),
      perps_sync_funding: ($perps_funding_tx_hash | nullable_tx),
      perps_add_margin: ($perps_add_margin_tx_hash | nullable_tx),
      perps_remove_margin: ($perps_remove_margin_tx_hash | nullable_tx),
      perps_close_position: ($perps_close_tx_hash | nullable_tx),
      perps_open_liquidation_position: ($perps_liquidation_open_tx_hash | nullable_tx),
      perps_liquidation_queue_pass: ($perps_liquidation_queue_tx_hash | nullable_tx),
      perps_liquidation_recovery_pass: ($perps_liquidation_recover_tx_hash | nullable_tx),
      perps_liquidation_requeue_pass: ($perps_liquidation_requeue_tx_hash | nullable_tx),
      perps_liquidation_execute_pass: ($perps_liquidation_execute_tx_hash | nullable_tx),
      options_buy_shout: ($options_shout_buy_tx_hash | nullable_tx),
      options_record_shout: ($options_shout_record_tx_hash | nullable_tx),
      options_exercise_shout: ($options_shout_exercise_tx_hash | nullable_tx),
      options_buy_outperformance: ($options_outperformance_buy_tx_hash | nullable_tx),
      options_settle_outperformance_series: ($options_outperformance_settle_tx_hash | nullable_tx),
      options_exercise_outperformance: ($options_outperformance_exercise_tx_hash | nullable_tx),
      cover_register_policy: ($cover_register_tx_hash | nullable_tx),
      cover_stale_reset_observation: ($cover_stale_reset_tx_hash | nullable_tx),
      cover_trigger_1: ($cover_trigger_1_tx_hash | nullable_tx),
      cover_trigger_2: ($cover_trigger_2_tx_hash | nullable_tx),
      cover_trigger_3: ($cover_trigger_3_tx_hash | nullable_tx),
      cover_trigger_4: ($cover_trigger_4_tx_hash | nullable_tx),
      cover_route_claim: ($cover_claim_tx_hash | nullable_tx),
      automation_enqueue: ($job_enqueue_tx_hash | nullable_tx),
      automation_configure: ($job_config_tx_hash | nullable_tx),
      automation_assign_executor: ($job_assign_executor_tx_hash | nullable_tx),
      automation_configure_cron: ($job_cron_tx_hash | nullable_tx),
      automation_dispatch: ($job_dispatch_tx_hash | nullable_tx),
      automation_pause: ($job_pause_tx_hash | nullable_tx),
      automation_resume: ($job_resume_tx_hash | nullable_tx),
      automation_retry: ($job_retry_tx_hash | nullable_tx),
      automation_retry_dispatch: ($job_retry_dispatch_tx_hash | nullable_tx),
      automation_complete_run: ($job_complete_tx_hash | nullable_tx),
      intent_open: ($intent_open_tx_hash | nullable_tx),
      intent_fill: ($intent_fill_tx_hash | nullable_tx),
      vault_register: ($vault_register_tx_hash | nullable_tx),
      vault_deposit: ($vault_deposit_tx_hash | nullable_tx),
      vault_request_redeem: ($vault_request_redeem_tx_hash | nullable_tx),
      vault_claim_redeem: ($vault_claim_redeem_tx_hash | nullable_tx),
      operator_register: ($operator_register_tx_hash | nullable_tx),
      operator_bond: ($operator_bond_tx_hash | nullable_tx),
      operator_heartbeat: ($operator_heartbeat_tx_hash | nullable_tx),
      operator_claim_fees: ($operator_claim_fees_tx_hash | nullable_tx),
      margin_register_market: ($margin_register_market_tx_hash | nullable_tx),
      margin_deposit_collateral: ($margin_deposit_collateral_tx_hash | nullable_tx),
      margin_lock_exposure: ($margin_lock_exposure_tx_hash | nullable_tx),
      margin_liquidate_account: ($margin_liquidate_account_tx_hash | nullable_tx),
      rwa_issue_lot: ($rwa_issue_lot_tx_hash | nullable_tx),
      rwa_bind_share_asset: ($rwa_bind_share_asset_tx_hash | nullable_tx),
      rwa_report_nav: ($rwa_report_nav_tx_hash | nullable_tx),
      rwa_request_redemption: ($rwa_request_redemption_tx_hash | nullable_tx),
      rwa_settle_redemption: ($rwa_settle_redemption_tx_hash | nullable_tx),
      dlmm_configure_hook: ($dlmm_configure_hook_tx_hash | nullable_tx),
      dlmm_place_limit_order: ($dlmm_place_limit_order_tx_hash | nullable_tx),
      dlmm_schedule_twamm: ($dlmm_schedule_twamm_tx_hash | nullable_tx),
      dlmm_record_hook_execution: ($dlmm_record_execution_tx_hash | nullable_tx),
      conditional_escrow_open: ($conditional_escrow_open_tx_hash | nullable_tx),
      conditional_escrow_execute_trigger: ($conditional_escrow_execute_tx_hash | nullable_tx)
    },
    trigger_evidence: ($trigger_registration_evidence + {
      completions: {
        conditional_escrow_execute: $conditional_escrow_completion
      },
      epoch_auction_native_close: $epoch_auction_native_close_evidence
    }),
    rejection_evidence: {
      intent_replay: $intent_replay_rejection,
      unregistered_operator: $operator_unbonded_rejection,
      unhealthy_margin_withdraw: $margin_unhealthy_withdraw_rejection,
      duplicate_rwa_issue: $rwa_duplicate_issue_rejection,
      disabled_dlmm_hook: $dlmm_disabled_hook_rejection
    },
    view_results: {
      n3x_quote_mint: $n3x_quote_result,
      n3x_quote_redeem: $redeem_quote_result,
      dlmm_router_quote_bin: $router_bin_quote_result,
      n3x_assert_initialized: $n3x_assert_result,
      n3x_mirror_state: $n3x_mirror_result,
      dlmm_router_assert_config: $router_assert_result,
      dlmm_router_contract_binding: $router_contract_binding_result,
      dlmm_router_execution_binding: $router_execution_result,
      dlmm_router_mirror_state: $router_mirror_result,
      dlmm_pool_mirror_state: $pool_mirror_result,
      launchpad_mirror_sale: $launchpad_mirror_result,
      launchpad_mirror_sale_accounting: $launchpad_mirror_accounting_result,
      launchpad_activation_state: $launchpad_activation_result,
      launchpad_mirror_refund_allocation: $refund_allocation_mirror_result,
      referral_mirror_member: $referral_mirror_result,
      farms_mirror_position: $farm_mirror_result,
      risk_bucket_1: $risk_bucket_1_result,
      risk_bucket_2: $risk_bucket_2_result,
      risk_bucket_3: $risk_bucket_3_result,
      risk_vault_state: $risk_vault_state_result,
      risk_bucket_1_liability: $risk_bucket_1_liability_result,
      risk_bucket_1_liquidation_liability: $risk_bucket_1_liquidation_liability_result,
      risk_bucket_2_shout_liability: $risk_bucket_2_shout_liability_result,
      risk_bucket_2_outperformance_liability: $risk_bucket_2_outperformance_liability_result,
      risk_bucket_3_liability: $risk_bucket_3_liability_result,
      risk_bucket_1_automation: $risk_bucket_1_automation_result,
      risk_bucket_2_automation: $risk_bucket_2_automation_result,
      risk_bucket_3_automation: $risk_bucket_3_automation_result,
      perps_engine_config: $perps_engine_config_result,
      perps_market_state: $perps_market_state_result,
      perps_market_risk: $perps_market_risk_result,
      perps_automation_state: $perps_automation_result,
      perps_position_state: $perps_position_state_result,
      perps_recovery_position_state: $perps_recovery_position_state_result,
      perps_recovery_position_liquidation_state: $perps_recovery_position_liquidation_result,
      perps_liquidation_position_state: $perps_liquidation_position_state_result,
      perps_liquidation_position_liquidation_state: $perps_liquidation_position_liquidation_result,
      perps_liquidation_state: $perps_liquidation_state_result,
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
      options_factory_shout_position: $options_factory_shout_position_result,
      options_factory_outperformance_position: $options_factory_outperformance_position_result,
      options_vault_shout: $options_vault_shout_result,
      options_vault_outperformance: $options_vault_outperformance_result,
      options_vault_shout_position: $options_vault_shout_position_result,
      options_vault_outperformance_position: $options_vault_outperformance_position_result,
      options_shout_product: $options_shout_product_result,
      options_outperformance_product: $options_outperformance_product_result,
      options_shout_product_position: $options_shout_product_position_result,
      options_outperformance_product_position: $options_outperformance_product_position_result,
      cover_manager_config: $cover_manager_config_result,
      cover_automation_state: $cover_automation_result,
      cover_policy_state: $cover_policy_result,
      automation_mirror_job: $job_mirror_result,
      intent_state: $intent_state_result,
      vault_state: $vault_state_result,
      vault_position: $vault_position_result,
      operator_state: $operator_state_result,
      margin_account_health: $margin_account_health_result,
      rwa_market_state: $rwa_market_state_result,
      dlmm_hook_quote: $dlmm_hook_quote_result,
      epoch_auction_state: $epoch_auction_state_result,
      dlmm_range_governor: $dlmm_range_governor_result,
      twamm_trigger_state: $twamm_trigger_state_result,
      options_manager_lifecycle: $options_manager_lifecycle_result,
      options_factory_lifecycle: $options_factory_lifecycle_result,
      cover_lifecycle: $cover_lifecycle_result,
      launchpad_lifecycle: $launchpad_lifecycle_result,
      vault_lifecycle: $vault_lifecycle_result,
      perps_lifecycle: $perps_lifecycle_result,
      conditional_escrow_state: $conditional_escrow_state_result
    },
    decoded_state_ints: $decoded_state_ints
  }')"

printf '%s\n' "$report_json" > "$latest_report"
printf '%s\n' "$report_json" > "$timestamped_report"

print_smoke_tx "n3x config" "$n3x_config_tx_hash"
echo "local smoke n3x quote result: $(contract_view_result_json "$n3x_quote_view_json")"
print_smoke_tx "mint" "$mint_tx_hash"
echo "local smoke n3x redeem quote result: $(contract_view_result_json "$redeem_quote_view_json")"
print_smoke_tx "burn" "$burn_tx_hash"
echo "local smoke router bin quote result: $(contract_view_result_json "$router_bin_quote_view_json")"
print_smoke_tx "dlmm swap" "$dlmm_swap_tx_hash"
print_smoke_tx "dlmm collect-fees" "$dlmm_collect_position_fees_tx_hash"
print_smoke_tx "dlmm remove-position" "$dlmm_remove_position_tx_hash"
print_smoke_tx "launchpad" "$launchpad_tx_hash"
print_smoke_tx "launchpad vesting-config" "$launchpad_config_vesting_tx_hash"
print_smoke_tx "launchpad close" "$launchpad_close_tx_hash"
print_smoke_tx "launchpad claim-inventory" "$launchpad_claim_inventory_tx_hash"
print_smoke_tx "launchpad claim" "$launchpad_claim_tx_hash"
print_smoke_tx "launchpad seed-inventory" "$launchpad_seed_inventory_tx_hash"
print_smoke_tx "launchpad register-seed" "$launchpad_register_seed_tx_hash"
print_smoke_tx "launchpad seed-liquidity" "$launchpad_seed_liquidity_tx_hash"
print_smoke_tx "launchpad finalize-activation" "$launchpad_finalize_activation_tx_hash"
echo "local smoke launchpad activation result: $(contract_view_result_json "$launchpad_activation_view_json")"
print_smoke_tx "refund-sale init" "$refund_sale_init_tx_hash"
print_smoke_tx "refund-sale config" "$refund_sale_config_tx_hash"
print_smoke_tx "refund-sale contribute" "$refund_sale_contribute_tx_hash"
print_smoke_tx "refund-sale close" "$refund_sale_close_tx_hash"
print_smoke_tx "refund allocation" "$refund_sale_refund_tx_hash"
print_smoke_tx "referral config" "$referral_config_tx_hash"
print_smoke_tx "referral tiers" "$referral_tiers_tx_hash"
print_smoke_tx "referral parent-bind" "$referral_parent_bind_tx_hash"
print_smoke_tx "referral bind" "$referral_bind_tx_hash"
print_smoke_tx "referral accrue" "$referral_accrue_tx_hash"
print_smoke_tx "referral claim" "$referral_claim_tx_hash"
print_smoke_tx "referral parent-claim" "$referral_parent_claim_tx_hash"
echo "local smoke referral mirror result: $(contract_view_result_json "$referral_mirror_view_json")"
print_smoke_tx "farm config" "$farm_config_tx_hash"
print_smoke_tx "farm fund" "$farm_fund_tx_hash"
print_smoke_tx "farm stake" "$farm_stake_tx_hash"
print_smoke_tx "farm sync-claim-slot" "$farm_sync_claim_tx_hash"
print_smoke_tx "farm claim" "$farm_claim_tx_hash"
print_smoke_tx "farm sync-unstake-slot" "$farm_sync_unstake_tx_hash"
print_smoke_tx "farm unstake" "$farm_unstake_tx_hash"
echo "local smoke farm mirror result: $(contract_view_result_json "$farm_mirror_view_json")"
print_smoke_tx "perps open-position" "$perps_open_tx_hash"
print_smoke_tx "perps sync-funding" "$perps_funding_tx_hash"
print_smoke_tx "perps add-margin" "$perps_add_margin_tx_hash"
print_smoke_tx "perps remove-margin" "$perps_remove_margin_tx_hash"
print_smoke_tx "perps close-position" "$perps_close_tx_hash"
print_smoke_tx "perps open-liquidation-position" "$perps_liquidation_open_tx_hash"
print_smoke_tx "perps liquidation-queue-pass" "$perps_liquidation_queue_tx_hash"
print_smoke_tx "perps liquidation-recovery-pass" "$perps_liquidation_recover_tx_hash"
print_smoke_tx "perps liquidation-requeue-pass" "$perps_liquidation_requeue_tx_hash"
print_smoke_tx "perps liquidation-execute-pass" "$perps_liquidation_execute_tx_hash"
echo "local smoke risk bucket 1: $(contract_view_result_json "$risk_bucket_1_view_json")"
echo "local smoke risk bucket 2: $(contract_view_result_json "$risk_bucket_2_view_json")"
echo "local smoke risk bucket 3: $(contract_view_result_json "$risk_bucket_3_view_json")"
echo "local smoke risk vault state: $(contract_view_result_json "$risk_vault_state_view_json")"
echo "local smoke risk bucket 1 liability: $(contract_view_result_json "$risk_bucket_1_liability_view_json")"
echo "local smoke risk bucket 1 liquidation liability: $(contract_view_result_json "$risk_bucket_1_liquidation_liability_view_json")"
echo "local smoke risk bucket 2 shout liability: $(contract_view_result_json "$risk_bucket_2_shout_liability_view_json")"
echo "local smoke risk bucket 2 outperformance liability: $(contract_view_result_json "$risk_bucket_2_outperformance_liability_view_json")"
echo "local smoke risk bucket 3 liability: $(contract_view_result_json "$risk_bucket_3_liability_view_json")"
echo "local smoke perps engine config: $(contract_view_result_json "$perps_engine_config_view_json")"
echo "local smoke perps market state: $(contract_view_result_json "$perps_market_state_view_json")"
echo "local smoke perps market risk: $(contract_view_result_json "$perps_market_risk_view_json")"
echo "local smoke perps automation state: $(contract_view_result_json "$perps_automation_view_json")"
echo "local smoke perps position state: $(contract_view_result_json "$perps_position_state_view_json")"
echo "local smoke perps recovery position state: $(contract_view_result_json "$perps_recovery_position_state_view_json")"
echo "local smoke perps recovery position liquidation state: $(contract_view_result_json "$perps_recovery_position_liquidation_view_json")"
echo "local smoke perps liquidation position state: $(contract_view_result_json "$perps_liquidation_position_state_view_json")"
echo "local smoke perps liquidation position liquidation state: $(contract_view_result_json "$perps_liquidation_position_liquidation_view_json")"
echo "local smoke perps liquidation state: $(contract_view_result_json "$perps_liquidation_state_view_json")"
echo "local smoke options manager config: $(contract_view_result_json "$options_manager_config_view_json")"
echo "local smoke options factory config: $(contract_view_result_json "$options_factory_config_view_json")"
echo "local smoke options shout series: $(contract_view_result_json "$options_shout_series_view_json")"
echo "local smoke options outperformance series: $(contract_view_result_json "$options_outperformance_series_view_json")"
print_smoke_tx "options buy-shout" "$options_shout_buy_tx_hash"
print_smoke_tx "options record-shout" "$options_shout_record_tx_hash"
print_smoke_tx "options exercise-shout" "$options_shout_exercise_tx_hash"
print_smoke_tx "options buy-outperformance" "$options_outperformance_buy_tx_hash"
print_smoke_tx "options settle-outperformance" "$options_outperformance_settle_tx_hash"
print_smoke_tx "options exercise-outperformance" "$options_outperformance_exercise_tx_hash"
echo "local smoke options factory shout position: $(contract_view_result_json "$options_factory_shout_position_view_json")"
echo "local smoke options factory outperformance position: $(contract_view_result_json "$options_factory_outperformance_position_view_json")"
echo "local smoke options vault shout state: $(contract_view_result_json "$options_vault_shout_state_view_json")"
echo "local smoke options vault outperformance state: $(contract_view_result_json "$options_vault_outperformance_state_view_json")"
echo "local smoke options vault shout position: $(contract_view_result_json "$options_vault_shout_position_view_json")"
echo "local smoke options vault outperformance position: $(contract_view_result_json "$options_vault_outperformance_position_view_json")"
echo "local smoke options shout product: $(contract_view_result_json "$options_shout_product_view_json")"
echo "local smoke options outperformance product: $(contract_view_result_json "$options_outperformance_product_view_json")"
echo "local smoke options shout product position: $(contract_view_result_json "$options_shout_product_position_view_json")"
echo "local smoke options outperformance product position: $(contract_view_result_json "$options_outperformance_product_position_view_json")"
print_smoke_tx "cover register-policy" "$cover_register_tx_hash"
print_smoke_tx "cover stale-reset" "$cover_stale_reset_tx_hash"
print_smoke_tx "cover trigger-1" "$cover_trigger_1_tx_hash"
print_smoke_tx "cover trigger-2" "$cover_trigger_2_tx_hash"
print_smoke_tx "cover trigger-3" "$cover_trigger_3_tx_hash"
print_smoke_tx "cover trigger-4" "$cover_trigger_4_tx_hash"
print_smoke_tx "cover claim" "$cover_claim_tx_hash"
echo "local smoke cover manager config: $(contract_view_result_json "$cover_manager_config_view_json")"
echo "local smoke cover automation state: $(contract_view_result_json "$cover_automation_view_json")"
echo "local smoke cover policy state: $(contract_view_result_json "$cover_policy_view_json")"
print_smoke_tx "automation enqueue" "$job_enqueue_tx_hash"
print_smoke_tx "automation config" "$job_config_tx_hash"
print_smoke_tx "automation assign-executor" "$job_assign_executor_tx_hash"
print_smoke_tx "automation cron" "$job_cron_tx_hash"
print_smoke_tx "automation dispatch" "$job_dispatch_tx_hash"
print_smoke_tx "automation pause" "$job_pause_tx_hash"
print_smoke_tx "automation resume" "$job_resume_tx_hash"
print_smoke_tx "automation retry" "$job_retry_tx_hash"
print_smoke_tx "automation retry-dispatch" "$job_retry_dispatch_tx_hash"
print_smoke_tx "automation complete-run" "$job_complete_tx_hash"
echo "local smoke automation mirror result: $(contract_view_result_json "$job_mirror_view_json")"
print_smoke_tx "intent open" "$intent_open_tx_hash"
print_smoke_tx "intent fill" "$intent_fill_tx_hash"
echo "local smoke intent state: $(contract_view_result_json "$intent_state_view_json")"
print_smoke_tx "vault register" "$vault_register_tx_hash"
print_smoke_tx "vault deposit" "$vault_deposit_tx_hash"
print_smoke_tx "vault request-redeem" "$vault_request_redeem_tx_hash"
print_smoke_tx "vault claim-redeem" "$vault_claim_redeem_tx_hash"
echo "local smoke vault state: $(contract_view_result_json "$vault_state_view_json")"
echo "local smoke vault position: $(contract_view_result_json "$vault_position_view_json")"
print_smoke_tx "operator register" "$operator_register_tx_hash"
print_smoke_tx "operator bond" "$operator_bond_tx_hash"
print_smoke_tx "operator heartbeat" "$operator_heartbeat_tx_hash"
print_smoke_tx "operator claim-fees" "$operator_claim_fees_tx_hash"
echo "local smoke operator state: $(contract_view_result_json "$operator_state_view_json")"
print_smoke_tx "margin register-market" "$margin_register_market_tx_hash"
print_smoke_tx "margin deposit-collateral" "$margin_deposit_collateral_tx_hash"
print_smoke_tx "margin lock-exposure" "$margin_lock_exposure_tx_hash"
print_smoke_tx "margin liquidate" "$margin_liquidate_account_tx_hash"
echo "local smoke margin account health: $(contract_view_result_json "$margin_account_health_view_json")"
print_smoke_tx "rwa issue-lot" "$rwa_issue_lot_tx_hash"
print_smoke_tx "rwa bind-share-asset" "$rwa_bind_share_asset_tx_hash"
print_smoke_tx "rwa report-nav" "$rwa_report_nav_tx_hash"
print_smoke_tx "rwa request-redemption" "$rwa_request_redemption_tx_hash"
print_smoke_tx "rwa settle-redemption" "$rwa_settle_redemption_tx_hash"
echo "local smoke rwa market state: $(contract_view_result_json "$rwa_market_state_view_json")"
print_smoke_tx "dlmm hook configure" "$dlmm_configure_hook_tx_hash"
print_smoke_tx "dlmm hook limit-order" "$dlmm_place_limit_order_tx_hash"
print_smoke_tx "dlmm hook twamm" "$dlmm_schedule_twamm_tx_hash"
print_smoke_tx "dlmm hook execution" "$dlmm_record_execution_tx_hash"
echo "local smoke dlmm hook quote: $(contract_view_result_json "$dlmm_hook_quote_view_json")"
print_smoke_tx "conditional-escrow open" "$conditional_escrow_open_tx_hash"
print_smoke_tx "conditional-escrow execute-trigger" "$conditional_escrow_execute_tx_hash"
echo "local smoke epoch auction state: $(contract_view_result_json "$epoch_auction_state_view_json")"
echo "local smoke dlmm range governor: $(contract_view_result_json "$dlmm_range_governor_view_json")"
echo "local smoke twamm trigger state: $(contract_view_result_json "$twamm_trigger_state_view_json")"
echo "local smoke conditional escrow state: $(contract_view_result_json "$conditional_escrow_state_view_json")"
echo "local smoke decoded state ints: $(jq -c '.decoded_state_ints' <<<"$report_json")"
echo "local smoke report: $timestamped_report"
