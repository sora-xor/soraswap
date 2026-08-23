#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

mode="${1:-local}"
case "$mode" in
  testnet|production)
    require_public_mutation_consent "$mode" "$mode bootstrap assets"
    ;;
esac

config="$(client_config_or_default "$mode")"
treasury_seed_balance="${SORASWAP_TREASURY_SEED_BALANCE:-1000000}"
soraswap_require_positive_integer_setting "SORASWAP_TREASURY_SEED_BALANCE" "$treasury_seed_balance" || exit 1
if [[ "$mode" == "local" ]]; then
  soraswap_require_nonnegative_integer_setting "SORASWAP_LOCAL_FEE_ASSET_SCALE" "$SORASWAP_LOCAL_FEE_ASSET_SCALE" || exit 1
fi
ensure_client "$config"
ensure_authority "$config"
treasury_account="$(treasury_account_for_mode "$mode")"
domain_id="soraswap.universal"

echo "bootstrap domain and helper assets via $(soraswap_display_path "$config")"

if ! public_env_for_config "$config" >/dev/null 2>&1; then
  local_fee_asset_definition_id="$(localnet_fee_asset_definition_id_for_config "$config" 2>/dev/null || true)"
  if [[ -n "$local_fee_asset_definition_id" && "$SORASWAP_LOCAL_FEE_ASSET_LABEL" == *"#"* ]]; then
    ensure_asset_definition_alias "$config" \
      "$local_fee_asset_definition_id" \
      "${SORASWAP_LOCAL_FEE_ASSET_LABEL%%#*}" \
      "$SORASWAP_LOCAL_FEE_ASSET_LABEL" \
      "$SORASWAP_LOCAL_FEE_ASSET_SCALE"
    ensure_asset_balance_min "$config" "$SORASWAP_LOCAL_FEE_ASSET_LABEL" "$SORASWAP_AUTHORITY" 1000000
  fi
fi

ensure_domain_sns_lease "$config" soraswap

if ! iroha_cli_json --config "$config" ledger domain get --id "$domain_id" >/dev/null 2>&1; then
  domain_register_output=""
  domain_register_status=0
  set +e
  domain_register_output="$(iroha_cli_with_gas_metadata "$config" ledger domain register --id "$domain_id" 2>&1)"
  domain_register_status=$?
  set -e
  if (( domain_register_status != 0 )); then
    if [[ "$domain_register_output" == *"Repeated instruction"* || "$domain_register_output" == *"Repetition of \`Register\`"* ]] \
      && iroha_cli_json --config "$config" ledger domain get --id "$domain_id" >/dev/null 2>&1; then
      echo "domain already present after duplicate register rejection: $domain_id"
    else
      soraswap_redact_sensitive_text "$domain_register_output" >&2
      exit "$domain_register_status"
    fi
  elif [[ -n "$domain_register_output" ]]; then
    printf '%s\n' "$domain_register_output"
  fi
fi

ensure_account_registered "$config" "$treasury_account" "$domain_id"

ensure_asset_definition_alias "$config" \
  "$SORASWAP_XOR_ASSET_DEFINITION_ID" \
  xor \
  "$SORASWAP_BASE_ASSET_ALIAS" \
  0
ensure_asset_definition_alias "$config" \
  "$SORASWAP_USDT_ASSET_DEFINITION_ID" \
  usdt \
  usdt#soraswap.universal \
  0
ensure_asset_definition_alias "$config" \
  "$SORASWAP_USDC_ASSET_DEFINITION_ID" \
  usdc \
  usdc#soraswap.universal \
  0
ensure_asset_definition_alias "$config" \
  "$SORASWAP_KUSD_ASSET_DEFINITION_ID" \
  kusd \
  kusd#soraswap.universal \
  0
ensure_asset_definition_alias "$config" \
  "$SORASWAP_N3X_ASSET_DEFINITION_ID" \
  n3x \
  n3x#soraswap.universal \
  0

ensure_asset_balance_min "$config" "$SORASWAP_BASE_ASSET_ALIAS" "$SORASWAP_AUTHORITY" 1000000
ensure_asset_balance_min "$config" usdt#soraswap.universal "$SORASWAP_AUTHORITY" 1000000
ensure_asset_balance_min "$config" usdc#soraswap.universal "$SORASWAP_AUTHORITY" 1000000
ensure_asset_balance_min "$config" kusd#soraswap.universal "$SORASWAP_AUTHORITY" 1000000
ensure_asset_balance_min "$config" n3x#soraswap.universal "$SORASWAP_AUTHORITY" 1000000
if [[ "$treasury_account" != "$SORASWAP_AUTHORITY" ]]; then
  ensure_asset_balance_min "$config" "$SORASWAP_BASE_ASSET_ALIAS" "$treasury_account" "$treasury_seed_balance"
  ensure_asset_balance_min "$config" usdt#soraswap.universal "$treasury_account" "$treasury_seed_balance"
  ensure_asset_balance_min "$config" usdc#soraswap.universal "$treasury_account" "$treasury_seed_balance"
  ensure_asset_balance_min "$config" kusd#soraswap.universal "$treasury_account" "$treasury_seed_balance"
fi

echo "expected DEX base asset alias: $SORASWAP_BASE_ASSET_ALIAS"
echo "treasury account: $treasury_account"
