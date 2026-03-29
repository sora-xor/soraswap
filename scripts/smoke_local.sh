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
launchpad_sale_factory_contract="$(deployed_contract_id_for_env local launchpad.sale_factory)"
referral_registry_contract="$(deployed_contract_id_for_env local referral.registry)"
farms_farm_contract="$(deployed_contract_id_for_env local farms.farm)"
perps_engine_contract="$(deployed_contract_id_for_env local perps.perps_engine)"
options_series_manager_contract="$(deployed_contract_id_for_env local options.series_manager)"
cover_policy_manager_contract="$(deployed_contract_id_for_env local cover.policy_manager)"
automation_job_queue_contract="$(deployed_contract_id_for_env local automation.job_queue)"

iroha_cli --machine --config "$config" app contracts instances --dataspace universal --table

iroha_cli_json --config "$config" ledger asset definition get --alias "$SORASWAP_BASE_ASSET_ALIAS" \
  | jq -e --arg id "$SORASWAP_XOR_ASSET_DEFINITION_ID" '.id == $id and .name == "xor"' >/dev/null

contract_instance_exists "$config" "$n3x_hub_dataspace" "$n3x_hub_contract"
contract_instance_exists "$config" "$dlmm_pool_dataspace" "$dlmm_pool_contract"
contract_instance_exists "$config" "$dlmm_router_dataspace" "$dlmm_router_contract"

vault_account="$(treasury_account_for_mode local)"
xor_id="$(asset_definition_id_for_alias "$config" "$SORASWAP_BASE_ASSET_ALIAS")"
usdt_id="$(asset_definition_id_for_alias "$config" usdt#soraswap.universal)"
usdc_id="$(asset_definition_id_for_alias "$config" usdc#soraswap.universal)"
kusd_id="$(asset_definition_id_for_alias "$config" kusd#soraswap.universal)"
n3x_id="$(asset_definition_id_for_alias "$config" n3x#soraswap.universal)"
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
perps_position="${SORASWAP_PERPS_SMOKE_POSITION:-smoke_perps_position}"
perps_size="${SORASWAP_PERPS_SMOKE_SIZE:-1000}"
perps_initial_collateral="${SORASWAP_PERPS_SMOKE_COLLATERAL:-250}"
perps_add_collateral="${SORASWAP_PERPS_SMOKE_ADD_COLLATERAL:-50}"
perps_remove_collateral="${SORASWAP_PERPS_SMOKE_REMOVE_COLLATERAL:-40}"
perps_funding_bps="${SORASWAP_PERPS_SMOKE_FUNDING_BPS:-100}"
perps_max_leverage_bps="${SORASWAP_PERPS_SMOKE_MAX_LEVERAGE_BPS:-50000}"
perps_maintenance_margin_bps="${SORASWAP_PERPS_SMOKE_MAINTENANCE_MARGIN_BPS:-500}"
perps_liquidation_fee_bps="${SORASWAP_PERPS_SMOKE_LIQUIDATION_FEE_BPS:-1000}"
perps_entry_price_bps="${SORASWAP_PERPS_SMOKE_ENTRY_PRICE_BPS:-10000}"
perps_funding_mark_price_bps="${SORASWAP_PERPS_SMOKE_FUNDING_MARK_PRICE_BPS:-11000}"
perps_funding_index_price_bps="${SORASWAP_PERPS_SMOKE_FUNDING_INDEX_PRICE_BPS:-10000}"
perps_exit_mark_price_bps="${SORASWAP_PERPS_SMOKE_EXIT_MARK_PRICE_BPS:-10200}"
option_ticket="${SORASWAP_OPTIONS_SMOKE_TICKET:-smoke_option_ticket}"
option_void_ticket="${SORASWAP_OPTIONS_SMOKE_VOID_TICKET:-smoke_option_ticket_void}"
option_strike_price="${SORASWAP_OPTIONS_SMOKE_STRIKE_PRICE:-2}"
option_premium="${SORASWAP_OPTIONS_SMOKE_PREMIUM:-1}"
option_collateral_amount="${SORASWAP_OPTIONS_SMOKE_COLLATERAL:-4}"
option_exercise_payout="${SORASWAP_OPTIONS_SMOKE_EXERCISE_PAYOUT:-2}"
option_expiry_slot="${SORASWAP_OPTIONS_SMOKE_EXPIRY_SLOT:-12}"
cover_notional="${SORASWAP_COVER_SMOKE_NOTIONAL:-10}"
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

before_n3x="$(asset_value_for_account "$config" n3x#soraswap.universal "$SORASWAP_AUTHORITY")"
n3x_config_tx_hash="$(call_contract_and_wait "$config" "$n3x_hub_contract" configure_hub "$(
  jq -cn \
    --argjson target_usdt_bps "$n3x_target_usdt_bps" \
    --argjson target_usdc_bps "$n3x_target_usdc_bps" \
    --argjson target_kusd_bps "$n3x_target_kusd_bps" \
    --argjson mint_fee_bps "$n3x_mint_fee_bps" \
    --argjson redeem_fee_bps "$n3x_redeem_fee_bps" \
    '{
      target_usdt_bps: $target_usdt_bps,
      target_usdc_bps: $target_usdc_bps,
      target_kusd_bps: $target_kusd_bps,
      mint_fee_bps: $mint_fee_bps,
      redeem_fee_bps: $redeem_fee_bps
    }'
)")"
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
if (( perps_entry_price_bps <= 0 || perps_funding_mark_price_bps <= 0 || perps_funding_index_price_bps <= 0 || perps_exit_mark_price_bps <= 0 )); then
  echo "invalid perps price configuration for smoke: all prices must be positive" >&2
  exit 1
fi
if (( perps_funding_mark_price_bps <= perps_funding_index_price_bps )); then
  echo "invalid perps funding configuration for smoke: funding mark price must exceed index price" >&2
  exit 1
fi
if (( option_collateral_amount < option_strike_price * 2 )); then
  echo "invalid options collateral for smoke: must reserve two one-contract tickets" >&2
  exit 1
fi

mint_tx_hash="$(call_contract_and_wait "$config" "$n3x_hub_contract" deposit_and_mint_with_assets "$(
  jq -cn \
    --arg user "$SORASWAP_AUTHORITY" \
    --arg vault "$vault_account" \
    --arg usdt_asset "$usdt_id" \
    --arg usdc_asset "$usdc_id" \
    --arg kusd_asset "$kusd_id" \
    --arg n3x_asset "$n3x_id" \
    --argjson usdt_in "$n3x_usdt_in" \
    --argjson usdc_in "$n3x_usdc_in" \
    --argjson kusd_in "$n3x_kusd_in" \
    '{
      user: $user,
      vault: $vault,
      usdt_asset: $usdt_asset,
      usdc_asset: $usdc_asset,
      kusd_asset: $kusd_asset,
      n3x_asset: $n3x_asset,
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
burn_tx_hash="$(call_contract_and_wait "$config" "$n3x_hub_contract" burn_and_redeem_with_assets "$(
  jq -cn \
    --arg user "$SORASWAP_AUTHORITY" \
    --arg vault "$vault_account" \
    --arg usdt_asset "$usdt_id" \
    --arg usdc_asset "$usdc_id" \
    --arg kusd_asset "$kusd_id" \
    --arg n3x_asset "$n3x_id" \
    --argjson n3x_amount "$n3x_expected_minted" \
    '{
      user: $user,
      vault: $vault,
      usdt_asset: $usdt_asset,
      usdc_asset: $usdc_asset,
      kusd_asset: $kusd_asset,
      n3x_asset: $n3x_asset,
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
dlmm_swap_tx_hash="$(call_contract_and_wait "$config" "$dlmm_pool_contract" swap_exact_in_with_assets "$(
  jq -cn \
    --arg trader "$SORASWAP_AUTHORITY" \
    --arg input_asset "$xor_id" \
    --arg vault "$vault_account" \
    --arg base_asset "$xor_id" \
    --arg quote_asset "$usdt_id" \
    --argjson amount_in "$swap_amount_in" \
    --argjson min_out 1 \
    '{
      trader: $trader,
      input_asset: $input_asset,
      vault: $vault,
      base_asset: $base_asset,
      quote_asset: $quote_asset,
      amount_in: $amount_in,
      min_out: $min_out
    }'
)")"
dlmm_collect_position_fees_tx_hash="$(call_contract_and_wait "$config" "$dlmm_pool_contract" collect_position_fees_with_assets "$(
  jq -cn \
    --arg position_id "$pool_position_id" \
    --arg recipient "$SORASWAP_AUTHORITY" \
    --arg vault "$vault_account" \
    --arg base_asset "$xor_id" \
    --arg quote_asset "$usdt_id" \
    '{
      position_id: $position_id,
      recipient: $recipient,
      vault: $vault,
      base_asset: $base_asset,
      quote_asset: $quote_asset
    }'
)")"
dlmm_remove_position_tx_hash="$(call_contract_and_wait "$config" "$dlmm_pool_contract" remove_position_liquidity_with_assets "$(
  jq -cn \
    --arg position_id "$pool_position_id" \
    --arg recipient "$SORASWAP_AUTHORITY" \
    --arg vault "$vault_account" \
    --arg base_asset "$xor_id" \
    --arg quote_asset "$usdt_id" \
    --argjson shares "$pool_position_remove_shares" \
    '{
      position_id: $position_id,
      recipient: $recipient,
      vault: $vault,
      base_asset: $base_asset,
      quote_asset: $quote_asset,
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
launchpad_mirror_view_json='{"ok":true,"result":null}'
launchpad_mirror_accounting_view_json='{"ok":true,"result":null}'
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
farm_claim_tx_hash=""
farm_unstake_tx_hash=""
farm_mirror_view_json='{"ok":true,"result":null}'
perps_risk_tx_hash=""
perps_open_tx_hash=""
perps_add_collateral_tx_hash=""
perps_funding_tx_hash=""
perps_remove_collateral_tx_hash=""
perps_close_tx_hash=""
perps_mirror_view_json='{"ok":true,"result":null}'
option_config_tx_hash=""
option_collateral_tx_hash=""
option_buy_tx_hash=""
option_buy_void_tx_hash=""
option_exercise_tx_hash=""
option_expire_tx_hash=""
option_void_tx_hash=""
option_series_mirror_view_json='{"ok":true,"result":null}'
option_ticket_mirror_view_json='{"ok":true,"result":null}'
option_void_ticket_mirror_view_json='{"ok":true,"result":null}'
cover_config_tx_hash=""
cover_buy_tx_hash=""
cover_breach_tx_hash=""
cover_claim_tx_hash=""
cover_mirror_view_json='{"ok":true,"result":null}'
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
launchpad_config_vesting_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" configure_vesting "$(
  jq -cn \
    --arg sale "$sale_name" \
    --argjson claim_start_slot 0 \
    --argjson claim_end_slot 0 \
    '{
      sale: $sale,
      claim_start_slot: $claim_start_slot,
      claim_end_slot: $claim_end_slot
    }'
)")"
launchpad_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" contribute_recorded_with_assets "$(
  jq -cn \
    --arg buyer "$SORASWAP_AUTHORITY" \
    --arg sale "$sale_name" \
    --arg allocation "$launchpad_allocation_id" \
    --arg treasury "$vault_account" \
    --arg payment_asset "$xor_id" \
    --argjson payment_amount "$launchpad_payment_amount" \
    '{
      buyer: $buyer,
      sale: $sale,
      allocation: $allocation,
      treasury: $treasury,
      payment_asset: $payment_asset,
      payment_amount: $payment_amount
    }'
)")"
launchpad_close_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" close_sale "$(
  jq -cn \
    --arg sale "$sale_name" \
    '{ sale: $sale }'
)")"
launchpad_claim_inventory_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" deposit_claim_inventory_with_assets "$(
  jq -cn \
    --arg owner "$SORASWAP_AUTHORITY" \
    --arg sale "$sale_name" \
    --arg treasury "$vault_account" \
    --arg sale_asset "$n3x_id" \
    --argjson amount "$launchpad_claim_inventory_amount" \
    '{
      owner: $owner,
      sale: $sale,
      treasury: $treasury,
      sale_asset: $sale_asset,
      amount: $amount
    }'
)")"
launchpad_claim_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" settle_claim_assets "$(
  jq -cn \
    --arg buyer "$SORASWAP_AUTHORITY" \
    --arg allocation "$launchpad_allocation_id" \
    --arg treasury "$vault_account" \
    --arg sale_asset "$n3x_id" \
    --argjson current_slot "$launchpad_claim_slot" \
    '{
      buyer: $buyer,
      allocation: $allocation,
      treasury: $treasury,
      sale_asset: $sale_asset,
      current_slot: $current_slot
    }'
)")"
launchpad_seed_inventory_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" deposit_seed_inventory_with_assets "$(
  jq -cn \
    --arg owner "$SORASWAP_AUTHORITY" \
    --arg sale "$sale_name" \
    --arg treasury "$vault_account" \
    --arg sale_asset "$n3x_id" \
    --argjson amount "$launchpad_seed_sale_amount" \
    '{
      owner: $owner,
      sale: $sale,
      treasury: $treasury,
      sale_asset: $sale_asset,
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
launchpad_seed_liquidity_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" seed_liquidity_with_assets "$(
  jq -cn \
    --arg sale "$sale_name" \
    --arg treasury "$vault_account" \
    --arg vault_account "$vault_account" \
    --arg payment_asset "$xor_id" \
    --arg sale_asset "$n3x_id" \
    '{
      sale: $sale,
      treasury: $treasury,
      vault_account: $vault_account,
      payment_asset: $payment_asset,
      sale_asset: $sale_asset
    }'
)")"
refund_sale_init_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" init_sale "$(
  jq -cn \
    --arg sale "$refund_sale_name" \
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
    }'
)")"
refund_sale_config_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" configure_sale "$(
  jq -cn \
    --arg sale "$refund_sale_name" \
    --argjson unit_price 1 \
    --argjson soft_cap "$refund_soft_cap" \
    --argjson hard_cap 100000 \
    '{
      sale: $sale,
      unit_price: $unit_price,
      soft_cap: $soft_cap,
      hard_cap: $hard_cap
    }'
)")"
refund_sale_contribute_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" contribute_recorded_with_assets "$(
  jq -cn \
    --arg buyer "$SORASWAP_AUTHORITY" \
    --arg sale "$refund_sale_name" \
    --arg allocation "$refund_allocation_id" \
    --arg treasury "$vault_account" \
    --arg payment_asset "$xor_id" \
    --argjson payment_amount "$refund_payment_amount" \
    '{
      buyer: $buyer,
      sale: $sale,
      allocation: $allocation,
      treasury: $treasury,
      payment_asset: $payment_asset,
      payment_amount: $payment_amount
    }'
)")"
refund_sale_close_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" close_sale "$(
  jq -cn \
    --arg sale "$refund_sale_name" \
    '{ sale: $sale }'
)")"
refund_sale_refund_tx_hash="$(call_contract_and_wait "$config" "$launchpad_sale_factory_contract" settle_refund_assets "$(
  jq -cn \
    --arg buyer "$SORASWAP_AUTHORITY" \
    --arg allocation "$refund_allocation_id" \
    --arg treasury "$vault_account" \
    --arg payment_asset "$xor_id" \
    '{
      buyer: $buyer,
      allocation: $allocation,
      treasury: $treasury,
      payment_asset: $payment_asset
    }'
)")"
refund_allocation_mirror_view_json="$(submit_contract_view "$config" "$launchpad_sale_factory_contract" mirror_allocation "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --arg allocation "$refund_allocation_id" \
    '{ allocation: $allocation }'
)")"

referral_config_tx_hash="$(call_contract_and_wait "$config" "$referral_registry_contract" configure_registry "$(
  jq -cn \
    --arg reward_asset "$xor_id" \
    --arg treasury "$vault_account" \
    --argjson claim_threshold "$referral_claim_threshold" \
    '{
      reward_asset: $reward_asset,
      treasury: $treasury,
      claim_threshold: $claim_threshold
    }'
)")"
referral_tiers_tx_hash="$(call_contract_and_wait "$config" "$referral_registry_contract" configure_tiers "$(
  jq -cn \
    --argjson direct_share_bps "$referral_direct_share_bps" \
    --argjson parent_share_bps "$referral_parent_share_bps" \
    '{
      direct_share_bps: $direct_share_bps,
      parent_share_bps: $parent_share_bps
    }'
)")"
referral_parent_bind_tx_hash="$(call_contract_and_wait "$config" "$referral_registry_contract" bind_referrer "$(
  jq -cn \
    --arg member "$referral_parent_member" \
    --arg referrer "$SORASWAP_AUTHORITY" \
    '{
      member: $member,
      referrer: $referrer
    }'
)")"
referral_bind_tx_hash="$(call_contract_and_wait "$config" "$referral_registry_contract" bind_referrer_with_parent "$(
  jq -cn \
    --arg member "$referral_member" \
    --arg referrer "$SORASWAP_AUTHORITY" \
    --arg parent_member "$referral_parent_member" \
    '{
      member: $member,
      referrer: $referrer,
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
referral_claim_tx_hash="$(call_contract_and_wait "$config" "$referral_registry_contract" claim_with_assets "$(
  jq -cn \
    --arg claimant "$SORASWAP_AUTHORITY" \
    --arg member "$referral_member" \
    --arg treasury "$vault_account" \
    --arg reward_asset "$xor_id" \
    '{
      claimant: $claimant,
      member: $member,
      treasury: $treasury,
      reward_asset: $reward_asset
    }'
)")"
referral_parent_claim_tx_hash="$(call_contract_and_wait "$config" "$referral_registry_contract" claim_with_assets "$(
  jq -cn \
    --arg claimant "$SORASWAP_AUTHORITY" \
    --arg member "$referral_parent_member" \
    --arg treasury "$vault_account" \
    --arg reward_asset "$xor_id" \
    '{
      claimant: $claimant,
      member: $member,
      treasury: $treasury,
      reward_asset: $reward_asset
    }'
)")"
referral_mirror_view_json="$(submit_contract_view "$config" "$referral_registry_contract" mirror_member "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --arg member "$referral_member" \
    '{ member: $member }'
)")"

farm_config_tx_hash="$(call_contract_and_wait "$config" "$farms_farm_contract" configure_farm "$(
  jq -cn \
    --argjson reward_rate 10 \
    '{ reward_rate: $reward_rate }'
)")"
farm_fund_tx_hash="$(call_contract_and_wait "$config" "$farms_farm_contract" fund_rewards_with_assets "$(
  jq -cn \
    --arg funder "$SORASWAP_AUTHORITY" \
    --arg treasury "$vault_account" \
    --arg reward_asset "$xor_id" \
    --argjson amount "$farm_reward_fund_amount" \
    '{
      funder: $funder,
      treasury: $treasury,
      reward_asset: $reward_asset,
      amount: $amount
    }'
)")"
farm_stake_tx_hash="$(call_contract_and_wait "$config" "$farms_farm_contract" stake_with_assets "$(
  jq -cn \
    --arg staker "$SORASWAP_AUTHORITY" \
    --arg position "$farm_position" \
    --arg treasury "$vault_account" \
    --arg stake_asset "$n3x_id" \
    --argjson amount "$farm_stake_amount" \
    '{
      staker: $staker,
      position: $position,
      treasury: $treasury,
      stake_asset: $stake_asset,
      amount: $amount
    }'
)")"
farm_claim_tx_hash="$(call_contract_and_wait "$config" "$farms_farm_contract" claim_with_assets "$(
  jq -cn \
    --arg staker "$SORASWAP_AUTHORITY" \
    --arg position "$farm_position" \
    --arg treasury "$vault_account" \
    --arg reward_asset "$xor_id" \
    '{
      staker: $staker,
      position: $position,
      treasury: $treasury,
      reward_asset: $reward_asset
    }'
)")"
farm_unstake_tx_hash="$(call_contract_and_wait "$config" "$farms_farm_contract" unstake_with_assets "$(
  jq -cn \
    --arg staker "$SORASWAP_AUTHORITY" \
    --arg position "$farm_position" \
    --arg treasury "$vault_account" \
    --arg stake_asset "$n3x_id" \
    --argjson amount "$farm_unstake_amount" \
    '{
      staker: $staker,
      position: $position,
      treasury: $treasury,
      stake_asset: $stake_asset,
      amount: $amount
    }'
)")"
farm_mirror_view_json="$(submit_contract_view "$config" "$farms_farm_contract" mirror_position "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --arg position "$farm_position" \
    '{ position: $position }'
)")"

perps_risk_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" configure_risk "$(
  jq -cn \
    --argjson funding_bps "$perps_funding_bps" \
    --argjson max_leverage_bps "$perps_max_leverage_bps" \
    --argjson maintenance_margin_bps "$perps_maintenance_margin_bps" \
    --argjson liquidation_fee_bps "$perps_liquidation_fee_bps" \
    '{
      funding_bps: $funding_bps,
      max_leverage_bps: $max_leverage_bps,
      maintenance_margin_bps: $maintenance_margin_bps,
      liquidation_fee_bps: $liquidation_fee_bps
    }'
)")"
perps_open_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" open_position_priced_with_assets "$(
  jq -cn \
    --arg trader "$SORASWAP_AUTHORITY" \
    --arg position "$perps_position" \
    --arg vault_account "$vault_account" \
    --arg collateral_asset "$xor_id" \
    --argjson size "$perps_size" \
    --argjson collateral "$perps_initial_collateral" \
    --argjson entry_price_bps "$perps_entry_price_bps" \
    '{
      trader: $trader,
      position: $position,
      vault_account: $vault_account,
      collateral_asset: $collateral_asset,
      size: $size,
      collateral: $collateral,
      entry_price_bps: $entry_price_bps
    }'
)")"
perps_add_collateral_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" add_collateral_with_assets "$(
  jq -cn \
    --arg trader "$SORASWAP_AUTHORITY" \
    --arg position "$perps_position" \
    --arg vault_account "$vault_account" \
    --arg collateral_asset "$xor_id" \
    --argjson amount "$perps_add_collateral" \
    '{
      trader: $trader,
      position: $position,
      vault_account: $vault_account,
      collateral_asset: $collateral_asset,
      amount: $amount
    }'
)")"
perps_funding_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" settle_funding_with_assets "$(
  jq -cn \
    --arg trader "$SORASWAP_AUTHORITY" \
    --arg position "$perps_position" \
    --arg vault_account "$vault_account" \
    --arg collateral_asset "$xor_id" \
    --argjson funding_bps "$perps_funding_bps" \
    --argjson mark_price "$perps_funding_mark_price_bps" \
    --argjson index_price "$perps_funding_index_price_bps" \
    '{
      trader: $trader,
      position: $position,
      vault_account: $vault_account,
      collateral_asset: $collateral_asset,
      funding_bps: $funding_bps,
      mark_price: $mark_price,
      index_price: $index_price
    }'
)")"
perps_remove_collateral_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" remove_collateral_with_assets "$(
  jq -cn \
    --arg trader "$SORASWAP_AUTHORITY" \
    --arg position "$perps_position" \
    --arg vault_account "$vault_account" \
    --arg collateral_asset "$xor_id" \
    --argjson amount "$perps_remove_collateral" \
    '{
      trader: $trader,
      position: $position,
      vault_account: $vault_account,
      collateral_asset: $collateral_asset,
      amount: $amount
    }'
)")"
perps_close_tx_hash="$(call_contract_and_wait "$config" "$perps_engine_contract" close_position_marked_with_assets "$(
  jq -cn \
    --arg trader "$SORASWAP_AUTHORITY" \
    --arg position "$perps_position" \
    --arg vault_account "$vault_account" \
    --arg collateral_asset "$xor_id" \
    --argjson mark_price "$perps_exit_mark_price_bps" \
    '{
      trader: $trader,
      position: $position,
      vault_account: $vault_account,
      collateral_asset: $collateral_asset,
      mark_price: $mark_price
    }'
)")"
perps_mirror_view_json="$(submit_contract_view "$config" "$perps_engine_contract" mirror_position "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --arg position "$perps_position" \
    '{ position: $position }'
)")"

option_config_tx_hash="$(call_contract_and_wait "$config" "$options_series_manager_contract" configure_series "$(
  jq -cn \
    --arg series "$series_name" \
    --argjson strike_price "$option_strike_price" \
    --argjson premium "$option_premium" \
    --argjson expiry_slot "$option_expiry_slot" \
    --argjson active 1 \
    '{
      series: $series,
      strike_price: $strike_price,
      premium: $premium,
      expiry_slot: $expiry_slot,
      active: $active
    }'
)")"
option_collateral_tx_hash="$(call_contract_and_wait "$config" "$options_series_manager_contract" deposit_collateral_with_assets "$(
  jq -cn \
    --arg owner "$SORASWAP_AUTHORITY" \
    --arg series "$series_name" \
    --arg treasury "$vault_account" \
    --arg settlement_asset "$usdt_id" \
    --argjson amount "$option_collateral_amount" \
    '{
      owner: $owner,
      series: $series,
      treasury: $treasury,
      settlement_asset: $settlement_asset,
      amount: $amount
    }'
)")"
option_buy_tx_hash="$(call_contract_and_wait "$config" "$options_series_manager_contract" buy_option_sized_with_assets "$(
  jq -cn \
    --arg buyer "$SORASWAP_AUTHORITY" \
    --arg series "$series_name" \
    --arg ticket "$option_ticket" \
    --arg treasury "$vault_account" \
    --arg settlement_asset "$usdt_id" \
    --argjson premium "$option_premium" \
    --argjson contracts 1 \
    '{
      buyer: $buyer,
      series: $series,
      ticket: $ticket,
      treasury: $treasury,
      settlement_asset: $settlement_asset,
      premium: $premium,
      contracts: $contracts
    }'
)")"
option_buy_void_tx_hash="$(call_contract_and_wait "$config" "$options_series_manager_contract" buy_option_sized_with_assets "$(
  jq -cn \
    --arg buyer "$SORASWAP_AUTHORITY" \
    --arg series "$series_name" \
    --arg ticket "$option_void_ticket" \
    --arg treasury "$vault_account" \
    --arg settlement_asset "$usdt_id" \
    --argjson premium "$option_premium" \
    --argjson contracts 1 \
    '{
      buyer: $buyer,
      series: $series,
      ticket: $ticket,
      treasury: $treasury,
      settlement_asset: $settlement_asset,
      premium: $premium,
      contracts: $contracts
    }'
)")"
option_exercise_tx_hash="$(call_contract_and_wait "$config" "$options_series_manager_contract" exercise_with_assets "$(
  jq -cn \
    --arg buyer "$SORASWAP_AUTHORITY" \
    --arg ticket "$option_ticket" \
    --arg treasury "$vault_account" \
    --arg settlement_asset "$usdt_id" \
    --argjson payout "$option_exercise_payout" \
    '{
      buyer: $buyer,
      ticket: $ticket,
      treasury: $treasury,
      settlement_asset: $settlement_asset,
      payout: $payout
    }'
)")"
option_expire_tx_hash="$(call_contract_and_wait "$config" "$options_series_manager_contract" expire_series "$(
  jq -cn \
    --arg series "$series_name" \
    --argjson current_slot "$option_expiry_slot" \
    '{
      series: $series,
      current_slot: $current_slot
    }'
)")"
option_void_tx_hash="$(call_contract_and_wait "$config" "$options_series_manager_contract" void_expired_ticket "$(
  jq -cn \
    --arg ticket "$option_void_ticket" \
    '{ ticket: $ticket }'
)")"
option_series_mirror_view_json="$(submit_contract_view "$config" "$options_series_manager_contract" mirror_series "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --arg series "$series_name" \
    '{ series: $series }'
)")"
option_ticket_mirror_view_json="$(submit_contract_view "$config" "$options_series_manager_contract" mirror_ticket "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --arg ticket "$option_ticket" \
    '{ ticket: $ticket }'
)")"
option_void_ticket_mirror_view_json="$(submit_contract_view "$config" "$options_series_manager_contract" mirror_ticket "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --arg ticket "$option_void_ticket" \
    '{ ticket: $ticket }'
)")"

cover_config_tx_hash="$(call_contract_and_wait "$config" "$cover_policy_manager_contract" configure_policy "$(
  jq -cn \
    --arg policy "$policy_name" \
    --argjson duration_slots 10 \
    --argjson payout_bps 8000 \
    --argjson premium 5 \
    '{
      policy: $policy,
      duration_slots: $duration_slots,
      payout_bps: $payout_bps,
      premium: $premium
    }'
)")"
cover_buy_tx_hash="$(call_contract_and_wait "$config" "$cover_policy_manager_contract" buy_policy_sized_with_assets "$(
  jq -cn \
    --arg buyer "$SORASWAP_AUTHORITY" \
    --arg policy "$policy_name" \
    --arg vault_account "$vault_account" \
    --arg settlement_asset "$usdt_id" \
    --argjson premium 5 \
    --argjson covered_notional "$cover_notional" \
    '{
      buyer: $buyer,
      policy: $policy,
      vault_account: $vault_account,
      settlement_asset: $settlement_asset,
      premium: $premium,
      covered_notional: $covered_notional
    }'
)")"
cover_breach_tx_hash="$(call_contract_and_wait "$config" "$cover_policy_manager_contract" record_breach "$(
  jq -cn \
    --arg policy "$policy_name" \
    --argjson elapsed_slots 10 \
    '{
      policy: $policy,
      elapsed_slots: $elapsed_slots
    }'
)")"
cover_claim_tx_hash="$(call_contract_and_wait "$config" "$cover_policy_manager_contract" settle_claim_with_assets "$(
  jq -cn \
    --arg claimant "$SORASWAP_AUTHORITY" \
    --arg policy "$policy_name" \
    --arg vault_account "$vault_account" \
    --arg settlement_asset "$usdt_id" \
    --argjson covered_notional "$cover_notional" \
    '{
      claimant: $claimant,
      policy: $policy,
      vault_account: $vault_account,
      settlement_asset: $settlement_asset,
      covered_notional: $covered_notional
    }'
)")"
cover_mirror_view_json="$(submit_contract_view "$config" "$cover_policy_manager_contract" mirror_policy "$SORASWAP_SMOKE_GAS_LIMIT" "$(
  jq -cn \
    --arg policy "$policy_name" \
    '{ policy: $policy }'
)")"

job_enqueue_tx_hash="$(call_contract_and_wait "$config" "$automation_job_queue_contract" enqueue "$(
  jq -cn \
    --arg job "$job_name" \
    --arg owner "$SORASWAP_AUTHORITY" \
    --argjson payload_hash 123456 \
    '{
      job: $job,
      owner: $owner,
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
    --arg executor "$automation_executor" \
    --argjson current_slot "$automation_next_slot" \
    '{
      job: $job,
      executor: $executor,
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
    --arg executor "$automation_executor" \
    --argjson current_slot $(( automation_resume_slot + automation_retry_delay_slots )) \
    '{
      job: $job,
      executor: $executor,
      current_slot: $current_slot
    }'
)")"
job_complete_tx_hash="$(call_contract_and_wait "$config" "$automation_job_queue_contract" complete_run "$(
  jq -cn \
    --arg job "$job_name" \
    --arg executor "$automation_executor" \
    --argjson current_slot $(( automation_resume_slot + automation_retry_delay_slots )) \
    '{
      job: $job,
      executor: $executor,
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
    --argjson add "$(contract_view_result_object "$perps_mirror_view_json" \
      soraswap_perps_position_registered \
      soraswap_perps_size \
      soraswap_perps_collateral \
      soraswap_perps_funding_accrued \
      soraswap_perps_realized_pnl \
      soraswap_perps_liquidated \
      soraswap_perps_funding_bps \
      soraswap_perps_max_leverage_bps \
      soraswap_perps_maintenance_margin_bps \
      soraswap_perps_liquidation_fee_bps \
      soraswap_perps_entry_price_bps \
      soraswap_perps_mark_price_bps \
      soraswap_perps_index_price_bps)" \
    <<<"$decoded_state_ints")"
  decoded_state_ints="$(jq -c '. + $add' \
    --argjson add "$(contract_view_result_object "$option_series_mirror_view_json" \
      soraswap_options_strike_price \
      soraswap_options_premium \
      soraswap_options_expiry_slot \
      soraswap_options_series_active \
      soraswap_options_tickets_issued \
      soraswap_options_tickets_exercised \
      soraswap_options_tickets_voided \
      soraswap_options_series_collateral_inventory \
      soraswap_options_series_collateral_reserved \
      soraswap_options_series_collateral_paid)" \
    <<<"$decoded_state_ints")"
  decoded_state_ints="$(jq -c '. + $add' \
    --argjson add "$(contract_view_result_object "$option_ticket_mirror_view_json" \
      soraswap_options_ticket_registered \
      soraswap_options_ticket_active \
      soraswap_options_ticket_premium_paid \
      soraswap_options_ticket_contracts \
      soraswap_options_ticket_collateral_reserved \
      soraswap_options_ticket_payout_paid)" \
    <<<"$decoded_state_ints")"
  decoded_state_ints="$(jq -c '. + $add' \
    --argjson add "$(contract_view_result_object "$option_void_ticket_mirror_view_json" \
      soraswap_options_void_ticket_registered \
      soraswap_options_void_ticket_active \
      soraswap_options_void_ticket_premium_paid \
      soraswap_options_void_ticket_contracts \
      soraswap_options_void_ticket_collateral_reserved \
      soraswap_options_void_ticket_payout_paid)" \
    <<<"$decoded_state_ints")"
  decoded_state_ints="$(jq -c '. + $add' \
    --argjson add "$(contract_view_result_object "$cover_mirror_view_json" \
      soraswap_cover_active \
      soraswap_cover_duration_slots \
      soraswap_cover_payout_bps \
      soraswap_cover_premium_paid \
      soraswap_cover_notional \
      soraswap_cover_breach_elapsed \
      soraswap_cover_claim_payout \
      soraswap_cover_expired \
      soraswap_cover_claim_count)" \
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
farm_expected_claim=$(( farm_stake_amount * 10 ))
farm_expected_stake=$(( farm_stake_amount - farm_unstake_amount ))
farm_expected_reward_budget=$(( farm_reward_fund_amount - farm_expected_claim ))
perps_expected_funding=$(( perps_size * (perps_funding_mark_price_bps - perps_funding_index_price_bps) * perps_funding_bps / 10000 / 10000 ))
if (( perps_expected_funding <= 0 )); then
  echo "invalid perps smoke parameters: funding settlement rounded to zero" >&2
  exit 1
fi
perps_expected_realized_pnl=$(( perps_size * (perps_exit_mark_price_bps - perps_entry_price_bps) / 10000 ))
perps_expected_close_payout=$(( perps_initial_collateral + perps_add_collateral - perps_expected_funding - perps_remove_collateral + perps_expected_realized_pnl ))
option_expected_series_collateral_inventory=$(( option_collateral_amount - option_exercise_payout ))
automation_retry_run_slot=$(( automation_resume_slot + automation_retry_delay_slots ))
automation_expected_next_slot=$(( automation_retry_run_slot + automation_cron_interval_slots ))
automation_expected_run_count=2
cover_expected_claim_payout=$(( cover_notional * 8000 / 10000 ))
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
    .soraswap_dlmm_pool_reserve_base == $expected_pool_reserve_base and
    .soraswap_dlmm_pool_reserve_quote == $expected_pool_reserve_quote and
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

if [[ "$smoke_scope" != "foundation" ]]; then
if ! jq -e \
  --argjson expected_launchpad_payment "$launchpad_payment_amount" \
  --argjson expected_launchpad_sale "$launchpad_payment_amount" \
  --argjson expected_launchpad_claim_inventory 0 \
  --argjson expected_launchpad_claimed_supply "$launchpad_payment_amount" \
  --argjson expected_launchpad_refunded_payment 0 \
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
  --argjson expected_farm_stake "$farm_expected_stake" \
  --argjson expected_farm_claim "$farm_expected_claim" \
  --argjson expected_farm_reward_budget "$farm_expected_reward_budget" \
  --argjson expected_perps_funding "$perps_expected_funding" \
  --argjson expected_perps_realized_pnl "$perps_expected_realized_pnl" \
  --argjson expected_perps_funding_bps "$perps_funding_bps" \
  --argjson expected_perps_max_leverage_bps "$perps_max_leverage_bps" \
  --argjson expected_perps_maintenance_margin_bps "$perps_maintenance_margin_bps" \
  --argjson expected_perps_liquidation_fee_bps "$perps_liquidation_fee_bps" \
  --argjson expected_perps_entry_price_bps "$perps_entry_price_bps" \
  --argjson expected_perps_mark_price_bps "$perps_exit_mark_price_bps" \
  --argjson expected_perps_index_price_bps "$perps_funding_index_price_bps" \
  --argjson expected_option_strike_price "$option_strike_price" \
  --argjson expected_option_premium "$option_premium" \
  --argjson expected_option_expiry_slot "$option_expiry_slot" \
  --argjson expected_option_series_collateral_inventory "$option_expected_series_collateral_inventory" \
  --argjson expected_option_exercise_payout "$option_exercise_payout" \
  --argjson expected_cover_notional "$cover_notional" \
  --argjson expected_cover_claim_payout "$cover_expected_claim_payout" \
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
    .soraswap_farm_accrued == 0 and
    .soraswap_farm_claimed == $expected_farm_claim and
    .soraswap_farm_total_staked == $expected_farm_stake and
    .soraswap_farm_reward_budget == $expected_farm_reward_budget and
    .soraswap_farm_reward_distributed == $expected_farm_claim and
    .soraswap_farm_reward_rate == 10 and
    .soraswap_perps_position_registered == 1 and
    .soraswap_perps_size == 0 and
    .soraswap_perps_collateral == 0 and
    .soraswap_perps_funding_accrued == $expected_perps_funding and
    .soraswap_perps_realized_pnl == $expected_perps_realized_pnl and
    .soraswap_perps_liquidated == 0 and
    .soraswap_perps_funding_bps == $expected_perps_funding_bps and
    .soraswap_perps_max_leverage_bps == $expected_perps_max_leverage_bps and
    .soraswap_perps_maintenance_margin_bps == $expected_perps_maintenance_margin_bps and
    .soraswap_perps_liquidation_fee_bps == $expected_perps_liquidation_fee_bps and
    .soraswap_perps_entry_price_bps == $expected_perps_entry_price_bps and
    .soraswap_perps_mark_price_bps == $expected_perps_mark_price_bps and
    .soraswap_perps_index_price_bps == $expected_perps_index_price_bps and
    .soraswap_options_strike_price == $expected_option_strike_price and
    .soraswap_options_premium == $expected_option_premium and
    .soraswap_options_expiry_slot == $expected_option_expiry_slot and
    .soraswap_options_series_active == 0 and
    .soraswap_options_tickets_issued == 2 and
    .soraswap_options_tickets_exercised == 1 and
    .soraswap_options_tickets_voided == 1 and
    .soraswap_options_series_collateral_inventory == $expected_option_series_collateral_inventory and
    .soraswap_options_series_collateral_reserved == 0 and
    .soraswap_options_series_collateral_paid == $expected_option_exercise_payout and
    .soraswap_options_ticket_registered == 1 and
    .soraswap_options_ticket_active == 0 and
    .soraswap_options_ticket_premium_paid == $expected_option_premium and
    .soraswap_options_ticket_contracts == 1 and
    .soraswap_options_ticket_collateral_reserved == 0 and
    .soraswap_options_ticket_payout_paid == $expected_option_exercise_payout and
    .soraswap_options_void_ticket_registered == 1 and
    .soraswap_options_void_ticket_active == 0 and
    .soraswap_options_void_ticket_premium_paid == $expected_option_premium and
    .soraswap_options_void_ticket_contracts == 1 and
    .soraswap_options_void_ticket_collateral_reserved == 0 and
    .soraswap_options_void_ticket_payout_paid == 0 and
    .soraswap_cover_active == 0 and
    .soraswap_cover_duration_slots == 10 and
    .soraswap_cover_payout_bps == 8000 and
    .soraswap_cover_premium_paid == 5 and
    .soraswap_cover_notional == $expected_cover_notional and
    .soraswap_cover_breach_elapsed == 10 and
    .soraswap_cover_claim_payout == $expected_cover_claim_payout and
    .soraswap_cover_expired == 0 and
    .soraswap_cover_claim_count == 1 and
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
  --argjson expected_referral_member_total "$referral_expected_member_share" \
  --argjson expected_referral_parent_total "$referral_expected_parent_share" \
  --argjson expected_farm_stake "$farm_expected_stake" \
  --argjson expected_farm_claim "$farm_expected_claim" \
  --argjson expected_perps_funding "$perps_expected_funding" \
  --argjson expected_perps_realized_pnl "$perps_expected_realized_pnl" \
  --argjson expected_perps_close_payout "$perps_expected_close_payout" \
  --argjson expected_option_series_collateral_inventory "$option_expected_series_collateral_inventory" \
  --argjson expected_option_exercise_payout "$option_exercise_payout" \
  --argjson expected_cover_claim_payout "$cover_expected_claim_payout" \
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
  --arg farm_claim_tx_hash "$farm_claim_tx_hash" \
  --arg farm_unstake_tx_hash "$farm_unstake_tx_hash" \
  --arg perps_risk_tx_hash "$perps_risk_tx_hash" \
  --arg perps_open_tx_hash "$perps_open_tx_hash" \
  --arg perps_add_collateral_tx_hash "$perps_add_collateral_tx_hash" \
  --arg perps_funding_tx_hash "$perps_funding_tx_hash" \
  --arg perps_remove_collateral_tx_hash "$perps_remove_collateral_tx_hash" \
  --arg perps_close_tx_hash "$perps_close_tx_hash" \
  --arg option_config_tx_hash "$option_config_tx_hash" \
  --arg option_collateral_tx_hash "$option_collateral_tx_hash" \
  --arg option_buy_tx_hash "$option_buy_tx_hash" \
  --arg option_buy_void_tx_hash "$option_buy_void_tx_hash" \
  --arg option_exercise_tx_hash "$option_exercise_tx_hash" \
  --arg option_expire_tx_hash "$option_expire_tx_hash" \
  --arg option_void_tx_hash "$option_void_tx_hash" \
  --arg cover_config_tx_hash "$cover_config_tx_hash" \
  --arg cover_buy_tx_hash "$cover_buy_tx_hash" \
  --arg cover_breach_tx_hash "$cover_breach_tx_hash" \
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
  --argjson router_mirror_result "$(contract_view_result_json "$router_mirror_view_json")" \
  --argjson pool_mirror_result "$(contract_view_result_json "$pool_mirror_view_json")" \
  --argjson launchpad_mirror_result "$(contract_view_result_json "$launchpad_mirror_view_json")" \
  --argjson launchpad_mirror_accounting_result "$(contract_view_result_json "$launchpad_mirror_accounting_view_json")" \
  --argjson refund_allocation_mirror_result "$(contract_view_result_json "$refund_allocation_mirror_view_json")" \
  --argjson referral_mirror_result "$(contract_view_result_json "$referral_mirror_view_json")" \
  --argjson farm_mirror_result "$(contract_view_result_json "$farm_mirror_view_json")" \
  --argjson perps_mirror_result "$(contract_view_result_json "$perps_mirror_view_json")" \
  --argjson option_series_mirror_result "$(contract_view_result_json "$option_series_mirror_view_json")" \
  --argjson option_ticket_mirror_result "$(contract_view_result_json "$option_ticket_mirror_view_json")" \
  --argjson option_void_ticket_mirror_result "$(contract_view_result_json "$option_void_ticket_mirror_view_json")" \
  --argjson cover_mirror_result "$(contract_view_result_json "$cover_mirror_view_json")" \
  --argjson job_mirror_result "$(contract_view_result_json "$job_mirror_view_json")" \
  --argjson decoded_state_ints "$decoded_state_ints" \
  '{
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
      expected_referral_member_total: $expected_referral_member_total,
      expected_referral_parent_total: $expected_referral_parent_total,
      expected_farm_stake: $expected_farm_stake,
      expected_farm_claim: $expected_farm_claim,
      expected_perps_funding: $expected_perps_funding,
      expected_perps_realized_pnl: $expected_perps_realized_pnl,
      expected_perps_close_payout: $expected_perps_close_payout,
      expected_option_series_collateral_inventory: $expected_option_series_collateral_inventory,
      expected_option_exercise_payout: $expected_option_exercise_payout,
      expected_cover_claim_payout: $expected_cover_claim_payout,
      expected_automation_next_slot: $expected_automation_next_slot,
      expected_automation_retry_run_slot: $expected_automation_retry_run_slot,
      expected_automation_cron_interval_slots: $expected_automation_cron_interval_slots,
      expected_automation_run_count: $expected_automation_run_count,
      expected_n3x_mint_fee: $expected_n3x_mint_fee,
      expected_n3x_redeem_fees: $expected_n3x_redeem_fees
    },
    tx_hashes: {
      n3x_configure_hub: $n3x_config_tx_hash,
      n3x_deposit_and_mint: $mint_tx_hash,
      n3x_burn_and_redeem: $burn_tx_hash,
      dlmm_pool_swap_exact_in_with_assets: $dlmm_swap_tx_hash,
      dlmm_pool_collect_position_fees_with_assets: $dlmm_collect_position_fees_tx_hash,
      dlmm_pool_remove_position_liquidity_with_assets: $dlmm_remove_position_tx_hash,
      launchpad_contribute: $launchpad_tx_hash,
      launchpad_configure_vesting: $launchpad_config_vesting_tx_hash,
      launchpad_close: $launchpad_close_tx_hash,
      launchpad_deposit_claim_inventory: $launchpad_claim_inventory_tx_hash,
      launchpad_claim_allocation: $launchpad_claim_tx_hash,
      launchpad_deposit_seed_inventory: $launchpad_seed_inventory_tx_hash,
      launchpad_register_seed_liquidity: $launchpad_register_seed_tx_hash,
      launchpad_seed_liquidity_with_assets: $launchpad_seed_liquidity_tx_hash,
      launchpad_refund_sale_init: $refund_sale_init_tx_hash,
      launchpad_refund_sale_configure: $refund_sale_config_tx_hash,
      launchpad_refund_sale_contribute: $refund_sale_contribute_tx_hash,
      launchpad_refund_sale_close: $refund_sale_close_tx_hash,
      launchpad_refund_allocation: $refund_sale_refund_tx_hash,
      referral_configure: $referral_config_tx_hash,
      referral_configure_tiers: $referral_tiers_tx_hash,
      referral_bind_parent: $referral_parent_bind_tx_hash,
      referral_bind: $referral_bind_tx_hash,
      referral_accrue: $referral_accrue_tx_hash,
      referral_claim: $referral_claim_tx_hash,
      referral_parent_claim: $referral_parent_claim_tx_hash,
      farms_configure: $farm_config_tx_hash,
      farms_fund_rewards: $farm_fund_tx_hash,
      farms_stake: $farm_stake_tx_hash,
      farms_claim: $farm_claim_tx_hash,
      farms_unstake: $farm_unstake_tx_hash,
      perps_configure_risk: $perps_risk_tx_hash,
      perps_open: $perps_open_tx_hash,
      perps_add_collateral: $perps_add_collateral_tx_hash,
      perps_settle_funding: $perps_funding_tx_hash,
      perps_remove_collateral: $perps_remove_collateral_tx_hash,
      perps_close: $perps_close_tx_hash,
      options_configure_series: $option_config_tx_hash,
      options_deposit_collateral: $option_collateral_tx_hash,
      options_buy: $option_buy_tx_hash,
      options_buy_void_ticket: $option_buy_void_tx_hash,
      options_exercise: $option_exercise_tx_hash,
      options_expire_series: $option_expire_tx_hash,
      options_void_expired_ticket: $option_void_tx_hash,
      cover_configure_policy: $cover_config_tx_hash,
      cover_buy: $cover_buy_tx_hash,
      cover_record_breach: $cover_breach_tx_hash,
      cover_settle_claim: $cover_claim_tx_hash,
      automation_enqueue: $job_enqueue_tx_hash,
      automation_configure: $job_config_tx_hash,
      automation_assign_executor: $job_assign_executor_tx_hash,
      automation_configure_cron: $job_cron_tx_hash,
      automation_dispatch: $job_dispatch_tx_hash,
      automation_pause: $job_pause_tx_hash,
      automation_resume: $job_resume_tx_hash,
      automation_retry: $job_retry_tx_hash,
      automation_retry_dispatch: $job_retry_dispatch_tx_hash,
      automation_complete_run: $job_complete_tx_hash
    },
    view_results: {
      n3x_quote_mint: $n3x_quote_result,
      n3x_quote_redeem: $redeem_quote_result,
      dlmm_router_quote_bin: $router_bin_quote_result,
      n3x_assert_initialized: $n3x_assert_result,
      n3x_mirror_state: $n3x_mirror_result,
      dlmm_router_assert_config: $router_assert_result,
      dlmm_router_mirror_state: $router_mirror_result,
      dlmm_pool_mirror_state: $pool_mirror_result,
      launchpad_mirror_sale: $launchpad_mirror_result,
      launchpad_mirror_sale_accounting: $launchpad_mirror_accounting_result,
      launchpad_mirror_refund_allocation: $refund_allocation_mirror_result,
      referral_mirror_member: $referral_mirror_result,
      farms_mirror_position: $farm_mirror_result,
      perps_mirror_position: $perps_mirror_result,
      options_mirror_series: $option_series_mirror_result,
      options_mirror_ticket: $option_ticket_mirror_result,
      options_mirror_void_ticket: $option_void_ticket_mirror_result,
      cover_mirror_policy: $cover_mirror_result,
      automation_mirror_job: $job_mirror_result
    },
    decoded_state_ints: $decoded_state_ints
  }')"

printf '%s\n' "$report_json" > "$latest_report"
printf '%s\n' "$report_json" > "$timestamped_report"

echo "local smoke committed n3x config tx: $n3x_config_tx_hash"
echo "local smoke n3x quote result: $(contract_view_result_json "$n3x_quote_view_json")"
echo "local smoke committed mint tx: $mint_tx_hash"
echo "local smoke n3x redeem quote result: $(contract_view_result_json "$redeem_quote_view_json")"
echo "local smoke committed burn tx: $burn_tx_hash"
echo "local smoke router bin quote result: $(contract_view_result_json "$router_bin_quote_view_json")"
echo "local smoke committed dlmm swap tx: $dlmm_swap_tx_hash"
echo "local smoke committed dlmm collect-fees tx: $dlmm_collect_position_fees_tx_hash"
echo "local smoke committed dlmm remove-position tx: $dlmm_remove_position_tx_hash"
echo "local smoke committed launchpad tx: $launchpad_tx_hash"
echo "local smoke committed launchpad vesting-config tx: $launchpad_config_vesting_tx_hash"
echo "local smoke committed launchpad close tx: $launchpad_close_tx_hash"
echo "local smoke committed launchpad claim-inventory tx: $launchpad_claim_inventory_tx_hash"
echo "local smoke committed launchpad claim tx: $launchpad_claim_tx_hash"
echo "local smoke committed launchpad seed-inventory tx: $launchpad_seed_inventory_tx_hash"
echo "local smoke committed launchpad register-seed tx: $launchpad_register_seed_tx_hash"
echo "local smoke committed launchpad seed-liquidity tx: $launchpad_seed_liquidity_tx_hash"
echo "local smoke committed refund-sale init tx: $refund_sale_init_tx_hash"
echo "local smoke committed refund-sale config tx: $refund_sale_config_tx_hash"
echo "local smoke committed refund-sale contribute tx: $refund_sale_contribute_tx_hash"
echo "local smoke committed refund-sale close tx: $refund_sale_close_tx_hash"
echo "local smoke committed refund allocation tx: $refund_sale_refund_tx_hash"
echo "local smoke committed referral config tx: $referral_config_tx_hash"
echo "local smoke committed referral tiers tx: $referral_tiers_tx_hash"
echo "local smoke committed referral parent-bind tx: $referral_parent_bind_tx_hash"
echo "local smoke committed referral bind tx: $referral_bind_tx_hash"
echo "local smoke committed referral accrue tx: $referral_accrue_tx_hash"
echo "local smoke committed referral claim tx: $referral_claim_tx_hash"
echo "local smoke committed referral parent-claim tx: $referral_parent_claim_tx_hash"
echo "local smoke referral mirror result: $(contract_view_result_json "$referral_mirror_view_json")"
echo "local smoke committed farm config tx: $farm_config_tx_hash"
echo "local smoke committed farm fund tx: $farm_fund_tx_hash"
echo "local smoke committed farm stake tx: $farm_stake_tx_hash"
echo "local smoke committed farm claim tx: $farm_claim_tx_hash"
echo "local smoke committed farm unstake tx: $farm_unstake_tx_hash"
echo "local smoke farm mirror result: $(contract_view_result_json "$farm_mirror_view_json")"
echo "local smoke committed perps risk tx: $perps_risk_tx_hash"
echo "local smoke committed perps open tx: $perps_open_tx_hash"
echo "local smoke committed perps add-collateral tx: $perps_add_collateral_tx_hash"
echo "local smoke committed perps funding tx: $perps_funding_tx_hash"
echo "local smoke committed perps remove-collateral tx: $perps_remove_collateral_tx_hash"
echo "local smoke committed perps close tx: $perps_close_tx_hash"
echo "local smoke perps mirror result: $(contract_view_result_json "$perps_mirror_view_json")"
echo "local smoke committed option config tx: $option_config_tx_hash"
echo "local smoke committed option collateral tx: $option_collateral_tx_hash"
echo "local smoke committed option buy tx: $option_buy_tx_hash"
echo "local smoke committed option buy-void-ticket tx: $option_buy_void_tx_hash"
echo "local smoke committed option exercise tx: $option_exercise_tx_hash"
echo "local smoke committed option expire tx: $option_expire_tx_hash"
echo "local smoke committed option void tx: $option_void_tx_hash"
echo "local smoke option series mirror result: $(contract_view_result_json "$option_series_mirror_view_json")"
echo "local smoke option ticket mirror result: $(contract_view_result_json "$option_ticket_mirror_view_json")"
echo "local smoke option void-ticket mirror result: $(contract_view_result_json "$option_void_ticket_mirror_view_json")"
echo "local smoke committed cover config tx: $cover_config_tx_hash"
echo "local smoke committed cover buy tx: $cover_buy_tx_hash"
echo "local smoke committed cover breach tx: $cover_breach_tx_hash"
echo "local smoke committed cover claim tx: $cover_claim_tx_hash"
echo "local smoke cover mirror result: $(contract_view_result_json "$cover_mirror_view_json")"
echo "local smoke committed automation enqueue tx: $job_enqueue_tx_hash"
echo "local smoke committed automation config tx: $job_config_tx_hash"
echo "local smoke committed automation assign-executor tx: $job_assign_executor_tx_hash"
echo "local smoke committed automation cron tx: $job_cron_tx_hash"
echo "local smoke committed automation dispatch tx: $job_dispatch_tx_hash"
echo "local smoke committed automation pause tx: $job_pause_tx_hash"
echo "local smoke committed automation resume tx: $job_resume_tx_hash"
echo "local smoke committed automation retry tx: $job_retry_tx_hash"
echo "local smoke committed automation retry-dispatch tx: $job_retry_dispatch_tx_hash"
echo "local smoke committed automation complete-run tx: $job_complete_tx_hash"
echo "local smoke automation mirror result: $(contract_view_result_json "$job_mirror_view_json")"
echo "local smoke decoded state ints: $(jq -c '.decoded_state_ints' <<<"$report_json")"
echo "local smoke report: $timestamped_report"
