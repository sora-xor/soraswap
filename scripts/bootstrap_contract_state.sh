#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

mode="${1:-local}"
if [[ "$mode" == "production" ]]; then
  export SORASWAP_PUBLIC_ENV=production
  readonly SORASWAP_PUBLIC_ENV
fi
bootstrap_secret_dir="$(soraswap_secure_temp_directory bootstrap-secrets)" || exit 1
cleanup_bootstrap_secret_dir() {
  soraswap_cleanup_oracle_client_config || return 1
  if ! soraswap_secure_cleanup_owned_directory "$bootstrap_secret_dir"; then
    echo "bootstrap secret directory identity changed or contains an unowned entry; refusing unsafe cleanup" >&2
    return 1
  fi
}
trap cleanup_bootstrap_secret_dir EXIT
case "$mode" in
  testnet|production)
    require_public_mutation_consent "$mode" "$mode contract-state bootstrap"
    ;;
esac

bootstrap_scope="${SORASWAP_BOOTSTRAP_SCOPE:-${SORASWAP_DEPLOY_SCOPE:-full}}"
pool_fee_pips="${SORASWAP_POOL_FEE_PIPS:-3000}"
pool_active_bin="${SORASWAP_POOL_ACTIVE_BIN:-0}"
trigger_lifecycle_cadence_slots="${SORASWAP_TRIGGER_LIFECYCLE_CADENCE_SLOTS:-4}"
trigger_lifecycle_max_items="${SORASWAP_TRIGGER_LIFECYCLE_MAX_ITEMS:-4}"
trigger_lifecycle_enabled="${SORASWAP_TRIGGER_LIFECYCLE_ENABLED:-1}"
perps_trigger_lifecycle_max_items="${SORASWAP_PERPS_TRIGGER_LIFECYCLE_MAX_ITEMS:-4}"
dlmm_range_governor_cadence_slots="${SORASWAP_DLMM_RANGE_GOVERNOR_CADENCE_SLOTS:-4}"
dlmm_range_governor_max_fee_pips="${SORASWAP_DLMM_RANGE_GOVERNOR_MAX_FEE_PIPS:-$pool_fee_pips}"
dlmm_range_governor_target_active_bin="${SORASWAP_DLMM_RANGE_GOVERNOR_TARGET_ACTIVE_BIN:-$pool_active_bin}"
dlmm_range_governor_max_active_bin_drift="${SORASWAP_DLMM_RANGE_GOVERNOR_MAX_ACTIVE_BIN_DRIFT:-2}"
dlmm_range_governor_enabled="${SORASWAP_DLMM_RANGE_GOVERNOR_ENABLED:-1}"
twamm_trigger_cadence_slots="${SORASWAP_TWAMM_TRIGGER_CADENCE_SLOTS:-2}"
twamm_trigger_max_orders_per_tick="${SORASWAP_TWAMM_TRIGGER_MAX_ORDERS_PER_TICK:-4}"
twamm_trigger_enabled="${SORASWAP_TWAMM_TRIGGER_ENABLED:-1}"
epoch_auction_epoch_id="${SORASWAP_EPOCH_AUCTION_EPOCH_ID:-1}"
epoch_auction_duration_slots="${SORASWAP_EPOCH_AUCTION_DURATION_SLOTS:-12}"
epoch_auction_lower_tick="${SORASWAP_EPOCH_AUCTION_LOWER_TICK:-900000}"
epoch_auction_upper_tick="${SORASWAP_EPOCH_AUCTION_UPPER_TICK:-1100000}"
epoch_auction_tick_step="${SORASWAP_EPOCH_AUCTION_TICK_STEP:-10000}"
epoch_auction_max_orders="${SORASWAP_EPOCH_AUCTION_MAX_ORDERS:-32}"
bootstrap_controller_sync_pipeline_wait_secs="${SORASWAP_BOOTSTRAP_CONTROLLER_SYNC_PIPELINE_WAIT_SECS:-20}"
bootstrap_controller_sync_committed_wait_secs="${SORASWAP_BOOTSTRAP_CONTROLLER_SYNC_COMMITTED_WAIT_SECS:-20}"
case "$mode" in
  testnet|production)
    default_bootstrap_view_retry_attempts=60
    default_bootstrap_apply_retry_attempts=3
    ;;
  *)
    default_bootstrap_view_retry_attempts=15
    default_bootstrap_apply_retry_attempts=1
    ;;
esac
bootstrap_view_retry_attempts="${SORASWAP_BOOTSTRAP_VIEW_RETRY_ATTEMPTS:-$default_bootstrap_view_retry_attempts}"
bootstrap_view_retry_sleep_secs="${SORASWAP_BOOTSTRAP_VIEW_RETRY_SLEEP_SECS:-1}"
bootstrap_apply_retry_attempts="${SORASWAP_BOOTSTRAP_APPLY_RETRY_ATTEMPTS:-$default_bootstrap_apply_retry_attempts}"
bootstrap_apply_retry_sleep_secs="${SORASWAP_BOOTSTRAP_APPLY_RETRY_SLEEP_SECS:-3}"
warm_view_timeout_secs="${SORASWAP_WARM_VIEW_TIMEOUT_SECS:-5}"

case "$bootstrap_scope" in
  foundation|full)
    ;;
  *)
    echo "SORASWAP_BOOTSTRAP_SCOPE must be foundation or full; got '$bootstrap_scope'" >&2
    exit 1
    ;;
esac
if [[ "$mode" == "local" \
  && "${SORASWAP_DEPLOY_SCOPE:-full}" == "foundation" \
  && "$bootstrap_scope" != "foundation" ]]; then
  echo "full bootstrap requires SORASWAP_DEPLOY_SCOPE=full" >&2
  exit 1
fi
rwa_release_enabled="$(soraswap_rwa_release_enabled_setting_for_env "$mode")" || exit 1
soraswap_require_nonnegative_integer_at_most_setting "SORASWAP_POOL_FEE_PIPS" "$pool_fee_pips" 999999 || exit 1
soraswap_require_integer_setting "SORASWAP_POOL_ACTIVE_BIN" "$pool_active_bin" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_TRIGGER_LIFECYCLE_CADENCE_SLOTS" "$trigger_lifecycle_cadence_slots" || exit 1
soraswap_require_positive_integer_at_most_setting "SORASWAP_TRIGGER_LIFECYCLE_MAX_ITEMS" "$trigger_lifecycle_max_items" 16 || exit 1
soraswap_require_binary_integer_setting "SORASWAP_TRIGGER_LIFECYCLE_ENABLED" "$trigger_lifecycle_enabled" || exit 1
soraswap_require_positive_integer_at_most_setting "SORASWAP_PERPS_TRIGGER_LIFECYCLE_MAX_ITEMS" "$perps_trigger_lifecycle_max_items" 4 || exit 1
soraswap_require_positive_integer_setting "SORASWAP_DLMM_RANGE_GOVERNOR_CADENCE_SLOTS" "$dlmm_range_governor_cadence_slots" || exit 1
soraswap_require_nonnegative_integer_at_most_setting "SORASWAP_DLMM_RANGE_GOVERNOR_MAX_FEE_PIPS" "$dlmm_range_governor_max_fee_pips" 999999 || exit 1
soraswap_require_integer_setting "SORASWAP_DLMM_RANGE_GOVERNOR_TARGET_ACTIVE_BIN" "$dlmm_range_governor_target_active_bin" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_DLMM_RANGE_GOVERNOR_MAX_ACTIVE_BIN_DRIFT" "$dlmm_range_governor_max_active_bin_drift" || exit 1
soraswap_require_binary_integer_setting "SORASWAP_DLMM_RANGE_GOVERNOR_ENABLED" "$dlmm_range_governor_enabled" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_TWAMM_TRIGGER_CADENCE_SLOTS" "$twamm_trigger_cadence_slots" || exit 1
soraswap_require_positive_integer_at_most_setting "SORASWAP_TWAMM_TRIGGER_MAX_ORDERS_PER_TICK" "$twamm_trigger_max_orders_per_tick" 16 || exit 1
soraswap_require_binary_integer_setting "SORASWAP_TWAMM_TRIGGER_ENABLED" "$twamm_trigger_enabled" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_EPOCH_AUCTION_EPOCH_ID" "$epoch_auction_epoch_id" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_EPOCH_AUCTION_DURATION_SLOTS" "$epoch_auction_duration_slots" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_EPOCH_AUCTION_LOWER_TICK" "$epoch_auction_lower_tick" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_EPOCH_AUCTION_UPPER_TICK" "$epoch_auction_upper_tick" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_EPOCH_AUCTION_TICK_STEP" "$epoch_auction_tick_step" || exit 1
soraswap_require_positive_integer_at_most_setting "SORASWAP_EPOCH_AUCTION_MAX_ORDERS" "$epoch_auction_max_orders" 256 || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_BOOTSTRAP_CONTROLLER_SYNC_PIPELINE_WAIT_SECS" "$bootstrap_controller_sync_pipeline_wait_secs" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_BOOTSTRAP_CONTROLLER_SYNC_COMMITTED_WAIT_SECS" "$bootstrap_controller_sync_committed_wait_secs" || exit 1
soraswap_validate_poll_window "SORASWAP_BOOTSTRAP_VIEW_RETRY" "$bootstrap_view_retry_attempts" "$bootstrap_view_retry_sleep_secs" || exit 1
soraswap_validate_poll_window "SORASWAP_BOOTSTRAP_APPLY_RETRY" "$bootstrap_apply_retry_attempts" "$bootstrap_apply_retry_sleep_secs" || exit 1
soraswap_require_nonnegative_number_setting "SORASWAP_WARM_VIEW_TIMEOUT_SECS" "$warm_view_timeout_secs" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_SMOKE_GAS_LIMIT" "$SORASWAP_SMOKE_GAS_LIMIT" || exit 1
if (( epoch_auction_upper_tick < epoch_auction_lower_tick )); then
  echo "SORASWAP_EPOCH_AUCTION_UPPER_TICK must be greater than or equal to SORASWAP_EPOCH_AUCTION_LOWER_TICK; got lower='$epoch_auction_lower_tick' upper='$epoch_auction_upper_tick'" >&2
  exit 1
fi

config="$(client_config_or_default "$mode")"
ensure_client "$config"
ensure_authority "$config"
prepare_env_chain_state "$mode" "$config"
case "$mode" in
  testnet|production)
    ensure_deployment_records_current "$mode" "$config"
    ;;
esac
if [[ "$mode" == "production" ]]; then
  require_production_operator_permissions "$config" "$SORASWAP_AUTHORITY"
fi
ensure_unit_account_permission "$config" "$SORASWAP_AUTHORITY" Admin
ensure_unit_account_permission "$config" "$SORASWAP_AUTHORITY" AssetOps
if [[ "$bootstrap_scope" == "full" ]]; then
  soraswap_ensure_oracle_account_ready "$config"
fi

n3x_hub_contract="$(deployed_contract_id_for_env "$mode" n3x.n3x_hub)"
dlmm_router_contract="$(deployed_contract_id_for_env "$mode" dlmm.dlmm_router)"
dlmm_pool_contract="$(deployed_contract_id_for_env "$mode" dlmm.dlmm_pool)"
batch_epoch_auction_contract="$(deployed_contract_id_for_env "$mode" batch_amm.epoch_auction)"
launchpad_liquidity_executor_contract="$(deployed_contract_id_for_env "$mode" launchpad.liquidity_executor)"
escrow_conditional_escrow_contract="$(deployed_contract_id_for_env "$mode" escrow.conditional_escrow)"
n3x_hub_contract_subject="$(contract_subject_account_for_literal "$config" "$n3x_hub_contract")"
dlmm_pool_contract_subject="$(contract_subject_account_for_literal "$config" "$dlmm_pool_contract")"
batch_epoch_auction_contract_subject="$(contract_subject_account_for_literal "$config" "$batch_epoch_auction_contract")"
launchpad_liquidity_executor_contract_subject="$(contract_subject_account_for_literal "$config" "$launchpad_liquidity_executor_contract")"
dlmm_router_contract_subject="$(contract_subject_account_for_literal "$config" "$dlmm_router_contract")"
escrow_conditional_escrow_contract_subject="$(contract_subject_account_for_literal "$config" "$escrow_conditional_escrow_contract")"
dlmm_pool_contract_blob_hex="0x$(printf '%s' "$dlmm_pool_contract" | xxd -p -c 256 | tr -d '\n')"
dlmm_router_contract_blob_hex="0x$(printf '%s' "$dlmm_router_contract" | xxd -p -c 256 | tr -d '\n')"
launchpad_liquidity_executor_contract_blob_hex="0x$(printf '%s' "$launchpad_liquidity_executor_contract" | xxd -p -c 256 | tr -d '\n')"

launchpad_sale_factory_contract=""
referral_registry_contract=""
farms_farm_contract=""
perps_engine_contract=""
options_factory_contract=""
cover_policy_manager_contract=""
automation_job_queue_contract=""
intents_settlement_router_contract=""
vaults_manager_contract=""
operators_registry_contract=""
margin_portfolio_margin_contract=""
rwa_market_contract=""
dlmm_hooks_manager_contract=""
launchpad_sale_factory_contract_subject=""
perps_engine_contract_subject=""
options_factory_contract_subject=""
cover_policy_manager_contract_subject=""
intents_settlement_router_contract_subject=""
vaults_manager_contract_subject=""
operators_registry_contract_subject=""
margin_portfolio_margin_contract_subject=""
rwa_market_contract_subject=""
dlmm_hooks_manager_contract_subject=""
sccp_bridge_contract=""
if [[ "$bootstrap_scope" == "full" ]]; then
  launchpad_sale_factory_contract="$(deployed_contract_id_for_env "$mode" launchpad.sale_factory)"
  referral_registry_contract="$(deployed_contract_id_for_env "$mode" referral.registry)"
  farms_farm_contract="$(deployed_contract_id_for_env "$mode" farms.farm)"
  perps_engine_contract="$(deployed_contract_id_for_env "$mode" perps.perps_engine)"
  options_factory_contract="$(deployed_contract_id_for_env "$mode" options.factory)"
  cover_policy_manager_contract="$(deployed_contract_id_for_env "$mode" cover.policy_manager)"
  automation_job_queue_contract="$(deployed_contract_id_for_env "$mode" automation.job_queue)"
  intents_settlement_router_contract="$(deployed_contract_id_for_env "$mode" intents.settlement_router)"
  vaults_manager_contract="$(deployed_contract_id_for_env "$mode" vaults.manager)"
  operators_registry_contract="$(deployed_contract_id_for_env "$mode" operators.registry)"
  margin_portfolio_margin_contract="$(deployed_contract_id_for_env "$mode" margin.portfolio_margin)"
  rwa_market_contract="$(deployed_contract_id_for_env "$mode" rwa.market)"
  dlmm_hooks_manager_contract="$(deployed_contract_id_for_env "$mode" dlmm_hooks.hook_manager)"
  sccp_bridge_contract="$(deployed_contract_id_for_env "$mode" bridge.sccp_bridge)"

  launchpad_sale_factory_contract_subject="$(contract_subject_account_for_literal "$config" "$launchpad_sale_factory_contract")"
  perps_engine_contract_subject="$(contract_subject_account_for_literal "$config" "$perps_engine_contract")"
  options_factory_contract_subject="$(contract_subject_account_for_literal "$config" "$options_factory_contract")"
  cover_policy_manager_contract_subject="$(contract_subject_account_for_literal "$config" "$cover_policy_manager_contract")"
  intents_settlement_router_contract_subject="$(contract_subject_account_for_literal "$config" "$intents_settlement_router_contract")"
  vaults_manager_contract_subject="$(contract_subject_account_for_literal "$config" "$vaults_manager_contract")"
  operators_registry_contract_subject="$(contract_subject_account_for_literal "$config" "$operators_registry_contract")"
  margin_portfolio_margin_contract_subject="$(contract_subject_account_for_literal "$config" "$margin_portfolio_margin_contract")"
  rwa_market_contract_subject="$(contract_subject_account_for_literal "$config" "$rwa_market_contract")"
  dlmm_hooks_manager_contract_subject="$(contract_subject_account_for_literal "$config" "$dlmm_hooks_manager_contract")"
fi
vault_account="$(treasury_account_for_mode "$mode")"
n3x_vault_account="${SORASWAP_N3X_VAULT_ACCOUNT:-$n3x_hub_contract_subject}"
dlmm_pool_vault_account="${SORASWAP_DLMM_POOL_VAULT_ACCOUNT:-$dlmm_pool_contract_subject}"
dlmm_router_guardian_account="${SORASWAP_DLMM_ROUTER_GUARDIAN_ACCOUNT:-$SORASWAP_AUTHORITY}"
pool_bin_step="${SORASWAP_POOL_BIN_STEP:-1}"
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
n3x_target_usdt_bps="${SORASWAP_N3X_TARGET_USDT_BPS:-3334}"
n3x_target_usdc_bps="${SORASWAP_N3X_TARGET_USDC_BPS:-3333}"
n3x_target_kusd_bps="${SORASWAP_N3X_TARGET_KUSD_BPS:-3333}"
n3x_mint_fee_bps="${SORASWAP_N3X_MINT_FEE_BPS:-100}"
n3x_redeem_fee_bps="${SORASWAP_N3X_REDEEM_FEE_BPS:-100}"
if [[ "$mode" == "testnet" || "$mode" == "production" ]]; then
  sale_name="${SORASWAP_SALE_NAME:-genesis_sale_usdt}"
else
  sale_name="${SORASWAP_SALE_NAME:-genesis_sale}"
fi
referral_claim_threshold="${SORASWAP_REFERRAL_SMOKE_CLAIM_THRESHOLD:-3}"
referral_direct_share_bps="${SORASWAP_REFERRAL_SMOKE_DIRECT_SHARE_BPS:-7000}"
referral_parent_share_bps="${SORASWAP_REFERRAL_SMOKE_PARENT_SHARE_BPS:-3000}"
perps_funding_bps="${SORASWAP_PERPS_SMOKE_FUNDING_BPS:-100}"
perps_max_leverage_bps="${SORASWAP_PERPS_SMOKE_MAX_LEVERAGE_BPS:-50000}"
perps_maintenance_margin_bps="${SORASWAP_PERPS_SMOKE_MAINTENANCE_MARGIN_BPS:-500}"
perps_liquidation_fee_bps="${SORASWAP_PERPS_SMOKE_LIQUIDATION_FEE_BPS:-1000}"
perps_open_interest_cap="${SORASWAP_PERPS_MARKET_OPEN_INTEREST_CAP:-80000}"
perps_funding_interval_slots="${SORASWAP_PERPS_MARKET_FUNDING_INTERVAL_SLOTS:-4}"
perps_oracle_stale_slots="${SORASWAP_PERPS_MARKET_ORACLE_STALE_SLOTS:-120}"
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
options_oracle_stale_slots="${SORASWAP_OPTIONS_ORACLE_STALE_SLOTS:-120}"
options_factory_bump_activate_bps="${SORASWAP_OPTIONS_GUARD_BUMP_ACTIVATE_BPS:-8000}"
options_factory_bump_deactivate_bps="${SORASWAP_OPTIONS_GUARD_BUMP_DEACTIVATE_BPS:-6000}"
options_factory_pause_threshold_bps="${SORASWAP_OPTIONS_GUARD_PAUSE_THRESHOLD_BPS:-9500}"
options_factory_bump_percent_bps="${SORASWAP_OPTIONS_GUARD_BUMP_PERCENT_BPS:-1500}"
cover_required_observations="${SORASWAP_COVER_REQUIRED_OBSERVATIONS:-3}"
cover_oracle_stale_slots="${SORASWAP_COVER_ORACLE_STALE_SLOTS:-120}"
perps_collateral_pool_bootstrap_deposit="${SORASWAP_PERPS_COLLATERAL_POOL_BOOTSTRAP_DEPOSIT:-200}"
bridge_asset_key="${SORASWAP_BRIDGE_ASSET_KEY:-genesis_bridge_asset}"
bridge_route="${SORASWAP_BRIDGE_ROUTE:-eth_sora_usdt}"
bridge_listing_fee_amount="${SORASWAP_BRIDGE_LISTING_FEE_AMOUNT:-0}"
bridge_proof_authority="${SORASWAP_BRIDGE_PROOF_AUTHORITY:-$SORASWAP_AUTHORITY}"
bridge_remote_domain="${SORASWAP_BRIDGE_REMOTE_DOMAIN:-1}"
bridge_asset_home_domain="${SORASWAP_BRIDGE_ASSET_HOME_DOMAIN:-1}"
bridge_asset_decimals="${SORASWAP_BRIDGE_ASSET_DECIMALS:-6}"
if [[ "$mode" == "testnet" || "$mode" == "production" ]]; then
  # Public Taira maintenance calls are single-transaction repairs; keep the
  # default reserve small enough that existing contract-subject balances remain
  # usable without forcing a large authority-funded top-up first.
  bootstrap_signer_fee_minimum="${SORASWAP_BOOTSTRAP_SIGNER_FEE_MINIMUM:-1000}"
else
  bootstrap_signer_fee_minimum="${SORASWAP_BOOTSTRAP_SIGNER_FEE_MINIMUM:-100000}"
fi
bootstrap_maintenance_gas_limit="${SORASWAP_BOOTSTRAP_MAINTENANCE_GAS_LIMIT:-10000}"

xor_id="$(asset_definition_id_for_alias "$config" "$SORASWAP_BASE_ASSET_ALIAS")"
fee_asset_id="$(fee_asset_definition_id_for_config "$config")"
usdt_id="$(asset_definition_id_for_alias "$config" usdt#soraswap.universal)"
usdc_id="$(asset_definition_id_for_alias "$config" usdc#soraswap.universal)"
kusd_id="$(asset_definition_id_for_alias "$config" kusd#soraswap.universal)"
n3x_id="$(asset_definition_id_for_alias "$config" n3x#soraswap.universal)"
bridge_local_asset="${SORASWAP_BRIDGE_LOCAL_ASSET:-$usdt_id}"
current_slot="$(soraswap_current_block_height "$config")"
if [[ -z "$current_slot" || "$current_slot" == "null" || ! "$current_slot" =~ ^[0-9]+$ ]]; then
  current_slot=0
fi
if [[ -z "${SORASWAP_OPTIONS_SHOUT_EXPIRY_SLOT:-}" ]]; then
  options_shout_expiry_slot=$(( current_slot + options_shout_tenor_slots ))
fi
if [[ -z "${SORASWAP_OPTIONS_OUTPERFORMANCE_EXPIRY_SLOT:-}" ]]; then
  options_outperformance_expiry_slot=$(( current_slot + options_outperformance_tenor_slots ))
fi
epoch_auction_start_slot="${SORASWAP_EPOCH_AUCTION_START_SLOT:-$current_slot}"
soraswap_require_nonnegative_integer_setting "SORASWAP_EPOCH_AUCTION_START_SLOT" "$epoch_auction_start_slot" || exit 1
if [[ -n "${SORASWAP_EPOCH_AUCTION_END_SLOT:-}" ]]; then
  epoch_auction_end_slot="$SORASWAP_EPOCH_AUCTION_END_SLOT"
else
  epoch_auction_end_slot=$(( epoch_auction_start_slot + epoch_auction_duration_slots ))
fi
soraswap_require_nonnegative_integer_setting "SORASWAP_EPOCH_AUCTION_END_SLOT" "$epoch_auction_end_slot" || exit 1
if (( epoch_auction_end_slot <= epoch_auction_start_slot )); then
  epoch_auction_end_slot=$(( epoch_auction_start_slot + 1 ))
fi
if [[ "$mode" == "local" ]]; then
  default_launchpad_sale_asset_id="$usdt_id"
else
  default_launchpad_sale_asset_id="$usdt_id"
fi
launchpad_sale_asset_id="${SORASWAP_LAUNCHPAD_SALE_ASSET_ID:-$default_launchpad_sale_asset_id}"
launchpad_pool_quote_asset_id="${SORASWAP_LAUNCHPAD_POOL_QUOTE_ASSET_ID:-$usdt_id}"
soraswap_launch_vault_id="${SORASWAP_LAUNCH_VAULT_ID:-n3x_savings}"
soraswap_launch_vault_strategy_code="${SORASWAP_LAUNCH_VAULT_STRATEGY_CODE:-1}"
soraswap_launch_vault_async_redeem="${SORASWAP_LAUNCH_VAULT_ASYNC_REDEEM:-1}"
soraswap_launch_operator_service="${SORASWAP_LAUNCH_OPERATOR_SERVICE:-solver}"
soraswap_launch_operator_min_bond="${SORASWAP_LAUNCH_OPERATOR_MIN_BOND:-100}"
soraswap_launch_operator_bond="${SORASWAP_LAUNCH_OPERATOR_BOND:-100}"
soraswap_launch_operator_heartbeat_slot="${SORASWAP_LAUNCH_OPERATOR_HEARTBEAT_SLOT:-1}"
soraswap_launch_operator_health_bps="${SORASWAP_LAUNCH_OPERATOR_HEALTH_BPS:-10000}"
soraswap_launch_margin_market_id="${SORASWAP_LAUNCH_MARGIN_MARKET_ID:-portfolio}"
soraswap_launch_margin_risk_weight_bps="${SORASWAP_LAUNCH_MARGIN_RISK_WEIGHT_BPS:-8000}"
soraswap_launch_margin_liquidation_threshold_bps="${SORASWAP_LAUNCH_MARGIN_LIQUIDATION_THRESHOLD_BPS:-1000}"
soraswap_launch_rwa_market_id="${SORASWAP_LAUNCH_RWA_MARKET_ID:-tbill_2026}"
soraswap_launch_rwa_nav="${SORASWAP_LAUNCH_RWA_NAV:-100}"
soraswap_launch_rwa_shares="${SORASWAP_LAUNCH_RWA_SHARES:-1000}"
soraswap_launch_dlmm_hook_id="${SORASWAP_LAUNCH_DLMM_HOOK_ID:-dynamic_fee}"
soraswap_launch_dlmm_hook_phase="${SORASWAP_LAUNCH_DLMM_HOOK_PHASE:-1}"
soraswap_launch_dlmm_hook_max_fee_pips="${SORASWAP_LAUNCH_DLMM_HOOK_MAX_FEE_PIPS:-5000}"

soraswap_require_positive_integer_setting "SORASWAP_POOL_BIN_STEP" "$pool_bin_step" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_POOL_SEED_BASE" "$pool_seed_base" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_POOL_SEED_QUOTE" "$pool_seed_quote" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_POOL_SEED_NEXT_BASE" "$pool_seed_next_base" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_POOL_SEED_NEXT_QUOTE" "$pool_seed_next_quote" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_POOL_SEED_FAR_BASE" "$pool_seed_far_base" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_POOL_SEED_FAR_QUOTE" "$pool_seed_far_quote" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_POOL_POSITION_BASE" "$pool_position_base" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_POOL_POSITION_QUOTE" "$pool_position_quote" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_POOL_POSITION_MIN_SHARES_OUT" "$pool_position_min_shares_out" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_POOL_IMPACT_CAP_BPS" "$pool_impact_cap_bps" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_POOL_MIN_RESERVE_BASE" "$pool_min_reserve_base" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_POOL_MIN_RESERVE_QUOTE" "$pool_min_reserve_quote" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_POOL_MAX_BINS_PER_SWAP" "$pool_max_bins_per_swap" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_POOL_BIN_LIQUIDITY_CAP" "$pool_bin_liquidity_cap" || exit 1
if (( pool_bin_liquidity_cap > 0 && pool_bin_liquidity_cap < pool_min_reserve_base )); then
  echo "SORASWAP_POOL_BIN_LIQUIDITY_CAP must be 0 or greater than or equal to SORASWAP_POOL_MIN_RESERVE_BASE; got cap='$pool_bin_liquidity_cap' min_base='$pool_min_reserve_base'" >&2
  exit 1
fi
if (( pool_bin_liquidity_cap > 0 && pool_bin_liquidity_cap < pool_min_reserve_quote )); then
  echo "SORASWAP_POOL_BIN_LIQUIDITY_CAP must be 0 or greater than or equal to SORASWAP_POOL_MIN_RESERVE_QUOTE; got cap='$pool_bin_liquidity_cap' min_quote='$pool_min_reserve_quote'" >&2
  exit 1
fi
soraswap_require_nonnegative_integer_at_most_setting "SORASWAP_N3X_TARGET_USDT_BPS" "$n3x_target_usdt_bps" 10000 || exit 1
soraswap_require_nonnegative_integer_at_most_setting "SORASWAP_N3X_TARGET_USDC_BPS" "$n3x_target_usdc_bps" 10000 || exit 1
soraswap_require_nonnegative_integer_at_most_setting "SORASWAP_N3X_TARGET_KUSD_BPS" "$n3x_target_kusd_bps" 10000 || exit 1
if (( n3x_target_usdt_bps + n3x_target_usdc_bps + n3x_target_kusd_bps != 10000 )); then
  echo "SORASWAP_N3X_TARGET_*_BPS values must sum to 10000; got '$n3x_target_usdt_bps+$n3x_target_usdc_bps+$n3x_target_kusd_bps'" >&2
  exit 1
fi
soraswap_require_nonnegative_integer_at_most_setting "SORASWAP_N3X_MINT_FEE_BPS" "$n3x_mint_fee_bps" 9999 || exit 1
soraswap_require_nonnegative_integer_at_most_setting "SORASWAP_N3X_REDEEM_FEE_BPS" "$n3x_redeem_fee_bps" 9999 || exit 1
soraswap_require_positive_integer_setting "SORASWAP_REFERRAL_SMOKE_CLAIM_THRESHOLD" "$referral_claim_threshold" || exit 1
soraswap_require_nonnegative_integer_at_most_setting "SORASWAP_REFERRAL_SMOKE_DIRECT_SHARE_BPS" "$referral_direct_share_bps" 10000 || exit 1
soraswap_require_nonnegative_integer_at_most_setting "SORASWAP_REFERRAL_SMOKE_PARENT_SHARE_BPS" "$referral_parent_share_bps" 10000 || exit 1
if (( referral_direct_share_bps + referral_parent_share_bps != 10000 )); then
  echo "SORASWAP_REFERRAL_SMOKE_DIRECT_SHARE_BPS and SORASWAP_REFERRAL_SMOKE_PARENT_SHARE_BPS must sum to 10000; got '$referral_direct_share_bps+$referral_parent_share_bps'" >&2
  exit 1
fi
soraswap_require_integer_setting "SORASWAP_PERPS_SMOKE_FUNDING_BPS" "$perps_funding_bps" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_PERPS_SMOKE_MAX_LEVERAGE_BPS" "$perps_max_leverage_bps" || exit 1
if (( perps_max_leverage_bps <= 10000 )); then
  echo "SORASWAP_PERPS_SMOKE_MAX_LEVERAGE_BPS must be greater than 10000; got '$perps_max_leverage_bps'" >&2
  exit 1
fi
soraswap_require_positive_integer_at_most_setting "SORASWAP_PERPS_SMOKE_MAINTENANCE_MARGIN_BPS" "$perps_maintenance_margin_bps" 10000 || exit 1
soraswap_require_nonnegative_integer_at_most_setting "SORASWAP_PERPS_SMOKE_LIQUIDATION_FEE_BPS" "$perps_liquidation_fee_bps" 10000 || exit 1
soraswap_require_positive_integer_setting "SORASWAP_PERPS_MARKET_OPEN_INTEREST_CAP" "$perps_open_interest_cap" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_PERPS_MARKET_FUNDING_INTERVAL_SLOTS" "$perps_funding_interval_slots" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_PERPS_MARKET_ORACLE_STALE_SLOTS" "$perps_oracle_stale_slots" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_PERPS_MARKET_BACKLOG_LIMIT" "$perps_backlog_limit" || exit 1
soraswap_require_nonnegative_integer_at_most_setting "SORASWAP_PERPS_MARKET_UTILISATION_CLAMP_BPS" "$perps_utilisation_clamp_bps" 10000 || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_PERPS_MARKET_LIQUIDATION_STRESS_LIMIT" "$perps_liquidation_stress_limit" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_OPTIONS_SHOUT_TENOR_SLOTS" "$options_shout_tenor_slots" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_OPTIONS_OUTPERFORMANCE_TENOR_SLOTS" "$options_outperformance_tenor_slots" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_OPTIONS_SHOUT_STRIKE_BPS" "$options_shout_strike_bps" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_OPTIONS_OUTPERFORMANCE_STRIKE_BPS" "$options_outperformance_strike_bps" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_OPTIONS_COLLATERAL_MULTIPLIER_BPS" "$options_collateral_multiplier_bps" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_OPTIONS_SHOUT_BASE_PREMIUM_BPS" "$options_shout_base_premium_bps" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_OPTIONS_OUTPERFORMANCE_BASE_PREMIUM_BPS" "$options_outperformance_base_premium_bps" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_OPTIONS_SHOUT_EXPIRY_SLOT" "$options_shout_expiry_slot" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_OPTIONS_OUTPERFORMANCE_EXPIRY_SLOT" "$options_outperformance_expiry_slot" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_OPTIONS_SHOUT_MAX_NOTIONAL" "$options_shout_max_notional" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_OPTIONS_OUTPERFORMANCE_MAX_NOTIONAL" "$options_outperformance_max_notional" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_OPTIONS_ORACLE_STALE_SLOTS" "$options_oracle_stale_slots" || exit 1
soraswap_require_nonnegative_integer_at_most_setting "SORASWAP_OPTIONS_GUARD_BUMP_ACTIVATE_BPS" "$options_factory_bump_activate_bps" 10000 || exit 1
soraswap_require_nonnegative_integer_at_most_setting "SORASWAP_OPTIONS_GUARD_BUMP_DEACTIVATE_BPS" "$options_factory_bump_deactivate_bps" 10000 || exit 1
soraswap_require_nonnegative_integer_at_most_setting "SORASWAP_OPTIONS_GUARD_PAUSE_THRESHOLD_BPS" "$options_factory_pause_threshold_bps" 10000 || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_OPTIONS_GUARD_BUMP_PERCENT_BPS" "$options_factory_bump_percent_bps" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_COVER_REQUIRED_OBSERVATIONS" "$cover_required_observations" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_COVER_ORACLE_STALE_SLOTS" "$cover_oracle_stale_slots" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_PERPS_COLLATERAL_POOL_BOOTSTRAP_DEPOSIT" "$perps_collateral_pool_bootstrap_deposit" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_BRIDGE_LISTING_FEE_AMOUNT" "$bridge_listing_fee_amount" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_BRIDGE_REMOTE_DOMAIN" "$bridge_remote_domain" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_BRIDGE_ASSET_HOME_DOMAIN" "$bridge_asset_home_domain" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_BRIDGE_ASSET_DECIMALS" "$bridge_asset_decimals" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_BOOTSTRAP_SIGNER_FEE_MINIMUM" "$bootstrap_signer_fee_minimum" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_BOOTSTRAP_MAINTENANCE_GAS_LIMIT" "$bootstrap_maintenance_gas_limit" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_EPOCH_AUCTION_START_SLOT" "$epoch_auction_start_slot" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_EPOCH_AUCTION_END_SLOT" "$epoch_auction_end_slot" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_LAUNCH_VAULT_STRATEGY_CODE" "$soraswap_launch_vault_strategy_code" || exit 1
soraswap_require_binary_integer_setting "SORASWAP_LAUNCH_VAULT_ASYNC_REDEEM" "$soraswap_launch_vault_async_redeem" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_LAUNCH_OPERATOR_MIN_BOND" "$soraswap_launch_operator_min_bond" || exit 1
soraswap_require_positive_integer_setting "SORASWAP_LAUNCH_OPERATOR_BOND" "$soraswap_launch_operator_bond" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_LAUNCH_OPERATOR_HEARTBEAT_SLOT" "$soraswap_launch_operator_heartbeat_slot" || exit 1
soraswap_require_nonnegative_integer_at_most_setting "SORASWAP_LAUNCH_OPERATOR_HEALTH_BPS" "$soraswap_launch_operator_health_bps" 10000 || exit 1
soraswap_require_nonnegative_integer_at_most_setting "SORASWAP_LAUNCH_MARGIN_RISK_WEIGHT_BPS" "$soraswap_launch_margin_risk_weight_bps" 10000 || exit 1
soraswap_require_nonnegative_integer_at_most_setting "SORASWAP_LAUNCH_MARGIN_LIQUIDATION_THRESHOLD_BPS" "$soraswap_launch_margin_liquidation_threshold_bps" 10000 || exit 1
if [[ "$rwa_release_enabled" == "1" \
  || -n "${SORASWAP_LAUNCH_RWA_NAV+x}" \
  || -n "${SORASWAP_LAUNCH_RWA_SHARES+x}" ]]; then
  soraswap_require_positive_integer_setting "SORASWAP_LAUNCH_RWA_NAV" "$soraswap_launch_rwa_nav" || exit 1
  soraswap_require_positive_integer_setting "SORASWAP_LAUNCH_RWA_SHARES" "$soraswap_launch_rwa_shares" || exit 1
fi
soraswap_require_integer_setting "SORASWAP_LAUNCH_DLMM_HOOK_PHASE" "$soraswap_launch_dlmm_hook_phase" || exit 1
soraswap_require_nonnegative_integer_setting "SORASWAP_LAUNCH_DLMM_HOOK_MAX_FEE_PIPS" "$soraswap_launch_dlmm_hook_max_fee_pips" || exit 1

echo "bootstrap contract state via $(soraswap_display_path "$config")"

ensure_account_registered "$config" "$vault_account" soraswap
ensure_account_registered "$config" "$n3x_hub_contract_subject" contract-subject
ensure_account_registered "$config" "$dlmm_pool_contract_subject" contract-subject
ensure_account_registered "$config" "$dlmm_router_contract_subject" contract-subject
ensure_account_registered "$config" "$batch_epoch_auction_contract_subject" contract-subject
ensure_account_registered "$config" "$launchpad_liquidity_executor_contract_subject" contract-subject
ensure_account_registered "$config" "$escrow_conditional_escrow_contract_subject" contract-subject
contract_subject_accounts=(
  "$n3x_hub_contract_subject"
  "$dlmm_pool_contract_subject"
  "$dlmm_router_contract_subject"
  "$batch_epoch_auction_contract_subject"
  "$launchpad_liquidity_executor_contract_subject"
  "$escrow_conditional_escrow_contract_subject"
)
if [[ "$bootstrap_scope" != "foundation" ]]; then
  ensure_account_registered "$config" "$launchpad_sale_factory_contract_subject" contract-subject
  ensure_account_registered "$config" "$perps_engine_contract_subject" contract-subject
  ensure_account_registered "$config" "$options_factory_contract_subject" contract-subject
  ensure_account_registered "$config" "$cover_policy_manager_contract_subject" contract-subject
  ensure_account_registered "$config" "$intents_settlement_router_contract_subject" contract-subject
  ensure_account_registered "$config" "$vaults_manager_contract_subject" contract-subject
  ensure_account_registered "$config" "$operators_registry_contract_subject" contract-subject
  ensure_account_registered "$config" "$margin_portfolio_margin_contract_subject" contract-subject
  ensure_account_registered "$config" "$rwa_market_contract_subject" contract-subject
  ensure_account_registered "$config" "$dlmm_hooks_manager_contract_subject" contract-subject
  contract_subject_accounts+=(
    "$intents_settlement_router_contract_subject"
    "$vaults_manager_contract_subject"
    "$operators_registry_contract_subject"
    "$margin_portfolio_margin_contract_subject"
    "$rwa_market_contract_subject"
    "$dlmm_hooks_manager_contract_subject"
    "$launchpad_sale_factory_contract_subject"
    "$perps_engine_contract_subject"
    "$options_factory_contract_subject"
    "$cover_policy_manager_contract_subject"
  )
fi
typeset -A contract_subject_account_seen
for contract_subject_account in "${contract_subject_accounts[@]}"; do
  if [[ -n "${contract_subject_account_seen[$contract_subject_account]-}" ]]; then
    echo "production bootstrap resolved duplicate contract-subject account: $contract_subject_account" >&2
    exit 1
  fi
  contract_subject_account_seen[$contract_subject_account]=1
  ensure_unit_account_permission "$config" "$contract_subject_account" AssetOps
done

if [[ "$mode" == "production" ]]; then
  permission_receipt_timestamp="$(utc_timestamp)"
  permission_receipt_id="${permission_receipt_timestamp}-$(od -An -tx1 -N8 /dev/urandom | tr -d ' \n')"
  permission_receipt_dir="$(deployments_dir_for_env "$mode")"
  permission_receipt_latest="$permission_receipt_dir/permission_provisioning.latest.json"
  permission_receipt_timestamped="$permission_receipt_dir/permission_provisioning.${permission_receipt_id}.json"
  [[ ! -e "$permission_receipt_timestamped" ]] || {
    echo "refusing to overwrite an existing production permission receipt" >&2
    exit 1
  }
  permission_subjects_json='[]'
  for contract_subject_account in "${contract_subject_accounts[@]}"; do
    contract_subject_account_readback_json="$(exact_account_readback_json "$config" "$contract_subject_account")" || exit 1
    if ! jq -e '.query_available == true and .matched == true' \
      >/dev/null <<<"$contract_subject_account_readback_json"; then
      echo "production contract-subject account is not query-visible at receipt time: $contract_subject_account" >&2
      exit 1
    fi
    if ! contract_subject_permissions_json="$(iroha_cli_json --config "$config" account permission list --id "$contract_subject_account")" \
      || ! jq -e 'type == "array" and any(.[]; .name == "AssetOps" and .payload == null)' \
        >/dev/null 2>&1 <<<"$contract_subject_permissions_json"; then
      echo "production contract-subject AssetOps permission is not query-visible at receipt time: $contract_subject_account" >&2
      exit 1
    fi
    permission_subjects_json="$(jq -cn \
      --argjson current "$permission_subjects_json" \
      --arg account "$contract_subject_account" \
      --argjson account_readback "$contract_subject_account_readback_json" \
      '$current + [{account: $account, account_present: true, account_readback: $account_readback, permission: {name: "AssetOps", payload: null}, permission_present: true}]')"
  done
  if ! jq -e --argjson expected "${#contract_subject_accounts[@]}" '
      length == $expected
      and ([.[].account] | unique | length) == $expected
      and all(.[];
        .account_present == true
        and .permission_present == true
        and .account_readback.query_available == true
        and .account_readback.matched == true)
    ' >/dev/null <<<"$permission_subjects_json"; then
    echo "production contract-subject permission readback is incomplete or non-unique" >&2
    exit 1
  fi
  operator_permissions_json="$(production_operator_permission_readiness_json "$config" "$SORASWAP_AUTHORITY")"
  if ! jq -e '.query_available == true and .ready == true' >/dev/null <<<"$operator_permissions_json"; then
    echo "production operator permissions changed during contract-subject provisioning" >&2
    exit 1
  fi
  permission_chain_fingerprint_json="$(chain_fingerprint_json_or_null)"
  require_deployment_evidence_chain_fingerprint production "$permission_chain_fingerprint_json" "production permission receipt" || exit 1
  permission_receipt_json="$(jq -cn \
    --arg receipt_id "$permission_receipt_id" \
    --arg generated_at "$permission_receipt_timestamp" \
    --arg environment "$mode" \
    --arg bootstrap_scope "$bootstrap_scope" \
    --arg approval_gate "SORASWAP_ALLOW_PRODUCTION_MUTATIONS" \
    --argjson expected_count "${#contract_subject_accounts[@]}" \
    --argjson operator_permissions "$operator_permissions_json" \
    --argjson subjects "$permission_subjects_json" \
    --argjson chain_fingerprint "$permission_chain_fingerprint_json" \
    '{
      status: "completed",
      receipt_id: $receipt_id,
      generated_at: $generated_at,
      environment: $environment,
      chain_fingerprint: $chain_fingerprint,
      bootstrap_scope: $bootstrap_scope,
      policy: {
        operator_permissions: "preprovisioned_verify_only",
        deterministic_contract_subject_grants: "mutation_gate_approved_and_read_after_write_verified",
        approval: {gate: $approval_gate, value: 1}
      },
      operator_permissions: $operator_permissions,
      contract_subject_permissions: {
        expected_count: $expected_count,
        verified_count: ($subjects | length),
        subjects: $subjects
      }
    }')"
  mkdir -p "$permission_receipt_dir"
  soraswap_write_json_report_pair \
    "$permission_receipt_json" \
    "$permission_receipt_latest" \
    "$permission_receipt_timestamped"
  echo "production permission provisioning receipt: $(soraswap_display_path "$permission_receipt_timestamped")"
fi

warm_view() {
  local contract_id="$1"
  local entrypoint="$2"
  local payload_json="${3:-null}"

  SORASWAP_CONTRACT_VIEW_MAX_TIME_SECS="$warm_view_timeout_secs" \
    submit_contract_view "$config" "$contract_id" "$entrypoint" "$SORASWAP_SMOKE_GAS_LIMIT" "$payload_json" \
    >/dev/null 2>&1 || true
}

view_result_json() {
  local contract_id="$1"
  local entrypoint="$2"
  local payload_json="${3:-null}"
  local response_json

  response_json="$(submit_contract_view "$config" "$contract_id" "$entrypoint" "$SORASWAP_SMOKE_GAS_LIMIT" "$payload_json")" || return 1
  contract_view_result_json "$response_json"
}

view_result_json_with_retry() {
  local contract_id="$1"
  local entrypoint="$2"
  local payload_json="${3:-null}"
  local attempts="${4:-$bootstrap_view_retry_attempts}"
  local sleep_seconds="${5:-$bootstrap_view_retry_sleep_secs}"
  local attempt=1
  local result_json=""

  soraswap_validate_poll_window "bootstrap view retry" "$attempts" "$sleep_seconds" || return 1

  while (( attempt <= attempts )); do
    if result_json="$(view_result_json "$contract_id" "$entrypoint" "$payload_json" 2>/dev/null)" \
      && json_value_present "$result_json"; then
      printf '%s\n' "$result_json"
      return 0
    fi
    sleep "$sleep_seconds"
    attempt=$(( attempt + 1 ))
  done

  view_result_json "$contract_id" "$entrypoint" "$payload_json"
}

json_value_present() {
  local raw_json="${1:-}"
  if [[ -z "${raw_json//[$'\r\n\t ']}" ]]; then
    return 1
  fi
  jq -e . >/dev/null 2>&1 <<<"$raw_json"
}

safe_json_or_null() {
  local raw_json="${1:-}"
  if json_value_present "$raw_json"; then
    printf '%s\n' "$raw_json"
  else
    echo 'null'
  fi
}

fail_bootstrap_diff() {
  local label="$1"
  local expected_json="$2"
  local actual_json="$3"
  local prior_json="${4:-null}"
  local expected_safe actual_safe prior_safe

  expected_safe="$(safe_json_or_null "$expected_json")"
  actual_safe="$(safe_json_or_null "$actual_json")"
  prior_safe="$(safe_json_or_null "$prior_json")"

  echo "bootstrap state mismatch for $label" >&2
  jq -n \
    --arg label "$label" \
    --argjson expected "$expected_safe" \
    --argjson actual "$actual_safe" \
    --argjson prior "$prior_safe" \
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

  if actual_json="$(view_result_json "$contract_id" "$view_entrypoint" "$view_payload_json" 2>/dev/null)" \
    && json_value_present "$actual_json"; then
    if json_equals "$actual_json" "$expected_json"; then
      echo "bootstrap skip: $label already matches expected state"
      return 0
    fi
    fail_bootstrap_diff "$label" "$expected_json" "$actual_json"
  fi

  echo "bootstrap init: $label"
  call_contract_and_wait "$config" "$contract_id" "$init_entrypoint" "$init_payload_json" >/dev/null
  actual_json="$(view_result_json_with_retry "$contract_id" "$view_entrypoint" "$view_payload_json")"
  if ! json_equals "$actual_json" "$expected_json"; then
    fail_bootstrap_diff "$label" "$expected_json" "$actual_json"
  fi
}

ensure_init_or_skip_with_live_predicate() {
  local label="$1"
  local contract_id="$2"
  local view_entrypoint="$3"
  local view_payload_json="$4"
  local expected_json="$5"
  local init_entrypoint="$6"
  local init_payload_json="$7"
  local live_predicate_jq="$8"
  local actual_json

  if actual_json="$(view_result_json "$contract_id" "$view_entrypoint" "$view_payload_json" 2>/dev/null)" \
    && json_value_present "$actual_json"; then
    if json_equals "$actual_json" "$expected_json"; then
      echo "bootstrap skip: $label already matches expected state"
      return 0
    fi
    if jq -en \
      --argjson actual "$actual_json" \
      --argjson expected "$expected_json" \
      "$live_predicate_jq" \
      >/dev/null; then
      echo "bootstrap skip: $label already initialized on advanced live state"
      return 0
    fi
    fail_bootstrap_diff "$label" "$expected_json" "$actual_json"
  fi

  echo "bootstrap init: $label"
  call_contract_and_wait "$config" "$contract_id" "$init_entrypoint" "$init_payload_json" >/dev/null
  actual_json="$(view_result_json_with_retry "$contract_id" "$view_entrypoint" "$view_payload_json")"
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
  actual_json="$(view_result_json_with_retry "$contract_id" "$view_entrypoint" "$view_payload_json")"
  if ! json_equals "$actual_json" "$expected_json"; then
    fail_bootstrap_diff "$label" "$expected_json" "$actual_json" "$accepted_prior_json"
  fi
}

ensure_step_from_prior_or_skip_with_live_predicate() {
  local label="$1"
  local contract_id="$2"
  local view_entrypoint="$3"
  local view_payload_json="$4"
  local accepted_prior_json="$5"
  local expected_json="$6"
  local call_entrypoint="$7"
  local call_payload_json="$8"
  local live_predicate_jq="$9"
  local retry_apply="${10:-0}"
  local actual_json
  local attempt=1

  actual_json="$(view_result_json "$contract_id" "$view_entrypoint" "$view_payload_json")"
  if json_equals "$actual_json" "$expected_json"; then
    echo "bootstrap skip: $label already matches expected state"
    return 0
  fi
  if jq -en \
    --argjson actual "$actual_json" \
    --argjson expected "$expected_json" \
    --argjson prior "$accepted_prior_json" \
    "$live_predicate_jq" \
    >/dev/null; then
    echo "bootstrap skip: $label already applied on advanced live state"
    return 0
  fi
  if ! json_equals "$actual_json" "$accepted_prior_json"; then
    fail_bootstrap_diff "$label" "$expected_json" "$actual_json" "$accepted_prior_json"
  fi

  if [[ "$retry_apply" != "1" ]]; then
    echo "bootstrap apply: $label"
    call_contract_and_wait "$config" "$contract_id" "$call_entrypoint" "$call_payload_json" >/dev/null
    actual_json="$(view_result_json_with_retry "$contract_id" "$view_entrypoint" "$view_payload_json")"
    if ! json_equals "$actual_json" "$expected_json"; then
      fail_bootstrap_diff "$label" "$expected_json" "$actual_json" "$accepted_prior_json"
    fi
    return 0
  fi

  while (( attempt <= bootstrap_apply_retry_attempts )); do
    echo "bootstrap apply: $label"
    if ! call_contract_and_wait "$config" "$contract_id" "$call_entrypoint" "$call_payload_json" >/dev/null; then
      actual_json="$(view_result_json_with_retry "$contract_id" "$view_entrypoint" "$view_payload_json" 2>/dev/null || true)"
      if json_value_present "$actual_json" && jq -en \
        --argjson actual "$actual_json" \
        --argjson expected "$expected_json" \
        --argjson prior "$accepted_prior_json" \
        "$live_predicate_jq" \
        >/dev/null; then
        echo "bootstrap note: $label submit failed after reaching expected live state"
        return 0
      fi
      if (( attempt < bootstrap_apply_retry_attempts )); then
        echo "bootstrap apply: $label submit failed; retrying ($attempt/$bootstrap_apply_retry_attempts)" >&2
        sleep "$bootstrap_apply_retry_sleep_secs"
        attempt=$(( attempt + 1 ))
        continue
      fi
      return 1
    fi

    actual_json="$(view_result_json_with_retry "$contract_id" "$view_entrypoint" "$view_payload_json")"
    if jq -en \
      --argjson actual "$actual_json" \
      --argjson expected "$expected_json" \
      --argjson prior "$accepted_prior_json" \
      "$live_predicate_jq" \
      >/dev/null; then
      return 0
    fi
    if (( attempt < bootstrap_apply_retry_attempts )); then
      echo "bootstrap apply: $label postcondition not visible; retrying ($attempt/$bootstrap_apply_retry_attempts)" >&2
      sleep "$bootstrap_apply_retry_sleep_secs"
      attempt=$(( attempt + 1 ))
      continue
    fi
    fail_bootstrap_diff "$label" "$expected_json" "$actual_json" "$accepted_prior_json"
  done
}

apply_step_and_expect() {
  local label="$1"
  local contract_id="$2"
  local view_entrypoint="$3"
  local view_payload_json="$4"
  local expected_json="$5"
  local call_entrypoint="$6"
  local call_payload_json="$7"
  local actual_json
  local attempt=1

  actual_json="$(view_result_json "$contract_id" "$view_entrypoint" "$view_payload_json" 2>/dev/null || true)"
  if json_value_present "$actual_json" && json_equals "$actual_json" "$expected_json"; then
    echo "bootstrap skip: $label already matches expected state"
    return 0
  fi

  while (( attempt <= bootstrap_apply_retry_attempts )); do
    echo "bootstrap apply: $label"
    if ! call_contract_and_wait "$config" "$contract_id" "$call_entrypoint" "$call_payload_json" >/dev/null; then
      actual_json="$(view_result_json_with_retry "$contract_id" "$view_entrypoint" "$view_payload_json" 2>/dev/null || true)"
      if json_value_present "$actual_json" && json_equals "$actual_json" "$expected_json"; then
        echo "bootstrap note: $label submit failed after reaching expected state"
        return 0
      fi
      if (( attempt < bootstrap_apply_retry_attempts )); then
        echo "bootstrap apply: $label submit failed; retrying ($attempt/$bootstrap_apply_retry_attempts)" >&2
        sleep "$bootstrap_apply_retry_sleep_secs"
        attempt=$(( attempt + 1 ))
        continue
      fi
      return 1
    fi

    actual_json="$(view_result_json_with_retry "$contract_id" "$view_entrypoint" "$view_payload_json")"
    if json_equals "$actual_json" "$expected_json"; then
      return 0
    fi
    if (( attempt < bootstrap_apply_retry_attempts )); then
      echo "bootstrap apply: $label postcondition not visible; retrying ($attempt/$bootstrap_apply_retry_attempts)" >&2
      sleep "$bootstrap_apply_retry_sleep_secs"
      attempt=$(( attempt + 1 ))
      continue
    fi
    fail_bootstrap_diff "$label" "$expected_json" "$actual_json"
  done
}

ensure_view_predicate_or_apply() {
  local label="$1"
  local contract_id="$2"
  local view_entrypoint="$3"
  local view_payload_json="$4"
  local expected_json="$5"
  local call_entrypoint="$6"
  local call_payload_json="$7"
  local live_predicate_jq="$8"
  local actual_json
  local attempt=1

  actual_json="$(view_result_json "$contract_id" "$view_entrypoint" "$view_payload_json" 2>/dev/null || true)"
  if json_value_present "$actual_json" && jq -en \
    --argjson actual "$actual_json" \
    --argjson expected "$expected_json" \
    "$live_predicate_jq" \
    >/dev/null; then
    echo "bootstrap skip: $label already matches expected live state"
    return 0
  fi

  while (( attempt <= bootstrap_apply_retry_attempts )); do
    echo "bootstrap apply: $label"
    if ! call_contract_and_wait "$config" "$contract_id" "$call_entrypoint" "$call_payload_json" >/dev/null; then
      actual_json="$(view_result_json_with_retry "$contract_id" "$view_entrypoint" "$view_payload_json" 2>/dev/null || true)"
      if json_value_present "$actual_json" && jq -en \
        --argjson actual "$actual_json" \
        --argjson expected "$expected_json" \
        "$live_predicate_jq" \
        >/dev/null; then
        echo "bootstrap note: $label submit failed after reaching expected live state"
        return 0
      fi
      if (( attempt < bootstrap_apply_retry_attempts )); then
        echo "bootstrap apply: $label submit failed; retrying ($attempt/$bootstrap_apply_retry_attempts)" >&2
        sleep "$bootstrap_apply_retry_sleep_secs"
        attempt=$(( attempt + 1 ))
        continue
      fi
      return 1
    fi

    actual_json="$(view_result_json_with_retry "$contract_id" "$view_entrypoint" "$view_payload_json")"
    if jq -en \
      --argjson actual "$actual_json" \
      --argjson expected "$expected_json" \
      "$live_predicate_jq" \
      >/dev/null; then
      return 0
    fi
    if (( attempt < bootstrap_apply_retry_attempts )); then
      echo "bootstrap apply: $label postcondition not visible; retrying ($attempt/$bootstrap_apply_retry_attempts)" >&2
      sleep "$bootstrap_apply_retry_sleep_secs"
      attempt=$(( attempt + 1 ))
      continue
    fi
    fail_bootstrap_diff "$label" "$expected_json" "$actual_json"
  done
}

dlmm_seed_snapshot_json() {
  local next_bin_id="$1"
  local far_bin_id="$2"
  local active_json next_json far_json position_json

  active_json="$(view_result_json "$dlmm_pool_contract" mirror_bin "$(jq -cn --arg bin_id "$pool_active_bin" '{bin_id: $bin_id}')")"
  next_json="$(view_result_json "$dlmm_pool_contract" mirror_bin "$(jq -cn --arg bin_id "$next_bin_id" '{bin_id: $bin_id}')")"
  far_json="$(view_result_json "$dlmm_pool_contract" mirror_bin "$(jq -cn --arg bin_id "$far_bin_id" '{bin_id: $bin_id}')")"
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

dlmm_live_reserve_totals_json() {
  local next_bin_id="$1"
  local far_bin_id="$2"
  local active_json next_json far_json

  active_json="$(view_result_json "$dlmm_pool_contract" "mirror_bin" "$(jq -cn --arg bin_id "$pool_active_bin" '{bin_id: $bin_id}')")"
  next_json="$(view_result_json "$dlmm_pool_contract" "mirror_bin" "$(jq -cn --arg bin_id "$next_bin_id" '{bin_id: $bin_id}')")"
  far_json="$(view_result_json "$dlmm_pool_contract" "mirror_bin" "$(jq -cn --arg bin_id "$far_bin_id" '{bin_id: $bin_id}')")"

  jq -cn \
    --argjson active "$active_json" \
    --argjson next "$next_json" \
    --argjson far "$far_json" \
    '{
      base: (($active[0] // 0) + ($next[0] // 0) + ($far[0] // 0)),
      quote: (($active[1] // 0) + ($next[1] // 0) + ($far[1] // 0))
    }'
}

ensure_dlmm_pool_custody_balances() {
  local next_bin_id="$1"
  local far_bin_id="$2"
  local reserve_totals_json expected_base expected_quote actual_base actual_quote
  local topup_base topup_quote authority_base authority_quote

  reserve_totals_json="$(dlmm_live_reserve_totals_json "$next_bin_id" "$far_bin_id")"
  expected_base="$(jq -r '.base' <<<"$reserve_totals_json")"
  expected_quote="$(jq -r '.quote' <<<"$reserve_totals_json")"
  actual_base="$(asset_value_for_account_id "$config" "$xor_id" "$dlmm_pool_vault_account")"
  actual_quote="$(asset_value_for_account_id "$config" "$usdt_id" "$dlmm_pool_vault_account")"

  if (( actual_base >= expected_base && actual_quote >= expected_quote )); then
    echo "bootstrap skip: dlmm pool custody balances cover live reserve totals"
    return 0
  fi

  topup_base=$(( expected_base - actual_base ))
  topup_quote=$(( expected_quote - actual_quote ))
  (( topup_base < 0 )) && topup_base=0
  (( topup_quote < 0 )) && topup_quote=0
  authority_base="$(asset_value_for_account_id "$config" "$xor_id" "$SORASWAP_AUTHORITY")"
  authority_quote="$(asset_value_for_account_id "$config" "$usdt_id" "$SORASWAP_AUTHORITY")"
  if (( authority_base < topup_base || authority_quote < topup_quote )); then
    fail_bootstrap_diff \
      "dlmm pool custody funding" \
      "$(jq -cn --argjson base "$topup_base" --argjson quote "$topup_quote" '{required_base: $base, required_quote: $quote}')" \
      "$(jq -cn --argjson base "$authority_base" --argjson quote "$authority_quote" '{authority_base: $base, authority_quote: $quote}')"
  fi

  if (( topup_base > 0 )); then
    echo "bootstrap apply: dlmm pool custody base top-up"
    transfer_asset_balance_between_accounts "$config" "$SORASWAP_AUTHORITY" "$dlmm_pool_vault_account" "$xor_id" "$topup_base"
  fi
  if (( topup_quote > 0 )); then
    echo "bootstrap apply: dlmm pool custody quote top-up"
    transfer_asset_balance_between_accounts "$config" "$SORASWAP_AUTHORITY" "$dlmm_pool_vault_account" "$usdt_id" "$topup_quote"
  fi

  actual_base="$(asset_value_for_account_id "$config" "$xor_id" "$dlmm_pool_vault_account")"
  actual_quote="$(asset_value_for_account_id "$config" "$usdt_id" "$dlmm_pool_vault_account")"
  if (( actual_base < expected_base || actual_quote < expected_quote )); then
    fail_bootstrap_diff \
      "dlmm pool custody balances" \
      "$(jq -cn --argjson base "$expected_base" --argjson quote "$expected_quote" '{base: $base, quote: $quote}')" \
      "$(jq -cn --argjson base "$actual_base" --argjson quote "$actual_quote" '{base: $base, quote: $quote}')"
  fi
}

temp_signer_config_for_public_private_keys() {
  local public_key="$1"
  local private_key="$2"

  TMPDIR="$bootstrap_secret_dir" \
    materialize_cli_compatible_config "$config" "$public_key" "$private_key"
}

contract_subject_signer_config() {
  local contract_id="$1"
  local kagami_bin seed seed_hex key_output public_key private_key

  ensure_kagami_bin >/dev/null
  kagami_bin="${KAGAMI_BIN:-$SORASWAP_IROHA_ROOT/target/debug/kagami}"
  seed="iroha:contract-subject:v1:${contract_id}"
  seed_hex="$(printf '%s' "$seed" | json_sha256)"
  if [[ ! "$seed_hex" =~ '^[0-9a-f]{64}$' ]]; then
    echo "failed to derive deterministic contract subject signer seed for $contract_id" >&2
    return 1
  fi
  key_output="$("$kagami_bin" keys --algorithm ed25519 --seed-hex "$seed_hex" --compact 2>/dev/null)"
  public_key="$(awk '/^ed[0-9A-Fa-f]+$/ { print; exit }' <<<"$key_output")"
  private_key="$(awk '/^8026[0-9A-Fa-f]+$/ { print; exit }' <<<"$key_output")"
  if [[ -z "$public_key" || -z "$private_key" ]]; then
    echo "failed to derive contract subject signer for $contract_id" >&2
    return 1
  fi

  temp_signer_config_for_public_private_keys "$public_key" "$private_key"
}

transfer_asset_balance_between_accounts() {
  local signer_config="$1"
  local source_account="$2"
  local destination_account="$3"
  local asset_id="$4"
  local quantity="$5"

  if (( quantity <= 0 )); then
    return 0
  fi

  iroha_cli_with_authority_fee "$signer_config" ledger asset transfer \
    --definition "$asset_id" \
    --account "$source_account" \
    --to "$destination_account" \
    --quantity "$quantity" >/dev/null
}

migrate_contract_subject_balance_if_needed() {
  local label="$1"
  local source_account="$2"
  local destination_account="$3"
  local asset_id="$4"
  local quantity

  if [[ "$mode" == "local" ]]; then
    return 0
  fi
  if [[ -z "$source_account" || -z "$destination_account" || "$source_account" == "$destination_account" ]]; then
    return 0
  fi

  quantity="$(asset_value_for_account_id "$config" "$asset_id" "$source_account")"
  if (( quantity <= 0 )); then
    return 0
  fi

  echo "bootstrap apply: $label custody migration"
  transfer_asset_balance_between_accounts "$config" "$source_account" "$destination_account" "$asset_id" "$quantity"
}

ensure_signer_fee_balance() {
  local account_id="$1"
  local minimum_balance="${2:-$bootstrap_signer_fee_minimum}"
  local current_balance topup authority_balance

  if [[ -z "$account_id" || "$account_id" == "$SORASWAP_AUTHORITY" ]]; then
    return 0
  fi

  current_balance="$(asset_value_for_account_id "$config" "$fee_asset_id" "$account_id")"
  if (( current_balance >= minimum_balance )); then
    return 0
  fi

  topup=$(( minimum_balance - current_balance ))
  authority_balance="$(asset_value_for_account_id "$config" "$fee_asset_id" "$SORASWAP_AUTHORITY")"
  if (( authority_balance < topup )); then
    fail_bootstrap_diff \
      "signer fee funding" \
      "$(jq -cn --arg signer "$account_id" --arg fee_asset "$fee_asset_id" --argjson minimum_balance "$minimum_balance" --argjson topup "$topup" '{ signer: $signer, fee_asset: $fee_asset, minimum_balance: $minimum_balance, topup_required: $topup }')" \
      "$(jq -cn --arg authority "$SORASWAP_AUTHORITY" --arg fee_asset "$fee_asset_id" --argjson authority_balance "$authority_balance" '{ authority: $authority, fee_asset: $fee_asset, authority_balance: $authority_balance }')"
  fi

  echo "bootstrap apply: signer fee top-up for $account_id"
  transfer_asset_balance_between_accounts "$config" "$SORASWAP_AUTHORITY" "$account_id" "$fee_asset_id" "$topup"
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
  if jq -en \
    --argjson actual "$actual_state_json" \
    --argjson expected "$expected_state_json" \
    '
      true
      and ($actual.active_bin | length) == ($expected.active_bin | length)
      and ($actual.next_bin | length) == ($expected.next_bin | length)
      and ($actual.far_bin | length) == ($expected.far_bin | length)
      and ($actual.position | length) == ($expected.position | length)
      and (($actual.active_bin[0] // 0) > 0)
      and (($actual.active_bin[1] // 0) >= 0)
      and (($actual.active_bin[2] // 0) > 0)
      and (($actual.active_bin[3] // 0) >= 0)
      and (($actual.active_bin[4] // 0) >= 0)
      and (($actual.next_bin[0] // 0) >= 0)
      and (($actual.next_bin[1] // 0) >= 0)
      and (($actual.next_bin[2] // 0) > 0)
      and (($actual.next_bin[3] // 0) >= 0)
      and (($actual.next_bin[4] // 0) >= 0)
      and (($actual.far_bin[0] // 0) >= 0)
      and (($actual.far_bin[1] // 0) >= 0)
      and (($actual.far_bin[2] // 0) > 0)
      and (($actual.far_bin[3] // 0) >= 0)
      and (($actual.far_bin[4] // 0) >= 0)
      and ($actual.position[0] == 1)
      and ($actual.position[1] == $expected.position[1])
      and (($actual.position[2] // 0) > 0)
      and (($actual.active_bin[2] // 0) >= ($actual.position[2] // 0))
      and (($actual.position[3] // 0) >= 0)
      and (($actual.position[4] // 0) >= 0)
      and (($actual.position[5] // 0) >= 0)
      and (($actual.position[6] // 0) >= 0)
    ' >/dev/null; then
    echo "bootstrap skip: dlmm pool seed state already reflects live liquidity"
    return 0
  fi
  if ! json_equals "$actual_state_json" "$empty_state_json"; then
    fail_bootstrap_diff "dlmm pool seed state" "$expected_state_json" "$actual_state_json" "$empty_state_json"
  fi

  echo "bootstrap apply: dlmm pool seed state"

  seed_payload_json="$(jq -cn \
    --arg position_id "${pool_position_id}_seed_active" \
    --arg bin_id "$pool_active_bin" \
    --arg base_amount "$pool_seed_base" \
    --arg quote_amount "$pool_seed_quote" \
    '{
      position_id: $position_id,
      bin_id: $bin_id,
      base_amount: $base_amount,
      quote_amount: $quote_amount
    }')"
  call_contract_and_wait "$config" "$dlmm_pool_contract" seed_bin "$seed_payload_json" >/dev/null

  seed_payload_json="$(jq -cn \
    --arg position_id "${pool_position_id}_seed_next" \
    --arg bin_id "$next_bin_id" \
    --arg base_amount "$pool_seed_next_base" \
    --arg quote_amount "$pool_seed_next_quote" \
    '{
      position_id: $position_id,
      bin_id: $bin_id,
      base_amount: $base_amount,
      quote_amount: $quote_amount
    }')"
  call_contract_and_wait "$config" "$dlmm_pool_contract" seed_bin "$seed_payload_json" >/dev/null

  seed_payload_json="$(jq -cn \
    --arg position_id "${pool_position_id}_seed_far" \
    --arg bin_id "$far_bin_id" \
    --arg base_amount "$pool_seed_far_base" \
    --arg quote_amount "$pool_seed_far_quote" \
    '{
      position_id: $position_id,
      bin_id: $bin_id,
      base_amount: $base_amount,
      quote_amount: $quote_amount
    }')"
  call_contract_and_wait "$config" "$dlmm_pool_contract" seed_bin "$seed_payload_json" >/dev/null

  position_payload_json="$(jq -cn \
    --arg position_id "$pool_position_id" \
    --arg bin_id "$pool_active_bin" \
    --arg base_amount "$pool_position_base" \
    --arg quote_amount "$pool_position_quote" \
    --arg min_shares_out "$pool_position_min_shares_out" \
    '{
      position_id: $position_id,
      bin_id: $bin_id,
      base_amount: $base_amount,
      quote_amount: $quote_amount,
      min_shares_out: $min_shares_out
    }')"
  call_contract_and_wait "$config" "$dlmm_pool_contract" add_position_liquidity "$position_payload_json" >/dev/null

  actual_state_json="$(dlmm_seed_snapshot_json "$next_bin_id" "$far_bin_id")"
  if ! json_equals "$actual_state_json" "$expected_state_json"; then
    fail_bootstrap_diff "dlmm pool seed state" "$expected_state_json" "$actual_state_json" "$empty_state_json"
  fi
}

warmup_sale_payload="$(jq -cn --arg sale "warmup" '{sale: $sale}')"
warmup_member_payload="$(jq -cn --arg member "warmup" '{member: $member}')"
warmup_position_payload="$(jq -cn --arg position "warmup" '{position: $position}')"
warmup_market_payload='{"market_id":"1"}'
warmup_series_payload='{"series_id":"1"}'
warmup_policy_payload='{"policy_id":"1"}'
warmup_job_payload="$(jq -cn --arg job "warmup" '{job: $job}')"
warmup_escrow_payload="$(jq -cn --arg escrow_id "warmup" '{escrow_id: $escrow_id}')"
warmup_quote_mint_payload='{"usdt_in":"0","usdc_in":"0","kusd_in":"0"}'
warmup_quote_direct_payload='{"reserve_in":"1","reserve_out":"1","amount_in":"1","fee_pips":"0"}'

# The first IVM execution against a freshly deployed debug localnet can be
# slow enough to trip the single-peer consensus timeout. Prewarm each contract
# with a lightweight view before the first mutating bootstrap call.
warm_view "$n3x_hub_contract" quote_mint "$warmup_quote_mint_payload"
warm_view "$dlmm_router_contract" quote_direct "$warmup_quote_direct_payload"
warm_view "$dlmm_pool_contract" pool_config
warm_view "$batch_epoch_auction_contract" epoch_state
warm_view "$escrow_conditional_escrow_contract" escrow_state "$warmup_escrow_payload"
if [[ "$bootstrap_scope" != "foundation" ]]; then
  warm_view "$launchpad_liquidity_executor_contract" executor_config
  warm_view "$launchpad_sale_factory_contract" sale_config "$warmup_sale_payload"
  warm_view "$referral_registry_contract" registry_config
  warm_view "$farms_farm_contract" farm_config
  warm_view "$perps_engine_contract" engine_config
  warm_view "$perps_engine_contract" market_state "$warmup_market_payload"
  warm_view "$options_factory_contract" factory_config
  warm_view "$options_factory_contract" series_state "$warmup_series_payload"
  warm_view "$cover_policy_manager_contract" manager_config
  warm_view "$cover_policy_manager_contract" policy_state "$warmup_policy_payload"
  warm_view "$automation_job_queue_contract" mirror_job "$warmup_job_payload"
fi
if [[ -n "$sccp_bridge_contract" ]]; then
  warm_view "$sccp_bridge_contract" listing_config
fi

n3x_expected_json="$(jq -cn \
  --arg usdt_asset "$usdt_id" \
  --arg usdc_asset "$usdc_id" \
  --arg kusd_asset "$kusd_id" \
  --arg n3x_asset "$n3x_id" \
  --arg vault_account "$n3x_vault_account" \
  --argjson mint_fee_bps "$n3x_mint_fee_bps" \
  --argjson redeem_fee_bps "$n3x_redeem_fee_bps" \
  --argjson target_usdt_bps "$n3x_target_usdt_bps" \
  --argjson target_usdc_bps "$n3x_target_usdc_bps" \
  --argjson target_kusd_bps "$n3x_target_kusd_bps" \
  '[ $usdt_asset, $usdc_asset, $kusd_asset, $n3x_asset, $vault_account, $mint_fee_bps, $redeem_fee_bps, $target_usdt_bps, $target_usdc_bps, $target_kusd_bps ]')"
n3x_init_payload="$(jq -cn \
  --arg usdt_asset "$usdt_id" \
  --arg usdc_asset "$usdc_id" \
  --arg kusd_asset "$kusd_id" \
  --arg n3x_asset "$n3x_id" \
  --arg vault_account "$n3x_vault_account" \
  --arg target_usdt_bps "$n3x_target_usdt_bps" \
  --arg target_usdc_bps "$n3x_target_usdc_bps" \
  --arg target_kusd_bps "$n3x_target_kusd_bps" \
  --arg mint_fee_bps "$n3x_mint_fee_bps" \
  --arg redeem_fee_bps "$n3x_redeem_fee_bps" \
  '{
    usdt_asset: $usdt_asset,
    usdc_asset: $usdc_asset,
    kusd_asset: $kusd_asset,
    n3x_asset: $n3x_asset,
    vault_account: $vault_account,
    target_usdt_bps: $target_usdt_bps,
    target_usdc_bps: $target_usdc_bps,
    target_kusd_bps: $target_kusd_bps,
    mint_fee_bps: $mint_fee_bps,
    redeem_fee_bps: $redeem_fee_bps
  }')"
ensure_init_or_skip \
  "n3x hub config" \
  "$n3x_hub_contract" \
  "hub_config" \
  null \
  "$n3x_expected_json" \
  "hajimari" \
  "$n3x_init_payload"

ensure_view_predicate_or_apply \
  "epoch auction init" \
  "$batch_epoch_auction_contract" \
  "auction_config" \
  null \
  '[1, 1, 1]' \
  "hajimari" \
  "$(jq -cn \
    --arg base_asset "$xor_id" \
    --arg quote_asset "$n3x_id" \
    --arg custody_account "$batch_epoch_auction_contract_subject" \
    --arg guardian "$SORASWAP_AUTHORITY" \
    '{ base_asset: $base_asset, quote_asset: $quote_asset, custody_account: $custody_account, guardian: $guardian }')" \
  '($actual == $expected)'
apply_step_and_expect \
  "epoch auction unpause" \
  "$batch_epoch_auction_contract" \
  "auction_config" \
  null \
  '[1, 1, 0]' \
  "exit_paused" \
  null
epoch_auction_expected_json="$(jq -cn \
  --argjson epoch_id "$epoch_auction_epoch_id" \
  --argjson start_slot "$epoch_auction_start_slot" \
  --argjson end_slot "$epoch_auction_end_slot" \
  --argjson lower_tick "$epoch_auction_lower_tick" \
  --argjson upper_tick "$epoch_auction_upper_tick" \
  --argjson tick_step "$epoch_auction_tick_step" \
  '[ $epoch_id, 1, $start_slot, $end_slot, $lower_tick, $upper_tick, $tick_step, 0, 0, 0, 0 ]')"
ensure_view_predicate_or_apply \
  "epoch auction current epoch" \
  "$batch_epoch_auction_contract" \
  "epoch_state" \
  null \
  "$epoch_auction_expected_json" \
  "configure_epoch" \
  "$(jq -cn \
    --arg epoch_id "$epoch_auction_epoch_id" \
    --arg start_slot "$epoch_auction_start_slot" \
    --arg end_slot "$epoch_auction_end_slot" \
    --arg lower_tick "$epoch_auction_lower_tick" \
    --arg upper_tick "$epoch_auction_upper_tick" \
    --arg tick_step "$epoch_auction_tick_step" \
    --arg max_orders "$epoch_auction_max_orders" \
    '{
      epoch_id: $epoch_id,
      start_slot: $start_slot,
      end_slot: $end_slot,
      lower_tick: $lower_tick,
      upper_tick: $upper_tick,
      tick_step: $tick_step,
      max_orders: $max_orders
    }')" \
  '(
      (($actual[0] // 0) > ($expected[0] // 0))
      or (
        (($actual[0] // 0) == ($expected[0] // 0))
        and (($actual[1] // 0) >= 1)
        and (($actual[4] // 0) == ($expected[4] // 0))
        and (($actual[5] // 0) == ($expected[5] // 0))
        and (($actual[6] // 0) == ($expected[6] // 0))
      )
    )'

ensure_view_predicate_or_apply \
  "conditional escrow init" \
  "$escrow_conditional_escrow_contract" \
  "escrow_config" \
  null \
  "$(jq -cn --arg escrow_account "$escrow_conditional_escrow_contract_subject" '$escrow_account')" \
  "hajimari" \
  "$(jq -cn --arg escrow_account "$escrow_conditional_escrow_contract_subject" '{ escrow_account: $escrow_account }')" \
  '($actual == $expected)'

pool_expected_json="$(jq -cn \
  --arg base_asset "$xor_id" \
  --arg quote_asset "$usdt_id" \
  --arg vault_account "$dlmm_pool_vault_account" \
  --argjson fee_pips "$pool_fee_pips" \
  --argjson bin_step "$pool_bin_step" \
  --argjson active_bin "$pool_active_bin" \
  '[ $base_asset, $quote_asset, $vault_account, $fee_pips, $bin_step, $active_bin ]')"
pool_init_payload="$(jq -cn \
  --arg base_asset "$xor_id" \
  --arg quote_asset "$usdt_id" \
  --arg vault_account "$dlmm_pool_vault_account" \
  --arg launchpad_executor "$launchpad_liquidity_executor_contract_subject" \
  --arg fee_pips "$pool_fee_pips" \
  --arg bin_step "$pool_bin_step" \
  --arg active_bin "$pool_active_bin" \
  --arg impact_cap_bps "$pool_impact_cap_bps" \
  --arg min_reserve_base "$pool_min_reserve_base" \
  --arg min_reserve_quote "$pool_min_reserve_quote" \
  --arg max_bins_per_swap "$pool_max_bins_per_swap" \
  --arg bin_liquidity_cap "$pool_bin_liquidity_cap" \
  '{
    base_asset: $base_asset,
    quote_asset: $quote_asset,
    vault_account: $vault_account,
    launchpad_executor: $launchpad_executor,
    fee_pips: $fee_pips,
    bin_step: $bin_step,
    active_bin: $active_bin,
    impact_cap_bps: $impact_cap_bps,
    min_reserve_base: $min_reserve_base,
    min_reserve_quote: $min_reserve_quote,
    max_bins_per_swap: $max_bins_per_swap,
    bin_liquidity_cap: $bin_liquidity_cap
  }')"
pool_actual_json="$(view_result_json "$dlmm_pool_contract" "pool_config" null 2>/dev/null || true)"
if [[ -z "$pool_actual_json" ]]; then
  echo "bootstrap init: dlmm pool config"
  call_contract_and_wait "$config" "$dlmm_pool_contract" "hajimari" "$pool_init_payload" >/dev/null
  pool_actual_json="$(view_result_json "$dlmm_pool_contract" "pool_config" null)"
fi
if json_equals "$pool_actual_json" "$pool_expected_json"; then
  echo "bootstrap skip: dlmm pool config already matches expected state"
elif jq -en \
  --argjson actual "$pool_actual_json" \
  --argjson expected "$pool_expected_json" \
  '
    ($actual | length) == 6
    and ($expected | length) == 6
    and ($actual[0] == $expected[0])
    and ($actual[1] == $expected[1])
    and ($actual[2] == $expected[2])
    and ($actual[3] == $expected[3])
    and ($actual[4] == $expected[4])
    and ($actual[5] != $expected[5])
  ' >/dev/null; then
  pool_live_active_bin="$(jq -r '.[5]' <<<"$pool_actual_json")"
  echo "bootstrap note: dlmm pool active bin differs from the configured seed anchor (live=${pool_live_active_bin}, expected=${pool_active_bin}); preserving live active bin and leaving price-state realignment to swaps/governed triggers"
  pool_expected_json="$(jq -cn \
    --arg base_asset "$xor_id" \
    --arg quote_asset "$usdt_id" \
    --arg vault_account "$dlmm_pool_vault_account" \
    --argjson fee_pips "$pool_fee_pips" \
    --argjson bin_step "$pool_bin_step" \
    --argjson active_bin "$pool_live_active_bin" \
    '[ $base_asset, $quote_asset, $vault_account, $fee_pips, $bin_step, $active_bin ]')"
else
  fail_bootstrap_diff "dlmm pool config" "$pool_expected_json" "$pool_actual_json"
fi

pool_launchpad_binding_expected_json="$(jq -cn \
  --arg executor "$launchpad_liquidity_executor_contract_subject" \
  --argjson initialization_bin "$pool_active_bin" \
  '[ $executor, $initialization_bin ]')"
pool_launchpad_binding_actual_json="$(view_result_json "$dlmm_pool_contract" "launchpad_binding" null)"
if ! json_equals "$pool_launchpad_binding_actual_json" "$pool_launchpad_binding_expected_json"; then
  fail_bootstrap_diff \
    "dlmm pool launchpad binding" \
    "$pool_launchpad_binding_expected_json" \
    "$pool_launchpad_binding_actual_json"
fi
echo "bootstrap skip: dlmm pool launchpad binding matches the executor subject and immutable initialization bin"

ensure_account_registered "$config" "$dlmm_router_guardian_account" dlmm-router-guardian
ensure_unit_account_permission "$config" "$dlmm_router_guardian_account" Admin
router_init_expected_json="$(jq -cn \
  --arg base_asset "$xor_id" \
  --arg quote_asset "$usdt_id" \
  --argjson default_fee_pips "$pool_fee_pips" \
  --arg router_account "$dlmm_router_contract_subject" \
  --arg pool_contract "$dlmm_pool_contract_blob_hex" \
  '[ $base_asset, $quote_asset, $default_fee_pips, $router_account, $pool_contract, 1 ]')"
router_init_payload="$(jq -cn \
  --arg base_asset "$xor_id" \
  --arg quote_asset "$usdt_id" \
  --arg default_fee_pips "$pool_fee_pips" \
  --arg pool_contract "$dlmm_pool_contract_blob_hex" \
  --arg guardian "$dlmm_router_guardian_account" \
  '{
    base_asset: $base_asset,
    quote_asset: $quote_asset,
    default_fee_pips: $default_fee_pips,
    pool_contract: $pool_contract,
    guardian: $guardian
  }')"
ensure_init_or_skip_with_live_predicate \
  "dlmm router config" \
  "$dlmm_router_contract" \
  "router_config" \
  null \
  "$router_init_expected_json" \
  "hajimari" \
  "$router_init_payload" \
  '($actual | length) == 6
   and ($actual[0:5] == $expected[0:5])
   and (($actual[5] // -1) == 0)'

router_live_expected_json="$(jq -c '.[5] = 0' <<<"$router_init_expected_json")"
apply_step_and_expect \
  "dlmm router unpause" \
  "$dlmm_router_contract" \
  "router_config" \
  null \
  "$router_live_expected_json" \
  "set_paused" \
  '{"paused":"0"}'

next_bin_id=$(( pool_active_bin + pool_bin_step ))
far_bin_id=$(( pool_active_bin + (2 * pool_bin_step) ))
ensure_dlmm_pool_custody_balances "$next_bin_id" "$far_bin_id"
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

dlmm_range_governor_expected_json="$(jq -cn \
  --argjson enabled "$dlmm_range_governor_enabled" \
  --argjson cadence_slots "$dlmm_range_governor_cadence_slots" \
  --argjson max_fee_pips "$dlmm_range_governor_max_fee_pips" \
  --argjson target_active_bin "$dlmm_range_governor_target_active_bin" \
  --argjson max_active_bin_drift "$dlmm_range_governor_max_active_bin_drift" \
  '[ $enabled, $cadence_slots, 0, $max_fee_pips, $target_active_bin, $max_active_bin_drift, 0, 0 ]')"
ensure_view_predicate_or_apply \
  "dlmm range governor" \
  "$dlmm_pool_contract" \
  "range_governor_state" \
  null \
  "$dlmm_range_governor_expected_json" \
  "configure_range_governor" \
  "$(jq -cn \
    --arg cadence_slots "$dlmm_range_governor_cadence_slots" \
    --arg max_fee_pips "$dlmm_range_governor_max_fee_pips" \
    --arg target_active_bin "$dlmm_range_governor_target_active_bin" \
    --arg max_active_bin_drift "$dlmm_range_governor_max_active_bin_drift" \
    --arg enabled "$dlmm_range_governor_enabled" \
    '{
      cadence_slots: $cadence_slots,
      max_fee_pips: $max_fee_pips,
      target_active_bin: $target_active_bin,
      max_active_bin_drift: $max_active_bin_drift,
      enabled: $enabled
    }')" \
  '$actual[0] == $expected[0]
   and $actual[1] == $expected[1]
   and (($actual[2] // 0) >= 0)
   and $actual[3] == $expected[3]
   and $actual[4] == $expected[4]
   and $actual[5] == $expected[5]
   and (($actual[6] // 0) >= 0)
   and (($actual[7] // 0) >= 0)'

if [[ "$bootstrap_scope" == "foundation" ]]; then
  echo "post-deploy foundation contract state initialized"
  exit 0
fi

launchpad_guardian_account="${SORASWAP_LAUNCHPAD_GUARDIAN_ACCOUNT:-}"
if [[ -z "$launchpad_guardian_account" ]]; then
  echo "SORASWAP_LAUNCHPAD_GUARDIAN_ACCOUNT is required for full deployment" >&2
  exit 1
fi
case "$launchpad_guardian_account" in
  "$SORASWAP_AUTHORITY"|"$launchpad_liquidity_executor_contract_subject"|"$launchpad_sale_factory_contract_subject"|"$dlmm_hooks_manager_contract_subject")
    echo "SORASWAP_LAUNCHPAD_GUARDIAN_ACCOUNT must be distinct from the owner and guarded contract subjects" >&2
    exit 1
    ;;
esac
ensure_account_registered "$config" "$launchpad_guardian_account" launchpad-guardian
ensure_unit_account_permission "$config" "$launchpad_guardian_account" Admin

launchpad_executor_expected_json="$(jq -cn \
  --arg pool_contract "$dlmm_pool_contract_blob_hex" \
  --arg base_asset "$xor_id" \
  --arg quote_asset "$launchpad_pool_quote_asset_id" \
  --arg owner "$SORASWAP_AUTHORITY" \
  --arg guardian "$launchpad_guardian_account" \
  --arg executor_account "$launchpad_liquidity_executor_contract_subject" \
  --arg sale_factory_account "$launchpad_sale_factory_contract_subject" \
  '[
    $pool_contract,
    $base_asset,
    $quote_asset,
    $owner,
    $guardian,
    $executor_account,
    $sale_factory_account,
    1
  ]')"
launchpad_executor_init_payload="$(jq -cn \
  --arg pool_contract "$dlmm_pool_contract_blob_hex" \
  --arg base_asset "$xor_id" \
  --arg quote_asset "$launchpad_pool_quote_asset_id" \
  --arg sale_factory_account "$launchpad_sale_factory_contract_subject" \
  --arg guardian "$launchpad_guardian_account" \
  '{
    pool_contract: $pool_contract,
    base_asset: $base_asset,
    quote_asset: $quote_asset,
    sale_factory_account: $sale_factory_account,
    guardian: $guardian
  }')"
ensure_init_or_skip_with_live_predicate \
  "launchpad liquidity executor config" \
  "$launchpad_liquidity_executor_contract" \
  "executor_config" \
  null \
  "$launchpad_executor_expected_json" \
  "hajimari" \
  "$launchpad_executor_init_payload" \
  '($actual | length) == 8
   and ($actual[0:7] == $expected[0:7])
   and (($actual[7] // -1) == 0 or ($actual[7] // -1) == 1)'

launchpad_factory_expected_json="$(jq -cn \
  --arg owner "$SORASWAP_AUTHORITY" \
  --arg guardian "$launchpad_guardian_account" \
  --arg factory_account "$launchpad_sale_factory_contract_subject" \
  --arg executor_contract "$launchpad_liquidity_executor_contract_blob_hex" \
  '[ $owner, $guardian, $factory_account, $executor_contract, 1 ]')"
launchpad_factory_init_payload="$(jq -cn \
  --arg executor_contract "$launchpad_liquidity_executor_contract_blob_hex" \
  --arg guardian "$launchpad_guardian_account" \
  '{ executor_contract: $executor_contract, guardian: $guardian }')"

ensure_init_or_skip_with_live_predicate \
  "launchpad sale factory config" \
  "$launchpad_sale_factory_contract" \
  "factory_config" \
  null \
  "$launchpad_factory_expected_json" \
  "hajimari" \
  "$launchpad_factory_init_payload" \
  '($actual | length) == 5
   and ($actual[0:4] == $expected[0:4])
   and (($actual[4] // -1) == 0 or ($actual[4] // -1) == 1)'

launchpad_executor_live_json="$(jq -c '.[7] = 0' <<<"$launchpad_executor_expected_json")"
apply_step_and_expect \
  "launchpad liquidity executor unpause" \
  "$launchpad_liquidity_executor_contract" \
  "executor_config" \
  null \
  "$launchpad_executor_live_json" \
  "set_paused" \
  '{"paused":"0"}'

launchpad_factory_live_json="$(jq -c '.[4] = 0' <<<"$launchpad_factory_expected_json")"
apply_step_and_expect \
  "launchpad sale factory exit withdrawal-only mode" \
  "$launchpad_sale_factory_contract" \
  "factory_config" \
  null \
  "$launchpad_factory_live_json" \
  "exit_withdrawal_only" \
  null

product_trigger_lifecycle_expected_json="$(jq -cn \
  --argjson enabled "$trigger_lifecycle_enabled" \
  --argjson cadence_slots "$trigger_lifecycle_cadence_slots" \
  --argjson max_items "$trigger_lifecycle_max_items" \
  '[ $enabled, $cadence_slots, $max_items, 0, 0, 0, 0 ]')"
trigger_lifecycle_predicate='
  $actual[0] == $expected[0]
  and $actual[1] == $expected[1]
  and $actual[2] == $expected[2]
  and (($actual[3] // 0) >= 0)
  and (($actual[4] // 0) >= 0)
  and (($actual[5] // 0) >= 0)
  and (($actual[6] // 0) >= 0)
'
ensure_view_predicate_or_apply \
  "launchpad trigger lifecycle" \
  "$launchpad_sale_factory_contract" \
  "trigger_lifecycle_state" \
  null \
  "$product_trigger_lifecycle_expected_json" \
  "configure_trigger_lifecycle" \
  "$(jq -cn \
    --arg cadence_slots "$trigger_lifecycle_cadence_slots" \
    --arg max_items_per_tick "$trigger_lifecycle_max_items" \
    --arg enabled "$trigger_lifecycle_enabled" \
    '{ cadence_slots: $cadence_slots, max_items_per_tick: $max_items_per_tick, enabled: $enabled }')" \
  "$trigger_lifecycle_predicate"

referral_expected_json="$(jq -cn \
  --arg reward_asset "$xor_id" \
  --arg treasury "$vault_account" \
  --argjson claim_threshold "$referral_claim_threshold" \
  --argjson direct_share_bps "$referral_direct_share_bps" \
  --argjson parent_share_bps "$referral_parent_share_bps" \
  '[ $reward_asset, $treasury, $claim_threshold, $direct_share_bps, $parent_share_bps ]')"
referral_init_payload="$(jq -cn \
  --arg reward_asset "$xor_id" \
  --arg treasury "$vault_account" \
  --arg claim_threshold "$referral_claim_threshold" \
  --arg direct_share_bps "$referral_direct_share_bps" \
  --arg parent_share_bps "$referral_parent_share_bps" \
  '{
    reward_asset: $reward_asset,
    treasury: $treasury,
    claim_threshold: $claim_threshold,
    direct_share_bps: $direct_share_bps,
    parent_share_bps: $parent_share_bps
  }')"
ensure_init_or_skip \
  "referral registry config" \
  "$referral_registry_contract" \
  "registry_config" \
  null \
  "$referral_expected_json" \
  "hajimari" \
  "$referral_init_payload"

farm_expected_json="$(jq -cn --arg stake_asset "$n3x_id" --arg reward_asset "$xor_id" --arg treasury "$vault_account" '[ $stake_asset, $reward_asset, $treasury, 10 ]')"
farm_init_payload="$(jq -cn \
  --arg stake_asset "$n3x_id" \
  --arg reward_asset "$xor_id" \
  --arg treasury "$vault_account" \
  --arg reward_rate 10 \
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
  "hajimari" \
  "$farm_init_payload"

engine_init_expected_json="$(jq -cn \
  --arg collateral_asset "$usdt_id" \
  --arg custody_account "$perps_engine_contract_subject" \
  --arg oracle_account "$SORASWAP_ACTIVE_ORACLE_ACCOUNT" \
  '[ $collateral_asset, $custody_account, $oracle_account, 1, 1, 1, 0, 0, 0 ]')"
engine_live_expected_json="$(jq -cn \
  --arg collateral_asset "$usdt_id" \
  --arg custody_account "$perps_engine_contract_subject" \
  --arg oracle_account "$SORASWAP_ACTIVE_ORACLE_ACCOUNT" \
  '[ $collateral_asset, $custody_account, $oracle_account, 0, 1, 1, 0, 0, 0 ]')"
perps_automation_expected_json='[1,201,202,4,6,0,0]'
perps_market_expected_json="$(jq -cn \
  --argjson open_interest_cap "$perps_open_interest_cap" \
  --argjson max_leverage_bps "$perps_max_leverage_bps" \
  --argjson maintenance_margin_bps "$perps_maintenance_margin_bps" \
  --argjson liquidation_fee_bps "$perps_liquidation_fee_bps" \
  --argjson funding_bps "$perps_funding_bps" \
  --argjson funding_interval_slots "$perps_funding_interval_slots" \
  --argjson oracle_stale_slots "$perps_oracle_stale_slots" \
  --argjson backlog_limit "$perps_backlog_limit" \
  '[ 1, 1, 0, $open_interest_cap, $max_leverage_bps, $maintenance_margin_bps, $liquidation_fee_bps, $funding_bps, $funding_interval_slots, $oracle_stale_slots, 0, 0, $backlog_limit ]')"
engine_init_payload="$(jq -cn \
  --arg collateral_asset "$usdt_id" \
  --arg custody_account "$perps_engine_contract_subject" \
  --arg oracle_account "$SORASWAP_ACTIVE_ORACLE_ACCOUNT" \
  '{
    collateral_asset: $collateral_asset,
    custody_account: $custody_account,
    oracle_account: $oracle_account
  }')"
assert_perps_engine_config() {
  local engine_json="$1"

  jq -en \
    --argjson actual "$engine_json" \
    --arg collateral_asset "$usdt_id" \
    --arg custody_account "$perps_engine_contract_subject" \
    --arg oracle_account "$SORASWAP_ACTIVE_ORACLE_ACCOUNT" \
    '
      ($actual | type) == "array"
      and ($actual | length) == 9
      and $actual[0] == $collateral_asset
      and $actual[1] == $custody_account
      and $actual[2] == $oracle_account
      and (($actual[3] == 0) or ($actual[3] == 1))
      and ($actual[4] >= 1)
      and ($actual[5] >= 1)
      and ($actual[6] >= 0)
      and ($actual[7] >= 0)
      and ($actual[8] >= 0)
    ' >/dev/null
}

ensure_perps_engine_hajimari() {
  local initialized_json engine_json init_output

  initialized_json="$(view_result_json "$perps_engine_contract" "main" null)"
  case "$(jq -er 'if . == 0 then "uninitialized" elif . == 1 then "initialized" else error("invalid initialization state") end' <<<"$initialized_json" 2>/dev/null || true)" in
    uninitialized)
      echo "bootstrap init: perps engine config"
      if ! init_output="$(call_contract_and_wait "$config" "$perps_engine_contract" "hajimari" "$engine_init_payload" 2>&1)"; then
        initialized_json="$(view_result_json_with_retry "$perps_engine_contract" "main" null 2>/dev/null || true)"
        if [[ "$initialized_json" != "1" ]]; then
          printf '%s\n' "$(soraswap_redact_sensitive_text "$init_output")" >&2
          return 1
        fi
        echo "bootstrap note: perps hajimari submit failed after initialization became visible"
      fi
      ;;
    initialized)
      echo "bootstrap skip: perps engine already initialized"
      ;;
    *)
      fail_bootstrap_diff "perps initialization state" 1 "$initialized_json"
      return 1
      ;;
  esac

  engine_json="$(view_result_json_with_retry "$perps_engine_contract" "engine_config" null)"
  if ! assert_perps_engine_config "$engine_json"; then
    fail_bootstrap_diff "perps engine config" "$engine_init_expected_json" "$engine_json"
    return 1
  fi
}

exit_perps_withdrawal_only() {
  local engine_json withdrawal_only

  engine_json="$(view_result_json "$perps_engine_contract" "engine_config" null)"
  if ! assert_perps_engine_config "$engine_json"; then
    fail_bootstrap_diff "perps engine config" "$engine_live_expected_json" "$engine_json"
    return 1
  fi
  withdrawal_only="$(jq -er '.[3]' <<<"$engine_json")"
  if (( withdrawal_only == 0 )); then
    echo "bootstrap skip: perps engine already live"
    return 0
  fi

  echo "bootstrap apply: perps engine exit withdrawal only"
  call_contract_and_wait "$config" "$perps_engine_contract" "exit_withdrawal_only" null >/dev/null
  engine_json="$(view_result_json_with_retry "$perps_engine_contract" "engine_config" null)"
  if ! assert_perps_engine_config "$engine_json" || [[ "$(jq -er '.[3]' <<<"$engine_json")" != "0" ]]; then
    fail_bootstrap_diff "perps engine exit withdrawal only" "$engine_live_expected_json" "$engine_json" "$engine_init_expected_json"
    return 1
  fi
}

ensure_perps_collateral_pool_funded() {
  local pool_json reserved_margin surplus amount

  pool_json="$(view_result_json "$perps_engine_contract" "collateral_pool_state" null)"
  if ! jq -en \
    --argjson actual "$pool_json" \
    --arg custody_account "$perps_engine_contract_subject" \
    '
      ($actual | type) == "array"
      and ($actual | length) == 4
      and $actual[0] == $custody_account
      and $actual[1] >= $actual[2]
      and $actual[2] >= 0
      and $actual[3] == ($actual[1] - $actual[2])
    ' >/dev/null; then
    fail_bootstrap_diff \
      "perps collateral pool" \
      "$(jq -cn --arg custody_account "$perps_engine_contract_subject" '[ $custody_account, 0, 0, 0 ]')" \
      "$pool_json"
    return 1
  fi

  reserved_margin="$(jq -er '.[2]' <<<"$pool_json")"
  surplus="$(jq -er '.[3]' <<<"$pool_json")"
  if (( surplus >= perps_collateral_pool_bootstrap_deposit )); then
    echo "bootstrap skip: perps collateral pool surplus already meets the configured minimum"
    return 0
  fi
  amount=$(( perps_collateral_pool_bootstrap_deposit - surplus ))
  if (( amount <= 0 )); then
    return 0
  fi

  echo "bootstrap apply: fund perps collateral pool by $amount"
  call_contract_and_wait \
    "$config" \
    "$perps_engine_contract" \
    "fund_collateral_pool" \
    "$(jq -cn --arg amount "$amount" '{ amount: $amount }')" \
    >/dev/null
  pool_json="$(view_result_json_with_retry "$perps_engine_contract" "collateral_pool_state" null)"
  if ! jq -en \
    --argjson actual "$pool_json" \
    --arg custody_account "$perps_engine_contract_subject" \
    --argjson minimum_surplus "$perps_collateral_pool_bootstrap_deposit" \
    --argjson prior_reserved "$reserved_margin" \
    --argjson prior_surplus "$surplus" \
    '
      ($actual | type) == "array"
      and ($actual | length) == 4
      and $actual[0] == $custody_account
      and $actual[1] >= $actual[2]
      and $actual[2] >= $prior_reserved
      and $actual[3] == ($actual[1] - $actual[2])
      and $actual[3] >= $minimum_surplus
      and $actual[3] >= $prior_surplus
    ' >/dev/null; then
    fail_bootstrap_diff \
      "perps collateral pool funding" \
      "$(jq -cn --arg custody_account "$perps_engine_contract_subject" --argjson surplus "$perps_collateral_pool_bootstrap_deposit" --argjson reserved "$reserved_margin" '[ $custody_account, ($reserved + $surplus), $reserved, $surplus ]')" \
      "$pool_json"
    return 1
  fi
}

assert_perps_collateral_pool_invariants() {
  local engine_json pool_json next_position_id position_id position_json live_margin=0

  engine_json="$(view_result_json "$perps_engine_contract" "engine_config" null)"
  pool_json="$(view_result_json "$perps_engine_contract" "collateral_pool_state" null)"
  if ! assert_perps_engine_config "$engine_json"; then
    fail_bootstrap_diff "perps engine config" "$engine_live_expected_json" "$engine_json"
    return 1
  fi
  next_position_id="$(jq -er '.[5]' <<<"$engine_json")"
  for (( position_id = 1; position_id < next_position_id; position_id++ )); do
    position_json="$(view_result_json \
      "$perps_engine_contract" \
      "position_state" \
      "$(jq -cn --arg position_id "$position_id" '{ position_id: $position_id }')")"
    if jq -en \
      --argjson position "$position_json" \
      '($position[0] == 1) and (($position[1] == 1) or ($position[1] == 3))' \
      >/dev/null; then
      live_margin=$(( live_margin + $(jq -er '.[4]' <<<"$position_json") ))
    fi
  done

  if ! jq -en \
    --argjson actual "$pool_json" \
    --arg custody_account "$perps_engine_contract_subject" \
    --argjson live_margin "$live_margin" \
    '
      ($actual | type) == "array"
      and ($actual | length) == 4
      and $actual[0] == $custody_account
      and $actual[1] >= $actual[2]
      and $actual[2] == $live_margin
      and $actual[3] == ($actual[1] - $actual[2])
    ' >/dev/null; then
    echo "bootstrap invariant failed: perps collateral pool does not reconcile with live position margin" >&2
    jq -cn \
      --argjson engine_config "$engine_json" \
      --argjson collateral_pool_state "$pool_json" \
      --argjson computed_live_margin "$live_margin" \
      '{ engine_config: $engine_config, collateral_pool_state: $collateral_pool_state, computed_live_margin: $computed_live_margin }' >&2
    return 1
  fi
}

ensure_perps_engine_hajimari
apply_step_and_expect \
  "perps automation" \
  "$perps_engine_contract" \
  "automation_state" \
  null \
  "$perps_automation_expected_json" \
  "sync_automation" \
  "$(jq -cn --arg executor "$SORASWAP_AUTHORITY" '{ executor: $executor, funding_job_id: "201", liquidation_job_id: "202", cadence_slots: "4", backlog_cap: "6", safe_mode: "0" }')"
ensure_step_from_prior_or_skip_with_live_predicate \
  "perps market registration" \
  "$perps_engine_contract" \
  "market_state" \
  '{"market_id":"1"}' \
  '[0,0,0,0,0,0,0,0,0,0,0,0,0]' \
  "$perps_market_expected_json" \
  "register_market" \
  "$(jq -cn \
    --arg asset "$xor_id" \
    --arg max_leverage_bps "$perps_max_leverage_bps" \
    --arg maintenance_margin_bps "$perps_maintenance_margin_bps" \
    --arg liquidation_fee_bps "$perps_liquidation_fee_bps" \
    --arg open_interest_cap "$perps_open_interest_cap" \
    --arg funding_bps "$perps_funding_bps" \
    --arg funding_interval_slots "$perps_funding_interval_slots" \
    --arg oracle_stale_slots "$perps_oracle_stale_slots" \
    --arg backlog_limit "$perps_backlog_limit" \
    --arg utilisation_clamp_bps "$perps_utilisation_clamp_bps" \
    --arg liquidation_stress_limit "$perps_liquidation_stress_limit" \
    '{
      asset: $asset,
      max_leverage_bps: $max_leverage_bps,
      maintenance_margin_bps: $maintenance_margin_bps,
      liquidation_fee_bps: $liquidation_fee_bps,
      open_interest_cap: $open_interest_cap,
      funding_bps: $funding_bps,
      funding_interval_slots: $funding_interval_slots,
      oracle_stale_slots: $oracle_stale_slots,
      backlog_limit: $backlog_limit,
      utilisation_clamp_bps: $utilisation_clamp_bps,
      liquidation_stress_limit: $liquidation_stress_limit
    }')" \
  '$actual[0] == $expected[0]
   and $actual[1] == $expected[1]
   and (($actual[2] // 0) >= 0)
   and (($actual[3] // 0) == ($expected[3] // 0))
   and (($actual[4] // 0) == ($expected[4] // 0))
   and (($actual[5] // 0) == ($expected[5] // 0))
   and (($actual[6] // 0) == ($expected[6] // 0))
   and (($actual[7] // 0) == ($expected[7] // 0))
   and (($actual[8] // 0) == ($expected[8] // 0))
   and (($actual[9] // 0) == ($expected[9] // 0))
   and (($actual[10] // 0) >= 0)
   and (($actual[11] // 0) >= 0)
   and (($actual[12] // 0) == ($expected[12] // 0))'
ensure_perps_collateral_pool_funded
exit_perps_withdrawal_only
assert_perps_collateral_pool_invariants
trigger_lifecycle_predicate='
  $actual[0] == $expected[0]
  and $actual[1] == $expected[1]
  and $actual[2] == $expected[2]
  and (($actual[3] // 0) >= 0)
  and (($actual[4] // 0) >= 0)
  and (($actual[5] // 0) >= 0)
  and (($actual[6] // 0) >= 0)
'
perps_trigger_lifecycle_expected_json="$(jq -cn \
  --argjson enabled "$trigger_lifecycle_enabled" \
  --argjson cadence_slots "$trigger_lifecycle_cadence_slots" \
  --argjson max_items "$perps_trigger_lifecycle_max_items" \
  '[ $enabled, $cadence_slots, $max_items, 0, 0, 0, 0 ]')"
ensure_view_predicate_or_apply \
  "perps trigger lifecycle" \
  "$perps_engine_contract" \
  "trigger_lifecycle_state" \
  null \
  "$perps_trigger_lifecycle_expected_json" \
  "configure_trigger_lifecycle" \
  "$(jq -cn \
    --arg cadence_slots "$trigger_lifecycle_cadence_slots" \
    --arg max_items_per_tick "$perps_trigger_lifecycle_max_items" \
    --arg enabled "$trigger_lifecycle_enabled" \
    '{ cadence_slots: $cadence_slots, max_items_per_tick: $max_items_per_tick, enabled: $enabled }')" \
  "$trigger_lifecycle_predicate"

options_factory_init_expected_json="$(jq -cn \
  --arg settlement_asset "$usdt_id" \
  --arg factory_account "$options_factory_contract_subject" \
  --arg oracle_authority "$SORASWAP_ACTIVE_ORACLE_ACCOUNT" \
  '[ $settlement_asset, $factory_account, $oracle_authority, 1, 1, 0, 0, 0, 0 ]')"
options_factory_live_expected_json="$(jq -cn \
  --arg settlement_asset "$usdt_id" \
  --arg factory_account "$options_factory_contract_subject" \
  --arg oracle_authority "$SORASWAP_ACTIVE_ORACLE_ACCOUNT" \
  '[ $settlement_asset, $factory_account, $oracle_authority, 0, 1, 0, 0, 0, 0 ]')"
ensure_init_or_skip_with_live_predicate \
  "options factory config" \
  "$options_factory_contract" \
  "factory_config" \
  null \
  "$options_factory_init_expected_json" \
  "hajimari" \
  "$(jq -cn \
    --arg settlement_asset "$usdt_id" \
    --arg factory_account "$options_factory_contract_subject" \
    --arg guardian "$vault_account" \
    --arg oracle_authority "$SORASWAP_ACTIVE_ORACLE_ACCOUNT" \
    --arg stale_slots "$options_oracle_stale_slots" \
    '{
      settlement_asset: $settlement_asset,
      factory_account: $factory_account,
      guardian: $guardian,
      oracle_authority: $oracle_authority,
      stale_slots: $stale_slots
    }')" \
  '$actual[0] == $expected[0]
   and $actual[1] == $expected[1]
   and $actual[2] == $expected[2]
   and (($actual[4] // 0) >= ($expected[4] // 0))'
apply_step_and_expect \
  "options factory oracle stale slots" \
  "$options_factory_contract" \
  "oracle_stale_slots" \
  null \
  "$(jq -cn --argjson oracle_stale_slots "$options_oracle_stale_slots" '$oracle_stale_slots')" \
  "configure_oracle_stale_slots" \
  "$(jq -cn --arg stale_slots "$options_oracle_stale_slots" '{ stale_slots: $stale_slots }')"
ensure_step_from_prior_or_skip_with_live_predicate \
  "options factory exit withdrawal only" \
  "$options_factory_contract" \
  "factory_config" \
  null \
  "$options_factory_init_expected_json" \
  "$options_factory_live_expected_json" \
  "exit_withdrawal_only" \
  null \
  '$actual[0] == $expected[0]
   and $actual[1] == $expected[1]
   and $actual[2] == $expected[2]
   and ($actual[3] // 1) == 0
   and (($actual[4] // 0) >= ($expected[4] // 0))
   and (($actual[5] // 0) >= ($expected[5] // 0))
   and (($actual[6] // 0) >= ($expected[6] // 0))
   and (($actual[7] // 0) >= ($expected[7] // 0))
   and (($actual[8] // 0) >= ($expected[8] // 0))'
apply_step_and_expect \
  "options factory automation" \
  "$options_factory_contract" \
  "automation_state" \
  null \
  '[1,213,5,8,0,0,0]' \
  "sync_automation" \
  "$(jq -cn --arg executor "$SORASWAP_AUTHORITY" '{ executor: $executor, job_id: "213", cadence_slots: "5", backlog_cap: "8", safe_mode: "0" }')"
echo "bootstrap apply: options factory heartbeat"
if [[ "$mode" == "local" ]]; then
  call_contract_and_wait \
    "$config" \
    "$options_factory_contract" \
    "heartbeat" \
    '{"current_backlog":"0","safe_mode":"0"}' \
    >/dev/null
else
  if ! call_contract_and_wait \
    "$config" \
    "$options_factory_contract" \
    "heartbeat" \
      '{"current_backlog":"0","safe_mode":"0"}' \
    >/dev/null 2>&1; then
    echo "bootstrap note: options factory heartbeat returned a non-fatal public-chain error; continuing" >&2
  fi
fi

ensure_step_from_prior_or_skip_with_live_predicate \
  "options factory shout series sync" \
  "$options_factory_contract" \
  "series_state" \
  '{"series_id":"1"}' \
  '[0,0,0,0,0,0,0,0,0,0]' \
  "$(jq -cn --argjson max_notional "$options_shout_max_notional" --argjson premium_bps "$options_shout_base_premium_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" '[ 1, 1, $max_notional, $premium_bps, $collateral_multiplier_bps, 0, 0, 0, 0, 0 ]')" \
  "sync_series" \
  "$(jq -cn --arg series_id 1 --arg option_kind 1 --arg max_notional "$options_shout_max_notional" --arg premium_bps "$options_shout_base_premium_bps" --arg strike_bps "$options_shout_strike_bps" --arg collateral_multiplier_bps "$options_collateral_multiplier_bps" --arg expiry_slot "$options_shout_expiry_slot" '{ series_id: $series_id, option_kind: $option_kind, max_notional: $max_notional, premium_bps: $premium_bps, strike_bps: $strike_bps, collateral_multiplier_bps: $collateral_multiplier_bps, expiry_slot: $expiry_slot }')" \
  '$actual[0] == $expected[0]
   and $actual[1] == $expected[1]
   and $actual[2] == $expected[2]
   and $actual[3] == $expected[3]
   and $actual[4] == $expected[4]
   and (($actual[5] // 0) >= ($expected[5] // 0))
   and (($actual[6] // 0) >= ($expected[6] // 0))
   and (($actual[7] // 0) >= ($expected[7] // 0))
   and (($actual[8] // 0) >= ($expected[8] // 0))
   and (($actual[9] // 0) >= ($expected[9] // 0))'
options_factory_guard_live_predicate='
  $actual[0] == $expected[0]
  and $actual[1] == $expected[1]
  and $actual[2] == $expected[2]
  and $actual[3] == $expected[3]
  and $actual[4] == $expected[4]
  and (($actual[5] // 0) >= ($expected[5] // 0))
  and (($actual[6] // 0) >= ($expected[6] // 0))
  and (($actual[7] // 0) == ($expected[7] // 0))
  and (($actual[8] // 0) == ($expected[8] // 0))
  and (($actual[9] // 0) >= ($expected[9] // 0))
'
ensure_step_from_prior_or_skip_with_live_predicate \
  "options factory shout guard" \
  "$options_factory_contract" \
  "series_state" \
  '{"series_id":"1"}' \
  "$(jq -cn --argjson max_notional "$options_shout_max_notional" --argjson premium_bps "$options_shout_base_premium_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" '[ 1, 1, $max_notional, $premium_bps, $collateral_multiplier_bps, 0, 0, 0, 0, 0 ]')" \
  "$(jq -cn --argjson max_notional "$options_shout_max_notional" --argjson premium_bps "$options_shout_base_premium_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" --argjson pause_threshold_bps "$options_factory_pause_threshold_bps" --argjson bump_percent_bps "$options_factory_bump_percent_bps" '[ 1, 1, $max_notional, $premium_bps, $collateral_multiplier_bps, 0, 0, $pause_threshold_bps, $bump_percent_bps, 0 ]')" \
  "configure_utilisation_guard" \
  "$(jq -cn --arg series_id 1 --arg bump_activate_bps "$options_factory_bump_activate_bps" --arg bump_deactivate_bps "$options_factory_bump_deactivate_bps" --arg pause_threshold_bps "$options_factory_pause_threshold_bps" --arg bump_percent_bps "$options_factory_bump_percent_bps" '{ series_id: $series_id, bump_activate_bps: $bump_activate_bps, bump_deactivate_bps: $bump_deactivate_bps, pause_threshold_bps: $pause_threshold_bps, bump_percent_bps: $bump_percent_bps }')" \
  "$options_factory_guard_live_predicate"
ensure_step_from_prior_or_skip_with_live_predicate \
  "options factory outperformance series sync" \
  "$options_factory_contract" \
  "series_state" \
  '{"series_id":"2"}' \
  '[0,0,0,0,0,0,0,0,0,0]' \
  "$(jq -cn --argjson max_notional "$options_outperformance_max_notional" --argjson premium_bps "$options_outperformance_base_premium_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" '[ 1, 2, $max_notional, $premium_bps, $collateral_multiplier_bps, 0, 0, 0, 0, 0 ]')" \
  "sync_series" \
  "$(jq -cn --arg series_id 2 --arg option_kind 2 --arg max_notional "$options_outperformance_max_notional" --arg premium_bps "$options_outperformance_base_premium_bps" --arg strike_bps "$options_outperformance_strike_bps" --arg collateral_multiplier_bps "$options_collateral_multiplier_bps" --arg expiry_slot "$options_outperformance_expiry_slot" '{ series_id: $series_id, option_kind: $option_kind, max_notional: $max_notional, premium_bps: $premium_bps, strike_bps: $strike_bps, collateral_multiplier_bps: $collateral_multiplier_bps, expiry_slot: $expiry_slot }')" \
  '$actual[0] == $expected[0]
   and $actual[1] == $expected[1]
   and $actual[2] == $expected[2]
   and $actual[3] == $expected[3]
   and $actual[4] == $expected[4]
   and (($actual[5] // 0) >= ($expected[5] // 0))
   and (($actual[6] // 0) >= ($expected[6] // 0))
   and (($actual[7] // 0) >= ($expected[7] // 0))
   and (($actual[8] // 0) >= ($expected[8] // 0))
   and (($actual[9] // 0) >= ($expected[9] // 0))'
ensure_step_from_prior_or_skip_with_live_predicate \
  "options factory outperformance guard" \
  "$options_factory_contract" \
  "series_state" \
  '{"series_id":"2"}' \
  "$(jq -cn --argjson max_notional "$options_outperformance_max_notional" --argjson premium_bps "$options_outperformance_base_premium_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" '[ 1, 2, $max_notional, $premium_bps, $collateral_multiplier_bps, 0, 0, 0, 0, 0 ]')" \
  "$(jq -cn --argjson max_notional "$options_outperformance_max_notional" --argjson premium_bps "$options_outperformance_base_premium_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" --argjson pause_threshold_bps "$options_factory_pause_threshold_bps" --argjson bump_percent_bps "$options_factory_bump_percent_bps" '[ 1, 2, $max_notional, $premium_bps, $collateral_multiplier_bps, 0, 0, $pause_threshold_bps, $bump_percent_bps, 0 ]')" \
  "configure_utilisation_guard" \
  "$(jq -cn --arg series_id 2 --arg bump_activate_bps "$options_factory_bump_activate_bps" --arg bump_deactivate_bps "$options_factory_bump_deactivate_bps" --arg pause_threshold_bps "$options_factory_pause_threshold_bps" --arg bump_percent_bps "$options_factory_bump_percent_bps" '{ series_id: $series_id, bump_activate_bps: $bump_activate_bps, bump_deactivate_bps: $bump_deactivate_bps, pause_threshold_bps: $pause_threshold_bps, bump_percent_bps: $bump_percent_bps }')" \
  "$options_factory_guard_live_predicate"

product_trigger_lifecycle_expected_json="$(jq -cn \
  --argjson enabled "$trigger_lifecycle_enabled" \
  --argjson cadence_slots "$trigger_lifecycle_cadence_slots" \
  --argjson max_items "$trigger_lifecycle_max_items" \
  '[ $enabled, $cadence_slots, $max_items, 0, 0, 0, 0 ]')"
ensure_view_predicate_or_apply \
  "options factory trigger lifecycle" \
  "$options_factory_contract" \
  "trigger_lifecycle_state" \
  null \
  "$product_trigger_lifecycle_expected_json" \
  "configure_trigger_lifecycle" \
  "$(jq -cn \
    --arg cadence_slots "$trigger_lifecycle_cadence_slots" \
    --arg max_items_per_tick "$trigger_lifecycle_max_items" \
    --arg enabled "$trigger_lifecycle_enabled" \
    '{ cadence_slots: $cadence_slots, max_items_per_tick: $max_items_per_tick, enabled: $enabled }')" \
  "$trigger_lifecycle_predicate"

cover_manager_init_json="$(jq -cn \
  --arg settlement_asset "$usdt_id" \
  --arg cover_account "$cover_policy_manager_contract_subject" \
  --arg oracle_authority "$SORASWAP_ACTIVE_ORACLE_ACCOUNT" \
  --argjson required_observations "$cover_required_observations" \
  --argjson oracle_stale_slots "$cover_oracle_stale_slots" \
  '[ $settlement_asset, $cover_account, $oracle_authority, 1, $required_observations, 0, 0, 0, $oracle_stale_slots ]')"
cover_manager_live_json="$(jq -cn \
  --arg settlement_asset "$usdt_id" \
  --arg cover_account "$cover_policy_manager_contract_subject" \
  --arg oracle_authority "$SORASWAP_ACTIVE_ORACLE_ACCOUNT" \
  --argjson required_observations "$cover_required_observations" \
  --argjson oracle_stale_slots "$cover_oracle_stale_slots" \
  '[ $settlement_asset, $cover_account, $oracle_authority, 0, $required_observations, 0, 0, 0, $oracle_stale_slots ]')"
cover_automation_expected_json='[1,301,3,10,0,0,0]'
sync_cover_manager_oracle_stale_slots() {
  ensure_view_predicate_or_apply \
    "cover manager oracle stale slots" \
    "$cover_policy_manager_contract" \
    "manager_config" \
    null \
    "$cover_manager_live_json" \
    "configure_oracle_stale_slots" \
    "$(jq -cn --arg stale_slots "$cover_oracle_stale_slots" '{ stale_slots: $stale_slots }')" \
    '$actual[0] == $expected[0]
     and $actual[1] == $expected[1]
     and $actual[2] == $expected[2]
     and $actual[3] == $expected[3]
     and $actual[4] == $expected[4]
     and (($actual[5] // 0) >= ($expected[5] // 0))
     and (($actual[6] // 0) >= ($expected[6] // 0))
     and (($actual[7] // 0) >= ($expected[7] // 0))
     and (($actual[8] // 0) >= ($expected[8] // 0))'
}
ensure_init_or_skip_with_live_predicate \
  "cover manager config" \
  "$cover_policy_manager_contract" \
  "manager_config" \
  null \
  "$cover_manager_init_json" \
  "hajimari" \
  "$(jq -cn \
    --arg settlement_asset "$usdt_id" \
    --arg cover_account "$cover_policy_manager_contract_subject" \
    --arg guardian "$vault_account" \
    --arg oracle_authority "$SORASWAP_ACTIVE_ORACLE_ACCOUNT" \
    --arg default_required_observations "$cover_required_observations" \
    --arg oracle_stale_slots "$cover_oracle_stale_slots" \
    '{
      settlement_asset: $settlement_asset,
      cover_account: $cover_account,
      guardian: $guardian,
      oracle_authority: $oracle_authority,
      default_required_observations: $default_required_observations,
      oracle_stale_slots: $oracle_stale_slots
    }')" \
  '$actual[0] == $expected[0]
   and $actual[1] == $expected[1]
   and $actual[2] == $expected[2]
   and $actual[4] == $expected[4]'
sync_cover_manager_oracle_stale_slots
ensure_step_from_prior_or_skip_with_live_predicate \
  "cover manager exit withdrawal only" \
  "$cover_policy_manager_contract" \
  "manager_config" \
  null \
  "$cover_manager_init_json" \
  "$cover_manager_live_json" \
  "exit_withdrawal_only" \
  null \
  '$actual[0] == $expected[0]
   and $actual[1] == $expected[1]
   and $actual[2] == $expected[2]
   and ($actual[3] // 1) == 0
   and $actual[4] == $expected[4]
   and (($actual[5] // 0) >= ($expected[5] // 0))
   and (($actual[6] // 0) >= ($expected[6] // 0))
   and (($actual[7] // 0) >= ($expected[7] // 0))
   and (($actual[8] // 0) >= ($expected[8] // 0))'
apply_step_and_expect \
  "cover automation" \
  "$cover_policy_manager_contract" \
  "automation_state" \
  null \
  "$cover_automation_expected_json" \
  "sync_automation" \
  "$(jq -cn --arg executor "$SORASWAP_AUTHORITY" '{ executor: $executor, job_id: "301", cadence_slots: "3", backlog_cap: "10", safe_mode: "0" }')"
echo "bootstrap apply: cover heartbeat"
if [[ "$mode" == "local" ]]; then
  call_contract_and_wait \
    "$config" \
    "$cover_policy_manager_contract" \
    "heartbeat" \
    '{"current_backlog":"0","safe_mode":"0"}' \
    >/dev/null
else
  if ! call_contract_and_wait \
    "$config" \
    "$cover_policy_manager_contract" \
    "heartbeat" \
      '{"current_backlog":"0","safe_mode":"0"}' \
    >/dev/null 2>&1; then
    echo "bootstrap note: cover heartbeat returned a non-fatal public-chain error; continuing" >&2
  fi
fi
ensure_view_predicate_or_apply \
  "cover trigger lifecycle" \
  "$cover_policy_manager_contract" \
  "trigger_lifecycle_state" \
  null \
  "$product_trigger_lifecycle_expected_json" \
  "configure_trigger_lifecycle" \
  "$(jq -cn \
    --arg cadence_slots "$trigger_lifecycle_cadence_slots" \
    --arg max_items_per_tick "$trigger_lifecycle_max_items" \
    --arg enabled "$trigger_lifecycle_enabled" \
    '{ cadence_slots: $cadence_slots, max_items_per_tick: $max_items_per_tick, enabled: $enabled }')" \
  "$trigger_lifecycle_predicate"

if [[ -n "$sccp_bridge_contract" ]]; then
  bridge_registry_requires_governed=0
  if [[ "$mode" == "testnet" || "$mode" == "production" ]]; then
    bridge_registry_requires_governed=1
  fi
  bridge_listing_expected_json="$(jq -cn \
    --arg listing_fee_asset "$xor_id" \
    --arg treasury "$vault_account" \
    --argjson listing_fee_amount "$bridge_listing_fee_amount" \
    '[ $listing_fee_asset, $treasury, $listing_fee_amount, 1 ]')"
  bridge_listing_init_payload="$(jq -cn \
    --arg listing_fee_asset "$xor_id" \
    --arg treasury "$vault_account" \
    --arg proof_authority "$bridge_proof_authority" \
    --arg guardian "$launchpad_guardian_account" \
    --arg listing_fee_amount "$bridge_listing_fee_amount" \
    '{
      listing_fee_asset: $listing_fee_asset,
      treasury: $treasury,
      listing_fee_amount: $listing_fee_amount,
      proof_authority: $proof_authority,
      guardian: $guardian
    }')"
  ensure_init_or_skip \
    "bridge listing config" \
    "$sccp_bridge_contract" \
    "listing_config" \
    null \
    "$bridge_listing_expected_json" \
    "hajimari" \
    "$bridge_listing_init_payload"

  bridge_authorities_expected_json="$(jq -cn \
    --arg owner "$SORASWAP_AUTHORITY" \
    --arg proof_authority "$bridge_proof_authority" \
    --arg guardian "$launchpad_guardian_account" \
    '[ $owner, $proof_authority, $guardian ]')"
  actual_json="$(view_result_json "$sccp_bridge_contract" "bridge_authorities" null 2>/dev/null || true)"
  if json_value_present "$actual_json" && json_equals "$actual_json" "$bridge_authorities_expected_json"; then
    echo "bootstrap skip: bridge authorities already match expected state"
  else
    echo "bootstrap apply: bridge proof authority"
    call_contract_and_wait \
      "$config" \
      "$sccp_bridge_contract" \
      "set_proof_authority" \
      "$(jq -cn --arg proof_authority "$bridge_proof_authority" '{ proof_authority: $proof_authority }')" \
      >/dev/null
    actual_json="$(view_result_json "$sccp_bridge_contract" "bridge_authorities" null)"
    if ! json_equals "$actual_json" "$bridge_authorities_expected_json"; then
      fail_bootstrap_diff "bridge authorities" "$bridge_authorities_expected_json" "$actual_json"
    fi
  fi

  bridge_asset_view_payload="$(jq -cn --arg asset_key "$bridge_asset_key" '{asset_key: $asset_key}')"
  bridge_asset_mirror_prior_json='[0,0,0,0]'
  bridge_asset_mirror_expected_json="$(jq -cn \
    --argjson home_domain "$bridge_asset_home_domain" \
    --argjson decimals "$bridge_asset_decimals" \
    --argjson listing_paid "$bridge_listing_fee_amount" \
    '[ 1, $home_domain, $decimals, $listing_paid ]')"
  bridge_asset_config_expected_json="$(jq -cn \
    --arg asset "$bridge_local_asset" \
    --arg registrant "$SORASWAP_AUTHORITY" \
    --argjson home_domain "$bridge_asset_home_domain" \
    --argjson decimals "$bridge_asset_decimals" \
    '[ $asset, $registrant, $home_domain, $decimals ]')"
  bridge_asset_register_payload="$(jq -cn \
    --arg asset_key "$bridge_asset_key" \
    --arg asset "$bridge_local_asset" \
    --arg home_domain "$bridge_asset_home_domain" \
    --arg decimals "$bridge_asset_decimals" \
    '{
      asset_key: $asset_key,
      asset: $asset,
      home_domain: $home_domain,
      decimals: $decimals
    }')"
  ensure_step_from_prior_or_skip \
    "bridge asset registration" \
    "$sccp_bridge_contract" \
    "mirror_asset" \
    "$bridge_asset_view_payload" \
    "$bridge_asset_mirror_prior_json" \
    "$bridge_asset_mirror_expected_json" \
    "register_bridge_asset" \
    "$bridge_asset_register_payload"
  bridge_asset_actual_json="$(view_result_json "$sccp_bridge_contract" "asset_config" "$bridge_asset_view_payload")"
  if ! json_equals "$bridge_asset_actual_json" "$bridge_asset_config_expected_json"; then
    fail_bootstrap_diff "bridge asset config" "$bridge_asset_config_expected_json" "$bridge_asset_actual_json"
  fi

  bridge_asset_vault_bound_expected_json='1'
  bridge_asset_vault_account_expected_json="$(jq -cn --arg vault_account "$vault_account" '$vault_account')"
  bridge_asset_vault_bind_payload="$(jq -cn \
    --arg asset_key "$bridge_asset_key" \
    --arg vault_account "$vault_account" \
    '{
      asset_key: $asset_key,
      vault_account: $vault_account
    }')"
  ensure_step_from_prior_or_skip \
    "bridge asset vault binding" \
    "$sccp_bridge_contract" \
    "asset_vault_bound" \
    "$bridge_asset_view_payload" \
    '0' \
    "$bridge_asset_vault_bound_expected_json" \
    "bind_asset_vault" \
    "$bridge_asset_vault_bind_payload"
  bridge_asset_actual_json="$(view_result_json "$sccp_bridge_contract" "asset_vault_account" "$bridge_asset_view_payload")"
  if ! json_equals "$bridge_asset_actual_json" "$bridge_asset_vault_account_expected_json"; then
    fail_bootstrap_diff "bridge asset vault account" "$bridge_asset_vault_account_expected_json" "$bridge_asset_actual_json"
  fi

  bridge_route_view_payload="$(jq -cn --arg route "$bridge_route" '{route: $route}')"
  bridge_route_mirror_prior_json='[0,0,0,0]'
  bridge_route_mirror_expected_json="$(jq -cn \
    --argjson remote_domain "$bridge_remote_domain" \
    '[ 1, $remote_domain, 1, 1 ]')"
  bridge_route_live_predicate='
    $actual[0] == 1
    and $actual[1] == $expected[1]
    and $actual[2] == 1
    and (($actual[3] // 0) >= 1)'
  bridge_route_config_expected_json="$(jq -cn \
    --arg asset_key "$bridge_asset_key" \
    --arg asset "$bridge_local_asset" \
    --arg vault_account "$vault_account" \
    --argjson remote_domain "$bridge_remote_domain" \
    '[ $asset_key, $remote_domain, $asset, $vault_account ]')"
  bridge_route_activate_payload="$(jq -cn \
    --arg route "$bridge_route" \
    --arg asset_key "$bridge_asset_key" \
    --arg remote_domain "$bridge_remote_domain" \
    '{
      route: $route,
      asset_key: $asset_key,
      remote_domain: $remote_domain
    }')"
  bridge_route_activate_governed_payload="$(jq -cn \
    --arg message_id "${SORASWAP_BRIDGE_GOVERNANCE_MESSAGE_ID:-bridge_bootstrap_route}" \
    --arg route "$bridge_route" \
    --arg asset_key "$bridge_asset_key" \
    --arg remote_domain "$bridge_remote_domain" \
    '{
      message_id: $message_id,
      route: $route,
      asset_key: $asset_key,
      remote_domain: $remote_domain
    }')"
  if (( bridge_registry_requires_governed == 1 )); then
    ensure_step_from_prior_or_skip_with_live_predicate \
      "bridge route activation" \
      "$sccp_bridge_contract" \
      "mirror_route" \
      "$bridge_route_view_payload" \
      "$bridge_route_mirror_prior_json" \
      "$bridge_route_mirror_expected_json" \
      "activate_route_governed" \
      "$bridge_route_activate_governed_payload" \
      "$bridge_route_live_predicate"
    bridge_route_actual_json="$(view_result_json "$sccp_bridge_contract" "route_config" "$bridge_route_view_payload")"
    if ! json_equals "$bridge_route_actual_json" "$bridge_route_config_expected_json"; then
      fail_bootstrap_diff "bridge route config" "$bridge_route_config_expected_json" "$bridge_route_actual_json"
    fi
    bridge_route_actual_json="$(view_result_json "$sccp_bridge_contract" "route_provenance" "$bridge_route_view_payload")"
    if ! jq -en \
      --argjson actual "$bridge_route_actual_json" \
      '($actual[0] // 0) == 1 and (($actual[1] | type) == "string") and (($actual[1] | length) > 0)' \
      >/dev/null; then
      fail_bootstrap_diff \
        "bridge route provenance" \
        '{"governed":1,"message_id":"<non-empty>"}' \
        "$bridge_route_actual_json"
    fi
  else
    ensure_step_from_prior_or_skip \
      "bridge route activation" \
      "$sccp_bridge_contract" \
      "mirror_route" \
      "$bridge_route_view_payload" \
      "$bridge_route_mirror_prior_json" \
      "$bridge_route_mirror_expected_json" \
      "activate_route" \
      "$bridge_route_activate_payload"
  fi
fi

launch_vault_view_payload="$(jq -cn --arg vault_id "$soraswap_launch_vault_id" '{vault_id: $vault_id}')"
ensure_step_from_prior_or_skip \
  "soraswap launch vault" \
  "$vaults_manager_contract" \
  "vault_state" \
  "$launch_vault_view_payload" \
  '[0,0,0,0,0]' \
  "$(jq -cn --argjson strategy "$soraswap_launch_vault_strategy_code" --argjson async_redeem "$soraswap_launch_vault_async_redeem" '[1,$strategy,$async_redeem,0,0]')" \
  "register_vault" \
  "$(jq -cn \
    --arg vault_id "$soraswap_launch_vault_id" \
    --arg underlying_asset "$n3x_id" \
    --arg share_asset "$n3x_id" \
    --arg custody_account "$vaults_manager_contract_subject" \
    --arg strategy_code "$soraswap_launch_vault_strategy_code" \
    --arg async_redeem "$soraswap_launch_vault_async_redeem" \
    '{vault_id:$vault_id, underlying_asset:$underlying_asset, share_asset:$share_asset, custody_account:$custody_account, strategy_code:$strategy_code, async_redeem:$async_redeem}')"
ensure_view_predicate_or_apply \
  "vaults trigger lifecycle" \
  "$vaults_manager_contract" \
  "trigger_lifecycle_state" \
  null \
  "$product_trigger_lifecycle_expected_json" \
  "configure_trigger_lifecycle" \
  "$(jq -cn \
    --arg cadence_slots "$trigger_lifecycle_cadence_slots" \
    --arg max_items_per_tick "$trigger_lifecycle_max_items" \
    --arg enabled "$trigger_lifecycle_enabled" \
    '{ cadence_slots: $cadence_slots, max_items_per_tick: $max_items_per_tick, enabled: $enabled }')" \
  "$trigger_lifecycle_predicate"

launch_operator_view_payload="$(jq -cn --arg service "$soraswap_launch_operator_service" '{service: $service}')"
launch_operator_registered_json="$(jq -cn --argjson min_bond "$soraswap_launch_operator_min_bond" '[1,$min_bond,0,10000,0,0,0]')"
launch_operator_bonded_json="$(jq -cn --argjson min_bond "$soraswap_launch_operator_min_bond" --argjson bonded "$soraswap_launch_operator_bond" '[1,$min_bond,$bonded,10000,0,0,0]')"
launch_operator_heartbeat_json="$(jq -cn --argjson min_bond "$soraswap_launch_operator_min_bond" --argjson bonded "$soraswap_launch_operator_bond" --argjson slot "$soraswap_launch_operator_heartbeat_slot" --argjson health "$soraswap_launch_operator_health_bps" '[1,$min_bond,$bonded,$health,$slot,0,0]')"
ensure_step_from_prior_or_skip_with_live_predicate \
  "soraswap launch operator registration" \
  "$operators_registry_contract" \
  "operator_state" \
  "$launch_operator_view_payload" \
  '[0,0,0,0,0,0,0]' \
  "$launch_operator_registered_json" \
  "register_operator" \
  "$(jq -cn \
    --arg service "$soraswap_launch_operator_service" \
    --arg operator_owner "$SORASWAP_AUTHORITY" \
    --arg bond_asset "$xor_id" \
    --arg bond_vault "$operators_registry_contract_subject" \
    --arg fee_asset "$xor_id" \
    --arg fee_vault "$operators_registry_contract_subject" \
    --arg min_bond "$soraswap_launch_operator_min_bond" \
    '{service:$service, operator_owner:$operator_owner, bond_asset:$bond_asset, bond_vault:$bond_vault, fee_asset:$fee_asset, fee_vault:$fee_vault, min_bond:$min_bond}')" \
  '$actual[0] == $expected[0]
   and $actual[1] == $expected[1]
   and (($actual[2] // 0) >= 0)
   and (($actual[3] // 0) >= 0)
   and (($actual[4] // 0) >= 0)
   and (($actual[5] // 0) >= 0)
   and (($actual[6] // 0) == 0)' \
  1
ensure_step_from_prior_or_skip_with_live_predicate \
  "soraswap launch operator bond" \
  "$operators_registry_contract" \
  "operator_state" \
  "$launch_operator_view_payload" \
  "$launch_operator_registered_json" \
  "$launch_operator_bonded_json" \
  "bond" \
  "$(jq -cn --arg service "$soraswap_launch_operator_service" --arg amount "$soraswap_launch_operator_bond" '{service:$service, amount:$amount}')" \
  '$actual[0] == $expected[0]
   and $actual[1] == $expected[1]
   and (($actual[2] // 0) >= ($expected[2] // 0))
   and (($actual[3] // 0) >= 0)
   and (($actual[4] // 0) >= 0)
   and (($actual[5] // 0) >= 0)
   and (($actual[6] // 0) == 0)'
ensure_step_from_prior_or_skip \
  "soraswap launch operator heartbeat" \
  "$operators_registry_contract" \
  "operator_state" \
  "$launch_operator_view_payload" \
  "$launch_operator_bonded_json" \
  "$launch_operator_heartbeat_json" \
  "heartbeat" \
  "$(jq -cn --arg service "$soraswap_launch_operator_service" --arg slot "$soraswap_launch_operator_heartbeat_slot" --arg health_bps "$soraswap_launch_operator_health_bps" '{service:$service, slot:$slot, health_bps:$health_bps}')"

launch_margin_view_payload="$(jq -cn --arg market_id "$soraswap_launch_margin_market_id" '{market_id: $market_id}')"
ensure_step_from_prior_or_skip \
  "soraswap launch margin market" \
  "$margin_portfolio_margin_contract" \
  "market_state" \
  "$launch_margin_view_payload" \
  '[0,0,0]' \
  "$(jq -cn --argjson risk "$soraswap_launch_margin_risk_weight_bps" --argjson threshold "$soraswap_launch_margin_liquidation_threshold_bps" '[1,$risk,$threshold]')" \
  "register_market" \
  "$(jq -cn \
    --arg market_id "$soraswap_launch_margin_market_id" \
    --arg collateral_asset "$usdt_id" \
    --arg collateral_vault "$margin_portfolio_margin_contract_subject" \
    --arg risk_weight_bps "$soraswap_launch_margin_risk_weight_bps" \
    --arg liquidation_threshold_bps "$soraswap_launch_margin_liquidation_threshold_bps" \
    '{market_id:$market_id, collateral_asset:$collateral_asset, collateral_vault:$collateral_vault, risk_weight_bps:$risk_weight_bps, liquidation_threshold_bps:$liquidation_threshold_bps}')"

launch_rwa_view_payload="$(jq -cn --arg market_id "$soraswap_launch_rwa_market_id" '{market_id: $market_id}')"
if [[ "$rwa_release_enabled" == "1" ]]; then
  ensure_step_from_prior_or_skip \
    "soraswap launch rwa market" \
    "$rwa_market_contract" \
    "rwa_market_state" \
    "$launch_rwa_view_payload" \
    '[0,0,0,0]' \
    "$(jq -cn --argjson nav "$soraswap_launch_rwa_nav" --argjson shares "$soraswap_launch_rwa_shares" '[1,$nav,$shares,1]')" \
    "issue_lot" \
    "$(jq -cn --arg market_id "$soraswap_launch_rwa_market_id" --arg share_asset "$n3x_id" --arg nav_asset "$usdt_id" --arg initial_nav_per_share "$soraswap_launch_rwa_nav" --arg total_shares "$soraswap_launch_rwa_shares" '{market_id:$market_id, share_asset:$share_asset, nav_asset:$nav_asset, initial_nav_per_share:$initial_nav_per_share, total_shares:$total_shares}')"
else
  echo "skipping public RWA market bootstrap; set SORASWAP_ENABLE_RWA_RELEASE=1 only for an explicit RWA launch"
fi

ensure_view_predicate_or_apply \
  "dlmm hook manager init" \
  "$dlmm_hooks_manager_contract" \
  "main" \
  null \
  '1' \
  "hajimari" \
  "$(jq -cn \
    --arg base_asset "$xor_id" \
    --arg quote_asset "$usdt_id" \
    --arg custody_account "$dlmm_hooks_manager_contract_subject" \
    --arg router_contract "$dlmm_router_contract_blob_hex" \
    --arg guardian "$launchpad_guardian_account" \
    '{base_asset:$base_asset, quote_asset:$quote_asset, custody_account:$custody_account, router_contract:$router_contract, guardian:$guardian}')" \
  '($actual == $expected)'
echo "bootstrap apply: dlmm hook manager exit withdrawal only"
call_contract_and_wait \
  "$config" \
  "$dlmm_hooks_manager_contract" \
  "exit_withdrawal_only" \
  null \
  >/dev/null
twamm_expected_json="$(jq -cn \
  --argjson enabled "$twamm_trigger_enabled" \
  --argjson cadence_slots "$twamm_trigger_cadence_slots" \
  --argjson max_orders_per_tick "$twamm_trigger_max_orders_per_tick" \
  '[ $enabled, $cadence_slots, $max_orders_per_tick, 1, 0, 0, 0 ]')"
ensure_view_predicate_or_apply \
  "dlmm hook manager trigger twamm" \
  "$dlmm_hooks_manager_contract" \
  "twamm_trigger_state" \
  null \
  "$twamm_expected_json" \
  "configure_trigger_twamm" \
  "$(jq -cn \
    --arg cadence_slots "$twamm_trigger_cadence_slots" \
    --arg max_orders_per_tick "$twamm_trigger_max_orders_per_tick" \
    --arg enabled "$twamm_trigger_enabled" \
    '{
      cadence_slots: $cadence_slots,
      max_orders_per_tick: $max_orders_per_tick,
      enabled: $enabled
    }')" \
  '$actual[0] == $expected[0]
   and $actual[1] == $expected[1]
   and $actual[2] == $expected[2]
   and (($actual[3] // 0) >= 1)
   and (($actual[4] // 0) >= 0)
   and (($actual[5] // 0) >= 0)
   and (($actual[6] // 0) >= 0)'

launch_hook_view_payload="$(jq -cn --arg hook_id "$soraswap_launch_dlmm_hook_id" '{hook_id: $hook_id}')"
ensure_step_from_prior_or_skip \
  "soraswap launch dlmm hook policy" \
  "$dlmm_hooks_manager_contract" \
  "hook_policy" \
  "$launch_hook_view_payload" \
  '[0,0,0,0]' \
  "$(jq -cn --argjson phase "$soraswap_launch_dlmm_hook_phase" --argjson max_fee "$soraswap_launch_dlmm_hook_max_fee_pips" '[1,$phase,$max_fee,1]')" \
  "configure_hook_policy" \
  "$(jq -cn --arg hook_id "$soraswap_launch_dlmm_hook_id" --arg phase "$soraswap_launch_dlmm_hook_phase" --arg max_fee_pips "$soraswap_launch_dlmm_hook_max_fee_pips" '{hook_id:$hook_id, phase:$phase, max_fee_pips:$max_fee_pips, enabled:"1"}')"

echo "post-deploy contract state initialized"
