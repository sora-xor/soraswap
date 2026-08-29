#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

export SORASWAP_PUBLIC_ENV=testnet
require_public_mutation_consent testnet "testnet signer funding"

config="$(client_config_or_default testnet)"
ensure_client "$config"
ensure_authority "$config"
prepare_env_chain_state testnet "$config"

ensure_public_signer_ready "$config" "$SORASWAP_AUTHORITY" autofund

fee_asset_id="$(fee_asset_definition_id_for_config "$config")"
fee_asset_label="$(fee_asset_label_for_config "$config")"
balance="$(asset_value_for_account_id "$config" "$fee_asset_id" "$SORASWAP_AUTHORITY")"
echo "Taira write canary verified funded signer: $SORASWAP_AUTHORITY -> $balance $fee_asset_label ($fee_asset_id)"
