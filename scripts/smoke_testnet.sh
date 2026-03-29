#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

config="$(client_config_or_default testnet)"
ensure_client "$config"
ensure_authority "$config"
prepare_env_chain_state testnet "$config"
ensure_public_testnet_signer_ready "$config" "$SORASWAP_AUTHORITY" readonly

n3x_hub_contract="$(deployed_contract_id_for_env testnet n3x.n3x_hub)"
n3x_hub_dataspace="$(deployed_contract_dataspace_for_env testnet n3x.n3x_hub)"
dlmm_pool_contract="$(deployed_contract_id_for_env testnet dlmm.dlmm_pool)"
dlmm_pool_dataspace="$(deployed_contract_dataspace_for_env testnet dlmm.dlmm_pool)"
dlmm_router_contract="$(deployed_contract_id_for_env testnet dlmm.dlmm_router)"
dlmm_router_dataspace="$(deployed_contract_dataspace_for_env testnet dlmm.dlmm_router)"

report_dir="$SORASWAP_ROOT/deployments/testnet"
timestamp="$(env TZ=UTC date '+%Y%m%dT%H%M%SZ')"
latest_report="$report_dir/smoke.latest.json"
timestamped_report="$report_dir/smoke.${timestamp}.json"
mkdir -p "$report_dir"

iroha_cli --machine --config "$config" app contracts instances --dataspace universal --table
instances_json="$(iroha_cli_json --config "$config" app contracts instances --dataspace universal)"

iroha_cli_json --config "$config" ledger asset definition get --alias "$SORASWAP_BASE_ASSET_ALIAS" \
  | jq -e --arg id "$SORASWAP_XOR_ASSET_DEFINITION_ID" '.id == $id and .name == "xor"' >/dev/null

typeset -a contract_keys
while IFS= read -r contract_key; do
  contract_keys+=("$contract_key")
done < <(expected_contract_ids)

manifest_verified=0
for contract_key in "${contract_keys[@]}"; do
  contract_id="$(deployed_contract_id_for_env testnet "$contract_key")"
  live_hash="$(jq -r --arg cid "$contract_id" '.instances[]? | select(.contract_id == $cid) | .code_hash_hex' <<<"$instances_json")"
  if [[ -z "$live_hash" || "$live_hash" == "null" ]]; then
    echo "missing active universal contract instance: $contract_id" >&2
    exit 1
  fi

  manifest_path="$SORASWAP_ROOT/deployments/testnet/${contract_key}.manifest.json"
  if [[ -f "$manifest_path" ]]; then
    expected_hash="$(manifest_code_hash_hex "$manifest_path")"
    if [[ "${live_hash:l}" != "$expected_hash" ]]; then
      echo "live code hash mismatch for $contract_id: expected $expected_hash, got ${live_hash:l}" >&2
      exit 1
    fi
    manifest_verified=$(( manifest_verified + 1 ))
  fi
done

contract_instance_exists "$config" "$n3x_hub_dataspace" "$n3x_hub_contract"
contract_instance_exists "$config" "$dlmm_pool_dataspace" "$dlmm_pool_contract"
contract_instance_exists "$config" "$dlmm_router_dataspace" "$dlmm_router_contract"

xor_id="$(asset_definition_id_for_alias "$config" "$SORASWAP_BASE_ASSET_ALIAS")"
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
  --argjson instances "$(jq -c '.instances // []' <<<"$instances_json")" \
  --argjson n3x_quote_result "$(contract_view_result_json "$n3x_quote_view_json")" \
  --argjson router_quote_result "$(contract_view_result_json "$router_quote_view_json")" \
  --argjson router_select_result "$(contract_view_result_json "$router_select_view_json")" \
  --argjson n3x_assert_result "$(contract_view_result_json "$n3x_assert_view_json")" \
  --argjson router_assert_result "$(contract_view_result_json "$router_assert_view_json")" \
  --argjson n3x_mirror_result "$(contract_view_result_json "$n3x_mirror_view_json")" \
  --argjson router_mirror_result "$(contract_view_result_json "$router_mirror_view_json")" \
  --argjson pool_mirror_result "$(contract_view_result_json "$pool_mirror_view_json")" \
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
    instances: $instances,
    view_results: {
      n3x_quote_mint: $n3x_quote_result,
      dlmm_router_quote_bin: $router_quote_result,
      dlmm_router_select_best_quote: $router_select_result,
      n3x_assert_initialized: $n3x_assert_result,
      n3x_mirror_state: $n3x_mirror_result,
      dlmm_router_assert_config: $router_assert_result,
      dlmm_router_mirror_state: $router_mirror_result,
      dlmm_pool_mirror_state: $pool_mirror_result
    },
    decoded_state_ints: $decoded_state_ints
  }')"

printf '%s\n' "$report_json" > "$latest_report"
printf '%s\n' "$report_json" > "$timestamped_report"

echo "testnet smoke n3x quote result: $(contract_view_result_json "$n3x_quote_view_json")"
echo "testnet smoke router quote result: $(contract_view_result_json "$router_quote_view_json")"
echo "testnet smoke router select result: $(contract_view_result_json "$router_select_view_json")"
echo "testnet smoke assert results: $(contract_view_result_json "$n3x_assert_view_json") $(contract_view_result_json "$router_assert_view_json")"
echo "testnet smoke mirror tuples: $(jq -c '.view_results | {n3x_mirror_state, dlmm_router_mirror_state, dlmm_pool_mirror_state}' <<<"$report_json")"
echo "testnet smoke decoded state ints: $(jq -c '.decoded_state_ints' <<<"$report_json")"
echo "testnet smoke report: $timestamped_report"
