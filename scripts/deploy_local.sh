#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

config="$(client_config_or_default local)"
ensure_client "$config"
ensure_authority "$config"

"$SORASWAP_ROOT/scripts/bootstrap_assets.sh" local
"$SORASWAP_ROOT/scripts/compile_contracts.sh"

while IFS= read -r contract; do
  contract_key="$(contract_id_for "$contract")"
  rm -f \
    "$(deployment_record_path_for_env local "$contract_key")" \
    "$SORASWAP_ROOT/deployments/local/${contract_key}.manifest.json"
done < <(list_contracts)

while IFS= read -r contract; do
  echo "deploy-local: $contract"
  deploy_one "$config" "$contract" "local"
done < <(list_contracts)

"$SORASWAP_ROOT/scripts/bootstrap_contract_state.sh" local

iroha_cli --config "$config" app contracts instances --dataspace universal --table || true
