#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

config="$(client_config_or_default local)"
ensure_client "$config"
ensure_authority "$config"

n3x_hub_contract="$(deployed_contract_id_for_env local n3x.n3x_hub)"
n3x_hub_dataspace="$(deployed_contract_dataspace_for_env local n3x.n3x_hub)"
dlmm_pool_contract="$(deployed_contract_id_for_env local dlmm.dlmm_pool)"
dlmm_pool_dataspace="$(deployed_contract_dataspace_for_env local dlmm.dlmm_pool)"
dlmm_router_contract="$(deployed_contract_id_for_env local dlmm.dlmm_router)"
dlmm_router_dataspace="$(deployed_contract_dataspace_for_env local dlmm.dlmm_router)"
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
risk_vault_contract_subject="$(contract_subject_account_for_literal "$config" "$risk_vault_contract")"
perps_engine_contract_subject="$(contract_subject_account_for_literal "$config" "$perps_engine_contract")"
risk_vault_contract_blob_hex="0x$(printf '%s' "$risk_vault_contract" | xxd -p -c 256 | tr -d '\n')"

iroha_cli_json --config "$config" ledger asset definition get --alias "$SORASWAP_BASE_ASSET_ALIAS" \
  | jq -e --arg id "$SORASWAP_XOR_ASSET_DEFINITION_ID" '.id == $id and .name == "xor"' >/dev/null

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
sale_name="${SORASWAP_SALE_NAME:-genesis_sale}"
launchpad_payment_amount="${SORASWAP_LAUNCHPAD_SMOKE_PAYMENT_AMOUNT:-10}"
launchpad_allocation_id="${SORASWAP_LAUNCHPAD_SMOKE_ALLOCATION_ID:-smoke_launchpad_allocation}"
launchpad_claim_inventory_amount="${SORASWAP_LAUNCHPAD_CLAIM_INVENTORY_AMOUNT:-$launchpad_payment_amount}"
launchpad_claim_slot="${SORASWAP_LAUNCHPAD_CLAIM_SLOT:-0}"
launchpad_seed_position_id="${SORASWAP_LAUNCHPAD_SEED_POSITION_ID:-smoke_launchpad_seed_lp}"
launchpad_seed_payment_amount="${SORASWAP_LAUNCHPAD_SEED_PAYMENT_AMOUNT:-4}"
launchpad_seed_sale_amount="${SORASWAP_LAUNCHPAD_SEED_SALE_AMOUNT:-6}"
launchpad_seed_bin_id="${SORASWAP_LAUNCHPAD_SEED_BIN_ID:-0}"
refund_sale_name="${SORASWAP_REFUND_SALE_NAME:-refund_sale}"
refund_allocation_id="${SORASWAP_REFUND_ALLOCATION_ID:-smoke_refund_allocation}"
refund_payment_amount="${SORASWAP_REFUND_PAYMENT_AMOUNT:-10}"
refund_soft_cap="${SORASWAP_REFUND_SOFT_CAP:-20}"
series_name="${SORASWAP_SERIES_NAME:-genesis_series}"
policy_name="${SORASWAP_POLICY_NAME:-genesis_policy}"
referral_member="${SORASWAP_REFERRAL_SMOKE_MEMBER:-smoke_referrer}"
referral_parent_member="${SORASWAP_REFERRAL_SMOKE_PARENT_MEMBER:-smoke_referral_parent}"
referral_claim_threshold="${SORASWAP_REFERRAL_SMOKE_CLAIM_THRESHOLD:-3}"
referral_accrual_amount="${SORASWAP_REFERRAL_SMOKE_ACCRUAL:-7}"
referral_direct_share_bps="${SORASWAP_REFERRAL_SMOKE_DIRECT_SHARE_BPS:-7000}"
referral_parent_share_bps="${SORASWAP_REFERRAL_SMOKE_PARENT_SHARE_BPS:-3000}"
farm_position="${SORASWAP_FARM_SMOKE_POSITION:-smoke_farm_position}"
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
cover_registration_slot="${SORASWAP_COVER_SMOKE_REGISTRATION_SLOT:-49}"
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
job_name="${SORASWAP_AUTOMATION_SMOKE_JOB:-smoke_job}"
automation_executor="${SORASWAP_AUTOMATION_SMOKE_EXECUTOR:-$vault_account}"
automation_next_slot="${SORASWAP_AUTOMATION_SMOKE_NEXT_SLOT:-5}"
automation_resume_slot="${SORASWAP_AUTOMATION_SMOKE_RESUME_SLOT:-6}"
automation_retry_delay_slots="${SORASWAP_AUTOMATION_SMOKE_RETRY_DELAY_SLOTS:-3}"
automation_max_retries="${SORASWAP_AUTOMATION_SMOKE_MAX_RETRIES:-2}"
automation_cron_interval_slots="${SORASWAP_AUTOMATION_SMOKE_CRON_INTERVAL_SLOTS:-4}"
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

print_smoke_tx() {
  local label="$1"
  local tx_hash="${2:-}"

  if [[ -n "$tx_hash" ]]; then
    echo "local smoke committed $label tx: $tx_hash"
    return 0
  fi

  echo "local smoke committed $label tx: skipped"
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
n3x_expected_mint_fee=$(( n3x_gross_in * n3x_mint_fee_bps / 10000 ))
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
launchpad_config_vesting_tx_hash=""
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
    --argjson current_slot "$launchpad_claim_slot" \
    '{
      allocation: $allocation,
      current_slot: $current_slot
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
    --argjson mark_price_bps "$perps_entry_price_bps" \
    --argjson index_price_bps "$perps_entry_price_bps" \
    --argjson confidence_bps 25 \
    --argjson oracle_slot 1 \
    --argjson current_slot 1 \
    --argjson status_flags 0 \
    --argjson attestation_hash 101 \
    '{
      market_id: $market_id,
      size: $size,
      margin: $margin,
      requested_leverage_bps: $requested_leverage_bps,
      mark_price_bps: $mark_price_bps,
      index_price_bps: $index_price_bps,
      confidence_bps: $confidence_bps,
      oracle_slot: $oracle_slot,
      current_slot: $current_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
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
    --argjson mark_price_bps "$perps_funding_mark_price_bps" \
    --argjson index_price_bps "$perps_funding_index_price_bps" \
    --argjson confidence_bps 25 \
    --argjson oracle_slot 2 \
    --argjson current_slot 2 \
    --argjson status_flags 0 \
    --argjson attestation_hash 102 \
    '{
      market_id: $market_id,
      mark_price_bps: $mark_price_bps,
      index_price_bps: $index_price_bps,
      confidence_bps: $confidence_bps,
      oracle_slot: $oracle_slot,
      current_slot: $current_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
    }'
)")"
perps_add_margin_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" add_margin "$(
  jq -cn \
    --argjson position_id 1 \
    --argjson amount "$perps_add_collateral" \
    '{
      position_id: $position_id,
      amount: $amount
    }'
)")"
perps_remove_margin_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" remove_margin "$(
  jq -cn \
    --argjson position_id 1 \
    --argjson amount "$perps_remove_collateral" \
    --argjson mark_price_bps "$perps_entry_price_bps" \
    --argjson index_price_bps "$perps_entry_price_bps" \
    --argjson confidence_bps 25 \
    --argjson oracle_slot 3 \
    --argjson current_slot 3 \
    --argjson status_flags 0 \
    --argjson attestation_hash 103 \
    '{
      position_id: $position_id,
      amount: $amount,
      mark_price_bps: $mark_price_bps,
      index_price_bps: $index_price_bps,
      confidence_bps: $confidence_bps,
      oracle_slot: $oracle_slot,
      current_slot: $current_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
    }'
)")"
perps_close_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" close_position "$(
  jq -cn \
    --argjson position_id 1 \
    --argjson mark_price_bps "$perps_exit_mark_price_bps" \
    --argjson index_price_bps "$perps_exit_mark_price_bps" \
    --argjson confidence_bps 25 \
    --argjson oracle_slot 4 \
    --argjson current_slot 4 \
    --argjson status_flags 0 \
    --argjson attestation_hash 104 \
    '{
      position_id: $position_id,
      mark_price_bps: $mark_price_bps,
      index_price_bps: $index_price_bps,
      confidence_bps: $confidence_bps,
      oracle_slot: $oracle_slot,
      current_slot: $current_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
    }'
)")"
perps_liquidation_open_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" open_position "$(
  jq -cn \
    --argjson market_id 1 \
    --argjson size "$perps_size" \
    --argjson margin "$perps_liquidation_collateral" \
    --argjson requested_leverage_bps "$perps_liquidation_requested_leverage_bps" \
    --argjson mark_price_bps "$perps_entry_price_bps" \
    --argjson index_price_bps "$perps_entry_price_bps" \
    --argjson confidence_bps 25 \
    --argjson oracle_slot 70 \
    --argjson current_slot 70 \
    --argjson status_flags 0 \
    --argjson attestation_hash 170 \
    '{
      market_id: $market_id,
      size: $size,
      margin: $margin,
      requested_leverage_bps: $requested_leverage_bps,
      mark_price_bps: $mark_price_bps,
      index_price_bps: $index_price_bps,
      confidence_bps: $confidence_bps,
      oracle_slot: $oracle_slot,
      current_slot: $current_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
    }'
)")"
perps_liquidation_queue_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" run_liquidation_pass "$(
  jq -cn \
    --argjson market_id 1 \
    --argjson max_positions "$perps_liquidation_scan_limit" \
    --argjson mark_price_bps "$perps_liquidation_stress_mark_price_bps" \
    --argjson index_price_bps "$perps_liquidation_stress_mark_price_bps" \
    --argjson confidence_bps 25 \
    --argjson oracle_slot 70 \
    --argjson current_slot 70 \
    --argjson status_flags 0 \
    --argjson attestation_hash 171 \
    '{
      market_id: $market_id,
      max_positions: $max_positions,
      mark_price_bps: $mark_price_bps,
      index_price_bps: $index_price_bps,
      confidence_bps: $confidence_bps,
      oracle_slot: $oracle_slot,
      current_slot: $current_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
    }'
)")"
perps_liquidation_recover_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" run_liquidation_pass "$(
  jq -cn \
    --argjson market_id 1 \
    --argjson max_positions "$perps_liquidation_scan_limit" \
    --argjson mark_price_bps "$perps_liquidation_healthy_mark_price_bps" \
    --argjson index_price_bps "$perps_liquidation_healthy_mark_price_bps" \
    --argjson confidence_bps 25 \
    --argjson oracle_slot 71 \
    --argjson current_slot 71 \
    --argjson status_flags 0 \
    --argjson attestation_hash 172 \
    '{
      market_id: $market_id,
      max_positions: $max_positions,
      mark_price_bps: $mark_price_bps,
      index_price_bps: $index_price_bps,
      confidence_bps: $confidence_bps,
      oracle_slot: $oracle_slot,
      current_slot: $current_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
    }'
)")"
perps_recovery_position_state_view_json="$(submit_contract_view "$config" "$perps_engine_contract" position_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"position_id":2}')"
perps_recovery_position_liquidation_view_json="$(submit_contract_view "$config" "$perps_engine_contract" position_liquidation_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"position_id":2}')"
perps_liquidation_requeue_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" run_liquidation_pass "$(
  jq -cn \
    --argjson market_id 1 \
    --argjson max_positions "$perps_liquidation_scan_limit" \
    --argjson mark_price_bps "$perps_liquidation_stress_mark_price_bps" \
    --argjson index_price_bps "$perps_liquidation_stress_mark_price_bps" \
    --argjson confidence_bps 25 \
    --argjson oracle_slot 72 \
    --argjson current_slot 72 \
    --argjson status_flags 0 \
    --argjson attestation_hash 173 \
    '{
      market_id: $market_id,
      max_positions: $max_positions,
      mark_price_bps: $mark_price_bps,
      index_price_bps: $index_price_bps,
      confidence_bps: $confidence_bps,
      oracle_slot: $oracle_slot,
      current_slot: $current_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
    }'
)")"
perps_liquidation_execute_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" run_liquidation_pass "$(
  jq -cn \
    --argjson market_id 1 \
    --argjson max_positions "$perps_liquidation_scan_limit" \
    --argjson mark_price_bps "$perps_liquidation_stress_mark_price_bps" \
    --argjson index_price_bps "$perps_liquidation_stress_mark_price_bps" \
    --argjson confidence_bps 25 \
    --argjson oracle_slot 73 \
    --argjson current_slot 73 \
    --argjson status_flags 0 \
    --argjson attestation_hash 174 \
    '{
      market_id: $market_id,
      max_positions: $max_positions,
      mark_price_bps: $mark_price_bps,
      index_price_bps: $index_price_bps,
      confidence_bps: $confidence_bps,
      oracle_slot: $oracle_slot,
      current_slot: $current_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
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
    --argjson position_id 1 \
    --argjson mark_price_bps "$options_shout_record_mark_bps" \
    --argjson oracle_slot 5 \
    --argjson current_slot 5 \
    --argjson status_flags 0 \
    --argjson attestation_hash 201 \
    '{
      position_id: $position_id,
      mark_price_bps: $mark_price_bps,
      oracle_slot: $oracle_slot,
      current_slot: $current_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
    }'
)")"
options_shout_exercise_tx_hash="$(call_contract_and_wait "$config" "$options_factory_contract" exercise_shout_position "$(
  jq -cn \
    --argjson position_id 1 \
    --argjson mark_price_bps "$options_shout_exercise_mark_bps" \
    --argjson oracle_slot 6 \
    --argjson current_slot 6 \
    --argjson status_flags 0 \
    --argjson attestation_hash 202 \
    '{
      position_id: $position_id,
      mark_price_bps: $mark_price_bps,
      oracle_slot: $oracle_slot,
      current_slot: $current_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
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
    --argjson final_mark "$options_outperformance_final_mark_bps" \
    --argjson final_quote_mark "$options_outperformance_final_quote_mark_bps" \
    --argjson settlement_slot "$options_outperformance_expiry_slot" \
    --argjson oracle_slot "$options_outperformance_expiry_slot" \
    --argjson current_slot "$options_outperformance_expiry_slot" \
    --argjson status_flags 0 \
    --argjson attestation_hash 203 \
    '{
      series_id: $series_id,
      final_mark: $final_mark,
      final_quote_mark: $final_quote_mark,
      settlement_slot: $settlement_slot,
      oracle_slot: $oracle_slot,
      current_slot: $current_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
    }'
)")"
options_outperformance_exercise_tx_hash="$(call_contract_and_wait "$config" "$options_factory_contract" exercise_outperformance_position "$(
  jq -cn \
    --argjson position_id 2 \
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
    --argjson registration_slot "$cover_registration_slot" \
    '{
      lower_bound: $lower_bound,
      upper_bound: $upper_bound,
      payout_amount: $payout_amount,
      monitoring_window_slots: $monitoring_window_slots,
      required_observations: $required_observations,
      covered_notional: $covered_notional,
      premium_paid: $premium_paid,
      registration_slot: $registration_slot
    }'
)")"
cover_trigger_1_tx_hash="$(call_contract_and_wait "$config" "$cover_policy_manager_contract" record_observation "$(
  jq -cn \
    --argjson policy_id 1 \
    --argjson observed_price "$cover_trigger_price" \
    --argjson oracle_slot 50 \
    --argjson current_slot 50 \
    --argjson status_flags 0 \
    --argjson attestation_hash 301 \
    '{
      policy_id: $policy_id,
      observed_price: $observed_price,
      oracle_slot: $oracle_slot,
      current_slot: $current_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
    }'
)")"
cover_stale_reset_tx_hash="$(call_contract_and_wait "$config" "$cover_policy_manager_contract" record_observation "$(
  jq -cn \
    --argjson policy_id 1 \
    --argjson observed_price "$cover_trigger_price" \
    --argjson oracle_slot 50 \
    --argjson current_slot $(( 50 + cover_oracle_stale_slots + 1 )) \
    --argjson status_flags 0 \
    --argjson attestation_hash 302 \
    '{
      policy_id: $policy_id,
      observed_price: $observed_price,
      oracle_slot: $oracle_slot,
      current_slot: $current_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
    }'
)")"
cover_trigger_2_tx_hash="$(call_contract_and_wait "$config" "$cover_policy_manager_contract" record_observation "$(
  jq -cn \
    --argjson policy_id 1 \
    --argjson observed_price "$cover_trigger_price" \
    --argjson oracle_slot 60 \
    --argjson current_slot 60 \
    --argjson status_flags 0 \
    --argjson attestation_hash 303 \
    '{
      policy_id: $policy_id,
      observed_price: $observed_price,
      oracle_slot: $oracle_slot,
      current_slot: $current_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
    }'
)")"
cover_trigger_3_tx_hash="$(call_contract_and_wait "$config" "$cover_policy_manager_contract" record_observation "$(
  jq -cn \
    --argjson policy_id 1 \
    --argjson observed_price "$cover_trigger_price" \
    --argjson oracle_slot 61 \
    --argjson current_slot 61 \
    --argjson status_flags 0 \
    --argjson attestation_hash 304 \
    '{
      policy_id: $policy_id,
      observed_price: $observed_price,
      oracle_slot: $oracle_slot,
      current_slot: $current_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
    }'
)")"
cover_trigger_4_tx_hash="$(call_contract_and_wait "$config" "$cover_policy_manager_contract" record_observation "$(
  jq -cn \
    --argjson policy_id 1 \
    --argjson observed_price "$cover_trigger_price" \
    --argjson oracle_slot 62 \
    --argjson current_slot 62 \
    --argjson status_flags 0 \
    --argjson attestation_hash 305 \
    '{
      policy_id: $policy_id,
      observed_price: $observed_price,
      oracle_slot: $oracle_slot,
      current_slot: $current_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
    }'
)")"
cover_claim_tx_hash="$(call_contract_and_wait "$config" "$cover_policy_manager_contract" route_claim "$(
  jq -cn \
    --argjson policy_id 1 \
    '{
      policy_id: $policy_id
    }'
)")"

risk_bucket_1_view_json="$(submit_contract_view "$config" "$risk_vault_contract" bucket_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"bucket_id":1}')"
risk_bucket_2_view_json="$(submit_contract_view "$config" "$risk_vault_contract" bucket_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"bucket_id":2}')"
risk_bucket_3_view_json="$(submit_contract_view "$config" "$risk_vault_contract" bucket_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"bucket_id":3}')"
risk_vault_state_view_json="$(submit_contract_view "$config" "$risk_vault_contract" risk_state "$SORASWAP_SMOKE_GAS_LIMIT")"
risk_bucket_1_liability_view_json="$(submit_contract_view "$config" "$risk_vault_contract" liability_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"bucket_id":1,"exposure_id":1}')"
risk_bucket_1_liquidation_liability_view_json="$(submit_contract_view "$config" "$risk_vault_contract" liability_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"bucket_id":1,"exposure_id":2}')"
risk_bucket_2_shout_liability_view_json="$(submit_contract_view "$config" "$risk_vault_contract" liability_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"bucket_id":2,"exposure_id":1}')"
risk_bucket_2_outperformance_liability_view_json="$(submit_contract_view "$config" "$risk_vault_contract" liability_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"bucket_id":2,"exposure_id":2}')"
risk_bucket_3_liability_view_json="$(submit_contract_view "$config" "$risk_vault_contract" liability_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"bucket_id":3,"exposure_id":1}')"
risk_bucket_1_automation_view_json="$(submit_contract_view "$config" "$risk_vault_contract" automation_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"bucket_id":1}')"
risk_bucket_2_automation_view_json="$(submit_contract_view "$config" "$risk_vault_contract" automation_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"bucket_id":2}')"
risk_bucket_3_automation_view_json="$(submit_contract_view "$config" "$risk_vault_contract" automation_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"bucket_id":3}')"
perps_engine_config_view_json="$(submit_contract_view "$config" "$perps_engine_contract" engine_config "$SORASWAP_SMOKE_GAS_LIMIT")"
perps_market_state_view_json="$(submit_contract_view "$config" "$perps_engine_contract" market_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"market_id":1}')"
perps_market_risk_view_json="$(submit_contract_view "$config" "$perps_engine_contract" risk_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"market_id":1}')"
perps_automation_view_json="$(submit_contract_view "$config" "$perps_engine_contract" automation_state "$SORASWAP_SMOKE_GAS_LIMIT")"
perps_position_state_view_json="$(submit_contract_view "$config" "$perps_engine_contract" position_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"position_id":1}')"
perps_liquidation_position_state_view_json="$(submit_contract_view "$config" "$perps_engine_contract" position_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"position_id":2}')"
perps_liquidation_position_liquidation_view_json="$(submit_contract_view "$config" "$perps_engine_contract" position_liquidation_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"position_id":2}')"
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
options_factory_shout_position_view_json="$(submit_contract_view "$config" "$options_factory_contract" position_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"position_id":1}')"
options_factory_outperformance_position_view_json="$(submit_contract_view "$config" "$options_factory_contract" position_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"position_id":2}')"
options_vault_shout_state_view_json="$(submit_contract_view "$config" "$options_vault_contract" vault_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"series_id":1}')"
options_vault_outperformance_state_view_json="$(submit_contract_view "$config" "$options_vault_contract" vault_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"series_id":2}')"
options_vault_shout_position_view_json="$(submit_contract_view "$config" "$options_vault_contract" position_accounting "$SORASWAP_SMOKE_GAS_LIMIT" '{"position_id":1}')"
options_vault_outperformance_position_view_json="$(submit_contract_view "$config" "$options_vault_contract" position_accounting "$SORASWAP_SMOKE_GAS_LIMIT" '{"position_id":2}')"
options_shout_product_view_json="$(submit_contract_view "$config" "$options_shout_option_contract" series_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"series_id":1}')"
options_outperformance_product_view_json="$(submit_contract_view "$config" "$options_outperformance_option_contract" series_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"series_id":2}')"
options_shout_product_position_view_json="$(submit_contract_view "$config" "$options_shout_option_contract" position_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"position_id":1}')"
options_outperformance_product_position_view_json="$(submit_contract_view "$config" "$options_outperformance_option_contract" position_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"position_id":2}')"
cover_manager_config_view_json="$(submit_contract_view "$config" "$cover_policy_manager_contract" manager_config "$SORASWAP_SMOKE_GAS_LIMIT")"
cover_automation_view_json="$(submit_contract_view "$config" "$cover_policy_manager_contract" automation_state "$SORASWAP_SMOKE_GAS_LIMIT")"
cover_policy_view_json="$(submit_contract_view "$config" "$cover_policy_manager_contract" policy_state "$SORASWAP_SMOKE_GAS_LIMIT" '{"policy_id":1}')"

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
job_dispatch_tx_hash="$(call_contract_and_wait "$config" "$automation_job_queue_contract" dispatch_job "$(
  jq -cn \
    --arg job "$job_name" \
    --argjson current_slot "$automation_next_slot" \
    '{
      job: $job,
      current_slot: $current_slot
    }'
)")"
job_pause_tx_hash="$(call_contract_and_wait "$config" "$automation_job_queue_contract" pause_job "$(
  jq -cn \
    --arg job "$job_name" \
    '{ job: $job }'
)")"
job_resume_tx_hash="$(call_contract_and_wait "$config" "$automation_job_queue_contract" resume_job "$(
  jq -cn \
    --arg job "$job_name" \
    --argjson current_slot "$automation_resume_slot" \
    '{
      job: $job,
      current_slot: $current_slot
    }'
)")"
job_retry_tx_hash="$(call_contract_and_wait "$config" "$automation_job_queue_contract" retry_at "$(
  jq -cn \
    --arg job "$job_name" \
    --argjson current_slot "$automation_resume_slot" \
    '{
      job: $job,
      current_slot: $current_slot
    }'
)")"
job_retry_dispatch_tx_hash="$(call_contract_and_wait "$config" "$automation_job_queue_contract" dispatch_job "$(
  jq -cn \
    --arg job "$job_name" \
    --argjson current_slot $(( automation_resume_slot + automation_retry_delay_slots )) \
    '{
      job: $job,
      current_slot: $current_slot
    }'
)")"
job_complete_tx_hash="$(call_contract_and_wait "$config" "$automation_job_queue_contract" complete_run "$(
  jq -cn \
    --arg job "$job_name" \
    --argjson current_slot $(( automation_resume_slot + automation_retry_delay_slots )) \
    '{
      job: $job,
      current_slot: $current_slot
    }'
)")"
job_mirror_view_json="$(submit_contract_view "$config" "$automation_job_queue_contract" mirror_job "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --arg job "$job_name" \
    '{ job: $job }'
)")"
fi

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
automation_retry_run_slot=$(( automation_resume_slot + automation_retry_delay_slots ))
automation_expected_next_slot=$(( automation_retry_run_slot + automation_cron_interval_slots ))
automation_expected_run_count=2
n3x_expected_redeem_fee_usdt=$(( n3x_usdt_in * n3x_redeem_fee_bps / 10000 ))
n3x_expected_redeem_fee_usdc=$(( n3x_usdc_in * n3x_redeem_fee_bps / 10000 ))
n3x_expected_redeem_fee_kusd=$(( n3x_kusd_in * n3x_redeem_fee_bps / 10000 ))
n3x_expected_basket_usdt=$(( n3x_usdt_in - (n3x_usdt_in - n3x_expected_redeem_fee_usdt) ))
n3x_expected_basket_usdc=$(( n3x_usdc_in - (n3x_usdc_in - n3x_expected_redeem_fee_usdc) ))
n3x_expected_basket_kusd=$(( n3x_kusd_in - (n3x_kusd_in - n3x_expected_redeem_fee_kusd) ))
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
assert_view_result_equals "perps engine config" "$perps_engine_config_view_json" "$(jq -cn --arg settlement_asset "$usdt_id" --arg risk_vault "$risk_vault_contract_blob_hex" '[ $settlement_asset, $risk_vault, 0, 2, 3, 201, 202, 6 ]')"
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
assert_view_result_equals "options factory config" "$options_factory_config_view_json" "$(jq -cn --arg settlement_asset "$usdt_id" '[ $settlement_asset, 0, 3, 213, 5, 8, 0 ]')"
assert_view_result_equals "options factory shout series" "$options_factory_shout_series_view_json" "$(jq -cn --argjson max_notional "$options_shout_max_notional" --argjson premium_bps "$options_shout_base_premium_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" --argjson pause_threshold_bps "$options_factory_pause_threshold_bps" --argjson bump_percent_bps "$options_factory_bump_percent_bps" '[ 1, 1, $max_notional, $premium_bps, $collateral_multiplier_bps, 0, 0, $pause_threshold_bps, $bump_percent_bps, 0 ]')"
assert_view_result_equals "options factory outperformance series" "$options_factory_outperformance_series_view_json" "$(jq -cn --argjson max_notional "$options_outperformance_max_notional" --argjson premium_bps "$options_outperformance_base_premium_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" --argjson pause_threshold_bps "$options_factory_pause_threshold_bps" --argjson bump_percent_bps "$options_factory_bump_percent_bps" --argjson expiry_slot "$options_outperformance_expiry_slot" '[ 1, 2, $max_notional, $premium_bps, $collateral_multiplier_bps, 0, 0, $pause_threshold_bps, $bump_percent_bps, $expiry_slot ]')"
assert_view_result_equals "options factory automation" "$options_factory_automation_view_json" '[1,213,5,8,0,0,0]'
assert_view_result_equals "options factory shout position" "$options_factory_shout_position_view_json" "$(jq -cn --argjson premium "$options_shout_premium_paid" --argjson collateral_locked "$options_shout_collateral_locked" --argjson payout "$options_shout_settled_payout" --argjson notional "$options_shout_notional" '[ 1, 1, 1, $notional, $premium, $collateral_locked, 3, $payout, 1 ]')"
assert_view_result_equals "options factory outperformance position" "$options_factory_outperformance_position_view_json" "$(jq -cn --argjson premium "$options_outperformance_premium_paid" --argjson collateral_locked "$options_outperformance_collateral_locked" --argjson payout "$options_outperformance_settled_payout" --argjson notional "$options_outperformance_notional" '[ 1, 2, 2, $notional, $premium, $collateral_locked, 3, $payout, 1 ]')"
assert_view_result_equals "options vault shout state" "$options_vault_shout_state_view_json" "$(jq -cn --argjson collateral_locked $(( options_shout_collateral_locked - options_shout_settled_payout )) --argjson payout "$options_shout_settled_payout" '[ 1, $collateral_locked, 0, $payout, 0 ]')"
assert_view_result_equals "options vault outperformance state" "$options_vault_outperformance_state_view_json" "$(jq -cn --argjson collateral_locked $(( options_outperformance_collateral_locked - options_outperformance_settled_payout )) --argjson payout "$options_outperformance_settled_payout" '[ 1, $collateral_locked, 0, $payout, 0 ]')"
assert_view_result_equals "options vault shout position" "$options_vault_shout_position_view_json" "$(jq -cn --argjson collateral_locked $(( options_shout_collateral_locked - options_shout_settled_payout )) --argjson payout "$options_shout_settled_payout" '[ 1, 1, $collateral_locked, 0, $payout, 2 ]')"
assert_view_result_equals "options vault outperformance position" "$options_vault_outperformance_position_view_json" "$(jq -cn --argjson collateral_locked $(( options_outperformance_collateral_locked - options_outperformance_settled_payout )) --argjson payout "$options_outperformance_settled_payout" '[ 1, 2, $collateral_locked, 0, $payout, 2 ]')"
assert_view_result_equals "options shout product" "$options_shout_product_view_json" "$(jq -cn --argjson expiry_slot "$options_shout_expiry_slot" --argjson strike_bps "$options_shout_strike_bps" '[ 1, $expiry_slot, $strike_bps, 1 ]')"
assert_view_result_equals "options outperformance product" "$options_outperformance_product_view_json" "$(jq -cn --argjson expiry_slot "$options_outperformance_expiry_slot" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" '[ 1, $expiry_slot, $collateral_multiplier_bps, 2 ]')"
assert_view_result_equals "options shout product position" "$options_shout_product_position_view_json" "$(jq -cn --argjson notional "$options_shout_notional" --argjson strike_bps "$options_shout_strike_bps" --argjson shout_floor "$options_shout_floor_bps" --argjson last_mark "$options_shout_exercise_mark_bps" --argjson payout "$options_shout_desired_payout" '[ 1, 1, $notional, $strike_bps, $shout_floor, $last_mark, $payout, 2 ]')"
assert_view_result_equals "options outperformance product position" "$options_outperformance_product_position_view_json" "$(jq -cn --argjson notional "$options_outperformance_notional" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" --argjson final_mark "$options_outperformance_final_mark_bps" --argjson final_quote_mark "$options_outperformance_final_quote_mark_bps" --argjson payout "$options_outperformance_desired_payout" '[ 1, 2, $notional, $collateral_multiplier_bps, $final_mark, $final_quote_mark, $payout, 2 ]')"
assert_view_result_equals "cover manager config" "$cover_manager_config_view_json" "$(jq -cn --arg settlement_asset "$usdt_id" --arg risk_vault "$risk_vault_contract_blob_hex" --argjson required_observations "$cover_required_observations" --argjson stale_slots "$cover_oracle_stale_slots" '[ $settlement_asset, $risk_vault, 0, $required_observations, $stale_slots, 301, 3, 10, 0 ]')"
assert_view_result_equals "cover automation" "$cover_automation_view_json" '[1,301,3,10,0,0,0]'
assert_view_result_equals "cover policy" "$cover_policy_view_json" "$(jq -cn --argjson lower_bound "$cover_lower_bound" --argjson upper_bound "$cover_upper_bound" --argjson payout_amount "$cover_payout_amount" --argjson monitoring_window_slots "$cover_monitoring_window_slots" --argjson required_observations "$cover_policy_required_observations" --argjson covered_notional "$cover_notional" --argjson last_observed_price "$cover_trigger_price" --argjson claim_payout "$cover_expected_claim_payout" '[ 1, 4, $lower_bound, $upper_bound, $payout_amount, $monitoring_window_slots, $required_observations, $covered_notional, 2, 3, $last_observed_price, $claim_payout ]')"
fi

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
  --argjson job_mirror_result "$(contract_view_result_json "$job_mirror_view_json")" \
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
      expected_n3x_redeem_fees: $expected_n3x_redeem_fees
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
      automation_complete_run: ($job_complete_tx_hash | nullable_tx)
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
      automation_mirror_job: $job_mirror_result
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
echo "local smoke decoded state ints: $(jq -c '.decoded_state_ints' <<<"$report_json")"
echo "local smoke report: $timestamped_report"
