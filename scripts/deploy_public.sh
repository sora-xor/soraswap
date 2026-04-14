#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

public_env="${SORASWAP_PUBLIC_ENV:-testnet}"
case "$public_env" in
  testnet|production)
    ;;
  *)
    echo "deploy_public.sh only supports SORASWAP_PUBLIC_ENV=testnet|production; got $public_env" >&2
    exit 1
    ;;
  esac

public_env_upper="${(U)public_env}"

config="$(client_config_or_default "$public_env")"
ensure_client "$config"
ensure_authority "$config"
prepare_env_chain_state "$public_env" "$config"
deploy_report_init "$public_env" "$config"

bootstrap_assets_requested_var="SORASWAP_${public_env_upper}_BOOTSTRAP"
bootstrap_assets_requested="${(P)bootstrap_assets_requested_var:-${SORASWAP_PUBLIC_BOOTSTRAP:-0}}"

deploy_failed=1
trap 'if [[ ${deploy_failed:-1} -ne 0 ]]; then deploy_report_finish "$public_env" failed || true; fi' EXIT

deploy_report_set_phase "$public_env" preflight running "$(jq -cn \
  --arg authority "$SORASWAP_AUTHORITY" \
  --arg config "$config" \
  '{authority: $authority, client_config: $config}')"
warn_if_public_tx_gossip_cap_low "$config"
if [[ "$public_env" == "testnet" ]]; then
  ensure_public_signer_ready "$config" "$SORASWAP_AUTHORITY" autofund
else
  ensure_public_signer_ready "$config" "$SORASWAP_AUTHORITY" readonly
fi
deploy_report_set_phase "$public_env" preflight completed "$(jq -cn \
  --arg authority "$SORASWAP_AUTHORITY" \
  --arg fee_asset "$(fee_asset_label_for_config "$config")" \
  --arg fee_asset_id "$(fee_asset_definition_id_for_config "$config")" \
  --arg balance "$(asset_value_for_account_id "$config" "$(fee_asset_definition_id_for_config "$config")" "$SORASWAP_AUTHORITY")" \
  '{authority: $authority, fee_asset: $fee_asset, fee_asset_id: $fee_asset_id, balance: $balance}')"

if [[ "$bootstrap_assets_requested" == "1" ]]; then
  deploy_report_set_phase "$public_env" bootstrap_assets running null
  "$SORASWAP_ROOT/scripts/bootstrap_assets.sh" "$public_env"
  deploy_report_set_phase "$public_env" bootstrap_assets completed null
else
  echo "skipping $public_env bootstrap; set ${bootstrap_assets_requested_var}=1 or SORASWAP_PUBLIC_BOOTSTRAP=1 for the one-time public domain/asset setup"
  deploy_report_set_phase "$public_env" bootstrap_assets skipped null
fi

deploy_report_set_phase "$public_env" compile running null
"$SORASWAP_ROOT/scripts/compile_contracts.sh"
deploy_report_set_phase "$public_env" compile completed null

deploy_report_set_phase "$public_env" nested_call_probe running null
if nested_call_probe_json="$(ensure_nested_call_runtime_supported "$public_env" "$config")"; then
  deploy_report_set_phase "$public_env" nested_call_probe completed "$nested_call_probe_json"
else
  nested_call_probe_json='null'
  nested_call_probe_summary=""
  if [[ -f "$(nested_call_probe_latest_path_for_env "$public_env")" ]]; then
    nested_call_probe_json="$(cat "$(nested_call_probe_latest_path_for_env "$public_env")")"
    nested_call_probe_summary="$(jq -r '.summary // empty' <<<"$nested_call_probe_json" 2>/dev/null || true)"
  fi
  deploy_report_set_phase "$public_env" nested_call_probe failed "$nested_call_probe_json"
  if [[ -n "$nested_call_probe_summary" ]]; then
    echo "$public_env deploy blocked: $nested_call_probe_summary" >&2
  else
    echo "$public_env deploy blocked: the public environment rejected the minimal nested call_contract(...) probe" >&2
  fi
  echo "evidence: $(nested_call_probe_latest_path_for_env "$public_env")" >&2
  exit 1
fi

deploy_report_set_phase "$public_env" deploy running null
while IFS= read -r contract; do
  contract_key="$(contract_id_for "$contract")"
  rm -f \
    "$(deployment_record_path_for_env "$public_env" "$contract_key")" \
    "$SORASWAP_ROOT/deployments/${public_env}/${contract_key}.manifest.json"
done < <(list_contracts)
rm -f "$(contract_bundle_receipt_path_for_env "$public_env")"
bundle_receipt_json="$(submit_contract_app_bundle "$config" deploy)"
materialize_contract_bundle_records_for_env "$public_env" "$bundle_receipt_json"
deploy_report_set_phase "$public_env" deploy completed "$(jq -cn \
  --arg bundle_digest "$(jq -r '.bundle_digest' <<<"$bundle_receipt_json")" \
  --arg total "$(jq -r '.contracts | length' <<<"$bundle_receipt_json")" \
  '{bundle_digest: $bundle_digest, contract_count: ($total|tonumber)}')"

if [[ "${SORASWAP_INIT_CONTRACT_STATE:-1}" == "1" ]]; then
  deploy_report_set_phase "$public_env" bootstrap_contract_state running null
  "$SORASWAP_ROOT/scripts/bootstrap_contract_state.sh" "$public_env"
  deploy_report_set_phase "$public_env" bootstrap_contract_state completed null
else
  echo "skipping post-deploy contract init on $public_env; set SORASWAP_INIT_CONTRACT_STATE=0 only for an explicit debug bypass"
  deploy_report_set_phase "$public_env" bootstrap_contract_state skipped null
fi

report_dir="$(deployments_dir_for_env "$public_env")"
timestamp="$(utc_timestamp)"
contracts_latest_path="$(contracts_snapshot_latest_path_for_env "$public_env")"
contracts_timestamped_path="$(contracts_snapshot_timestamped_path_for_env "$public_env" "$timestamp")"
mkdir -p "$report_dir"
deploy_report_set_phase "$public_env" deployment_records_snapshot running null
snapshot_json="$(deployment_records_snapshot_json_for_env "$public_env" "$timestamp")"
printf '%s\n' "$snapshot_json" > "$contracts_latest_path"
printf '%s\n' "$snapshot_json" > "$contracts_timestamped_path"
deploy_report_set_phase "$public_env" deployment_records_snapshot completed "$(jq -cn --arg path "$contracts_timestamped_path" '{snapshot: $path}')"
deploy_report_finish "$public_env" completed
deploy_failed=0
trap - EXIT
echo "$public_env deployment snapshot: $contracts_timestamped_path"
