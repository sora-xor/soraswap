#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

config="$(client_config_or_default testnet)"
ensure_client "$config"
ensure_authority "$config"
prepare_env_chain_state testnet "$config"

ensure_public_testnet_signer_ready "$config" "$SORASWAP_AUTHORITY" autofund

fee_asset_id="$(fee_asset_definition_id_for_config "$config")"
fee_asset_label="$(fee_asset_label_for_config "$config")"
balance="$(asset_value_for_account_id "$config" "$fee_asset_id" "$SORASWAP_AUTHORITY")"
echo "funded testnet signer: $SORASWAP_AUTHORITY -> $balance $fee_asset_label ($fee_asset_id)"
