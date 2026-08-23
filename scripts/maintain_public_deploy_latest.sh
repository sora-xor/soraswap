#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

public_env="${SORASWAP_PUBLIC_ENV:-testnet}"
apply=0

usage() {
  cat >&2 <<EOF
Usage: $0 [--env testnet|production] [--apply|--dry-run]

Preserve a failed deployments/<env>/deploy.latest.json as deploy.failed.* and,
only when a completed report matches the current chain and contracts snapshot,
restore deploy.latest.json to that completed report.

The default mode is dry-run. Use --apply to write evidence sidecars or restore
deploy.latest.json.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --env)
      [[ $# -ge 2 ]] || {
        usage
        exit 1
      }
      public_env="$2"
      shift 2
      ;;
    --apply)
      apply=1
      shift
      ;;
    --dry-run)
      apply=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

case "$public_env" in
  testnet|production)
    ;;
  *)
    echo "maintain_public_deploy_latest.sh only supports --env testnet|production; got $public_env" >&2
    exit 1
    ;;
esac

deploy_candidate_check_json() {
  local env="$1"
  local deploy_path="$2"
  local contracts_path="$3"
  local chain_fingerprint_json="$4"
  local issues_json issue_count output deploy_generated_at contracts_generated_at

  if [[ ! -s "$deploy_path" ]]; then
    jq -cn \
      --arg output "missing deploy report at $(soraswap_display_path "$deploy_path")" \
      '{status: "degraded", output: $output}'
    return 0
  fi
  if [[ ! -s "$contracts_path" ]]; then
    jq -cn \
      --arg output "missing contracts snapshot at $(soraswap_display_path "$contracts_path")" \
      '{status: "degraded", output: $output}'
    return 0
  fi
  if ! jq -e '
    type == "object"
    and ((.torii_url // "") | type == "string" and length > 0)
    and ((.chain // "") | type == "string" and length > 0)
    and ((.block_1_hash // "") | type == "string" and length > 0)
  ' >/dev/null 2>&1 <<<"$chain_fingerprint_json"; then
    jq -cn '{status: "degraded", output: "current chain fingerprint is unavailable"}'
    return 0
  fi

  issues_json="$(jq -n -c \
    --slurpfile deploy "$deploy_path" \
    --slurpfile contracts "$contracts_path" \
    --arg env "$env" \
    --argjson chain "$chain_fingerprint_json" \
    '
      def nonempty_string($v): (($v // "") | type == "string" and length > 0);
      def matches_chain($fingerprint):
        (($fingerprint.torii_url // null) == ($chain.torii_url // null))
        and (($fingerprint.chain // null) == ($chain.chain // null))
        and (($fingerprint.block_1_hash // null) == ($chain.block_1_hash // null));
      def current_contract_snapshot_path($snapshot; $contracts_generated):
        ($snapshot | type) == "string"
        and ("contracts." + $contracts_generated + ".json") as $contracts_file
        | ($snapshot == $contracts_file or ($snapshot | endswith("/" + $contracts_file)));

      ($deploy[0] // {}) as $deploy_report
      | ($contracts[0] // {}) as $contracts_snapshot
      | ($deploy_report.generated_at // "") as $deploy_generated
      | ($contracts_snapshot.generated_at // "") as $contracts_generated
      | [
          if ((
            ($deploy_report.status // "") == "completed"
            and nonempty_string($deploy_generated)
            and (($deploy_report.environment // "") == $env)
            and matches_chain($deploy_report.chain_fingerprint // {})
            and (($deploy_report.phases.preflight.status // "") == "completed")
            and (($deploy_report.phases.compile.status // "") == "completed")
            and (($deploy_report.phases.nested_call_probe.status // "") == "completed")
            and (($deploy_report.phases.deploy.status // "") == "completed")
            and (($deploy_report.phases.bootstrap_contract_state.status // "") == "completed")
            and (($deploy_report.phases.deployment_records_snapshot.status // "") == "completed")
            and (($deploy_report.phases.preflight.detail.signer_ready_check.status // "") == "completed")
            and (($deploy_report.phases.preflight.detail.signer_ready_check.debug_bypass_env // null) == null)
          ) | not) then
            "deploy report is not a completed current-chain deploy with all required phases and signer-readiness proof"
          else empty end,
          if ((
            ($contracts_snapshot.status // "") == "completed"
            and nonempty_string($contracts_generated)
            and (($contracts_snapshot.environment // "") == $env)
            and matches_chain($contracts_snapshot.chain_fingerprint // {})
            and (($contracts_snapshot.contracts // []) | type == "array" and length > 0)
          ) | not) then
            "contracts.latest.json is not a completed current-chain contracts snapshot"
          else empty end,
          if ((nonempty_string($deploy_generated) and nonempty_string($contracts_generated) and ($contracts_generated >= $deploy_generated)) | not) then
            "current contracts snapshot is older than the deploy report"
          else empty end,
          if ((current_contract_snapshot_path(($deploy_report.phases.deployment_records_snapshot.detail.snapshot // ""); $contracts_generated)) | not) then
            "deploy report does not reference the current contracts snapshot"
          else empty end
        ]
    ' 2>/dev/null)" || {
      jq -cn '{status: "degraded", output: "deploy report candidate could not be evaluated"}'
      return 0
    }

  issue_count="$(jq -r 'length' <<<"$issues_json" 2>/dev/null || echo 1)"
  if [[ -z "$issue_count" || "$issue_count" != <-> ]]; then
    issue_count=1
  fi
  if (( issue_count > 0 )); then
    output="$(jq -r '.[]' <<<"$issues_json" | soraswap_redact_sensitive_text)"
    jq -cn --arg status degraded --arg output "$output" '{status: $status, output: $output}'
    return 0
  fi

  deploy_generated_at="$(jq -r '.generated_at' "$deploy_path")"
  contracts_generated_at="$(jq -r '.generated_at' "$contracts_path")"
  jq -cn \
    --arg status completed \
    --arg output "deploy report matches current chain and contracts snapshot" \
    --arg deploy_path "$(soraswap_display_path "$deploy_path")" \
    --arg deploy_generated_at "$deploy_generated_at" \
    --arg contracts_generated_at "$contracts_generated_at" \
    '{
      status: $status,
      output: $output,
      deploy: {
        path: $deploy_path,
        generated_at: $deploy_generated_at
      },
      contracts_snapshot: {
        generated_at: $contracts_generated_at
      }
    }'
}

report_dir="$(deployments_dir_for_env "$public_env")"
latest="$(deploy_report_latest_path_for_env "$public_env")"
contracts_latest="$(contracts_snapshot_latest_path_for_env "$public_env")"
chain_fingerprint_json="$(current_or_saved_chain_fingerprint_json_for_env "$public_env" 2>/dev/null || printf 'null')"

if [[ ! -s "$latest" ]]; then
  echo "deploy latest maintenance: missing $(soraswap_display_path "$latest")" >&2
  exit 1
fi

latest_json="$(jq -c . "$latest" 2>/dev/null)" || {
  echo "deploy latest maintenance: $(soraswap_display_path "$latest") is not valid JSON" >&2
  exit 1
}
latest_status="$(jq -r '.status // empty' <<<"$latest_json")"
latest_check_json="$(deploy_candidate_check_json "$public_env" "$latest" "$contracts_latest" "$chain_fingerprint_json")"

if [[ "$latest_status" != "failed" ]]; then
  if [[ "$(jq -r '.status // empty' <<<"$latest_check_json")" == "completed" ]]; then
    echo "deploy latest maintenance: no action needed; $(soraswap_display_path "$latest") is current"
    exit 0
  fi
  echo "deploy latest maintenance blocked: $(soraswap_display_path "$latest") is status=${latest_status:-unknown}, not failed, but it is not current" >&2
  jq -r '.output // empty' <<<"$latest_check_json" | soraswap_redact_sensitive_text >&2
  exit 75
fi

best_candidate_path=""
best_candidate_json="null"
best_candidate_generated_at=""
newest_completed_issue_output=""

for candidate_path in "$report_dir"/deploy.*.json(N); do
  candidate_base="$(basename "$candidate_path")"
  case "$candidate_base" in
    deploy.latest.json|deploy.failed.*.json)
      continue
      ;;
  esac
  if ! jq -e '(.status // "") == "completed"' "$candidate_path" >/dev/null 2>&1; then
    continue
  fi
  candidate_generated_at="$(jq -r '.generated_at // empty' "$candidate_path" 2>/dev/null || true)"
  [[ -n "$candidate_generated_at" ]] || continue
  candidate_check_json="$(deploy_candidate_check_json "$public_env" "$candidate_path" "$contracts_latest" "$chain_fingerprint_json")"
  if [[ "$(jq -r '.status // empty' <<<"$candidate_check_json")" == "completed" ]]; then
    if [[ -z "$best_candidate_generated_at" || "$candidate_generated_at" > "$best_candidate_generated_at" ]]; then
      best_candidate_path="$candidate_path"
      best_candidate_json="$candidate_check_json"
      best_candidate_generated_at="$candidate_generated_at"
    fi
  elif [[ -z "$newest_completed_issue_output" || "$candidate_generated_at" > "${newest_completed_issue_generated_at:-}" ]]; then
    newest_completed_issue_generated_at="$candidate_generated_at"
    newest_completed_issue_output="$(jq -r '.output // empty' <<<"$candidate_check_json")"
  fi
done

failed_generated_at="$(jq -r '.generated_at // empty' <<<"$latest_json")"
failed_latest="$(deploy_report_failed_latest_path_for_env "$public_env")"
if [[ -n "$failed_generated_at" ]]; then
  failed_timestamped="$(deploy_report_failed_timestamped_path_for_env "$public_env" "$failed_generated_at")"
else
  failed_timestamped=""
fi
redacted_latest_json="$(soraswap_redact_sensitive_text "$latest_json")"

if (( apply == 0 )); then
  echo "deploy latest maintenance dry-run: failed deploy latest found at $(soraswap_display_path "$latest")"
  echo "  would preserve failed report: $(soraswap_display_path "$failed_latest")"
  if [[ -n "$failed_timestamped" ]]; then
    echo "  would preserve failed report: $(soraswap_display_path "$failed_timestamped")"
  fi
  if [[ -n "$best_candidate_path" ]]; then
    echo "  would restore deploy latest from: $(soraswap_display_path "$best_candidate_path")"
    jq -r '("  candidate: generated_at=" + .deploy.generated_at + " contracts_snapshot=" + .contracts_snapshot.generated_at)' <<<"$best_candidate_json"
    exit 0
  fi
  echo "  no completed deploy report matches the current chain and contracts.latest.json" >&2
  if [[ -n "$newest_completed_issue_output" ]]; then
    printf '%s\n' "$newest_completed_issue_output" | sed 's/^/  newest completed deploy issue: /' >&2
  fi
  echo "  fresh deploy evidence is required after public write health recovers" >&2
  exit 75
fi

soraswap_write_json_report_pair "$redacted_latest_json" "$failed_latest" "$failed_timestamped" || exit 1
echo "deploy latest maintenance: preserved failed report at $(soraswap_display_path "$failed_latest")"
if [[ -n "$failed_timestamped" ]]; then
  echo "deploy latest maintenance: preserved failed report at $(soraswap_display_path "$failed_timestamped")"
fi

if [[ -z "$best_candidate_path" ]]; then
  echo "deploy latest maintenance blocked: no completed deploy report matches the current chain and contracts.latest.json" >&2
  if [[ -n "$newest_completed_issue_output" ]]; then
    printf '%s\n' "$newest_completed_issue_output" | sed 's/^/  newest completed deploy issue: /' >&2
  fi
  echo "fresh deploy evidence is required after public write health recovers" >&2
  exit 75
fi

best_candidate_report_json="$(jq -c . "$best_candidate_path")"
soraswap_write_json_file_atomic "$best_candidate_report_json" "$latest" || exit 1
best_timestamped="$report_dir/deploy.${best_candidate_generated_at}.json"
soraswap_write_json_file_atomic "$best_candidate_report_json" "$best_timestamped" || exit 1
echo "deploy latest maintenance: restored $(soraswap_display_path "$latest") from $(soraswap_display_path "$best_candidate_path")"
