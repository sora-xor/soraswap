#!/bin/zsh
set -euo pipefail

ROOT="${SORASWAP_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
register="$ROOT/docs/parity/migration_register.md"
testnet_dir="$ROOT/deployments/testnet"

required_docs=(
  "$ROOT/docs/release/production_readiness_checklist.md"
  "$ROOT/docs/release/contract_console_security_review.md"
  "$ROOT/docs/release/contract_console_runbook.md"
)

required_evidence=(
  "$testnet_dir/chain.latest.json"
  "$testnet_dir/deploy.latest.json"
  "$testnet_dir/nested_call_probe.latest.json"
  "$testnet_dir/contracts.latest.json"
  "$testnet_dir/smoke.latest.json"
  "$testnet_dir/contract_console_smoke.latest.json"
  "$testnet_dir/trader_readonly.latest.json"
  "$testnet_dir/trader.latest.json"
  "$testnet_dir/trader_api_bundle.latest.json"
)

local_acceptance_targets=(
  test-public-env-helpers
  lint
  compile
  simulate-smoke
  simulate-full
  test-local-isolated
)

for target in "${local_acceptance_targets[@]}"; do
  echo "release checklist: make $target"
  make -C "$ROOT" "$target"
done

for artifact_path in "${required_docs[@]}" "${required_evidence[@]}"; do
  if [[ ! -f "$artifact_path" ]]; then
    echo "missing required release artifact: $artifact_path" >&2
    exit 1
  fi
done

typeset -a non_ported_lines
ported_count=0
reference_only_count=0

trim_whitespace() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

while IFS= read -r line; do
  [[ "$line" == \|* ]] || continue
  [[ "$line" == *"| Status |"* ]] && continue
  [[ "$line" == *"| --- |"* ]] && continue

  IFS='|' read -r _ _ _ row_status _ <<<"$line"
  row_status="$(trim_whitespace "$row_status")"
  case "$row_status" in
    ported)
      ported_count=$(( ported_count + 1 ))
      ;;
    reference-only)
      reference_only_count=$(( reference_only_count + 1 ))
      ;;
    "")
      ;;
    *)
      non_ported_lines+=("$line")
      ;;
  esac
done < "$register"

if (( ${#non_ported_lines[@]} > 0 )); then
  echo "release checklist failed: migration register still contains non-ported production rows" >&2
  printf '%s\n' "${non_ported_lines[@]}" >&2
  exit 1
fi

chain_json="$(cat "$testnet_dir/chain.latest.json")"
deploy_json="$(cat "$testnet_dir/deploy.latest.json")"
contracts_json="$(cat "$testnet_dir/contracts.latest.json")"
probe_json="$(cat "$testnet_dir/nested_call_probe.latest.json")"
smoke_json="$(cat "$testnet_dir/smoke.latest.json")"
console_json="$(cat "$testnet_dir/contract_console_smoke.latest.json")"
trader_readonly_json="$(cat "$testnet_dir/trader_readonly.latest.json")"
trader_json="$(cat "$testnet_dir/trader.latest.json")"
trader_api_json="$(cat "$testnet_dir/trader_api_bundle.latest.json")"

for evidence_path in \
  "$testnet_dir/deploy.latest.json" \
  "$testnet_dir/nested_call_probe.latest.json" \
  "$testnet_dir/contracts.latest.json" \
  "$testnet_dir/smoke.latest.json" \
  "$testnet_dir/contract_console_smoke.latest.json" \
  "$testnet_dir/trader_readonly.latest.json" \
  "$testnet_dir/trader.latest.json" \
  "$testnet_dir/trader_api_bundle.latest.json"; do
  if ! jq -e \
    --argjson chain "$chain_json" \
    '.chain_fingerprint != null
      and .chain_fingerprint.chain == $chain.chain
      and .chain_fingerprint.block_1_hash == $chain.block_1_hash' \
    "$evidence_path" >/dev/null; then
    echo "release checklist failed: chain fingerprint mismatch for $evidence_path" >&2
    exit 1
  fi
done

if ! jq -e '.status == "completed"' <<<"$deploy_json" >/dev/null; then
  echo "release checklist failed: deployments/testnet/deploy.latest.json is not completed" >&2
  exit 1
fi

if ! jq -e '.status == "completed"' <<<"$trader_readonly_json" >/dev/null; then
  trader_readonly_reason="$(jq -r '.blocked_reason // empty' <<<"$trader_readonly_json" 2>/dev/null || true)"
  if [[ -n "$trader_readonly_reason" ]]; then
    echo "release checklist failed: trader_readonly.latest.json is not completed: $trader_readonly_reason" >&2
  else
    echo "release checklist failed: trader_readonly.latest.json is not completed" >&2
  fi
  exit 1
fi

if ! jq -e '.status == "completed"' <<<"$trader_json" >/dev/null; then
  trader_reason="$(jq -r '.blocked_reason // empty' <<<"$trader_json" 2>/dev/null || true)"
  if [[ -n "$trader_reason" ]]; then
    echo "release checklist failed: trader.latest.json is not completed: $trader_reason" >&2
  else
    echo "release checklist failed: trader.latest.json is not completed" >&2
  fi
  exit 1
fi

if ! jq -e '
  ((.content_cid // "") | test("^b[a-z2-7]+$"))
  and ((.manifest_digest_hex // "") | test("^[0-9a-fA-F]{64}$"))
  and ((.routes // []) | length >= 5)
  and (.cid_probe.status // "") == "completed"
' <<<"$trader_api_json" >/dev/null; then
  echo "release checklist failed: trader_api_bundle.latest.json is missing CID, manifest digest, routes, or successful CID probe" >&2
  exit 1
fi

required_phases=(
  preflight
  compile
  nested_call_probe
  deploy
  bootstrap_contract_state
  deployment_records_snapshot
)

for phase in "${required_phases[@]}"; do
  if ! jq -e --arg phase "$phase" '.phases[$phase].status == "completed"' <<<"$deploy_json" >/dev/null; then
    echo "release checklist failed: deploy.latest.json phase $phase is not completed" >&2
    exit 1
  fi
done

if ! jq -e '.supported == true' <<<"$probe_json" >/dev/null; then
  probe_summary="$(jq -r '.summary // empty' <<<"$probe_json" 2>/dev/null || true)"
  if [[ -n "$probe_summary" ]]; then
    echo "release checklist failed: $probe_summary" >&2
  else
    echo "release checklist failed: nested_call_probe.latest.json shows public Taira nested call support is unavailable" >&2
  fi
  exit 1
fi

if ! jq -e \
  --argjson probe "$probe_json" \
  --argjson contracts "$contracts_json" \
  --argjson deploy "$deploy_json" \
  '
    (.nested_call_probe.generated_at // null) == ($probe.generated_at // null)
    and (.nested_call_probe.supported // false) == true
    and (.contracts_snapshot.generated_at // null) == ($contracts.generated_at // null)
    and (.deploy_snapshot.generated_at // null) == ($deploy.generated_at // null)
    and (.deploy_snapshot.status // null) == ($deploy.status // null)
  ' <<<"$smoke_json" >/dev/null; then
  echo "release checklist failed: smoke.latest.json does not reference the current nested-call/contracts/deploy snapshots" >&2
  exit 1
fi

if ! jq -e \
  --argjson contracts "$contracts_json" \
  --argjson deploy "$deploy_json" \
  '
    (.contracts_snapshot.generated_at // null) == ($contracts.generated_at // null)
    and (.deploy_snapshot.generated_at // null) == ($deploy.generated_at // null)
    and (.deploy_snapshot.status // null) == ($deploy.status // null)
' <<<"$console_json" >/dev/null; then
  echo "release checklist failed: contract_console_smoke.latest.json does not reference the current contracts/deploy snapshots" >&2
  exit 1
fi

if ! jq -e \
  --argjson contracts "$contracts_json" \
  --argjson deploy "$deploy_json" \
  '
    (.contracts_snapshot.generated_at // null) == ($contracts.generated_at // null)
    and (.deploy_snapshot.generated_at // null) == ($deploy.generated_at // null)
    and (.deploy_snapshot.status // null) == ($deploy.status // null)
  ' <<<"$trader_readonly_json" >/dev/null; then
  echo "release checklist failed: trader_readonly.latest.json does not reference the current contracts/deploy snapshots" >&2
  exit 1
fi

if ! jq -e \
  --argjson contracts "$contracts_json" \
  --argjson deploy "$deploy_json" \
  '
    (.contracts_snapshot.generated_at // null) == ($contracts.generated_at // null)
    and (.deploy_snapshot.generated_at // null) == ($deploy.generated_at // null)
    and (.deploy_snapshot.status // null) == ($deploy.status // null)
  ' <<<"$trader_json" >/dev/null; then
  echo "release checklist failed: trader.latest.json does not reference the current contracts/deploy snapshots" >&2
  exit 1
fi

if ! jq -e --argjson contracts "$contracts_json" '(.generated_at // "") >= ($contracts.generated_at // "")' <<<"$smoke_json" >/dev/null; then
  echo "release checklist failed: smoke.latest.json is older than contracts.latest.json" >&2
  exit 1
fi

if ! jq -e '
  (.tx_hashes.perps_liquidation_queue_pass // null) != null
  and (.tx_hashes.perps_liquidation_recovery_pass // null) != null
  and (.tx_hashes.perps_liquidation_requeue_pass // null) != null
  and (.tx_hashes.perps_liquidation_execute_pass // null) != null
  and ((.view_results.perps_liquidation_state[6] // 0) == 1)
  and ((.view_results.perps_liquidation_position_liquidation_state[1] // 0) > 0)
  and ((.view_results.perps_liquidation_position_liquidation_state[2] // 0) > 0)
' <<<"$smoke_json" >/dev/null; then
  echo "release checklist failed: smoke.latest.json is missing automatic perps liquidation evidence" >&2
  exit 1
fi

if ! jq -e '(.bridge.route_provenance[0] // 0) == 1' <<<"$console_json" >/dev/null; then
  echo "release checklist failed: contract_console_smoke.latest.json does not prove a governed bridge route" >&2
  exit 1
fi

if ! jq -e --argjson contracts "$contracts_json" '(.generated_at // "") >= ($contracts.generated_at // "")' <<<"$console_json" >/dev/null; then
  echo "release checklist failed: contract_console_smoke.latest.json is older than contracts.latest.json" >&2
  exit 1
fi

if ! jq -e --argjson contracts "$contracts_json" '(.generated_at // "") >= ($contracts.generated_at // "")' <<<"$trader_readonly_json" >/dev/null; then
  echo "release checklist failed: trader_readonly.latest.json is older than contracts.latest.json" >&2
  exit 1
fi

if ! jq -e --argjson contracts "$contracts_json" '(.generated_at // "") >= ($contracts.generated_at // "")' <<<"$trader_json" >/dev/null; then
  echo "release checklist failed: trader.latest.json is older than contracts.latest.json" >&2
  exit 1
fi

if ! jq -e '
  if (.bridge.submission_expectation // "") == "apply" then
    ((.submissions.proof_status.status_kind // "") | test("Applied|Committed"))
    and ((.submissions.message_status.status_kind // "") | test("Applied|Committed"))
    and ((.bridge.consumed_before_submit // 1) == 0)
  elif (.bridge.submission_expectation // "") == "replay_reject" then
    ((.submissions.proof_status.status_kind // "") | test("Applied|Committed|Skipped|Rejected"))
    and ((.submissions.message_status.status_kind // "") == "Rejected")
    and ((.bridge.consumed_before_submit // 0) != 0)
  else
    false
  end
' <<<"$console_json" >/dev/null; then
  echo "release checklist failed: contract_console_smoke.latest.json does not record a valid bridge submission outcome" >&2
  exit 1
fi

if ! jq -e '(.route_probes.required_missing | length) == 0' <<<"$trader_readonly_json" >/dev/null; then
  echo "release checklist failed: trader_readonly.latest.json reports missing trader routes on public Taira" >&2
  exit 1
fi

if ! jq -e '
  (.route_probes.required_missing | length) == 0
  and ((.mutation.signer_ready.status // "") == "completed")
  and ((.mutation.swap.status // "") == "completed")
  and ((.mutation.swap.tx_hash // null) != null)
' <<<"$trader_json" >/dev/null; then
  echo "release checklist failed: trader.latest.json is missing a signed trader mutation or still reports missing trader routes" >&2
  exit 1
fi

echo "release checklist ok"
echo "  ported: $ported_count"
echo "  reference-only: $reference_only_count"
echo "  docs: ${#required_docs[@]} present"
echo "  evidence: ${#required_evidence[@]} present under deployments/testnet"
