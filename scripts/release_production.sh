#!/bin/zsh
set -euo pipefail

ROOT="${SORASWAP_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
config="${SORASWAP_CLIENT_CONFIG:-${SORASWAP_PRODUCTION_CLIENT_CONFIG:-$ROOT/config/production/production.client.toml}}"
production_dir="$ROOT/deployments/production"
source "$ROOT/scripts/common.sh"
source "$ROOT/scripts/release_phase_guards.sh"

if [[ -n "${SORASWAP_TESTNET_CHAIN_ID+x}" ]]; then
  echo "release-production: retired environment variable is not supported: SORASWAP_TESTNET_CHAIN_ID" >&2
  exit 1
fi
if [[ -n "${SORASWAP_TESTNET_CHAIN_DISCRIMINANT+x}" ]]; then
  echo "release-production: retired environment variable is not supported: SORASWAP_TESTNET_CHAIN_DISCRIMINANT" >&2
  exit 1
fi

local_acceptance_pin_setting_count=0
[[ -n "${SORASWAP_LOCAL_ACCEPTANCE_IROHA_ROOT+x}" ]] && local_acceptance_pin_setting_count=$(( local_acceptance_pin_setting_count + 1 ))
[[ -n "${SORASWAP_LOCAL_ACCEPTANCE_BUNDLE_DIR+x}" ]] && local_acceptance_pin_setting_count=$(( local_acceptance_pin_setting_count + 1 ))
[[ -n "${SORASWAP_LOCAL_ACCEPTANCE_EXPECTED_GIT_SHA+x}" ]] && local_acceptance_pin_setting_count=$(( local_acceptance_pin_setting_count + 1 ))
local_acceptance_pin_iroha_root="${SORASWAP_LOCAL_ACCEPTANCE_IROHA_ROOT:-}"
local_acceptance_pin_bundle_dir="${SORASWAP_LOCAL_ACCEPTANCE_BUNDLE_DIR:-}"
local_acceptance_pin_expected_git_sha="${SORASWAP_LOCAL_ACCEPTANCE_EXPECTED_GIT_SHA:-}"
exact_candidate_pin_state=""
soraswap_rc_state=""
soraswap_rc_identity_json=""
soraswap_source_identity_json=""
production_cutover_policy="$ROOT/config/production/cutover-trust-policy.json"
production_cutover_approval="$ROOT/config/production/cutover-approval.json"
production_cutover_evidence="$production_dir/cutover_approval.latest.json"
production_cutover_approval_state=""
production_signer_authority=""
production_oracle_authority=""
production_admin_authority=""
production_treasury_authority=""
production_bridge_authority=""
production_minimum_fee_balance=""

fail() {
  echo "release-production: $*" >&2
  exit 1
}

print_setup_hint() {
  cat >&2 <<EOF

Required setup:
  cp config/production/production.client.toml.example config/production/production.client.toml
  # edit the copied file with real untracked production credentials
  export SORASWAP_CLIENT_CONFIG=config/production/production.client.toml
  export SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1
  export SORASWAP_RELEASE_EXPECTED_GIT_SHA=<signed-soraswap-rc-sha>
  export SORASWAP_LOCAL_ACCEPTANCE_IROHA_ROOT=<signed-iroha-candidate-root>
  export SORASWAP_LOCAL_ACCEPTANCE_BUNDLE_DIR=<verified-rollout-bundle-dir>
  export SORASWAP_LOCAL_ACCEPTANCE_EXPECTED_GIT_SHA=<signed-iroha-sha>
  export SORASWAP_PRODUCTION_MIN_FEE_BALANCE=<approved-canonical-minimum>
  export SORASWAP_PRODUCTION_ADMIN_AUTHORITY=<independent-admin-authority>
  export SORASWAP_PRODUCTION_TREASURY_AUTHORITY=<independent-treasury-authority>
  export SORASWAP_PRODUCTION_BRIDGE_AUTHORITY=<independent-bridge-authority>
  # The real trust policy is tracked in the signed RC; the approval is mode 0600 and ignored.
  cp config/production/cutover-approval.example.json config/production/cutover-approval.json
  # Replace every placeholder, then collect distinct security + operations sshsig signatures.
  cp config/production/production.client.toml.example config/production/oracle.client.toml
  # edit this second config with a distinct oracle signer on the same production chain and Torii endpoint
  chmod 600 config/production/oracle.client.toml
  export SORASWAP_ORACLE_CLIENT_CONFIG=config/production/oracle.client.toml
  # Required only when SORASWAP_ENABLE_RWA_RELEASE=1.
  export SORASWAP_ENABLE_RWA_RELEASE=1
  export SORASWAP_RWA_ISSUER_APPROVAL_REF=<external approval id or URL>
  export SORASWAP_RWA_LEGAL_REVIEW_REF=<external legal review id or URL>
  export SORASWAP_RWA_COMPLIANCE_POLICY_REF=<external compliance policy id or URL>
  export SORASWAP_RWA_NAV_SOURCE_REF=<external NAV source id or URL>
  export SORASWAP_RWA_REDEMPTION_TERMS_REF=<external redemption terms id or URL>
  SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make release-production

Both client configs are runtime-only secrets. RWA documents stay outside this repo; only their release references are recorded.
EOF
}

print_production_preflight_setup_summary() {
  local production_preflight="$production_dir/preflight.latest.json"
  local preflight_label
  local generated_at preflight_status

  preflight_label="$(soraswap_display_path "$production_preflight")"
  if [[ ! -s "$production_preflight" ]]; then
    echo "production setup summary: $preflight_label is missing" >&2
    echo "next production setup: SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make production-preflight" >&2
    return 0
  fi

  generated_at="$(jq -r '.generated_at // "unknown"' "$production_preflight" 2>/dev/null || echo "unknown")"
  preflight_status="$(jq -r '.status // "unknown"' "$production_preflight" 2>/dev/null || echo "unknown")"
  echo "production setup summary: $preflight_label status=$preflight_status generated_at=$generated_at" >&2
  soraswap_print_preflight_report_reasons "$production_preflight" "production"
}

fail_with_setup_hint() {
  echo "release-production: $*" >&2
  print_production_preflight_setup_summary
  print_setup_hint
  exit 1
}

require_production_rwa_refs_ready() {
  local validation_error

  [[ "$rwa_release_enabled" == "1" ]] || return 0
  validation_error="$(soraswap_validate_required_rwa_refs)" || fail_with_setup_hint "$validation_error"
}

abs_path() {
  local input_path="$1"
  local dir base
  dir="$(cd "$(dirname "$input_path")" && pwd)" || return 1
  base="$(basename "$input_path")"
  printf '%s/%s\n' "$dir" "$base"
}

require_artifacts() {
  local artifact
  for artifact in "$@"; do
    [[ -s "$artifact" ]] || fail "missing required evidence after target: $(soraswap_display_path "$artifact")"
  done
}

clear_inherited_soraswap_env() {
  local env_name

  for env_name in ${(k)parameters}; do
    if [[ "$env_name" == SORASWAP_* ]]; then
      unset "$env_name"
    fi
  done
  unset CHAIN
  unset ACCOUNT_CHAIN_DISCRIMINANT IROHA_ACCOUNT_CHAIN_DISCRIMINANT
}

clear_inherited_make_control_env() {
  unset MAKEFLAGS MFLAGS GNUMAKEFLAGS MAKEFILES MAKEOVERRIDES
}

clear_inherited_generic_chain_env() {
  unset CHAIN ACCOUNT_CHAIN_DISCRIMINANT IROHA_ACCOUNT_CHAIN_DISCRIMINANT
}

clear_inherited_internal_report_override_env() {
  unset SORASWAP_SMOKE_LATEST_REPORT SORASWAP_SMOKE_TIMESTAMPED_REPORT
}

require_taira_release_gate() {
  echo "release-production: verifying Taira release gate before production mutations"
  (
    unset SORASWAP_CLIENT_CONFIG SORASWAP_PRODUCTION_CLIENT_CONFIG
    unset RELEASE_CHECKLIST_INTERNAL_TOKEN
    unset RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_TOKEN RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_JOURNAL
    unset SORASWAP_TORII_URL SORASWAP_TORII_API_TOKEN CHAIN
    unset ACCOUNT_CHAIN_DISCRIMINANT IROHA_ACCOUNT_CHAIN_DISCRIMINANT
    unset SORASWAP_ALLOW_TESTNET_MUTATIONS SORASWAP_ALLOW_PRODUCTION_MUTATIONS
    unset SORASWAP_PROFILE SORASWAP_CONTRACTS_MANIFEST
    unset SORASWAP_IROHA_ROOT SORASWAP_IROHA_CLI_BIN SORASWAP_SORAFS_CLI_BIN
    unset SORASWAP_KOTO_COMPILE_BIN SORASWAP_KOTO_LINT_BIN SORASWAP_KOTO_TEST_BIN
    unset SORASWAP_ACTIVE_IROHA_CLI_BIN SORASWAP_ACTIVE_IVM_CONTRACT_DEPLOY_BIN
    unset SORASWAP_ACTIVE_GOV_INSTRUCTION_BIN SORASWAP_ACTIVE_SORAFS_CLI_BIN
    unset SORASWAP_SKIP_IROHA_DEV_TOOL_BUILD SORASWAP_SKIP_IROHA_CLI_BUILD
    unset SORASWAP_SKIP_KOTO_TOOL_BUILD SORASWAP_SKIP_LOCALNET_TOOL_BUILD SORASWAP_FORCE_COMPILE
    unset SORASWAP_KOTO_COMPILE_BIN_READY SORASWAP_KOTO_LINT_BIN_READY
    unset SORASWAP_PRODUCTION_CHAIN_ID SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT SORASWAP_CHAIN_DISCRIMINANT
    unset SORASWAP_CHAIN_FINGERPRINT_JSON
    unset SORASWAP_CHAIN_FINGERPRINT_ATTEMPTS SORASWAP_CHAIN_FINGERPRINT_SLEEP_SECS
    unset SORASWAP_BLOCK_HEIGHT_SAMPLE_ATTEMPTS
    unset SORASWAP_PUBLIC_PREFLIGHT_REPORT_DIR SORASWAP_TAIRA_PREFLIGHT_REPORT_DIR SORASWAP_PRODUCTION_PREFLIGHT_REPORT_DIR
    unset SORASWAP_TAIRA_PREFLIGHT_TIMEOUT_SECS SORASWAP_PUBLIC_PREFLIGHT_QUEUED_STALL_MAX_MS
    unset SORASWAP_TAIRA_DIRECT_VALIDATOR_HEALTH SORASWAP_TAIRA_DNS_RECORDS_JSON
    unset SORASWAP_TAIRA_DIRECT_TORII_HOST SORASWAP_TAIRA_DIRECT_TORII_PORTS
    unset SORASWAP_ISOLATED_LOCAL_UP_TIMEOUT_SECS SORASWAP_ISOLATED_DEPLOY_TIMEOUT_SECS
    unset SORASWAP_ISOLATED_SMOKE_TIMEOUT_SECS SORASWAP_ISOLATED_TESTNET_SMOKE_TIMEOUT_SECS
    unset SORASWAP_TESTNET_FEE_ASSET_DEFINITION_ID SORASWAP_TESTNET_FEE_ASSET_LABEL
    unset SORASWAP_PRODUCTION_FEE_ASSET_DEFINITION_ID SORASWAP_PRODUCTION_FEE_ASSET_LABEL
    unset SORASWAP_TAIRA_REPAIR_DONOR_STORAGE SORASWAP_TAIRA_REPAIR_HEIGHT SORASWAP_TAIRA_REPAIR_OPERATOR
    unset SORASWAP_TAIRA_REPAIR_PARENT_ROOT SORASWAP_TAIRA_REPAIR_POST_ROOT SORASWAP_TAIRA_REPAIR_REASON
    unset SORASWAP_TAIRA_REPAIR_PLATFORM SORASWAP_TAIRA_REPAIR_REPORT_DIR SORASWAP_TAIRA_REPAIR_SNAPSHOT_POLICY
    unset SORASWAP_TAIRA_REPAIR_STATUS_JSON SORASWAP_TAIRA_REPAIR_TARGET_STORAGES SORASWAP_TAIRA_REPAIR_TRACE_CONFIG
    unset SORASWAP_RELEASE_CHECKLIST_TAIRA_PREREQ_ONLY SORASWAP_RELEASE_CHECKLIST_INTERNAL_PRODUCTION_PREREQ
    unset SORASWAP_SKIP_PUBLIC_SIGNER_READY_CHECK SORASWAP_INIT_CONTRACT_STATE
    unset SORASWAP_PREFLIGHT_SKIP_EXISTING_NESTED_PROBE_CHECK
    unset SORASWAP_RUN_TESTNET_SMOKE SORASWAP_RUN_CONTRACT_CONSOLE_LIVE_SMOKE
    unset SORASWAP_ASSERT_BOOTSTRAP_STATE
    unset SORASWAP_CONTRACT_CONSOLE_LIVE_TORII_URL SORASWAP_TORII_READ_MAX_TIME_SECS
    unset SORASWAP_TORII_READ_RETRY_COUNT SORASWAP_TORII_READ_RETRY_DELAY_SECS
    unset SORASWAP_PUBLIC_TX_COMMITTED_WAIT_SECS SORASWAP_PUBLIC_TX_WAIT_QUEUED_STALL_MAX_MS
    unset SORASWAP_PUBLIC_CONTRACT_CALL_TRANSACTION_TTL_MS
    unset SORASWAP_CONTRACT_CALL_RETRY_COUNT SORASWAP_CONTRACT_CALL_RETRY_DELAY_SECS
    unset SORASWAP_CONTRACT_VIEW_EXPECT_RETRY_COUNT SORASWAP_CONTRACT_VIEW_EXPECT_RETRY_DELAY_SECS
    unset SORASWAP_PUBLIC_WRITE_HEALTH_QUEUE_MAX SORASWAP_PUBLIC_WRITE_HEALTH_QC_LAG_MAX SORASWAP_PUBLIC_WRITE_HEALTH_AGE_MAX_MS
    unset SORASWAP_PUBLIC_WRITE_HEALTH_RETRY_COUNT SORASWAP_PUBLIC_WRITE_HEALTH_RETRY_DELAY_SECS
    unset SORASWAP_PUBLIC_SUBMIT_HEALTH_RETRY_COUNT SORASWAP_PUBLIC_SUBMIT_HEALTH_RETRY_DELAY_SECS
    unset SORASWAP_CONTRACT_ALIAS_RESOLVE_RETRY_COUNT SORASWAP_CONTRACT_ALIAS_RESOLVE_RETRY_DELAY_SECS
    unset SORASWAP_BOOTSTRAP_SCOPE SORASWAP_DEPLOY_SCOPE SORASWAP_SMOKE_SCOPE
    unset SORASWAP_EXPECTED_TRIGGER_SCOPE
    unset SORASWAP_TRIGGER_LIFECYCLE_CADENCE_SLOTS SORASWAP_TRIGGER_LIFECYCLE_MAX_ITEMS SORASWAP_TRIGGER_LIFECYCLE_ENABLED
    unset SORASWAP_PERPS_TRIGGER_LIFECYCLE_MAX_ITEMS
    unset SORASWAP_DLMM_RANGE_GOVERNOR_CADENCE_SLOTS SORASWAP_DLMM_RANGE_GOVERNOR_MAX_FEE_PIPS
    unset SORASWAP_DLMM_RANGE_GOVERNOR_TARGET_ACTIVE_BIN SORASWAP_DLMM_RANGE_GOVERNOR_MAX_ACTIVE_BIN_DRIFT SORASWAP_DLMM_RANGE_GOVERNOR_ENABLED
    unset SORASWAP_TWAMM_TRIGGER_CADENCE_SLOTS SORASWAP_TWAMM_TRIGGER_MAX_ORDERS_PER_TICK SORASWAP_TWAMM_TRIGGER_ENABLED
    unset SORASWAP_PUBLIC_BOOTSTRAP SORASWAP_TESTNET_BOOTSTRAP SORASWAP_PRODUCTION_BOOTSTRAP
    unset SORASWAP_PUBLIC_DEPLOY_REUSE_CONTRACTS SORASWAP_TESTNET_DEPLOY_REUSE_CONTRACTS SORASWAP_PRODUCTION_DEPLOY_REUSE_CONTRACTS
    unset SORASWAP_PUBLIC_RUN_SUFFIX SORASWAP_TESTNET_RUN_SUFFIX SORASWAP_PRODUCTION_RUN_SUFFIX
    unset SORASWAP_PUBLIC_BRIDGE_ROUTE SORASWAP_PUBLIC_BRIDGE_MESSAGE_ID SORASWAP_PUBLIC_BRIDGE_RECENT_LIMIT
    unset SORASWAP_PUBLIC_BRIDGE_AUTO_SEED SORASWAP_PUBLIC_BRIDGE_NONCE SORASWAP_PUBLIC_BRIDGE_AMOUNT
    unset SORASWAP_PUBLIC_BRIDGE_SOURCE_DOMAIN SORASWAP_PUBLIC_BRIDGE_DEST_DOMAIN
    unset SORASWAP_PUBLIC_BRIDGE_ASSET_HOME_DOMAIN SORASWAP_PUBLIC_BRIDGE_ASSET_ID_CODEC
    unset SORASWAP_PUBLIC_BRIDGE_SENDER_CODEC SORASWAP_PUBLIC_BRIDGE_RECIPIENT_CODEC
    unset SORASWAP_PUBLIC_BRIDGE_ROUTE_ID_CODEC SORASWAP_PUBLIC_BRIDGE_ASSET_ID
    unset SORASWAP_PUBLIC_BRIDGE_SENDER SORASWAP_BRIDGE_ROUTE SORASWAP_SCCP_IVM_GAS_LIMIT
    unset SORASWAP_TESTNET_BRIDGE_ROUTE SORASWAP_TESTNET_BRIDGE_MESSAGE_ID SORASWAP_TESTNET_BRIDGE_RECENT_LIMIT
    unset SORASWAP_TESTNET_BRIDGE_AUTO_SEED SORASWAP_TESTNET_BRIDGE_NONCE SORASWAP_TESTNET_BRIDGE_AMOUNT
    unset SORASWAP_PRODUCTION_BRIDGE_ROUTE SORASWAP_PRODUCTION_BRIDGE_MESSAGE_ID SORASWAP_PRODUCTION_BRIDGE_RECENT_LIMIT
    unset SORASWAP_PRODUCTION_BRIDGE_AUTO_SEED SORASWAP_PRODUCTION_BRIDGE_NONCE SORASWAP_PRODUCTION_BRIDGE_AMOUNT
    unset SORASWAP_REQUIRE_STANDALONE_BRIDGE_PROOF
    unset SORASWAP_PUBLIC_XOR_TOPUP_MAX_ATTEMPTS SORASWAP_PUBLIC_XOR_TOPUP_MAX_USDT_IN SORASWAP_PUBLIC_XOR_TOPUP_BUFFER
    unset SORASWAP_TESTNET_XOR_TOPUP_MAX_ATTEMPTS SORASWAP_TESTNET_XOR_TOPUP_MAX_USDT_IN SORASWAP_TESTNET_XOR_TOPUP_BUFFER
    unset SORASWAP_PRODUCTION_XOR_TOPUP_MAX_ATTEMPTS SORASWAP_PRODUCTION_XOR_TOPUP_MAX_USDT_IN SORASWAP_PRODUCTION_XOR_TOPUP_BUFFER
    unset SORASWAP_TAIRA_ONBOARDING_TOKEN_FILE
    unset SORASWAP_ORACLE_CLIENT_CONFIG SORASWAP_LAST_ORACLE_SLOT
    unset SORASWAP_ACTIVE_ORACLE_CLIENT_CONFIG SORASWAP_ACTIVE_ORACLE_CLIENT_CONFIG_OWNED SORASWAP_ACTIVE_ORACLE_ACCOUNT
    unset SORASWAP_ENABLE_RWA_RELEASE
    unset SORASWAP_RWA_COMPLIANCE_CHAIN_JSON SORASWAP_RWA_COMPLIANCE_REPORT_DIR
    unset SORASWAP_RWA_COMPLIANCE_CHAIN_FILE SORASWAP_RWA_COMPLIANCE_PREFLIGHT_FILE
    unset SORASWAP_RWA_COMPLIANCE_NOTES
    unset SORASWAP_RWA_ISSUER_APPROVAL_REF SORASWAP_RWA_LEGAL_REVIEW_REF
    unset SORASWAP_RWA_COMPLIANCE_POLICY_REF SORASWAP_RWA_NAV_SOURCE_REF
    unset SORASWAP_RWA_REDEMPTION_TERMS_REF
    unset SORASWAP_TRADER_API_PROBE_ROOT SORASWAP_TRADER_API_PROBE_ATTEMPTS
    unset SORASWAP_TRADER_API_PROBE_INTERVAL_SECS SORASWAP_TRADER_API_PROBE_BODY_MAX_CHARS
    unset SORASWAP_TRADER_API_REGISTRY_VISIBILITY_ATTEMPTS SORASWAP_TRADER_API_REGISTRY_VISIBILITY_RETRY_DELAY_SECS
    unset SORASWAP_TRADER_API_GATEWAY_PROPAGATION_ATTEMPTS SORASWAP_TRADER_API_GATEWAY_PROPAGATION_RETRY_DELAY_SECS
    unset SORASWAP_TRADER_PUBLIC_RESPONSE_BODY_MAX_CHARS
    unset SORASWAP_TRADER_PUBLIC_ROUTE_PROBE_ATTEMPTS SORASWAP_TRADER_PUBLIC_ROUTE_PROBE_RETRY_DELAY_SECS
    unset SORASWAP_PUBLISH_TRADER_API_BINDING SORASWAP_TRADER_API_SERVICE_NAME
    unset SORASWAP_TRADER_API_APP_ID
    unset SORASWAP_TAIRA_TRON_XOR_DIAGNOSTIC_AMOUNT SORASWAP_TAIRA_TRON_XOR_ASSET_KEY
    unset SORASWAP_TAIRA_TRON_XOR_REMOTE_DOMAIN SORASWAP_TAIRA_TRON_XOR_ASSET_HOME_DOMAIN SORASWAP_TAIRA_TRON_XOR_ASSET_DECIMALS
    unset SORASWAP_TAIRA_TRON_XOR_GOVERNANCE_MESSAGE_ID SORASWAP_TAIRA_TRON_XOR_ROUTE_GAS_LIMIT
    unset SORASWAP_TAIRA_TRON_XOR_ROUTE_VIEW_ATTEMPTS SORASWAP_TAIRA_TRON_XOR_ROUTE_VIEW_RETRY_DELAY_SECS
    clear_inherited_soraswap_env
    clear_inherited_make_control_env
    if (( local_acceptance_pin_setting_count > 0 )); then
      export SORASWAP_LOCAL_ACCEPTANCE_IROHA_ROOT="$local_acceptance_pin_iroha_root"
      export SORASWAP_LOCAL_ACCEPTANCE_BUNDLE_DIR="$local_acceptance_pin_bundle_dir"
      export SORASWAP_LOCAL_ACCEPTANCE_EXPECTED_GIT_SHA="$local_acceptance_pin_expected_git_sha"
    fi
    if [[ "${rwa_release_enabled:-0}" == "1" ]]; then
      SORASWAP_ENABLE_RWA_RELEASE=1 SORASWAP_PUBLIC_ENV=testnet SORASWAP_RELEASE_ENV=testnet make -C "$ROOT" release-checklist
    else
      SORASWAP_PUBLIC_ENV=testnet SORASWAP_RELEASE_ENV=testnet make -C "$ROOT" release-checklist
    fi
  )
}

release_phase_index=0
release_phase_total=12
rwa_release_enabled="$(soraswap_rwa_release_enabled_setting_for_env production)" || exit 1
phase_journal="$ROOT/tmp/release-closeout/production.phase-journal.json"
phase_journal_token=""
typeset -a release_phase_targets
release_phase_targets=("${(@f)$(release_closeout_expected_phase_targets production)}")

run_target() {
  local target="$1"
  local artifact
  local missing_artifact
  local target_status
  local artifact_snapshot
  typeset -a artifacts
  shift
  artifacts=("$@")
  target_status=0

  require_exact_candidate_pin_settings
  require_soraswap_rc_identity
  require_production_cutover_approval_unchanged
  artifact_snapshot="$(release_phase_artifact_snapshot_json "$ROOT" "${artifacts[@]}")" || \
    fail "could not capture pre-phase artifact identity for $target"

  release_phase_index=$(( release_phase_index + 1 ))
  echo "release-production: [$release_phase_index/$release_phase_total] make $target"
  if (( ${#artifacts[@]} > 0 )); then
    echo "release-production: [$release_phase_index/$release_phase_total] expected evidence"
    for artifact in "${artifacts[@]}"; do
      echo "  - $(soraswap_display_path "$artifact")"
    done
  fi
  (
    clear_inherited_generic_chain_env
    clear_inherited_make_control_env
    clear_inherited_internal_report_override_env
    unset RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_TOKEN RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_JOURNAL
    if [[ "$target" == "production-nested-call-probe" ]]; then
      export SORASWAP_FORCE_NESTED_CALL_PROBE=1
    fi
    if [[ "$target" == "record-production-rwa-compliance" ]]; then
      export SORASWAP_FORCE_RWA_COMPLIANCE_REFRESH=1
    fi
    if [[ "$target" == "release-production-checklist" ]]; then
      run_production_cutover_observation
      release_phase_journal_state verify "$ROOT" production "$phase_journal" "${release_phase_targets[@]}" >/dev/null
      export RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_TOKEN="$phase_journal_token"
      export RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_JOURNAL="$phase_journal"
      zsh "$ROOT/scripts/release_production_checklist.sh" --prepare-status-doc-closeout "$phase_journal_token"
    else
      make -C "$ROOT" "$target"
    fi
  ) || target_status="$?"
  if (( target_status != 0 )); then
    missing_artifact=0
    for artifact in "${artifacts[@]}"; do
      [[ -s "$artifact" ]] || missing_artifact=1
    done
    if (( ${#artifacts[@]} > 0 && missing_artifact == 0 )); then
      release_phase_guard_verify_target "release-production" production "$production_dir" "$target" || true
    fi
    fail "phase $target failed with exit status $target_status"
  fi
  require_exact_candidate_pin_settings
  require_soraswap_rc_identity
  require_production_cutover_approval_unchanged
  release_phase_require_regenerated_artifacts "$ROOT" "$artifact_snapshot" "${artifacts[@]}" || \
    fail "phase $target did not regenerate its exact evidence artifacts"
  require_artifacts "${artifacts[@]}"
  release_phase_guard_verify_target "release-production" production "$production_dir" "$target" || \
    fail "phase $target produced non-release evidence"
  if (( release_phase_index <= 11 )); then
    release_phase_journal_state record "$ROOT" production "$phase_journal" \
      "$release_phase_index" "$target" "${artifacts[@]}" || \
      fail "could not record phase $target in the release phase journal"
  fi
  if (( ${#artifacts[@]} > 0 )); then
    echo "release-production: [$release_phase_index/$release_phase_total] evidence ready"
    for artifact in "${artifacts[@]}"; do
      echo "  - $(soraswap_display_path "$artifact")"
    done
  else
    echo "release-production: [$release_phase_index/$release_phase_total] $target completed"
  fi
}

verify_phase_count() {
  [[ "$release_phase_index" == "$release_phase_total" ]] || \
    fail "release phase count mismatch: ran $release_phase_index of $release_phase_total phases"
}

skip_public_signer_ready_check="${SORASWAP_SKIP_PUBLIC_SIGNER_READY_CHECK:-0}"
init_contract_state="${SORASWAP_INIT_CONTRACT_STATE:-1}"
skip_existing_nested_probe_check="${SORASWAP_PREFLIGHT_SKIP_EXISTING_NESTED_PROBE_CHECK:-0}"
resume_closeout="${SORASWAP_RELEASE_RESUME_CLOSEOUT:-0}"
soraswap_require_binary_integer_setting "SORASWAP_SKIP_PUBLIC_SIGNER_READY_CHECK" "$skip_public_signer_ready_check" || exit 1
soraswap_require_binary_integer_setting "SORASWAP_INIT_CONTRACT_STATE" "$init_contract_state" || exit 1
soraswap_require_binary_integer_setting "SORASWAP_PREFLIGHT_SKIP_EXISTING_NESTED_PROBE_CHECK" "$skip_existing_nested_probe_check" || exit 1
soraswap_require_binary_integer_setting "SORASWAP_RELEASE_RESUME_CLOSEOUT" "$resume_closeout" || exit 1
if [[ -n "${SORASWAP_RELEASE_CHECKLIST_TAIRA_PREREQ_ONLY+x}" || -n "${SORASWAP_RELEASE_CHECKLIST_INTERNAL_PRODUCTION_PREREQ+x}" ]]; then
  fail "release-checklist internal prerequisite flags cannot be exported for the production release gate"
fi
if [[ -n "${RELEASE_CHECKLIST_INTERNAL_TOKEN+x}" ]]; then
  fail "release-checklist internal prerequisite token cannot be exported for the production release gate"
fi
if [[ -n "${RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_TOKEN+x}" ]]; then
  fail "release-checklist internal closeout token cannot be exported for the production release gate"
fi
if [[ -n "${RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_JOURNAL+x}" ]]; then
  fail "release-checklist internal closeout journal cannot be exported for the production release gate"
fi
if [[ -n "${SORASWAP_INTERNAL_PRODUCTION_CUTOVER_APPROVAL_STATE_JSON+x}" ]]; then
  fail "internal production cutover approval state cannot be exported; release-production derives it from signed inputs"
fi
if [[ -n "${SORASWAP_TRADER_API_PROBE_ROOT+x}" ]]; then
  fail "SORASWAP_TRADER_API_PROBE_ROOT cannot override the approved same-origin production Torii CID probe"
fi

require_exact_candidate_pin_settings() {
  local current_state

  if (( local_acceptance_pin_setting_count != 3 )) \
    || [[ -z "$local_acceptance_pin_iroha_root" \
      || -z "$local_acceptance_pin_bundle_dir" \
      || -z "$local_acceptance_pin_expected_git_sha" ]]; then
    fail "full production release prepare/resume requires all three exact-candidate local acceptance pin settings"
  fi
  current_state="$(release_local_acceptance_pin_state_json \
    "$local_acceptance_pin_iroha_root" \
    "$local_acceptance_pin_bundle_dir" \
    "$local_acceptance_pin_expected_git_sha")" || \
    fail "exact-candidate local acceptance pin validation failed"
  if [[ -n "$exact_candidate_pin_state" && "$current_state" != "$exact_candidate_pin_state" ]]; then
    fail "exact-candidate local acceptance pin identity changed during the release"
  fi
  exact_candidate_pin_state="$current_state"
}

require_soraswap_rc_identity() {
  local current_state current_source_state

  [[ -n "${SORASWAP_RELEASE_EXPECTED_GIT_SHA:-}" ]] || \
    fail "full production release prepare/resume requires SORASWAP_RELEASE_EXPECTED_GIT_SHA"
  current_state="$(release_soraswap_rc_state_json "$ROOT" "$SORASWAP_RELEASE_EXPECTED_GIT_SHA")" || \
    fail "signed SoraSwap RC validation failed"
  current_source_state="$(release_closeout_source_state_json "$ROOT" production)" || \
    fail "SoraSwap release source differs from the signed RC"
  current_state="${current_state}|${current_source_state}"
  if [[ -n "$soraswap_rc_state" && "$current_state" != "$soraswap_rc_state" ]]; then
    fail "SoraSwap RC identity changed during the release"
  fi
  soraswap_rc_state="$current_state"
  soraswap_rc_identity_json="${current_state%%|*}"
  soraswap_source_identity_json="${current_state#*|}"
}

require_no_observation_test_controls() {
  local setting

  for setting in \
    SORASWAP_PRODUCTION_OBSERVATION_DURATION_SECS \
    SORASWAP_PRODUCTION_OBSERVATION_INTERVAL_SECS \
    SORASWAP_PRODUCTION_OBSERVATION_MINIMUM_SAMPLES \
    SORASWAP_PRODUCTION_OBSERVATION_FIXTURE \
    SORASWAP_PRODUCTION_OBSERVATION_TEST_MODE \
    SORASWAP_PRODUCTION_OBSERVATION_TEST_TOKEN \
    SORASWAP_PRODUCTION_OBSERVATION_SAMPLE_COMMAND; do
    if (( ${+parameters[$setting]} )); then
      fail "$setting is a test/duration override and cannot be exported for release-production"
    fi
  done
}

configure_production_cutover_inputs() {
  local evidence_mode="--write-evidence"
  local current_state

  [[ -f "$production_cutover_policy" ]] || \
    fail "missing RC-bound production trust policy: config/production/cutover-trust-policy.json"
  [[ -f "$production_cutover_approval" ]] || \
    fail "missing signed runtime approval: config/production/cutover-approval.json"
  [[ -s "$production_dir/chain.latest.json" ]] || \
    fail "missing production chain fingerprint; run make refresh-production-chain before approval signing"
  [[ -n "${SORASWAP_PRODUCTION_ADMIN_AUTHORITY:-}" ]] || \
    fail "SORASWAP_PRODUCTION_ADMIN_AUTHORITY is required by the signed cutover approval"
  [[ -n "${SORASWAP_PRODUCTION_TREASURY_AUTHORITY:-}" ]] || \
    fail "SORASWAP_PRODUCTION_TREASURY_AUTHORITY is required by the signed cutover approval"
  [[ -n "${SORASWAP_PRODUCTION_BRIDGE_AUTHORITY:-}" ]] || \
    fail "SORASWAP_PRODUCTION_BRIDGE_AUTHORITY is required by the signed cutover approval"

  production_signer_authority="$(
    SORASWAP_IROHA_ROOT="$local_acceptance_pin_iroha_root" \
    SORASWAP_IROHA_CLI_BIN="$local_acceptance_pin_bundle_dir/bin/iroha" \
    SORASWAP_SKIP_IROHA_CLI_BUILD=1 \
      authority_from_config "$config_abs"
  )" || fail "could not derive the production signer authority with the pinned iroha CLI"
  [[ -n "$production_signer_authority" ]] || fail "derived production signer authority is empty"
  [[ -n "$production_oracle_authority" ]] || fail "derived production oracle account is empty"
  production_admin_authority="$SORASWAP_PRODUCTION_ADMIN_AUTHORITY"
  production_treasury_authority="$SORASWAP_PRODUCTION_TREASURY_AUTHORITY"
  production_bridge_authority="$SORASWAP_PRODUCTION_BRIDGE_AUTHORITY"
  production_minimum_fee_balance="$(soraswap_production_min_fee_balance)" || \
    fail "missing approved production fee minimum"

  [[ ! -e "$production_cutover_evidence" && ! -L "$production_cutover_evidence" ]] || \
    evidence_mode="--verify-evidence"
  current_state="$(
    "$ROOT/scripts/verify_production_cutover_approval.sh" \
      --policy "$production_cutover_policy" \
      --approval "$production_cutover_approval" \
      --expected-soraswap-sha "$SORASWAP_RELEASE_EXPECTED_GIT_SHA" \
      --soraswap-rc-state-json "$soraswap_rc_identity_json" \
      --soraswap-source-state-json "$soraswap_source_identity_json" \
      --iroha-state-json "$exact_candidate_pin_state" \
      --chain-file "$production_dir/chain.latest.json" \
      --signer-authority "$production_signer_authority" \
      --oracle-authority "$production_oracle_authority" \
      --admin-authority "$production_admin_authority" \
      --treasury-authority "$production_treasury_authority" \
      --bridge-authority "$production_bridge_authority" \
      --minimum-fee-balance "$production_minimum_fee_balance" \
      "$evidence_mode" "$production_cutover_evidence"
  )" || fail "signed production cutover approval validation failed"
  production_cutover_approval_state="$current_state"
  export SORASWAP_INTERNAL_PRODUCTION_CUTOVER_APPROVAL_STATE_JSON="$current_state"
  release_phase_guard_require_no_sensitive_diagnostic_leaks \
    "release-production" "$production_cutover_evidence" || \
    fail "cutover approval evidence contains unredacted sensitive diagnostics"
}

require_production_cutover_approval_unchanged() {
  local current_state

  current_state="$(
    "$ROOT/scripts/verify_production_cutover_approval.sh" \
      --policy "$production_cutover_policy" \
      --approval "$production_cutover_approval" \
      --expected-soraswap-sha "$SORASWAP_RELEASE_EXPECTED_GIT_SHA" \
      --soraswap-rc-state-json "$soraswap_rc_identity_json" \
      --soraswap-source-state-json "$soraswap_source_identity_json" \
      --iroha-state-json "$exact_candidate_pin_state" \
      --chain-file "$production_dir/chain.latest.json" \
      --signer-authority "$production_signer_authority" \
      --oracle-authority "$production_oracle_authority" \
      --admin-authority "$production_admin_authority" \
      --treasury-authority "$production_treasury_authority" \
      --bridge-authority "$production_bridge_authority" \
      --minimum-fee-balance "$production_minimum_fee_balance" \
      --verify-evidence "$production_cutover_evidence"
  )" || fail "production cutover approval failed revalidation"
  [[ "$current_state" == "$production_cutover_approval_state" ]] || \
    fail "production cutover approval identity changed during the release"
  [[ "${SORASWAP_INTERNAL_PRODUCTION_CUTOVER_APPROVAL_STATE_JSON:-}" == "$production_cutover_approval_state" ]] || \
    fail "internal production cutover approval state changed during the release"
}

run_production_cutover_observation() {
  require_exact_candidate_pin_settings
  require_soraswap_rc_identity
  require_production_cutover_approval_unchanged
  "$ROOT/scripts/observe_production_cutover.sh" \
    --approval-state-json "$production_cutover_approval_state" \
    --client-config "$config_abs" \
    --chain-file "$production_dir/chain.latest.json" \
    --soraswap-rc-state-json "$soraswap_rc_identity_json" \
    --soraswap-source-state-json "$soraswap_source_identity_json" \
    --iroha-state-json "$exact_candidate_pin_state" \
    --deploy-file "$production_dir/deploy.latest.json" \
    --contracts-file "$production_dir/contracts.latest.json" \
    --trader-api-file "$production_dir/trader_api_bundle.latest.json" \
    --output "$production_dir/observation.latest.json" >/dev/null
  require_production_cutover_approval_unchanged
}

require_no_observation_test_controls

closeout_checkpoint="$ROOT/tmp/release-closeout/production.pending.json"
other_closeout_checkpoint="$ROOT/tmp/release-closeout/testnet.pending.json"
other_phase_journal="$ROOT/tmp/release-closeout/testnet.phase-journal.json"
if [[ -e "$other_closeout_checkpoint" || -L "$other_closeout_checkpoint" \
  || -e "$other_phase_journal" || -L "$other_phase_journal" ]]; then
  fail "Taira closeout state holds the global release lock"
fi
if [[ "$resume_closeout" == "1" ]]; then
  if [[ -e "$phase_journal" || -L "$phase_journal" ]]; then
    fail "phase journal remains beside the pending checkpoint: $(soraswap_display_path "$phase_journal"); inspect and remove only that stale journal before resume"
  fi
  [[ -e "$closeout_checkpoint" && ! -L "$closeout_checkpoint" ]] || \
    fail "pending production closeout checkpoint is missing or unsafe"
else
  if [[ -e "$closeout_checkpoint" || -L "$closeout_checkpoint" ]]; then
    fail "pending closeout checkpoint already exists: $(soraswap_display_path "$closeout_checkpoint"); resume it or remove it explicitly before a new full release"
  fi
  if [[ -e "$phase_journal" || -L "$phase_journal" ]]; then
    fail "release phase journal already exists: $(soraswap_display_path "$phase_journal"); inspect and remove only that exact failed-run journal before a new full release"
  fi
fi

soraswap_require_contract_source_hygiene "$ROOT" "release-production" || exit 1

[[ -f "$config" ]] || fail_with_setup_hint "real production client config not found: $(soraswap_display_path "$config")"
config_abs="$(abs_path "$config")"
[[ "$config_abs" == "$ROOT/config/production/production.client.toml" ]] || \
  fail_with_setup_hint "production release and observer require config/production/production.client.toml"
soraswap_require_secure_production_client_config "$config_abs" "$ROOT" || \
  fail_with_setup_hint "production client config failed secure file validation"
example_abs="$(abs_path "$ROOT/config/production/production.client.toml.example")"
testnet_default_abs="$(abs_path "$ROOT/config/testnet/taira.client.toml" 2>/dev/null || true)"
if [[ "$config_abs" == "$ROOT/config/testnet/"* || ( -n "$testnet_default_abs" && "$config_abs" == "$testnet_default_abs" ) ]]; then
  fail_with_setup_hint "refusing to use a Taira client config for the production release gate: $(soraswap_display_path "$config_abs")"
fi
[[ "$config_abs" != "$example_abs" ]] || fail_with_setup_hint "refusing to use the tracked example production config"
[[ "$config_abs" != *.example ]] || fail_with_setup_hint "refusing to use an example production config: $(soraswap_display_path "$config_abs")"
export SORASWAP_PUBLIC_ENV=production

if [[ "$config_abs" == "$ROOT/"* ]]; then
  config_rel="${config_abs#$ROOT/}"
  if git -C "$ROOT" ls-files --error-unmatch "$config_rel" >/dev/null 2>&1; then
    fail "production client config must be untracked: $config_rel"
  fi
fi

if soraswap_client_config_has_placeholder_values "$config_abs"; then
  fail_with_setup_hint "production client config still contains example credentials or local endpoints"
fi
production_chain_id="$(config_chain_id_from_config "$config_abs" 2>/dev/null || true)"
if [[ -z "$production_chain_id" ]]; then
  fail_with_setup_hint "production client config must provide chain or SORASWAP_PRODUCTION_CHAIN_ID"
fi
if production_taira_chain_blocker="$(production_client_config_taira_chain_blocker_message "$config_abs" 2>/dev/null || true)" \
  && [[ -n "$production_taira_chain_blocker" ]]; then
  fail_with_setup_hint "$production_taira_chain_blocker"
fi

if [[ "$resume_closeout" != "1" ]]; then
  [[ "${SORASWAP_ALLOW_PRODUCTION_MUTATIONS:-}" == "1" ]] || \
    fail_with_setup_hint "SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 is required for the full production release gate"
fi
[[ "$skip_public_signer_ready_check" != "1" ]] || \
  fail "SORASWAP_SKIP_PUBLIC_SIGNER_READY_CHECK is a debug bypass and cannot be used for the production release gate"
[[ "$init_contract_state" == "1" ]] || \
  fail "SORASWAP_INIT_CONTRACT_STATE=0 is a debug bypass and cannot be used for the production release gate"
[[ "$skip_existing_nested_probe_check" != "1" ]] || \
  fail "SORASWAP_PREFLIGHT_SKIP_EXISTING_NESTED_PROBE_CHECK is managed by the release runner and cannot be exported for the production release gate"
if soraswap_value_looks_placeholder "${SORASWAP_ORACLE_CLIENT_CONFIG:-}"; then
  fail "SORASWAP_ORACLE_CLIENT_CONFIG is an example value"
fi
if ! soraswap_prepare_oracle_client_config "$config_abs" >/dev/null; then
  fail_with_setup_hint "could not validate the separate typed-oracle client config"
fi
production_oracle_authority="$SORASWAP_ACTIVE_ORACLE_ACCOUNT"
soraswap_cleanup_oracle_client_config || fail "could not clean up typed-oracle client state"

require_production_rwa_refs_ready
require_exact_candidate_pin_settings
require_soraswap_rc_identity

export SORASWAP_CLIENT_CONFIG="$config_abs"
if [[ "$resume_closeout" != "1" ]]; then
  export SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1
else
  unset SORASWAP_ALLOW_PRODUCTION_MUTATIONS
fi
export SORASWAP_RELEASE_ENV=production
export SORASWAP_ENABLE_RWA_RELEASE="$rwa_release_enabled"

require_taira_release_gate
configure_production_cutover_inputs
require_production_cutover_approval_unchanged

if [[ "$resume_closeout" == "1" ]]; then
  internal_closeout_token="$(release_closeout_checkpoint_resume_token "$ROOT" production "$closeout_checkpoint")" || \
    fail "pending production closeout checkpoint is missing or invalid"
  echo "release-production: resuming fail-closed status-doc closeout; signed public phases and local E2E will not rerun"
  (
    clear_inherited_generic_chain_env
    clear_inherited_make_control_env
    unset RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_TOKEN RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_JOURNAL
    export RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_TOKEN="$internal_closeout_token"
    export SORASWAP_PUBLIC_ENV=production
    export SORASWAP_RELEASE_ENV=production
    zsh "$ROOT/scripts/release_production_checklist.sh" --resume-status-doc-closeout "$internal_closeout_token"
  ) || fail "status-doc closeout resume failed"
  require_exact_candidate_pin_settings
  require_soraswap_rc_identity
  require_production_cutover_approval_unchanged
  echo "release-production: completed all 12 release phases and strict status-doc closeout"
  exit 0
fi

phase_journal_token="$(release_phase_journal_state create "$ROOT" production "$phase_journal" "${release_phase_targets[@]}")" || \
  fail "could not create the production release phase journal"

SORASWAP_PREFLIGHT_SKIP_EXISTING_NESTED_PROBE_CHECK=1 run_target production-preflight \
  "$production_dir/preflight.latest.json"
SORASWAP_FORCE_NESTED_CALL_PROBE=1 run_target production-nested-call-probe \
  "$production_dir/chain.latest.json" \
  "$production_dir/nested_call_probe.latest.json"
run_target production-preflight \
  "$production_dir/preflight.latest.json"
run_target record-production-rwa-compliance \
  "$production_dir/rwa_compliance.latest.json"
run_target deploy-production \
  "$production_dir/deploy.latest.json" \
  "$production_dir/contracts.latest.json"
run_target smoke-production-readonly \
  "$production_dir/smoke.latest.json"
run_target smoke-production \
  "$production_dir/smoke.latest.json"
run_target test-contract-console-production \
  "$production_dir/contract_console_smoke.latest.json"
run_target smoke-production-trader-readonly \
  "$production_dir/trader_readonly.latest.json"
run_target smoke-production-trader \
  "$production_dir/trader.latest.json"
run_target publish-production-trader-api \
  "$production_dir/trader_api_bundle.latest.json"
run_target release-production-checklist \
  "$production_dir/observation.latest.json"

verify_phase_count
echo "release-production: all 12 phase bodies validated, but the release remains pending status-doc closeout"
echo "release-production: update only the tracked release status docs, then run SORASWAP_RELEASE_RESUME_CLOSEOUT=1 make release-production"
exit 3
