#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

config="$(client_config_or_default testnet)"
ensure_client "$config"
ensure_authority "$config"
prepare_env_chain_state testnet "$config"
deploy_report_init testnet "$config"

deploy_failed=1
trap 'if [[ ${deploy_failed:-1} -ne 0 ]]; then deploy_report_finish testnet failed || true; fi' EXIT

deploy_report_set_phase testnet preflight running "$(jq -cn \
  --arg authority "$SORASWAP_AUTHORITY" \
  --arg config "$config" \
  '{authority: $authority, client_config: $config}')"
warn_if_testnet_tx_gossip_cap_low "$config"
ensure_public_testnet_signer_ready "$config" "$SORASWAP_AUTHORITY" autofund
deploy_report_set_phase testnet preflight completed "$(jq -cn \
  --arg authority "$SORASWAP_AUTHORITY" \
  --arg fee_alias "$SORASWAP_FEE_ASSET_ALIAS" \
  --arg balance "$(asset_value_for_account "$config" "$SORASWAP_FEE_ASSET_ALIAS" "$SORASWAP_AUTHORITY")" \
  '{authority: $authority, fee_asset: $fee_alias, balance: $balance}')"

if [[ "${SORASWAP_TESTNET_BOOTSTRAP:-0}" == "1" ]]; then
  deploy_report_set_phase testnet bootstrap_assets running null
  "$SORASWAP_ROOT/scripts/bootstrap_assets.sh" testnet
  deploy_report_set_phase testnet bootstrap_assets completed null
else
  echo "skipping testnet bootstrap; set SORASWAP_TESTNET_BOOTSTRAP=1 for one-time domain/asset setup"
  deploy_report_set_phase testnet bootstrap_assets skipped null
fi

deploy_report_set_phase testnet compile running null
"$SORASWAP_ROOT/scripts/compile_contracts.sh"
deploy_report_set_phase testnet compile completed null

deploy_report_set_phase testnet deploy running null
while IFS= read -r contract; do
  echo "deploy-testnet: $contract"
  deploy_one "$config" "$contract" "testnet"
done < <(list_contracts)
deploy_report_set_phase testnet deploy completed "$(jq -cn --arg total "$(list_contracts | wc -l | tr -d ' ')" '{contract_count: ($total|tonumber)}')"

if [[ "${SORASWAP_INIT_CONTRACT_STATE:-0}" == "1" ]]; then
  deploy_report_set_phase testnet bootstrap_contract_state running null
  "$SORASWAP_ROOT/scripts/bootstrap_contract_state.sh" testnet
  deploy_report_set_phase testnet bootstrap_contract_state completed null
else
  echo "skipping post-deploy contract init on testnet; set SORASWAP_INIT_CONTRACT_STATE=1 to enable"
  deploy_report_set_phase testnet bootstrap_contract_state skipped null
fi

iroha_cli --config "$config" app contracts instances --dataspace universal --table || true

report_dir="$(deployments_dir_for_env testnet)"
timestamp="$(utc_timestamp)"
mkdir -p "$report_dir"
deploy_report_set_phase testnet instances_snapshot running null
instances_json="$(iroha_cli_json --config "$config" app contracts instances --dataspace universal)"
snapshot_json="$(jq -cn \
  --arg generated_at "$timestamp" \
  --argjson chain_fingerprint "${SORASWAP_CHAIN_FINGERPRINT_JSON:-null}" \
  --argjson instances "$instances_json" \
  '$instances + {
    generated_at: $generated_at,
    chain_fingerprint: $chain_fingerprint
  }')"
printf '%s\n' "$snapshot_json" > "$report_dir/instances.latest.json"
printf '%s\n' "$snapshot_json" > "$report_dir/instances.${timestamp}.json"
deploy_report_set_phase testnet instances_snapshot completed "$(jq -cn --arg path "$report_dir/instances.${timestamp}.json" '{snapshot: $path}')"
deploy_report_finish testnet completed
deploy_failed=0
trap - EXIT
echo "testnet deployment snapshot: $report_dir/instances.${timestamp}.json"
