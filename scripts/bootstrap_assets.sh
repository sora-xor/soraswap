#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

mode="${1:-local}"
config="$(client_config_or_default "$mode")"
ensure_client "$config"
ensure_authority "$config"
treasury_account="$(treasury_account_for_mode "$mode")"
treasury_seed_balance="${SORASWAP_TREASURY_SEED_BALANCE:-1000000}"
domain_id="soraswap.universal"

echo "bootstrap domain and helper assets via $config"

ensure_domain_sns_lease "$config" soraswap

if ! iroha_cli_json --config "$config" ledger domain get --id "$domain_id" >/dev/null 2>&1; then
  iroha_cli --machine --config "$config" ledger domain register --id "$domain_id"
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
