#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
TMP_DIR="${TMP_DIR:A}"
cleanup_tmp_dir() {
  chmod -R u+w "$TMP_DIR" 2>/dev/null || true
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp_dir EXIT

export SORASWAP_VALIDATION_FEE_LIBRARY_ONLY=1
source "$ROOT/scripts/apply_validation_fee_deployment.sh"

validation_fee_taira_p1_invocation_journal_dir() {
  printf '%s/invocations\n' "$TMP_DIR"
}
export SORASWAP_VALIDATION_FEE_ONE_WRITE_PER_INVOCATION=1
export SORASWAP_VALIDATION_FEE_INVOCATION_ID=offline-one-write
export SORASWAP_VALIDATION_FEE_INVOCATION_JOURNAL_DIR="$TMP_DIR/invocations"
export SORASWAP_VALIDATION_FEE_EXPECTED_BLOCK_1_HASH="$(printf '1%.0s' {1..64})"
fixture_plan="$(jq -cn \
  --arg genesis_sha256 "$(printf '2%.0s' {1..64})" \
  --arg deployment_spec_sha256 "$(printf '3%.0s' {1..64})" \
  '{
    schema_version: 1,
    status: "undeployed_plan",
    network: "taira",
    chain_id: "fc56984b-2be7-431d-840e-21514d1883f0",
    chain_discriminant: 369,
    genesis_sha256: $genesis_sha256,
    authority_account_id:
      "testuﾛ1PｵEmｷjMZZﾑﾙeｱﾁﾎﾅﾂﾊmECepdbﾎｳ2uWﾃｸﾊﾘvｵi2ｦP1Y18A",
    dataspace: "universal",
    deployment_spec_sha256: $deployment_spec_sha256,
    required_starting_deploy_nonce: 0,
    required_final_deploy_nonce: 2,
    sequence: [],
    contracts: [],
    payout_binding: {},
    protected_permissions: [],
    preconditions: {},
    prohibited_actions: {
      protected_permission_grants: true,
      role_grants: true,
      parliament_activation: true,
      validation_fee_lifecycle_activation: true
    },
    toolchain: {}
  }')"
fixture_plan_sha256="$(
  printf '%s' "$(jq -cS . <<<"$fixture_plan")" \
    | shasum -a 256 | awk '{print $1}'
)"
fixture_plan_evidence="$TMP_DIR/00.plan.json"
validation_fee_write_immutable_json \
  "$(jq -cn \
    --arg plan_sha256 "$fixture_plan_sha256" \
    --argjson plan "$fixture_plan" \
    --arg write_gate_command_sha256 "$(printf '4%.0s' {1..64})" \
    --arg state_binding_sha256 "$(printf '5%.0s' {1..64})" \
    --arg block_1_hash "$SORASWAP_VALIDATION_FEE_EXPECTED_BLOCK_1_HASH" \
    '{
      schema_version: 1,
      phase: "plan",
      plan_sha256: $plan_sha256,
      payload: {
        result: {plan: $plan, plan_sha256: $plan_sha256},
        write_gate_command_sha256: $write_gate_command_sha256,
        state_binding_sha256: $state_binding_sha256,
        block_1_hash: $block_1_hash
      }
    }')" \
  "$fixture_plan_evidence" >/dev/null
export SORASWAP_VALIDATION_FEE_DEPLOYMENT_PLAN_EVIDENCE_PATH="$fixture_plan_evidence"
export SORASWAP_VALIDATION_FEE_REVIEWED_PLAN_SHA256="$fixture_plan_sha256"
validation_fee_require_one_write_mode

(
  transport_marker="$TMP_DIR/forbidden-contract-transport"
  validation_fee_write_gate_json() {
    print -r -- called >"$transport_marker"
    return 41
  }
  exact_pool_contract='tairac1qyqqqqqqqqqqqqymmv4lktrp3r7xyq3jmzk89sy7hyvzdwssatnvg'
  exact_pool_subject='testuﾛ1PcﾀkｼﾉpﾔﾖｸPUCヰrｻjSUzﾕhZGSAｳJﾐｹﾜrﾄﾗﾓｿxS8QRALXF'
  exact_hajimari_arguments="$(jq -cn \
    --arg base_asset 6TEAJqbb8oEPmLncoNiMRbLEK6tw \
    --arg quote_asset 7ZepsJTHCVLKsrFFNZGSRGZgvBhv \
    --arg vault_account "$exact_pool_subject" \
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
  alternate_contract_operation="$(jq -cn \
    --arg plan_sha256 "$fixture_plan_sha256" \
    --arg contract_address tairac1alternatevalidtarget \
    --argjson arguments "$exact_hajimari_arguments" \
    '{
      kind: "contract_call",
      plan_sha256: $plan_sha256,
      contract_address: $contract_address,
      entrypoint: "hajimari",
      arguments: $arguments
    }')"
  alternate_subject_operation="$(jq -cn \
    --arg plan_sha256 "$fixture_plan_sha256" \
    --arg contract_address "$exact_pool_contract" \
    --argjson arguments "$(
      jq -c '.vault_account = "testalternatevalidpoolsubject"' \
        <<<"$exact_hajimari_arguments"
    )" \
    '{
      kind: "contract_call",
      plan_sha256: $plan_sha256,
      contract_address: $contract_address,
      entrypoint: "hajimari",
      arguments: $arguments
    }')"
  for forbidden_operation in \
    "$alternate_contract_operation" \
    "$alternate_subject_operation"; do
    rm -f "$transport_marker"
    SORASWAP_VALIDATION_FEE_IMMINENT_OPERATION_JSON="$forbidden_operation" \
    SORASWAP_VALIDATION_FEE_IMMINENT_JOURNAL_PREFIX="$TMP_DIR/forbidden-contract" \
      validation_fee_contract_call_immediate_gate >/dev/null 2>&1 || true
    [[ ! -e "$transport_marker" ]] || {
      echo "alternate valid pool selector reached the write-gate transport" >&2
      exit 1
    }
  done
)

operation_json="$(jq -cn \
  --arg plan_sha256 "$fixture_plan_sha256" \
  '{
    kind: "account_registration",
    plan_sha256: $plan_sha256,
    account_id: "test-offline-subject",
    purpose: "pool_contract_subject",
    payload_sha256:
      "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    payload_size_bytes: 1024,
    transaction: {
      tx_hash:
        "hash:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA#ABCD",
      tx_hash_hex:
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    }
  }')"
duplicate_operation_json="${operation_json/\"purpose\":\"pool_contract_subject\"/\"purpose\":\"pool_contract_subject\",\"purpose\":\"pool_contract_subject\"}"
if validation_fee_validate_imminent_operation_json \
  "$duplicate_operation_json" >/dev/null 2>&1; then
  echo "shell imminent-operation boundary collapsed a duplicate JSON key" >&2
  exit 1
fi
journal_prefix="$TMP_DIR/mutations/0001.account-registration"
validation_fee_start_mutation_intent "$journal_prefix" "$operation_json"

gate_path="$SORASWAP_VALIDATION_FEE_INVOCATION_JOURNAL_DIR/$SORASWAP_VALIDATION_FEE_INVOCATION_ID.gate.json"
VALIDATION_FEE_TEST_ROOT="$ROOT" \
VALIDATION_FEE_TEST_GATE="$gate_path" \
VALIDATION_FEE_TEST_OPERATION="$operation_json" \
  python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

root = Path(os.environ["VALIDATION_FEE_TEST_ROOT"])
sys.path.insert(0, str(root / "tests"))
from test_validate_validation_fee_write_gate import gate_marker, gate_request

request = gate_request()
request["invocation_id"] = "offline-one-write"
request["operation"] = json.loads(os.environ["VALIDATION_FEE_TEST_OPERATION"])
request["plan_sha256"] = request["operation"]["plan_sha256"]
marker = gate_marker(request)
Path(os.environ["VALIDATION_FEE_TEST_GATE"]).write_text(
    json.dumps(marker, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY
chmod 0444 "$gate_path"

tx_hash_hex="$(printf 'a%.0s' {1..64})"
transaction="$(jq -cn \
  --arg tx_hash "hash:${tx_hash_hex:u}#ABCD" \
  --arg tx_hash_hex "$tx_hash_hex" \
  '{tx_hash: $tx_hash, tx_hash_hex: $tx_hash_hex}')"
terminal="$(jq -cn \
  --arg tx_hash_hex "$tx_hash_hex" \
  '{
    source: "pipeline",
    status: {status: {kind: "Applied"}},
    queried_tx_hash_hex: $tx_hash_hex
  }')"
receipt="$(jq -cn \
  --arg account_id test-offline-subject \
  --arg purpose pool_contract_subject \
  --argjson transaction "$transaction" \
  --argjson terminal "$terminal" \
  '{
    account_id: $account_id,
    purpose: $purpose,
    preexisting: false,
    transaction: $transaction,
    terminal: $terminal
  }')"
if validation_fee_record_mutation_submission \
  "$journal_prefix" \
  "$(jq -cn \
    --arg tx_hash_hex "$(printf 'f%.0s' {1..64})" \
    '{
      tx_hash: $tx_hash_hex,
      tx_hash_hex: $tx_hash_hex
    }')" >/dev/null 2>&1; then
  echo "submission journal accepted a transaction other than the prepared operation" >&2
  exit 1
fi
validation_fee_record_mutation_submission "$journal_prefix" "$transaction"
validation_fee_record_mutation_applied \
  "$journal_prefix" "$receipt" "$operation_json"
validation_fee_assert_mutation_journal "$journal_prefix" "$operation_json"

export SORASWAP_VALIDATION_FEE_INVOCATION_ID=offline-contract-accepted
accepted_operation="$(jq -cn \
  --arg plan_sha256 "$fixture_plan_sha256" \
  '{
    kind: "contract_call",
    plan_sha256: $plan_sha256,
    contract_address:
      "tairac1qyqqqqqqqqqqqqymmv4lktrp3r7xyq3jmzk89sy7hyvzdwssatnvg",
    entrypoint: "seed_bin",
    arguments: {
      position_id: "validation_fee_seed_bin_0",
      bin_id: 0,
      base_amount: 1000,
      quote_amount: 1000
    }
  }')"
accepted_prefix="$TMP_DIR/mutations/0002.contract-accepted"
accepted_gate_path="$SORASWAP_VALIDATION_FEE_INVOCATION_JOURNAL_DIR/$SORASWAP_VALIDATION_FEE_INVOCATION_ID.gate.json"
VALIDATION_FEE_TEST_ROOT="$ROOT" \
VALIDATION_FEE_TEST_GATE="$accepted_gate_path" \
VALIDATION_FEE_TEST_OPERATION="$accepted_operation" \
  python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

root = Path(os.environ["VALIDATION_FEE_TEST_ROOT"])
sys.path.insert(0, str(root / "tests"))
from test_validate_validation_fee_write_gate import gate_marker, gate_request

request = gate_request()
request["invocation_id"] = "offline-contract-accepted"
request["operation"] = json.loads(os.environ["VALIDATION_FEE_TEST_OPERATION"])
request["plan_sha256"] = request["operation"]["plan_sha256"]
marker = gate_marker(request)
Path(os.environ["VALIDATION_FEE_TEST_GATE"]).write_text(
    json.dumps(marker, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY
chmod 0444 "$accepted_gate_path"
validation_fee_start_mutation_intent \
  "$accepted_prefix" "$accepted_operation"
accepted_tx_hash="$(printf 'b%.0s' {1..64})"
SORASWAP_VALIDATION_FEE_IMMINENT_OPERATION_JSON="$accepted_operation" \
SORASWAP_VALIDATION_FEE_IMMINENT_JOURNAL_PREFIX="$accepted_prefix" \
  soraswap_invoke_accepted_submission_callback \
    validation_fee_contract_call_accepted_submission \
    "" \
    "offline accepted contract call" \
    "$accepted_tx_hash"
[[ "$(validation_fee_mutation_journal_state "$accepted_prefix")" \
  == "submission" ]] || {
  echo "accepted contract call was not durably journaled before polling" >&2
  exit 1
}
[[ "$(jq -er '.transaction.tx_hash_hex' \
  "$accepted_prefix.submission.json")" == "$accepted_tx_hash" ]]
[[ ! -e "$accepted_prefix.Applied.json" ]]

export SORASWAP_VALIDATION_FEE_INVOCATION_ID=offline-invocation-bound
bound_operation="$(jq -cn \
  --arg plan_sha256 "$fixture_plan_sha256" \
  '{
    kind: "account_registration",
    plan_sha256: $plan_sha256,
    account_id: "testboundsubject",
    purpose: "payout_contract_subject",
    payload_sha256:
      "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    payload_size_bytes: 2048,
    transaction: {
      tx_hash:
        "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
      tx_hash_hex:
        "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    }
  }')"
bound_prefix="$TMP_DIR/mutations/0003.invocation-bound"
validation_fee_start_mutation_intent "$bound_prefix" "$bound_operation"
export SORASWAP_VALIDATION_FEE_INVOCATION_ID=offline-invocation-changed
if validation_fee_record_mutation_submission \
  "$bound_prefix" "$transaction" >/dev/null 2>&1; then
  echo "submission journal accepted an invocation different from its intent" >&2
  exit 1
fi

export SORASWAP_VALIDATION_FEE_INVOCATION_ID=offline-invocation-bound
if validation_fee_start_mutation_intent \
  "$TMP_DIR/mutations/0004.forbidden" \
  '{"kind":"forbidden_second_write"}' >/dev/null 2>&1; then
  echo "one-write invocation reserved a second mutation" >&2
  exit 1
fi
pause_json="$(
  validation_fee_pause_result_json \
    account_registration "$journal_prefix.Applied.json"
)"
jq -e '
  .status == "paused_after_applied_write"
  and .submitted_mutations_this_invocation == 1
  and .resume_required == true
' >/dev/null <<<"$pause_json"

chmod 0644 "$gate_path"
if validation_fee_assert_mutation_journal \
  "$journal_prefix" "$operation_json" >/dev/null 2>&1; then
  echo "mutable write-gate evidence was accepted" >&2
  exit 1
fi
chmod 0444 "$gate_path"

export SORASWAP_VALIDATION_FEE_INVOCATION_ID=offline-ambiguous-intent
ambiguous_prefix="$TMP_DIR/mutations/0005.ambiguous"
validation_fee_start_mutation_intent \
  "$ambiguous_prefix" '{"kind":"ambiguous_fixture"}'
if validation_fee_fail_on_ambiguous_mutation \
  "$ambiguous_prefix" '{"kind":"ambiguous_fixture"}' >/dev/null 2>&1; then
  echo "intent-only mutation journal was treated as resumable" >&2
  exit 1
fi

spec_json="$(jq -c . "$ROOT/config/validation_fee/deployment.taira.p1.json")"
contract_json="$(jq -c '.contracts[0]' <<<"$spec_json")"
split_hashes='[]'
for hash_digit in 1 2 3 4; do
  split_hashes="$(jq -c \
    --arg hash "$(printf "$hash_digit%.0s" {1..64})" \
    '. + [$hash]' <<<"$split_hashes")"
done
split_receipt="$(jq -cn \
  --argjson spec "$spec_json" \
  --argjson contract "$contract_json" \
  --argjson hashes "$split_hashes" \
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
    register_bytes_stage_tx_hashes: [
      ("hash:" + ($hashes[0] | ascii_upcase) + "#ABCD")
    ],
    register_bytes_tx_hash:
      ("hash:" + ($hashes[1] | ascii_upcase) + "#ABCD"),
    register_manifest_tx_hash:
      ("hash:" + ($hashes[2] | ascii_upcase) + "#ABCD"),
    commit_tx_hash:
      ("hash:" + ($hashes[3] | ascii_upcase) + "#ABCD")
  }')"
prepared_dir="$TMP_DIR/prepared"
mkdir -p "$prepared_dir/transactions"
prepared_transactions='[]'
labels=(
  register_bytes_stage_0
  register_bytes_finalize
  register_manifest
  commit
)
emitted_names=(
  register_bytes_chunk_0001_of_0002
  register_bytes_finalize
  register_manifest
  commit
)
for index in {1..4}; do
  label="${labels[$index]}"
  emitted_name="${emitted_names[$index]}"
  printf -v payload_file '%04d.%s.norito' "$index" "$label"
  printf 'offline prepared payload %s\n' "$index" \
    >"$prepared_dir/transactions/$payload_file"
  chmod 0444 "$prepared_dir/transactions/$payload_file"
  payload_sha="$(
    shasum -a 256 "$prepared_dir/transactions/$payload_file" | awk '{print $1}'
  )"
  payload_size="$(
    wc -c <"$prepared_dir/transactions/$payload_file" | tr -d '[:space:]'
  )"
  hash_hex="$(jq -er --argjson index "$(( index - 1 ))" '.[$index]' \
    <<<"$split_hashes")"
  prepared_transactions="$(jq -c \
    --argjson sequence "$index" \
    --arg label "$label" \
    --arg emitted_name "$emitted_name" \
    --argjson emitted_size "$payload_size" \
    --arg file "$payload_file" \
    --arg payload_sha256 "$payload_sha" \
    --arg tx_hash "hash:${hash_hex:u}#ABCD" \
    --arg tx_hash_hex "$hash_hex" \
    '. + [{
      sequence: $sequence,
      label: $label,
      emitted_name: $emitted_name,
      emitted_size: $emitted_size,
      file: $file,
      payload_sha256: $payload_sha256,
      transaction: {
        tx_hash: $tx_hash,
        tx_hash_hex: $tx_hash_hex
      }
    }]' <<<"$prepared_transactions")"
done
prepared_json="$(jq -cn \
  --arg contract_key "$(jq -er '.key' <<<"$contract_json")" \
  --argjson split_receipt "$split_receipt" \
  --argjson transactions "$prepared_transactions" \
  '{
    schema_version: 1,
    phase: "prepared_split_deploy",
    contract_key: $contract_key,
    split_receipt: $split_receipt,
    transactions: $transactions
  }')"
validation_fee_write_immutable_json \
  "$prepared_json" "$prepared_dir/plan.json" >/dev/null
chmod 0555 "$prepared_dir" "$prepared_dir/transactions"
validation_fee_validate_prepared_split_deploy_json \
  "$prepared_json" "$prepared_dir" "$spec_json" "$contract_json"
duplicate_split_receipt="$(jq -c \
  '.register_bytes_tx_hash = .register_manifest_tx_hash' \
  <<<"$split_receipt")"
if validation_fee_validate_split_deploy_receipt_json \
  "$duplicate_split_receipt" "$spec_json" "$contract_json" \
  >/dev/null 2>&1; then
  echo "split receipt accepted one transaction hash for two deploy stages" >&2
  exit 1
fi
chmod 0755 "$prepared_dir/transactions"
printf 'unexpected\n' >"$prepared_dir/transactions/unexpected.norito"
chmod 0444 "$prepared_dir/transactions/unexpected.norito"
chmod 0555 "$prepared_dir/transactions"
if validation_fee_validate_prepared_split_deploy_json \
  "$prepared_json" "$prepared_dir" "$spec_json" "$contract_json" \
  >/dev/null 2>&1; then
  echo "prepared split validator accepted an extra transaction payload" >&2
  exit 1
fi
chmod 0755 "$prepared_dir/transactions"
rm "$prepared_dir/transactions/unexpected.norito"
chmod 0555 "$prepared_dir/transactions"

rg -Fq -- '--emit-only' "$ROOT/scripts/validation_fee_evidence.sh"
rg -Fq '/v1/pipeline/transactions' \
  "$ROOT/scripts/validation_fee_evidence.sh"
rg -Fq 'SORASWAP_CONTRACT_CALL_RETRY_COUNT=1' \
  "$ROOT/scripts/validation_fee_evidence.sh"
rg -Fq 'SORASWAP_CONTRACT_CALL_INVISIBLE_RETRY_COUNT=0' \
  "$ROOT/scripts/validation_fee_evidence.sh"
if rg -Fq 'SORASWAP_IMMEDIATE_LEDGER_SUBMIT_GATE_FUNCTION=validation_fee_ledger_immediate_gate' \
  "$ROOT/scripts/validation_fee_evidence.sh"; then
  echo "typed validation-fee writes still route through the generic Iroha CLI" >&2
  exit 1
fi
rg -Fq 'validation_fee_prepared_ledger_transaction_immediate_gate' \
  "$ROOT/scripts/validation_fee_evidence.sh"
rg -Fq 'SORASWAP_VALIDATION_FEE_LEDGER_ADAPTER_BIN' \
  "$ROOT/scripts/validation_fee_evidence.sh"
rg -Fq 'SORASWAP_VALIDATION_FEE_LEDGER_ADAPTER_SOURCE_SHA256' \
  "$ROOT/scripts/validation_fee_evidence.sh"
[[ "$(
  rg -Fc \
    'validation_fee_assert_prepared_ledger_operation_json' \
    "$ROOT/scripts/validation_fee_evidence.sh"
)" -ge 4 ]] || {
  echo "prepared ledger package is not rebound at prepare, submit, and immediate-gate boundaries" >&2
  exit 1
}
rg -Fq 'SORASWAP_VALIDATION_FEE_IMMINENT_PREPARED_DIR="$prepared_dir"' \
  "$ROOT/scripts/validation_fee_evidence.sh"
rg -Fq 'SORASWAP_VALIDATION_FEE_IMMINENT_PAYLOAD_FD="$payload_fd"' \
  "$ROOT/scripts/validation_fee_evidence.sh"
rg -Fq -- '--data-binary @-' \
  "$ROOT/scripts/validation_fee_evidence.sh"
rg -Fq 'SORASWAP_IMMEDIATE_CURL_GATE_FUNCTION=validation_fee_prepared_transaction_immediate_gate' \
  "$ROOT/scripts/validation_fee_evidence.sh"
rg -Fq 'SORASWAP_IMMEDIATE_CURL_GATE_FUNCTION="${SORASWAP_IMMEDIATE_SUBMIT_GATE_FUNCTION:-}"' \
  "$ROOT/scripts/common.sh"

(
  fake_adapter="$TMP_DIR/fake-ledger-adapter"
  original_payload="$TMP_DIR/open-payload.norito"
  printf '%s\n' \
    '#!/bin/zsh' \
    'payload="$(command cat)"' \
    'digest="$(print -rn -- "$payload" | shasum -a 256 | awk '"'"'{print $1}'"'"')"' \
    'jq -cn --arg digest "$digest" '"'"'{payload_sha256: $digest}'"'" \
    >"$fake_adapter"
  chmod 0700 "$fake_adapter"
  print -rn -- 'original-frozen-payload' >"$original_payload"
  exec {fixture_payload_fd}< "$original_payload"
  mv "$original_payload" "$original_payload.opened"
  print -rn -- 'substituted-path-payload' >"$original_payload"
  validation_fee_reviewed_ledger_adapter_sha256() {
    printf '%s\n' "$(printf 'a%.0s' {1..64})"
  }
  validation_fee_reviewed_ledger_adapter_source_sha256() {
    printf '%s\n' "$(printf 'b%.0s' {1..64})"
  }
  export SORASWAP_VALIDATION_FEE_LEDGER_ADAPTER_BIN="$fake_adapter"
  verified_fd_manifest="$(
    validation_fee_verify_prepared_ledger_manifest_fd \
      "$fixture_payload_fd" '{}'
  )"
  expected_open_digest="$(
    print -rn -- 'original-frozen-payload' | shasum -a 256 | awk '{print $1}'
  )"
  [[ "$(jq -er '.payload_sha256' <<<"$verified_fd_manifest")" \
    == "$expected_open_digest" ]] || {
    echo "native ledger verification reopened a substituted payload pathname" >&2
    exit 1
  }
  [[ "$(command cat <&$fixture_payload_fd)" == 'original-frozen-payload' ]] || {
    echo "verified payload descriptor was not rewound for the immediate POST" >&2
    exit 1
  }
  exec {fixture_payload_fd}<&-
)

export VALIDATION_FEE_TEST_CURL_ORDER="$TMP_DIR/curl-order"
fake_curl="$TMP_DIR/fake-curl"
printf '%s\n' \
  '#!/bin/zsh' \
  'printf "curl\\n" >>"$VALIDATION_FEE_TEST_CURL_ORDER"' \
  'printf 204' >"$fake_curl"
chmod 0700 "$fake_curl"
validation_fee_test_curl_gate() {
  printf 'gate\n' >>"$VALIDATION_FEE_TEST_CURL_ORDER"
}
curl_result="$(
  SORASWAP_CURL_BIN="$fake_curl" \
  SORASWAP_IMMEDIATE_CURL_GATE_FUNCTION=validation_fee_test_curl_gate \
    soraswap_curl_for_config "" https://offline.invalid/submit
)"
[[ "$curl_result" == "204" ]]
[[ "$(cat "$VALIDATION_FEE_TEST_CURL_ORDER")" == $'gate\ncurl' ]] || {
  echo "immediate curl gate did not run directly before the external command" >&2
  exit 1
}
printf '' >"$VALIDATION_FEE_TEST_CURL_ORDER"
validation_fee_test_curl_refusal() {
  printf 'gate-refused\n' >>"$VALIDATION_FEE_TEST_CURL_ORDER"
  return 42
}
if SORASWAP_CURL_BIN="$fake_curl" \
  SORASWAP_IMMEDIATE_CURL_GATE_FUNCTION=validation_fee_test_curl_refusal \
    soraswap_curl_for_config "" https://offline.invalid/submit \
      >/dev/null 2>&1; then
  echo "curl submission ran after its immediate gate refused" >&2
  exit 1
fi
[[ "$(cat "$VALIDATION_FEE_TEST_CURL_ORDER")" == "gate-refused" ]] || {
  echo "curl ran despite its immediate gate refusal" >&2
  exit 1
}

expired_gate_path="$TMP_DIR/expired.gate.json"
VALIDATION_FEE_TEST_ROOT="$ROOT" \
VALIDATION_FEE_TEST_GATE="$expired_gate_path" \
  python3 - <<'PY'
import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

root = Path(os.environ["VALIDATION_FEE_TEST_ROOT"])
sys.path.insert(0, str(root / "tests"))
from test_validate_validation_fee_write_gate import gate_marker, gate_request

created = datetime(2020, 1, 1, tzinfo=timezone.utc)
request = gate_request()
marker = gate_marker(
    request,
    created_at=created,
    expires_at=created + timedelta(seconds=30),
)
Path(os.environ["VALIDATION_FEE_TEST_GATE"]).write_text(
    json.dumps(marker, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY
chmod 0444 "$expired_gate_path"
printf '' >"$VALIDATION_FEE_TEST_CURL_ORDER"
validation_fee_test_expired_gate() {
  validation_fee_revalidate_current_write_gate "$expired_gate_path"
}
if SORASWAP_CURL_BIN="$fake_curl" \
  SORASWAP_IMMEDIATE_CURL_GATE_FUNCTION=validation_fee_test_expired_gate \
    soraswap_curl_for_config "" https://offline.invalid/submit \
      >/dev/null 2>&1; then
  echo "expired post-journal gate was accepted" >&2
  exit 1
fi
[[ ! -s "$VALIDATION_FEE_TEST_CURL_ORDER" ]] || {
  echo "curl ran after the post-journal gate expired" >&2
  exit 1
}

export SORASWAP_VALIDATION_FEE_INVOCATION_ID=offline-ledger-refused
export SORASWAP_VALIDATION_FEE_IMMINENT_OPERATION_JSON="$bound_operation"
export SORASWAP_VALIDATION_FEE_IMMINENT_JOURNAL_PREFIX="$TMP_DIR/mutations/ledger"
if validation_fee_ledger_immediate_gate >/dev/null 2>&1; then
  echo "unsafe pre-process-gated Iroha ledger mutation was admitted" >&2
  exit 1
fi
[[ ! -e "$SORASWAP_VALIDATION_FEE_IMMINENT_JOURNAL_PREFIX.intent.json" ]]

mkdir "$TMP_DIR/bound-evidence" "$TMP_DIR/bound-work" "$TMP_DIR/alternate-work"
export SORASWAP_VALIDATION_FEE_STATE_ROOT="$TMP_DIR/bound-state"
binding_producer_sha="$(printf 'd%.0s' {1..64})"
binding_sha="$(
  validation_fee_taira_p1_state_binding_sha256 \
    "$binding_producer_sha" 1 \
    "$TMP_DIR/bound-evidence" "$TMP_DIR/bound-work"
)"
[[ "$binding_sha" =~ '^[0-9a-f]{64}$' ]]
[[ "$(
  validation_fee_taira_p1_state_binding_sha256 \
    "$binding_producer_sha" 0 \
    "$TMP_DIR/bound-evidence" "$TMP_DIR/bound-work"
)" == "$binding_sha" ]]
validation_fee_check_journal_shape "$TMP_DIR/bound-evidence"
if validation_fee_taira_p1_state_binding_sha256 \
  "$binding_producer_sha" 0 \
  "$TMP_DIR/bound-evidence" "$TMP_DIR/alternate-work" \
  >/dev/null 2>&1; then
  echo "durable state binding admitted a different work root" >&2
  exit 1
fi
mv "$TMP_DIR/bound-work" "$TMP_DIR/bound-work.saved"
mkdir "$TMP_DIR/bound-work"
if validation_fee_taira_p1_state_binding_sha256 \
  "$binding_producer_sha" 0 \
  "$TMP_DIR/bound-evidence" "$TMP_DIR/bound-work" \
  >/dev/null 2>&1; then
  echo "durable state binding admitted a recreated empty work root" >&2
  exit 1
fi
rmdir "$TMP_DIR/bound-work"
mv "$TMP_DIR/bound-work.saved" "$TMP_DIR/bound-work"

mutable_producer="$TMP_DIR/operator-writable/gate"
mkdir -p "${mutable_producer:h}"
printf '#!/bin/zsh\nexit 1\n' >"$mutable_producer"
chmod 0555 "$mutable_producer"
mutable_producer_sha="$(shasum -a 256 "$mutable_producer" | awk '{print $1}')"
if validation_fee_reviewed_gate_producer_sha256 \
  "$mutable_producer" "$mutable_producer_sha" >/dev/null 2>&1; then
  echo "write-gate producer under an operator-writable ancestor was accepted" >&2
  exit 1
fi

reservation_history="$TMP_DIR/reservation-history"
reservation_work="$TMP_DIR/reservation-work"
mkdir "$reservation_history" "$reservation_work"
reservation_operation="$(jq -cn \
  --arg plan_sha256 "$fixture_plan_sha256" \
  '{
    kind: "account_registration",
    plan_sha256: $plan_sha256,
    account_id: "testreservationsubject",
    purpose: "pool_contract_subject",
    payload_sha256:
      "9999999999999999999999999999999999999999999999999999999999999999",
    payload_size_bytes: 4096,
    transaction: {
      tx_hash:
        "8888888888888888888888888888888888888888888888888888888888888888",
      tx_hash_hex:
        "8888888888888888888888888888888888888888888888888888888888888888"
    }
  }')"
reservation_prefix="$reservation_work/0001.registration"
reservation_gate="$reservation_history/offline-reservation.gate.json"
VALIDATION_FEE_TEST_ROOT="$ROOT" \
VALIDATION_FEE_TEST_GATE="$reservation_gate" \
VALIDATION_FEE_TEST_OPERATION="$reservation_operation" \
  python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

root = Path(os.environ["VALIDATION_FEE_TEST_ROOT"])
sys.path.insert(0, str(root / "tests"))
from test_validate_validation_fee_write_gate import gate_marker, gate_request

request = gate_request()
request["invocation_id"] = "offline-reservation"
request["operation"] = json.loads(os.environ["VALIDATION_FEE_TEST_OPERATION"])
request["plan_sha256"] = request["operation"]["plan_sha256"]
Path(os.environ["VALIDATION_FEE_TEST_GATE"]).write_text(
    json.dumps(
        gate_marker(request),
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
    )
    + "\n",
    encoding="utf-8",
)
PY
chmod 0444 "$reservation_gate"
validation_fee_write_immutable_json \
  "$(jq -cn \
    --arg journal_prefix "$reservation_prefix" \
    --argjson operation "$reservation_operation" \
    '{
      schema_version: 1,
      phase: "write_intent_reserved",
      invocation_id: "offline-reservation",
      journal_prefix: $journal_prefix,
      operation: $operation
    }')" \
  "$reservation_history/offline-reservation.intent.json" >/dev/null
validation_fee_write_immutable_json \
  "$(jq -cn \
    --argjson operation "$reservation_operation" \
    '{
      schema_version: 1,
      phase: "intent",
      invocation_id: "offline-reservation",
      operation: $operation
    }')" \
  "$reservation_prefix.intent.json" >/dev/null
SORASWAP_VALIDATION_FEE_BOUND_WORK_ROOT="$reservation_work" \
  validation_fee_assert_write_reservation_history_dir "$reservation_history"
mv "$reservation_prefix.intent.json" "$reservation_prefix.intent.lost"
if SORASWAP_VALIDATION_FEE_BOUND_WORK_ROOT="$reservation_work" \
  validation_fee_assert_write_reservation_history_dir \
    "$reservation_history" >/dev/null 2>&1; then
  echo "reservation history accepted a lost mutation journal" >&2
  exit 1
fi
mv "$reservation_prefix.intent.lost" "$reservation_prefix.intent.json"

lock_dir="$TMP_DIR/exclusive.lock"
validation_fee_acquire_apply_lock "$lock_dir"
if (
  VALIDATION_FEE_APPLY_LOCK_DIR=""
  validation_fee_acquire_apply_lock "$lock_dir"
) >/dev/null 2>&1; then
  echo "exclusive validation-fee apply lock admitted a concurrent holder" >&2
  exit 1
fi
validation_fee_release_apply_lock
validation_fee_acquire_apply_lock "$lock_dir"
validation_fee_release_apply_lock

echo "validation-fee one-write smoke ok"
