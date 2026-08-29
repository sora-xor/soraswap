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
require_public_mutation_consent "$public_env" "$public_env deploy"

init_contract_state="${SORASWAP_INIT_CONTRACT_STATE:-1}"
skip_public_signer_ready_check="${SORASWAP_SKIP_PUBLIC_SIGNER_READY_CHECK:-0}"
soraswap_require_binary_integer_setting "SORASWAP_INIT_CONTRACT_STATE" "$init_contract_state" || exit 1
soraswap_require_binary_integer_setting "SORASWAP_SKIP_PUBLIC_SIGNER_READY_CHECK" "$skip_public_signer_ready_check" || exit 1
bootstrap_assets_requested_var="SORASWAP_${public_env_upper}_BOOTSTRAP"
bootstrap_assets_requested="${(P)bootstrap_assets_requested_var:-${SORASWAP_PUBLIC_BOOTSTRAP:-auto}}"
reuse_contracts_requested_var="SORASWAP_${public_env_upper}_DEPLOY_REUSE_CONTRACTS"
reuse_contracts_requested="${(P)reuse_contracts_requested_var:-${SORASWAP_PUBLIC_DEPLOY_REUSE_CONTRACTS:-auto}}"
case "$bootstrap_assets_requested" in
  auto|0|1)
    ;;
  *)
    echo "$bootstrap_assets_requested_var/SORASWAP_PUBLIC_BOOTSTRAP must be auto, 0, or 1; got '$bootstrap_assets_requested'" >&2
    exit 1
    ;;
esac
case "$reuse_contracts_requested" in
  auto|0|1)
    ;;
  *)
    echo "$reuse_contracts_requested_var/SORASWAP_PUBLIC_DEPLOY_REUSE_CONTRACTS must be auto, 0, or 1; got '$reuse_contracts_requested'" >&2
    exit 1
    ;;
esac

config="$(client_config_or_default "$public_env")"
ensure_client "$config"
ensure_authority "$config"
prepare_env_chain_state "$public_env" "$config"
previous_deploy_report_json='null'
previous_deploy_report_path="$(deploy_report_latest_path_for_env "$public_env")"
if [[ -s "$previous_deploy_report_path" ]]; then
  previous_deploy_report_json="$(jq -c . "$previous_deploy_report_path" 2>/dev/null || echo 'null')"
fi
deploy_report_init "$public_env" "$config"

deploy_failed=1
cleanup_deploy_public() {
  local exit_status="$?"

  if [[ ${deploy_failed:-1} -ne 0 ]]; then
    deploy_report_mark_running_phase_failed \
      "$public_env" \
      "$config" \
      "$exit_status" \
      "deploy_public.sh stopped before completing $public_env deployment" || true
    deploy_report_finish "$public_env" failed || true
    deploy_report_preserve_failed_latest "$public_env" "$previous_deploy_report_json" || true
  fi
  return "$exit_status"
}
trap cleanup_deploy_public EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

deploy_public_direct_per_contract() {
  while IFS= read -r contract; do
    deploy_one "$config" "$contract" "$public_env"
  done < <(list_contracts)
}

deploy_public_previous_report_allows_contract_reuse() {
  local previous_json="$1"

  jq -e --arg env "$public_env" '
    type == "object"
    and (.environment // "") == $env
    and (.status // "") == "failed"
    and (.phases.deploy.status // "") == "completed"
    and (
      (.phases.bootstrap_contract_state.status // "") != "completed"
      or (.phases.deployment_records_snapshot.status // "") != "completed"
    )
  ' <<<"$previous_json" >/dev/null 2>&1
}

deploy_report_set_phase "$public_env" preflight running "$(jq -cn \
  --arg authority "$SORASWAP_AUTHORITY" \
  --arg config "$(soraswap_display_path "$config")" \
  '{authority: $authority, client_config: $config}')"
warn_if_public_tx_gossip_cap_low "$config"
signer_ready_mode=readonly
if [[ "$public_env" == "testnet" ]]; then
  signer_ready_mode=autofund
fi
signer_ready_check_status=completed
signer_ready_debug_bypass=false
if [[ "$public_env" == "production" && "$skip_public_signer_ready_check" == "1" ]]; then
  echo "SORASWAP_SKIP_PUBLIC_SIGNER_READY_CHECK is not permitted for production" >&2
  exit 1
fi
if [[ "$skip_public_signer_ready_check" == "1" ]]; then
  signer_ready_check_status=skipped
  signer_ready_debug_bypass=true
else
  deploy_report_run_phase_command "$public_env" "$config" preflight \
    ensure_public_signer_ready "$config" "$SORASWAP_AUTHORITY" "$signer_ready_mode" || exit $?
fi
operator_permissions_json='null'
if [[ "$public_env" == "production" ]]; then
  deploy_report_run_phase_command "$public_env" "$config" preflight \
    require_production_operator_permissions "$config" "$SORASWAP_AUTHORITY" || exit $?
  operator_permissions_json="$(production_operator_permission_readiness_json "$config" "$SORASWAP_AUTHORITY")"
else
  deploy_report_run_phase_command "$public_env" "$config" preflight \
    ensure_can_register_trigger_permission "$config" "$SORASWAP_AUTHORITY" || exit $?
fi
deploy_report_set_phase "$public_env" preflight completed "$(jq -cn \
  --arg authority "$SORASWAP_AUTHORITY" \
  --arg fee_asset "$(fee_asset_label_for_config "$config")" \
  --arg fee_asset_id "$(fee_asset_definition_id_for_config "$config")" \
  --arg balance "$(asset_value_for_account_id "$config" "$(fee_asset_definition_id_for_config "$config")" "$SORASWAP_AUTHORITY")" \
  --arg signer_ready_mode "$signer_ready_mode" \
  --arg signer_ready_check_status "$signer_ready_check_status" \
  --argjson signer_ready_debug_bypass "$signer_ready_debug_bypass" \
  --argjson operator_permissions "$operator_permissions_json" \
  '{
    authority: $authority,
    fee_asset: $fee_asset,
    fee_asset_id: $fee_asset_id,
    balance: $balance,
    signer_ready_check: {
      status: $signer_ready_check_status,
      mode: $signer_ready_mode,
      debug_bypass_env: (if $signer_ready_debug_bypass then "SORASWAP_SKIP_PUBLIC_SIGNER_READY_CHECK" else null end)
    },
    operator_permissions: $operator_permissions
  }')"

if [[ "$bootstrap_assets_requested" == "auto" ]]; then
  if public_helper_asset_bootstrap_needed "$config"; then
    bootstrap_assets_requested=1
  else
    bootstrap_assets_requested=0
  fi
fi
case "$bootstrap_assets_requested" in
  0|1)
    ;;
  *)
    echo "$bootstrap_assets_requested_var/SORASWAP_PUBLIC_BOOTSTRAP must be auto, 0, or 1; got '$bootstrap_assets_requested'" >&2
    exit 1
    ;;
esac

if [[ "$bootstrap_assets_requested" == "1" ]]; then
  deploy_report_set_phase "$public_env" bootstrap_assets running null
  deploy_report_run_phase_command "$public_env" "$config" bootstrap_assets \
    zsh "$SORASWAP_ROOT/scripts/bootstrap_assets.sh" "$public_env" || exit $?
  deploy_report_set_phase "$public_env" bootstrap_assets completed null
else
  echo "skipping $public_env bootstrap; helper domain/assets are already present (set ${bootstrap_assets_requested_var}=1 or SORASWAP_PUBLIC_BOOTSTRAP=1 to force)"
  deploy_report_set_phase "$public_env" bootstrap_assets skipped null
fi

deploy_report_set_phase "$public_env" compile running null
deploy_report_run_phase_command "$public_env" "$config" compile \
  zsh "$SORASWAP_ROOT/scripts/compile_contracts.sh" || exit $?
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
    echo "$public_env deploy blocked: $(soraswap_redact_sensitive_text "$nested_call_probe_summary")" >&2
  else
    echo "$public_env deploy blocked: the public environment rejected the minimal nested call_contract(...) probe" >&2
  fi
  echo "evidence: $(soraswap_display_path "$(nested_call_probe_latest_path_for_env "$public_env")")" >&2
  exit 1
fi

deploy_report_set_phase "$public_env" deploy running null
reuse_contracts=0
reuse_check_json='null'
if [[ "$reuse_contracts_requested" != "0" ]]; then
  reuse_check_json="$(public_reusable_contracts_snapshot_check_json "$public_env" "$SORASWAP_CHAIN_FINGERPRINT_JSON")"
  if [[ "$(jq -r '.status // empty' <<<"$reuse_check_json")" == "completed" ]]; then
    if [[ "$reuse_contracts_requested" == "1" ]] \
      || deploy_public_previous_report_allows_contract_reuse "$previous_deploy_report_json"; then
      reuse_contracts=1
    fi
  elif [[ "$reuse_contracts_requested" == "1" ]]; then
    deploy_report_set_phase "$public_env" deploy failed "$reuse_check_json" || true
    echo "$public_env deploy blocked: requested contract snapshot reuse, but the current contracts snapshot is not reusable" >&2
    jq -r '.output // empty' <<<"$reuse_check_json" | soraswap_redact_sensitive_text >&2
    exit 1
  fi
fi

if (( reuse_contracts == 1 )); then
  echo "$public_env deploy: reusing current contracts snapshot; resuming bootstrap/snapshot phases"
  deploy_report_set_phase "$public_env" deploy completed "$(jq -cn \
    --arg strategy "reuse_current_contracts" \
    --arg requested "$reuse_contracts_requested" \
    --arg previous_status "$(jq -r '.status // empty' <<<"$previous_deploy_report_json" 2>/dev/null || true)" \
    --arg previous_generated_at "$(jq -r '.generated_at // empty' <<<"$previous_deploy_report_json" 2>/dev/null || true)" \
    --argjson reuse_check "$reuse_check_json" \
    '{
      strategy: $strategy,
      requested: $requested,
      reason: "previous public deploy completed contract submission but did not finish bootstrap/snapshot phases",
      previous_deploy_report: {
        status: (if $previous_status == "" then null else $previous_status end),
        generated_at: (if $previous_generated_at == "" then null else $previous_generated_at end)
      },
      contracts_snapshot: $reuse_check.contracts_snapshot
    }')"
else
  while IFS= read -r contract; do
    contract_key="$(contract_id_for "$contract")"
    rm -f \
      "$(deployment_record_path_for_env "$public_env" "$contract_key")" \
      "$SORASWAP_ROOT/deployments/${public_env}/${contract_key}.manifest.json"
  done < <(list_contracts)
  deploy_report_run_phase_command "$public_env" "$config" deploy \
    deploy_public_direct_per_contract || exit $?
  deploy_report_set_phase "$public_env" deploy completed "$(jq -cn \
    --arg total "$(list_contracts | wc -l | tr -d ' ')" \
    '{
      strategy: "ivm_contract_deploy_per_contract",
      contract_count: ($total|tonumber)
    }')"
fi

if [[ "$init_contract_state" == "1" ]]; then
  deploy_report_set_phase "$public_env" bootstrap_contract_state running null
  deploy_report_run_phase_command "$public_env" "$config" bootstrap_contract_state \
    zsh "$SORASWAP_ROOT/scripts/bootstrap_contract_state.sh" "$public_env" || exit $?
  permission_provisioning_json='null'
  if [[ "$public_env" == "production" && -s "$(deployments_dir_for_env "$public_env")/permission_provisioning.latest.json" ]]; then
    permission_provisioning_json="$(jq -c . "$(deployments_dir_for_env "$public_env")/permission_provisioning.latest.json")"
  fi
  deploy_report_set_phase "$public_env" bootstrap_contract_state completed "$(jq -cn \
    --argjson permission_provisioning "$permission_provisioning_json" \
    '{permission_provisioning: $permission_provisioning}')"
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
cleanup_stale_deployment_records_for_env "$public_env"
snapshot_json="$(deployment_records_snapshot_json_for_env "$public_env" "$timestamp")"
soraswap_write_json_report_pair "$snapshot_json" "$contracts_latest_path" "$contracts_timestamped_path"
deploy_report_set_phase "$public_env" deployment_records_snapshot completed "$(jq -cn --arg path "$(soraswap_display_path "$contracts_timestamped_path")" '{snapshot: $path}')"
deploy_report_finish "$public_env" completed
deploy_failed=0
trap - EXIT
trap - HUP INT TERM
echo "$public_env deployment snapshot: $(soraswap_display_path "$contracts_timestamped_path")"
