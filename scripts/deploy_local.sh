#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

config="$(client_config_or_default local)"
ensure_client "$config"
ensure_authority "$config"
deploy_scope="${SORASWAP_DEPLOY_SCOPE:-full}"
deploy_manifest="$(contract_app_manifest_path)"
tmp_deploy_manifest=""
prepare_env_chain_state local "$config"
deploy_report_init local "$config"

deploy_failed=1
cleanup_deploy_local() {
  if [[ -n "${tmp_deploy_manifest:-}" ]]; then
    rm -f "$tmp_deploy_manifest"
  fi
  if [[ ${deploy_failed:-1} -ne 0 ]]; then
    deploy_report_finish local failed || true
  fi
}
trap cleanup_deploy_local EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "$deploy_scope" == "foundation" ]]; then
  foundation_contract_keys=("${(@f)$(expected_contract_ids_for_deploy_scope foundation)}")
  mkdir -p "$SORASWAP_ROOT/tmp"
  tmp_deploy_manifest="$(mktemp "$SORASWAP_ROOT/tmp/soraswap-foundation-manifest.XXXXXX")"
  write_contract_app_manifest_subset "$deploy_manifest" "$tmp_deploy_manifest" \
    "${foundation_contract_keys[@]}"
  deploy_manifest="$tmp_deploy_manifest"
elif [[ "$deploy_scope" != "full" ]]; then
  echo "unsupported SORASWAP_DEPLOY_SCOPE: $deploy_scope" >&2
  exit 2
fi

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
zsh "$SORASWAP_ROOT/scripts/compile_contracts.sh"
deploy_report_set_phase local compile completed null

while IFS= read -r contract; do
  contract_key="$(contract_id_for "$contract")"
  rm -f \
    "$(deployment_record_path_for_env local "$contract_key")" \
    "$SORASWAP_ROOT/deployments/local/${contract_key}.manifest.json"
done < <(list_contracts)
rm -f "$(contract_bundle_receipt_path_for_env local)"

deploy_report_set_phase local deploy running null
bundle_receipt_json="$(submit_contract_app_manifest_for_env local "$config" "$deploy_manifest")"
deploy_report_set_phase local deploy completed "$(jq -cn \
  --arg bundle_digest "$(jq -r '.bundle_digest' <<<"$bundle_receipt_json")" \
  --arg total "$(jq -r '.contracts | length' <<<"$bundle_receipt_json")" \
  --arg deploy_scope "$deploy_scope" \
  --argjson chunked "$(jq -r '(.chunked // false)' <<<"$bundle_receipt_json")" \
  --argjson chunks "$(jq -c '(.chunks // [])' <<<"$bundle_receipt_json")" \
  '{
    bundle_digest: $bundle_digest,
    contract_count: ($total|tonumber),
    deploy_scope: $deploy_scope
  } + (if $chunked then {
    chunked: true,
    chunk_count: ($chunks | length),
    chunks: ($chunks | map({
      index,
      bundle_digest,
      contract_count,
      contracts
    }))
  } else {} end)')"

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
if [[ -n "${tmp_deploy_manifest:-}" ]]; then
  rm -f "$tmp_deploy_manifest"
  tmp_deploy_manifest=""
fi
deploy_failed=0
trap - EXIT
trap - HUP INT TERM

echo "local deployment snapshot: $(soraswap_display_path "$contracts_timestamped_path")"
