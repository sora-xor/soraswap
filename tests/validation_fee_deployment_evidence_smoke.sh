#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
TMP_DIR="${TMP_DIR:A}"
trap 'rm -rf "$TMP_DIR"' EXIT

export SORASWAP_VALIDATION_FEE_LIBRARY_ONLY=1
source "$ROOT/scripts/apply_validation_fee_deployment.sh"

rg -Fq 'SORASWAP_VALIDATION_FEE_DEPLOYMENT_PLAN_EVIDENCE_PATH' \
  "$ROOT/scripts/bootstrap_validation_fee_pool.sh"
rg -Fq 'SORASWAP_VALIDATION_FEE_PREFLIGHT_EVIDENCE_PATH' \
  "$ROOT/scripts/bootstrap_validation_fee_pool.sh"
rg -Fq 'SORASWAP_VALIDATION_FEE_POOL_DEPLOYMENT_EVIDENCE_PATH' \
  "$ROOT/scripts/bootstrap_validation_fee_pool.sh"
rg -Fq 'SORASWAP_VALIDATION_FEE_PAYOUT_DEPLOYMENT_EVIDENCE_PATH' \
  "$ROOT/scripts/bootstrap_validation_fee_pool.sh"
rg -Fq 'SORASWAP_VALIDATION_FEE_POOL_WORK_JOURNAL_DIR' \
  "$ROOT/scripts/bootstrap_validation_fee_pool.sh"
rg -Fq 'SORASWAP_VALIDATION_FEE_POOL_PREPARED_LEDGER_DIR' \
  "$ROOT/scripts/bootstrap_validation_fee_pool.sh"
rg -Fq 'validation_fee_prepare_bound_ledger_operation_json' \
  "$ROOT/scripts/apply_validation_fee_deployment.sh"
rg -Fq 'bootstrap_append_event' \
  "$ROOT/scripts/bootstrap_validation_fee_pool.sh"
rg -Fq 'previous_event_sha256' \
  "$ROOT/scripts/bootstrap_validation_fee_pool.sh"
rg -Fq 'validation_fee_emergency_cleanup_on_exit' \
  "$ROOT/scripts/bootstrap_validation_fee_pool.sh"
rg -Fq "trap 'validation_fee_emergency_cleanup_on_signal INT 130' INT" \
  "$ROOT/scripts/bootstrap_validation_fee_pool.sh"
rg -Fq "trap 'validation_fee_emergency_cleanup_on_signal TERM 143' TERM" \
  "$ROOT/scripts/bootstrap_validation_fee_pool.sh"
rg -Fq 'CRITICAL: validation-fee emergency permission cleanup was not proven' \
  "$ROOT/scripts/bootstrap_validation_fee_pool.sh"
rg -Fq 'validation_fee_bootstrap_preflight_guard_and_unlock' \
  "$ROOT/scripts/bootstrap_validation_fee_pool.sh"
rg -Fq 'bootstrap deployment evidence omits or changes a split transaction receipt' \
  "$ROOT/scripts/bootstrap_validation_fee_pool.sh"
! rg -Fq "cleanup_temporary_permissions || true" \
  "$ROOT/scripts/bootstrap_validation_fee_pool.sh"
! rg -Fq 'status: "already_completed"' \
  "$ROOT/scripts/bootstrap_validation_fee_pool.sh"
rg -Fq 'SORASWAP_VALIDATION_FEE_EXPECTED_BLOCK_1_HASH' \
  "$ROOT/scripts/apply_validation_fee_deployment.sh"

signal_marker="$TMP_DIR/signal-cleanup"
set +e
VALIDATION_FEE_SIGNAL_MARKER="$signal_marker" \
VALIDATION_FEE_SIGNAL_ROOT="$ROOT" \
  zsh -c '
    set -euo pipefail
    source "$VALIDATION_FEE_SIGNAL_ROOT/scripts/validation_fee_evidence.sh"
    signal_cleanup() {
      printf "%s\n" "$1" >"$VALIDATION_FEE_SIGNAL_MARKER"
      return "$1"
    }
    trap "validation_fee_signal_cleanup_and_exit TERM 143 signal_cleanup" TERM
    kill -TERM $$
    sleep 1
  ' >/dev/null 2>&1
signal_exit_code=$?
set -e
if [[ "$signal_exit_code" != "143" \
  || "$(cat "$signal_marker")" != "143" ]]; then
  echo "TERM did not execute validation-fee cleanup with exit status 143" >&2
  exit 1
fi
signal_failure_marker="$TMP_DIR/signal-cleanup-failure"
set +e
VALIDATION_FEE_SIGNAL_MARKER="$signal_failure_marker" \
VALIDATION_FEE_SIGNAL_ROOT="$ROOT" \
  zsh -c '
    set -euo pipefail
    source "$VALIDATION_FEE_SIGNAL_ROOT/scripts/validation_fee_evidence.sh"
    signal_cleanup_failure() {
      printf "%s\n" "$1" >"$VALIDATION_FEE_SIGNAL_MARKER"
      return 1
    }
    trap "validation_fee_signal_cleanup_and_exit INT 130 signal_cleanup_failure" INT
    kill -INT $$
    sleep 1
  ' >/dev/null 2>&1
signal_failure_exit_code=$?
set -e
if [[ "$signal_failure_exit_code" != "1" \
  || "$(cat "$signal_failure_marker")" != "130" ]]; then
  echo "INT cleanup failure did not override the signal exit status" >&2
  exit 1
fi

spec_json="$(jq -c . "$ROOT/config/validation_fee/deployment.taira.p1.json")"
contract_json="$(jq -c '.contracts[0]' <<<"$spec_json")"
hash_1="$(printf '1%.0s' {1..64})"
hash_2="$(printf '2%.0s' {1..64})"
hash_3="$(printf '3%.0s' {1..64})"
hash_4="$(printf '4%.0s' {1..64})"
applied_terminal="$(jq -cn \
  --arg hash "$hash_1" \
  '{
    source: "pipeline",
    status: {status: {kind: "Applied"}},
    queried_tx_hash_hex: $hash
  }')"
committed_terminal="$(jq -cn \
  --arg hash "$hash_1" \
  '{
    source: "committed",
    transaction_result: {Ok: null},
    queried_tx_hash_hex: $hash
  }')"

normalized="$(
  validation_fee_normalized_transaction_hash_json "0x${hash_1:u}"
)"
jq -e \
  --arg expected "$hash_1" \
  '.tx_hash_hex == $expected' >/dev/null <<<"$normalized"
canonical_literal="hash:${${hash_2:u}}#ABCD"
normalized="$(
  validation_fee_normalized_transaction_hash_json "$canonical_literal"
)"
jq -e \
  --arg expected "$hash_2" \
  '.tx_hash_hex == $expected' >/dev/null <<<"$normalized"
if validation_fee_normalized_transaction_hash_json "hash:$hash_1" \
  >/dev/null 2>&1; then
  echo "truncated canonical hash literal was accepted" >&2
  exit 1
fi

validation_fee_assert_applied_terminal_json "$applied_terminal"
validation_fee_assert_applied_terminal_json "$committed_terminal"
if validation_fee_assert_applied_terminal_json \
  '{"source":"pipeline","status":{"status":{"kind":"Rejected"}}}' \
  >/dev/null 2>&1; then
  echo "rejected terminal evidence was accepted" >&2
  exit 1
fi
validation_fee_assert_transaction_evidence_json \
  "$(jq -cn --arg hash "$hash_1" \
    '{tx_hash: $hash, tx_hash_hex: $hash}')" \
  "$applied_terminal"

split_receipt="$(jq -cn \
  --argjson spec "$spec_json" \
  --argjson contract "$contract_json" \
  --arg hash_1 "$hash_1" \
  --arg hash_2 "$hash_2" \
  --arg hash_3 "$hash_3" \
  --arg hash_4 "$hash_4" \
  '{
    ok: true,
    submitted: true,
    chain_id: $spec.chain_id,
    chain_discriminant: $spec.chain_discriminant,
    dataspace: $spec.dataspace,
    contract_address: $contract.contract_address,
    contract_alias: $contract.alias,
    contract_subject_account: $contract.subject_account_id,
    deploy_nonce: $contract.deploy_nonce,
    next_deploy_nonce: ($contract.deploy_nonce + 1),
    expected_previous_contract_address: null,
    code_hash_hex: $contract.code_hash,
    register_bytes_tx_strategy: "native_chunks",
    register_bytes_chunk_count: 2,
    register_bytes_stage_tx_hashes: [$hash_1],
    register_bytes_tx_hash: $hash_2,
    register_manifest_tx_hash: $hash_3,
    commit_tx_hash: $hash_4
  }')"
validation_fee_validate_split_deploy_receipt_json \
  "$split_receipt" "$spec_json" "$contract_json" >/dev/null
if validation_fee_validate_split_deploy_receipt_json \
  "$(jq '.register_bytes_chunk_count = 3' <<<"$split_receipt")" \
  "$spec_json" "$contract_json" >/dev/null 2>&1; then
  echo "inconsistent validation-fee chunk/stage count was accepted" >&2
  exit 1
fi
for field in contract_alias contract_address contract_subject_account deploy_nonce \
  next_deploy_nonce code_hash_hex; do
  altered="$(jq \
    --arg field "$field" \
    'if $field == "deploy_nonce" or $field == "next_deploy_nonce"
      then .[$field] = 99
      else .[$field] = "wrong"
      end' <<<"$split_receipt")"
  if validation_fee_validate_split_deploy_receipt_json \
    "$altered" "$spec_json" "$contract_json" >/dev/null 2>&1; then
    echo "split deploy receipt accepted altered $field" >&2
    exit 1
  fi
done

validation_fee_applied_transaction_json() {
  jq -cn \
    --arg hash "$2" \
    '{
      source: "pipeline",
      status: {status: {kind: "Applied"}},
      queried_tx_hash_hex: $hash
    }'
}
transaction_evidence="$(
  validation_fee_split_deploy_transactions_json \
    "/offline/not-used.toml" "$split_receipt"
)"
jq -e \
  'length == 4
   and ([.[].label] == [
     "register_bytes_stage_0",
     "register_bytes_finalize",
     "register_manifest",
     "commit"
   ])
   and all(.[].terminal; .source == "pipeline")' \
  >/dev/null <<<"$transaction_evidence"

fixture_transaction_json() {
  local fixture_index="$1"
  local fixture_hash

  fixture_hash="$(printf '%064x' "$fixture_index")"
  jq -cn \
    --arg tx_hash "hash:${fixture_hash:u}#ABCD" \
    --arg tx_hash_hex "$fixture_hash" \
    '{
      transaction: {
        tx_hash: $tx_hash,
        tx_hash_hex: $tx_hash_hex
      },
      terminal: {
        source: "pipeline",
        status: {status: {kind: "Applied"}},
        queried_tx_hash_hex: $tx_hash_hex
      }
    }'
}

fixture_contract_receipt() {
  local fixture_index="$1"
  local fixture_contract="$2"
  local fixture_entrypoint="$3"
  local fixture_arguments="$4"
  local transaction_json

  transaction_json="$(fixture_transaction_json "$fixture_index")"
  jq -cn \
    --arg contract_address "$fixture_contract" \
    --arg entrypoint "$fixture_entrypoint" \
    --argjson arguments "$fixture_arguments" \
    --argjson transaction "$(jq -c '.transaction' <<<"$transaction_json")" \
    --argjson terminal "$(jq -c '.terminal' <<<"$transaction_json")" \
    '{
      contract_address: $contract_address,
      entrypoint: $entrypoint,
      arguments: $arguments,
      transaction: $transaction,
      terminal: $terminal
    }'
}

fixture_permission_receipt() {
  local fixture_index="$1"
  local fixture_holder="$2"
  local fixture_permission="$3"
  local transaction_json

  transaction_json="$(fixture_transaction_json "$fixture_index")"
  jq -cn \
    --arg account_id "$fixture_holder" \
    --argjson permission "$fixture_permission" \
    --argjson transaction "$(jq -c '.transaction' <<<"$transaction_json")" \
    --argjson terminal "$(jq -c '.terminal' <<<"$transaction_json")" \
    '{
      account_id: $account_id,
      permission: $permission,
      transaction: $transaction,
      terminal: $terminal
    }'
}

fixture_pool_contract='tairac1pool'
fixture_payout_contract='tairac1payout'
fixture_pool_subject='testpool'
fixture_payout_subject='testpayout'
fixture_operator='testoperator'
fixture_permissions="$(jq -cn \
  --arg operator "$fixture_operator" \
  --arg pool_subject "$fixture_pool_subject" \
  --arg pool_contract "$fixture_pool_contract" \
  '[
    {
      holder: $operator,
      permission: {
        name: "CanInvokeContractEntrypoint",
        payload: {contract: $pool_contract, entrypoint: "hajimari"}
      },
      present: false
    },
    {
      holder: $operator,
      permission: {
        name: "CanInvokeContractEntrypoint",
        payload: {contract: $pool_contract, entrypoint: "seed_bin"}
      },
      present: false
    },
    {
      holder: $operator,
      permission: {
        name: "CanInvokeContractEntrypoint",
        payload: {contract: $pool_contract, entrypoint: "renounce_admin"}
      },
      present: false
    },
    {
      holder: $pool_subject,
      permission: {
        name: "CanTransferAsset",
        payload: {asset: "xor#operator#dataspace:0"}
      },
      present: false
    },
    {
      holder: $pool_subject,
      permission: {
        name: "CanTransferAsset",
        payload: {asset: "sbd#operator#dataspace:0"}
      },
      present: false
    }
  ]')"
fixture_hajimari="$(
  fixture_contract_receipt 10 "$fixture_pool_contract" hajimari \
    '{"base_asset":"xor","quote_asset":"sbd"}'
)"
fixture_seed_receipts='[]'
for fixture_seed_index in 0 1 2; do
  fixture_seed_receipt="$(
    fixture_contract_receipt \
      "$(( 11 + fixture_seed_index ))" \
      "$fixture_pool_contract" \
      seed_bin \
      "$(jq -cn \
        --arg position_id "validation_fee_seed_bin_$fixture_seed_index" \
        --argjson bin_id "$fixture_seed_index" \
        '{
          position_id: $position_id,
          bin_id: $bin_id,
          base_amount: 1000,
          quote_amount: 1000
        }')"
  )"
  fixture_seed_receipts="$(jq -c \
    --argjson receipt "$fixture_seed_receipt" \
    '. + [$receipt]' <<<"$fixture_seed_receipts")"
done
fixture_renounce="$(
  fixture_contract_receipt 14 "$fixture_pool_contract" renounce_admin '{}'
)"
fixture_grants='[]'
fixture_revokes='[]'
fixture_permission_index=0
while IFS= read -r fixture_permission_spec; do
  fixture_grant="$(
    fixture_permission_receipt \
      "$(( 20 + fixture_permission_index ))" \
      "$(jq -r '.holder' <<<"$fixture_permission_spec")" \
      "$(jq -c '.permission' <<<"$fixture_permission_spec")"
  )"
  fixture_revoke="$(
    fixture_permission_receipt \
      "$(( 30 + fixture_permission_index ))" \
      "$(jq -r '.holder' <<<"$fixture_permission_spec")" \
      "$(jq -c '.permission' <<<"$fixture_permission_spec")"
  )"
  fixture_grants="$(jq -c \
    --argjson receipt "$fixture_grant" '. + [$receipt]' <<<"$fixture_grants")"
  fixture_revokes="$(jq -c \
    --argjson receipt "$fixture_revoke" '. + [$receipt]' <<<"$fixture_revokes")"
  fixture_permission_index=$(( fixture_permission_index + 1 ))
done < <(jq -c '.[]' <<<"$fixture_permissions")
# Simulate an interrupted attempt that revoked seed_bin, then a resumed attempt
# that granted and revoked the same exact selector once more.
fixture_retry_permission="$(jq -c '.[1]' <<<"$fixture_permissions")"
fixture_retry_grant="$(
  fixture_permission_receipt \
    40 \
    "$(jq -r '.holder' <<<"$fixture_retry_permission")" \
    "$(jq -c '.permission' <<<"$fixture_retry_permission")"
)"
fixture_retry_revoke="$(
  fixture_permission_receipt \
    41 \
    "$(jq -r '.holder' <<<"$fixture_retry_permission")" \
    "$(jq -c '.permission' <<<"$fixture_retry_permission")"
)"
fixture_grants="$(jq -c \
  --argjson receipt "$fixture_retry_grant" '. + [$receipt]' <<<"$fixture_grants")"
fixture_revokes="$(jq -c \
  --argjson receipt "$fixture_retry_revoke" '. + [$receipt]' <<<"$fixture_revokes")"
fixture_bootstrap_evidence="$(jq -cn \
  --arg pool_contract "$fixture_pool_contract" \
  --arg payout_contract "$fixture_payout_contract" \
  --arg pool_subject "$fixture_pool_subject" \
  --arg payout_subject "$fixture_payout_subject" \
  --argjson permissions "$fixture_permissions" \
  --argjson hajimari "$fixture_hajimari" \
  --argjson seeds "$fixture_seed_receipts" \
  --argjson renounce "$fixture_renounce" \
  --argjson grants "$fixture_grants" \
  --argjson revokes "$fixture_revokes" \
  --arg journal_hash "$hash_1" \
  '{
    status: "completed",
    plan: {
      chain_id: "fc56984b-2be7-431d-840e-21514d1883f0",
      chain_discriminant: 369,
      pool: {
        contract_address: $pool_contract,
        subject_account_id: $pool_subject
      },
      payout_contract_address: $payout_contract,
      payout_subject_account_id: $payout_subject,
      operations: [
        {entrypoint: "hajimari"},
        {entrypoint: "seed_bin"},
        {entrypoint: "seed_bin"},
        {entrypoint: "seed_bin"},
        {entrypoint: "renounce_admin"}
      ]
    },
    bootstrap_work_journal: {
      binding_sha256: $journal_hash,
      terminal_event_sha256: $journal_hash,
      event_count: (
        5 + ($grants | length) + ($revokes | length)
      ),
      append_only: true,
      complete: true
    },
    contract_transaction_evidence: {
      hajimari: $hajimari,
      seed_bins: $seeds,
      renounce_admin: $renounce
    },
    contract_transactions: {
      hajimari: $hajimari.transaction.tx_hash_hex,
      seed_bins: ($seeds | map(.transaction.tx_hash_hex)),
      renounce_admin: $renounce.transaction.tx_hash_hex
    },
    permission_grants: $grants,
    permission_revokes: $revokes,
    temporary_permissions_revoked: true,
    temporary_permission_topology: {
      before: $permissions,
      after: $permissions
    },
    protected_permission_topology: {
      before: {absent: true},
      after: {absent: true}
    }
  }')"
validation_fee_assert_pool_bootstrap_evidence \
  "/offline/not-used.toml" \
  "$fixture_bootstrap_evidence" \
  "$fixture_pool_contract" \
  "$fixture_payout_contract" \
  "$fixture_pool_subject" \
  "$fixture_payout_subject"
if validation_fee_assert_pool_bootstrap_evidence \
  "/offline/not-used.toml" \
  "$(jq '
    .permission_revokes[5].transaction
      = .permission_grants[5].transaction
    | .permission_revokes[5].terminal.queried_tx_hash_hex
      = .permission_grants[5].transaction.tx_hash_hex
  ' <<<"$fixture_bootstrap_evidence")" \
  "$fixture_pool_contract" \
  "$fixture_payout_contract" \
  "$fixture_pool_subject" \
  "$fixture_payout_subject" >/dev/null 2>&1; then
  echo "bootstrap resume evidence accepted a reused transaction hash" >&2
  exit 1
fi

manifest_json="$(jq -cn \
  --argjson contract "$contract_json" \
  '{manifest: {
    code_hash_hex: $contract.code_hash,
    abi_hash_hex: $contract.abi_hash
  }}')"
validation_fee_assert_manifest_hashes "$manifest_json" "$contract_json"
if validation_fee_assert_manifest_hashes \
  "$(jq '.manifest.abi_hash_hex = ("0" * 64)' <<<"$manifest_json")" \
  "$contract_json" >/dev/null 2>&1; then
  echo "wrong validation-fee ABI hash was accepted" >&2
  exit 1
fi

alias_json="$(jq -cn \
  --argjson contract "$contract_json" \
  '{contract_address: $contract.contract_address, dataspace: "universal"}')"
validation_fee_assert_alias_resolution \
  "$alias_json" "$contract_json" universal
if validation_fee_assert_alias_resolution \
  "$(jq '.contract_address = "wrong"' <<<"$alias_json")" \
  "$contract_json" universal >/dev/null 2>&1; then
  echo "wrong validation-fee alias target was accepted" >&2
  exit 1
fi

absent_topology='{
  "direct": [
    {"present": false},
    {"present": false},
    {"present": false}
  ],
  "role_permission_matches": [],
  "subject_roles": [
    {"account_id": "pool", "roles": []},
    {"account_id": "payout", "roles": []}
  ],
  "subject_direct_permissions": [
    {"account_id": "pool", "permissions": []},
    {"account_id": "payout", "permissions": []}
  ],
  "direct_absent": true,
  "role_permissions_absent": true,
  "subject_permissions_absent": true,
  "subject_roles_absent": true,
  "absent": true
}'
validation_fee_assert_protected_permission_topology_absent "$absent_topology"
if validation_fee_assert_protected_permission_topology_absent \
  "$(jq '.direct[1].present = true | .direct_absent = false | .absent = false' \
    <<<"$absent_topology")" >/dev/null 2>&1; then
  echo "direct protected validation-fee permission was accepted" >&2
  exit 1
fi
if validation_fee_assert_protected_permission_topology_absent \
  "$(jq \
    '.role_permission_matches = [{"role_id":"forbidden","permission":{}}]
     | .role_permissions_absent = false
     | .absent = false' <<<"$absent_topology")" >/dev/null 2>&1; then
  echo "role-carried protected validation-fee permission was accepted" >&2
  exit 1
fi
if validation_fee_assert_protected_permission_topology_absent \
  "$(jq \
    '.subject_direct_permissions[0].permissions = [{
      "name":"CanTransferAssetWithDefinition",
      "payload":{"asset_definition":"7ZepsJTHCVLKsrFFNZGSRGZgvBhv"}
    }]
    | .subject_permissions_absent = false
    | .absent = false' <<<"$absent_topology")" >/dev/null 2>&1; then
  echo "broader direct validation-fee permission was accepted" >&2
  exit 1
fi
if validation_fee_assert_protected_permission_topology_absent \
  "$(jq \
    '.subject_roles[0].roles = ["broad-transfer-role"]
    | .subject_roles_absent = false
    | .absent = false' <<<"$absent_topology")" >/dev/null 2>&1; then
  echo "validation-fee subject role was accepted" >&2
  exit 1
fi

immutable_path="$TMP_DIR/immutable.json"
validation_fee_write_immutable_json '{"b":2,"a":1}' "$immutable_path" \
  >/dev/null
validation_fee_write_immutable_json '{"a":1,"b":2}' "$immutable_path" \
  >/dev/null
[[ "$(stat -f '%Lp' "$immutable_path" 2>/dev/null \
  || stat -c '%a' "$immutable_path")" == "444" ]]
if validation_fee_write_immutable_json '{"a":2,"b":2}' "$immutable_path" \
  >/dev/null 2>&1; then
  echo "immutable validation-fee evidence was replaced" >&2
  exit 1
fi
jq -e '.a == 1 and .b == 2' "$immutable_path" >/dev/null

journal="$TMP_DIR/journal"
mkdir "$journal"
validation_fee_check_journal_shape "$journal"
printf '{}\n' >"$journal/00.plan.json"
printf '{}\n' >"$journal/02.pool-subject-registration.json"
if validation_fee_check_journal_shape "$journal" >/dev/null 2>&1; then
  echo "validation-fee journal phase gap was accepted" >&2
  exit 1
fi
rm "$journal/02.pool-subject-registration.json"
printf '{}\n' >"$journal/.unexpected"
if validation_fee_check_journal_shape "$journal" >/dev/null 2>&1; then
  echo "unexpected hidden validation-fee journal file was accepted" >&2
  exit 1
fi

echo "validation-fee deployment evidence smoke ok"
