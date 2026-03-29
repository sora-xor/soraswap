#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

mode="${1:-local}"
config="$(client_config_or_default "$mode")"
ensure_client "$config"
ensure_authority "$config"
treasury_account="$(treasury_account_for_mode "$mode")"
treasury_seed_balance="${SORASWAP_TREASURY_SEED_BALANCE:-1000000}"

echo "bootstrap domain and helper assets via $config"

ensure_domain_sns_lease "$config" soraswap

if ! iroha_cli_json --config "$config" ledger domain get --id soraswap >/dev/null 2>&1; then
  iroha_cli --machine --config "$config" ledger domain register --id soraswap
fi

ensure_account_registered "$config" "$treasury_account" soraswap

ensure_asset_definition_alias "$config" \
  "$SORASWAP_XOR_ASSET_DEFINITION_ID" \
  xor \
  "$SORASWAP_BASE_ASSET_ALIAS" \
  0
ensure_asset_definition_alias "$config" \
  7Dsw1EgqCsPmv9HpEztf26xEL2qo \
  usdt \
  usdt#soraswap.universal \
  0
ensure_asset_definition_alias "$config" \
  4wicsaHQFueXc3GKLG7WoQaKMWWq \
  usdc \
  usdc#soraswap.universal \
  0
ensure_asset_definition_alias "$config" \
  6Fjwa298w3A7KDnGxjFncsfqj8qC \
  kusd \
  kusd#soraswap.universal \
  0
ensure_asset_definition_alias "$config" \
  5N3DQmQr8sx9bKRU87WVkqQR6D2j \
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
