#!/bin/zsh
set -euo pipefail

VALIDATION_FEE_SCRIPT_DIR="${${(%):-%N}:A:h}"
SORASWAP_SCRIPT_DIR="${SORASWAP_SCRIPT_DIR:-$VALIDATION_FEE_SCRIPT_DIR}"
source "$VALIDATION_FEE_SCRIPT_DIR/common.sh"
source "$SORASWAP_ROOT/scripts/validation_fee_evidence.sh"

readonly VALIDATION_FEE_SPEC_DEFAULT="$SORASWAP_ROOT/config/validation_fee/deployment.taira.p1.json"
readonly VALIDATION_FEE_CHAIN_ID="fc56984b-2be7-431d-840e-21514d1883f0"
readonly VALIDATION_FEE_CHAIN_DISCRIMINANT=369
readonly VALIDATION_FEE_PINNED_PYTHON="/opt/homebrew/bin/python3"

validation_fee_prepare_plan() {
  local spec_path="$1"
  local iroha_bin="$2"
  local koto_bin="$3"
  local account_helper="$4"
  local split_bin="$5"
  local iroha_source_root="$6"

  /usr/bin/env -i \
    HOME=/Users/takemiyamakoto \
    LANG=C \
    LC_ALL=C \
    PATH=/usr/bin:/bin:/opt/homebrew/bin \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONHASHSEED=0 \
    PYTHONNOUSERSITE=1 \
    TMPDIR=/private/tmp \
    TZ=UTC \
    "$VALIDATION_FEE_PINNED_PYTHON" \
    "$SORASWAP_ROOT/scripts/prepare_validation_fee_deployment.py" \
    --root "$SORASWAP_ROOT" \
    --spec "$spec_path" \
    --iroha-bin "$iroha_bin" \
    --koto-bin "$koto_bin" \
    --account-helper "$account_helper" \
    --split-deploy-bin "$split_bin" \
    --iroha-source-root "$iroha_source_root"
}

validation_fee_evidence_phase_json() {
  local phase="$1"
  local plan_sha256="$2"
  local payload="$3"

  jq -cn \
    --arg phase "$phase" \
    --arg plan_sha256 "$plan_sha256" \
    --argjson payload "$payload" \
    '{
      schema_version: 1,
      phase: $phase,
      plan_sha256: $plan_sha256,
      payload: $payload
    }'
}

validation_fee_require_regular_evidence_file() {
  local evidence_file="$1"
  local mode

  [[ -f "$evidence_file" && ! -L "$evidence_file" ]] || {
    echo "validation-fee evidence is not a regular file: $evidence_file" >&2
    return 1
  }
  mode="$(stat -f '%Lp' "$evidence_file" 2>/dev/null \
    || stat -c '%a' "$evidence_file" 2>/dev/null)" \
    || return 1
  if [[ "$mode" != "444" ]]; then
    echo "validation-fee evidence must be immutable mode 0444: $evidence_file" >&2
    return 1
  fi
  jq -e . "$evidence_file" >/dev/null || {
    echo "validation-fee evidence is not valid JSON: $evidence_file" >&2
    return 1
  }
}

validation_fee_require_phase_binding() {
  local evidence_file="$1"
  local phase="$2"
  local plan_sha256="$3"

  validation_fee_require_regular_evidence_file "$evidence_file" || return 1
  jq -e \
    --arg phase "$phase" \
    --arg plan_sha256 "$plan_sha256" \
    '
      .schema_version == 1
      and .phase == $phase
      and .plan_sha256 == $plan_sha256
      and (.payload | type == "object")
    ' "$evidence_file" >/dev/null || {
      echo "validation-fee evidence phase binding is invalid: $evidence_file" >&2
      return 1
    }
}

validation_fee_assert_alias_absent() {
  local config="$1"
  local contract_alias="$2"
  local status

  if contract_alias_resolve_json "$config" "$contract_alias" >/dev/null 2>&1; then
    echo "fresh validation-fee deployment requires absent alias $contract_alias" >&2
    return 1
  else
    status=$?
  fi
  if (( status != 2 )); then
    echo "could not prove validation-fee alias absence: $contract_alias" >&2
    return 1
  fi
}

validation_fee_assert_chain_fingerprint_matches() {
  local expected="$1"
  local actual="$2"

  if ! jq -en \
    --argjson expected "$expected" \
    --argjson actual "$actual" \
    '$expected == $actual' >/dev/null; then
    echo "validation-fee deployment journal belongs to a different chain fingerprint" >&2
    return 1
  fi
}

validation_fee_assert_registration_receipt() {
  local receipt="$1"
  local expected_account="$2"
  local expected_purpose="$3"

  if ! jq -e \
    --arg account_id "$expected_account" \
    --arg purpose "$expected_purpose" \
    '
      .account_id == $account_id
      and .purpose == $purpose
      and .preexisting == false
      and (.transaction | type == "object")
      and (.terminal | type == "object")
    ' >/dev/null <<<"$receipt"; then
    echo "validation-fee subject-registration receipt is invalid" >&2
    return 1
  fi
  validation_fee_assert_transaction_evidence_json \
    "$(jq -c '.transaction' <<<"$receipt")" \
    "$(jq -c '.terminal' <<<"$receipt")"
}

validation_fee_assert_deploy_receipt() {
  local config="$1"
  local receipt="$2"
  local spec_json="$3"
  local contract_json="$4"
  local split_json transaction alias_json manifest_json code_hash

  split_json="$(jq -ce '.split_receipt' <<<"$receipt")" || return 1
  validation_fee_validate_split_deploy_receipt_json \
    "$split_json" "$spec_json" "$contract_json" >/dev/null || return 1
  while IFS= read -r transaction; do
    validation_fee_assert_transaction_evidence_json \
      "$(jq -c '.transaction' <<<"$transaction")" \
      "$(jq -c '.terminal' <<<"$transaction")" || return 1
    validation_fee_reverify_transaction_evidence_json \
      "$config" "$(jq -c '.transaction' <<<"$transaction")" || return $?
  done < <(jq -c '.transactions[]' <<<"$receipt")
  if ! jq -e \
    --argjson expected_count "$(
      jq '[.register_bytes_stage_tx_hashes[]]
        | length + 3' <<<"$split_json"
    )" \
    --argjson split "$split_json" \
    '
      (.transactions | length == $expected_count)
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
    ' \
    >/dev/null <<<"$receipt"; then
    echo "validation-fee deploy receipt has incomplete or mismatched transaction evidence" >&2
    return 1
  fi
  alias_json="$(
    contract_alias_resolve_json \
      "$config" \
      "$(jq -er '.alias' <<<"$contract_json")"
  )" || return 1
  validation_fee_assert_alias_resolution \
    "$alias_json" "$contract_json" "$(jq -er '.dataspace' <<<"$spec_json")" \
    || return 1
  code_hash="$(jq -er '.code_hash' <<<"$contract_json")" || return 1
  manifest_json="$(contract_manifest_json_by_code_hash "$config" "$code_hash")" \
    || return 1
  validation_fee_assert_manifest_hashes "$manifest_json" "$contract_json" \
    || return 1
  contract_code_bytes_visible_by_code_hash "$config" "$code_hash" || {
    echo "validation-fee contract code bytes are no longer visible" >&2
    return 1
  }
}

validation_fee_assert_pool_bootstrap_evidence() {
  local config="$1"
  local evidence="$2"
  local pool_contract="$3"
  local payout_contract="$4"
  local pool_subject="$5"
  local payout_subject="$6"
  local receipt

  if ! jq -e \
    --arg pool_contract "$pool_contract" \
    --arg payout_contract "$payout_contract" \
    --arg pool_subject "$pool_subject" \
    --arg payout_subject "$payout_subject" \
    '
      . as $evidence
      | (
          $evidence.temporary_permission_topology.before
          | map({holder: .holder, permission: .permission})
        ) as $expected_permissions
      | $evidence.status == "completed"
      and $evidence.plan.chain_id == "fc56984b-2be7-431d-840e-21514d1883f0"
      and $evidence.plan.chain_discriminant == 369
      and $evidence.plan.pool.contract_address == $pool_contract
      and $evidence.plan.pool.subject_account_id == $pool_subject
      and $evidence.plan.payout_contract_address == $payout_contract
      and $evidence.plan.payout_subject_account_id == $payout_subject
      and ($evidence.plan.operations | map(.entrypoint)) == [
        "hajimari",
        "seed_bin",
        "seed_bin",
        "seed_bin",
        "renounce_admin"
      ]
      and ($evidence.contract_transaction_evidence.seed_bins | length == 3)
      and ($evidence.permission_grants | length >= 5)
      and (
        ($evidence.permission_grants | length)
        == ($evidence.permission_revokes | length)
      )
      and $evidence.bootstrap_work_journal.append_only == true
      and $evidence.bootstrap_work_journal.complete == true
      and (
        $evidence.bootstrap_work_journal.event_count
        == (
          5
          + ($evidence.permission_grants | length)
          + ($evidence.permission_revokes | length)
        )
      )
      and (
        [
          $evidence.contract_transaction_evidence.hajimari,
          $evidence.contract_transaction_evidence.seed_bins[],
          $evidence.contract_transaction_evidence.renounce_admin,
          $evidence.permission_grants[],
          $evidence.permission_revokes[]
          | .transaction.tx_hash_hex
        ] as $transaction_hashes
        | ($transaction_hashes | length)
          == ($transaction_hashes | unique | length)
      )
      and (
        $evidence.bootstrap_work_journal.binding_sha256
        | test("^[0-9a-f]{64}$")
      )
      and (
        $evidence.bootstrap_work_journal.terminal_event_sha256
        | test("^[0-9a-f]{64}$")
      )
      and $evidence.temporary_permissions_revoked == true
      and all(
        $evidence.temporary_permission_topology.before[];
        .present == false
      )
      and all(
        $evidence.temporary_permission_topology.after[];
        .present == false
      )
      and $evidence.protected_permission_topology.before.absent == true
      and $evidence.protected_permission_topology.after.absent == true
      and all(
        $evidence.permission_grants[];
        . as $receipt
        | any(
            $expected_permissions[];
            .holder == $receipt.account_id
            and .permission == $receipt.permission
          )
      )
      and all(
        $evidence.permission_revokes[];
        . as $receipt
        | any(
            $expected_permissions[];
            .holder == $receipt.account_id
            and .permission == $receipt.permission
          )
      )
      and all(
        $expected_permissions[];
        . as $expected
        | (
            [
              $evidence.permission_grants[]
              | select(
                  .account_id == $expected.holder
                  and .permission == $expected.permission
                )
            ]
            | length
          ) as $grant_count
        | (
            [
              $evidence.permission_revokes[]
              | select(
                  .account_id == $expected.holder
                  and .permission == $expected.permission
                )
            ]
            | length
          ) as $revoke_count
        | $grant_count >= 1 and $grant_count == $revoke_count
      )
      and $evidence.contract_transaction_evidence.hajimari.entrypoint
        == "hajimari"
      and (
        $evidence.contract_transaction_evidence.seed_bins
        | map(.entrypoint)
      ) == ["seed_bin", "seed_bin", "seed_bin"]
      and (
        $evidence.contract_transaction_evidence.seed_bins
        | map(.arguments.position_id)
      ) == [
        "validation_fee_seed_bin_0",
        "validation_fee_seed_bin_1",
        "validation_fee_seed_bin_2"
      ]
      and (
        $evidence.contract_transaction_evidence.seed_bins
        | map(.arguments.bin_id)
      ) == [0, 1, 2]
      and all(
        $evidence.contract_transaction_evidence.seed_bins[].arguments;
        .base_amount == 1000 and .quote_amount == 1000
      )
      and $evidence.contract_transaction_evidence.renounce_admin.entrypoint
        == "renounce_admin"
      and $evidence.contract_transactions.hajimari
        == $evidence.contract_transaction_evidence.hajimari.transaction.tx_hash_hex
      and $evidence.contract_transactions.seed_bins
        == (
          $evidence.contract_transaction_evidence.seed_bins
          | map(.transaction.tx_hash_hex)
        )
      and $evidence.contract_transactions.renounce_admin
        == $evidence.contract_transaction_evidence.renounce_admin.transaction.tx_hash_hex
    ' >/dev/null <<<"$evidence"; then
    echo "validation-fee pool bootstrap evidence is incomplete" >&2
    return 1
  fi
  while IFS= read -r receipt; do
    validation_fee_assert_transaction_evidence_json \
      "$(jq -c '.transaction' <<<"$receipt")" \
      "$(jq -c '.terminal' <<<"$receipt")" || return 1
    validation_fee_reverify_transaction_evidence_json \
      "$config" "$(jq -c '.transaction' <<<"$receipt")" || return $?
  done < <(jq -c '
    [
      .contract_transaction_evidence.hajimari,
      .contract_transaction_evidence.seed_bins[],
      .contract_transaction_evidence.renounce_admin,
      .permission_grants[],
      .permission_revokes[]
    ][]
  ' <<<"$evidence")
}

validation_fee_assert_live_pool_bootstrap_state() {
  local config="$1"
  local pool_contract="$2"
  local pool_subject="$3"
  local authority="$4"
  local pool_config risk_config admin_state range_governor_state
  local position_id bin_id position_state bin_state

  pool_config="$(contract_view_result_json "$(
    submit_contract_view \
      "$config" "$pool_contract" pool_config "$SORASWAP_SMOKE_GAS_LIMIT" null
  )")" || return 1
  if ! jq -e \
    --arg pool_subject "$pool_subject" \
    '
      . == [
        "6TEAJqbb8oEPmLncoNiMRbLEK6tw",
        "7ZepsJTHCVLKsrFFNZGSRGZgvBhv",
        $pool_subject,
        3000,
        1,
        0
      ]
    ' >/dev/null <<<"$pool_config"; then
    echo "live validation-fee pool configuration differs from the bootstrap binding" >&2
    return 1
  fi
  risk_config="$(contract_view_result_json "$(
    submit_contract_view \
      "$config" "$pool_contract" risk_config "$SORASWAP_SMOKE_GAS_LIMIT" null
  )")" || return 1
  [[ "$risk_config" == "[10000,0,0,8,0]" ]] || {
    echo "live validation-fee pool risk bounds differ from the bootstrap binding" >&2
    return 1
  }
  admin_state="$(contract_view_result_json "$(
    submit_contract_view \
      "$config" "$pool_contract" admin_state "$SORASWAP_SMOKE_GAS_LIMIT" null
  )")" || return 1
  if ! jq -e \
    --arg authority "$authority" \
    '.[0] == $authority and .[1] == 1' >/dev/null <<<"$admin_state"; then
    echo "live validation-fee pool admin is not irreversibly renounced" >&2
    return 1
  fi
  range_governor_state="$(contract_view_result_json "$(
    submit_contract_view \
      "$config" \
      "$pool_contract" \
      range_governor_state \
      "$SORASWAP_SMOKE_GAS_LIMIT" \
      null
  )")" || return 1
  if ! jq -e '.[0] == 0' >/dev/null <<<"$range_governor_state"; then
    echo "live validation-fee pool range governor is still enabled" >&2
    return 1
  fi
  for bin_id in 0 1 2; do
    position_id="validation_fee_seed_bin_$bin_id"
    position_state="$(contract_view_result_json "$(
      submit_contract_view \
        "$config" \
        "$pool_contract" \
        mirror_position \
        "$SORASWAP_SMOKE_GAS_LIMIT" \
        "$(jq -cn --arg position_id "$position_id" \
          '{position_id: $position_id}')"
    )")" || return 1
    if ! jq -e \
      --argjson bin_id "$bin_id" \
      '.[0] == 1 and .[1] == $bin_id' >/dev/null <<<"$position_state"; then
      echo "live validation-fee pool is missing bootstrap position $position_id" >&2
      return 1
    fi
    bin_state="$(contract_view_result_json "$(
      submit_contract_view \
        "$config" \
        "$pool_contract" \
        mirror_bin \
        "$SORASWAP_SMOKE_GAS_LIMIT" \
        "$(jq -cn --argjson bin_id "$bin_id" '{bin_id: $bin_id}')"
    )")" || return 1
    if ! jq -e \
      '.[0] == 1000 and .[1] == 1000' >/dev/null <<<"$bin_state"; then
      echo "live validation-fee pool bin $bin_id has unexpected seed reserves" >&2
      return 1
    fi
  done
}

validation_fee_check_journal_shape() {
  local evidence_dir="$1"
  local -a phases=(
    00.plan.json
    01.preflight.json
    02.pool-subject-registration.json
    03.payout-subject-registration.json
    04.pool-deployment.json
    05.payout-deployment.json
    06.pool-bootstrap.json
    07.final.json
  )
  local file phase found_gap=0

  for file in "$evidence_dir"/*(DN); do
    [[ -f "$file" && ! -L "$file" ]] || {
      echo "validation-fee evidence directory contains a non-regular entry: $file" >&2
      return 1
    }
    if [[ "${file:t}" == "root.binding.json" ]]; then
      validation_fee_require_immutable_json_file "$file" || return 1
      continue
    fi
    if (( ${phases[(Ie)${file:t}]} == 0 )); then
      echo "validation-fee evidence directory contains an unexpected file: $file" >&2
      return 1
    fi
  done
  for phase in "${phases[@]}"; do
    if [[ -e "$evidence_dir/$phase" ]]; then
      if (( found_gap )); then
        echo "validation-fee deployment journal contains a phase gap before $phase" >&2
        return 1
      fi
    else
      found_gap=1
    fi
  done
}

validation_fee_record_or_verify_registration() {
  local config="$1"
  local phase_path="$2"
  local phase="$3"
  local plan_sha256="$4"
  local account_id="$5"
  local purpose="$6"
  local journal_prefix="$7"
  local prepared_dir="$8"
  local receipt phase_json operation_json semantic_operation_json state new_submission=0
  local transaction terminal_json

  semantic_operation_json="$(jq -cn \
    --arg kind account_registration \
    --arg plan_sha256 "$plan_sha256" \
    --arg account_id "$account_id" \
    --arg purpose "$purpose" \
    '{
      kind: $kind,
      plan_sha256: $plan_sha256,
      account_id: $account_id,
      purpose: $purpose
    }')"
  operation_json="$(
    validation_fee_prepare_bound_ledger_operation_json \
      "$config" "$semantic_operation_json" "$prepared_dir"
  )" || return $?
  if [[ -e "$phase_path" ]]; then
    validation_fee_require_phase_binding "$phase_path" "$phase" "$plan_sha256" \
      || return 1
    receipt="$(jq -ce '.payload.receipt' "$phase_path")" || return 1
    validation_fee_assert_registration_receipt \
      "$receipt" "$account_id" "$purpose" || return 1
    validation_fee_reverify_transaction_evidence_json \
      "$config" "$(jq -c '.transaction' <<<"$receipt")" || return $?
    [[ "$(validation_fee_account_presence "$config" "$account_id")" \
      == "present" ]] || {
      echo "journaled validation-fee subject is missing on-chain: $account_id" >&2
      return 1
    }
    if [[ "$(validation_fee_mutation_journal_state "$journal_prefix")" \
      != "Applied" ]]; then
      echo "journaled validation-fee registration lacks an Applied mutation journal" >&2
      return 1
    fi
    validation_fee_assert_mutation_journal \
      "$journal_prefix" "$operation_json" || return 1
    if ! jq -e \
      --argjson receipt "$receipt" \
      '.receipt == $receipt' "$journal_prefix.Applied.json" >/dev/null; then
      echo "validation-fee registration phase differs from its Applied journal" >&2
      return 1
    fi
    return 0
  fi

  state="$(validation_fee_mutation_journal_state "$journal_prefix")" || return 1
  case "$state" in
    Applied)
      validation_fee_assert_mutation_journal \
        "$journal_prefix" "$operation_json" || return 1
      receipt="$(jq -ce '.receipt' "$journal_prefix.Applied.json")" || return 1
      ;;
    submission)
      validation_fee_assert_mutation_journal \
        "$journal_prefix" "$operation_json" || return 1
      transaction="$(jq -ce '.transaction' "$journal_prefix.submission.json")" \
        || return 1
      terminal_json="$(
        validation_fee_applied_transaction_json \
          "$config" "$(jq -er '.tx_hash_hex' <<<"$transaction")"
      )" || {
        echo "validation-fee registration submission is not proven Applied; refusing retry" >&2
        return 1
      }
      if ! wait_for_account_exists "$config" "$account_id" 30 1 \
        || [[ "$(validation_fee_account_presence "$config" "$account_id")" \
          != "present" ]]; then
        echo "submitted validation-fee registration is not query-visible" >&2
        return 1
      fi
      receipt="$(jq -cn \
        --arg account_id "$account_id" \
        --arg purpose "$purpose" \
        --argjson transaction "$transaction" \
        --argjson terminal "$terminal_json" \
        '{
          account_id: $account_id,
          purpose: $purpose,
          preexisting: false,
          transaction: $transaction,
          terminal: $terminal
        }')"
      validation_fee_record_mutation_applied \
        "$journal_prefix" "$receipt" "$operation_json" || return 1
      ;;
    intent)
      validation_fee_fail_on_ambiguous_mutation \
        "$journal_prefix" "$operation_json" || return 1
      return 1
      ;;
    absent)
      receipt="$(
        validation_fee_register_account_with_evidence \
          "$config" "$account_id" "$purpose" "$journal_prefix" \
          "$prepared_dir" "$operation_json"
      )" || return $?
      new_submission=1
      ;;
  esac
  validation_fee_assert_registration_receipt \
    "$receipt" "$account_id" "$purpose" || return 1
  phase_json="$(
    validation_fee_evidence_phase_json \
      "$phase" \
      "$plan_sha256" \
      "$(jq -cn --argjson receipt "$receipt" '{receipt: $receipt}')"
  )"
  validation_fee_write_immutable_json "$phase_json" "$phase_path" >/dev/null \
    || return 1
  if (( new_submission == 1 )); then
    validation_fee_pause_result_json "$phase" "$journal_prefix.Applied.json"
    return "$VALIDATION_FEE_ONE_WRITE_PAUSE_RETURN_STATUS"
  fi
}

validation_fee_record_or_verify_deploy() {
  local config="$1"
  local phase_path="$2"
  local phase="$3"
  local plan_sha256="$4"
  local spec_json="$5"
  local contract_json="$6"
  local authority="$7"
  local split_bin="$8"
  local prepared_dir="$9"
  local mutation_dir="${10}"
  local receipt phase_json prepared_json item result sequence label
  local journal_prefix split_receipt transactions_json alias_json manifest_json
  local deploy_nonce next_nonce current_nonce contract_address contract_alias
  local contract_subject code_hash abi_hash dataspace

  if [[ -e "$phase_path" ]]; then
    validation_fee_require_phase_binding "$phase_path" "$phase" "$plan_sha256" \
      || return 1
    receipt="$(jq -ce '.payload.receipt' "$phase_path")" || return 1
    validation_fee_assert_deploy_receipt \
      "$config" "$receipt" "$spec_json" "$contract_json"
    return
  fi

  prepared_json="$(
    validation_fee_prepare_split_deploy_one_write_json \
      "$config" "$authority" "$spec_json" "$contract_json" \
      "$split_bin" "$prepared_dir"
  )" || return $?
  while IFS= read -r item; do
    sequence="$(jq -er '.sequence' <<<"$item")" || return 1
    label="$(jq -er '.label' <<<"$item")" || return 1
    printf -v journal_prefix '%s/%04d.%s' \
      "$mutation_dir" "$sequence" "$label"
    result="$(
      validation_fee_submit_prepared_transaction_one_write_json \
        "$config" "$contract_json" "$prepared_dir" "$item" "$journal_prefix"
    )" || return $?
    if [[ "$(jq -er '.new_submission' <<<"$result")" == "true" ]]; then
      validation_fee_pause_result_json \
        "$(jq -er '.key' <<<"$contract_json").$label" \
        "$journal_prefix.Applied.json"
      return "$VALIDATION_FEE_ONE_WRITE_PAUSE_RETURN_STATUS"
    fi
  done < <(jq -c '.transactions[]' <<<"$prepared_json")

  split_receipt="$(jq -ce '.split_receipt' <<<"$prepared_json")" || return 1
  transactions_json='[]'
  while IFS= read -r item; do
    sequence="$(jq -er '.sequence' <<<"$item")" || return 1
    label="$(jq -er '.label' <<<"$item")" || return 1
    printf -v journal_prefix '%s/%04d.%s' \
      "$mutation_dir" "$sequence" "$label"
    transactions_json="$(jq -c \
      --argjson receipt "$(jq -ce '.receipt' "$journal_prefix.Applied.json")" \
      '. + [$receipt]' <<<"$transactions_json")" || return 1
  done < <(jq -c '.transactions[]' <<<"$prepared_json")

  deploy_nonce="$(jq -er '.deploy_nonce' <<<"$contract_json")" || return 1
  next_nonce=$(( deploy_nonce + 1 ))
  contract_address="$(jq -er '.contract_address' <<<"$contract_json")" \
    || return 1
  contract_alias="$(jq -er '.alias' <<<"$contract_json")" || return 1
  contract_subject="$(jq -er '.subject_account_id' <<<"$contract_json")" \
    || return 1
  code_hash="$(jq -er '.code_hash' <<<"$contract_json")" || return 1
  abi_hash="$(jq -er '.abi_hash' <<<"$contract_json")" || return 1
  dataspace="$(jq -er '.dataspace' <<<"$spec_json")" || return 1
  alias_json="$(
    wait_for_contract_alias_activation \
      "$config" "$contract_alias" "$contract_address" \
      "$(jq -er '.commit_tx_hash' <<<"$split_receipt")"
  )" || return 1
  validation_fee_assert_alias_resolution \
    "$alias_json" "$contract_json" "$dataspace" || return 1
  manifest_json="$(
    wait_for_contract_manifest_by_code_hash \
      "$config" "$code_hash" "${SORASWAP_DEPLOY_MANIFEST_WAIT_SECS:-120}" 1
  )" || return 1
  validation_fee_assert_manifest_hashes "$manifest_json" "$contract_json" \
    || return 1
  wait_for_contract_code_bytes_by_code_hash \
    "$config" "$code_hash" "${SORASWAP_DEPLOY_MANIFEST_WAIT_SECS:-120}" 1 \
    >/dev/null || return 1
  current_nonce="$(contract_deploy_nonce_for_authority "$config" "$authority")" \
    || return 1
  [[ "$current_nonce" == "$next_nonce" ]] || {
    echo "validation-fee deploy nonce is $current_nonce after deploy, expected $next_nonce" >&2
    return 1
  }
  receipt="$(jq -cn \
    --arg contract_key "$(jq -er '.key' <<<"$contract_json")" \
    --arg contract_address "$contract_address" \
    --arg contract_alias "$contract_alias" \
    --arg subject_account_id "$contract_subject" \
    --arg code_hash "$code_hash" \
    --arg abi_hash "$abi_hash" \
    --argjson deploy_nonce "$deploy_nonce" \
    --argjson next_deploy_nonce "$next_nonce" \
    --argjson split_receipt "$split_receipt" \
    --argjson transactions "$transactions_json" \
    --argjson alias_resolution "$alias_json" \
    --argjson manifest "$manifest_json" \
    '{
      contract_key: $contract_key,
      contract_address: $contract_address,
      contract_alias: $contract_alias,
      subject_account_id: $subject_account_id,
      deploy_nonce: $deploy_nonce,
      next_deploy_nonce: $next_deploy_nonce,
      code_hash: $code_hash,
      abi_hash: $abi_hash,
      split_receipt: $split_receipt,
      transactions: $transactions,
      alias_resolution: $alias_resolution,
      manifest: $manifest,
      code_bytes_visible: true
    }')"
  validation_fee_assert_deploy_receipt \
    "$config" "$receipt" "$spec_json" "$contract_json" || return 1
  phase_json="$(
    validation_fee_evidence_phase_json \
      "$phase" \
      "$plan_sha256" \
      "$(jq -cn --argjson receipt "$receipt" '{receipt: $receipt}')"
  )"
  validation_fee_write_immutable_json "$phase_json" "$phase_path" >/dev/null
}

validation_fee_main() {
  local action="${1:-plan}"
  local spec_path="${SORASWAP_VALIDATION_FEE_DEPLOY_SPEC:-$VALIDATION_FEE_SPEC_DEFAULT}"
  local iroha_bin="${SORASWAP_VALIDATION_FEE_IROHA_BIN:-$SORASWAP_IROHA_ROOT/target/release/iroha}"
  local koto_bin="${SORASWAP_VALIDATION_FEE_KOTO_BIN:-$SORASWAP_IROHA_ROOT/target/release/koto}"
  local account_helper="${SORASWAP_VALIDATION_FEE_ACCOUNT_HELPER_BIN:-$SORASWAP_IROHA_ROOT/target/release/account_literal_reencode}"
  local split_bin="${SORASWAP_VALIDATION_FEE_SPLIT_DEPLOY_BIN:-$SORASWAP_IROHA_ROOT/target/release/split_contract_deploy}"
  local iroha_source_root="${SORASWAP_VALIDATION_FEE_IROHA_SOURCE_ROOT:-$SORASWAP_IROHA_ROOT}"
  local plan_result plan_json plan_sha256 spec_json
  local config authority evidence_dir work_root evidence_abs work_abs lock_dir
  local requested_state_root state_root state_root_abs
  local state_binding_sha256 state_binding_allow_create
  local write_gate_command write_gate_sha actual_write_gate_sha
  local invocation_history_dir
  local mutation_history_exists=""
  local mutation_root prepared_root plan_phase plan_evidence step_status=0
  local chain_json recorded_chain config_chain config_discriminant current_nonce
  local expected_block_1_hash
  local protected_permissions topology pool_contract payout_contract
  local pool_subject payout_subject pool_purpose payout_purpose
  local pool_json payout_json derived_subject
  local preflight_json phase_json bootstrap_json final_json phase_hashes='[]'
  local phase_file phase_hash

  case "$action" in
    plan|apply)
      ;;
    *)
      echo "usage: $0 [plan|apply]" >&2
      return 2
      ;;
  esac

  plan_result="$(
    validation_fee_prepare_plan \
      "$spec_path" \
      "$iroha_bin" \
      "$koto_bin" \
      "$account_helper" \
      "$split_bin" \
      "$iroha_source_root"
  )" || return 1
  if [[ "$action" == "plan" ]]; then
    printf '%s\n' "$plan_result"
    return 0
  fi
  plan_json="$(jq -ce '.plan' <<<"$plan_result")" || return 1
  plan_sha256="$(jq -er '.plan_sha256' <<<"$plan_result")" || return 1
  export SORASWAP_VALIDATION_FEE_REVIEWED_PLAN_SHA256="$plan_sha256"

  if [[ "${SORASWAP_PUBLIC_ENV:-}" != "testnet" ]]; then
    echo "apply requires SORASWAP_PUBLIC_ENV=testnet" >&2
    return 1
  fi
  if [[ "${SORASWAP_VALIDATION_FEE_DEPLOY_APPLY:-0}" != "1" ]]; then
    echo "apply requires SORASWAP_VALIDATION_FEE_DEPLOY_APPLY=1" >&2
    return 1
  fi
  require_public_mutation_consent \
    testnet "fresh Taira validation-fee contract deployment" || return 1

  config="${SORASWAP_VALIDATION_FEE_DEPLOY_CLIENT_CONFIG:-}"
  [[ -n "$config" ]] || {
    echo "apply requires SORASWAP_VALIDATION_FEE_DEPLOY_CLIENT_CONFIG" >&2
    return 1
  }
  evidence_dir="${SORASWAP_VALIDATION_FEE_EVIDENCE_DIR:-}"
  [[ -n "$evidence_dir" && "$evidence_dir" == /* ]] || {
    echo "apply requires an absolute SORASWAP_VALIDATION_FEE_EVIDENCE_DIR" >&2
    return 1
  }
  if [[ -L "$evidence_dir" || ( -e "$evidence_dir" && ! -d "$evidence_dir" ) ]]; then
    echo "validation-fee evidence directory must be a real directory" >&2
    return 1
  fi
  validation_fee_ensure_durable_directory "$evidence_dir" || return 1
  validation_fee_check_journal_shape "$evidence_dir" || return 1
  work_root="${SORASWAP_VALIDATION_FEE_WORK_ROOT:-$evidence_dir.work}"
  [[ "$work_root" == /* ]] || {
    echo "apply requires an absolute SORASWAP_VALIDATION_FEE_WORK_ROOT" >&2
    return 1
  }
  evidence_abs="${evidence_dir:A}"
  work_abs="${work_root:A}"
  if [[ "$evidence_dir" != "$evidence_abs" || "$work_root" != "$work_abs" ]]; then
    echo "validation-fee evidence and work roots must be canonical and symlink-free" >&2
    return 1
  fi
  if [[ "$work_abs" == "$evidence_abs" \
    || "$work_abs" == "$evidence_abs/"* \
    || "$evidence_abs" == "$work_abs/"* ]]; then
    echo "validation-fee work root and canonical evidence must not overlap" >&2
    return 1
  fi
  if [[ -L "$work_root" || ( -e "$work_root" && ! -d "$work_root" ) ]]; then
    echo "validation-fee work root must be a real directory" >&2
    return 1
  fi
  validation_fee_ensure_durable_directory "$work_root" || return 1
  mutation_root="$work_root/deployment-mutations"
  prepared_root="$work_root/prepared"
  validation_fee_ensure_durable_directory "$mutation_root" || return 1
  validation_fee_ensure_durable_directory "$prepared_root" || return 1
  requested_state_root="${SORASWAP_VALIDATION_FEE_STATE_ROOT:-}"
  [[ -n "$requested_state_root" && "$requested_state_root" == /* ]] || {
    echo "apply requires an absolute external validation-fee state root" >&2
    return 1
  }
  state_root_abs="${requested_state_root:A}"
  if [[ "$state_root_abs" == "$evidence_abs" \
    || "$state_root_abs" == "$evidence_abs/"* \
    || "$evidence_abs" == "$state_root_abs/"* \
    || "$state_root_abs" == "$work_abs" \
    || "$state_root_abs" == "$work_abs/"* \
    || "$work_abs" == "$state_root_abs/"* ]]; then
    echo "validation-fee external state, work, and evidence roots must not overlap" >&2
    return 1
  fi
  state_root="$(validation_fee_taira_p1_state_root)" || return 1
  write_gate_command="${SORASWAP_VALIDATION_FEE_WRITE_GATE_COMMAND:-}"
  write_gate_sha="${SORASWAP_VALIDATION_FEE_WRITE_GATE_COMMAND_SHA256:-}"
  actual_write_gate_sha="$(
    validation_fee_reviewed_gate_producer_sha256 \
      "$write_gate_command" "$write_gate_sha"
  )" || return 1
  expected_block_1_hash="${SORASWAP_VALIDATION_FEE_EXPECTED_BLOCK_1_HASH:-}"
  if [[ ! "$expected_block_1_hash" =~ '^[0-9a-f]{64}$' ]]; then
    echo "apply requires a reviewed lowercase block-1 SHA-256" >&2
    return 1
  fi
  lock_dir="$(validation_fee_taira_p1_apply_lock_dir)" || return 1
  validation_fee_acquire_apply_lock "$lock_dir" || return 1
  trap 'validation_fee_release_apply_lock' EXIT
  if [[ -e "$evidence_dir/00.plan.json" ]]; then
    state_binding_allow_create=0
  else
    state_binding_allow_create=1
  fi
  state_binding_sha256="$(
    validation_fee_taira_p1_state_binding_sha256 \
      "$actual_write_gate_sha" "$state_binding_allow_create" \
      "$evidence_abs" "$work_abs"
  )" || return 1
  if [[ -e "$evidence_dir/00.plan.json" ]] \
    && [[ "$(jq -er '.payload.state_binding_sha256' \
      "$evidence_dir/00.plan.json")" != "$state_binding_sha256" ]]; then
    echo "validation-fee deployment plan is bound to another durable state root" >&2
    return 1
  fi
  export SORASWAP_VALIDATION_FEE_BOUND_EVIDENCE_ROOT="$evidence_abs"
  export SORASWAP_VALIDATION_FEE_BOUND_WORK_ROOT="$work_abs"
  export SORASWAP_VALIDATION_FEE_DEPLOYMENT_PLAN_EVIDENCE_PATH="$evidence_abs/00.plan.json"
  invocation_history_dir="$(
    validation_fee_taira_p1_invocation_journal_dir
  )" || return 1
  mutation_history_exists="$(
    find "$evidence_dir" "$work_root" -type f \
      \( -name '*.intent.json' -o -name '*.submission.json' \
        -o -name '*.Applied.json' -o -name '0[2-7].*.json' \) \
      -print -quit 2>/dev/null
  )"
  if [[ -n "$mutation_history_exists" ]]; then
    validation_fee_assert_write_gate_history_dir "$invocation_history_dir" \
      || {
        echo "durable gate history is missing for existing mutation evidence" >&2
        return 1
      }
  fi
  validation_fee_require_one_write_mode || return 1
  validation_fee_assert_write_reservation_history_dir \
    "$invocation_history_dir" || return 1

  ensure_client "$config"
  ensure_authority "$config"
  authority="$SORASWAP_AUTHORITY"
  spec_json="$(jq -ce . "$spec_path")" || return 1
  if [[ "$authority" != "$(jq -er '.authority_account_id' <<<"$plan_json")" ]]; then
    echo "validation-fee client authority differs from the reviewed P1 authority" >&2
    return 1
  fi

  plan_phase="$evidence_dir/00.plan.json"
  plan_evidence="$(
    validation_fee_evidence_phase_json \
      "plan" \
      "$plan_sha256" \
      "$(jq -cn \
        --argjson result "$plan_result" \
        --arg write_gate_command_sha256 "$write_gate_sha" \
        --arg state_binding_sha256 "$state_binding_sha256" \
        --arg block_1_hash "$expected_block_1_hash" \
        '{
          result: $result,
          write_gate_command_sha256: $write_gate_command_sha256,
          state_binding_sha256: $state_binding_sha256,
          block_1_hash: $block_1_hash
        }')"
  )"
  validation_fee_write_immutable_json "$plan_evidence" "$plan_phase" >/dev/null
  validation_fee_require_phase_binding "$plan_phase" "plan" "$plan_sha256"

  config_chain="$(config_chain_id_from_config "$config")" || return 1
  config_discriminant="$(chain_discriminant_for_env_config testnet "$config")" \
    || return 1
  if [[ "$config_chain" != "$VALIDATION_FEE_CHAIN_ID" \
    || "$config_chain" != "$(jq -er '.chain_id' <<<"$plan_json")" ]]; then
    echo "validation-fee client does not target the reviewed fresh Taira chain" >&2
    return 1
  fi
  if [[ "$config_discriminant" != "$VALIDATION_FEE_CHAIN_DISCRIMINANT" \
    || "$config_discriminant" != "$(jq -er '.chain_discriminant' <<<"$plan_json")" ]]; then
    echo "validation-fee client does not use the reviewed Taira discriminant" >&2
    return 1
  fi
  chain_json="$(current_chain_fingerprint_json "$config")" || return 1
  if [[ "$(jq -er '.chain' <<<"$chain_json")" != "$VALIDATION_FEE_CHAIN_ID" ]]; then
    echo "live Torii is not the reviewed fresh Taira chain" >&2
    return 1
  fi
  if [[ "$(jq -er '.block_1_hash' <<<"$chain_json")" \
    != "$expected_block_1_hash" ]]; then
    echo "live Torii block 1 does not match the reviewed fresh-chain fingerprint" >&2
    return 1
  fi

  pool_json="$(jq -ce '.contracts[] | select(.key == "pool")' <<<"$plan_json")" \
    || return 1
  payout_json="$(jq -ce '.contracts[] | select(.key == "payout")' <<<"$plan_json")" \
    || return 1
  pool_contract="$(jq -er '.contract_address' <<<"$pool_json")"
  payout_contract="$(jq -er '.contract_address' <<<"$payout_json")"
  pool_subject="$(jq -er '.subject_account_id' <<<"$pool_json")"
  payout_subject="$(jq -er '.subject_account_id' <<<"$payout_json")"
  pool_purpose="$(jq -er '
    .sequence[]
    | select(.action == "register_contract_subject" and .account_id == $subject)
    | .purpose
  ' --arg subject "$pool_subject" <<<"$plan_json")"
  payout_purpose="$(jq -er '
    .sequence[]
    | select(.action == "register_contract_subject" and .account_id == $subject)
    | .purpose
  ' --arg subject "$payout_subject" <<<"$plan_json")"
  protected_permissions="$(jq -ce '.protected_permissions' <<<"$plan_json")"

  for contract_json in "$pool_json" "$payout_json"; do
    derived_subject="$(
      contract_subject_account_for_literal \
        "$config" \
        "$(jq -er '.contract_address' <<<"$contract_json")"
    )" || return 1
    if [[ "$derived_subject" != "$(jq -er '.subject_account_id' <<<"$contract_json")" ]]; then
      echo "live chain derivation differs from the reviewed validation-fee subject" >&2
      return 1
    fi
  done

  topology="$(
    validation_fee_protected_permission_topology_json \
      "$config" "$protected_permissions"
  )" || return 1
  validation_fee_assert_protected_permission_topology_absent "$topology" \
    || return 1

  if [[ -e "$evidence_dir/01.preflight.json" ]]; then
    validation_fee_require_phase_binding \
      "$evidence_dir/01.preflight.json" "preflight" "$plan_sha256"
    recorded_chain="$(jq -ce '.payload.chain_fingerprint' \
      "$evidence_dir/01.preflight.json")"
    validation_fee_assert_chain_fingerprint_matches \
      "$recorded_chain" "$chain_json"
    if ! jq -e \
      --arg authority "$authority" \
      '
        .payload.authority_account_id == $authority
        and .payload.deploy_nonce == 0
        and .payload.contract_subject_accounts_absent == true
        and .payload.contract_aliases_absent == true
        and .payload.protected_permission_topology.absent == true
      ' "$evidence_dir/01.preflight.json" >/dev/null; then
      echo "validation-fee preflight evidence is incomplete" >&2
      return 1
    fi
  else
    current_nonce="$(contract_deploy_nonce_for_authority "$config" "$authority")" \
      || {
        echo "could not prove the fresh validation-fee deploy nonce" >&2
        return 1
      }
    [[ "$current_nonce" == "0" ]] || {
      echo "fresh validation-fee deployment requires deploy nonce exactly 0" >&2
      return 1
    }
    [[ "$(validation_fee_account_presence "$config" "$pool_subject")" \
      == "absent" ]] || {
      echo "fresh validation-fee deployment requires absent pool subject" >&2
      return 1
    }
    [[ "$(validation_fee_account_presence "$config" "$payout_subject")" \
      == "absent" ]] || {
      echo "fresh validation-fee deployment requires absent payout subject" >&2
      return 1
    }
    validation_fee_assert_alias_absent \
      "$config" "$(jq -er '.alias' <<<"$pool_json")"
    validation_fee_assert_alias_absent \
      "$config" "$(jq -er '.alias' <<<"$payout_json")"
    soraswap_require_public_write_health_ready_for_config \
      "$config" "validation-fee fresh-deployment preflight" || return $?
    preflight_json="$(jq -cn \
      --argjson chain_fingerprint "$chain_json" \
      --arg authority "$authority" \
      --argjson deploy_nonce "$current_nonce" \
      --argjson protected_permission_topology "$topology" \
      '{
        chain_fingerprint: $chain_fingerprint,
        authority_account_id: $authority,
        deploy_nonce: $deploy_nonce,
        contract_subject_accounts_absent: true,
        contract_aliases_absent: true,
        protected_permission_topology: $protected_permission_topology
      }')"
    phase_json="$(
      validation_fee_evidence_phase_json \
        "preflight" "$plan_sha256" "$preflight_json"
    )"
    validation_fee_write_immutable_json \
      "$phase_json" "$evidence_dir/01.preflight.json" >/dev/null
  fi

  step_status=0
  validation_fee_record_or_verify_registration \
    "$config" \
    "$evidence_dir/02.pool-subject-registration.json" \
    "pool_subject_registration" \
    "$plan_sha256" \
    "$pool_subject" \
    "$pool_purpose" \
    "$mutation_root/02.pool-subject-registration" \
    "$prepared_root/ledger/02.pool-subject-registration" \
    || step_status=$?
  if (( step_status == VALIDATION_FEE_ONE_WRITE_PAUSE_RETURN_STATUS )); then
    return 0
  elif (( step_status != 0 )); then
    return "$step_status"
  fi
  step_status=0
  validation_fee_record_or_verify_registration \
    "$config" \
    "$evidence_dir/03.payout-subject-registration.json" \
    "payout_subject_registration" \
    "$plan_sha256" \
    "$payout_subject" \
    "$payout_purpose" \
    "$mutation_root/03.payout-subject-registration" \
    "$prepared_root/ledger/03.payout-subject-registration" \
    || step_status=$?
  if (( step_status == VALIDATION_FEE_ONE_WRITE_PAUSE_RETURN_STATUS )); then
    return 0
  elif (( step_status != 0 )); then
    return "$step_status"
  fi

  topology="$(
    validation_fee_protected_permission_topology_json \
      "$config" "$protected_permissions"
  )"
  validation_fee_assert_protected_permission_topology_absent "$topology"
  step_status=0
  validation_fee_record_or_verify_deploy \
    "$config" \
    "$evidence_dir/04.pool-deployment.json" \
    "pool_deployment" \
    "$plan_sha256" \
    "$plan_json" \
    "$pool_json" \
    "$authority" \
    "$split_bin" \
    "$prepared_root/pool" \
    "$mutation_root/04.pool-deployment" \
    || step_status=$?
  if (( step_status == VALIDATION_FEE_ONE_WRITE_PAUSE_RETURN_STATUS )); then
    return 0
  elif (( step_status != 0 )); then
    return "$step_status"
  fi
  topology="$(
    validation_fee_protected_permission_topology_json \
      "$config" "$protected_permissions"
  )"
  validation_fee_assert_protected_permission_topology_absent "$topology"
  step_status=0
  validation_fee_record_or_verify_deploy \
    "$config" \
    "$evidence_dir/05.payout-deployment.json" \
    "payout_deployment" \
    "$plan_sha256" \
    "$plan_json" \
    "$payout_json" \
    "$authority" \
    "$split_bin" \
    "$prepared_root/payout" \
    "$mutation_root/05.payout-deployment" \
    || step_status=$?
  if (( step_status == VALIDATION_FEE_ONE_WRITE_PAUSE_RETURN_STATUS )); then
    return 0
  elif (( step_status != 0 )); then
    return "$step_status"
  fi

  if [[ -e "$evidence_dir/06.pool-bootstrap.json" ]]; then
    validation_fee_require_regular_evidence_file \
      "$evidence_dir/06.pool-bootstrap.json"
    bootstrap_json="$(jq -ce . "$evidence_dir/06.pool-bootstrap.json")"
  else
    bootstrap_json="$(
      SORASWAP_VALIDATION_FEE_POOL_CONTRACT_ADDRESS="$pool_contract" \
      SORASWAP_VALIDATION_FEE_POOL_SUBJECT_ACCOUNT_ID="$pool_subject" \
      SORASWAP_VALIDATION_FEE_PAYOUT_CONTRACT_ADDRESS="$payout_contract" \
      SORASWAP_VALIDATION_FEE_PAYOUT_SUBJECT_ACCOUNT_ID="$payout_subject" \
      SORASWAP_VALIDATION_FEE_POOL_APPLY=1 \
      SORASWAP_VALIDATION_FEE_POOL_CLIENT_CONFIG="$config" \
      SORASWAP_VALIDATION_FEE_POOL_EVIDENCE_PATH="$evidence_dir/06.pool-bootstrap.json" \
      SORASWAP_VALIDATION_FEE_POOL_RECOVERY_EVIDENCE_PATH="$work_root/recovery/pool-bootstrap.json" \
      SORASWAP_VALIDATION_FEE_POOL_WORK_JOURNAL_DIR="$work_root/pool-bootstrap/events" \
      SORASWAP_VALIDATION_FEE_POOL_MUTATION_JOURNAL_DIR="$work_root/pool-bootstrap/mutations" \
      SORASWAP_VALIDATION_FEE_POOL_PREPARED_LEDGER_DIR="$work_root/pool-bootstrap/prepared-ledger" \
      SORASWAP_VALIDATION_FEE_PARENT_LOCK_DIR="$VALIDATION_FEE_APPLY_LOCK_DIR" \
      SORASWAP_VALIDATION_FEE_PARENT_LOCK_TOKEN="$VALIDATION_FEE_APPLY_LOCK_TOKEN" \
      SORASWAP_VALIDATION_FEE_PARENT_STATE_BINDING_SHA256="$state_binding_sha256" \
      SORASWAP_VALIDATION_FEE_BOUND_EVIDENCE_ROOT="$evidence_abs" \
      SORASWAP_VALIDATION_FEE_BOUND_WORK_ROOT="$work_abs" \
      SORASWAP_VALIDATION_FEE_DEPLOYMENT_PLAN_EVIDENCE_PATH="$evidence_dir/00.plan.json" \
      SORASWAP_VALIDATION_FEE_PREFLIGHT_EVIDENCE_PATH="$evidence_dir/01.preflight.json" \
      SORASWAP_VALIDATION_FEE_POOL_DEPLOYMENT_EVIDENCE_PATH="$evidence_dir/04.pool-deployment.json" \
      SORASWAP_VALIDATION_FEE_PAYOUT_DEPLOYMENT_EVIDENCE_PATH="$evidence_dir/05.payout-deployment.json" \
        zsh "$SORASWAP_ROOT/scripts/bootstrap_validation_fee_pool.sh" apply
    )" || return $?
    if jq -e \
      --arg status "$VALIDATION_FEE_ONE_WRITE_PAUSE_STATUS" \
      '.status == $status' >/dev/null <<<"$bootstrap_json"; then
      printf '%s\n' "$bootstrap_json"
      return 0
    fi
  fi
  validation_fee_assert_chain_fingerprint_matches \
    "$(jq -ce '.chain_fingerprint' <<<"$bootstrap_json")" \
    "$chain_json"
  validation_fee_assert_pool_bootstrap_evidence \
    "$config" \
    "$bootstrap_json" \
    "$pool_contract" \
    "$payout_contract" \
    "$pool_subject" \
    "$payout_subject"
  validation_fee_assert_live_pool_bootstrap_state \
    "$config" "$pool_contract" "$pool_subject" "$authority"

  topology="$(
    validation_fee_protected_permission_topology_json \
      "$config" "$protected_permissions"
  )"
  validation_fee_assert_protected_permission_topology_absent "$topology"
  current_nonce="$(contract_deploy_nonce_for_authority "$config" "$authority")" \
    || return 1
  if [[ "$current_nonce" != "2" ]]; then
    echo "validation-fee deployment ended at nonce $current_nonce, expected exactly 2" >&2
    return 1
  fi

  for phase_file in \
    "$evidence_dir/00.plan.json" \
    "$evidence_dir/01.preflight.json" \
    "$evidence_dir/02.pool-subject-registration.json" \
    "$evidence_dir/03.payout-subject-registration.json" \
    "$evidence_dir/04.pool-deployment.json" \
    "$evidence_dir/05.payout-deployment.json" \
    "$evidence_dir/06.pool-bootstrap.json"; do
    validation_fee_require_regular_evidence_file "$phase_file"
    phase_hash="$(shasum -a 256 "$phase_file" | awk '{print $1}')"
    phase_hashes="$(jq -c \
      --arg file "${phase_file:t}" \
      --arg sha256 "$phase_hash" \
      '. + [{file: $file, sha256: $sha256}]' <<<"$phase_hashes")"
  done
  if [[ -e "$evidence_dir/07.final.json" ]]; then
    validation_fee_require_phase_binding \
      "$evidence_dir/07.final.json" "complete" "$plan_sha256"
    if ! jq -e \
      --argjson chain_fingerprint "$chain_json" \
      --arg authority "$authority" \
      --arg pool_contract_address "$pool_contract" \
      --arg payout_contract_address "$payout_contract" \
      --argjson phase_files "$phase_hashes" \
      '
        .payload.status == "completed"
        and .payload.chain_fingerprint == $chain_fingerprint
        and .payload.authority_account_id == $authority
        and .payload.pool_contract_address == $pool_contract_address
        and .payload.payout_contract_address == $payout_contract_address
        and .payload.final_deploy_nonce == 2
        and .payload.protected_permissions_absent == true
        and .payload.protected_permission_topology.absent == true
        and .payload.phase_files == $phase_files
      ' "$evidence_dir/07.final.json" >/dev/null; then
      echo "final validation-fee evidence no longer matches its immutable phases" >&2
      return 1
    fi
    printf '%s\n' "$evidence_dir/07.final.json"
    return 0
  fi
  final_json="$(validation_fee_evidence_phase_json \
    "complete" \
    "$plan_sha256" \
    "$(jq -cn \
      --argjson chain_fingerprint "$chain_json" \
      --arg authority "$authority" \
      --arg pool_contract_address "$pool_contract" \
      --arg payout_contract_address "$payout_contract" \
      --argjson final_deploy_nonce "$current_nonce" \
      --argjson protected_permission_topology "$topology" \
      --argjson phase_files "$phase_hashes" \
      '{
        status: "completed",
        chain_fingerprint: $chain_fingerprint,
        authority_account_id: $authority,
        pool_contract_address: $pool_contract_address,
        payout_contract_address: $payout_contract_address,
        final_deploy_nonce: $final_deploy_nonce,
        protected_permission_topology: $protected_permission_topology,
        protected_permissions_absent: true,
        phase_files: $phase_files
      }')"
  )"
  validation_fee_write_immutable_json \
    "$final_json" "$evidence_dir/07.final.json" >/dev/null
  validation_fee_release_apply_lock
  trap - EXIT
  printf '%s\n' "$evidence_dir/07.final.json"
}

if [[ "${SORASWAP_VALIDATION_FEE_LIBRARY_ONLY:-0}" != "1" ]]; then
  validation_fee_main "$@"
fi
