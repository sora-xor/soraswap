#!/bin/zsh
set -euo pipefail

ROOT="${SORASWAP_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
source "$ROOT/scripts/common.sh"

public_env="${SORASWAP_PUBLIC_ENV:-testnet}"
case "$public_env" in
  testnet|production)
    ;;
  *)
    echo "record_rwa_compliance.sh only supports SORASWAP_PUBLIC_ENV=testnet|production; got $public_env" >&2
    exit 1
    ;;
esac
case "$public_env" in
  testnet)
    chain_refresh_command="make refresh-testnet-chain"
    nested_probe_setup_command="SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make testnet-nested-call-probe"
    preflight_setup_command="SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make taira-preflight"
    ;;
  production)
    chain_refresh_command="make refresh-production-chain"
    nested_probe_setup_command="SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make production-nested-call-probe"
    preflight_setup_command="SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make production-preflight"
    ;;
esac

report_dir="${SORASWAP_RWA_COMPLIANCE_REPORT_DIR:-$(deployments_dir_for_env "$public_env")}"
latest_report="$report_dir/rwa_compliance.latest.json"
timestamp="$(utc_timestamp)"
timestamped_report="$report_dir/rwa_compliance.${timestamp}.json"
preflight_path="${SORASWAP_RWA_COMPLIANCE_PREFLIGHT_FILE:-$report_dir/preflight.latest.json}"
chain_path="${SORASWAP_RWA_COMPLIANCE_CHAIN_FILE:-$report_dir/chain.latest.json}"

print_preflight_setup_summary() {
  local preflight_label generated_at preflight_status target_environment

  [[ -s "$preflight_path" ]] || return 0
  if jq -e '
    (.status // "") == "ready"
    and ((.blockers // []) | length) == 0
    and ((.warnings // []) | length) == 0
    and (.endpoint.health_issues | type == "array" and length == 0)
    and ((.endpoint.health.status.http_status // "") | tostring) == "200"
    and (.endpoint.health.status.json_available == true)
    and ((.endpoint.health.sumeragi.http_status // "") | tostring) == "200"
    and (.endpoint.health.sumeragi.json_available == true)
  ' "$preflight_path" >/dev/null 2>&1; then
    return 0
  fi

  preflight_label="$(soraswap_display_path "$preflight_path")"
  generated_at="$(jq -r '.generated_at // "unknown"' "$preflight_path" 2>/dev/null || echo "unknown")"
  preflight_status="$(jq -r '.status // "unknown"' "$preflight_path" 2>/dev/null || echo "unknown")"
  target_environment="$(jq -r '.target_environment // "unknown"' "$preflight_path" 2>/dev/null || echo "unknown")"
  echo "preflight setup summary: $preflight_label status=$preflight_status target_environment=$target_environment generated_at=$generated_at" >&2
  soraswap_print_preflight_report_reasons "$preflight_path" "preflight"
}

fail_with_setup_hint() {
  echo "rwa compliance evidence: $*" >&2
  print_preflight_setup_summary
  cat >&2 <<EOF

Required setup:
  # Required first when chain fingerprint evidence is missing or stale.
  $chain_refresh_command
  # Required after chain refresh to prove current-chain nested-call support.
  $nested_probe_setup_command
  # Required after the signed nested-call probe and before final release references.
  $preflight_setup_command
  export SORASWAP_RWA_ISSUER_APPROVAL_REF=<external approval id or URL>
  export SORASWAP_RWA_LEGAL_REVIEW_REF=<external legal review id or URL>
  export SORASWAP_RWA_COMPLIANCE_POLICY_REF=<external compliance policy id or URL>
  export SORASWAP_RWA_NAV_SOURCE_REF=<external NAV source id or URL>
  export SORASWAP_RWA_REDEMPTION_TERMS_REF=<external redemption terms id or URL>
  make record-${public_env}-rwa-compliance

The referenced documents stay outside this repository; this script records only their release-gate references.
EOF
  exit 1
}

preflight_not_ready_detail() {
  local preflight_file="$1"
  local detail

  detail="$(jq -r '
    [
      (.blockers[]? | "blocker: \(.)"),
      (.warnings[]? | "warning: \(.)"),
      (.endpoint.health_issues[]? | "health issue: \(.)"),
      (if ((.endpoint.health.status.http_status // "") | tostring) != "200"
          or (.endpoint.health.status.json_available != true)
        then "health issue: status endpoint health snapshot is not JSON-ready" else empty end),
      (if ((.endpoint.health.sumeragi.http_status // "") | tostring) != "200"
          or (.endpoint.health.sumeragi.json_available != true)
        then "health issue: sumeragi endpoint health snapshot is not JSON-ready" else empty end)
    ] as $reasons
    | if ($reasons | length) > 0 then
        $reasons | join("; ")
      else
        "status: \((.status // "missing") | tostring)"
      end
  ' "$preflight_file" 2>/dev/null || true)"
  soraswap_redact_sensitive_text "$detail"
}

validated_chain_latest_json() {
  if [[ -s "$chain_path" ]]; then
    if ! jq -e --arg public_env "$public_env" \
      '((.environment // "") | type == "string") and .environment == $public_env' \
      "$chain_path" >/dev/null 2>&1; then
      fail_with_setup_hint "chain.latest.json environment does not match selected environment $public_env"
    fi
    if ! jq -e '
      ((.generated_at // "") | type == "string" and length > 0)
      and ((.torii_url // "") | type == "string" and length > 0)
      and ((.chain // "") | type == "string" and length > 0)
      and ((.block_1_hash // "") | type == "string" and length > 0)
    ' "$chain_path" >/dev/null 2>&1; then
      fail_with_setup_hint "chain.latest.json is missing generated_at, torii_url, chain, or block_1_hash"
    fi
    jq -c '{torii_url, chain, block_1_hash}' "$chain_path"
    return
  fi

  return 1
}

ready_preflight_chain_fingerprint_json() {
  local expected_chain_json="${1:-}"
  local preflight_detail chain_fingerprint_json

  if [[ ! -s "$preflight_path" ]]; then
    if [[ -n "$expected_chain_json" ]]; then
      fail_with_setup_hint "preflight.latest.json is required before RWA compliance evidence can be completed for selected environment $public_env"
    fi
    if [[ -s "$chain_path" ]]; then
      validated_chain_latest_json >/dev/null || return 1
      fail_with_setup_hint "preflight.latest.json is required before RWA compliance evidence can be completed for selected environment $public_env"
    fi
    fail_with_setup_hint "missing chain fingerprint; run $chain_refresh_command, then $nested_probe_setup_command, then $preflight_setup_command"
  fi

  if ! jq -e --arg public_env "$public_env" \
    '((.target_environment // "") | type == "string") and .target_environment == $public_env' \
    "$preflight_path" >/dev/null 2>&1; then
    fail_with_setup_hint "preflight.latest.json target_environment does not match selected environment $public_env"
  fi

  if ! jq -e '.chain.fingerprint != null' "$preflight_path" >/dev/null 2>&1; then
    fail_with_setup_hint "preflight.latest.json is missing chain fingerprint for selected environment $public_env"
  fi

  if ! jq -e --arg public_env "$public_env" '
    .status == "ready"
    and ((.generated_at // "") | type == "string" and length > 0)
    and ((.blockers // []) | length) == 0
    and ((.warnings // []) | length) == 0
    and (.environment.mutations_allowed // false) == true
    and (.environment.oracle_client_config_present // false) == true
    and (.environment.oracle_client_config_valid // false) == true
    and (.environment.oracle_account_derivable // false) == true
    and (.environment.oracle_account_distinct // false) == true
    and ((.environment.oracle_client_config_source // "") | type == "string" and length > 0)
    and ((.endpoint.mcp_http_status // "") | tostring) == "200"
    and (.endpoint.mcp.enabled // false) == true
    and (.endpoint.mcp.metadata_valid // false) == true
    and ((.endpoint.mcp.protocol_version // "") | type == "string" and length > 0)
    and ((.endpoint.mcp.server_name // "") | type == "string" and length > 0)
    and ((.endpoint.mcp.server_version // "") | type == "string" and length > 0)
    and ((.endpoint.mcp.tool_count // 0) | type == "number" and . > 0)
    and ((.endpoint.mcp.toolset_version // "") | type == "string" and length > 0)
    and (.endpoint.health_issues | type == "array" and length == 0)
    and ((.endpoint.health.status.http_status // "") | tostring) == "200"
    and (.endpoint.health.status.json_available == true)
    and ((.endpoint.health.sumeragi.http_status // "") | tostring) == "200"
    and (.endpoint.health.sumeragi.json_available == true)
    and (.chain.fingerprint_available // false) == true
    and (.chain.saved_snapshot_exists // false) == true
    and (.chain.saved_snapshot_matches // false) == true
    and (.chain.saved_snapshot_environment // "") == $public_env
    and (.nested_call_probe.latest_exists // false) == true
    and (.nested_call_probe.matches_current_chain // false) == true
    and (.nested_call_probe.supported // false) == true
    and (.signer.authority_derivable // false) == true
    and (.signer.account_exists // false) == true
    and (.signer.assets_query_available // false) == true
    and (((.signer.fee_balance // "0") | tonumber) > 0)
  ' "$preflight_path" >/dev/null 2>&1; then
    preflight_detail="$(preflight_not_ready_detail "$preflight_path")"
    if [[ -n "$preflight_detail" ]]; then
      fail_with_setup_hint "preflight.latest.json is not release-ready for selected environment $public_env: $preflight_detail"
    fi
    fail_with_setup_hint "preflight.latest.json is not release-ready for selected environment $public_env"
  fi

  if [[ ! -s "$chain_path" ]]; then
    fail_with_setup_hint "chain.latest.json is required when using preflight.latest.json for RWA compliance evidence"
  fi
  validated_chain_latest_json >/dev/null || return 1

  if ! jq -e --arg public_env "$public_env" \
    --slurpfile chain "$chain_path" \
    '
      (($chain[0].environment // "") | type == "string") and ($chain[0].environment // "") == $public_env
      and (($chain[0].generated_at // "") | type == "string" and length > 0)
      and (($chain[0].torii_url // "") | type == "string" and length > 0)
      and (($chain[0].chain // "") | type == "string" and length > 0)
      and (($chain[0].block_1_hash // "") | type == "string" and length > 0)
      and ((.chain.fingerprint.torii_url // "") | type == "string" and length > 0)
      and (.chain.fingerprint.torii_url // null) == ($chain[0].torii_url // null)
      and (.chain.fingerprint.chain // null) == ($chain[0].chain // null)
      and (.chain.fingerprint.block_1_hash // null) == ($chain[0].block_1_hash // null)
    ' "$preflight_path" >/dev/null 2>&1; then
    fail_with_setup_hint "preflight.latest.json does not match saved chain.latest.json for selected environment $public_env"
  fi

  chain_fingerprint_json="$(jq -c '.chain.fingerprint | {torii_url, chain, block_1_hash}' "$preflight_path")"
  if [[ -n "$expected_chain_json" ]] && ! jq -en \
    --argjson expected "$expected_chain_json" \
    --argjson current "$chain_fingerprint_json" \
    '$expected.torii_url == $current.torii_url
      and $expected.chain == $current.chain
      and $expected.block_1_hash == $current.block_1_hash' \
      >/dev/null 2>&1; then
    fail_with_setup_hint "SORASWAP_RWA_COMPLIANCE_CHAIN_JSON does not match ready preflight.latest.json and saved chain.latest.json for selected environment $public_env"
  fi

  printf '%s\n' "$chain_fingerprint_json"
}

chain_fingerprint_from_inputs() {
  local manual_chain_fingerprint_json

  if [[ -n "${SORASWAP_RWA_COMPLIANCE_CHAIN_JSON:-}" ]]; then
    if ! manual_chain_fingerprint_json="$(strict_chain_fingerprint_json_or_null "$SORASWAP_RWA_COMPLIANCE_CHAIN_JSON")"; then
      fail_with_setup_hint "chain fingerprint must include torii_url, chain, and block_1_hash"
    fi
    if [[ "$manual_chain_fingerprint_json" == "null" ]]; then
      fail_with_setup_hint "chain fingerprint must include torii_url, chain, and block_1_hash"
    fi
    ready_preflight_chain_fingerprint_json "$manual_chain_fingerprint_json"
    return
  fi

  ready_preflight_chain_fingerprint_json
}

valid_completed_report_matches_chain() {
  local report="$1"
  local chain_fingerprint_json="$2"
  local field value ready_preflight_generated_at notes_value notes_redacted_value

  [[ -s "$report" ]] || return 1
  jq -e \
    --arg public_env "$public_env" \
    --argjson chain "$chain_fingerprint_json" \
    '
      def current_chain:
        ((.generated_at // "") | type == "string" and length > 0)
        and (.environment // "") == $public_env
        and .chain_fingerprint != null
        and .chain_fingerprint.torii_url == $chain.torii_url
        and .chain_fingerprint.chain == $chain.chain
        and .chain_fingerprint.block_1_hash == $chain.block_1_hash;
      def completed_refs:
        .status == "completed"
        and ((.issuer_approval_ref // "") | type == "string" and length > 0)
        and ((.legal_review_ref // "") | type == "string" and length > 0)
        and ((.compliance_policy_ref // "") | type == "string" and length > 0)
        and ((.nav_source_ref // "") | type == "string" and length > 0)
        and ((.redemption_terms_ref // "") | type == "string" and length > 0);
      def not_applicable:
        .status == "not_applicable"
        and .rwa_release_enabled == false
        and ((.reason // "") | type == "string" and length > 0);
      current_chain and (completed_refs or not_applicable)
    ' "$report" >/dev/null || return 1

  if jq -e '.status == "completed"' "$report" >/dev/null 2>&1; then
    for field in \
      issuer_approval_ref \
      legal_review_ref \
      compliance_policy_ref \
      nav_source_ref \
      redemption_terms_ref; do
      value="$(jq -r --arg field "$field" '.[$field] // ""' "$report")"
      if soraswap_rwa_ref_has_control_chars "$value" || soraswap_rwa_ref_looks_placeholder "$value"; then
        return 1
      fi
    done
  fi
  notes_value="$(jq -r '.notes // ""' "$report")"
  notes_redacted_value="$(soraswap_redact_sensitive_text "$notes_value")"
  [[ "$notes_value" == "$notes_redacted_value" ]] || return 1

  ready_preflight_generated_at=""
  if [[ -s "$preflight_path" ]]; then
    ready_preflight_generated_at="$(jq -r --arg public_env "$public_env" '
      if ((.target_environment // "") == $public_env)
        and (.status == "ready")
        and ((.generated_at // "") | type == "string" and length > 0)
        and ((.blockers // []) | length) == 0
        and ((.warnings // []) | length) == 0
        and (.environment.mutations_allowed // false) == true
        and (.environment.oracle_client_config_present // false) == true
        and (.environment.oracle_client_config_valid // false) == true
        and (.environment.oracle_account_derivable // false) == true
        and (.environment.oracle_account_distinct // false) == true
        and ((.environment.oracle_client_config_source // "") | type == "string" and length > 0)
        and ((.endpoint.mcp_http_status // "") | tostring) == "200"
        and (.endpoint.mcp.enabled // false) == true
        and (.endpoint.mcp.metadata_valid // false) == true
        and ((.endpoint.mcp.protocol_version // "") | type == "string" and length > 0)
        and ((.endpoint.mcp.server_name // "") | type == "string" and length > 0)
        and ((.endpoint.mcp.server_version // "") | type == "string" and length > 0)
        and ((.endpoint.mcp.tool_count // 0) | type == "number" and . > 0)
        and ((.endpoint.mcp.toolset_version // "") | type == "string" and length > 0)
        and (.endpoint.health_issues | type == "array" and length == 0)
        and ((.endpoint.health.status.http_status // "") | tostring) == "200"
        and (.endpoint.health.status.json_available == true)
        and ((.endpoint.health.sumeragi.http_status // "") | tostring) == "200"
        and (.endpoint.health.sumeragi.json_available == true)
        and (.chain.fingerprint_available // false) == true
        and (.chain.saved_snapshot_exists // false) == true
        and (.chain.saved_snapshot_matches // false) == true
        and (.chain.saved_snapshot_environment // "") == $public_env
        and (.chain.fingerprint != null)
        and ((.chain.fingerprint.torii_url // "") | type == "string" and length > 0)
        and ((.chain.fingerprint.chain // "") | type == "string" and length > 0)
        and ((.chain.fingerprint.block_1_hash // "") | type == "string" and length > 0)
        and (.nested_call_probe.latest_exists // false) == true
        and (.nested_call_probe.matches_current_chain // false) == true
        and (.nested_call_probe.supported // false) == true
        and (.signer.authority_derivable // false) == true
        and (.signer.account_exists // false) == true
        and (.signer.assets_query_available // false) == true
        and (((.signer.fee_balance // "0") | tonumber) > 0)
      then .generated_at
      else empty end
    ' "$preflight_path" 2>/dev/null || true)"
  fi
  if [[ -n "$ready_preflight_generated_at" ]]; then
    jq -e --arg ready_preflight_generated_at "$ready_preflight_generated_at" \
      '((.generated_at // "") | type == "string" and . >= $ready_preflight_generated_at)' \
      "$report" >/dev/null || return 1
  fi

  return 0
}

chain_fingerprint_json="$(chain_fingerprint_from_inputs)"
if [[ "$chain_fingerprint_json" == "null" ]]; then
  fail_with_setup_hint "missing usable chain fingerprint"
fi
if ! jq -e '
  type == "object"
  and ((.torii_url // "") | type == "string" and length > 0)
  and ((.chain // "") | type == "string" and length > 0)
  and ((.block_1_hash // "") | type == "string" and length > 0)
' <<<"$chain_fingerprint_json" >/dev/null 2>&1; then
  fail_with_setup_hint "chain fingerprint must include torii_url, chain, and block_1_hash"
fi

rwa_release_enabled="$(soraswap_rwa_release_enabled_setting_for_env "$public_env")" || exit 1
force_refresh="${SORASWAP_FORCE_RWA_COMPLIANCE_REFRESH:-0}"
soraswap_require_binary_integer_setting "SORASWAP_FORCE_RWA_COMPLIANCE_REFRESH" "$force_refresh" || exit 1
if [[ "$force_refresh" != "1" ]] \
  && valid_completed_report_matches_chain "$latest_report" "$chain_fingerprint_json" \
  && { [[ "$rwa_release_enabled" != "1" ]] || ! jq -e '.status == "not_applicable"' "$latest_report" >/dev/null 2>&1; }; then
  echo "rwa compliance evidence already current: $(soraswap_display_path "$latest_report")"
  exit 0
fi

if [[ "$rwa_release_enabled" != "1" ]]; then
  report_json="$(jq -cn \
    --arg generated_at "$timestamp" \
    --arg environment "$public_env" \
    --arg reason "public RWA market launch is disabled for this DEX release; no real-world asset lot, NAV source, or redemption terms are being launched" \
    --argjson chain_fingerprint "$chain_fingerprint_json" \
    '{
      generated_at: $generated_at,
      status: "not_applicable",
      environment: $environment,
      chain_fingerprint: $chain_fingerprint,
      rwa_release_enabled: false,
      reason: $reason
    }')"

  mkdir -p "$report_dir"
  soraswap_write_json_report_pair "$report_json" "$latest_report" "$timestamped_report"

  echo "rwa compliance evidence: not applicable"
  echo "evidence: $(soraswap_display_path "$latest_report")"
  exit 0
fi

rwa_validation_error="$(soraswap_validate_required_rwa_refs)" || fail_with_setup_hint "$rwa_validation_error"
issuer_approval_ref="$(soraswap_rwa_ref_value_for_field issuer_approval_ref)"
legal_review_ref="$(soraswap_rwa_ref_value_for_field legal_review_ref)"
compliance_policy_ref="$(soraswap_rwa_ref_value_for_field compliance_policy_ref)"
nav_source_ref="$(soraswap_rwa_ref_value_for_field nav_source_ref)"
redemption_terms_ref="$(soraswap_rwa_ref_value_for_field redemption_terms_ref)"
notes="$(soraswap_redact_sensitive_text "$(soraswap_trim_rwa_ref "$(soraswap_env_value SORASWAP_RWA_COMPLIANCE_NOTES)")")"

report_json="$(jq -cn \
  --arg generated_at "$timestamp" \
  --arg environment "$public_env" \
  --arg issuer_approval_ref "$issuer_approval_ref" \
  --arg legal_review_ref "$legal_review_ref" \
  --arg compliance_policy_ref "$compliance_policy_ref" \
  --arg nav_source_ref "$nav_source_ref" \
  --arg redemption_terms_ref "$redemption_terms_ref" \
  --arg notes "$notes" \
  --argjson chain_fingerprint "$chain_fingerprint_json" \
  '{
    generated_at: $generated_at,
    status: "completed",
    environment: $environment,
    chain_fingerprint: $chain_fingerprint,
    issuer_approval_ref: $issuer_approval_ref,
    legal_review_ref: $legal_review_ref,
    compliance_policy_ref: $compliance_policy_ref,
    nav_source_ref: $nav_source_ref,
    redemption_terms_ref: $redemption_terms_ref,
    notes: (if $notes == "" then null else $notes end)
  }')"

mkdir -p "$report_dir"
soraswap_write_json_report_pair "$report_json" "$latest_report" "$timestamped_report"

echo "rwa compliance evidence: completed"
echo "evidence: $(soraswap_display_path "$latest_report")"
