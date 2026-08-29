#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

config="$(client_config_or_default local)"
ensure_client "$config"
ensure_authority "$config"
deploy_scope="${SORASWAP_DEPLOY_SCOPE:-full}"
typeset -A deploy_contract_key_set
deploy_contract_count=0
prepare_env_chain_state local "$config"
deploy_report_init local "$config"

deploy_failed=1
cleanup_deploy_local() {
  if [[ ${deploy_failed:-1} -ne 0 ]]; then
    deploy_report_finish local failed || true
  fi
}
trap cleanup_deploy_local EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "$deploy_scope" != "foundation" && "$deploy_scope" != "full" ]]; then
  echo "unsupported SORASWAP_DEPLOY_SCOPE: $deploy_scope" >&2
  exit 2
fi
while IFS= read -r contract_key; do
  [[ -n "$contract_key" ]] || continue
  deploy_contract_key_set[$contract_key]=1
done < <(expected_contract_ids_for_deploy_scope "$deploy_scope")

deploy_report_set_phase local preflight running "$(jq -cn \
  --arg authority "$SORASWAP_AUTHORITY" \
  --arg config "$(soraswap_display_path "$config")" \
  '{authority: $authority, client_config: $config}')"
deploy_report_set_phase local preflight completed "$(jq -cn \
  --arg authority "$SORASWAP_AUTHORITY" \
  --arg fee_asset "$(fee_asset_label_for_config "$config")" \
  --arg fee_asset_id "$(fee_asset_definition_id_for_config "$config")" \
  --arg balance "$(asset_value_for_account_id "$config" "$(fee_asset_definition_id_for_config "$config")" "$SORASWAP_AUTHORITY")" \
  '{authority: $authority, fee_asset: $fee_asset, fee_asset_id: $fee_asset_id, balance: $balance}')"
ensure_can_register_trigger_permission "$config" "$SORASWAP_AUTHORITY"

deploy_report_set_phase local bootstrap_assets running null
zsh "$SORASWAP_ROOT/scripts/bootstrap_assets.sh" local
deploy_report_set_phase local bootstrap_assets completed null

deploy_report_set_phase local compile running null
if [[ "$deploy_scope" == "full" ]]; then
  zsh "$SORASWAP_ROOT/scripts/compile_contracts.sh"
else
  soraswap_require_contract_source_hygiene "$SORASWAP_ROOT" "foundation compile failed" || exit 1
  while IFS= read -r contract; do
    contract_key="$(contract_id_for "$contract")"
    [[ -n "${deploy_contract_key_set[$contract_key]:-}" ]] || continue
    compile_one "$contract"
  done < <(list_contracts)
fi
deploy_report_set_phase local compile completed "$(jq -cn --arg deploy_scope "$deploy_scope" '{deploy_scope: $deploy_scope}')"

while IFS= read -r contract; do
  contract_key="$(contract_id_for "$contract")"
  [[ -n "${deploy_contract_key_set[$contract_key]:-}" ]] || continue
  rm -f \
    "$(deployment_record_path_for_env local "$contract_key")" \
    "$SORASWAP_ROOT/deployments/local/${contract_key}.manifest.json"
done < <(list_contracts)

deploy_report_set_phase local deploy running null
while IFS= read -r contract; do
  contract_key="$(contract_id_for "$contract")"
  [[ -n "${deploy_contract_key_set[$contract_key]:-}" ]] || continue
  deploy_one "$config" "$contract" local
  deploy_contract_count=$(( deploy_contract_count + 1 ))
done < <(list_contracts)
deploy_report_set_phase local deploy completed "$(jq -cn \
  --argjson total "$deploy_contract_count" \
  --arg deploy_scope "$deploy_scope" \
  '{
    strategy: "ivm_contract_deploy_per_contract",
    contract_count: $total,
    deploy_scope: $deploy_scope
  }')"

deploy_report_set_phase local bootstrap_contract_state running null
zsh "$SORASWAP_ROOT/scripts/bootstrap_contract_state.sh" local
deploy_report_set_phase local bootstrap_contract_state completed null

report_dir="$(deployments_dir_for_env local)"
timestamp="$(utc_timestamp)"
contracts_latest_path="$(contracts_snapshot_latest_path_for_env local)"
contracts_timestamped_path="$(contracts_snapshot_timestamped_path_for_env local "$timestamp")"
mkdir -p "$report_dir"
deploy_report_set_phase local deployment_records_snapshot running null
cleanup_stale_deployment_records_for_env local
snapshot_json="$(deployment_records_snapshot_json_for_env local "$timestamp")"
soraswap_write_json_report_pair "$snapshot_json" "$contracts_latest_path" "$contracts_timestamped_path"
deploy_report_set_phase local deployment_records_snapshot completed "$(jq -cn --arg path "$(soraswap_display_path "$contracts_timestamped_path")" '{snapshot: $path}')"
deploy_report_finish local completed
deploy_failed=0
trap - EXIT
trap - HUP INT TERM

echo "local deployment snapshot: $(soraswap_display_path "$contracts_timestamped_path")"
