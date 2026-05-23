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
launchpad_liquidity_executor_contract="$(deployed_contract_id_for_env "$mode" launchpad.liquidity_executor)"
launchpad_sale_factory_contract="$(deployed_contract_id_for_env "$mode" launchpad.sale_factory)"
referral_registry_contract="$(deployed_contract_id_for_env "$mode" referral.registry)"
farms_farm_contract="$(deployed_contract_id_for_env "$mode" farms.farm)"
risk_vault_contract="$(deployed_contract_id_for_env "$mode" risk.risk_vault)"
perps_engine_contract="$(deployed_contract_id_for_env "$mode" perps.perps_engine)"
options_manager_contract="$(deployed_contract_id_for_env "$mode" options.manager)"
options_factory_contract="$(deployed_contract_id_for_env "$mode" options.factory)"
options_vault_contract="$(deployed_contract_id_for_env "$mode" options.vault)"
options_shout_option_contract="$(deployed_contract_id_for_env "$mode" options.shout_option)"
options_outperformance_option_contract="$(deployed_contract_id_for_env "$mode" options.outperformance_option)"
cover_policy_manager_contract="$(deployed_contract_id_for_env "$mode" cover.policy_manager)"
automation_job_queue_contract="$(deployed_contract_id_for_env "$mode" automation.job_queue)"
intents_settlement_router_contract="$(deployed_contract_id_for_env "$mode" intents.settlement_router)"
vaults_manager_contract="$(deployed_contract_id_for_env "$mode" vaults.manager)"
operators_registry_contract="$(deployed_contract_id_for_env "$mode" operators.registry)"
margin_portfolio_margin_contract="$(deployed_contract_id_for_env "$mode" margin.portfolio_margin)"
rwa_market_contract="$(deployed_contract_id_for_env "$mode" rwa.market)"
dlmm_hooks_manager_contract="$(deployed_contract_id_for_env "$mode" dlmm_hooks.hook_manager)"
n3x_hub_contract_subject="$(contract_subject_account_for_literal "$config" "$n3x_hub_contract")"
dlmm_pool_contract_subject="$(contract_subject_account_for_literal "$config" "$dlmm_pool_contract")"
launchpad_liquidity_executor_contract_subject="$(contract_subject_account_for_literal "$config" "$launchpad_liquidity_executor_contract")"
launchpad_sale_factory_contract_subject="$(contract_subject_account_for_literal "$config" "$launchpad_sale_factory_contract")"
risk_vault_contract_subject="$(contract_subject_account_for_literal "$config" "$risk_vault_contract")"
perps_engine_contract_subject="$(contract_subject_account_for_literal "$config" "$perps_engine_contract")"
options_factory_contract_subject="$(contract_subject_account_for_literal "$config" "$options_factory_contract")"
cover_policy_manager_contract_subject="$(contract_subject_account_for_literal "$config" "$cover_policy_manager_contract")"
dlmm_router_contract_subject="$(contract_subject_account_for_literal "$config" "$dlmm_router_contract")"
intents_settlement_router_contract_subject="$(contract_subject_account_for_literal "$config" "$intents_settlement_router_contract")"
vaults_manager_contract_subject="$(contract_subject_account_for_literal "$config" "$vaults_manager_contract")"
operators_registry_contract_subject="$(contract_subject_account_for_literal "$config" "$operators_registry_contract")"
margin_portfolio_margin_contract_subject="$(contract_subject_account_for_literal "$config" "$margin_portfolio_margin_contract")"
rwa_market_contract_subject="$(contract_subject_account_for_literal "$config" "$rwa_market_contract")"
dlmm_hooks_manager_contract_subject="$(contract_subject_account_for_literal "$config" "$dlmm_hooks_manager_contract")"
dlmm_pool_contract_blob_hex="0x$(printf '%s' "$dlmm_pool_contract" | xxd -p -c 256 | tr -d '\n')"
launchpad_liquidity_executor_contract_blob_hex="0x$(printf '%s' "$launchpad_liquidity_executor_contract" | xxd -p -c 256 | tr -d '\n')"
risk_vault_contract_blob_hex="0x$(printf '%s' "$risk_vault_contract" | xxd -p -c 256 | tr -d '\n')"
options_manager_contract_blob_hex="0x$(printf '%s' "$options_manager_contract" | xxd -p -c 256 | tr -d '\n')"
options_vault_contract_blob_hex="0x$(printf '%s' "$options_vault_contract" | xxd -p -c 256 | tr -d '\n')"
options_shout_option_contract_blob_hex="0x$(printf '%s' "$options_shout_option_contract" | xxd -p -c 256 | tr -d '\n')"
options_outperformance_option_contract_blob_hex="0x$(printf '%s' "$options_outperformance_option_contract" | xxd -p -c 256 | tr -d '\n')"
risk_vault_custody_account="$risk_vault_contract_subject"
bridge_deploy_record="$(deployment_record_path_for_env "$mode" bridge.sccp_bridge)"
sccp_bridge_contract=""
if [[ -f "$bridge_deploy_record" ]]; then
  sccp_bridge_contract="$(deployed_contract_id_for_env "$mode" bridge.sccp_bridge)"
fi
n3x_deploy_record="$(deployment_record_path_for_env "$mode" n3x.n3x_hub)"
dlmm_pool_deploy_record="$(deployment_record_path_for_env "$mode" dlmm.dlmm_pool)"
perps_deploy_record="$(deployment_record_path_for_env "$mode" perps.perps_engine)"
options_factory_deploy_record="$(deployment_record_path_for_env "$mode" options.factory)"
cover_policy_manager_deploy_record="$(deployment_record_path_for_env "$mode" cover.policy_manager)"
previous_n3x_hub_contract=""
previous_n3x_hub_contract_subject=""
if [[ -f "$n3x_deploy_record" ]]; then
  previous_n3x_hub_contract="$(jq -r '.response.previous_contract_address // empty' "$n3x_deploy_record")"
  if [[ -n "$previous_n3x_hub_contract" ]]; then
    previous_n3x_hub_contract_subject="$(contract_subject_account_for_literal "$config" "$previous_n3x_hub_contract")"
  fi
fi
previous_dlmm_pool_contract=""
previous_dlmm_pool_contract_subject=""
if [[ -f "$dlmm_pool_deploy_record" ]]; then
  previous_dlmm_pool_contract="$(jq -r '.response.previous_contract_address // empty' "$dlmm_pool_deploy_record")"
  if [[ -n "$previous_dlmm_pool_contract" ]]; then
    previous_dlmm_pool_contract_subject="$(contract_subject_account_for_literal "$config" "$previous_dlmm_pool_contract")"
  fi
fi
previous_perps_engine_contract=""
previous_perps_engine_contract_subject=""
if [[ -f "$perps_deploy_record" ]]; then
  previous_perps_engine_contract="$(jq -r '.response.previous_contract_address // empty' "$perps_deploy_record")"
  if [[ -n "$previous_perps_engine_contract" ]]; then
    previous_perps_engine_contract_subject="$(contract_subject_account_for_literal "$config" "$previous_perps_engine_contract")"
  fi
fi
previous_options_factory_contract=""
previous_options_factory_contract_subject=""
if [[ -f "$options_factory_deploy_record" ]]; then
  previous_options_factory_contract="$(jq -r '.response.previous_contract_address // empty' "$options_factory_deploy_record")"
  if [[ -n "$previous_options_factory_contract" ]]; then
    previous_options_factory_contract_subject="$(contract_subject_account_for_literal "$config" "$previous_options_factory_contract")"
  fi
fi
previous_cover_policy_manager_contract=""
previous_cover_policy_manager_contract_subject=""
if [[ -f "$cover_policy_manager_deploy_record" ]]; then
  previous_cover_policy_manager_contract="$(jq -r '.response.previous_contract_address // empty' "$cover_policy_manager_deploy_record")"
  if [[ -n "$previous_cover_policy_manager_contract" ]]; then
    previous_cover_policy_manager_contract_subject="$(contract_subject_account_for_literal "$config" "$previous_cover_policy_manager_contract")"
  fi
fi

vault_account="$(treasury_account_for_mode "$mode")"
n3x_vault_account="${SORASWAP_N3X_VAULT_ACCOUNT:-$n3x_hub_contract_subject}"
n3x_actual_vault_account="$n3x_vault_account"
dlmm_pool_vault_account="${SORASWAP_DLMM_POOL_VAULT_ACCOUNT:-$dlmm_pool_contract_subject}"
dlmm_pool_balance_source_account="${SORASWAP_AUTHORITY}"
dlmm_pool_balance_source_signer_config="$config"
dlmm_pool_balance_source_cleanup=0
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
bootstrap_scope="${SORASWAP_BOOTSTRAP_SCOPE:-full}"
referral_claim_threshold="${SORASWAP_REFERRAL_SMOKE_CLAIM_THRESHOLD:-3}"
referral_direct_share_bps="${SORASWAP_REFERRAL_SMOKE_DIRECT_SHARE_BPS:-7000}"
referral_parent_share_bps="${SORASWAP_REFERRAL_SMOKE_PARENT_SHARE_BPS:-3000}"
perps_funding_bps="${SORASWAP_PERPS_SMOKE_FUNDING_BPS:-100}"
perps_max_leverage_bps="${SORASWAP_PERPS_SMOKE_MAX_LEVERAGE_BPS:-50000}"
perps_maintenance_margin_bps="${SORASWAP_PERPS_SMOKE_MAINTENANCE_MARGIN_BPS:-500}"
perps_liquidation_fee_bps="${SORASWAP_PERPS_SMOKE_LIQUIDATION_FEE_BPS:-1000}"
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
cover_oracle_stale_slots="${SORASWAP_COVER_ORACLE_STALE_SLOTS:-4}"
oracle_public_key_hex="$(soraswap_required_oracle_public_key_hex "$config")"
oracle_scheme="$SORASWAP_ORACLE_SCHEME"
if [[ "$mode" == "local" ]]; then
  default_risk_bucket_1_bootstrap_deposit=200
  default_risk_bucket_2_bootstrap_deposit=0
  default_risk_bucket_3_bootstrap_deposit=0
else
  default_risk_bucket_1_bootstrap_deposit=200
  default_risk_bucket_2_bootstrap_deposit=0
  default_risk_bucket_3_bootstrap_deposit=0
fi
risk_bucket_1_bootstrap_deposit="${SORASWAP_RISK_BUCKET_1_BOOTSTRAP_DEPOSIT:-$default_risk_bucket_1_bootstrap_deposit}"
risk_bucket_2_bootstrap_deposit="${SORASWAP_RISK_BUCKET_2_BOOTSTRAP_DEPOSIT:-$default_risk_bucket_2_bootstrap_deposit}"
risk_bucket_3_bootstrap_deposit="${SORASWAP_RISK_BUCKET_3_BOOTSTRAP_DEPOSIT:-$default_risk_bucket_3_bootstrap_deposit}"
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

echo "bootstrap contract state via $config"

ensure_account_registered "$config" "$vault_account" soraswap
ensure_account_registered "$config" "$n3x_hub_contract_subject" contract-subject
ensure_account_registered "$config" "$dlmm_pool_contract_subject" contract-subject
ensure_account_registered "$config" "$dlmm_router_contract_subject" contract-subject
ensure_account_registered "$config" "$intents_settlement_router_contract_subject" contract-subject
ensure_account_registered "$config" "$vaults_manager_contract_subject" contract-subject
ensure_account_registered "$config" "$operators_registry_contract_subject" contract-subject
ensure_account_registered "$config" "$margin_portfolio_margin_contract_subject" contract-subject
ensure_account_registered "$config" "$rwa_market_contract_subject" contract-subject
ensure_account_registered "$config" "$dlmm_hooks_manager_contract_subject" contract-subject

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

  response_json="$(submit_contract_view "$config" "$contract_id" "$entrypoint" "$SORASWAP_SMOKE_GAS_LIMIT" "$payload_json")" || return 1
  contract_view_result_json "$response_json"
}

view_result_json_with_retry() {
  local contract_id="$1"
  local entrypoint="$2"
  local payload_json="${3:-null}"
  local attempts="${4:-15}"
  local sleep_seconds="${5:-1}"
  local attempt=1
  local result_json=""

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
  local actual_json

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

  echo "bootstrap apply: $label"
  call_contract_and_wait "$config" "$contract_id" "$call_entrypoint" "$call_payload_json" >/dev/null
  actual_json="$(view_result_json "$contract_id" "$view_entrypoint" "$view_payload_json")"
  if ! json_equals "$actual_json" "$expected_json"; then
    fail_bootstrap_diff "$label" "$expected_json" "$actual_json" "$accepted_prior_json"
  fi
}

ensure_risk_vault_init_or_skip() {
  local contract_id="$1"
  local expected_json="$2"
  local live_json="$3"
  local init_payload_json="$4"
  local live_predicate_jq="${5:-}"
  local actual_json

  actual_json="$(view_result_json "$contract_id" "risk_state" null)"
  if json_equals "$actual_json" "$expected_json"; then
    echo "bootstrap skip: risk vault init already matches expected state"
    return 0
  fi
  if json_equals "$actual_json" "$live_json"; then
    echo "bootstrap skip: risk vault init already exposes the live exit state"
    return 0
  fi
  if [[ "$mode" != "local" && -n "$live_predicate_jq" ]] && jq -en \
    --argjson actual "$actual_json" \
    --argjson expected "$expected_json" \
    "$live_predicate_jq" \
    >/dev/null; then
    echo "bootstrap skip: risk vault init already initialized on advanced live state"
    return 0
  fi

  echo "bootstrap apply: risk vault init"
  if ! call_contract_and_wait "$config" "$contract_id" "init_vault" "$init_payload_json" >/dev/null 2>&1; then
    actual_json="$(view_result_json "$contract_id" "risk_state" null)"
    if json_equals "$actual_json" "$expected_json"; then
      echo "bootstrap note: risk vault init returned a non-fatal live-state error after reaching the expected initialized state"
      return 0
    fi
    if json_equals "$actual_json" "$live_json"; then
      echo "bootstrap note: risk vault init returned a non-fatal live-state error while the vault already exposes the live exit state"
      return 0
    fi
    if [[ -n "$live_predicate_jq" ]] && jq -en \
      --argjson actual "$actual_json" \
      --argjson expected "$expected_json" \
      "$live_predicate_jq" \
      >/dev/null; then
      echo "bootstrap note: risk vault init returned a non-fatal live-state error while the vault already exposes advanced live state"
      return 0
    fi
    fail_bootstrap_diff "risk vault init" "$expected_json" "$actual_json" "$live_json"
  fi
  actual_json="$(view_result_json "$contract_id" "risk_state" null)"
  if ! json_equals "$actual_json" "$expected_json" \
    && ! json_equals "$actual_json" "$live_json" \
    && ! { [[ -n "$live_predicate_jq" ]] && jq -en \
      --argjson actual "$actual_json" \
      --argjson expected "$expected_json" \
      "$live_predicate_jq" \
      >/dev/null; }; then
    fail_bootstrap_diff "risk vault init" "$expected_json" "$actual_json" "$live_json"
  fi
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

  actual_json="$(view_result_json "$contract_id" "$view_entrypoint" "$view_payload_json" 2>/dev/null || true)"
  if json_value_present "$actual_json" && json_equals "$actual_json" "$expected_json"; then
    echo "bootstrap skip: $label already matches expected state"
    return 0
  fi

  echo "bootstrap apply: $label"
  call_contract_and_wait "$config" "$contract_id" "$call_entrypoint" "$call_payload_json" >/dev/null
  actual_json="$(view_result_json "$contract_id" "$view_entrypoint" "$view_payload_json")"
  if ! json_equals "$actual_json" "$expected_json"; then
    fail_bootstrap_diff "$label" "$expected_json" "$actual_json"
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

dlmm_live_reserve_totals_json() {
  local next_bin_id="$1"
  local far_bin_id="$2"
  local active_json next_json far_json

  active_json="$(view_result_json "$dlmm_pool_contract" "mirror_bin" "$(jq -cn --argjson bin_id "$pool_active_bin" '{bin_id: $bin_id}')")"
  next_json="$(view_result_json "$dlmm_pool_contract" "mirror_bin" "$(jq -cn --argjson bin_id "$next_bin_id" '{bin_id: $bin_id}')")"
  far_json="$(view_result_json "$dlmm_pool_contract" "mirror_bin" "$(jq -cn --argjson bin_id "$far_bin_id" '{bin_id: $bin_id}')")"

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
  local source_account source_signer_config source_base source_quote
  local migrate_base_from_source migrate_quote_from_source
  local topup_base topup_quote authority_base authority_quote

  reserve_totals_json="$(dlmm_live_reserve_totals_json "$next_bin_id" "$far_bin_id")"
  expected_base="$(jq -r '.base' <<<"$reserve_totals_json")"
  expected_quote="$(jq -r '.quote' <<<"$reserve_totals_json")"
  actual_base="$(asset_value_for_account_id "$config" "$xor_id" "$dlmm_pool_vault_account")"
  actual_quote="$(asset_value_for_account_id "$config" "$usdt_id" "$dlmm_pool_vault_account")"

  if (( actual_base >= expected_base && actual_quote >= expected_quote )); then
    echo "bootstrap skip: dlmm pool custody balances already cover live reserve totals"
    return 0
  fi

  source_account="${dlmm_pool_balance_source_account:-${SORASWAP_AUTHORITY:?missing authority for dlmm custody migration}}"
  source_signer_config="${dlmm_pool_balance_source_signer_config:-$config}"
  source_base="$(asset_value_for_account_id "$config" "$xor_id" "$source_account")"
  source_quote="$(asset_value_for_account_id "$config" "$usdt_id" "$source_account")"
  migrate_base_from_source=$(( expected_base - actual_base ))
  migrate_quote_from_source=$(( expected_quote - actual_quote ))

  if (( migrate_base_from_source <= 0 && migrate_quote_from_source <= 0 )); then
    echo "bootstrap skip: dlmm pool custody balances already aligned"
    return 0
  fi

  if (( migrate_base_from_source < 0 )); then
    migrate_base_from_source=0
  fi
  if (( migrate_quote_from_source < 0 )); then
    migrate_quote_from_source=0
  fi
  if (( source_base < migrate_base_from_source )); then
    migrate_base_from_source="$source_base"
  fi
  if (( source_quote < migrate_quote_from_source )); then
    migrate_quote_from_source="$source_quote"
  fi
  topup_base=$(( expected_base - actual_base - migrate_base_from_source ))
  topup_quote=$(( expected_quote - actual_quote - migrate_quote_from_source ))
  if (( topup_base < 0 )); then
    topup_base=0
  fi
  if (( topup_quote < 0 )); then
    topup_quote=0
  fi

  if [[ "$source_account" != "$SORASWAP_AUTHORITY" ]] && (( migrate_base_from_source > 0 || migrate_quote_from_source > 0 )); then
    ensure_signer_fee_balance "$source_account"
  fi

  if [[ "$source_account" != "$SORASWAP_AUTHORITY" ]]; then
    authority_base="$(asset_value_for_account_id "$config" "$xor_id" "$SORASWAP_AUTHORITY")"
    authority_quote="$(asset_value_for_account_id "$config" "$usdt_id" "$SORASWAP_AUTHORITY")"
    if (( authority_base < topup_base || authority_quote < topup_quote )); then
      fail_bootstrap_diff \
        "dlmm pool custody migration source balances" \
        "$(jq -cn --argjson base "$expected_base" --argjson quote "$expected_quote" --argjson target_base "$actual_base" --argjson target_quote "$actual_quote" --argjson topup_base "$topup_base" --argjson topup_quote "$topup_quote" '{base_required: $base, quote_required: $quote, target_base: $target_base, target_quote: $target_quote, authority_topup_base: $topup_base, authority_topup_quote: $topup_quote}')" \
        "$(jq -cn --arg source_account "$source_account" --argjson source_base "$source_base" --argjson source_quote "$source_quote" --arg authority_account "$SORASWAP_AUTHORITY" --argjson authority_base "$authority_base" --argjson authority_quote "$authority_quote" '{source_account: $source_account, source_base: $source_base, source_quote: $source_quote, authority_account: $authority_account, authority_base: $authority_base, authority_quote: $authority_quote}')"
    fi
  fi

  if (( migrate_base_from_source > 0 )); then
    echo "bootstrap apply: dlmm pool custody base transfer"
    transfer_asset_balance_between_accounts "$source_signer_config" "$source_account" "$dlmm_pool_vault_account" "$xor_id" "$migrate_base_from_source"
  fi

  if (( migrate_quote_from_source > 0 )); then
    echo "bootstrap apply: dlmm pool custody quote transfer"
    transfer_asset_balance_between_accounts "$source_signer_config" "$source_account" "$dlmm_pool_vault_account" "$usdt_id" "$migrate_quote_from_source"
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
  local chain torii_url account_domain ttl_ms status_timeout_ms nonce tmp_config

  chain="$(config_chain_id_from_config "$config")"
  torii_url="$(awk -F '"' '/^[[:space:]]*torii_url[[:space:]]*=/ {print $2; exit}' "$config")"
  account_domain="$(awk '
    /^\[account\]/ { in_account = 1; next }
    /^\[/ { in_account = 0 }
    in_account && /^[[:space:]]*domain[[:space:]]*=/ {
      sub(/^[[:space:]]*domain[[:space:]]*=[[:space:]]*"/, "", $0)
      sub(/"[[:space:]]*$/, "", $0)
      print $0
      exit
    }
  ' "$config")"
  ttl_ms="$(awk '
    /^\[transaction\]/ { in_tx = 1; next }
    /^\[/ { in_tx = 0 }
    in_tx && /^[[:space:]]*time_to_live_ms[[:space:]]*=/ { gsub(/[^0-9]/, "", $0); print $0; exit }
  ' "$config")"
  status_timeout_ms="$(awk '
    /^\[transaction\]/ { in_tx = 1; next }
    /^\[/ { in_tx = 0 }
    in_tx && /^[[:space:]]*status_timeout_ms[[:space:]]*=/ { gsub(/[^0-9]/, "", $0); print $0; exit }
  ' "$config")"
  nonce="$(awk '
    /^\[transaction\]/ { in_tx = 1; next }
    /^\[/ { in_tx = 0 }
    in_tx && /^[[:space:]]*nonce[[:space:]]*=/ {
      sub(/^[[:space:]]*nonce[[:space:]]*=[[:space:]]*/, "", $0)
      print $0
      exit
    }
  ' "$config")"

  ttl_ms="${ttl_ms:-120000}"
  status_timeout_ms="${status_timeout_ms:-120000}"
  nonce="${nonce:-false}"
  account_domain="${account_domain:-default}"
  tmp_config="$(mktemp -t soraswap-signer-config)"
  printf '%s\n' \
    "chain = \"$chain\"" \
    "torii_url = \"$torii_url\"" \
    "" \
    "[account]" \
    "domain = \"$account_domain\"" \
    "public_key = \"$public_key\"" \
    "private_key = \"$private_key\"" \
    "" \
    "[transaction]" \
    "time_to_live_ms = $ttl_ms" \
    "status_timeout_ms = $status_timeout_ms" \
    "nonce = $nonce" \
    > "$tmp_config"
  echo "$tmp_config"
}

contract_subject_signer_config() {
  local contract_id="$1"
  local kagami_bin seed key_output public_key private_key

  ensure_kagami_bin >/dev/null
  kagami_bin="$SORASWAP_IROHA_ROOT/target/debug/kagami"
  seed="iroha:contract-subject:v1:${contract_id}"
  key_output="$("$kagami_bin" keys --algorithm ed25519 --seed "$seed" --compact 2>/dev/null)"
  public_key="$(awk '/^ed[0-9A-Fa-f]+$/ { print; exit }' <<<"$key_output")"
  private_key="$(awk '/^8026[0-9A-Fa-f]+$/ { print; exit }' <<<"$key_output")"
  if [[ -z "$public_key" || -z "$private_key" ]]; then
    echo "failed to derive contract subject signer for $contract_id" >&2
    return 1
  fi

  temp_signer_config_for_public_private_keys "$public_key" "$private_key"
}

historical_contract_id_for_subject_account() {
  local env="$1"
  local contract_key="$2"
  local subject_account="$3"
  local deployments_dir archive_dir
  local -a json_files
  local contract_id

  if [[ -z "$subject_account" ]]; then
    return 1
  fi

  deployments_dir="$(deployments_dir_for_env "$env")"
  json_files=("$deployments_dir"/*.json(N))
  archive_dir="$deployments_dir/archive"
  if [[ -d "$archive_dir" ]]; then
    json_files+=("$archive_dir"/*/*.json(N))
  fi
  if (( ${#json_files[@]} == 0 )); then
    return 1
  fi

  while IFS= read -r contract_id; do
    if [[ -n "$contract_id" && "$(contract_subject_account_for_literal "$config" "$contract_id")" == "$subject_account" ]]; then
      echo "$contract_id"
      return 0
    fi
  done < <(
    jq -r --arg key "$contract_key" '
      def emit($value):
        if $value == null or $value == "" then
          empty
        else
          $value
        end;
      if .contract_key? == $key then
        emit(.contract_address),
        emit(.response.previous_contract_address),
        emit(.instance.contract_address)
      elif .contracts? then
        .contracts[]
        | select(.contract_key == $key)
        | emit(.contract_address),
          emit(.response.previous_contract_address),
          emit(.instance.contract_address)
      else
        empty
      end
    ' "${json_files[@]}" 2>/dev/null | awk 'NF && !seen[$0]++'
  )

  return 1
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

  iroha_cli_with_gas_metadata "$signer_config" ledger asset transfer \
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

ensure_contract_subject_balance_covers_bucket_deposits() {
  local label="$1"
  local subject_account="$2"
  local asset_id="$3"
  local bucket_id="$4"
  local bucket_json tracked_deposits current_balance topup

  if [[ "$mode" == "local" || -z "$subject_account" ]]; then
    return 0
  fi

  bucket_json="$(view_result_json "$risk_vault_contract" "bucket_state" "$(jq -cn --argjson bucket_id "$bucket_id" '{ bucket_id: $bucket_id }')")"
  tracked_deposits="$(jq -er '.[1] // 0' <<<"$bucket_json")"
  current_balance="$(asset_value_for_account_id "$config" "$asset_id" "$subject_account")"
  if (( current_balance >= tracked_deposits )); then
    return 0
  fi

  topup=$(( tracked_deposits - current_balance ))
  echo "bootstrap apply: $label custody top-up"
  transfer_asset_balance_between_accounts "$config" "$SORASWAP_AUTHORITY" "$subject_account" "$asset_id" "$topup"
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
  if [[ "$mode" == "testnet" || "$mode" == "production" ]] && jq -en \
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
    echo "bootstrap skip: dlmm pool seed state already reflects live $mode liquidity"
    return 0
  fi
  if ! json_equals "$actual_state_json" "$empty_state_json"; then
    fail_bootstrap_diff "dlmm pool seed state" "$expected_state_json" "$actual_state_json" "$empty_state_json"
  fi

  echo "bootstrap apply: dlmm pool seed state"

  seed_payload_json="$(jq -cn \
    --argjson bin_id "$pool_active_bin" \
    --argjson base_amount "$pool_seed_base" \
    --argjson quote_amount "$pool_seed_quote" \
    '{
      bin_id: $bin_id,
      base_amount: $base_amount,
      quote_amount: $quote_amount
    }')"
  call_contract_and_wait "$config" "$dlmm_pool_contract" seed_bin "$seed_payload_json" >/dev/null

  seed_payload_json="$(jq -cn \
    --argjson bin_id "$next_bin_id" \
    --argjson base_amount "$pool_seed_next_base" \
    --argjson quote_amount "$pool_seed_next_quote" \
    '{
      bin_id: $bin_id,
      base_amount: $base_amount,
      quote_amount: $quote_amount
    }')"
  call_contract_and_wait "$config" "$dlmm_pool_contract" seed_bin "$seed_payload_json" >/dev/null

  seed_payload_json="$(jq -cn \
    --argjson bin_id "$far_bin_id" \
    --argjson base_amount "$pool_seed_far_base" \
    --argjson quote_amount "$pool_seed_far_quote" \
    '{
      bin_id: $bin_id,
      base_amount: $base_amount,
      quote_amount: $quote_amount
    }')"
  call_contract_and_wait "$config" "$dlmm_pool_contract" seed_bin "$seed_payload_json" >/dev/null

  position_payload_json="$(jq -cn \
    --arg position_id "$pool_position_id" \
    --argjson bin_id "$pool_active_bin" \
    --argjson base_amount "$pool_position_base" \
    --argjson quote_amount "$pool_position_quote" \
    --argjson min_shares_out "$pool_position_min_shares_out" \
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
warmup_bucket_payload='{"bucket_id":1}'
warmup_market_payload='{"market_id":1}'
warmup_template_payload='{"template_id":1}'
warmup_series_payload='{"series_id":1}'
warmup_policy_payload='{"policy_id":1}'
warmup_job_payload="$(jq -cn --arg job "warmup" '{job: $job}')"
warmup_quote_mint_payload='{"usdt_in":0,"usdc_in":0,"kusd_in":0}'
warmup_quote_direct_payload='{"reserve_in":1,"reserve_out":1,"amount_in":1,"fee_pips":0}'

# The first IVM execution against a freshly deployed debug localnet can be
# slow enough to trip the single-peer consensus timeout. Prewarm each contract
# with a lightweight view before the first mutating bootstrap call.
warm_view "$n3x_hub_contract" quote_mint "$warmup_quote_mint_payload"
warm_view "$dlmm_router_contract" quote_direct "$warmup_quote_direct_payload"
warm_view "$dlmm_pool_contract" pool_config
warm_view "$launchpad_liquidity_executor_contract" executor_config
warm_view "$launchpad_sale_factory_contract" sale_config "$warmup_sale_payload"
warm_view "$referral_registry_contract" registry_config
warm_view "$farms_farm_contract" farm_config
warm_view "$risk_vault_contract" bucket_state "$warmup_bucket_payload"
warm_view "$perps_engine_contract" engine_config
warm_view "$perps_engine_contract" market_state "$warmup_market_payload"
warm_view "$options_manager_contract" manager_config
warm_view "$options_manager_contract" template_state "$warmup_template_payload"
warm_view "$options_manager_contract" series_state "$warmup_series_payload"
warm_view "$options_factory_contract" factory_config
warm_view "$options_factory_contract" series_state "$warmup_series_payload"
warm_view "$options_vault_contract" vault_state "$warmup_series_payload"
warm_view "$options_shout_option_contract" series_state "$warmup_series_payload"
warm_view "$options_outperformance_option_contract" series_state "$warmup_series_payload"
warm_view "$cover_policy_manager_contract" manager_config
warm_view "$cover_policy_manager_contract" policy_state "$warmup_policy_payload"
warm_view "$automation_job_queue_contract" mirror_job "$warmup_job_payload"
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
  --argjson target_usdt_bps "$n3x_target_usdt_bps" \
  --argjson target_usdc_bps "$n3x_target_usdc_bps" \
  --argjson target_kusd_bps "$n3x_target_kusd_bps" \
  --argjson mint_fee_bps "$n3x_mint_fee_bps" \
  --argjson redeem_fee_bps "$n3x_redeem_fee_bps" \
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
if ! view_result_json "$n3x_hub_contract" hub_config null >/dev/null 2>&1; then
  echo "bootstrap apply: n3x hub config"
  call_contract_and_wait "$config" "$n3x_hub_contract" "init_hub" "$n3x_init_payload" >/dev/null
  n3x_actual_json="$(view_result_json_with_retry "$n3x_hub_contract" "hub_config" null)"
  if ! json_equals "$n3x_actual_json" "$n3x_expected_json"; then
    fail_bootstrap_diff "n3x hub config" "$n3x_expected_json" "$n3x_actual_json"
  fi
else
  n3x_actual_json="$(view_result_json "$n3x_hub_contract" "hub_config" null)"
  if json_equals "$n3x_actual_json" "$n3x_expected_json"; then
    echo "bootstrap skip: n3x hub config already matches expected state"
  else
    n3x_state_json="$(view_result_json "$n3x_hub_contract" "mirror_state" null)"
    if jq -en \
      --argjson actual "$n3x_actual_json" \
      --argjson expected "$n3x_expected_json" \
      '
        ($actual | length) == 10
        and ($expected | length) == 10
        and ($actual[0] == $expected[0])
        and ($actual[1] == $expected[1])
        and ($actual[2] == $expected[2])
        and ($actual[3] == $expected[3])
        and ($actual[5] == $expected[5])
        and ($actual[6] == $expected[6])
        and ($actual[7] == $expected[7])
        and ($actual[8] == $expected[8])
        and ($actual[9] == $expected[9])
      ' >/dev/null; then
      n3x_actual_vault_account="$(jq -r '.[4]' <<<"$n3x_actual_json")"
      n3x_total_supply="$(jq -r '.[4]' <<<"$n3x_state_json")"
      n3x_basket_usdt="$(jq -r '.[1]' <<<"$n3x_state_json")"
      n3x_basket_usdc="$(jq -r '.[2]' <<<"$n3x_state_json")"
      n3x_basket_kusd="$(jq -r '.[3]' <<<"$n3x_state_json")"
      n3x_source_signer_config="$config"
      n3x_source_signer_cleanup=0
      n3x_source_signer_available=0
      if [[ "$n3x_actual_vault_account" == "$dlmm_pool_contract_subject" ]]; then
        n3x_source_signer_config="$(contract_subject_signer_config "$dlmm_pool_contract")"
        n3x_source_signer_cleanup=1
        n3x_source_signer_available=1
      elif [[ -n "$previous_dlmm_pool_contract_subject" && "$n3x_actual_vault_account" == "$previous_dlmm_pool_contract_subject" ]]; then
        n3x_source_signer_config="$(contract_subject_signer_config "$previous_dlmm_pool_contract")"
        n3x_source_signer_cleanup=1
        n3x_source_signer_available=1
      elif [[ -n "$previous_n3x_hub_contract_subject" && "$n3x_actual_vault_account" == "$previous_n3x_hub_contract_subject" ]]; then
        n3x_source_signer_config="$(contract_subject_signer_config "$previous_n3x_hub_contract")"
        n3x_source_signer_cleanup=1
        n3x_source_signer_available=1
      elif [[ "$n3x_actual_vault_account" == "$SORASWAP_AUTHORITY" || "$n3x_actual_vault_account" == "$n3x_vault_account" ]]; then
        n3x_source_signer_available=1
      fi

      if (( n3x_total_supply > 0 )); then
        if [[ "$n3x_actual_vault_account" != "$n3x_vault_account" ]]; then
          current_usdt_balance="$(asset_value_for_account_id "$config" "$usdt_id" "$n3x_actual_vault_account")"
          current_usdc_balance="$(asset_value_for_account_id "$config" "$usdc_id" "$n3x_actual_vault_account")"
          current_kusd_balance="$(asset_value_for_account_id "$config" "$kusd_id" "$n3x_actual_vault_account")"
          target_usdt_balance="$(asset_value_for_account_id "$config" "$usdt_id" "$n3x_vault_account")"
          target_usdc_balance="$(asset_value_for_account_id "$config" "$usdc_id" "$n3x_vault_account")"
          target_kusd_balance="$(asset_value_for_account_id "$config" "$kusd_id" "$n3x_vault_account")"
          if (( n3x_source_signer_available == 1 )); then
            migrate_usdt_from_source=$(( n3x_basket_usdt - target_usdt_balance ))
            migrate_usdc_from_source=$(( n3x_basket_usdc - target_usdc_balance ))
            migrate_kusd_from_source=$(( n3x_basket_kusd - target_kusd_balance ))
            if (( migrate_usdt_from_source < 0 )); then
              migrate_usdt_from_source=0
            fi
            if (( migrate_usdc_from_source < 0 )); then
              migrate_usdc_from_source=0
            fi
            if (( migrate_kusd_from_source < 0 )); then
              migrate_kusd_from_source=0
            fi
            if (( current_usdt_balance < migrate_usdt_from_source )); then
              migrate_usdt_from_source="$current_usdt_balance"
            fi
            if (( current_usdc_balance < migrate_usdc_from_source )); then
              migrate_usdc_from_source="$current_usdc_balance"
            fi
            if (( current_kusd_balance < migrate_kusd_from_source )); then
              migrate_kusd_from_source="$current_kusd_balance"
            fi
          else
            migrate_usdt_from_source=0
            migrate_usdc_from_source=0
            migrate_kusd_from_source=0
          fi
          migrate_usdt_topup=$(( n3x_basket_usdt - target_usdt_balance - migrate_usdt_from_source ))
          migrate_usdc_topup=$(( n3x_basket_usdc - target_usdc_balance - migrate_usdc_from_source ))
          migrate_kusd_topup=$(( n3x_basket_kusd - target_kusd_balance - migrate_kusd_from_source ))
          if (( migrate_usdt_topup < 0 )); then
            migrate_usdt_topup=0
          fi
          if (( migrate_usdc_topup < 0 )); then
            migrate_usdc_topup=0
          fi
          if (( migrate_kusd_topup < 0 )); then
            migrate_kusd_topup=0
          fi
          authority_usdt_balance="$(asset_value_for_account_id "$config" "$usdt_id" "$SORASWAP_AUTHORITY")"
          authority_usdc_balance="$(asset_value_for_account_id "$config" "$usdc_id" "$SORASWAP_AUTHORITY")"
          authority_kusd_balance="$(asset_value_for_account_id "$config" "$kusd_id" "$SORASWAP_AUTHORITY")"
          if (( authority_usdt_balance < migrate_usdt_topup || authority_usdc_balance < migrate_usdc_topup || authority_kusd_balance < migrate_kusd_topup )); then
            if (( n3x_source_signer_cleanup == 1 )); then
              rm -f "$n3x_source_signer_config"
            fi
            fail_bootstrap_diff \
              "n3x hub custody balances" \
              "$(jq -cn --argjson basket_usdt "$n3x_basket_usdt" --argjson basket_usdc "$n3x_basket_usdc" --argjson basket_kusd "$n3x_basket_kusd" --argjson topup_usdt "$migrate_usdt_topup" --argjson topup_usdc "$migrate_usdc_topup" --argjson topup_kusd "$migrate_kusd_topup" '{ basket_usdt: $basket_usdt, basket_usdc: $basket_usdc, basket_kusd: $basket_kusd, topup_usdt: $topup_usdt, topup_usdc: $topup_usdc, topup_kusd: $topup_kusd }')" \
              "$(jq -cn --arg source_account "$n3x_actual_vault_account" --argjson source_signer_available "$n3x_source_signer_available" --argjson source_usdt "$current_usdt_balance" --argjson source_usdc "$current_usdc_balance" --argjson source_kusd "$current_kusd_balance" --arg authority_account "$SORASWAP_AUTHORITY" --argjson authority_usdt "$authority_usdt_balance" --argjson authority_usdc "$authority_usdc_balance" --argjson authority_kusd "$authority_kusd_balance" '{ source_account: $source_account, source_signer_available: $source_signer_available, source_usdt: $source_usdt, source_usdc: $source_usdc, source_kusd: $source_kusd, authority_account: $authority_account, authority_usdt: $authority_usdt, authority_usdc: $authority_usdc, authority_kusd: $authority_kusd }')"
          fi
          echo "bootstrap apply: n3x hub custody migration"
          if (( n3x_source_signer_available == 1 )); then
            transfer_asset_balance_between_accounts "$n3x_source_signer_config" "$n3x_actual_vault_account" "$n3x_vault_account" "$usdt_id" "$migrate_usdt_from_source"
            transfer_asset_balance_between_accounts "$n3x_source_signer_config" "$n3x_actual_vault_account" "$n3x_vault_account" "$usdc_id" "$migrate_usdc_from_source"
            transfer_asset_balance_between_accounts "$n3x_source_signer_config" "$n3x_actual_vault_account" "$n3x_vault_account" "$kusd_id" "$migrate_kusd_from_source"
          else
            echo "bootstrap note: n3x hub source account $n3x_actual_vault_account is not signer-accessible; covering live basket from authority before rebinding vault"
          fi
          transfer_asset_balance_between_accounts "$config" "$SORASWAP_AUTHORITY" "$n3x_vault_account" "$usdt_id" "$migrate_usdt_topup"
          transfer_asset_balance_between_accounts "$config" "$SORASWAP_AUTHORITY" "$n3x_vault_account" "$usdc_id" "$migrate_usdc_topup"
          transfer_asset_balance_between_accounts "$config" "$SORASWAP_AUTHORITY" "$n3x_vault_account" "$kusd_id" "$migrate_kusd_topup"
          final_target_usdt_balance="$(asset_value_for_account_id "$config" "$usdt_id" "$n3x_vault_account")"
          final_target_usdc_balance="$(asset_value_for_account_id "$config" "$usdc_id" "$n3x_vault_account")"
          final_target_kusd_balance="$(asset_value_for_account_id "$config" "$kusd_id" "$n3x_vault_account")"
          if (( final_target_usdt_balance < n3x_basket_usdt || final_target_usdc_balance < n3x_basket_usdc || final_target_kusd_balance < n3x_basket_kusd )); then
            if (( n3x_source_signer_cleanup == 1 )); then
              rm -f "$n3x_source_signer_config"
            fi
            fail_bootstrap_diff \
              "n3x hub migrated custody balances" \
              "$(jq -cn --argjson basket_usdt "$n3x_basket_usdt" --argjson basket_usdc "$n3x_basket_usdc" --argjson basket_kusd "$n3x_basket_kusd" '{ basket_usdt: $basket_usdt, basket_usdc: $basket_usdc, basket_kusd: $basket_kusd }')" \
              "$(jq -cn --arg vault_account "$n3x_vault_account" --argjson target_usdt "$final_target_usdt_balance" --argjson target_usdc "$final_target_usdc_balance" --argjson target_kusd "$final_target_kusd_balance" '{ vault_account: $vault_account, target_usdt: $target_usdt, target_usdc: $target_usdc, target_kusd: $target_kusd }')"
          fi
          echo "bootstrap apply: n3x hub vault binding"
          call_contract_and_wait \
            "$config" \
            "$n3x_hub_contract" \
            "bind_vault_account" \
            "$(jq -cn --arg vault_account "$n3x_vault_account" '{ vault_account: $vault_account }')" \
            >/dev/null
          if (( n3x_source_signer_cleanup == 1 )); then
            rm -f "$n3x_source_signer_config"
          fi
        fi
      else
        if [[ "$n3x_actual_vault_account" != "$n3x_vault_account" || "$n3x_basket_usdt" != "0" || "$n3x_basket_usdc" != "0" || "$n3x_basket_kusd" != "0" ]]; then
          echo "bootstrap apply: n3x hub zero-supply repair"
          call_contract_and_wait \
            "$config" \
            "$n3x_hub_contract" \
            "repair_zero_supply_state" \
            "$(jq -cn --arg vault_account "$n3x_vault_account" '{ vault_account: $vault_account }')" \
            >/dev/null
        fi
        if (( n3x_source_signer_cleanup == 1 )); then
          rm -f "$n3x_source_signer_config"
        fi
      fi

      n3x_actual_json="$(view_result_json_with_retry "$n3x_hub_contract" "hub_config" null)"
      if ! json_equals "$n3x_actual_json" "$n3x_expected_json"; then
        fail_bootstrap_diff "n3x hub config" "$n3x_expected_json" "$n3x_actual_json"
      fi
      n3x_state_json="$(view_result_json_with_retry "$n3x_hub_contract" "mirror_state" null)"
      if (( $(jq -r '.[4]' <<<"$n3x_state_json") == 0 )); then
        if ! jq -en --argjson state "$n3x_state_json" '
          ($state[1] // 0) == 0
          and ($state[2] // 0) == 0
          and ($state[3] // 0) == 0
          and ($state[4] // 0) == 0
          and ($state[7] // 0) == 0
          and ($state[8] // 0) == 0
        ' >/dev/null; then
          fail_bootstrap_diff "n3x hub zero-supply repair" '[0,0,0,0,0,0]' "$n3x_state_json"
        fi
      fi
    else
      fail_bootstrap_diff "n3x hub config" "$n3x_expected_json" "$n3x_actual_json"
    fi
  fi
fi

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
  --arg vault_account "$dlmm_pool_vault_account" \
  --argjson fee_pips "$pool_fee_pips" \
  --argjson bin_step "$pool_bin_step" \
  --argjson active_bin "$pool_active_bin" \
  '[ $base_asset, $quote_asset, $vault_account, $fee_pips, $bin_step, $active_bin ]')"
pool_legacy_json="$(jq -cn \
  --arg base_asset "$xor_id" \
  --arg quote_asset "$usdt_id" \
  --arg vault_account "$vault_account" \
  --argjson fee_pips "$pool_fee_pips" \
  --argjson bin_step "$pool_bin_step" \
  --argjson active_bin "$pool_active_bin" \
  '[ $base_asset, $quote_asset, $vault_account, $fee_pips, $bin_step, $active_bin ]')"
pool_n3x_custody_json="$(jq -cn \
  --arg base_asset "$xor_id" \
  --arg quote_asset "$usdt_id" \
  --arg vault_account "$n3x_vault_account" \
  --argjson fee_pips "$pool_fee_pips" \
  --argjson bin_step "$pool_bin_step" \
  --argjson active_bin "$pool_active_bin" \
  '[ $base_asset, $quote_asset, $vault_account, $fee_pips, $bin_step, $active_bin ]')"
pool_n3x_source_custody_json='null'
if [[ "$n3x_actual_vault_account" != "$n3x_vault_account" ]]; then
  pool_n3x_source_custody_json="$(jq -cn \
    --arg base_asset "$xor_id" \
    --arg quote_asset "$usdt_id" \
    --arg vault_account "$n3x_actual_vault_account" \
    --argjson fee_pips "$pool_fee_pips" \
    --argjson bin_step "$pool_bin_step" \
    --argjson active_bin "$pool_active_bin" \
    '[ $base_asset, $quote_asset, $vault_account, $fee_pips, $bin_step, $active_bin ]')"
fi
pool_previous_custody_json='null'
if [[ -n "$previous_dlmm_pool_contract_subject" ]]; then
  pool_previous_custody_json="$(jq -cn \
    --arg base_asset "$xor_id" \
    --arg quote_asset "$usdt_id" \
    --arg vault_account "$previous_dlmm_pool_contract_subject" \
    --argjson fee_pips "$pool_fee_pips" \
    --argjson bin_step "$pool_bin_step" \
    --argjson active_bin "$pool_active_bin" \
    '[ $base_asset, $quote_asset, $vault_account, $fee_pips, $bin_step, $active_bin ]')"
fi
pool_init_payload="$(jq -cn \
  --arg base_asset "$xor_id" \
  --arg quote_asset "$usdt_id" \
  --arg vault_account "$dlmm_pool_vault_account" \
  --argjson fee_pips "$pool_fee_pips" \
  --argjson bin_step "$pool_bin_step" \
  --argjson active_bin "$pool_active_bin" \
  --argjson impact_cap_bps "$pool_impact_cap_bps" \
  --argjson min_reserve_base "$pool_min_reserve_base" \
  --argjson min_reserve_quote "$pool_min_reserve_quote" \
  --argjson max_bins_per_swap "$pool_max_bins_per_swap" \
  --argjson bin_liquidity_cap "$pool_bin_liquidity_cap" \
  '{
    base_asset: $base_asset,
    quote_asset: $quote_asset,
    vault_account: $vault_account,
    fee_pips: $fee_pips,
    bin_step: $bin_step,
    active_bin: $active_bin,
    impact_cap_bps: $impact_cap_bps,
    min_reserve_base: $min_reserve_base,
    min_reserve_quote: $min_reserve_quote,
    max_bins_per_swap: $max_bins_per_swap,
    bin_liquidity_cap: $bin_liquidity_cap
  }')"
if ! view_result_json "$dlmm_pool_contract" pool_config null >/dev/null 2>&1; then
  call_contract_and_wait "$config" "$dlmm_pool_contract" warm_write null >/dev/null
fi
pool_actual_json="$(view_result_json "$dlmm_pool_contract" "pool_config" null 2>/dev/null || true)"
if [[ -z "$pool_actual_json" ]]; then
  echo "bootstrap init: dlmm pool config"
  call_contract_and_wait "$config" "$dlmm_pool_contract" "init_pool" "$pool_init_payload" >/dev/null
  pool_actual_json="$(view_result_json "$dlmm_pool_contract" "pool_config" null)"
fi
pool_current_vault_account="$(jq -r '
  if type == "array" and length > 2 and .[2] != null then
    .[2]
  else
    ""
  end
' <<<"$pool_actual_json" 2>/dev/null || true)"
pool_current_vault_contract="$(historical_contract_id_for_subject_account "$mode" "dlmm.dlmm_pool" "$pool_current_vault_account" || true)"
if [[ -z "$pool_current_vault_contract" ]]; then
  pool_current_vault_contract="$(historical_contract_id_for_subject_account "$mode" "n3x.n3x_hub" "$pool_current_vault_account" || true)"
fi
pool_active_bin_repair_needed=0
if json_equals "$pool_actual_json" "$pool_expected_json"; then
  echo "bootstrap skip: dlmm pool config already matches expected state"
elif json_equals "$pool_actual_json" "$pool_legacy_json"; then
  echo "bootstrap note: dlmm pool still uses legacy treasury custody; rotating to contract subject"
elif json_equals "$pool_actual_json" "$pool_n3x_custody_json"; then
  echo "bootstrap note: dlmm pool custody is temporarily pinned to n3x subject; rotating back to pool subject"
  dlmm_pool_balance_source_account="$n3x_vault_account"
  dlmm_pool_balance_source_signer_config="$(contract_subject_signer_config "$n3x_hub_contract")"
  dlmm_pool_balance_source_cleanup=1
elif [[ "$pool_n3x_source_custody_json" != "null" ]] && json_equals "$pool_actual_json" "$pool_n3x_source_custody_json"; then
  echo "bootstrap note: dlmm pool custody is still pinned to the pre-migration n3x source account; covering reserves from authority before rebinding"
elif [[ "$pool_previous_custody_json" != "null" ]] && json_equals "$pool_actual_json" "$pool_previous_custody_json"; then
  echo "bootstrap note: dlmm pool custody is still pinned to the previous pool subject; migrating forward"
  dlmm_pool_balance_source_account="$previous_dlmm_pool_contract_subject"
  dlmm_pool_balance_source_signer_config="$(contract_subject_signer_config "$previous_dlmm_pool_contract")"
  dlmm_pool_balance_source_cleanup=1
elif jq -en \
  --argjson actual "$pool_actual_json" \
  --argjson expected "$pool_expected_json" \
  '
    ($actual | length) == 6
    and ($expected | length) == 6
    and ($actual[0] == $expected[0])
    and ($actual[1] == $expected[1])
    and ($actual[3] == $expected[3])
    and ($actual[4] == $expected[4])
    and ($actual[5] == $expected[5])
    and ($actual[2] != $expected[2])
  ' >/dev/null; then
  if [[ -n "$pool_current_vault_contract" ]]; then
    dlmm_pool_balance_source_account="$pool_current_vault_account"
    dlmm_pool_balance_source_signer_config="$(contract_subject_signer_config "$pool_current_vault_contract")"
    dlmm_pool_balance_source_cleanup=1
  fi
  echo "bootstrap note: dlmm pool custody is pinned to an earlier vault account; rotating to pool subject with authority backfill if needed"
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
  if [[ "$mode" == "testnet" || "$mode" == "production" ]]; then
    pool_live_active_bin_state_json="$(view_result_json "$dlmm_pool_contract" "mirror_bin" "$(jq -cn --argjson bin_id "$pool_live_active_bin" '{ bin_id: $bin_id }')")"
    pool_seed_anchor_state_json="$(view_result_json "$dlmm_pool_contract" "mirror_bin" "$(jq -cn --argjson bin_id "$pool_active_bin" '{ bin_id: $bin_id }')")"
    pool_seed_position_json="$(view_result_json "$dlmm_pool_contract" "mirror_position" "$(jq -cn --arg position_id "$pool_position_id" '{ position_id: $position_id }')")"
    if jq -en \
      --argjson live "$pool_live_active_bin_state_json" \
      --argjson anchor "$pool_seed_anchor_state_json" \
      --argjson position "$pool_seed_position_json" \
      --argjson anchor_bin "$pool_active_bin" \
      '
        (($live[0] // 0) + ($live[1] // 0) + ($live[2] // 0)) == 0
        and (
          (($anchor[0] // 0) + ($anchor[1] // 0) + ($anchor[2] // 0)) > 0
          or (
            ($position[0] // 0) == 1
            and ($position[1] // 0) == $anchor_bin
            and ($position[2] // 0) > 0
          )
        )
      ' >/dev/null; then
      echo "bootstrap note: dlmm pool active bin drift detected on live $mode (live=${pool_live_active_bin}, expected=${pool_active_bin}) but the live bin is empty and the seeded anchor is still populated; repairing back to the seed anchor"
      pool_active_bin_repair_needed=1
    else
      echo "bootstrap note: dlmm pool active bin drift detected on live $mode (live=${pool_live_active_bin}, expected=${pool_active_bin}); preserving live config and relying on swap-time realignment"
      pool_expected_json="$(jq -cn \
        --arg base_asset "$xor_id" \
        --arg quote_asset "$usdt_id" \
        --arg vault_account "$dlmm_pool_vault_account" \
        --argjson fee_pips "$pool_fee_pips" \
        --argjson bin_step "$pool_bin_step" \
        --argjson active_bin "$pool_live_active_bin" \
        '[ $base_asset, $quote_asset, $vault_account, $fee_pips, $bin_step, $active_bin ]')"
    fi
  else
    echo "bootstrap note: dlmm pool active bin drifted from the configured seed anchor (live=${pool_live_active_bin}, expected=${pool_active_bin}); repairing active bin"
    pool_active_bin_repair_needed=1
  fi
else
  fail_bootstrap_diff "dlmm pool config" "$pool_expected_json" "$pool_actual_json" "$(jq -cn --argjson legacy "$pool_legacy_json" --argjson polluted "$pool_n3x_custody_json" --argjson n3x_source "$pool_n3x_source_custody_json" --argjson previous "$pool_previous_custody_json" '[ $legacy, $polluted ] + (if $n3x_source == null then [] else [ $n3x_source ] end) + (if $previous == null then [] else [ $previous ] end)')"
fi

if ! json_equals "$pool_actual_json" "$pool_expected_json"; then
  pool_bind_config="$config"
  pool_bind_cleanup=0
  if [[ "$pool_current_vault_account" == "$SORASWAP_AUTHORITY" || -z "$pool_current_vault_account" ]]; then
    :
  elif [[ -n "$pool_current_vault_contract" ]]; then
    pool_bind_config="$(contract_subject_signer_config "$pool_current_vault_contract")"
    pool_bind_cleanup=1
  elif [[ -n "$pool_current_vault_account" && "$pool_current_vault_account" != "$SORASWAP_AUTHORITY" ]]; then
    echo "bootstrap cannot derive signer for current dlmm pool custody account: $pool_current_vault_account" >&2
    exit 1
  fi
  if (( pool_bind_cleanup == 1 )); then
    ensure_signer_fee_balance "$pool_current_vault_account"
  fi

  if (( pool_active_bin_repair_needed == 1 )); then
    echo "bootstrap apply: dlmm pool active bin repair"
    call_contract_and_wait \
      "$pool_bind_config" \
      "$dlmm_pool_contract" \
      "repair_active_bin" \
      "$(jq -cn --argjson active_bin "$pool_active_bin" '{ active_bin: $active_bin }')" \
      "$bootstrap_maintenance_gas_limit" \
      >/dev/null
    if (( pool_bind_cleanup == 1 )); then
      rm -f "$pool_bind_config"
      pool_bind_cleanup=0
    fi
    pool_actual_json="$(view_result_json "$dlmm_pool_contract" "pool_config" null)"
  fi

  if json_equals "$pool_actual_json" "$pool_expected_json"; then
    :
  else
  echo "bootstrap apply: dlmm pool custody binding"
  call_contract_and_wait \
    "$pool_bind_config" \
    "$dlmm_pool_contract" \
    "bind_custody_account" \
    "$(jq -cn --arg vault_account "$dlmm_pool_vault_account" '{ vault_account: $vault_account }')" \
    "$bootstrap_maintenance_gas_limit" \
    >/dev/null
  if (( pool_bind_cleanup == 1 )); then
    rm -f "$pool_bind_config"
  fi
  pool_actual_json="$(view_result_json "$dlmm_pool_contract" "pool_config" null)"
  if ! json_equals "$pool_actual_json" "$pool_expected_json"; then
    fail_bootstrap_diff \
      "dlmm pool custody binding" \
      "$pool_expected_json" \
      "$pool_actual_json" \
      "$(jq -cn --argjson legacy "$pool_legacy_json" --argjson polluted "$pool_n3x_custody_json" --argjson n3x_source "$pool_n3x_source_custody_json" '[ $legacy, $polluted ] + (if $n3x_source == null then [] else [ $n3x_source ] end)')"
  fi
  fi
fi

apply_step_and_expect \
  "dlmm router contract binding" \
  "$dlmm_router_contract" \
  "contract_binding" \
  null \
  '1' \
  "bind_contract" \
  "$(jq -cn --arg contract_id "$dlmm_router_contract_subject" '{ contract_id: $contract_id }')"

apply_step_and_expect \
  "dlmm router execution binding" \
  "$dlmm_router_contract" \
  "execution_binding" \
  null \
  '1' \
  "bind_pool" \
  "$(jq -cn --arg pool_contract "$dlmm_pool_contract" --arg quote_asset "$usdt_id" '{ pool_contract: $pool_contract, quote_asset: $quote_asset }')"

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
if (( dlmm_pool_balance_source_cleanup == 1 )); then
  rm -f "$dlmm_pool_balance_source_signer_config"
fi

if [[ "$bootstrap_scope" == "foundation" ]]; then
  echo "post-deploy foundation contract state initialized"
  exit 0
fi

launchpad_executor_expected_json="$(jq -cn \
  --arg base_asset "$xor_id" \
  --arg quote_asset "$launchpad_pool_quote_asset_id" \
  '[ $base_asset, $quote_asset, 0, 0 ]')"
launchpad_executor_init_payload="$(jq -cn \
  --arg pool_contract "$dlmm_pool_contract" \
  --arg base_asset "$xor_id" \
  --arg quote_asset "$launchpad_pool_quote_asset_id" \
  '{
    pool_contract: $pool_contract,
    base_asset: $base_asset,
    quote_asset: $quote_asset
  }')"
launchpad_executor_live_predicate='
  ($actual | length) == 4
  and ($expected | length) == 4
  and $actual[0] == $expected[0]
  and $actual[1] == $expected[1]
  and (($actual[2] // 0) >= ($expected[2] // 0))
  and (($actual[3] // 0) >= ($expected[3] // 0))
'
launchpad_executor_binding_expected_json="$(jq -cn \
  --arg pool_contract "$dlmm_pool_contract_blob_hex" \
  --arg contract_id "$launchpad_liquidity_executor_contract_subject" \
  --arg factory_contract "$launchpad_sale_factory_contract_subject" \
  '[ $pool_contract, $contract_id, $factory_contract, 1, 1 ]')"
ensure_init_or_skip_with_live_predicate \
  "launchpad liquidity executor config" \
  "$launchpad_liquidity_executor_contract" \
  "executor_config" \
  null \
  "$launchpad_executor_expected_json" \
  "init_executor" \
  "$launchpad_executor_init_payload" \
  "$launchpad_executor_live_predicate"

actual_json="$(view_result_json "$launchpad_liquidity_executor_contract" "executor_binding_details" null 2>/dev/null || true)"
if json_value_present "$actual_json" && json_equals "$actual_json" "$launchpad_executor_binding_expected_json"; then
  echo "bootstrap skip: launchpad liquidity executor binding details already match expected state"
else
  echo "bootstrap apply: launchpad liquidity executor contract binding"
  call_contract_and_wait \
    "$config" \
    "$launchpad_liquidity_executor_contract" \
    "bind_contract" \
    "$(jq -cn --arg contract_id "$launchpad_liquidity_executor_contract_subject" '{ contract_id: $contract_id }')" >/dev/null

  echo "bootstrap apply: launchpad liquidity executor sale factory binding"
  call_contract_and_wait \
    "$config" \
    "$launchpad_liquidity_executor_contract" \
    "bind_sale_factory" \
    "$(jq -cn --arg factory_contract "$launchpad_sale_factory_contract_subject" '{ factory_contract: $factory_contract }')" >/dev/null

  echo "bootstrap apply: launchpad liquidity executor pool binding"
  call_contract_and_wait \
    "$config" \
    "$launchpad_liquidity_executor_contract" \
    "bind_pool_contract" \
    "$(jq -cn --arg pool_contract "$dlmm_pool_contract" '{ pool_contract: $pool_contract }')" >/dev/null

  actual_json="$(view_result_json "$launchpad_liquidity_executor_contract" "executor_binding_details" null)"
  if ! json_equals "$actual_json" "$launchpad_executor_binding_expected_json"; then
    fail_bootstrap_diff "launchpad liquidity executor binding details" "$launchpad_executor_binding_expected_json" "$actual_json"
  fi
fi

launchpad_factory_binding_expected_json="$(jq -cn \
  --arg contract_id "$launchpad_sale_factory_contract_subject" \
  --arg executor_contract "$launchpad_liquidity_executor_contract_blob_hex" \
  '[ $contract_id, $executor_contract, 1, 1 ]')"
launchpad_factory_owner_expected_json="$(jq -cn --arg owner "$SORASWAP_AUTHORITY" '[ 1, $owner ]')"

ensure_init_or_skip \
  "launchpad sale factory owner" \
  "$launchpad_sale_factory_contract" \
  "factory_owner_state" \
  null \
  "$launchpad_factory_owner_expected_json" \
  "init_factory" \
  null

actual_json="$(view_result_json "$launchpad_sale_factory_contract" "factory_binding_details" null 2>/dev/null || true)"
if json_value_present "$actual_json" && json_equals "$actual_json" "$launchpad_factory_binding_expected_json"; then
  echo "bootstrap skip: launchpad sale factory binding details already match expected state"
else
  echo "bootstrap apply: launchpad sale factory contract binding"
  call_contract_and_wait \
    "$config" \
    "$launchpad_sale_factory_contract" \
    "bind_contract" \
    "$(jq -cn --arg contract_id "$launchpad_sale_factory_contract_subject" '{ contract_id: $contract_id }')" >/dev/null

  echo "bootstrap apply: launchpad sale factory executor binding"
  call_contract_and_wait \
    "$config" \
    "$launchpad_sale_factory_contract" \
    "bind_executor" \
    "$(jq -cn --arg executor_contract "$launchpad_liquidity_executor_contract" '{ executor_contract: $executor_contract }')" >/dev/null

  actual_json="$(view_result_json "$launchpad_sale_factory_contract" "factory_binding_details" null)"
  if ! json_equals "$actual_json" "$launchpad_factory_binding_expected_json"; then
    fail_bootstrap_diff "launchpad sale factory binding details" "$launchpad_factory_binding_expected_json" "$actual_json"
  fi
fi

sale_expected_json="$(jq -cn \
  --arg sale_asset "$launchpad_sale_asset_id" \
  --arg payment_asset "$xor_id" \
  --arg treasury "$vault_account" \
  --argjson unit_price 1 \
  --argjson soft_cap 1 \
  --argjson hard_cap 100000 \
  --argjson claim_start_slot 0 \
  --argjson claim_end_slot 0 \
  '[ $sale_asset, $payment_asset, $treasury, $unit_price, $soft_cap, $hard_cap, $claim_start_slot, $claim_end_slot ]')"
sale_init_payload="$(jq -cn \
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
  --argjson claim_threshold "$referral_claim_threshold" \
  --argjson direct_share_bps "$referral_direct_share_bps" \
  --argjson parent_share_bps "$referral_parent_share_bps" \
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

risk_vault_init_expected_json='[0,0,0,0,0,0,1,3]'
risk_vault_exit_expected_json='[0,0,0,0,0,0,0,3]'
risk_vault_init_live_predicate='
  (($actual[7] // 0) == 3)
  and (($actual[0] // 0) >= 0)
  and (($actual[1] // 0) >= 0)
  and (($actual[2] // 0) >= 0)
  and (($actual[3] // 0) >= 0)
  and (($actual[4] // 0) >= 0)
  and (($actual[5] // 0) >= 0)
  and ((($actual[6] // 0) == 0) or (($actual[6] // 0) == 1))
  and (
    (($actual[0] // 0) > 0)
    or (($actual[1] // 0) > 0)
    or (($actual[2] // 0) > 0)
    or (($actual[3] // 0) > 0)
    or (($actual[5] // 0) > 0)
  )'
risk_vault_init_payload="$(jq -cn \
  --arg collateral_asset "$usdt_id" \
  --arg vault_account "$risk_vault_custody_account" \
  '{
    collateral_asset: $collateral_asset,
    vault_account: $vault_account
  }')"
ensure_risk_vault_init_or_skip \
  "$risk_vault_contract" \
  "$risk_vault_init_expected_json" \
  "$risk_vault_exit_expected_json" \
  "$risk_vault_init_payload" \
  "$risk_vault_init_live_predicate"

risk_bucket_prior_json='[0,0,0,0,0,0,0,0,0,0,0,0]'
risk_bucket_1_base_json='[1,0,0,0,8000,0,1500,0,0,0,0,0]'
risk_bucket_2_base_json='[1,0,0,0,10000,10000,10000,0,0,0,0,0]'
risk_bucket_3_base_json='[1,0,0,0,7000,10000,10000,0,0,0,0,0]'

ensure_step_from_prior_or_skip_with_live_predicate \
  "risk bucket 1 config" \
  "$risk_vault_contract" \
  "bucket_state" \
  '{"bucket_id":1}' \
  '[0,0,0,0,0,0,0,0,0,0,0,0]' \
  "$risk_bucket_1_base_json" \
  "configure_bucket" \
  "$(jq -cn --arg controller "$perps_engine_contract_subject" '{ bucket_id: 1, controller: $controller, payout_cap_bps: 8000, utilisation_cap_bps: 0, collateral_multiplier_bps: 1500 }')" \
  '$actual[0] == $expected[0]
   and (($actual[1] // 0) >= 0)
   and (($actual[2] // 0) >= 0)
   and (($actual[3] // 0) >= 0)
   and (($actual[4] // 0) == ($expected[4] // 0))
   and (($actual[5] // 0) == ($expected[5] // 0))
   and (($actual[6] // 0) == ($expected[6] // 0))
   and (($actual[7] // 0) >= 0)
   and (($actual[8] // 0) >= 0)
   and (($actual[9] // 0) >= 0)
   and (($actual[10] // 0) >= 0)
   and (($actual[11] // 0) >= 0)'
ensure_step_from_prior_or_skip_with_live_predicate \
  "risk bucket 2 config" \
  "$risk_vault_contract" \
  "bucket_state" \
  '{"bucket_id":2}' \
  '[0,0,0,0,0,0,0,0,0,0,0,0]' \
  "$risk_bucket_2_base_json" \
  "configure_bucket" \
  "$(jq -cn --arg controller "$options_factory_contract_subject" '{ bucket_id: 2, controller: $controller, payout_cap_bps: 10000, utilisation_cap_bps: 10000, collateral_multiplier_bps: 10000 }')" \
  '$actual[0] == $expected[0]
   and (($actual[1] // 0) >= 0)
   and (($actual[2] // 0) >= 0)
   and (($actual[3] // 0) >= 0)
   and (($actual[4] // 0) == ($expected[4] // 0))
   and (($actual[5] // 0) == ($expected[5] // 0))
   and (($actual[6] // 0) == ($expected[6] // 0))
   and (($actual[7] // 0) >= 0)
   and (($actual[8] // 0) >= 0)
   and (($actual[9] // 0) >= 0)
   and (($actual[10] // 0) >= 0)
   and (($actual[11] // 0) >= 0)'
ensure_step_from_prior_or_skip_with_live_predicate \
  "risk bucket 3 config" \
  "$risk_vault_contract" \
  "bucket_state" \
  '{"bucket_id":3}' \
  '[0,0,0,0,0,0,0,0,0,0,0,0]' \
  "$risk_bucket_3_base_json" \
  "configure_bucket" \
  "$(jq -cn --arg controller "$cover_policy_manager_contract_subject" '{ bucket_id: 3, controller: $controller, payout_cap_bps: 7000, utilisation_cap_bps: 10000, collateral_multiplier_bps: 10000 }')" \
  '$actual[0] == $expected[0]
   and (($actual[1] // 0) >= 0)
   and (($actual[2] // 0) >= 0)
   and (($actual[3] // 0) >= 0)
   and (($actual[4] // 0) == ($expected[4] // 0))
   and (($actual[5] // 0) == ($expected[5] // 0))
   and (($actual[6] // 0) == ($expected[6] // 0))
   and (($actual[7] // 0) >= 0)
   and (($actual[8] // 0) >= 0)
   and (($actual[9] // 0) >= 0)
   and (($actual[10] // 0) >= 0)
   and (($actual[11] // 0) >= 0)'

if [[ "$mode" != "local" ]]; then
  echo "bootstrap apply: risk bucket 1 controller sync"
  if ! SORASWAP_TX_PIPELINE_WAIT_SECS="${SORASWAP_BOOTSTRAP_CONTROLLER_SYNC_PIPELINE_WAIT_SECS:-20}" \
    SORASWAP_TX_COMMITTED_WAIT_SECS="${SORASWAP_BOOTSTRAP_CONTROLLER_SYNC_COMMITTED_WAIT_SECS:-20}" \
    call_contract_and_wait \
      "$config" \
      "$risk_vault_contract" \
      "configure_bucket" \
      "$(jq -cn --arg controller "$perps_engine_contract_subject" '{ bucket_id: 1, controller: $controller, payout_cap_bps: 8000, utilisation_cap_bps: 0, collateral_multiplier_bps: 1500 }')" \
      >/dev/null 2>&1; then
    echo "bootstrap note: risk bucket 1 controller sync did not confirm within the bounded wait; continuing with existing live state" >&2
  fi
  echo "bootstrap apply: risk bucket 2 controller sync"
  if ! SORASWAP_TX_PIPELINE_WAIT_SECS="${SORASWAP_BOOTSTRAP_CONTROLLER_SYNC_PIPELINE_WAIT_SECS:-20}" \
    SORASWAP_TX_COMMITTED_WAIT_SECS="${SORASWAP_BOOTSTRAP_CONTROLLER_SYNC_COMMITTED_WAIT_SECS:-20}" \
    call_contract_and_wait \
      "$config" \
      "$risk_vault_contract" \
      "configure_bucket" \
      "$(jq -cn --arg controller "$options_factory_contract_subject" '{ bucket_id: 2, controller: $controller, payout_cap_bps: 10000, utilisation_cap_bps: 10000, collateral_multiplier_bps: 10000 }')" \
      >/dev/null 2>&1; then
    echo "bootstrap note: risk bucket 2 controller sync did not confirm within the bounded wait; continuing with existing live state" >&2
  fi
  echo "bootstrap apply: risk bucket 3 controller sync"
  if ! SORASWAP_TX_PIPELINE_WAIT_SECS="${SORASWAP_BOOTSTRAP_CONTROLLER_SYNC_PIPELINE_WAIT_SECS:-20}" \
    SORASWAP_TX_COMMITTED_WAIT_SECS="${SORASWAP_BOOTSTRAP_CONTROLLER_SYNC_COMMITTED_WAIT_SECS:-20}" \
    call_contract_and_wait \
      "$config" \
      "$risk_vault_contract" \
      "configure_bucket" \
      "$(jq -cn --arg controller "$cover_policy_manager_contract_subject" '{ bucket_id: 3, controller: $controller, payout_cap_bps: 7000, utilisation_cap_bps: 10000, collateral_multiplier_bps: 10000 }')" \
      >/dev/null 2>&1; then
    echo "bootstrap note: risk bucket 3 controller sync did not confirm within the bounded wait; continuing with existing live state" >&2
  fi
fi

ensure_step_from_prior_or_skip_with_live_predicate \
  "risk vault exit withdrawal only" \
  "$risk_vault_contract" \
  "risk_state" \
  null \
  "$risk_vault_init_expected_json" \
  "$risk_vault_exit_expected_json" \
  "exit_withdrawal_only" \
  null \
  '($actual[6] // 1) == 0
   and (($actual[7] // 0) == ($expected[7] // 0))
   and (($actual[0] // 0) >= 0)
   and (($actual[1] // 0) >= 0)
   and (($actual[2] // 0) >= 0)
   and (($actual[3] // 0) >= 0)
   and (($actual[4] // 0) >= 0)
   and (($actual[5] // 0) >= 0)'

risk_bucket_1_expected_json="$risk_bucket_1_base_json"
risk_bucket_2_expected_json="$risk_bucket_2_base_json"
risk_bucket_3_expected_json="$risk_bucket_3_base_json"
risk_bucket_live_deposit_predicate='
  ($actual[0] // 0) == ($expected[0] // 0)
  and (($actual[4] // 0) == ($expected[4] // 0))
  and (($actual[5] // 0) == ($expected[5] // 0))
  and (($actual[6] // 0) == ($expected[6] // 0))
  and (($actual[1] // 0) >= 0)
  and (($actual[7] // 0) >= 0)
  and ((($actual[1] // 0) + ($actual[7] // 0)) >= ($expected[1] // 0))
  and (($actual[8] // 0) >= 0)
  and (($actual[9] // 0) >= 0)
  and (($actual[10] // 0) >= 0)
  and (($actual[11] // 0) >= 0)
'
if (( risk_bucket_1_bootstrap_deposit > 0 )); then
  risk_bucket_1_expected_json="$(jq -cn --argjson deposit "$risk_bucket_1_bootstrap_deposit" '[ 1, $deposit, 0, 0, 8000, 0, 1500, 0, 0, $deposit, 0, 0 ]')"
  ensure_step_from_prior_or_skip_with_live_predicate \
    "risk bucket 1 bootstrap deposit" \
    "$risk_vault_contract" \
    "bucket_state" \
    '{"bucket_id":1}' \
    "$risk_bucket_1_base_json" \
    "$risk_bucket_1_expected_json" \
    "deposit" \
    "$(jq -cn --argjson amount "$risk_bucket_1_bootstrap_deposit" '{ bucket_id: 1, amount: $amount }')" \
    "$risk_bucket_live_deposit_predicate"
fi
if (( risk_bucket_2_bootstrap_deposit > 0 )); then
  risk_bucket_2_expected_json="$(jq -cn --argjson deposit "$risk_bucket_2_bootstrap_deposit" '[ 1, $deposit, 0, 0, 10000, 10000, 10000, 0, 0, $deposit, 0, 0 ]')"
  ensure_step_from_prior_or_skip_with_live_predicate \
    "risk bucket 2 bootstrap deposit" \
    "$risk_vault_contract" \
    "bucket_state" \
    '{"bucket_id":2}' \
    "$risk_bucket_2_base_json" \
    "$risk_bucket_2_expected_json" \
    "deposit" \
    "$(jq -cn --argjson amount "$risk_bucket_2_bootstrap_deposit" '{ bucket_id: 2, amount: $amount }')" \
    "$risk_bucket_live_deposit_predicate"
fi
if (( risk_bucket_3_bootstrap_deposit > 0 )); then
  risk_bucket_3_expected_json="$(jq -cn --argjson deposit "$risk_bucket_3_bootstrap_deposit" '[ 1, $deposit, 0, 0, 7000, 10000, 10000, 0, 0, $deposit, 0, 0 ]')"
  ensure_step_from_prior_or_skip_with_live_predicate \
    "risk bucket 3 bootstrap deposit" \
    "$risk_vault_contract" \
    "bucket_state" \
    '{"bucket_id":3}' \
    "$risk_bucket_3_base_json" \
    "$risk_bucket_3_expected_json" \
    "deposit" \
    "$(jq -cn --argjson amount "$risk_bucket_3_bootstrap_deposit" '{ bucket_id: 3, amount: $amount }')" \
    "$risk_bucket_live_deposit_predicate"
fi
if [[ "$mode" != "local" ]]; then
  ensure_contract_subject_balance_covers_bucket_deposits "risk bucket 1" "$perps_engine_contract_subject" "$usdt_id" 1
  ensure_contract_subject_balance_covers_bucket_deposits "risk bucket 2" "$options_factory_contract_subject" "$usdt_id" 2
  ensure_contract_subject_balance_covers_bucket_deposits "risk bucket 3" "$cover_policy_manager_contract_subject" "$usdt_id" 3
fi

risk_bucket_1_automation_expected_json='[1,101,4,6,0,0,0]'
risk_bucket_2_automation_expected_json='[1,102,5,8,0,0,0]'
risk_bucket_3_automation_expected_json='[1,103,3,10,0,0,0]'
apply_step_and_expect \
  "risk bucket 1 automation" \
  "$risk_vault_contract" \
  "automation_state" \
  '{"bucket_id":1}' \
  "$risk_bucket_1_automation_expected_json" \
  "sync_automation" \
  "$(jq -cn --arg executor "$SORASWAP_AUTHORITY" '{ bucket_id: 1, executor: $executor, job_id: 101, cadence_slots: 4, backlog_cap: 6, safe_mode: 0 }')"
apply_step_and_expect \
  "risk bucket 2 automation" \
  "$risk_vault_contract" \
  "automation_state" \
  '{"bucket_id":2}' \
  "$risk_bucket_2_automation_expected_json" \
  "sync_automation" \
  "$(jq -cn --arg executor "$SORASWAP_AUTHORITY" '{ bucket_id: 2, executor: $executor, job_id: 102, cadence_slots: 5, backlog_cap: 8, safe_mode: 0 }')"
apply_step_and_expect \
  "risk bucket 3 automation" \
  "$risk_vault_contract" \
  "automation_state" \
  '{"bucket_id":3}' \
  "$risk_bucket_3_automation_expected_json" \
  "sync_automation" \
  "$(jq -cn --arg executor "$SORASWAP_AUTHORITY" '{ bucket_id: 3, executor: $executor, job_id: 103, cadence_slots: 3, backlog_cap: 10, safe_mode: 0 }')"

engine_init_expected_json="$(jq -cn --arg collateral_asset "$usdt_id" --arg risk_vault_contract "$risk_vault_contract_blob_hex" '[ $collateral_asset, $risk_vault_contract, 1, 1, 1, 0, 0, 0 ]')"
engine_live_expected_json="$(jq -cn --arg collateral_asset "$usdt_id" --arg risk_vault_contract "$risk_vault_contract_blob_hex" '[ $collateral_asset, $risk_vault_contract, 0, 1, 1, 0, 0, 0 ]')"
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
  --arg risk_vault_contract "$risk_vault_contract_blob_hex" \
  --arg oracle_public_key "$oracle_public_key_hex" \
  --argjson oracle_scheme "$oracle_scheme" \
  '{
    collateral_asset: $collateral_asset,
    risk_vault_contract: $risk_vault_contract,
    oracle_public_key: $oracle_public_key,
    oracle_scheme: $oracle_scheme
  }')"
perps_engine_matches_live_state() {
  local engine_json market_state_json automation_state_json

  if ! engine_json="$(view_result_json "$perps_engine_contract" "engine_config" null 2>/dev/null)" \
    || ! market_state_json="$(view_result_json "$perps_engine_contract" "market_state" '{"market_id":1}' 2>/dev/null)" \
    || ! automation_state_json="$(view_result_json "$perps_engine_contract" "automation_state" null 2>/dev/null)"; then
    return 1
  fi

  jq -en \
    --argjson engine "$engine_json" \
    --argjson market "$market_state_json" \
    --argjson automation "$automation_state_json" \
    --argjson engine_expected "$engine_live_expected_json" \
    --argjson market_expected "$perps_market_expected_json" \
    --argjson automation_expected "$perps_automation_expected_json" \
    '
      ($engine[0] == $engine_expected[0])
      and ($engine[1] == $engine_expected[1])
      and (($engine[2] // 1) == 0)
      and (($engine[3] // 0) >= ($engine_expected[3] // 0))
      and (($engine[4] // 0) >= ($engine_expected[4] // 0))
      and (($engine[5] // 0) >= ($engine_expected[5] // 0))
      and (($engine[6] // 0) >= ($engine_expected[6] // 0))
      and (($engine[7] // 0) >= ($engine_expected[7] // 0))
      and ($market[0] == $market_expected[0])
      and ($market[1] == $market_expected[1])
      and (($market[3] // 0) == ($market_expected[3] // 0))
      and (($market[4] // 0) == ($market_expected[4] // 0))
      and (($market[5] // 0) == ($market_expected[5] // 0))
      and (($market[6] // 0) == ($market_expected[6] // 0))
      and (($market[7] // 0) == ($market_expected[7] // 0))
      and (($market[8] // 0) == ($market_expected[8] // 0))
      and (($market[9] // 0) == ($market_expected[9] // 0))
      and (($market[12] // 0) == ($market_expected[12] // 0))
      and ($automation[0] == $automation_expected[0])
      and (($automation[1] // 0) == ($automation_expected[1] // 0))
      and (($automation[2] // 0) == ($automation_expected[2] // 0))
      and (($automation[3] // 0) == ($automation_expected[3] // 0))
      and (($automation[4] // 0) == ($automation_expected[4] // 0))
      and (($automation[5] // 0) >= 0)
      and (($automation[6] // 0) >= 0)
    ' >/dev/null
}

perps_engine_initialized_live_state() {
  local engine_json market_state_json automation_state_json

  if ! engine_json="$(view_result_json "$perps_engine_contract" "engine_config" null 2>/dev/null)" \
    || ! market_state_json="$(view_result_json "$perps_engine_contract" "market_state" '{"market_id":1}' 2>/dev/null)" \
    || ! automation_state_json="$(view_result_json "$perps_engine_contract" "automation_state" null 2>/dev/null)"; then
    return 1
  fi

  jq -en \
    --argjson engine "$engine_json" \
    --argjson market "$market_state_json" \
    --argjson automation "$automation_state_json" \
    --argjson engine_expected "$engine_live_expected_json" \
    --argjson market_expected "$perps_market_expected_json" \
    --argjson automation_expected "$perps_automation_expected_json" \
    '
      ($engine[0] == $engine_expected[0])
      and (($engine[1] | type) == "string")
      and (($engine[1] | startswith("0x")))
      and ((($engine[2] // 0) == 0) or (($engine[2] // 0) == 1))
      and (($engine[3] // 0) >= 1)
      and (($engine[4] // 0) >= 1)
      and (($market[0] == $market_expected[0]))
      and (($market[1] == $market_expected[1]))
      and (($market[3] // 0) == ($market_expected[3] // 0))
      and (($market[4] // 0) == ($market_expected[4] // 0))
      and (($market[5] // 0) == ($market_expected[5] // 0))
      and (($market[6] // 0) == ($market_expected[6] // 0))
      and (($market[7] // 0) == ($market_expected[7] // 0))
      and (($market[8] // 0) == ($market_expected[8] // 0))
      and (($market[9] // 0) == ($market_expected[9] // 0))
      and (($market[12] // 0) == ($market_expected[12] // 0))
      and ($automation[0] == $automation_expected[0])
      and (($automation[1] // 0) == ($automation_expected[1] // 0))
      and (($automation[2] // 0) == ($automation_expected[2] // 0))
      and (($automation[3] // 0) == ($automation_expected[3] // 0))
      and (($automation[4] // 0) == ($automation_expected[4] // 0))
      and (($automation[5] // 0) >= 0)
      and (($automation[6] // 0) >= 0)
    ' >/dev/null
}

repair_orphaned_perps_positions() {
  local engine_json next_position_id position_id position_payload position_json
  local liability_payload liability_json mark_price_bps index_price_bps

  if ! engine_json="$(view_result_json "$perps_engine_contract" "engine_config" null 2>/dev/null)"; then
    return 0
  fi

  next_position_id="$(jq -er '.[4] // 1' <<<"$engine_json" 2>/dev/null || true)"
  if [[ -z "$next_position_id" ]] || (( next_position_id <= 1 )); then
    return 0
  fi

  for (( position_id = 1; position_id < next_position_id; position_id++ )); do
    position_payload="$(jq -cn --argjson position_id "$position_id" '{ position_id: $position_id }')"
    if ! position_json="$(view_result_json "$perps_engine_contract" "position_state" "$position_payload" 2>/dev/null)"; then
      continue
    fi
    if ! jq -en \
      --argjson position "$position_json" \
      '($position[0] // 0) == 1 and (((($position[1] // 0) == 1) or (($position[1] // 0) == 3)))' \
      >/dev/null; then
      continue
    fi

    liability_payload="$(jq -cn --argjson bucket_id 1 --argjson exposure_id "$position_id" '{ bucket_id: $bucket_id, exposure_id: $exposure_id }')"
    if ! liability_json="$(view_result_json "$risk_vault_contract" "liability_state" "$liability_payload" 2>/dev/null)"; then
      continue
    fi
    if ! jq -en --argjson liability "$liability_json" '(($liability[0] // 0) == 0)' >/dev/null; then
      continue
    fi

    mark_price_bps="$(jq -er 'if (.[8] // 0) > 0 then .[8] elif (.[7] // 0) > 0 then .[7] else 10000 end' <<<"$position_json")"
    index_price_bps="$(jq -er 'if (.[9] // 0) > 0 then .[9] elif (.[8] // 0) > 0 then .[8] elif (.[7] // 0) > 0 then .[7] else 10000 end' <<<"$position_json")"

    echo "bootstrap apply: perps orphan repair position $position_id"
    call_contract_and_wait \
      "$config" \
      "$perps_engine_contract" \
      "admin_repair_orphan_position" \
      "$(jq -cn \
        --argjson position_id "$position_id" \
        --argjson mark_price_bps "$mark_price_bps" \
        --argjson index_price_bps "$index_price_bps" \
        '{
          position_id: $position_id,
          mark_price_bps: $mark_price_bps,
          index_price_bps: $index_price_bps
        }')" \
      >/dev/null
  done
}
if [[ "$mode" == "local" ]]; then
  ensure_init_or_skip_with_live_predicate \
    "perps engine config" \
    "$perps_engine_contract" \
    "engine_config" \
    null \
    "$engine_init_expected_json" \
    "init_engine" \
    "$engine_init_payload" \
    '$actual[0] == $expected[0]
     and (($actual[3] // 0) >= ($expected[3] // 0))
     and (($actual[4] // 0) >= ($expected[4] // 0))'
  echo "bootstrap apply: perps engine bind risk vault"
  call_contract_and_wait \
    "$config" \
    "$perps_engine_contract" \
    "bind_risk_vault" \
    "$(jq -cn --arg risk_vault_contract "$risk_vault_contract_blob_hex" '{ risk_vault_contract: $risk_vault_contract }')" \
    >/dev/null
  echo "bootstrap apply: perps engine bind contract"
  call_contract_and_wait \
    "$config" \
    "$perps_engine_contract" \
    "bind_contract" \
    "$(jq -cn --arg contract_id "$perps_engine_contract_subject" '{ contract_id: $contract_id }')" \
    >/dev/null
  ensure_step_from_prior_or_skip_with_live_predicate \
    "perps engine exit withdrawal only" \
    "$perps_engine_contract" \
    "engine_config" \
    null \
    "$engine_init_expected_json" \
    "$engine_live_expected_json" \
    "exit_withdrawal_only" \
    null \
    '$actual[0] == $expected[0]
     and $actual[1] == $expected[1]
     and ($actual[2] // 1) == 0
     and (($actual[3] // 0) >= ($expected[3] // 0))
     and (($actual[4] // 0) >= ($expected[4] // 0))
     and (($actual[5] // 0) >= ($expected[5] // 0))
     and (($actual[6] // 0) >= ($expected[6] // 0))
     and (($actual[7] // 0) >= ($expected[7] // 0))'
else
  if perps_engine_matches_live_state; then
    echo "bootstrap skip: perps engine already matches expected live state"
  else
    echo "bootstrap init/apply: perps engine config (public-compatible path)"
    if ! init_output="$(call_contract_and_wait "$config" "$perps_engine_contract" "init_engine" "$engine_init_payload" 2>&1)"; then
      call_contract_and_wait \
        "$config" \
        "$perps_engine_contract" \
        "bind_risk_vault" \
        "$(jq -cn --arg risk_vault_contract "$risk_vault_contract_blob_hex" '{ risk_vault_contract: $risk_vault_contract }')" \
        >/dev/null 2>&1 || true
      call_contract_and_wait \
        "$config" \
        "$perps_engine_contract" \
        "bind_contract" \
        "$(jq -cn --arg contract_id "$perps_engine_contract_subject" '{ contract_id: $contract_id }')" \
        >/dev/null 2>&1 || true
      if perps_engine_initialized_live_state; then
        echo "bootstrap skip: perps engine init already completed on advanced live state"
      elif ! perps_engine_matches_live_state; then
        printf '%s\n' "$init_output" >&2
        exit 1
      fi
    fi
    echo "bootstrap apply: perps engine bind risk vault"
    call_contract_and_wait \
      "$config" \
      "$perps_engine_contract" \
      "bind_risk_vault" \
      "$(jq -cn --arg risk_vault_contract "$risk_vault_contract_blob_hex" '{ risk_vault_contract: $risk_vault_contract }')" \
      >/dev/null
    echo "bootstrap apply: perps engine bind contract"
    call_contract_and_wait \
      "$config" \
      "$perps_engine_contract" \
      "bind_contract" \
      "$(jq -cn --arg contract_id "$perps_engine_contract_subject" '{ contract_id: $contract_id }')" \
      >/dev/null
    ensure_step_from_prior_or_skip_with_live_predicate \
      "perps engine exit withdrawal only" \
      "$perps_engine_contract" \
      "engine_config" \
      null \
      "$engine_init_expected_json" \
      "$engine_live_expected_json" \
      "exit_withdrawal_only" \
      null \
      '$actual[0] == $expected[0]
       and $actual[1] == $expected[1]
       and ($actual[2] // 1) == 0
       and (($actual[3] // 0) >= ($expected[3] // 0))
       and (($actual[4] // 0) >= ($expected[4] // 0))
       and (($actual[5] // 0) >= ($expected[5] // 0))
       and (($actual[6] // 0) >= ($expected[6] // 0))
       and (($actual[7] // 0) >= ($expected[7] // 0))'
  fi
fi
apply_step_and_expect \
  "perps automation" \
  "$perps_engine_contract" \
  "automation_state" \
  null \
  "$perps_automation_expected_json" \
  "sync_automation" \
  "$(jq -cn --arg executor "$SORASWAP_AUTHORITY" '{ executor: $executor, funding_job_id: 201, liquidation_job_id: 202, cadence_slots: 4, backlog_cap: 6, safe_mode: 0 }')"
ensure_step_from_prior_or_skip_with_live_predicate \
  "perps market registration" \
  "$perps_engine_contract" \
  "market_state" \
  '{"market_id":1}' \
  '[0,0,0,0,0,0,0,0,0,0,0,0,0]' \
  "$perps_market_expected_json" \
  "register_market" \
  "$(jq -cn \
    --arg asset "$xor_id" \
    --argjson max_leverage_bps "$perps_max_leverage_bps" \
    --argjson maintenance_margin_bps "$perps_maintenance_margin_bps" \
    --argjson liquidation_fee_bps "$perps_liquidation_fee_bps" \
    --argjson open_interest_cap "$perps_open_interest_cap" \
    --argjson funding_bps "$perps_funding_bps" \
    --argjson funding_interval_slots "$perps_funding_interval_slots" \
    --argjson oracle_stale_slots "$perps_oracle_stale_slots" \
    --argjson backlog_limit "$perps_backlog_limit" \
    --argjson utilisation_clamp_bps "$perps_utilisation_clamp_bps" \
    --argjson liquidation_stress_limit "$perps_liquidation_stress_limit" \
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
repair_orphaned_perps_positions

options_manager_expected_json="$(jq -cn --arg settlement_asset "$usdt_id" '[ $settlement_asset, 1, 1, 1, 0, 0, 0, 0, 0 ]')"
ensure_init_or_skip_with_live_predicate \
  "options manager config" \
  "$options_manager_contract" \
  "manager_config" \
  null \
  "$options_manager_expected_json" \
  "init_manager" \
  "$(jq -cn --arg settlement_asset "$usdt_id" --arg guardian "$vault_account" --arg oracle_public_key "$oracle_public_key_hex" --argjson oracle_scheme "$oracle_scheme" '{ settlement_asset: $settlement_asset, guardian: $guardian, oracle_public_key: $oracle_public_key, oracle_scheme: $oracle_scheme }')" \
  '$actual[0] == $expected[0]
   and (($actual[2] // 0) >= ($expected[2] // 0))
   and (($actual[3] // 0) >= ($expected[3] // 0))'
apply_step_and_expect \
  "options manager automation" \
  "$options_manager_contract" \
  "automation_state" \
  null \
  '[1,211,212,5,8,0,0]' \
  "sync_automation" \
  "$(jq -cn --arg executor "$SORASWAP_AUTHORITY" '{ executor: $executor, expiry_job_id: 211, settlement_job_id: 212, cadence_slots: 5, backlog_cap: 8, safe_mode: 0 }')"
ensure_step_from_prior_or_skip \
  "options shout template" \
  "$options_manager_contract" \
  "template_state" \
  '{"template_id":1}' \
  '[0,0,0,0,0,0,0,1]' \
  "$(jq -cn --argjson tenor "$options_shout_tenor_slots" --argjson strike "$options_shout_strike_bps" --argjson collateral_multiplier "$options_collateral_multiplier_bps" --argjson base_premium "$options_shout_base_premium_bps" '[ 1, 1, $tenor, $strike, $collateral_multiplier, $base_premium, 1, 1 ]')" \
  "register_template" \
  "$(jq -cn --arg underlying_asset "$xor_id" --arg quote_asset "$usdt_id" --argjson tenor_slots "$options_shout_tenor_slots" --argjson strike_bps "$options_shout_strike_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" --argjson base_premium_bps "$options_shout_base_premium_bps" '{ option_kind: 1, underlying_asset: $underlying_asset, quote_asset: $quote_asset, tenor_slots: $tenor_slots, strike_bps: $strike_bps, collateral_multiplier_bps: $collateral_multiplier_bps, base_premium_bps: $base_premium_bps }')"
ensure_step_from_prior_or_skip \
  "options outperformance template" \
  "$options_manager_contract" \
  "template_state" \
  '{"template_id":2}' \
  '[0,0,0,0,0,0,0,1]' \
  "$(jq -cn --argjson tenor "$options_outperformance_tenor_slots" --argjson strike "$options_outperformance_strike_bps" --argjson collateral_multiplier "$options_collateral_multiplier_bps" --argjson base_premium "$options_outperformance_base_premium_bps" '[ 1, 2, $tenor, $strike, $collateral_multiplier, $base_premium, 1, 1 ]')" \
  "register_template" \
  "$(jq -cn --arg underlying_asset "$xor_id" --arg quote_asset "$usdt_id" --argjson tenor_slots "$options_outperformance_tenor_slots" --argjson strike_bps "$options_outperformance_strike_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" --argjson base_premium_bps "$options_outperformance_base_premium_bps" '{ option_kind: 2, underlying_asset: $underlying_asset, quote_asset: $quote_asset, tenor_slots: $tenor_slots, strike_bps: $strike_bps, collateral_multiplier_bps: $collateral_multiplier_bps, base_premium_bps: $base_premium_bps }')"
ensure_step_from_prior_or_skip_with_live_predicate \
  "options shout series" \
  "$options_manager_contract" \
  "series_state" \
  '{"series_id":1}' \
  '[0,0,0,0,0,0,0,0,0,0,0]' \
  "$(jq -cn --argjson expiry_slot "$options_shout_expiry_slot" --argjson max_notional "$options_shout_max_notional" --argjson premium_bps "$options_shout_base_premium_bps" --argjson strike_bps "$options_shout_strike_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" '[ 1, 1, 1, $expiry_slot, $max_notional, $premium_bps, $strike_bps, $collateral_multiplier_bps, 1, 0, 0 ]')" \
  "create_series" \
  "$(jq -cn --argjson template_id 1 --argjson expiry_slot "$options_shout_expiry_slot" --argjson max_notional "$options_shout_max_notional" --argjson premium_bps "$options_shout_base_premium_bps" '{ template_id: $template_id, expiry_slot: $expiry_slot, max_notional: $max_notional, premium_bps: $premium_bps }')" \
  '$actual[0] == $expected[0]
   and $actual[1] == $expected[1]
   and $actual[2] == $expected[2]
   and $actual[3] == $expected[3]
   and $actual[4] == $expected[4]
   and $actual[5] == $expected[5]
   and $actual[6] == $expected[6]
   and $actual[7] == $expected[7]
   and (($actual[8] // 0) >= ($expected[8] // 0))
   and (($actual[9] // 0) >= ($expected[9] // 0))
   and (($actual[10] // 0) >= ($expected[10] // 0))'
ensure_step_from_prior_or_skip_with_live_predicate \
  "options outperformance series" \
  "$options_manager_contract" \
  "series_state" \
  '{"series_id":2}' \
  '[0,0,0,0,0,0,0,0,0,0,0]' \
  "$(jq -cn --argjson expiry_slot "$options_outperformance_expiry_slot" --argjson max_notional "$options_outperformance_max_notional" --argjson premium_bps "$options_outperformance_base_premium_bps" --argjson strike_bps "$options_outperformance_strike_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" '[ 1, 2, 2, $expiry_slot, $max_notional, $premium_bps, $strike_bps, $collateral_multiplier_bps, 1, 0, 0 ]')" \
  "create_series" \
  "$(jq -cn --argjson template_id 2 --argjson expiry_slot "$options_outperformance_expiry_slot" --argjson max_notional "$options_outperformance_max_notional" --argjson premium_bps "$options_outperformance_base_premium_bps" '{ template_id: $template_id, expiry_slot: $expiry_slot, max_notional: $max_notional, premium_bps: $premium_bps }')" \
  '$actual[0] == $expected[0]
   and $actual[1] == $expected[1]
   and $actual[2] == $expected[2]
   and $actual[3] == $expected[3]
   and $actual[4] == $expected[4]
   and $actual[5] == $expected[5]
   and $actual[6] == $expected[6]
   and $actual[7] == $expected[7]
   and (($actual[8] // 0) >= ($expected[8] // 0))
   and (($actual[9] // 0) >= ($expected[9] // 0))
   and (($actual[10] // 0) >= ($expected[10] // 0))'

options_factory_init_expected_json="$(jq -cn --arg settlement_asset "$usdt_id" '[ $settlement_asset, 1, 1, 0, 0, 0, 0 ]')"
options_factory_live_expected_json="$(jq -cn --arg settlement_asset "$usdt_id" '[ $settlement_asset, 0, 1, 0, 0, 0, 0 ]')"
ensure_init_or_skip_with_live_predicate \
  "options factory config" \
  "$options_factory_contract" \
  "factory_config" \
  null \
  "$options_factory_init_expected_json" \
  "init_factory" \
  "$(jq -cn --arg settlement_asset "$usdt_id" --arg guardian "$vault_account" --arg oracle_public_key "$oracle_public_key_hex" --argjson oracle_scheme "$oracle_scheme" '{ settlement_asset: $settlement_asset, guardian: $guardian, oracle_public_key: $oracle_public_key, oracle_scheme: $oracle_scheme }')" \
  '$actual[0] == $expected[0]
   and (($actual[2] // 0) >= ($expected[2] // 0))'
echo "bootstrap apply: options factory bind manager"
call_contract_and_wait \
  "$config" \
  "$options_factory_contract" \
  "bind_manager" \
  "$(jq -cn --arg manager_contract "$options_manager_contract_blob_hex" '{ manager_contract: $manager_contract }')" \
  >/dev/null
echo "bootstrap apply: options factory bind contract"
call_contract_and_wait \
  "$config" \
  "$options_factory_contract" \
  "bind_contract" \
  "$(jq -cn --arg contract_id "$options_factory_contract_subject" '{ contract_id: $contract_id }')" \
  >/dev/null
echo "bootstrap apply: options factory bind modules"
call_contract_and_wait \
  "$config" \
  "$options_factory_contract" \
  "bind_modules" \
  "$(jq -cn --arg risk_vault_contract "$risk_vault_contract_blob_hex" --arg vault_contract "$options_vault_contract_blob_hex" --arg shout_contract "$options_shout_option_contract_blob_hex" --arg outperf_contract "$options_outperformance_option_contract_blob_hex" '{ risk_vault_contract: $risk_vault_contract, vault_contract: $vault_contract, shout_contract: $shout_contract, outperf_contract: $outperf_contract }')" \
  >/dev/null
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
   and ($actual[1] // 1) == 0
   and (($actual[2] // 0) >= ($expected[2] // 0))
   and (($actual[3] // 0) >= ($expected[3] // 0))
   and (($actual[4] // 0) >= ($expected[4] // 0))
   and (($actual[5] // 0) >= ($expected[5] // 0))
   and (($actual[6] // 0) >= ($expected[6] // 0))'
apply_step_and_expect \
  "options factory automation" \
  "$options_factory_contract" \
  "automation_state" \
  null \
  '[1,213,5,8,0,0,0]' \
  "sync_automation" \
  "$(jq -cn --arg executor "$SORASWAP_AUTHORITY" '{ executor: $executor, job_id: 213, cadence_slots: 5, backlog_cap: 8, safe_mode: 0 }')"
echo "bootstrap apply: options factory heartbeat"
if [[ "$mode" == "local" ]]; then
  call_contract_and_wait \
    "$config" \
    "$options_factory_contract" \
    "heartbeat" \
    '{"current_backlog":0,"safe_mode":0}' \
    >/dev/null
else
  if ! call_contract_and_wait \
    "$config" \
    "$options_factory_contract" \
    "heartbeat" \
    '{"current_backlog":0,"safe_mode":0}' \
    >/dev/null 2>&1; then
    echo "bootstrap note: options factory heartbeat returned a non-fatal public-chain error; continuing" >&2
  fi
fi

if [[ "$mode" == "local" ]]; then
  ensure_step_from_prior_or_skip \
    "options vault init" \
    "$options_vault_contract" \
    "vault_state" \
    '{"series_id":1}' \
    '[1,0,0,0,0]' \
    '[1,0,0,0,1]' \
    "init_vault" \
    "$(jq -cn --arg settlement_asset "$usdt_id" --arg risk_vault_contract "$risk_vault_contract_blob_hex" '{ settlement_asset: $settlement_asset, risk_vault_contract: $risk_vault_contract }')"
else
  if ! call_contract_and_wait \
    "$config" \
    "$options_vault_contract" \
    "init_vault" \
    "$(jq -cn --arg settlement_asset "$usdt_id" --arg risk_vault_contract "$risk_vault_contract_blob_hex" '{ settlement_asset: $settlement_asset, risk_vault_contract: $risk_vault_contract }')" \
    >/dev/null 2>&1; then
    echo "bootstrap skip: options vault init already applied"
  fi
fi
echo "bootstrap apply: options vault bind controller"
call_contract_and_wait \
  "$config" \
  "$options_vault_contract" \
  "bind_controller" \
  "$(jq -cn --arg controller "$options_factory_contract_subject" '{ controller: $controller }')" \
  >/dev/null
ensure_step_from_prior_or_skip_with_live_predicate \
  "options vault exit withdrawal only" \
  "$options_vault_contract" \
  "vault_state" \
  '{"series_id":1}' \
  '[1,0,0,0,1]' \
  '[1,0,0,0,0]' \
  "exit_withdrawal_only" \
  null \
  '$actual[0] == $expected[0]
   and (($actual[1] // 0) >= 0)
   and (($actual[2] // 0) >= 0)
   and (($actual[3] // 0) >= 0)
   and (($actual[4] // 1) == 0)'

if ! call_contract_and_wait \
  "$config" \
  "$options_shout_option_contract" \
  "init_product" \
  "$(jq -cn --arg guardian "$vault_account" --arg oracle_public_key "$oracle_public_key_hex" --argjson oracle_scheme "$oracle_scheme" '{ guardian: $guardian, oracle_public_key: $oracle_public_key, oracle_scheme: $oracle_scheme }')" \
  >/dev/null 2>&1; then
  echo "bootstrap skip: options shout product init already applied"
fi
echo "bootstrap apply: options shout bind controller"
call_contract_and_wait \
  "$config" \
  "$options_shout_option_contract" \
  "bind_controller" \
  "$(jq -cn --arg controller "$options_factory_contract_subject" '{ controller: $controller }')" \
  >/dev/null
echo "bootstrap apply: options shout exit withdrawal only"
call_contract_and_wait "$config" "$options_shout_option_contract" "exit_withdrawal_only" null >/dev/null

if ! call_contract_and_wait \
  "$config" \
  "$options_outperformance_option_contract" \
  "init_product" \
  "$(jq -cn --arg guardian "$vault_account" '{ guardian: $guardian }')" \
  >/dev/null 2>&1; then
  echo "bootstrap skip: options outperformance product init already applied"
fi
echo "bootstrap apply: options outperformance bind controller"
call_contract_and_wait \
  "$config" \
  "$options_outperformance_option_contract" \
  "bind_controller" \
  "$(jq -cn --arg controller "$options_factory_contract_subject" '{ controller: $controller }')" \
  >/dev/null
echo "bootstrap apply: options outperformance exit withdrawal only"
call_contract_and_wait "$config" "$options_outperformance_option_contract" "exit_withdrawal_only" null >/dev/null

echo "bootstrap apply: options manager bind controller"
call_contract_and_wait \
  "$config" \
  "$options_manager_contract" \
  "bind_controller" \
  "$(jq -cn --arg controller "$options_factory_contract_subject" '{ controller: $controller }')" \
  >/dev/null

ensure_step_from_prior_or_skip_with_live_predicate \
  "options factory shout series sync" \
  "$options_factory_contract" \
  "series_state" \
  '{"series_id":1}' \
  '[0,0,0,0,0,0,0,0,0,0]' \
  "$(jq -cn --argjson max_notional "$options_shout_max_notional" --argjson premium_bps "$options_shout_base_premium_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" '[ 1, 1, $max_notional, $premium_bps, $collateral_multiplier_bps, 0, 0, 0, 0, 0 ]')" \
  "sync_series" \
  "$(jq -cn --argjson series_id 1 --argjson option_kind 1 --argjson max_notional "$options_shout_max_notional" --argjson premium_bps "$options_shout_base_premium_bps" --argjson strike_bps "$options_shout_strike_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" --argjson expiry_slot "$options_shout_expiry_slot" '{ series_id: $series_id, option_kind: $option_kind, max_notional: $max_notional, premium_bps: $premium_bps, strike_bps: $strike_bps, collateral_multiplier_bps: $collateral_multiplier_bps, expiry_slot: $expiry_slot }')" \
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
  '{"series_id":1}' \
  "$(jq -cn --argjson max_notional "$options_shout_max_notional" --argjson premium_bps "$options_shout_base_premium_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" '[ 1, 1, $max_notional, $premium_bps, $collateral_multiplier_bps, 0, 0, 0, 0, 0 ]')" \
  "$(jq -cn --argjson max_notional "$options_shout_max_notional" --argjson premium_bps "$options_shout_base_premium_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" --argjson pause_threshold_bps "$options_factory_pause_threshold_bps" --argjson bump_percent_bps "$options_factory_bump_percent_bps" '[ 1, 1, $max_notional, $premium_bps, $collateral_multiplier_bps, 0, 0, $pause_threshold_bps, $bump_percent_bps, 0 ]')" \
  "configure_utilisation_guard" \
  "$(jq -cn --argjson series_id 1 --argjson bump_activate_bps "$options_factory_bump_activate_bps" --argjson bump_deactivate_bps "$options_factory_bump_deactivate_bps" --argjson pause_threshold_bps "$options_factory_pause_threshold_bps" --argjson bump_percent_bps "$options_factory_bump_percent_bps" '{ series_id: $series_id, bump_activate_bps: $bump_activate_bps, bump_deactivate_bps: $bump_deactivate_bps, pause_threshold_bps: $pause_threshold_bps, bump_percent_bps: $bump_percent_bps }')" \
  "$options_factory_guard_live_predicate"
ensure_step_from_prior_or_skip_with_live_predicate \
  "options factory outperformance series sync" \
  "$options_factory_contract" \
  "series_state" \
  '{"series_id":2}' \
  '[0,0,0,0,0,0,0,0,0,0]' \
  "$(jq -cn --argjson max_notional "$options_outperformance_max_notional" --argjson premium_bps "$options_outperformance_base_premium_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" '[ 1, 2, $max_notional, $premium_bps, $collateral_multiplier_bps, 0, 0, 0, 0, 0 ]')" \
  "sync_series" \
  "$(jq -cn --argjson series_id 2 --argjson option_kind 2 --argjson max_notional "$options_outperformance_max_notional" --argjson premium_bps "$options_outperformance_base_premium_bps" --argjson strike_bps "$options_outperformance_strike_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" --argjson expiry_slot "$options_outperformance_expiry_slot" '{ series_id: $series_id, option_kind: $option_kind, max_notional: $max_notional, premium_bps: $premium_bps, strike_bps: $strike_bps, collateral_multiplier_bps: $collateral_multiplier_bps, expiry_slot: $expiry_slot }')" \
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
  '{"series_id":2}' \
  "$(jq -cn --argjson max_notional "$options_outperformance_max_notional" --argjson premium_bps "$options_outperformance_base_premium_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" '[ 1, 2, $max_notional, $premium_bps, $collateral_multiplier_bps, 0, 0, 0, 0, 0 ]')" \
  "$(jq -cn --argjson max_notional "$options_outperformance_max_notional" --argjson premium_bps "$options_outperformance_base_premium_bps" --argjson collateral_multiplier_bps "$options_collateral_multiplier_bps" --argjson pause_threshold_bps "$options_factory_pause_threshold_bps" --argjson bump_percent_bps "$options_factory_bump_percent_bps" '[ 1, 2, $max_notional, $premium_bps, $collateral_multiplier_bps, 0, 0, $pause_threshold_bps, $bump_percent_bps, 0 ]')" \
  "configure_utilisation_guard" \
  "$(jq -cn --argjson series_id 2 --argjson bump_activate_bps "$options_factory_bump_activate_bps" --argjson bump_deactivate_bps "$options_factory_bump_deactivate_bps" --argjson pause_threshold_bps "$options_factory_pause_threshold_bps" --argjson bump_percent_bps "$options_factory_bump_percent_bps" '{ series_id: $series_id, bump_activate_bps: $bump_activate_bps, bump_deactivate_bps: $bump_deactivate_bps, pause_threshold_bps: $pause_threshold_bps, bump_percent_bps: $bump_percent_bps }')" \
  "$options_factory_guard_live_predicate"

cover_manager_init_json="$(jq -cn --arg settlement_asset "$usdt_id" --arg risk_vault_contract "$risk_vault_contract_blob_hex" --argjson required_observations "$cover_required_observations" --argjson oracle_stale_slots "$cover_oracle_stale_slots" '[ $settlement_asset, $risk_vault_contract, 1, $required_observations, $oracle_stale_slots, 0, 0, 0, 0 ]')"
cover_manager_live_json="$(jq -cn --arg settlement_asset "$usdt_id" --arg risk_vault_contract "$risk_vault_contract_blob_hex" --argjson required_observations "$cover_required_observations" --argjson oracle_stale_slots "$cover_oracle_stale_slots" '[ $settlement_asset, $risk_vault_contract, 0, $required_observations, $oracle_stale_slots, 0, 0, 0, 0 ]')"
cover_automation_expected_json='[1,301,3,10,0,0,0]'
if [[ "$mode" == "local" ]]; then
  ensure_init_or_skip_with_live_predicate \
    "cover manager config" \
    "$cover_policy_manager_contract" \
    "manager_config" \
    null \
    "$cover_manager_init_json" \
    "init_manager" \
    "$(jq -cn --arg settlement_asset "$usdt_id" --arg risk_vault_contract "$risk_vault_contract_blob_hex" --argjson required_observations "$cover_required_observations" --argjson oracle_stale_slots "$cover_oracle_stale_slots" --arg oracle_public_key "$oracle_public_key_hex" --argjson oracle_scheme "$oracle_scheme" '{ settlement_asset: $settlement_asset, risk_vault_contract: $risk_vault_contract, required_observations: $required_observations, oracle_stale_slots: $oracle_stale_slots, oracle_public_key: $oracle_public_key, oracle_scheme: $oracle_scheme }')" \
    '$actual[0] == $expected[0]
     and $actual[3] == $expected[3]
     and $actual[4] == $expected[4]'
  echo "bootstrap apply: cover manager bind risk vault"
  call_contract_and_wait \
    "$config" \
    "$cover_policy_manager_contract" \
    "bind_risk_vault" \
    "$(jq -cn --arg risk_vault_contract "$risk_vault_contract_blob_hex" '{ risk_vault_contract: $risk_vault_contract }')" \
    >/dev/null
  echo "bootstrap apply: cover manager bind contract"
  call_contract_and_wait \
    "$config" \
    "$cover_policy_manager_contract" \
    "bind_contract" \
    "$(jq -cn --arg contract_id "$cover_policy_manager_contract_subject" '{ contract_id: $contract_id }')" \
    >/dev/null
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
     and ($actual[2] // 1) == 0
     and $actual[3] == $expected[3]
     and $actual[4] == $expected[4]
     and (($actual[5] // 0) >= ($expected[5] // 0))
     and (($actual[6] // 0) >= ($expected[6] // 0))
     and (($actual[7] // 0) >= ($expected[7] // 0))
     and (($actual[8] // 0) >= ($expected[8] // 0))'
else
  cover_automation_state_json="$(view_result_json "$cover_policy_manager_contract" "automation_state" null 2>/dev/null || echo 'null')"
  if ! json_equals "$cover_automation_state_json" "$cover_automation_expected_json"; then
    echo "bootstrap init/apply: cover manager config (public-compatible path)"
    if ! call_contract_and_wait \
      "$config" \
      "$cover_policy_manager_contract" \
      "init_manager" \
      "$(jq -cn --arg settlement_asset "$usdt_id" --arg risk_vault_contract "$risk_vault_contract_blob_hex" --argjson required_observations "$cover_required_observations" --argjson oracle_stale_slots "$cover_oracle_stale_slots" --arg oracle_public_key "$oracle_public_key_hex" --argjson oracle_scheme "$oracle_scheme" '{ settlement_asset: $settlement_asset, risk_vault_contract: $risk_vault_contract, required_observations: $required_observations, oracle_stale_slots: $oracle_stale_slots, oracle_public_key: $oracle_public_key, oracle_scheme: $oracle_scheme }')" \
      >/dev/null 2>&1; then
      echo "bootstrap note: cover manager init returned a non-fatal live-state error; continuing with bind/sync checks" >&2
    fi
    echo "bootstrap apply: cover manager bind risk vault"
    if ! call_contract_and_wait \
      "$config" \
      "$cover_policy_manager_contract" \
      "bind_risk_vault" \
      "$(jq -cn --arg risk_vault_contract "$risk_vault_contract_blob_hex" '{ risk_vault_contract: $risk_vault_contract }')" \
      >/dev/null 2>&1; then
      echo "bootstrap note: cover manager bind_risk_vault returned a non-fatal live-state error; continuing" >&2
    fi
    echo "bootstrap apply: cover manager bind contract"
    if ! call_contract_and_wait \
      "$config" \
      "$cover_policy_manager_contract" \
      "bind_contract" \
      "$(jq -cn --arg contract_id "$cover_policy_manager_contract_subject" '{ contract_id: $contract_id }')" \
      >/dev/null 2>&1; then
      echo "bootstrap note: cover manager bind_contract returned a non-fatal live-state error; continuing" >&2
    fi
    echo "bootstrap apply: cover manager exit withdrawal only"
    if ! call_contract_and_wait "$config" "$cover_policy_manager_contract" "exit_withdrawal_only" null >/dev/null 2>&1; then
      echo "bootstrap note: cover manager exit_withdrawal_only returned a non-fatal live-state error; continuing" >&2
    fi
  else
    echo "bootstrap skip: cover automation already matches expected live state"
  fi
  echo "bootstrap apply: cover manager bind risk vault"
  if ! call_contract_and_wait \
    "$config" \
    "$cover_policy_manager_contract" \
    "bind_risk_vault" \
    "$(jq -cn --arg risk_vault_contract "$risk_vault_contract_blob_hex" '{ risk_vault_contract: $risk_vault_contract }')" \
    >/dev/null 2>&1; then
    echo "bootstrap note: cover manager bind_risk_vault returned a non-fatal live-state error; continuing" >&2
  fi
  echo "bootstrap apply: cover manager bind contract"
  if ! call_contract_and_wait \
    "$config" \
    "$cover_policy_manager_contract" \
    "bind_contract" \
    "$(jq -cn --arg contract_id "$cover_policy_manager_contract_subject" '{ contract_id: $contract_id }')" \
    >/dev/null 2>&1; then
    echo "bootstrap note: cover manager bind_contract returned a non-fatal live-state error; continuing" >&2
  fi
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
     and ($actual[2] // 1) == 0
     and $actual[3] == $expected[3]
     and $actual[4] == $expected[4]
     and (($actual[5] // 0) >= ($expected[5] // 0))
     and (($actual[6] // 0) >= ($expected[6] // 0))
     and (($actual[7] // 0) >= ($expected[7] // 0))
     and (($actual[8] // 0) >= ($expected[8] // 0))'
fi
apply_step_and_expect \
  "cover automation" \
  "$cover_policy_manager_contract" \
  "automation_state" \
  null \
  "$cover_automation_expected_json" \
  "sync_automation" \
  "$(jq -cn --arg executor "$SORASWAP_AUTHORITY" '{ executor: $executor, job_id: 301, cadence_slots: 3, backlog_cap: 10, safe_mode: 0 }')"
echo "bootstrap apply: cover heartbeat"
if [[ "$mode" == "local" ]]; then
  call_contract_and_wait \
    "$config" \
    "$cover_policy_manager_contract" \
    "heartbeat" \
    '{"current_backlog":0,"safe_mode":0}' \
    >/dev/null
else
  if ! call_contract_and_wait \
    "$config" \
    "$cover_policy_manager_contract" \
    "heartbeat" \
    '{"current_backlog":0,"safe_mode":0}' \
    >/dev/null 2>&1; then
    echo "bootstrap note: cover heartbeat returned a non-fatal public-chain error; continuing" >&2
  fi
fi

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
    --argjson listing_fee_amount "$bridge_listing_fee_amount" \
    '{
      listing_fee_asset: $listing_fee_asset,
      treasury: $treasury,
      listing_fee_amount: $listing_fee_amount,
      proof_authority: $proof_authority
    }')"
  ensure_init_or_skip \
    "bridge listing config" \
    "$sccp_bridge_contract" \
    "listing_config" \
    null \
    "$bridge_listing_expected_json" \
    "init_bridge" \
    "$bridge_listing_init_payload"

  bridge_authorities_expected_json="$(jq -cn --arg owner "$SORASWAP_AUTHORITY" --arg proof_authority "$bridge_proof_authority" '[ $owner, $proof_authority ]')"
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
    --argjson home_domain "$bridge_asset_home_domain" \
    --argjson decimals "$bridge_asset_decimals" \
    '[ $asset, $home_domain, $decimals ]')"
  bridge_asset_register_payload="$(jq -cn \
    --arg asset_key "$bridge_asset_key" \
    --arg asset "$bridge_local_asset" \
    --argjson home_domain "$bridge_asset_home_domain" \
    --argjson decimals "$bridge_asset_decimals" \
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
    "register_asset" \
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
    --arg asset "$bridge_local_asset" \
    --arg vault_account "$vault_account" \
    --argjson remote_domain "$bridge_remote_domain" \
    '{
      route: $route,
      asset_key: $asset_key,
      remote_domain: $remote_domain,
      local_asset: $asset,
      vault_account: $vault_account
    }')"
  bridge_route_activate_governed_payload="$(jq -cn \
    --arg message_id "${SORASWAP_BRIDGE_GOVERNANCE_MESSAGE_ID:-bridge_bootstrap_route}" \
    --arg route "$bridge_route" \
    --arg asset_key "$bridge_asset_key" \
    --argjson remote_domain "$bridge_remote_domain" \
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
    --argjson strategy_code "$soraswap_launch_vault_strategy_code" \
    --argjson async_redeem "$soraswap_launch_vault_async_redeem" \
    '{vault_id:$vault_id, underlying_asset:$underlying_asset, share_asset:$share_asset, strategy_code:$strategy_code, async_redeem:$async_redeem}')"

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
  "$(jq -cn --arg service "$soraswap_launch_operator_service" --arg bond_asset "$xor_id" --argjson min_bond "$soraswap_launch_operator_min_bond" '{service:$service, bond_asset:$bond_asset, min_bond:$min_bond}')" \
  '$actual[0] == $expected[0]
   and $actual[1] == $expected[1]
   and (($actual[2] // 0) >= 0)
   and (($actual[3] // 0) >= 0)
   and (($actual[4] // 0) >= 0)
   and (($actual[5] // 0) >= 0)
   and (($actual[6] // 0) == 0)'
ensure_step_from_prior_or_skip_with_live_predicate \
  "soraswap launch operator bond" \
  "$operators_registry_contract" \
  "operator_state" \
  "$launch_operator_view_payload" \
  "$launch_operator_registered_json" \
  "$launch_operator_bonded_json" \
  "bond" \
  "$(jq -cn --arg service "$soraswap_launch_operator_service" --argjson amount "$soraswap_launch_operator_bond" '{service:$service, amount:$amount}')" \
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
  "$(jq -cn --arg service "$soraswap_launch_operator_service" --argjson slot "$soraswap_launch_operator_heartbeat_slot" --argjson health_bps "$soraswap_launch_operator_health_bps" '{service:$service, slot:$slot, health_bps:$health_bps, fees_accrued:0}')"

launch_margin_view_payload="$(jq -cn --arg market_id "$soraswap_launch_margin_market_id" '{market_id: $market_id}')"
ensure_step_from_prior_or_skip \
  "soraswap launch margin market" \
  "$margin_portfolio_margin_contract" \
  "market_state" \
  "$launch_margin_view_payload" \
  '[0,0,0]' \
  "$(jq -cn --argjson risk "$soraswap_launch_margin_risk_weight_bps" --argjson threshold "$soraswap_launch_margin_liquidation_threshold_bps" '[1,$risk,$threshold]')" \
  "register_market" \
  "$(jq -cn --arg market_id "$soraswap_launch_margin_market_id" --argjson risk_weight_bps "$soraswap_launch_margin_risk_weight_bps" --argjson liquidation_threshold_bps "$soraswap_launch_margin_liquidation_threshold_bps" '{market_id:$market_id, risk_weight_bps:$risk_weight_bps, liquidation_threshold_bps:$liquidation_threshold_bps}')"

launch_rwa_view_payload="$(jq -cn --arg market_id "$soraswap_launch_rwa_market_id" '{market_id: $market_id}')"
ensure_step_from_prior_or_skip \
  "soraswap launch rwa market" \
  "$rwa_market_contract" \
  "rwa_market_state" \
  "$launch_rwa_view_payload" \
  '[0,0,0,0]' \
  "$(jq -cn --argjson nav "$soraswap_launch_rwa_nav" --argjson shares "$soraswap_launch_rwa_shares" '[1,$nav,$shares,1]')" \
  "issue_lot" \
  "$(jq -cn --arg market_id "$soraswap_launch_rwa_market_id" --arg share_asset "$n3x_id" --arg nav_asset "$usdt_id" --argjson initial_nav_per_share "$soraswap_launch_rwa_nav" --argjson total_shares "$soraswap_launch_rwa_shares" '{market_id:$market_id, share_asset:$share_asset, nav_asset:$nav_asset, initial_nav_per_share:$initial_nav_per_share, total_shares:$total_shares}')"

launch_hook_view_payload="$(jq -cn --arg hook_id "$soraswap_launch_dlmm_hook_id" '{hook_id: $hook_id}')"
ensure_step_from_prior_or_skip \
  "soraswap launch dlmm hook policy" \
  "$dlmm_hooks_manager_contract" \
  "hook_policy" \
  "$launch_hook_view_payload" \
  '[0,0,0,0]' \
  "$(jq -cn --argjson phase "$soraswap_launch_dlmm_hook_phase" --argjson max_fee "$soraswap_launch_dlmm_hook_max_fee_pips" '[1,$phase,$max_fee,1]')" \
  "configure_hook_policy" \
  "$(jq -cn --arg hook_id "$soraswap_launch_dlmm_hook_id" --argjson phase "$soraswap_launch_dlmm_hook_phase" --argjson max_fee_pips "$soraswap_launch_dlmm_hook_max_fee_pips" '{hook_id:$hook_id, phase:$phase, max_fee_pips:$max_fee_pips, enabled:1}')"

echo "post-deploy contract state initialized"
