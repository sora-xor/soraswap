#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"
source "$SORASWAP_ROOT/scripts/validation_fee_evidence.sh"

readonly TAIRA_VALIDATION_FEE_CHAIN_ID="fc56984b-2be7-431d-840e-21514d1883f0"
readonly TAIRA_VALIDATION_FEE_CHAIN_DISCRIMINANT=369
readonly VALIDATION_FEE_XOR_ASSET_ID="6TEAJqbb8oEPmLncoNiMRbLEK6tw"
readonly VALIDATION_FEE_SBD_ASSET_ID="7ZepsJTHCVLKsrFFNZGSRGZgvBhv"
readonly VALIDATION_FEE_SEED_AMOUNT=1000

action="${1:-plan}"
case "$action" in
  plan|apply)
    ;;
  *)
    echo "usage: $0 [plan|apply]" >&2
    exit 2
    ;;
esac

pool_contract="${SORASWAP_VALIDATION_FEE_POOL_CONTRACT_ADDRESS:-}"
pool_subject="${SORASWAP_VALIDATION_FEE_POOL_SUBJECT_ACCOUNT_ID:-}"
payout_contract="${SORASWAP_VALIDATION_FEE_PAYOUT_CONTRACT_ADDRESS:-}"
payout_subject="${SORASWAP_VALIDATION_FEE_PAYOUT_SUBJECT_ACCOUNT_ID:-}"
if [[ "$pool_contract" != tairac1* ]]; then
  echo "SORASWAP_VALIDATION_FEE_POOL_CONTRACT_ADDRESS must be a canonical Taira contract address" >&2
  exit 1
fi
if [[ "$payout_contract" != tairac1* ]]; then
  echo "SORASWAP_VALIDATION_FEE_PAYOUT_CONTRACT_ADDRESS must be a canonical Taira contract address" >&2
  exit 1
fi
if [[ "$pool_contract" == "$payout_contract" ]]; then
  echo "pool and payout contract addresses must differ" >&2
  exit 1
fi
if [[ "$pool_subject" != test* || "$pool_subject" == *[[:space:]]* ]]; then
  echo "SORASWAP_VALIDATION_FEE_POOL_SUBJECT_ACCOUNT_ID must be a canonical Taira account" >&2
  exit 1
fi
if [[ "$payout_subject" != test* || "$payout_subject" == *[[:space:]]* ]]; then
  echo "SORASWAP_VALIDATION_FEE_PAYOUT_SUBJECT_ACCOUNT_ID must be a canonical Taira account" >&2
  exit 1
fi
if [[ "$pool_subject" == "$payout_subject" ]]; then
  echo "pool and payout subjects must differ" >&2
  exit 1
fi

hajimari_payload="$(jq -cn \
  --arg base_asset "$VALIDATION_FEE_XOR_ASSET_ID" \
  --arg quote_asset "$VALIDATION_FEE_SBD_ASSET_ID" \
  --arg vault_account "$pool_subject" \
  '{
    base_asset: $base_asset,
    quote_asset: $quote_asset,
    vault_account: $vault_account,
    fee_pips: 3000,
    bin_step: 1,
    active_bin: 0,
    impact_cap_bps: 10000,
    min_reserve_base: 0,
    min_reserve_quote: 0,
    max_bins_per_swap: 8,
    bin_liquidity_cap: 0
  }')"
seed_operations="$(jq -cn \
  --argjson amount "$VALIDATION_FEE_SEED_AMOUNT" \
  '[
    {
      position_id: "validation_fee_seed_bin_0",
      bin_id: 0,
      base_amount: $amount,
      quote_amount: $amount
    },
    {
      position_id: "validation_fee_seed_bin_1",
      bin_id: 1,
      base_amount: $amount,
      quote_amount: $amount
    },
    {
      position_id: "validation_fee_seed_bin_2",
      bin_id: 2,
      base_amount: $amount,
      quote_amount: $amount
    }
  ]')"
plan_json="$(jq -cn \
  --arg chain_id "$TAIRA_VALIDATION_FEE_CHAIN_ID" \
  --argjson chain_discriminant "$TAIRA_VALIDATION_FEE_CHAIN_DISCRIMINANT" \
  --arg pool_contract "$pool_contract" \
  --arg pool_subject "$pool_subject" \
  --arg payout_contract "$payout_contract" \
  --arg payout_subject "$payout_subject" \
  --arg xor_asset "$VALIDATION_FEE_XOR_ASSET_ID" \
  --arg sbd_asset "$VALIDATION_FEE_SBD_ASSET_ID" \
  --argjson hajimari "$hajimari_payload" \
  --argjson seeds "$seed_operations" \
  '{
    schema_version: 1,
    status: "undeployed_plan",
    network: "taira",
    chain_id: $chain_id,
    chain_discriminant: $chain_discriminant,
    pool: {
      contract_address: $pool_contract,
      subject_account_id: $pool_subject,
      base_asset_definition_id: $xor_asset,
      quote_asset_definition_id: $sbd_asset
    },
    payout_contract_address: $payout_contract,
    payout_subject_account_id: $payout_subject,
    operations: (
      [{order: 1, entrypoint: "hajimari", arguments: $hajimari}]
      + ($seeds | to_entries | map({
          order: (.key + 2),
          entrypoint: "seed_bin",
          arguments: .value
        }))
      + [{order: 5, entrypoint: "renounce_admin", arguments: {}}]
    ),
    temporary_permissions: [
      {
        holder: "operator",
        name: "CanInvokeContractEntrypoint",
        contract: $pool_contract,
        entrypoint: "hajimari"
      },
      {
        holder: "operator",
        name: "CanInvokeContractEntrypoint",
        contract: $pool_contract,
        entrypoint: "seed_bin"
      },
      {
        holder: "operator",
        name: "CanInvokeContractEntrypoint",
        contract: $pool_contract,
        entrypoint: "renounce_admin"
      },
      {
        holder: $pool_subject,
        name: "CanTransferAsset",
        asset_definition: $xor_asset,
        asset_account: "operator",
        scope: "dataspace:0"
      },
      {
        holder: $pool_subject,
        name: "CanTransferAsset",
        asset_definition: $sbd_asset,
        asset_account: "operator",
        scope: "dataspace:0"
      }
    ],
    protected_runtime_permissions: [
      {
        holder: $payout_subject,
        name: "CanInvokeContractEntrypoint",
        contract: $payout_contract,
        entrypoint: "autonomous_validation_fee_tick",
        required_absent_before_enactment: true,
        sole_direct_holder: true,
        role_holders: false,
        provisioned_by: "protected_core_validation_fee_lifecycle",
        external_bootstrap_action: "none",
        post_activation_verification: "required"
      },
      {
        holder: $payout_subject,
        name: "CanInvokeContractEntrypoint",
        contract: $pool_contract,
        entrypoint: "swap_exact_in_quote_public",
        required_absent_before_enactment: true,
        sole_direct_holder: true,
        role_holders: false,
        provisioned_by: "protected_core_validation_fee_lifecycle",
        external_bootstrap_action: "none",
        post_activation_verification: "required"
      },
      {
        holder: $pool_subject,
        name: "CanTransferAsset",
        asset: ($sbd_asset + "#" + $payout_subject + "#dataspace:0"),
        required_absent_before_enactment: true,
        sole_direct_holder: true,
        role_holders: false,
        provisioned_by: "protected_core_validation_fee_lifecycle",
        external_bootstrap_action: "none",
        post_activation_verification: "required"
      }
    ],
    verification_views: [
      "pool_config",
      "risk_config",
      "mirror_position",
      "mirror_bin",
      "admin_state",
      "range_governor_state"
    ]
  }')"

if [[ "$action" == "plan" ]]; then
  printf '%s\n' "$plan_json"
  exit 0
fi

validation_fee_bootstrap_preflight_guard_and_unlock() {
  local original_status="$1"
  local guard_status=0 unlock_status=0
  local guard_config="${config:-${SORASWAP_VALIDATION_FEE_POOL_CLIENT_CONFIG:-}}"
  local guard_recovery="${recovery_evidence_path:-${SORASWAP_VALIDATION_FEE_POOL_RECOVERY_EVIDENCE_PATH:-}}"
  local guard_permissions guard_topology='null' guard_json guard_target timestamp
  local guard_authority="${SORASWAP_AUTHORITY:-}"

  if [[ -n "$guard_config" && -n "$pool_contract" && -n "$pool_subject" ]]; then
    if [[ -z "$guard_authority" ]]; then
      ensure_client "$guard_config" >/dev/null 2>&1 || guard_status=1
      ensure_authority "$guard_config" >/dev/null 2>&1 || guard_status=1
      guard_authority="${SORASWAP_AUTHORITY:-}"
    fi
    if (( guard_status == 0 )) && [[ -n "$guard_authority" ]]; then
      guard_permissions="$(jq -cn \
        --arg operator "$guard_authority" \
        --arg pool_subject "$pool_subject" \
        --arg pool_contract "$pool_contract" \
        --arg xor_asset "$VALIDATION_FEE_XOR_ASSET_ID#$guard_authority#dataspace:0" \
        --arg sbd_asset "$VALIDATION_FEE_SBD_ASSET_ID#$guard_authority#dataspace:0" \
        '[
          {
            holder: $operator,
            name: "CanInvokeContractEntrypoint",
            payload: {contract: $pool_contract, entrypoint: "hajimari"}
          },
          {
            holder: $operator,
            name: "CanInvokeContractEntrypoint",
            payload: {contract: $pool_contract, entrypoint: "seed_bin"}
          },
          {
            holder: $operator,
            name: "CanInvokeContractEntrypoint",
            payload: {contract: $pool_contract, entrypoint: "renounce_admin"}
          },
          {
            holder: $pool_subject,
            name: "CanTransferAsset",
            payload: {asset: $xor_asset}
          },
          {
            holder: $pool_subject,
            name: "CanTransferAsset",
            payload: {asset: $sbd_asset}
          }
        ]')"
      guard_topology="$(
        validation_fee_direct_permission_topology_json \
          "$guard_config" "$guard_permissions" 2>/dev/null
      )" || guard_status=1
    fi
  fi
  if (( guard_status != 0 )) \
    || jq -e 'type == "array" and any(.[]; .present == true)' \
      >/dev/null <<<"$guard_topology"; then
    echo "CRITICAL: bootstrap preflight could not prove temporary permissions absent; no safe ledger direct-submit adapter exists for cleanup" >&2
    guard_status=1
    if [[ -n "$guard_recovery" && "$guard_recovery" == /* \
      && -d "${guard_recovery:h}" && ! -L "${guard_recovery:h}" \
      && "${guard_recovery:h:A}" == "${guard_recovery:h}" ]]; then
      timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
      guard_target="${guard_recovery%.json}.preflight-critical.$timestamp-$$.json"
      guard_json="$(jq -cn \
        --argjson original_status "$original_status" \
        --argjson topology "$guard_topology" \
        '{
          schema_version: 1,
          status: "emergency_cleanup_blocked_no_safe_ledger_submit",
          original_exit_status: $original_status,
          temporary_permission_topology: $topology
        }')"
      validation_fee_write_immutable_json \
        "$guard_json" "$guard_target" >/dev/null 2>&1 || true
    fi
  fi
  validation_fee_release_apply_lock || unlock_status=$?
  if (( guard_status != 0 || unlock_status != 0 )); then
    return 1
  fi
  return "$original_status"
}

validation_fee_bootstrap_preflight_signal() {
  validation_fee_signal_cleanup_and_exit \
    "$1" "$2" validation_fee_bootstrap_preflight_guard_and_unlock
}

if [[ "${SORASWAP_PUBLIC_ENV:-}" != "testnet" ]]; then
  echo "apply requires SORASWAP_PUBLIC_ENV=testnet" >&2
  exit 1
fi
if [[ "${SORASWAP_VALIDATION_FEE_POOL_APPLY:-0}" != "1" ]]; then
  echo "apply requires SORASWAP_VALIDATION_FEE_POOL_APPLY=1" >&2
  exit 1
fi
require_public_mutation_consent testnet "Taira validation-fee XOR/SBD pool bootstrap"
preflight_state_root="${SORASWAP_VALIDATION_FEE_STATE_ROOT:-}"
preflight_bound_evidence_root="${SORASWAP_VALIDATION_FEE_BOUND_EVIDENCE_ROOT:-}"
preflight_bound_work_root="${SORASWAP_VALIDATION_FEE_BOUND_WORK_ROOT:-}"
if [[ -z "$preflight_state_root" || "$preflight_state_root" != /* \
  || "$preflight_state_root" != "${preflight_state_root:A}" \
  || -z "$preflight_bound_evidence_root" \
  || "$preflight_bound_evidence_root" != /* \
  || "$preflight_bound_evidence_root" != "${preflight_bound_evidence_root:A}" \
  || -z "$preflight_bound_work_root" \
  || "$preflight_bound_work_root" != /* \
  || "$preflight_bound_work_root" != "${preflight_bound_work_root:A}" ]]; then
  echo "pool bootstrap requires canonical state/evidence/work root bindings" >&2
  exit 1
fi
if [[ "$preflight_state_root" == "$preflight_bound_evidence_root" \
  || "$preflight_state_root" == "$preflight_bound_evidence_root/"* \
  || "$preflight_bound_evidence_root" == "$preflight_state_root/"* \
  || "$preflight_state_root" == "$preflight_bound_work_root" \
  || "$preflight_state_root" == "$preflight_bound_work_root/"* \
  || "$preflight_bound_work_root" == "$preflight_state_root/"* ]]; then
  echo "pool bootstrap state root must not overlap bound evidence/work roots" >&2
  exit 1
fi
bootstrap_invocation_history_dir="$(
  validation_fee_taira_p1_invocation_journal_dir
)"
if [[ ! -d "$bootstrap_invocation_history_dir" \
  || -L "$bootstrap_invocation_history_dir" ]]; then
  echo "durable Taira P1 write-gate history is absent before pool bootstrap" >&2
  exit 1
fi
canonical_apply_lock_dir="$(validation_fee_taira_p1_apply_lock_dir)"
parent_apply_lock_dir="${SORASWAP_VALIDATION_FEE_PARENT_LOCK_DIR:-}"
parent_apply_lock_token="${SORASWAP_VALIDATION_FEE_PARENT_LOCK_TOKEN:-}"
if [[ -n "$parent_apply_lock_dir" || -n "$parent_apply_lock_token" ]]; then
  if [[ -z "$parent_apply_lock_dir" || -z "$parent_apply_lock_token" ]]; then
    echo "pool apply received an incomplete parent lock handoff" >&2
    exit 1
  fi
  if [[ "$parent_apply_lock_dir" != "$canonical_apply_lock_dir" ]]; then
    echo "parent apply lock is not the fixed Taira P1 deployment lock" >&2
    exit 1
  fi
  validation_fee_borrow_parent_apply_lock \
    "$parent_apply_lock_dir" "$parent_apply_lock_token"
else
  validation_fee_acquire_apply_lock "$canonical_apply_lock_dir"
fi
trap 'validation_fee_bootstrap_preflight_guard_and_unlock $?' EXIT
trap 'validation_fee_bootstrap_preflight_signal INT 130' INT
trap 'validation_fee_bootstrap_preflight_signal TERM 143' TERM
validation_fee_assert_write_gate_history_dir \
  "$bootstrap_invocation_history_dir"
validation_fee_require_one_write_mode
validation_fee_assert_write_reservation_history_dir \
  "$bootstrap_invocation_history_dir"

config="${SORASWAP_VALIDATION_FEE_POOL_CLIENT_CONFIG:-}"
if [[ -z "$config" ]]; then
  echo "apply requires explicit SORASWAP_VALIDATION_FEE_POOL_CLIENT_CONFIG" >&2
  exit 1
fi
ensure_client "$config"
ensure_authority "$config"

config_chain_id="$(config_chain_id_from_config "$config")"
if [[ "$config_chain_id" != "$TAIRA_VALIDATION_FEE_CHAIN_ID" ]]; then
  echo "validation-fee pool config must use Taira chain $TAIRA_VALIDATION_FEE_CHAIN_ID; got $config_chain_id" >&2
  exit 1
fi
config_discriminant="$(chain_discriminant_for_env_config testnet "$config")"
if [[ "$config_discriminant" != "$TAIRA_VALIDATION_FEE_CHAIN_DISCRIMINANT" ]]; then
  echo "validation-fee pool config must use chain discriminant $TAIRA_VALIDATION_FEE_CHAIN_DISCRIMINANT; got $config_discriminant" >&2
  exit 1
fi
live_chain_json="$(current_chain_fingerprint_json "$config")"
live_chain_id="$(jq -er '.chain' <<<"$live_chain_json")"
if [[ "$live_chain_id" != "$TAIRA_VALIDATION_FEE_CHAIN_ID" ]]; then
  echo "live Torii is not the pinned Taira chain $TAIRA_VALIDATION_FEE_CHAIN_ID; got $live_chain_id" >&2
  exit 1
fi
expected_block_1_hash="${SORASWAP_VALIDATION_FEE_EXPECTED_BLOCK_1_HASH:-}"
if [[ ! "$expected_block_1_hash" =~ '^[0-9a-f]{64}$' \
  || "$(jq -er '.block_1_hash' <<<"$live_chain_json")" \
    != "$expected_block_1_hash" ]]; then
  echo "validation-fee pool config is not on the reviewed fresh Taira block-1 hash" >&2
  exit 1
fi

derived_pool_subject="$(contract_subject_account_for_literal "$config" "$pool_contract")"
if [[ "$derived_pool_subject" != "$pool_subject" ]]; then
  echo "pool subject does not match the deterministic subject derived from the contract address" >&2
  exit 1
fi
derived_payout_subject="$(contract_subject_account_for_literal "$config" "$payout_contract")"
if [[ "$derived_payout_subject" != "$payout_subject" ]]; then
  echo "payout subject does not match the deterministic subject derived from the contract address" >&2
  exit 1
fi

deployment_plan_evidence_path="${SORASWAP_VALIDATION_FEE_DEPLOYMENT_PLAN_EVIDENCE_PATH:-}"
preflight_evidence_path="${SORASWAP_VALIDATION_FEE_PREFLIGHT_EVIDENCE_PATH:-}"
pool_deployment_evidence_path="${SORASWAP_VALIDATION_FEE_POOL_DEPLOYMENT_EVIDENCE_PATH:-}"
payout_deployment_evidence_path="${SORASWAP_VALIDATION_FEE_PAYOUT_DEPLOYMENT_EVIDENCE_PATH:-}"
pool_evidence_path="${SORASWAP_VALIDATION_FEE_POOL_EVIDENCE_PATH:-}"
recovery_evidence_path="${SORASWAP_VALIDATION_FEE_POOL_RECOVERY_EVIDENCE_PATH:-}"
bootstrap_work_journal_dir="${SORASWAP_VALIDATION_FEE_POOL_WORK_JOURNAL_DIR:-}"
bootstrap_mutation_journal_dir="${SORASWAP_VALIDATION_FEE_POOL_MUTATION_JOURNAL_DIR:-}"
bootstrap_prepared_ledger_dir="${SORASWAP_VALIDATION_FEE_POOL_PREPARED_LEDGER_DIR:-}"
for evidence_file in \
  "$deployment_plan_evidence_path" \
  "$preflight_evidence_path" \
  "$pool_deployment_evidence_path" \
  "$payout_deployment_evidence_path"; do
  if [[ -z "$evidence_file" || "$evidence_file" != /* ]]; then
    echo "pool apply requires absolute reviewed deployment evidence paths" >&2
    exit 1
  fi
  validation_fee_require_immutable_json_file "$evidence_file"
done
if [[ -z "$pool_evidence_path" || "$pool_evidence_path" != /* ]]; then
  echo "pool apply requires an absolute canonical bootstrap evidence path" >&2
  exit 1
fi
if [[ -z "$recovery_evidence_path" || "$recovery_evidence_path" != /* ]]; then
  echo "pool apply requires an absolute emergency recovery evidence path" >&2
  exit 1
fi
if [[ -z "$bootstrap_work_journal_dir" \
  || "$bootstrap_work_journal_dir" != /* ]]; then
  echo "pool apply requires an absolute append-only bootstrap work journal directory" >&2
  exit 1
fi
if [[ -z "$bootstrap_mutation_journal_dir" \
  || "$bootstrap_mutation_journal_dir" != /* ]]; then
  echo "pool apply requires an absolute durable mutation journal directory" >&2
  exit 1
fi
if [[ -z "$bootstrap_prepared_ledger_dir" \
  || "$bootstrap_prepared_ledger_dir" != /* ]]; then
  echo "pool apply requires an absolute prepared typed-ledger directory" >&2
  exit 1
fi
bootstrap_state_root="$(validation_fee_taira_p1_state_root)"
bound_evidence_root="${SORASWAP_VALIDATION_FEE_BOUND_EVIDENCE_ROOT:-}"
bound_work_root="${SORASWAP_VALIDATION_FEE_BOUND_WORK_ROOT:-}"
if [[ -z "$bound_evidence_root" || "$bound_evidence_root" != /* \
  || "$bound_evidence_root" != "${bound_evidence_root:A}" \
  || ! -d "$bound_evidence_root" || -L "$bound_evidence_root" \
  || -z "$bound_work_root" || "$bound_work_root" != /* \
  || "$bound_work_root" != "${bound_work_root:A}" \
  || ! -d "$bound_work_root" || -L "$bound_work_root" ]]; then
  echo "pool bootstrap requires the canonical evidence/work roots from state binding" >&2
  exit 1
fi
pool_evidence_parent="${pool_evidence_path:h:A}"
recovery_evidence_parent="${recovery_evidence_path:h:A}"
bootstrap_work_journal_abs="${bootstrap_work_journal_dir:A}"
bootstrap_mutation_journal_abs="${bootstrap_mutation_journal_dir:A}"
bootstrap_prepared_ledger_abs="${bootstrap_prepared_ledger_dir:A}"
if [[ "$bootstrap_work_journal_dir" != "$bootstrap_work_journal_abs" \
  || "$bootstrap_mutation_journal_dir" != "$bootstrap_mutation_journal_abs" \
  || "$bootstrap_prepared_ledger_dir" != "$bootstrap_prepared_ledger_abs" ]]; then
  echo "pool bootstrap work, mutation, and prepared roots must be canonical" >&2
  exit 1
fi
for deployment_evidence_file in \
  "$deployment_plan_evidence_path" \
  "$preflight_evidence_path" \
  "$pool_deployment_evidence_path" \
  "$payout_deployment_evidence_path" \
  "$pool_evidence_path"; do
  if [[ "${deployment_evidence_file:h:A}" != "$bound_evidence_root" ]]; then
    echo "pool bootstrap evidence path is outside its state-bound root" >&2
    exit 1
  fi
done
for bootstrap_work_path in \
  "$recovery_evidence_parent" \
  "$bootstrap_work_journal_abs" \
  "$bootstrap_mutation_journal_abs" \
  "$bootstrap_prepared_ledger_abs"; do
  if [[ "$bootstrap_work_path" != "$bound_work_root/"* ]]; then
    echo "pool bootstrap work path is outside its state-bound work root" >&2
    exit 1
  fi
done
bootstrap_overlap_roots=( \
  "$bootstrap_state_root" "$pool_evidence_parent" \
  "$bootstrap_state_root" "$recovery_evidence_parent" \
  "$bootstrap_state_root" "$bootstrap_work_journal_abs" \
  "$bootstrap_state_root" "$bootstrap_mutation_journal_abs" \
  "$bootstrap_state_root" "$bootstrap_prepared_ledger_abs" \
  "$pool_evidence_parent" "$bootstrap_work_journal_abs" \
  "$pool_evidence_parent" "$bootstrap_mutation_journal_abs" \
  "$pool_evidence_parent" "$bootstrap_prepared_ledger_abs" \
  "$recovery_evidence_parent" "$bootstrap_work_journal_abs" \
  "$recovery_evidence_parent" "$bootstrap_mutation_journal_abs" \
  "$recovery_evidence_parent" "$bootstrap_prepared_ledger_abs" \
  "$bootstrap_work_journal_abs" "$bootstrap_mutation_journal_abs" \
  "$bootstrap_work_journal_abs" "$bootstrap_prepared_ledger_abs" \
  "$bootstrap_mutation_journal_abs" "$bootstrap_prepared_ledger_abs" \
)
for (( overlap_index = 1; overlap_index <= ${#bootstrap_overlap_roots}; overlap_index += 2 )); do
  first_root="${bootstrap_overlap_roots[$overlap_index]}"
  second_root="${bootstrap_overlap_roots[$(( overlap_index + 1 ))]}"
  if [[ "$first_root" == "$second_root" \
    || "$first_root" == "$second_root/"* \
    || "$second_root" == "$first_root/"* ]]; then
    echo "validation-fee bootstrap state/evidence/journal roots overlap" >&2
    exit 1
  fi
done
if [[ -L "${recovery_evidence_path:h}" \
  || ( -e "${recovery_evidence_path:h}" && ! -d "${recovery_evidence_path:h}" ) ]]; then
  echo "pool recovery evidence parent must be a real directory" >&2
  exit 1
fi
validation_fee_ensure_durable_directory "${recovery_evidence_path:h}"
if [[ -L "$bootstrap_work_journal_dir" \
  || ( -e "$bootstrap_work_journal_dir" && ! -d "$bootstrap_work_journal_dir" ) ]]; then
  echo "pool bootstrap work journal must be a real directory" >&2
  exit 1
fi
validation_fee_ensure_durable_directory "$bootstrap_work_journal_dir"
if [[ -L "$bootstrap_mutation_journal_dir" \
  || ( -e "$bootstrap_mutation_journal_dir" \
    && ! -d "$bootstrap_mutation_journal_dir" ) ]]; then
  echo "pool bootstrap mutation journal must be a real directory" >&2
  exit 1
fi
validation_fee_ensure_durable_directory "$bootstrap_mutation_journal_dir"
if [[ -L "$bootstrap_prepared_ledger_dir" \
  || ( -e "$bootstrap_prepared_ledger_dir" \
    && ! -d "$bootstrap_prepared_ledger_dir" ) ]]; then
  echo "pool bootstrap prepared typed-ledger root must be a real directory" >&2
  exit 1
fi
validation_fee_ensure_durable_directory "$bootstrap_prepared_ledger_dir"
deployment_plan_evidence="$(jq -ce . "$deployment_plan_evidence_path")"
deployment_plan_sha256="$(jq -er '.plan_sha256' <<<"$deployment_plan_evidence")"
if [[ "${SORASWAP_VALIDATION_FEE_REVIEWED_PLAN_SHA256:-}" \
  != "$deployment_plan_sha256" ]]; then
  echo "pool bootstrap runtime plan pin differs from immutable plan evidence" >&2
  exit 1
fi
if [[ "$(validation_fee_bound_plan_sha256)" != "$deployment_plan_sha256" ]]; then
  echo "pool bootstrap canonical plan digest differs from its runtime pin" >&2
  exit 1
fi
deployment_write_gate_sha256="$(
  jq -er '.payload.write_gate_command_sha256' <<<"$deployment_plan_evidence"
)"
deployment_state_binding_sha256="$(
  jq -er '.payload.state_binding_sha256' <<<"$deployment_plan_evidence"
)"
deployment_block_1_hash="$(
  jq -er '.payload.block_1_hash' <<<"$deployment_plan_evidence"
)"
if [[ ! "$deployment_write_gate_sha256" =~ '^[0-9a-f]{64}$' \
  || "${SORASWAP_VALIDATION_FEE_WRITE_GATE_COMMAND_SHA256:-}" \
    != "$deployment_write_gate_sha256" ]]; then
  echo "pool bootstrap write-gate producer differs from the immutable deployment binding" >&2
  exit 1
fi
actual_state_binding_sha256="$(
  validation_fee_taira_p1_state_binding_sha256 \
    "$deployment_write_gate_sha256" 0 \
    "$bound_evidence_root" "$bound_work_root"
)"
if [[ ! "$deployment_state_binding_sha256" =~ '^[0-9a-f]{64}$' \
  || "$deployment_state_binding_sha256" != "$actual_state_binding_sha256" \
  || "$deployment_block_1_hash" != "$expected_block_1_hash" ]]; then
  echo "pool bootstrap durable-state or block-1 binding differs from the immutable plan" >&2
  exit 1
fi
parent_state_binding_sha256="${SORASWAP_VALIDATION_FEE_PARENT_STATE_BINDING_SHA256:-}"
if [[ -n "$parent_apply_lock_dir" \
  && "$parent_state_binding_sha256" != "$actual_state_binding_sha256" ]]; then
  echo "pool bootstrap parent handoff lacks the exact durable-state binding" >&2
  exit 1
fi
reviewed_deployment_plan="$(jq -ce '.payload.result.plan' \
  <<<"$deployment_plan_evidence")"
preflight_evidence="$(jq -ce . "$preflight_evidence_path")"
reviewed_deployment_spec_path="${SORASWAP_VALIDATION_FEE_DEPLOY_SPEC:-$SORASWAP_ROOT/config/validation_fee/deployment.taira.p1.json}"
if [[ ! -f "$reviewed_deployment_spec_path" \
  || -L "$reviewed_deployment_spec_path" ]]; then
  echo "reviewed validation-fee deployment spec is missing or not a regular file" >&2
  exit 1
fi
reviewed_deployment_spec="$(jq -ce . "$reviewed_deployment_spec_path")"
reviewed_deployment_spec_sha256="$(
  printf '%s' "$(jq -cS . "$reviewed_deployment_spec_path")" \
    | shasum -a 256 \
    | awk '{print $1}'
)"
if ! jq -e \
  --arg plan_sha256 "$deployment_plan_sha256" \
  --arg authority "$SORASWAP_AUTHORITY" \
  --arg pool_contract "$pool_contract" \
  --arg pool_subject "$pool_subject" \
  --arg payout_contract "$payout_contract" \
  --arg payout_subject "$payout_subject" \
  '
    .schema_version == 1
    and .phase == "plan"
    and (
      .payload.write_gate_command_sha256
      | type == "string" and test("^[0-9a-f]{64}$")
    )
    and (
      .payload.state_binding_sha256
      | type == "string" and test("^[0-9a-f]{64}$")
    )
    and (
      .payload.block_1_hash
      | type == "string" and test("^[0-9a-f]{64}$")
    )
    and .payload.result.plan_sha256 == $plan_sha256
    and .payload.result.plan.status == "undeployed_plan"
    and .payload.result.plan.network == "taira"
    and .payload.result.plan.chain_id
      == "fc56984b-2be7-431d-840e-21514d1883f0"
    and .payload.result.plan.chain_discriminant == 369
    and .payload.result.plan.authority_account_id == $authority
    and (.payload.result.plan.contracts | length == 2)
    and .payload.result.plan.contracts[0].key == "pool"
    and .payload.result.plan.contracts[0].alias
      == "dlmm_pool::dlmm.universal"
    and .payload.result.plan.contracts[0].deploy_nonce == 0
    and .payload.result.plan.contracts[0].contract_address == $pool_contract
    and .payload.result.plan.contracts[0].subject_account_id == $pool_subject
    and .payload.result.plan.contracts[1].key == "payout"
    and .payload.result.plan.contracts[1].alias
      == "autonomous_payout::validation_fee.universal"
    and .payload.result.plan.contracts[1].deploy_nonce == 1
    and .payload.result.plan.contracts[1].contract_address == $payout_contract
    and .payload.result.plan.contracts[1].subject_account_id == $payout_subject
  ' >/dev/null <<<"$deployment_plan_evidence"; then
  echo "pool bootstrap is not bound to the reviewed P1 deployment plan" >&2
  exit 1
fi
if ! jq -en \
  --argjson plan "$reviewed_deployment_plan" \
  --argjson spec "$reviewed_deployment_spec" \
  --arg spec_sha256 "$reviewed_deployment_spec_sha256" \
  '
    $plan.chain_id == $spec.chain_id
    and $plan.chain_discriminant == $spec.chain_discriminant
    and $plan.genesis_sha256 == $spec.genesis_sha256
    and $plan.authority_account_id == $spec.authority_account_id
    and $plan.dataspace == $spec.dataspace
    and $plan.deployment_spec_sha256 == $spec_sha256
    and (
      $plan.contracts | map({
        order,
        key,
        source,
        source_sha256,
        artifact,
        artifact_sha256,
        manifest_sha256,
        alias,
        deploy_nonce,
        contract_address,
        subject_account_id,
        code_hash,
        abi_hash,
        render_metadata,
        render_metadata_sha256
      })
    ) == (
      $spec.contracts | map({
        order,
        key,
        source,
        source_sha256,
        artifact,
        artifact_sha256,
        manifest_sha256,
        alias,
        deploy_nonce,
        contract_address,
        subject_account_id,
        code_hash,
        abi_hash,
        render_metadata,
        render_metadata_sha256
      })
    )
    and $plan.protected_permissions == $spec.protected_permissions
  ' >/dev/null; then
  echo "pool bootstrap plan differs from the checked-in reviewed P1 spec" >&2
  exit 1
fi
if ! jq -e \
  --arg plan_sha256 "$deployment_plan_sha256" \
  --argjson chain_fingerprint "$live_chain_json" \
  --arg authority "$SORASWAP_AUTHORITY" \
  '
    .schema_version == 1
    and .phase == "preflight"
    and .plan_sha256 == $plan_sha256
    and .payload.chain_fingerprint == $chain_fingerprint
    and .payload.authority_account_id == $authority
    and .payload.deploy_nonce == 0
    and .payload.contract_subject_accounts_absent == true
    and .payload.contract_aliases_absent == true
    and .payload.protected_permission_topology.absent == true
  ' >/dev/null <<<"$preflight_evidence"; then
  echo "pool bootstrap is not bound to the reviewed fresh-chain preflight" >&2
  exit 1
fi

verify_journaled_validation_fee_contract() {
  local evidence_path="$1"
  local expected_phase="$2"
  local contract_json="$3"
  local evidence receipt split_receipt transaction alias_json manifest_json
  local expected_alias expected_code_hash

  evidence="$(jq -ce . "$evidence_path")" || return 1
  if ! jq -e \
    --arg expected_phase "$expected_phase" \
    --arg plan_sha256 "$deployment_plan_sha256" \
    '
      .schema_version == 1
      and .phase == $expected_phase
      and .plan_sha256 == $plan_sha256
      and (.payload.receipt | type == "object")
    ' >/dev/null <<<"$evidence"; then
    echo "validation-fee deployment evidence phase is not plan-bound" >&2
    return 1
  fi
  receipt="$(jq -ce '.payload.receipt' <<<"$evidence")" || return 1
  split_receipt="$(jq -ce '.split_receipt' <<<"$receipt")" || return 1
  validation_fee_validate_split_deploy_receipt_json \
    "$split_receipt" "$reviewed_deployment_plan" "$contract_json" >/dev/null \
    || return 1
  if ! jq -e \
    --argjson expected_count "$(
      jq '[.register_bytes_stage_tx_hashes[]] | length + 3' \
        <<<"$split_receipt"
    )" \
    --argjson split "$split_receipt" \
    '
      (.transactions | type == "array" and length == $expected_count)
      and (
        .transactions | map({
          label: .label,
          hash: .transaction.tx_hash
        })
      ) == (
        [
          (
            $split.register_bytes_stage_tx_hashes
            | to_entries[]
            | {
                label: ("register_bytes_stage_" + (.key | tostring)),
                hash: .value
              }
          ),
          {
            label: "register_bytes_finalize",
            hash: $split.register_bytes_tx_hash
          },
          {
            label: "register_manifest",
            hash: $split.register_manifest_tx_hash
          },
          {label: "commit", hash: $split.commit_tx_hash}
        ]
      )
    ' >/dev/null <<<"$receipt"; then
    echo "bootstrap deployment evidence omits or changes a split transaction receipt" >&2
    return 1
  fi
  while IFS= read -r transaction; do
    validation_fee_assert_transaction_evidence_json \
      "$(jq -c '.transaction' <<<"$transaction")" \
      "$(jq -c '.terminal' <<<"$transaction")" || return 1
    validation_fee_reverify_transaction_evidence_json \
      "$config" "$(jq -c '.transaction' <<<"$transaction")" || return $?
  done < <(jq -c '.transactions[]' <<<"$receipt")
  expected_alias="$(jq -er '.alias' <<<"$contract_json")" || return 1
  alias_json="$(contract_alias_resolve_json "$config" "$expected_alias")" \
    || return 1
  validation_fee_assert_alias_resolution \
    "$alias_json" "$contract_json" universal || return 1
  expected_code_hash="$(jq -er '.code_hash' <<<"$contract_json")" || return 1
  manifest_json="$(
    contract_manifest_json_by_code_hash "$config" "$expected_code_hash"
  )" || return 1
  validation_fee_assert_manifest_hashes "$manifest_json" "$contract_json" \
    || return 1
  contract_code_bytes_visible_by_code_hash "$config" "$expected_code_hash" \
    || {
      echo "reviewed validation-fee contract code bytes are not live" >&2
      return 1
    }
}

reviewed_pool_contract="$(jq -ce '.contracts[0]' <<<"$reviewed_deployment_plan")"
reviewed_payout_contract="$(jq -ce '.contracts[1]' <<<"$reviewed_deployment_plan")"
verify_journaled_validation_fee_contract \
  "$pool_deployment_evidence_path" \
  pool_deployment \
  "$reviewed_pool_contract"
verify_journaled_validation_fee_contract \
  "$payout_deployment_evidence_path" \
  payout_deployment \
  "$reviewed_payout_contract"
if [[ "$(contract_deploy_nonce_for_authority "$config" "$SORASWAP_AUTHORITY")" \
  != "2" ]]; then
  echo "reviewed validation-fee contracts must end at authority deploy nonce 2" >&2
  exit 1
fi

# Subject registration is part of the dedicated fresh deployment journal. The
# pool bootstrap must not silently adopt or create either account.
if [[ "$(validation_fee_account_presence "$config" "$pool_subject")" \
  != "present" ]]; then
  echo "pool subject must be registered by the validation-fee deployment runner" >&2
  exit 1
fi
if [[ "$(validation_fee_account_presence "$config" "$payout_subject")" \
  != "present" ]]; then
  echo "payout subject must be registered by the validation-fee deployment runner" >&2
  exit 1
fi

required_seed_total=$(( VALIDATION_FEE_SEED_AMOUNT * 3 ))
xor_balance="$(asset_value_for_account_id "$config" "$VALIDATION_FEE_XOR_ASSET_ID" "$SORASWAP_AUTHORITY")"
sbd_balance="$(asset_value_for_account_id "$config" "$VALIDATION_FEE_SBD_ASSET_ID" "$SORASWAP_AUTHORITY")"
if ! jq -en \
  --arg xor_balance "$xor_balance" \
  --arg sbd_balance "$sbd_balance" \
  --argjson required "$required_seed_total" \
  '($xor_balance | tonumber) >= $required and ($sbd_balance | tonumber) >= $required' \
  >/dev/null; then
  echo "operator must hold at least $required_seed_total XOR and $required_seed_total SBD before bootstrap" >&2
  exit 1
fi

view_result() {
  local entrypoint="$1"
  local payload="${2:-null}"
  contract_view_result_json "$(
    submit_contract_view \
      "$config" \
      "$pool_contract" \
      "$entrypoint" \
      "$SORASWAP_SMOKE_GAS_LIMIT" \
      "$payload"
  )"
}

seed_selector_permission="$(jq -cn \
  --arg contract "$pool_contract" \
  '{name: "CanInvokeContractEntrypoint", payload: {contract: $contract, entrypoint: "seed_bin"}}')"
hajimari_selector_permission="$(jq -cn \
  --arg contract "$pool_contract" \
  '{name: "CanInvokeContractEntrypoint", payload: {contract: $contract, entrypoint: "hajimari"}}')"
renounce_selector_permission="$(jq -cn \
  --arg contract "$pool_contract" \
  '{name: "CanInvokeContractEntrypoint", payload: {contract: $contract, entrypoint: "renounce_admin"}}')"
xor_transfer_permission="$(jq -cn \
  --arg asset "$VALIDATION_FEE_XOR_ASSET_ID#$SORASWAP_AUTHORITY#dataspace:0" \
  '{name: "CanTransferAsset", payload: {asset: $asset}}')"
sbd_transfer_permission="$(jq -cn \
  --arg asset "$VALIDATION_FEE_SBD_ASSET_ID#$SORASWAP_AUTHORITY#dataspace:0" \
  '{name: "CanTransferAsset", payload: {asset: $asset}}')"
temporary_permissions="$(jq -cn \
  --arg operator "$SORASWAP_AUTHORITY" \
  --arg pool_subject "$pool_subject" \
  --argjson hajimari "$hajimari_selector_permission" \
  --argjson seed "$seed_selector_permission" \
  --argjson renounce "$renounce_selector_permission" \
  --argjson xor_transfer "$xor_transfer_permission" \
  --argjson sbd_transfer "$sbd_transfer_permission" \
  '[
    ({holder: $operator} + $hajimari),
    ({holder: $operator} + $seed),
    ({holder: $operator} + $renounce),
    ({holder: $pool_subject} + $xor_transfer),
    ({holder: $pool_subject} + $sbd_transfer)
  ]')"
temporary_permission_specs="$(jq -cn \
  --arg operator "$SORASWAP_AUTHORITY" \
  --arg pool_subject "$pool_subject" \
  --argjson hajimari "$hajimari_selector_permission" \
  --argjson seed "$seed_selector_permission" \
  --argjson renounce "$renounce_selector_permission" \
  --argjson xor_transfer "$xor_transfer_permission" \
  --argjson sbd_transfer "$sbd_transfer_permission" \
  '[
    {key: "hajimari_selector", holder: $operator, permission: $hajimari},
    {key: "seed_selector", holder: $operator, permission: $seed},
    {key: "renounce_selector", holder: $operator, permission: $renounce},
    {key: "xor_transfer", holder: $pool_subject, permission: $xor_transfer},
    {key: "sbd_transfer", holder: $pool_subject, permission: $sbd_transfer}
  ]')"
protected_permissions="$(jq -cn \
  --arg pool_contract "$pool_contract" \
  --arg pool_subject "$pool_subject" \
  --arg payout_contract "$payout_contract" \
  --arg payout_subject "$payout_subject" \
  --arg sbd_asset "$VALIDATION_FEE_SBD_ASSET_ID#$payout_subject#dataspace:0" \
  '[
    {
      holder: $payout_subject,
      name: "CanInvokeContractEntrypoint",
      payload: {
        contract: $payout_contract,
        entrypoint: "autonomous_validation_fee_tick"
      }
    },
    {
      holder: $payout_subject,
      name: "CanInvokeContractEntrypoint",
      payload: {
        contract: $pool_contract,
        entrypoint: "swap_exact_in_quote_public"
      }
    },
    {
      holder: $pool_subject,
      name: "CanTransferAsset",
      payload: {asset: $sbd_asset}
    }
  ]')"
protected_topology_observed="$(
  validation_fee_protected_permission_topology_json \
    "$config" "$protected_permissions"
)"
validation_fee_assert_protected_permission_topology_absent \
  "$protected_topology_observed"
temporary_topology_observed="$(
  validation_fee_direct_permission_topology_json \
    "$config" "$temporary_permissions"
)"
if ! jq -e 'type == "array" and length == 5' \
  >/dev/null <<<"$temporary_topology_observed"; then
  echo "validation-fee bootstrap temporary topology is incomplete" >&2
  exit 1
fi
cleanup_permissions=0
if jq -e 'any(.[]; .present == true)' \
  >/dev/null <<<"$temporary_topology_observed"; then
  cleanup_permissions=1
fi
orphan_permission_revokes='[]'
work_journal_complete=1

if [[ "${pool_evidence_path:h}" == "$bootstrap_work_journal_dir" \
  || "${recovery_evidence_path:h}" == "$bootstrap_work_journal_dir" ]]; then
  echo "canonical and recovery evidence must remain outside the work journal" >&2
  exit 1
fi

contract_operation_specs="$(jq -cn \
  --argjson hajimari "$hajimari_payload" \
  --argjson seeds "$seed_operations" \
  '[
    {key: "hajimari", entrypoint: "hajimari", arguments: $hajimari},
    {
      key: "seed_bin_0",
      entrypoint: "seed_bin",
      arguments: $seeds[0]
    },
    {
      key: "seed_bin_1",
      entrypoint: "seed_bin",
      arguments: $seeds[1]
    },
    {
      key: "seed_bin_2",
      entrypoint: "seed_bin",
      arguments: $seeds[2]
    },
    {key: "renounce_admin", entrypoint: "renounce_admin", arguments: {}}
  ]')"

bootstrap_binding_path="$bootstrap_work_journal_dir/00.binding.json"
bootstrap_binding_candidate="$(jq -cn \
  --arg plan_sha256 "$deployment_plan_sha256" \
  --arg write_gate_command_sha256 "$deployment_write_gate_sha256" \
  --arg state_binding_sha256 "$actual_state_binding_sha256" \
  --argjson chain_fingerprint "$live_chain_json" \
  --arg authority "$SORASWAP_AUTHORITY" \
  --arg pool_contract "$pool_contract" \
  --arg pool_subject "$pool_subject" \
  --arg payout_contract "$payout_contract" \
  --arg payout_subject "$payout_subject" \
  --argjson temporary_topology "$temporary_topology_observed" \
  --argjson protected_topology "$protected_topology_observed" \
  '{
    schema_version: 1,
    phase: "pool_bootstrap_work_binding",
    plan_sha256: $plan_sha256,
    write_gate_command_sha256: $write_gate_command_sha256,
    state_binding_sha256: $state_binding_sha256,
    chain_fingerprint: $chain_fingerprint,
    authority_account_id: $authority,
    pool_contract_address: $pool_contract,
    pool_subject_account_id: $pool_subject,
    payout_contract_address: $payout_contract,
    payout_subject_account_id: $payout_subject,
    temporary_permission_topology_before: $temporary_topology,
    protected_permission_topology_before: $protected_topology
  }')"
if [[ -e "$bootstrap_binding_path" ]]; then
  validation_fee_require_immutable_json_file "$bootstrap_binding_path"
  bootstrap_binding="$(jq -ce . "$bootstrap_binding_path")"
else
  if [[ -n "$(find "$bootstrap_work_journal_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "bootstrap work journal contains events without its immutable binding" >&2
    exit 1
  fi
  if ! jq -e 'all(.[]; .present == false)' \
    >/dev/null <<<"$temporary_topology_observed"; then
    echo "new bootstrap work journal requires all temporary permissions absent" >&2
    exit 1
  fi
  validation_fee_write_immutable_json \
    "$bootstrap_binding_candidate" "$bootstrap_binding_path" >/dev/null
  bootstrap_binding="$bootstrap_binding_candidate"
fi
if ! jq -e \
  --arg plan_sha256 "$deployment_plan_sha256" \
  --arg write_gate_command_sha256 "$deployment_write_gate_sha256" \
  --arg state_binding_sha256 "$actual_state_binding_sha256" \
  --argjson chain_fingerprint "$live_chain_json" \
  --arg authority "$SORASWAP_AUTHORITY" \
  --arg pool_contract "$pool_contract" \
  --arg pool_subject "$pool_subject" \
  --arg payout_contract "$payout_contract" \
  --arg payout_subject "$payout_subject" \
  '
    .schema_version == 1
    and .phase == "pool_bootstrap_work_binding"
    and (
      keys
      == [
        "authority_account_id",
        "chain_fingerprint",
        "payout_contract_address",
        "payout_subject_account_id",
        "phase",
        "plan_sha256",
        "pool_contract_address",
        "pool_subject_account_id",
        "protected_permission_topology_before",
        "schema_version",
        "state_binding_sha256",
        "temporary_permission_topology_before",
        "write_gate_command_sha256"
      ]
    )
    and .plan_sha256 == $plan_sha256
    and .write_gate_command_sha256 == $write_gate_command_sha256
    and .state_binding_sha256 == $state_binding_sha256
    and .chain_fingerprint == $chain_fingerprint
    and .authority_account_id == $authority
    and .pool_contract_address == $pool_contract
    and .pool_subject_account_id == $pool_subject
    and .payout_contract_address == $payout_contract
    and .payout_subject_account_id == $payout_subject
    and (
      .temporary_permission_topology_before
      | type == "array"
        and length == 5
        and all(.[]; .present == false)
    )
    and .protected_permission_topology_before.absent == true
  ' >/dev/null <<<"$bootstrap_binding"; then
  echo "bootstrap work journal binding does not match this reviewed deployment" >&2
  exit 1
fi
bootstrap_binding_sha256="$(
  shasum -a 256 "$bootstrap_binding_path" | awk '{print $1}'
)"
temporary_topology_before="$(
  jq -ce '.temporary_permission_topology_before' <<<"$bootstrap_binding"
)"
protected_topology_before="$(
  jq -ce '.protected_permission_topology_before' <<<"$bootstrap_binding"
)"

bootstrap_events='[]'
permission_state='{
  "hajimari_selector": false,
  "seed_selector": false,
  "renounce_selector": false,
  "xor_transfer": false,
  "sbd_transfer": false
}'
contract_progress=0
previous_event_sha256="$bootstrap_binding_sha256"
journal_transaction_hashes='[]'

bootstrap_permission_spec() {
  local permission_key="$1"
  jq -ce \
    --arg permission_key "$permission_key" \
    '.[] | select(.key == $permission_key)' \
    <<<"$temporary_permission_specs"
}

bootstrap_permission_is_active() {
  local permission_key="$1"
  jq -er --arg permission_key "$permission_key" '.[$permission_key]' \
    <<<"$permission_state"
}

bootstrap_validate_event_receipt() {
  local event_json="$1"
  local reverify="${2:-1}"
  local event_kind operation_key receipt spec expected_state tx_hash_hex
  local required_key

  event_kind="$(jq -er '.kind' <<<"$event_json")" || return 1
  operation_key="$(jq -er '.operation_key' <<<"$event_json")" || return 1
  receipt="$(jq -ce '.receipt' <<<"$event_json")" || return 1
  case "$event_kind" in
    permission_grant|permission_revoke)
      spec="$(bootstrap_permission_spec "$operation_key")" || {
        echo "bootstrap journal names an unknown permission operation" >&2
        return 1
      }
      if ! jq -e \
        --arg holder "$(jq -er '.holder' <<<"$spec")" \
        --argjson permission "$(jq -ce '.permission' <<<"$spec")" \
        '
          .account_id == $holder
          and .permission == $permission
        ' >/dev/null <<<"$receipt"; then
        echo "bootstrap journal permission receipt does not match its exact selector" >&2
        return 1
      fi
      expected_state="$(bootstrap_permission_is_active "$operation_key")" \
        || return 1
      if [[ "$event_kind" == "permission_grant" \
        && "$expected_state" != "false" ]]; then
        echo "bootstrap journal grants an already-active permission" >&2
        return 1
      fi
      if [[ "$event_kind" == "permission_revoke" \
        && "$expected_state" != "true" ]]; then
        echo "bootstrap journal revokes an inactive permission" >&2
        return 1
      fi
      ;;
    contract_call)
      spec="$(jq -ce \
        --argjson contract_progress "$contract_progress" \
        '.[$contract_progress]' <<<"$contract_operation_specs")" || {
        echo "bootstrap journal contains an extra or out-of-order contract call" >&2
        return 1
      }
      if [[ "$(jq -er '.key' <<<"$spec")" != "$operation_key" ]]; then
        echo "bootstrap journal contract calls are not in exact bootstrap order" >&2
        return 1
      fi
      if ! jq -e \
        --arg pool_contract "$pool_contract" \
        --arg entrypoint "$(jq -er '.entrypoint' <<<"$spec")" \
        --argjson arguments "$(jq -ce '.arguments' <<<"$spec")" \
        '
          .contract_address == $pool_contract
          and .entrypoint == $entrypoint
          and .arguments == $arguments
        ' >/dev/null <<<"$receipt"; then
        echo "bootstrap journal contract receipt differs from the exact operation" >&2
        return 1
      fi
      case "$operation_key" in
        hajimari)
          [[ "$(bootstrap_permission_is_active hajimari_selector)" == "true" ]] \
            || {
              echo "journaled hajimari lacked its exact temporary selector" >&2
              return 1
            }
          ;;
        seed_bin_*)
          for required_key in seed_selector xor_transfer sbd_transfer; do
            [[ "$(bootstrap_permission_is_active "$required_key")" == "true" ]] \
              || {
                echo "journaled seed_bin lacked exact temporary permissions" >&2
                return 1
              }
          done
          ;;
        renounce_admin)
          [[ "$(bootstrap_permission_is_active renounce_selector)" == "true" ]] \
            || {
              echo "journaled renounce_admin lacked its exact temporary selector" >&2
              return 1
            }
          ;;
      esac
      ;;
    *)
      echo "bootstrap journal contains an unsupported mutation kind" >&2
      return 1
      ;;
  esac
  validation_fee_assert_transaction_evidence_json \
    "$(jq -ce '.transaction' <<<"$receipt")" \
    "$(jq -ce '.terminal' <<<"$receipt")" || return 1
  tx_hash_hex="$(jq -er '.transaction.tx_hash_hex' <<<"$receipt")" \
    || return 1
  if jq -e \
    --arg tx_hash_hex "$tx_hash_hex" \
    'index($tx_hash_hex) != null' \
    >/dev/null <<<"$journal_transaction_hashes"; then
    echo "bootstrap work journal reuses a transaction hash" >&2
    return 1
  fi
  if (( reverify == 1 )); then
    validation_fee_reverify_transaction_evidence_json \
      "$config" "$(jq -ce '.transaction' <<<"$receipt")"
  fi
}

bootstrap_apply_event_state() {
  local event_json="$1"
  local event_kind operation_key tx_hash_hex

  event_kind="$(jq -er '.kind' <<<"$event_json")" || return 1
  operation_key="$(jq -er '.operation_key' <<<"$event_json")" || return 1
  case "$event_kind" in
    permission_grant)
      permission_state="$(jq -c \
        --arg permission_key "$operation_key" \
        '.[$permission_key] = true' <<<"$permission_state")"
      ;;
    permission_revoke)
      permission_state="$(jq -c \
        --arg permission_key "$operation_key" \
        '.[$permission_key] = false' <<<"$permission_state")"
      ;;
    contract_call)
      contract_progress=$(( contract_progress + 1 ))
      ;;
  esac
  tx_hash_hex="$(jq -er '.receipt.transaction.tx_hash_hex' <<<"$event_json")" \
    || return 1
  journal_transaction_hashes="$(jq -c \
    --arg tx_hash_hex "$tx_hash_hex" \
    '. + [$tx_hash_hex]' <<<"$journal_transaction_hashes")"
}

expected_event_sequence=1
while IFS= read -r journal_entry; do
  [[ "$journal_entry" == "$bootstrap_binding_path" ]] && continue
  if [[ ! -f "$journal_entry" || -L "$journal_entry" ]]; then
    echo "bootstrap work journal contains a non-regular entry" >&2
    exit 1
  fi
  journal_name="${journal_entry:t}"
  printf -v expected_event_name '%04d.event.json' "$expected_event_sequence"
  if [[ "$journal_name" != "$expected_event_name" ]]; then
    echo "bootstrap work journal event names must be contiguous" >&2
    exit 1
  fi
  validation_fee_require_immutable_json_file "$journal_entry"
  event_json="$(jq -ce . "$journal_entry")"
  if ! jq -e \
    --argjson sequence "$expected_event_sequence" \
    --arg plan_sha256 "$deployment_plan_sha256" \
    --argjson chain_fingerprint "$live_chain_json" \
    --arg previous_event_sha256 "$previous_event_sha256" \
    '
      .schema_version == 1
      and .phase == "pool_bootstrap_work_event"
      and (
        keys
        == [
          "chain_fingerprint",
          "kind",
          "operation_key",
          "phase",
          "plan_sha256",
          "previous_event_sha256",
          "receipt",
          "schema_version",
          "sequence"
        ]
      )
      and .sequence == $sequence
      and .plan_sha256 == $plan_sha256
      and .chain_fingerprint == $chain_fingerprint
      and .previous_event_sha256 == $previous_event_sha256
      and (.operation_key | type == "string" and length > 0)
      and (.receipt | type == "object")
    ' >/dev/null <<<"$event_json"; then
    echo "bootstrap work journal event is not bound to its predecessor and plan" >&2
    exit 1
  fi
  bootstrap_validate_event_receipt "$event_json"
  bootstrap_apply_event_state "$event_json"
  bootstrap_events="$(jq -c \
    --argjson event "$event_json" '. + [$event]' <<<"$bootstrap_events")"
  previous_event_sha256="$(
    shasum -a 256 "$journal_entry" | awk '{print $1}'
  )"
  expected_event_sequence=$(( expected_event_sequence + 1 ))
done < <(
  find "$bootstrap_work_journal_dir" -mindepth 1 -maxdepth 1 -print \
    | LC_ALL=C sort
)

bootstrap_append_event() {
  local event_kind="$1"
  local operation_key="$2"
  local receipt="$3"
  local sequence event_name event_path event_json

  sequence=$(( $(jq -r 'length' <<<"$bootstrap_events") + 1 ))
  if (( sequence > 9999 )); then
    echo "bootstrap work journal event sequence is exhausted" >&2
    return 1
  fi
  printf -v event_name '%04d.event.json' "$sequence"
  event_path="$bootstrap_work_journal_dir/$event_name"
  if [[ -e "$event_path" || -L "$event_path" ]]; then
    echo "refusing to replace bootstrap work journal event $event_name" >&2
    return 1
  fi
  event_json="$(jq -cn \
    --argjson sequence "$sequence" \
    --arg plan_sha256 "$deployment_plan_sha256" \
    --argjson chain_fingerprint "$live_chain_json" \
    --arg previous_event_sha256 "$previous_event_sha256" \
    --arg kind "$event_kind" \
    --arg operation_key "$operation_key" \
    --argjson receipt "$receipt" \
    '{
      schema_version: 1,
      phase: "pool_bootstrap_work_event",
      sequence: $sequence,
      plan_sha256: $plan_sha256,
      chain_fingerprint: $chain_fingerprint,
      previous_event_sha256: $previous_event_sha256,
      kind: $kind,
      operation_key: $operation_key,
      receipt: $receipt
    }')"
  bootstrap_validate_event_receipt "$event_json" 0 || return $?
  validation_fee_write_immutable_json "$event_json" "$event_path" >/dev/null \
    || return $?
  bootstrap_apply_event_state "$event_json"
  bootstrap_events="$(jq -c \
    --argjson event "$event_json" '. + [$event]' <<<"$bootstrap_events")"
  previous_event_sha256="$(
    shasum -a 256 "$event_path" | awk '{print $1}'
  )"
  validation_fee_reverify_transaction_evidence_json \
    "$config" "$(jq -ce '.receipt.transaction' <<<"$event_json")"
}

bootstrap_mutation_prefix_for() {
  local sequence="$1"
  local event_kind="$2"
  local operation_key="$3"
  local sequence_text target sibling

  if [[ "$sequence" != <-> || "$sequence" -lt 1 || "$sequence" -gt 9999 \
    || ! "$event_kind" =~ '^(permission_grant|permission_revoke|contract_call)$' \
    || ! "$operation_key" =~ '^[0-9A-Za-z_]+$' ]]; then
    echo "invalid validation-fee bootstrap mutation journal identity" >&2
    return 1
  fi
  printf -v sequence_text '%04d' "$sequence"
  printf '%s/%s.%s.%s\n' \
    "$bootstrap_mutation_journal_dir" \
    "$sequence_text" "$event_kind" "$operation_key"
}

bootstrap_prepared_ledger_dir_for() {
  local sequence="$1"
  local event_kind="$2"
  local operation_key="$3"
  local sequence_text

  if [[ "$sequence" != <-> || "$sequence" -lt 1 || "$sequence" -gt 9999 \
    || ! "$event_kind" =~ '^(permission_grant|permission_revoke)$' \
    || ! "$operation_key" =~ '^[0-9A-Za-z_]+$' ]]; then
    echo "invalid validation-fee prepared ledger identity" >&2
    return 1
  fi
  printf -v sequence_text '%04d' "$sequence"
  target="$bootstrap_prepared_ledger_dir/$sequence_text.$event_kind.$operation_key"
  for sibling in "$bootstrap_prepared_ledger_dir/$sequence_text."*(N); do
    [[ "$sibling" == "$target" ]] || {
      echo "bootstrap prepared ledger sequence is already bound to another operation" >&2
      return 1
    }
  done
  printf '%s\n' "$target"
}

bootstrap_permission_semantic_operation_json() {
  local event_kind="$1"
  local operation_key="$2"
  local spec

  [[ "$event_kind" =~ '^(permission_grant|permission_revoke)$' ]] || return 1
  spec="$(bootstrap_permission_spec "$operation_key")" || return 1
  jq -cn \
    --arg kind "$event_kind" \
    --arg plan_sha256 "$deployment_plan_sha256" \
    --arg account_id "$(jq -er '.holder' <<<"$spec")" \
    --argjson permission "$(jq -ce '.permission' <<<"$spec")" \
    '{
      kind: $kind,
      plan_sha256: $plan_sha256,
      account_id: $account_id,
      permission: $permission
    }'
}

bootstrap_operation_json_for_event() {
  local sequence="$1"
  local event_kind="$2"
  local operation_key="$3"
  local spec semantic_operation_json prepared_dir prepared_wrapper_json

  case "$event_kind" in
    permission_grant|permission_revoke)
      semantic_operation_json="$(
        bootstrap_permission_semantic_operation_json \
          "$event_kind" "$operation_key"
      )" || return 1
      prepared_dir="$(
        bootstrap_prepared_ledger_dir_for \
          "$sequence" "$event_kind" "$operation_key"
      )" || return 1
      [[ -e "$prepared_dir/plan.json" ]] || {
        echo "bootstrap permission journal lacks its frozen prepared transaction" >&2
        return 1
      }
      prepared_wrapper_json="$(
        validation_fee_validate_prepared_ledger_transaction_json \
          "$prepared_dir" "$semantic_operation_json"
      )" || return 1
      validation_fee_prepared_ledger_operation_json \
        "$semantic_operation_json" "$prepared_wrapper_json"
      ;;
    contract_call)
      spec="$(jq -ce \
        --arg operation_key "$operation_key" \
        '.[] | select(.key == $operation_key)' \
        <<<"$contract_operation_specs")" || return 1
      jq -cn \
        --arg kind contract_call \
        --arg plan_sha256 "$deployment_plan_sha256" \
        --arg contract_address "$pool_contract" \
        --arg entrypoint "$(jq -er '.entrypoint' <<<"$spec")" \
        --argjson arguments "$(jq -ce '.arguments' <<<"$spec")" \
        '{
          kind: $kind,
          plan_sha256: $plan_sha256,
          contract_address: $contract_address,
          entrypoint: $entrypoint,
          arguments: $arguments
        }'
      ;;
    *)
      echo "unsupported validation-fee bootstrap mutation event kind" >&2
      return 1
      ;;
  esac
}

bootstrap_assert_event_mutation_journal() {
  local event_json="$1"
  local sequence event_kind operation_key prefix operation_json receipt

  sequence="$(jq -er '.sequence' <<<"$event_json")" || return 1
  event_kind="$(jq -er '.kind' <<<"$event_json")" || return 1
  operation_key="$(jq -er '.operation_key' <<<"$event_json")" || return 1
  prefix="$(
    bootstrap_mutation_prefix_for "$sequence" "$event_kind" "$operation_key"
  )" || return 1
  operation_json="$(
    bootstrap_operation_json_for_event \
      "$sequence" "$event_kind" "$operation_key"
  )" || return 1
  [[ "$(validation_fee_mutation_journal_state "$prefix")" == "Applied" ]] || {
    echo "bootstrap work event lacks its Applied mutation journal: $prefix" >&2
    return 1
  }
  validation_fee_assert_mutation_journal "$prefix" "$operation_json" || return 1
  receipt="$(jq -ce '.receipt' "$prefix.Applied.json")" || return 1
  if ! jq -e --argjson receipt "$receipt" \
    '.receipt == $receipt' >/dev/null <<<"$event_json"; then
    echo "bootstrap work event differs from its Applied mutation journal" >&2
    return 1
  fi
}

bootstrap_reconcile_next_mutation() {
  local sequence sequence_text intent_path name stem prefix event_kind operation_key
  local operation_json expected_operation state transaction terminal receipt spec
  local -a candidates

  while true; do
    sequence=$(( $(jq -r 'length' <<<"$bootstrap_events") + 1 ))
    printf -v sequence_text '%04d' "$sequence"
    candidates=(
      "$bootstrap_mutation_journal_dir/$sequence_text."*.intent.json(N)
    )
    (( ${#candidates[@]} == 0 )) && return 0
    if (( ${#candidates[@]} != 1 )); then
      echo "bootstrap mutation journal has multiple intents for event $sequence_text" >&2
      return 1
    fi
    intent_path="${candidates[1]}"
    name="${intent_path:t}"
    stem="${name%.intent.json}"
    event_kind="${${stem#*.}%%.*}"
    operation_key="${${stem#*.*.}}"
    prefix="${intent_path%.intent.json}"
    if [[ ! "$event_kind" =~ '^(permission_grant|permission_revoke|contract_call)$' \
      || ! "$operation_key" =~ '^[0-9A-Za-z_]+$' ]]; then
      echo "bootstrap mutation journal name is invalid: $name" >&2
      return 1
    fi
    operation_json="$(jq -ce '.operation' "$intent_path")" || return 1
    expected_operation="$(
      bootstrap_operation_json_for_event \
        "$sequence" "$event_kind" "$operation_key"
    )" || return 1
    if ! json_equals "$operation_json" "$expected_operation"; then
      echo "bootstrap mutation journal operation differs from its exact event" >&2
      return 1
    fi
    state="$(validation_fee_mutation_journal_state "$prefix")" || return 1
    validation_fee_assert_mutation_journal "$prefix" "$expected_operation" \
      || return 1
    case "$state" in
      intent)
        echo "bootstrap mutation stopped after intent with an ambiguous submission outcome; refusing retry" >&2
        return 1
        ;;
      submission)
        transaction="$(jq -ce '.transaction' "$prefix.submission.json")" \
          || return 1
        terminal="$(
          validation_fee_applied_transaction_json \
            "$config" "$(jq -er '.tx_hash_hex' <<<"$transaction")"
        )" || {
          echo "bootstrap mutation submission is not proven Applied; refusing retry" >&2
          return 1
        }
        case "$event_kind" in
          permission_grant|permission_revoke)
            spec="$(bootstrap_permission_spec "$operation_key")" || return 1
            if [[ "$event_kind" == "permission_grant" ]]; then
              account_has_exact_permission_json \
                "$config" \
                "$(jq -er '.holder' <<<"$spec")" \
                "$(jq -ce '.permission' <<<"$spec")" || {
                  echo "journaled bootstrap grant is not query-visible" >&2
                  return 1
                }
            elif account_has_exact_permission_json \
              "$config" \
              "$(jq -er '.holder' <<<"$spec")" \
              "$(jq -ce '.permission' <<<"$spec")"; then
              echo "journaled bootstrap revoke is not query-visible" >&2
              return 1
            fi
            receipt="$(jq -cn \
              --arg account_id "$(jq -er '.holder' <<<"$spec")" \
              --argjson permission "$(jq -ce '.permission' <<<"$spec")" \
              --argjson transaction "$transaction" \
              --argjson terminal "$terminal" \
              '{
                account_id: $account_id,
                permission: $permission,
                transaction: $transaction,
                terminal: $terminal
              }')"
            ;;
          contract_call)
            spec="$(jq -ce \
              --arg operation_key "$operation_key" \
              '.[] | select(.key == $operation_key)' \
              <<<"$contract_operation_specs")" || return 1
            receipt="$(jq -cn \
              --arg contract_address "$pool_contract" \
              --arg entrypoint "$(jq -er '.entrypoint' <<<"$spec")" \
              --argjson arguments "$(jq -ce '.arguments' <<<"$spec")" \
              --argjson transaction "$transaction" \
              --argjson terminal "$terminal" \
              '{
                contract_address: $contract_address,
                entrypoint: $entrypoint,
                arguments: $arguments,
                transaction: $transaction,
                terminal: $terminal
              }')"
            ;;
        esac
        validation_fee_record_mutation_applied \
          "$prefix" "$receipt" "$expected_operation" || return 1
        ;;
      Applied)
        receipt="$(jq -ce '.receipt' "$prefix.Applied.json")" || return 1
        ;;
      *)
        return 1
        ;;
    esac
    bootstrap_append_event "$event_kind" "$operation_key" "$receipt" \
      || return 1
  done
}

bootstrap_assert_mutation_journal_shape() {
  local event_count sequence name stem prefix file state
  local -A prefix_by_sequence=()

  event_count="$(jq -er 'length' <<<"$bootstrap_events")" || return 1
  for file in "$bootstrap_mutation_journal_dir"/*(DN); do
    [[ -f "$file" && ! -L "$file" ]] || {
      echo "bootstrap mutation journal contains a non-regular entry" >&2
      return 1
    }
    name="${file:t}"
    if [[ ! "$name" \
      =~ '^[0-9]{4}\.(permission_grant|permission_revoke|contract_call)\.[0-9A-Za-z_]+\.(intent|submission|Applied)\.json$' ]]; then
      echo "bootstrap mutation journal contains an unexpected file: $name" >&2
      return 1
    fi
    validation_fee_require_immutable_json_file "$file" || return 1
    sequence="${name%%.*}"
    stem="${name%.*.json}"
    prefix="$bootstrap_mutation_journal_dir/$stem"
    if [[ -n "${prefix_by_sequence[$sequence]:-}" \
      && "${prefix_by_sequence[$sequence]}" != "$prefix" ]]; then
      echo "bootstrap mutation journal repeats event sequence $sequence" >&2
      return 1
    fi
    prefix_by_sequence[$sequence]="$prefix"
  done
  for sequence in "${(@k)prefix_by_sequence}"; do
    if (( 10#$sequence < 1 || 10#$sequence > event_count + 1 )); then
      echo "bootstrap mutation journal has an out-of-order event sequence" >&2
      return 1
    fi
    state="$(validation_fee_mutation_journal_state \
      "${prefix_by_sequence[$sequence]}")" || return 1
    [[ "$state" != "absent" ]] || return 1
  done
  for (( sequence = 1; sequence <= event_count; sequence++ )); do
    printf -v name '%04d' "$sequence"
    [[ -n "${prefix_by_sequence[$name]:-}" ]] || {
      echo "bootstrap event $name lacks a mutation journal" >&2
      return 1
    }
  done
}

bootstrap_assert_prepared_ledger_shape() {
  local entry name sequence event_kind operation_key intent_path
  local intent_file stem expected_dir event_count prepared_only_count=0

  event_count="$(jq -er 'length' <<<"$bootstrap_events")" || return 1

  for entry in "$bootstrap_prepared_ledger_dir"/*(DN); do
    [[ -d "$entry" && ! -L "$entry" ]] || {
      echo "bootstrap prepared ledger root contains a non-directory" >&2
      return 1
    }
    name="${entry:t}"
    if [[ ! "$name" \
      =~ '^([0-9]{4})\.(permission_grant|permission_revoke)\.([0-9A-Za-z_]+)$' ]]; then
      echo "bootstrap prepared ledger root contains an unexpected entry: $name" >&2
      return 1
    fi
    sequence="${name%%.*}"
    event_kind="${${name#*.}%%.*}"
    operation_key="${name#*.*.}"
    intent_path="$bootstrap_mutation_journal_dir/$name.intent.json"
    if [[ ! -f "$intent_path" || -L "$intent_path" ]]; then
      if (( 10#$sequence != event_count + 1 )); then
        echo "bootstrap prepared ledger package lacks its exact mutation intent" >&2
        return 1
      fi
      prepared_only_count=$(( prepared_only_count + 1 ))
      if (( prepared_only_count > 1 )); then
        echo "bootstrap prepared ledger root has multiple unsubmitted next operations" >&2
        return 1
      fi
    fi
    bootstrap_operation_json_for_event \
      "$(( 10#$sequence ))" "$event_kind" "$operation_key" >/dev/null \
      || return 1
  done
  for intent_file in \
    "$bootstrap_mutation_journal_dir"/*.permission_grant.*.intent.json(N) \
    "$bootstrap_mutation_journal_dir"/*.permission_revoke.*.intent.json(N); do
    stem="${${intent_file:t}%.intent.json}"
    expected_dir="$bootstrap_prepared_ledger_dir/$stem"
    [[ -d "$expected_dir" && ! -L "$expected_dir" ]] || {
      echo "bootstrap permission intent lacks its frozen prepared ledger package" >&2
      return 1
    }
  done
}

bootstrap_assert_mutation_journal_shape
bootstrap_assert_prepared_ledger_shape
for event_json in "${(@f)$(jq -c '.[]' <<<"$bootstrap_events")}"; do
  [[ -n "$event_json" ]] || continue
  bootstrap_assert_event_mutation_journal "$event_json"
done
bootstrap_reconcile_next_mutation

expected_temporary_topology="$(jq -cn \
  --argjson specs "$temporary_permission_specs" \
  --argjson permission_state "$permission_state" \
  '$specs | map({
    holder,
    permission,
    present: $permission_state[.key]
  })')"
if ! json_equals "$temporary_topology_observed" "$expected_temporary_topology"; then
  echo "live temporary permissions differ from the append-only bootstrap journal" >&2
  exit 1
fi

if jq -e 'any(.[]; . == true)' >/dev/null <<<"$permission_state"; then
  cleanup_permissions=1
fi

bootstrap_pause_after_applied_write() {
  local operation_key="$1"
  local journal_prefix="$2"

  [[ "$(validation_fee_mutation_journal_state "$journal_prefix")" \
    == "Applied" ]] || {
    echo "cannot pause bootstrap before its mutation is durably Applied" >&2
    return 1
  }
  validation_fee_release_apply_lock || return 1
  trap - EXIT INT TERM
  validation_fee_pause_result_json \
    "pool_bootstrap.$operation_key" "$journal_prefix.Applied.json"
  exit 0
}

ensure_permission_active() {
  local permission_key="$1"
  local spec receipt sequence journal_prefix prepared_dir
  local semantic_operation_json operation_json

  if [[ "$(bootstrap_permission_is_active "$permission_key")" == "true" ]]; then
    return 0
  fi
  spec="$(bootstrap_permission_spec "$permission_key")" || return 1
  if account_has_exact_permission_json \
    "$config" \
    "$(jq -er '.holder' <<<"$spec")" \
    "$(jq -ce '.permission' <<<"$spec")"; then
    echo "live permission is present without its bootstrap journal grant" >&2
    return 1
  fi
  cleanup_permissions=1
  sequence=$(( $(jq -r 'length' <<<"$bootstrap_events") + 1 ))
  journal_prefix="$(
    bootstrap_mutation_prefix_for \
      "$sequence" permission_grant "$permission_key"
  )" || return 1
  prepared_dir="$(
    bootstrap_prepared_ledger_dir_for \
      "$sequence" permission_grant "$permission_key"
  )" || return 1
  semantic_operation_json="$(
    bootstrap_permission_semantic_operation_json \
      permission_grant "$permission_key"
  )" || return 1
  operation_json="$(
    validation_fee_prepare_bound_ledger_operation_json \
      "$config" "$semantic_operation_json" "$prepared_dir"
  )" || return $?
  receipt="$(
    validation_fee_grant_exact_permission_with_evidence \
      "$config" \
      "$(jq -er '.holder' <<<"$spec")" \
      "$(jq -ce '.permission' <<<"$spec")" \
      "$journal_prefix" \
      "$prepared_dir" \
      "$operation_json"
  )" || return $?
  bootstrap_append_event permission_grant "$permission_key" "$receipt" \
    || return $?
  bootstrap_pause_after_applied_write "$permission_key.grant" "$journal_prefix"
}

record_permission_revoke_if_present() {
  local permission_key="$1"
  local pause_after="${2:-1}"
  local spec account_id permission_json receipt live_present=false
  local journal_active sequence journal_prefix prepared_dir
  local semantic_operation_json operation_json

  spec="$(bootstrap_permission_spec "$permission_key")" || return 1
  account_id="$(jq -er '.holder' <<<"$spec")" || return 1
  permission_json="$(jq -ce '.permission' <<<"$spec")" || return 1
  if account_has_exact_permission_json "$config" "$account_id" "$permission_json"; then
    live_present=true
  fi
  journal_active="$(bootstrap_permission_is_active "$permission_key")" \
    || return 1
  if [[ "$live_present" == "false" ]]; then
    if [[ "$journal_active" == "true" ]]; then
      echo "journaled temporary permission disappeared without revoke evidence" >&2
      work_journal_complete=0
      return 1
    fi
    return 0
  fi
  sequence=$(( $(jq -r 'length' <<<"$bootstrap_events") + 1 ))
  journal_prefix="$(
    bootstrap_mutation_prefix_for \
      "$sequence" permission_revoke "$permission_key"
  )" || return 1
  prepared_dir="$(
    bootstrap_prepared_ledger_dir_for \
      "$sequence" permission_revoke "$permission_key"
  )" || return 1
  semantic_operation_json="$(
    bootstrap_permission_semantic_operation_json \
      permission_revoke "$permission_key"
  )" || return 1
  operation_json="$(
    validation_fee_prepare_bound_ledger_operation_json \
      "$config" "$semantic_operation_json" "$prepared_dir"
  )" || return $?
  receipt="$(
    validation_fee_revoke_exact_permission_with_evidence \
      "$config" "$account_id" "$permission_json" "$journal_prefix" \
      "$prepared_dir" "$operation_json"
  )" || return $?
  if [[ "$journal_active" == "true" ]]; then
    bootstrap_append_event permission_revoke "$permission_key" "$receipt" \
      || return $?
    if (( pause_after == 1 )); then
      bootstrap_pause_after_applied_write \
        "$permission_key.revoke" "$journal_prefix"
    fi
    return "$VALIDATION_FEE_ONE_WRITE_PAUSE_RETURN_STATUS"
  else
    orphan_permission_revokes="$(jq -c \
      --argjson receipt "$receipt" '. + [$receipt]' \
      <<<"$orphan_permission_revokes")"
    work_journal_complete=0
    echo "temporary permission was cleaned but its grant evidence was not journaled" >&2
    return 1
  fi
}

cleanup_temporary_permissions() {
  (( cleanup_permissions == 1 )) || return 0
  local cleanup_status=0
  local permission_key

  for permission_key in \
    hajimari_selector seed_selector renounce_selector \
    xor_transfer sbd_transfer; do
    if record_permission_revoke_if_present "$permission_key" 0; then
      continue
    else
      cleanup_status=$?
    fi
    if (( cleanup_status == VALIDATION_FEE_ONE_WRITE_PAUSE_RETURN_STATUS )); then
      return "$cleanup_status"
    fi
  done
  return "$cleanup_status"
}

bootstrap_next_step_json() {
  local active

  case "$contract_progress" in
    0)
      active="$(bootstrap_permission_is_active hajimari_selector)" || return 1
      if [[ "$active" == "false" ]]; then
        jq -cn '{kind: "permission_grant", operation_key: "hajimari_selector"}'
      else
        jq -cn '{kind: "contract_call", operation_key: "hajimari"}'
      fi
      ;;
    1)
      if [[ "$(bootstrap_permission_is_active hajimari_selector)" == "true" ]]; then
        jq -cn '{kind: "permission_revoke", operation_key: "hajimari_selector"}'
      elif [[ "$(bootstrap_permission_is_active seed_selector)" == "false" ]]; then
        jq -cn '{kind: "permission_grant", operation_key: "seed_selector"}'
      elif [[ "$(bootstrap_permission_is_active xor_transfer)" == "false" ]]; then
        jq -cn '{kind: "permission_grant", operation_key: "xor_transfer"}'
      elif [[ "$(bootstrap_permission_is_active sbd_transfer)" == "false" ]]; then
        jq -cn '{kind: "permission_grant", operation_key: "sbd_transfer"}'
      else
        jq -cn '{kind: "contract_call", operation_key: "seed_bin_0"}'
      fi
      ;;
    2)
      jq -cn '{kind: "contract_call", operation_key: "seed_bin_1"}'
      ;;
    3)
      jq -cn '{kind: "contract_call", operation_key: "seed_bin_2"}'
      ;;
    4)
      if [[ "$(bootstrap_permission_is_active seed_selector)" == "true" ]]; then
        jq -cn '{kind: "permission_revoke", operation_key: "seed_selector"}'
      elif [[ "$(bootstrap_permission_is_active xor_transfer)" == "true" ]]; then
        jq -cn '{kind: "permission_revoke", operation_key: "xor_transfer"}'
      elif [[ "$(bootstrap_permission_is_active sbd_transfer)" == "true" ]]; then
        jq -cn '{kind: "permission_revoke", operation_key: "sbd_transfer"}'
      elif [[ "$(bootstrap_permission_is_active renounce_selector)" == "false" ]]; then
        jq -cn '{kind: "permission_grant", operation_key: "renounce_selector"}'
      else
        jq -cn '{kind: "contract_call", operation_key: "renounce_admin"}'
      fi
      ;;
    5)
      if [[ "$(bootstrap_permission_is_active renounce_selector)" == "true" ]]; then
        jq -cn '{kind: "permission_revoke", operation_key: "renounce_selector"}'
      else
        jq -cn '{kind: "complete", operation_key: "complete"}'
      fi
      ;;
    *)
      echo "bootstrap contract-call progress is outside the exact five-step plan" >&2
      return 1
      ;;
  esac
}

bootstrap_execute_next_step() {
  local step event_kind operation_key spec sequence journal_prefix receipt

  step="$(bootstrap_next_step_json)" || return 1
  event_kind="$(jq -er '.kind' <<<"$step")" || return 1
  operation_key="$(jq -er '.operation_key' <<<"$step")" || return 1
  case "$event_kind" in
    permission_grant)
      ensure_permission_active "$operation_key"
      ;;
    permission_revoke)
      record_permission_revoke_if_present "$operation_key"
      ;;
    contract_call)
      spec="$(jq -ce \
        --arg operation_key "$operation_key" \
        '.[] | select(.key == $operation_key)' \
        <<<"$contract_operation_specs")" || return 1
      sequence=$(( $(jq -r 'length' <<<"$bootstrap_events") + 1 ))
      journal_prefix="$(
        bootstrap_mutation_prefix_for \
          "$sequence" contract_call "$operation_key"
      )" || return 1
      receipt="$(
        validation_fee_contract_call_with_evidence \
          "$config" \
          "$pool_contract" \
          "$(jq -er '.entrypoint' <<<"$spec")" \
          "$(jq -ce '.arguments' <<<"$spec")" \
          "$journal_prefix"
      )" || return $?
      bootstrap_append_event contract_call "$operation_key" "$receipt" \
        || return $?
      bootstrap_pause_after_applied_write "$operation_key" "$journal_prefix"
      ;;
    complete)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

next_recovery_evidence_path() {
  local recovery_stem="$recovery_evidence_path"
  local recovery_sequence recovery_sequence_text candidate

  [[ "$recovery_stem" == *.json ]] \
    && recovery_stem="${recovery_stem%.json}"
  recovery_sequence=1
  while (( recovery_sequence <= 9999 )); do
    printf -v recovery_sequence_text '%04d' "$recovery_sequence"
    candidate="$recovery_stem.recovery-$recovery_sequence_text.json"
    if [[ ! -e "$candidate" && ! -L "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    validation_fee_require_immutable_json_file "$candidate" || return 1
    recovery_sequence=$(( recovery_sequence + 1 ))
  done
  echo "validation-fee recovery evidence sequence is exhausted" >&2
  return 1
}

validation_fee_emergency_cleanup_on_exit() {
  local original_status="$1"
  local cleanup_status=0
  local write_status=0
  local temporary_topology='null'
  local recovery_json recovery_target permission_grants permission_revokes

  (( cleanup_permissions == 1 )) || return "$original_status"
  cleanup_temporary_permissions || cleanup_status=$?
  temporary_topology="$(
    validation_fee_direct_permission_topology_json \
      "$config" "$temporary_permissions" 2>/dev/null
  )" || temporary_topology='null'
  if (( cleanup_status == VALIDATION_FEE_ONE_WRITE_PAUSE_RETURN_STATUS )) \
    && jq -e '
      type == "array"
      and length == 5
      and all(.[]; .present == false)
    ' >/dev/null <<<"$temporary_topology"; then
    cleanup_status=0
  fi
  permission_grants="$(jq -c \
    '[.[] | select(.kind == "permission_grant") | .receipt]' \
    <<<"$bootstrap_events")"
  permission_revokes="$(jq -c \
    '[.[] | select(.kind == "permission_revoke") | .receipt]' \
    <<<"$bootstrap_events")"
  recovery_json="$(jq -cn \
    --arg plan_sha256 "$deployment_plan_sha256" \
    --argjson chain_fingerprint "$live_chain_json" \
    --arg binding_sha256 "$bootstrap_binding_sha256" \
    --arg terminal_event_sha256 "$previous_event_sha256" \
    --argjson event_count "$(jq -r 'length' <<<"$bootstrap_events")" \
    --argjson permission_grants "$permission_grants" \
    --argjson permission_revokes "$permission_revokes" \
    --argjson orphan_permission_revokes "$orphan_permission_revokes" \
    --argjson temporary_permission_topology "$temporary_topology" \
    --argjson original_status "$original_status" \
    --argjson cleanup_status "$cleanup_status" \
    --argjson work_journal_complete "$work_journal_complete" \
    '{
      schema_version: 1,
      status: (
        if $cleanup_status == 0
          and $work_journal_complete == 1
          and $temporary_permission_topology != null
          and all($temporary_permission_topology[]; .present == false)
        then "emergency_cleanup_completed"
        else "emergency_cleanup_failed"
        end
      ),
      plan_sha256: $plan_sha256,
      chain_fingerprint: $chain_fingerprint,
      work_journal: {
        binding_sha256: $binding_sha256,
        event_count: $event_count,
        terminal_event_sha256: $terminal_event_sha256,
        complete: ($work_journal_complete == 1)
      },
      original_exit_status: $original_status,
      cleanup_exit_status: $cleanup_status,
      permission_grants: $permission_grants,
      permission_revokes: $permission_revokes,
      orphan_permission_revokes: $orphan_permission_revokes,
      temporary_permission_topology: $temporary_permission_topology
    }')"
  recovery_target="$(next_recovery_evidence_path)" || write_status=$?
  if (( write_status == 0 )); then
    validation_fee_write_immutable_json \
      "$recovery_json" "$recovery_target" >/dev/null || write_status=$?
  fi
  cleanup_permissions=0
  if (( cleanup_status != 0 || write_status != 0 )) \
    || ! jq -e '.status == "emergency_cleanup_completed"' \
      >/dev/null <<<"$recovery_json"; then
    echo "CRITICAL: validation-fee emergency permission cleanup was not proven" >&2
    echo "recovery evidence target prefix: $recovery_evidence_path" >&2
    return 1
  fi
  echo "validation-fee emergency cleanup evidence: $recovery_target" >&2
  return "$original_status"
}

validation_fee_emergency_cleanup_on_signal() {
  validation_fee_signal_cleanup_and_exit \
    "$1" "$2" validation_fee_bootstrap_cleanup_and_unlock_on_exit
}

validation_fee_bootstrap_cleanup_and_unlock_on_exit() {
  local original_status="$1"
  local cleanup_status=0 unlock_status=0

  validation_fee_emergency_cleanup_on_exit "$original_status" \
    || cleanup_status=$?
  validation_fee_release_apply_lock || unlock_status=$?
  if (( unlock_status != 0 )); then
    echo "CRITICAL: validation-fee apply lock could not be released" >&2
    return 1
  fi
  return "$cleanup_status"
}

trap 'validation_fee_bootstrap_cleanup_and_unlock_on_exit $?' EXIT
trap 'validation_fee_emergency_cleanup_on_signal INT 130' INT
trap 'validation_fee_emergency_cleanup_on_signal TERM 143' TERM

mirror_before="$(view_result mirror_state)"
initialized="$(jq -er '.[0]' <<<"$mirror_before")"
if [[ "$contract_progress" == "0" ]]; then
  if [[ "$initialized" != "0" ]]; then
    echo "pool initialization is live without immutable hajimari evidence" >&2
    exit 1
  fi
  bootstrap_execute_next_step
elif [[ "$initialized" != "1" ]]; then
  echo "journaled pool initialization is not query-visible" >&2
  exit 1
fi

expected_pool_config="$(jq -cn \
  --arg base "$VALIDATION_FEE_XOR_ASSET_ID" \
  --arg quote "$VALIDATION_FEE_SBD_ASSET_ID" \
  --arg vault "$pool_subject" \
  '[$base, $quote, $vault, 3000, 1, 0]')"
pool_config="$(view_result pool_config)"
if ! json_equals "$pool_config" "$expected_pool_config"; then
  echo "pool_config does not match the exact XOR/SBD validation-fee pool" >&2
  exit 1
fi
risk_config="$(view_result risk_config)"
if ! json_equals "$risk_config" '[10000,0,0,8,0]'; then
  echo "risk_config does not match the exact validation-fee bounds" >&2
  exit 1
fi
admin_state="$(view_result admin_state)"
if [[ "$(jq -r '.[0]' <<<"$admin_state")" != "$SORASWAP_AUTHORITY" ]]; then
  echo "pool owner is not the configured bootstrap authority" >&2
  exit 1
fi
if (( contract_progress < 5 )) \
  && [[ "$(jq -r '.[1]' <<<"$admin_state")" != "0" ]]; then
  echo "pool admin is renounced without immutable renounce evidence" >&2
  exit 1
fi
if (( contract_progress == 5 )) \
  && [[ "$(jq -r '.[1]' <<<"$admin_state")" != "1" ]]; then
  echo "journaled admin renunciation is not query-visible" >&2
  exit 1
fi

seed_index=0
while IFS= read -r seed; do
  position_id="$(jq -r '.position_id' <<<"$seed")"
  bin_id="$(jq -r '.bin_id' <<<"$seed")"
  position_state="$(
    view_result mirror_position \
      "$(jq -cn --arg position_id "$position_id" \
        '{position_id: $position_id}')"
  )"
  if (( contract_progress >= seed_index + 2 )); then
    bin_state="$(
      view_result mirror_bin \
        "$(jq -cn --argjson bin_id "$bin_id" '{bin_id: $bin_id}')"
    )"
    if ! jq -e \
      --argjson bin_id "$bin_id" \
      '.[0] == 1 and .[1] == $bin_id' \
      >/dev/null <<<"$position_state"; then
      echo "journaled bootstrap position $position_id is not query-visible" >&2
      exit 1
    fi
    if ! jq -e \
      --argjson amount "$VALIDATION_FEE_SEED_AMOUNT" \
      '.[0] == $amount and .[1] == $amount' \
      >/dev/null <<<"$bin_state"; then
      echo "journaled bootstrap bin $bin_id differs from the exact seed" >&2
      exit 1
    fi
  elif [[ "$(jq -r '.[0]' <<<"$position_state")" != "0" ]]; then
    echo "bootstrap position $position_id exists without immutable call evidence" >&2
    exit 1
  fi
  seed_index=$(( seed_index + 1 ))
done < <(jq -c '.[]' <<<"$seed_operations")

bootstrap_execute_next_step

seed_index=0
while IFS= read -r seed; do
  position_id="$(jq -r '.position_id' <<<"$seed")"
  bin_id="$(jq -r '.bin_id' <<<"$seed")"
  position_state="$(
    view_result mirror_position \
      "$(jq -cn --arg position_id "$position_id" \
        '{position_id: $position_id}')"
  )"
  bin_state="$(
    view_result mirror_bin \
      "$(jq -cn --argjson bin_id "$bin_id" '{bin_id: $bin_id}')"
  )"
  if ! jq -e \
    --argjson bin_id "$bin_id" \
    '.[0] == 1 and .[1] == $bin_id' \
    >/dev/null <<<"$position_state"; then
    echo "bootstrap position $position_id did not become query-visible" >&2
    exit 1
  fi
  if ! jq -e \
    --argjson amount "$VALIDATION_FEE_SEED_AMOUNT" \
    '.[0] == $amount and .[1] == $amount' \
    >/dev/null <<<"$bin_state"; then
    echo "bootstrap bin $bin_id does not contain exact XOR/SBD seed amounts" >&2
    exit 1
  fi
  seed_index=$(( seed_index + 1 ))
done < <(jq -c '.[]' <<<"$seed_operations")

if (( contract_progress != 5 )); then
  echo "bootstrap work journal did not reach all five exact contract calls" >&2
  exit 1
fi

admin_state="$(view_result admin_state)"
range_governor_state="$(view_result range_governor_state)"
if ! jq -e \
  --arg owner "$SORASWAP_AUTHORITY" \
  '.[0] == $owner and .[1] == 1' \
  >/dev/null <<<"$admin_state"; then
  echo "admin renunciation did not become query-visible" >&2
  exit 1
fi
if ! jq -e '.[0] == 0' >/dev/null <<<"$range_governor_state"; then
  echo "range governor remained enabled after admin renunciation" >&2
  exit 1
fi

temporary_topology_after="$(
  validation_fee_direct_permission_topology_json \
    "$config" "$temporary_permissions"
)"
if ! jq -e \
  'length == 5 and all(.[]; .present == false)' \
  >/dev/null <<<"$temporary_topology_after"; then
  echo "validation-fee bootstrap left temporary permissions behind" >&2
  exit 1
fi
protected_topology_after="$(
  validation_fee_protected_permission_topology_json \
    "$config" "$protected_permissions"
)"
validation_fee_assert_protected_permission_topology_absent \
  "$protected_topology_after"

hajimari_receipt="$(jq -ce '
  [
    .[]
    | select(
        .kind == "contract_call"
        and .operation_key == "hajimari"
      )
    | .receipt
  ]
  | if length == 1 then .[0] else error("hajimari evidence") end
' <<<"$bootstrap_events")"
seed_receipts="$(jq -ce '
  [
    .[]
    | select(
        .kind == "contract_call"
        and (.operation_key | startswith("seed_bin_"))
      )
    | .receipt
  ]
' <<<"$bootstrap_events")"
renounce_receipt="$(jq -ce '
  [
    .[]
    | select(
        .kind == "contract_call"
        and .operation_key == "renounce_admin"
      )
    | .receipt
  ]
  | if length == 1 then .[0] else error("renounce evidence") end
' <<<"$bootstrap_events")"
permission_grants="$(jq -c \
  '[.[] | select(.kind == "permission_grant") | .receipt]' \
  <<<"$bootstrap_events")"
permission_revokes="$(jq -c \
  '[.[] | select(.kind == "permission_revoke") | .receipt]' \
  <<<"$bootstrap_events")"
hajimari_tx_hash="$(jq -er '.transaction.tx_hash_hex' <<<"$hajimari_receipt")"
seed_tx_hashes="$(jq -c '[.[].transaction.tx_hash_hex]' <<<"$seed_receipts")"
renounce_tx_hash="$(jq -er '.transaction.tx_hash_hex' <<<"$renounce_receipt")"
bootstrap_work_journal="$(jq -cn \
  --arg binding_sha256 "$bootstrap_binding_sha256" \
  --arg terminal_event_sha256 "$previous_event_sha256" \
  --argjson event_count "$(jq -r 'length' <<<"$bootstrap_events")" \
  '{
    binding_sha256: $binding_sha256,
    event_count: $event_count,
    terminal_event_sha256: $terminal_event_sha256,
    append_only: true,
    complete: true
  }')"
result_json="$(jq -cn \
  --argjson plan "$plan_json" \
  --argjson chain_fingerprint "$live_chain_json" \
  --argjson pool_config "$pool_config" \
  --argjson risk_config "$risk_config" \
  --argjson admin_state "$admin_state" \
  --argjson range_governor_state "$range_governor_state" \
  --arg hajimari_tx_hash "$hajimari_tx_hash" \
  --argjson seed_tx_hashes "$seed_tx_hashes" \
  --arg renounce_tx_hash "$renounce_tx_hash" \
  --argjson hajimari_receipt "$hajimari_receipt" \
  --argjson seed_receipts "$seed_receipts" \
  --argjson renounce_receipt "$renounce_receipt" \
  --argjson permission_grants "$permission_grants" \
  --argjson permission_revokes "$permission_revokes" \
  --argjson protected_topology_before "$protected_topology_before" \
  --argjson protected_topology_after "$protected_topology_after" \
  --argjson temporary_topology_before "$temporary_topology_before" \
  --argjson temporary_topology_after "$temporary_topology_after" \
  --argjson work_journal "$bootstrap_work_journal" \
  '{
    status: "completed",
    plan: $plan,
    chain_fingerprint: $chain_fingerprint,
    pool_config: $pool_config,
    risk_config: $risk_config,
    admin_state: $admin_state,
    range_governor_state: $range_governor_state,
    bootstrap_work_journal: $work_journal,
    contract_transactions: {
      hajimari: $hajimari_tx_hash,
      seed_bins: $seed_tx_hashes,
      renounce_admin: $renounce_tx_hash
    },
    contract_transaction_evidence: {
      hajimari: $hajimari_receipt,
      seed_bins: $seed_receipts,
      renounce_admin: $renounce_receipt
    },
    permission_grants: $permission_grants,
    permission_revokes: $permission_revokes,
    protected_permission_topology: {
      before: $protected_topology_before,
      after: $protected_topology_after
    },
    temporary_permission_topology: {
      before: $temporary_topology_before,
      after: $temporary_topology_after
    },
    temporary_permissions_revoked: true
  }')"
if ! jq -e '
  .status == "completed"
  and (.bootstrap_work_journal.event_count >= 15)
  and .bootstrap_work_journal.append_only == true
  and .bootstrap_work_journal.complete == true
  and (.contract_transaction_evidence.hajimari | type == "object")
  and (.contract_transaction_evidence.seed_bins | length == 3)
  and (.contract_transaction_evidence.renounce_admin | type == "object")
  and (.permission_grants | length >= 5)
  and (.permission_grants | length) == (.permission_revokes | length)
  and all(.temporary_permission_topology.after[]; .present == false)
  and .protected_permission_topology.after.absent == true
' >/dev/null <<<"$result_json"; then
  echo "validation-fee bootstrap evidence is incomplete" >&2
  exit 1
fi
validation_fee_write_immutable_json \
  "$result_json" "$pool_evidence_path" >/dev/null
cleanup_permissions=0
validation_fee_release_apply_lock
trap - EXIT INT TERM
printf '%s\n' "$result_json"
