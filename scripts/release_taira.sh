#!/bin/zsh
set -euo pipefail

ROOT="${SORASWAP_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
config="${SORASWAP_CLIENT_CONFIG:-$ROOT/config/testnet/taira.client.toml}"
testnet_dir="$ROOT/deployments/testnet"
source "$ROOT/scripts/common.sh"
source "$ROOT/scripts/release_phase_guards.sh"
exact_candidate_pin_state=""
soraswap_rc_state=""

fail() {
  echo "release-taira: $*" >&2
  exit 1
}

print_setup_hint() {
  cat >&2 <<EOF

Required setup:
  cp config/testnet/taira.client.toml.example config/testnet/taira.client.toml
  # edit the copied file with real untracked Taira credentials
  export SORASWAP_CLIENT_CONFIG=config/testnet/taira.client.toml
  export SORASWAP_ALLOW_TESTNET_MUTATIONS=1
  cp config/testnet/taira.client.toml.example config/testnet/oracle.client.toml
  # edit this second config with a distinct oracle signer on the same Taira chain and Torii endpoint
  chmod 600 config/testnet/oracle.client.toml
  export SORASWAP_ORACLE_CLIENT_CONFIG=config/testnet/oracle.client.toml
  # Required only when SORASWAP_ENABLE_RWA_RELEASE=1.
  export SORASWAP_ENABLE_RWA_RELEASE=1
  export SORASWAP_RWA_ISSUER_APPROVAL_REF=<external approval id or URL>
  export SORASWAP_RWA_LEGAL_REVIEW_REF=<external legal review id or URL>
  export SORASWAP_RWA_COMPLIANCE_POLICY_REF=<external compliance policy id or URL>
  export SORASWAP_RWA_NAV_SOURCE_REF=<external NAV source id or URL>
  export SORASWAP_RWA_REDEMPTION_TERMS_REF=<external redemption terms id or URL>
  SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make release-taira

Both client configs are runtime-only secrets. RWA documents stay outside this repo; only their release references are recorded.
EOF
}

print_taira_preflight_setup_summary() {
  local taira_preflight="$testnet_dir/preflight.latest.json"
  local preflight_label
  local generated_at preflight_status

  preflight_label="$(soraswap_display_path "$taira_preflight")"
  if [[ ! -s "$taira_preflight" ]]; then
    echo "Taira setup summary: $preflight_label is missing" >&2
    echo "next Taira setup: SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make taira-preflight" >&2
    return 0
  fi

  generated_at="$(jq -r '.generated_at // "unknown"' "$taira_preflight" 2>/dev/null || echo "unknown")"
  preflight_status="$(jq -r '.status // "unknown"' "$taira_preflight" 2>/dev/null || echo "unknown")"
  echo "Taira setup summary: $preflight_label status=$preflight_status generated_at=$generated_at" >&2
  soraswap_print_preflight_report_reasons "$taira_preflight" "Taira"
}

fail_with_setup_hint() {
  echo "release-taira: $*" >&2
  print_taira_preflight_setup_summary
  print_setup_hint
  exit 1
}

require_taira_rwa_refs_ready() {
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

clear_inherited_make_control_env() {
  unset MAKEFLAGS MFLAGS GNUMAKEFLAGS MAKEFILES MAKEOVERRIDES
}

clear_inherited_generic_chain_env() {
  unset CHAIN ACCOUNT_CHAIN_DISCRIMINANT IROHA_ACCOUNT_CHAIN_DISCRIMINANT
}

clear_inherited_internal_report_override_env() {
  unset SORASWAP_SMOKE_LATEST_REPORT SORASWAP_SMOKE_TIMESTAMPED_REPORT
}

clear_inherited_public_deploy_override_env() {
  unset SORASWAP_PUBLIC_DEPLOY_REUSE_CONTRACTS
  unset SORASWAP_TESTNET_DEPLOY_REUSE_CONTRACTS SORASWAP_PRODUCTION_DEPLOY_REUSE_CONTRACTS
}

release_phase_index=0
release_phase_total=12
rwa_release_enabled="$(soraswap_rwa_release_enabled_setting_for_env testnet)" || exit 1
phase_journal="$ROOT/tmp/release-closeout/testnet.phase-journal.json"
phase_journal_token=""
typeset -a release_phase_targets
release_phase_targets=("${(@f)$(release_closeout_expected_phase_targets testnet)}")

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
  artifact_snapshot="$(release_phase_artifact_snapshot_json "$ROOT" "${artifacts[@]}")" || \
    fail "could not capture pre-phase artifact identity for $target"

  release_phase_index=$(( release_phase_index + 1 ))
  echo "release-taira: [$release_phase_index/$release_phase_total] make $target"
  if (( ${#artifacts[@]} > 0 )); then
    echo "release-taira: [$release_phase_index/$release_phase_total] expected evidence"
    for artifact in "${artifacts[@]}"; do
      echo "  - $(soraswap_display_path "$artifact")"
    done
  fi
  (
    clear_inherited_generic_chain_env
    clear_inherited_make_control_env
    clear_inherited_internal_report_override_env
    clear_inherited_public_deploy_override_env
    unset RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_TOKEN RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_JOURNAL
    if [[ "$target" == "testnet-nested-call-probe" ]]; then
      export SORASWAP_FORCE_NESTED_CALL_PROBE=1
    fi
    if [[ "$target" == "record-testnet-rwa-compliance" ]]; then
      export SORASWAP_FORCE_RWA_COMPLIANCE_REFRESH=1
    fi
    if [[ "$target" == "release-checklist" ]]; then
      release_phase_journal_state verify "$ROOT" testnet "$phase_journal" "${release_phase_targets[@]}" >/dev/null
      export RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_TOKEN="$phase_journal_token"
      export RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_JOURNAL="$phase_journal"
      zsh "$ROOT/scripts/release_checklist.sh" --prepare-status-doc-closeout "$phase_journal_token"
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
      release_phase_guard_verify_target "release-taira" testnet "$testnet_dir" "$target" || true
    fi
    fail "phase $target failed with exit status $target_status"
  fi
  require_exact_candidate_pin_settings
  require_soraswap_rc_identity
  release_phase_require_regenerated_artifacts "$ROOT" "$artifact_snapshot" "${artifacts[@]}" || \
    fail "phase $target did not regenerate its exact evidence artifacts"
  require_artifacts "${artifacts[@]}"
  release_phase_guard_verify_target "release-taira" testnet "$testnet_dir" "$target" || \
    fail "phase $target produced non-release evidence"
  if (( release_phase_index <= 11 )); then
    release_phase_journal_state record "$ROOT" testnet "$phase_journal" \
      "$release_phase_index" "$target" "${artifacts[@]}" || \
      fail "could not record phase $target in the release phase journal"
  fi
  if (( ${#artifacts[@]} > 0 )); then
    echo "release-taira: [$release_phase_index/$release_phase_total] evidence ready"
    for artifact in "${artifacts[@]}"; do
      echo "  - $(soraswap_display_path "$artifact")"
    done
  else
    echo "release-taira: [$release_phase_index/$release_phase_total] $target completed"
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
  fail "release-checklist internal prerequisite flags cannot be exported for the Taira release gate"
fi
if [[ -n "${RELEASE_CHECKLIST_INTERNAL_TOKEN+x}" ]]; then
  fail "release-checklist internal prerequisite token cannot be exported for the Taira release gate"
fi
if [[ -n "${RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_TOKEN+x}" ]]; then
  fail "release-checklist internal closeout token cannot be exported for the Taira release gate"
fi
if [[ -n "${RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_JOURNAL+x}" ]]; then
  fail "release-checklist internal closeout journal cannot be exported for the Taira release gate"
fi

require_exact_candidate_pin_settings() {
  local setting_count=0
  local current_state

  [[ -n "${SORASWAP_LOCAL_ACCEPTANCE_IROHA_ROOT+x}" ]] && setting_count=$(( setting_count + 1 ))
  [[ -n "${SORASWAP_LOCAL_ACCEPTANCE_BUNDLE_DIR+x}" ]] && setting_count=$(( setting_count + 1 ))
  [[ -n "${SORASWAP_LOCAL_ACCEPTANCE_EXPECTED_GIT_SHA+x}" ]] && setting_count=$(( setting_count + 1 ))
  if (( setting_count != 3 )) \
    || [[ -z "${SORASWAP_LOCAL_ACCEPTANCE_IROHA_ROOT:-}" \
      || -z "${SORASWAP_LOCAL_ACCEPTANCE_BUNDLE_DIR:-}" \
      || -z "${SORASWAP_LOCAL_ACCEPTANCE_EXPECTED_GIT_SHA:-}" ]]; then
    fail "full Taira release prepare/resume requires all three exact-candidate local acceptance pin settings"
  fi
  current_state="$(release_local_acceptance_pin_state_json \
    "$SORASWAP_LOCAL_ACCEPTANCE_IROHA_ROOT" \
    "$SORASWAP_LOCAL_ACCEPTANCE_BUNDLE_DIR" \
    "$SORASWAP_LOCAL_ACCEPTANCE_EXPECTED_GIT_SHA")" || \
    fail "exact-candidate local acceptance pin validation failed"
  if [[ -n "$exact_candidate_pin_state" && "$current_state" != "$exact_candidate_pin_state" ]]; then
    fail "exact-candidate local acceptance pin identity changed during the release"
  fi
  exact_candidate_pin_state="$current_state"
}

require_soraswap_rc_identity() {
  local current_state current_source_state

  [[ -n "${SORASWAP_RELEASE_EXPECTED_GIT_SHA:-}" ]] || \
    fail "full Taira release prepare/resume requires SORASWAP_RELEASE_EXPECTED_GIT_SHA"
  current_state="$(release_soraswap_rc_state_json "$ROOT" "$SORASWAP_RELEASE_EXPECTED_GIT_SHA")" || \
    fail "signed SoraSwap RC validation failed"
  current_source_state="$(release_closeout_source_state_json "$ROOT" testnet)" || \
    fail "SoraSwap release source differs from the signed RC"
  current_state="${current_state}|${current_source_state}"
  if [[ -n "$soraswap_rc_state" && "$current_state" != "$soraswap_rc_state" ]]; then
    fail "SoraSwap RC identity changed during the release"
  fi
  soraswap_rc_state="$current_state"
}

closeout_checkpoint="$ROOT/tmp/release-closeout/testnet.pending.json"
other_closeout_checkpoint="$ROOT/tmp/release-closeout/production.pending.json"
other_phase_journal="$ROOT/tmp/release-closeout/production.phase-journal.json"
if [[ -e "$other_closeout_checkpoint" || -L "$other_closeout_checkpoint" \
  || -e "$other_phase_journal" || -L "$other_phase_journal" ]]; then
  fail "production closeout state holds the global release lock"
fi
if [[ "$resume_closeout" == "1" ]]; then
  require_exact_candidate_pin_settings
  require_soraswap_rc_identity
  if [[ -e "$phase_journal" || -L "$phase_journal" ]]; then
    fail "phase journal remains beside the pending checkpoint: $(soraswap_display_path "$phase_journal"); inspect and remove only that stale journal before resume"
  fi
  internal_closeout_token="$(release_closeout_checkpoint_resume_token "$ROOT" testnet "$closeout_checkpoint")" || \
    fail "pending Taira closeout checkpoint is missing or invalid"
  echo "release-taira: resuming fail-closed status-doc closeout; signed public phases and local E2E will not rerun"
  (
    clear_inherited_generic_chain_env
    clear_inherited_make_control_env
    unset RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_TOKEN RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_JOURNAL
    export RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_TOKEN="$internal_closeout_token"
    export SORASWAP_PUBLIC_ENV=testnet
    export SORASWAP_RELEASE_ENV=testnet
    zsh "$ROOT/scripts/release_checklist.sh" --resume-status-doc-closeout "$internal_closeout_token"
  ) || fail "status-doc closeout resume failed"
  echo "release-taira: completed all 12 release phases and strict status-doc closeout"
  exit 0
fi
if [[ -e "$closeout_checkpoint" || -L "$closeout_checkpoint" ]]; then
  fail "pending closeout checkpoint already exists: $(soraswap_display_path "$closeout_checkpoint"); resume it or remove it explicitly before a new full release"
fi
if [[ -e "$phase_journal" || -L "$phase_journal" ]]; then
  fail "release phase journal already exists: $(soraswap_display_path "$phase_journal"); inspect and remove only that exact failed-run journal before a new full release"
fi

soraswap_require_contract_source_hygiene "$ROOT" "release-taira" || exit 1

[[ -f "$config" ]] || fail_with_setup_hint "real Taira client config not found: $(soraswap_display_path "$config")"
config_abs="$(abs_path "$config")"
example_abs="$(abs_path "$ROOT/config/testnet/taira.client.toml.example")"
production_default_abs="$(abs_path "$ROOT/config/production/production.client.toml" 2>/dev/null || true)"
if [[ "$config_abs" == "$ROOT/config/production/"* || ( -n "$production_default_abs" && "$config_abs" == "$production_default_abs" ) ]]; then
  fail_with_setup_hint "refusing to use a production client config for the Taira release gate: $(soraswap_display_path "$config_abs")"
fi
[[ "$config_abs" != "$example_abs" ]] || fail_with_setup_hint "refusing to use the tracked example Taira config"
[[ "$config_abs" != *.example ]] || fail_with_setup_hint "refusing to use an example Taira config: $(soraswap_display_path "$config_abs")"
export SORASWAP_PUBLIC_ENV=testnet

if [[ "$config_abs" == "$ROOT/"* ]]; then
  config_rel="${config_abs#$ROOT/}"
  if git -C "$ROOT" ls-files --error-unmatch "$config_rel" >/dev/null 2>&1; then
    fail "Taira client config must be untracked: $config_rel"
  fi
fi

if soraswap_client_config_has_placeholder_values "$config_abs"; then
  fail_with_setup_hint "Taira client config still contains example credentials or local endpoints"
fi
if taira_chain_blocker="$(testnet_client_config_unexpected_chain_blocker_message "$config_abs" 2>/dev/null || true)" \
  && [[ -n "$taira_chain_blocker" ]]; then
  fail_with_setup_hint "$taira_chain_blocker"
fi

[[ "${SORASWAP_ALLOW_TESTNET_MUTATIONS:-}" == "1" ]] || \
  fail_with_setup_hint "SORASWAP_ALLOW_TESTNET_MUTATIONS=1 is required for the full Taira release gate"
[[ "$skip_public_signer_ready_check" != "1" ]] || \
  fail "SORASWAP_SKIP_PUBLIC_SIGNER_READY_CHECK is a debug bypass and cannot be used for the Taira release gate"
[[ "$init_contract_state" == "1" ]] || \
  fail "SORASWAP_INIT_CONTRACT_STATE=0 is a debug bypass and cannot be used for the Taira release gate"
[[ "$skip_existing_nested_probe_check" != "1" ]] || \
  fail "SORASWAP_PREFLIGHT_SKIP_EXISTING_NESTED_PROBE_CHECK is managed by the release runner and cannot be exported for the Taira release gate"
if soraswap_value_looks_placeholder "${SORASWAP_ORACLE_CLIENT_CONFIG:-}"; then
  fail "SORASWAP_ORACLE_CLIENT_CONFIG is an example value"
fi
if ! soraswap_prepare_oracle_client_config "$config_abs" >/dev/null; then
  fail_with_setup_hint "could not validate the separate typed-oracle client config"
fi
soraswap_cleanup_oracle_client_config || fail "could not clean up typed-oracle client state"

require_taira_rwa_refs_ready
require_exact_candidate_pin_settings
require_soraswap_rc_identity

export SORASWAP_CLIENT_CONFIG="$config_abs"
export SORASWAP_ALLOW_TESTNET_MUTATIONS=1
export SORASWAP_RELEASE_ENV=testnet
export SORASWAP_ENABLE_RWA_RELEASE="$rwa_release_enabled"

phase_journal_token="$(release_phase_journal_state create "$ROOT" testnet "$phase_journal" "${release_phase_targets[@]}")" || \
  fail "could not create the Taira release phase journal"

SORASWAP_PREFLIGHT_SKIP_EXISTING_NESTED_PROBE_CHECK=1 run_target taira-preflight \
  "$testnet_dir/preflight.latest.json"
SORASWAP_FORCE_NESTED_CALL_PROBE=1 run_target testnet-nested-call-probe \
  "$testnet_dir/chain.latest.json" \
  "$testnet_dir/nested_call_probe.latest.json"
run_target taira-preflight \
  "$testnet_dir/preflight.latest.json"
run_target record-testnet-rwa-compliance \
  "$testnet_dir/rwa_compliance.latest.json"
run_target deploy-testnet \
  "$testnet_dir/deploy.latest.json" \
  "$testnet_dir/contracts.latest.json"
run_target smoke-testnet-readonly \
  "$testnet_dir/smoke.latest.json"
run_target smoke-testnet \
  "$testnet_dir/smoke.latest.json"
run_target test-contract-console-testnet \
  "$testnet_dir/contract_console_smoke.latest.json"
run_target smoke-testnet-trader-readonly \
  "$testnet_dir/trader_readonly.latest.json"
run_target smoke-testnet-trader \
  "$testnet_dir/trader.latest.json"
run_target publish-trader-api \
  "$testnet_dir/trader_api_bundle.latest.json"
run_target release-checklist

verify_phase_count
echo "release-taira: all 12 phase bodies validated, but the release remains pending status-doc closeout"
echo "release-taira: update only the tracked release status docs, then run SORASWAP_RELEASE_RESUME_CLOSEOUT=1 make release-taira"
exit 3
