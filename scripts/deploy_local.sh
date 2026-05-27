#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

config="$(client_config_or_default local)"
ensure_client "$config"
ensure_authority "$config"
prepare_env_chain_state local "$config"
deploy_report_init local "$config"

deploy_failed=1
trap 'if [[ ${deploy_failed:-1} -ne 0 ]]; then deploy_report_finish local failed || true; fi' EXIT

deploy_report_set_phase local preflight running "$(jq -cn \
  --arg authority "$SORASWAP_AUTHORITY" \
  --arg config "$config" \
  '{authority: $authority, client_config: $config}')"
deploy_report_set_phase local preflight completed "$(jq -cn \
  --arg authority "$SORASWAP_AUTHORITY" \
  --arg fee_asset "$(fee_asset_label_for_config "$config")" \
  --arg fee_asset_id "$(fee_asset_definition_id_for_config "$config")" \
  --arg balance "$(asset_value_for_account_id "$config" "$(fee_asset_definition_id_for_config "$config")" "$SORASWAP_AUTHORITY")" \
  '{authority: $authority, fee_asset: $fee_asset, fee_asset_id: $fee_asset_id, balance: $balance}')"
ensure_can_register_trigger_permission "$config" "$SORASWAP_AUTHORITY"

deploy_report_set_phase local bootstrap_assets running null
"$SORASWAP_ROOT/scripts/bootstrap_assets.sh" local
deploy_report_set_phase local bootstrap_assets completed null

deploy_report_set_phase local compile running null
"$SORASWAP_ROOT/scripts/compile_contracts.sh"
deploy_report_set_phase local compile completed null

while IFS= read -r contract; do
  contract_key="$(contract_id_for "$contract")"
  rm -f \
    "$(deployment_record_path_for_env local "$contract_key")" \
    "$SORASWAP_ROOT/deployments/local/${contract_key}.manifest.json"
done < <(list_contracts)
rm -f "$(contract_bundle_receipt_path_for_env local)"

deploy_report_set_phase local deploy running null
bundle_receipt_json="$(submit_contract_app_bundle "$config" deploy)"
materialize_contract_bundle_records_for_env local "$bundle_receipt_json" "$config"
deploy_report_set_phase local deploy completed "$(jq -cn \
  --arg bundle_digest "$(jq -r '.bundle_digest' <<<"$bundle_receipt_json")" \
  --arg total "$(jq -r '.contracts | length' <<<"$bundle_receipt_json")" \
  '{bundle_digest: $bundle_digest, contract_count: ($total|tonumber)}')"

deploy_report_set_phase local bootstrap_contract_state running null
"$SORASWAP_ROOT/scripts/bootstrap_contract_state.sh" local
deploy_report_set_phase local bootstrap_contract_state completed null

report_dir="$(deployments_dir_for_env local)"
timestamp="$(utc_timestamp)"
contracts_latest_path="$(contracts_snapshot_latest_path_for_env local)"
contracts_timestamped_path="$(contracts_snapshot_timestamped_path_for_env local "$timestamp")"
mkdir -p "$report_dir"
deploy_report_set_phase local deployment_records_snapshot running null
snapshot_json="$(deployment_records_snapshot_json_for_env local "$timestamp")"
printf '%s\n' "$snapshot_json" > "$contracts_latest_path"
printf '%s\n' "$snapshot_json" > "$contracts_timestamped_path"
deploy_report_set_phase local deployment_records_snapshot completed "$(jq -cn --arg path "$contracts_timestamped_path" '{snapshot: $path}')"
deploy_report_finish local completed
deploy_failed=0
trap - EXIT

echo "local deployment snapshot: $contracts_timestamped_path"
