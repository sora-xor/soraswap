#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

config="$(client_config_or_default testnet)"
ensure_client "$config"
ensure_authority "$config"
prepare_env_chain_state testnet "$config"

ensure_public_testnet_signer_ready "$config" "$SORASWAP_AUTHORITY" autofund

balance="$(asset_value_for_account "$config" "$SORASWAP_FEE_ASSET_ALIAS" "$SORASWAP_AUTHORITY")"
echo "funded testnet signer: $SORASWAP_AUTHORITY -> $balance $SORASWAP_FEE_ASSET_ALIAS"
