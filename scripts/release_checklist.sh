#!/bin/zsh
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REQUESTED_ROOT="${SORASWAP_ROOT:-}"
source "$SCRIPT_ROOT/scripts/common.sh"
source "$SCRIPT_ROOT/scripts/release_phase_guards.sh"

if [[ -n "${SORASWAP_TESTNET_CHAIN_ID+x}" ]]; then
  echo "release checklist failed: retired environment variable is not supported: SORASWAP_TESTNET_CHAIN_ID" >&2
  exit 1
fi
if [[ -n "${SORASWAP_TESTNET_CHAIN_DISCRIMINANT+x}" ]]; then
  echo "release checklist failed: retired environment variable is not supported: SORASWAP_TESTNET_CHAIN_DISCRIMINANT" >&2
  exit 1
fi

internal_production_prereq_arg=0
internal_production_prereq_token=""
closeout_mode="normal"
closeout_arg_token=""
internal_closeout_token="${RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_TOKEN:-}"
internal_closeout_journal="${RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_JOURNAL:-}"
while (( $# > 0 )); do
  case "$1" in
    --internal-production-prereq)
      internal_production_prereq_arg=1
      shift
      if (( $# == 0 )); then
        echo "release checklist failed: --internal-production-prereq requires a token" >&2
        exit 1
      fi
      internal_production_prereq_token="$1"
      ;;
    --prepare-status-doc-closeout|--resume-status-doc-closeout)
      [[ "$closeout_mode" == "normal" ]] || {
        echo "release checklist failed: closeout mode may be selected only once" >&2
        exit 1
      }
      if [[ "$1" == "--prepare-status-doc-closeout" ]]; then
        closeout_mode="prepare"
      else
        closeout_mode="resume"
      fi
      shift
      if (( $# == 0 )); then
        echo "release checklist failed: --${closeout_mode}-status-doc-closeout requires a runner-owned capability" >&2
        exit 1
      fi
      closeout_arg_token="$1"
      ;;
    *)
      echo "release checklist failed: unsupported argument: $1" >&2
      exit 1
      ;;
  esac
  shift
done

if [[ "$closeout_mode" == "normal" ]]; then
  if [[ -n "$internal_closeout_token" || -n "$internal_closeout_journal" ]]; then
    echo "release checklist failed: internal closeout capability cannot be exported outside a release runner" >&2
    exit 1
  fi
else
  if [[ -z "$internal_closeout_token" || -z "$closeout_arg_token" \
    || "$internal_closeout_token" != "$closeout_arg_token" ]]; then
    echo "release checklist failed: ${closeout_mode} status-doc closeout requires a runner-owned capability" >&2
    exit 1
  fi
fi

ROOT="${REQUESTED_ROOT:-$SCRIPT_ROOT}"
register="$ROOT/docs/parity/migration_register.md"
public_env="${SORASWAP_RELEASE_ENV:-testnet}"
case "$public_env" in
  testnet|production)
    ;;
  *)
    echo "release-checklist only supports SORASWAP_RELEASE_ENV=testnet|production; got $public_env" >&2
    exit 1
    ;;
esac
if [[ -n "${SORASWAP_INTERNAL_PRODUCTION_CUTOVER_APPROVAL_STATE_JSON+x}" ]] \
  && [[ "$public_env" != "production" || "$closeout_mode" == "normal" ]]; then
  echo "release checklist failed: internal production cutover approval state is accepted only from the controlled production closeout runner" >&2
  exit 1
fi
evidence_dir="$ROOT/deployments/$public_env"
taira_prereq_only="$internal_production_prereq_arg"
if [[ -n "${SORASWAP_RELEASE_CHECKLIST_TAIRA_PREREQ_ONLY+x}" || -n "${SORASWAP_RELEASE_CHECKLIST_INTERNAL_PRODUCTION_PREREQ+x}" ]]; then
  echo "release checklist failed: internal production prerequisite flags cannot be exported; use make release-production-checklist" >&2
  exit 1
fi
if [[ "$taira_prereq_only" != "1" && -n "${RELEASE_CHECKLIST_INTERNAL_TOKEN+x}" ]]; then
  echo "release checklist failed: internal production prerequisite token cannot be exported; use make release-production-checklist" >&2
  exit 1
fi
if [[ "$taira_prereq_only" == "1" ]]; then
  if [[ -z "$internal_production_prereq_token" || -z "${RELEASE_CHECKLIST_INTERNAL_TOKEN:-}" || "$internal_production_prereq_token" != "$RELEASE_CHECKLIST_INTERNAL_TOKEN" ]]; then
    echo "release checklist failed: internal production prerequisite mode requires private token; use make release-production-checklist" >&2
    exit 1
  fi
fi
taira_release_gate_checked=0
case "$public_env" in
  testnet)
    public_display_label="Taira"
    ;;
  production)
    public_display_label="production"
    ;;
esac
rwa_release_enabled="$(soraswap_rwa_release_enabled_setting_for_env "$public_env")" || exit 1
rwa_release_enabled_json="$(soraswap_rwa_release_enabled_json_for_env "$public_env")" || exit 1

required_docs=(
  "$register"
  "$ROOT/docs/release/smart_contract_production_audit.md"
  "$ROOT/docs/release/production_readiness_checklist.md"
  "$ROOT/docs/release/taira_devex_critique.md"
  "$ROOT/docs/release/taira_operator_runbook.md"
  "$ROOT/docs/release/contract_console_security_review.md"
  "$ROOT/docs/release/contract_console_runbook.md"
)

required_preflight_evidence=(
  "$evidence_dir/chain.latest.json"
  "$evidence_dir/preflight.latest.json"
)

required_release_evidence=(
  "$evidence_dir/nested_call_probe.latest.json"
  "$evidence_dir/rwa_compliance.latest.json"
  "$evidence_dir/deploy.latest.json"
  "$evidence_dir/contracts.latest.json"
  "$evidence_dir/smoke.latest.json"
  "$evidence_dir/contract_console_smoke.latest.json"
  "$evidence_dir/trader_readonly.latest.json"
  "$evidence_dir/trader.latest.json"
  "$evidence_dir/trader_api_bundle.latest.json"
)

if [[ "$public_env" == "production" ]]; then
  required_release_evidence+=(
    "$evidence_dir/cutover_approval.latest.json"
    "$evidence_dir/observation.latest.json"
  )
fi

required_evidence=(
  "${required_preflight_evidence[@]}"
  "${required_release_evidence[@]}"
)

required_local_evidence=(
  "$ROOT/artifacts/telemetry/defi_2026_primitives_latest.json"
  "$ROOT/deployments/local/chain.latest.json"
  "$ROOT/deployments/local/deploy.latest.json"
  "$ROOT/deployments/local/contracts.latest.json"
  "$ROOT/deployments/local/smoke.latest.json"
)

required_taira_status_docs=(
  "$ROOT/docs/release/smart_contract_production_audit.md"
  "$ROOT/docs/release/production_readiness_checklist.md"
  "$ROOT/docs/release/taira_devex_critique.md"
)

required_production_status_docs=(
  "$ROOT/docs/release/smart_contract_production_audit.md"
  "$ROOT/docs/release/production_readiness_checklist.md"
)

required_local_telemetry_docs=(
  "$ROOT/docs/release/smart_contract_production_audit.md"
  "$ROOT/docs/release/production_readiness_checklist.md"
)

required_local_evidence_docs=(
  "$ROOT/docs/release/smart_contract_production_audit.md"
  "$ROOT/docs/release/production_readiness_checklist.md"
)

local_acceptance_targets=(
  check-shell-syntax
  test-public-env-helpers
  test-contract-console
  test-contract-console-ui
  test-contract-console-integration
  test-trader-ui
  lint
  compile
  dev-check
  dev-build
  dev-test
  dev-schema
  simulate-build
  simulate-smoke
  simulate-full
  test-local-foundation-isolated
  test-local-isolated
)

typeset -a non_ported_lines
ported_count=0
reference_only_count=0
local_doc_chain_generated_at=""
local_doc_deploy_generated_at=""
local_doc_contracts_generated_at=""
local_doc_smoke_generated_at=""
local_doc_telemetry_generated_at=""
local_acceptance_pin_enabled=0
local_acceptance_iroha_root=""
local_acceptance_bundle_dir=""
local_acceptance_expected_git_sha=""
local_acceptance_bundle_name=""
local_acceptance_kagami_bin=""
local_acceptance_checksums_sha256=""
local_acceptance_manifest_sha256=""
local_acceptance_iroha3d_sha256=""
local_acceptance_iroha_sha256=""
local_acceptance_kagami_sha256=""
local_acceptance_archive_sha256=""
local_acceptance_archive_sidecar_sha256=""
local_acceptance_pin_state_json=""
release_closeout_checkpoint="$ROOT/tmp/release-closeout/$public_env.pending.json"
release_closeout_phase_journal="$ROOT/tmp/release-closeout/$public_env.phase-journal.json"
if [[ "$public_env" == "testnet" ]]; then
  release_closeout_other_env="production"
else
  release_closeout_other_env="testnet"
fi
release_closeout_other_checkpoint="$ROOT/tmp/release-closeout/$release_closeout_other_env.pending.json"
release_closeout_other_journal="$ROOT/tmp/release-closeout/$release_closeout_other_env.phase-journal.json"
typeset -a release_closeout_expected_targets
release_closeout_expected_targets=("${(@f)$(release_closeout_expected_phase_targets "$public_env")}")

case "$closeout_mode" in
  normal)
    if [[ -e "$release_closeout_checkpoint" || -L "$release_closeout_checkpoint" \
      || -e "$release_closeout_phase_journal" || -L "$release_closeout_phase_journal" ]]; then
      echo "release checklist failed: pending closeout state exists; resume it or remove the exact inspected checkpoint/journal before a standalone checklist" >&2
      exit 1
    fi
    if [[ "$taira_prereq_only" != "1" ]] \
      && [[ -e "$release_closeout_other_checkpoint" || -L "$release_closeout_other_checkpoint" \
        || -e "$release_closeout_other_journal" || -L "$release_closeout_other_journal" ]]; then
      echo "release checklist failed: pending closeout state exists; resume it or remove the exact inspected checkpoint/journal before a standalone checklist" >&2
      exit 1
    fi
    ;;
  prepare)
    if [[ -e "$release_closeout_other_checkpoint" || -L "$release_closeout_other_checkpoint" \
      || -e "$release_closeout_other_journal" || -L "$release_closeout_other_journal" ]]; then
      echo "release checklist failed: $release_closeout_other_env closeout state holds the global release lock" >&2
      exit 1
    fi
    if [[ "$internal_closeout_journal" != "$release_closeout_phase_journal" ]]; then
      echo "release checklist failed: prepare status-doc closeout requires the selected runner phase journal" >&2
      exit 1
    fi
    if [[ -e "$release_closeout_checkpoint" || -L "$release_closeout_checkpoint" ]]; then
      echo "release checklist failed: closeout checkpoint already exists: $(soraswap_display_path "$release_closeout_checkpoint")" >&2
      exit 1
    fi
    journal_token="$(release_phase_journal_state verify "$ROOT" "$public_env" "$release_closeout_phase_journal" "${release_closeout_expected_targets[@]}")" || exit 1
    if [[ "$journal_token" != "$internal_closeout_token" ]]; then
      echo "release checklist failed: prepare status-doc closeout capability does not match the runner phase journal" >&2
      exit 1
    fi
    ;;
  resume)
    if [[ -e "$release_closeout_other_checkpoint" || -L "$release_closeout_other_checkpoint" \
      || -e "$release_closeout_other_journal" || -L "$release_closeout_other_journal" ]]; then
      echo "release checklist failed: $release_closeout_other_env closeout state holds the global release lock" >&2
      exit 1
    fi
    if [[ -n "$internal_closeout_journal" ]]; then
      echo "release checklist failed: resume status-doc closeout does not accept a phase-journal override" >&2
      exit 1
    fi
    if [[ -e "$release_closeout_phase_journal" || -L "$release_closeout_phase_journal" ]]; then
      echo "release checklist failed: a phase journal remains beside the pending checkpoint; inspect and remove only the stale journal before resume" >&2
      exit 1
    fi
    checkpoint_token="$(release_closeout_checkpoint_resume_token "$ROOT" "$public_env" "$release_closeout_checkpoint")" || exit 1
    if [[ "$checkpoint_token" != "$internal_closeout_token" ]]; then
      echo "release checklist failed: resume status-doc closeout capability does not match the pending checkpoint" >&2
      exit 1
    fi
    ;;
esac

release_closeout_checkpoint_state() {
  local action="$1"
  local pin_enabled="${2:-$local_acceptance_pin_enabled}"
  local verification_token="${3:-$closeout_arg_token}"
  local source_state_json rc_state_json cutover_approval_state_json
  local python_bin="${commands[python3]:-python3}"

  rc_state_json="$(release_soraswap_rc_state_json "$ROOT" "${SORASWAP_RELEASE_EXPECTED_GIT_SHA:-}")" || return 1
  source_state_json="$(release_closeout_source_state_json "$ROOT" "$public_env")" || return 1
  cutover_approval_state_json="${SORASWAP_INTERNAL_PRODUCTION_CUTOVER_APPROVAL_STATE_JSON:-}"

  "$python_bin" - \
    "$action" \
    "$ROOT" \
    "$public_env" \
    "$release_closeout_checkpoint" \
    "$rwa_release_enabled" \
    "$pin_enabled" \
    "$local_acceptance_expected_git_sha" \
    "$local_acceptance_bundle_name" \
    "$local_acceptance_checksums_sha256" \
    "$local_acceptance_manifest_sha256" \
    "$local_acceptance_iroha3d_sha256" \
    "$local_acceptance_iroha_sha256" \
    "$local_acceptance_kagami_sha256" \
    "$local_acceptance_archive_sha256" \
    "$local_acceptance_archive_sidecar_sha256" \
    "$rc_state_json" \
    "$cutover_approval_state_json" \
    "$source_state_json" \
    "$release_closeout_phase_journal" \
    "$verification_token" <<'PY'
import datetime as dt
import hashlib
import json
import os
import secrets
import stat
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath

(
    action,
    root_raw,
    environment,
    checkpoint_raw,
    rwa_release_enabled,
    pin_enabled,
    pin_git_sha,
    pin_bundle_name,
    pin_checksums_sha256,
    pin_manifest_sha256,
    pin_iroha3d_sha256,
    pin_iroha_sha256,
    pin_kagami_sha256,
    pin_archive_sha256,
    pin_archive_sidecar_sha256,
    rc_state_raw,
    cutover_approval_state_raw,
    source_state_raw,
    phase_journal_raw,
    closeout_token,
) = sys.argv[1:]

root_input = Path(os.path.abspath(root_raw))
checkpoint_input = Path(os.path.abspath(checkpoint_raw))
phase_journal_input = Path(os.path.abspath(phase_journal_raw))
root = root_input.resolve(strict=True)
checkpoint = root / "tmp" / "release-closeout" / f"{environment}.pending.json"
phase_journal = root / "tmp" / "release-closeout" / f"{environment}.phase-journal.json"
schema = "soraswap-release-closeout/v2"

if environment not in {"testnet", "production"}:
    raise SystemExit(f"release checklist failed: unsupported closeout environment {environment}")
if action not in {"write", "verify-base", "verify-all"}:
    raise SystemExit(f"release checklist failed: unsupported closeout checkpoint action {action}")

expected_checkpoint = root / "tmp" / "release-closeout" / f"{environment}.pending.json"
expected_journal = root / "tmp" / "release-closeout" / f"{environment}.phase-journal.json"
if checkpoint_input != root_input / "tmp" / "release-closeout" / f"{environment}.pending.json" \
        or phase_journal_input != root_input / "tmp" / "release-closeout" / f"{environment}.phase-journal.json":
    raise SystemExit("release checklist failed: closeout state path does not match the selected environment")

required_latest = [
    f"deployments/{environment}/chain.latest.json",
    f"deployments/{environment}/preflight.latest.json",
    f"deployments/{environment}/nested_call_probe.latest.json",
    f"deployments/{environment}/rwa_compliance.latest.json",
    f"deployments/{environment}/deploy.latest.json",
    f"deployments/{environment}/contracts.latest.json",
    f"deployments/{environment}/smoke.latest.json",
    f"deployments/{environment}/contract_console_smoke.latest.json",
    f"deployments/{environment}/trader_readonly.latest.json",
    f"deployments/{environment}/trader.latest.json",
    f"deployments/{environment}/trader_api_bundle.latest.json",
    "deployments/local/chain.latest.json",
    "deployments/local/deploy.latest.json",
    "deployments/local/contracts.latest.json",
    "deployments/local/smoke.latest.json",
    "artifacts/telemetry/defi_2026_primitives_latest.json",
]
if environment == "production":
    required_latest.extend([
        "deployments/production/cutover_approval.latest.json",
        "deployments/production/observation.latest.json",
    ])


def fail(message):
    raise SystemExit(f"release checklist failed: closeout checkpoint {message}")


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def aggregate(entries):
    digest = hashlib.sha256()
    for relative, content_hash in entries:
        digest.update(relative.encode("utf-8", errors="surrogateescape"))
        digest.update(b"\0")
        digest.update(content_hash.encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest()


def canonical_json_sha256(value):
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return sha256_bytes(encoded)


def read_regular_single_link(path, label):
    try:
        before = path.lstat()
    except OSError:
        fail(f"{label} is missing")
    if stat.S_ISLNK(before.st_mode) or not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        fail(f"{label} must be a regular non-symlink file with exactly one hard link")
    try:
        data = path.read_bytes()
        after = path.lstat()
    except OSError:
        fail(f"{label} changed while it was being read")
    if (before.st_dev, before.st_ino, before.st_mode, before.st_nlink, before.st_size) != (
            after.st_dev, after.st_ino, after.st_mode, after.st_nlink, after.st_size):
        fail(f"{label} changed while it was being read")
    return data


def evidence_state():
    evidence_paths = set()
    for base in (root / "deployments" / environment, root / "deployments" / "local"):
        if base.exists() or base.is_symlink():
            try:
                base_metadata = base.lstat()
            except OSError:
                fail(f"evidence directory is unreadable: {base.relative_to(root).as_posix()}")
            if stat.S_ISLNK(base_metadata.st_mode) or not stat.S_ISDIR(base_metadata.st_mode):
                fail(f"evidence directory must be a real directory: {base.relative_to(root).as_posix()}")
            evidence_paths.update(base.rglob("*.json"))
    telemetry = root / "artifacts" / "telemetry" / "defi_2026_primitives_latest.json"
    if telemetry.exists() or telemetry.is_symlink():
        evidence_paths.add(telemetry)

    entries = []
    evidence_contents = {}
    for path in sorted(evidence_paths):
        relative = path.relative_to(root).as_posix()
        content = read_regular_single_link(path, f"evidence file {relative}")
        evidence_contents[relative] = content
        entries.append((relative, sha256_bytes(content)))

    final_timestamps = {}
    for relative in required_latest:
        content = evidence_contents.get(relative)
        if content is None:
            content = read_regular_single_link(root / relative, f"required evidence {relative}")
        try:
            value = json.loads(content.decode("utf-8"))
        except (UnicodeError, json.JSONDecodeError):
            fail(f"required evidence is not valid JSON: {relative}")
        generated_at = value.get("generated_at")
        if not isinstance(generated_at, str) or not generated_at:
            fail(f"required evidence lacks generated_at: {relative}")
        final_timestamps[relative] = generated_at

    chain_path = root / f"deployments/{environment}/chain.latest.json"
    chain_relative = chain_path.relative_to(root).as_posix()
    try:
        chain = json.loads(evidence_contents[chain_relative].decode("utf-8"))
    except (KeyError, UnicodeError, json.JSONDecodeError):
        fail("chain.latest.json is not valid JSON")
    fingerprint = {
        "torii_url": chain.get("torii_url"),
        "chain": chain.get("chain"),
        "block_1_hash": chain.get("block_1_hash"),
        "generated_at": chain.get("generated_at"),
    }
    if not all(isinstance(value, str) and value for value in fingerprint.values()):
        fail("chain.latest.json lacks a complete chain fingerprint")

    return {
        "chain_fingerprint": fingerprint,
        "release_evidence_file_count": len(entries),
        "release_evidence_sha256": aggregate(entries),
        "final_generated_at": final_timestamps,
    }


def pin_state():
    enabled = pin_enabled == "1"
    state = {"pinned": enabled}
    if enabled:
        values = {
            "iroha_git_sha": pin_git_sha,
            "bundle_name": pin_bundle_name,
            "checksums_sha256": pin_checksums_sha256,
            "manifest_sha256": pin_manifest_sha256,
            "iroha3d_sha256": pin_iroha3d_sha256,
            "iroha_sha256": pin_iroha_sha256,
            "kagami_sha256": pin_kagami_sha256,
            "archive_sha256": pin_archive_sha256,
            "archive_sidecar_sha256": pin_archive_sidecar_sha256,
        }
        if not all(values.values()):
            fail("pinned local-acceptance provenance is incomplete")
        state.update(values)
    return state


def require_regular_0600(path, label):
    try:
        metadata = path.lstat()
    except OSError:
        fail(f"{label} is missing")
    if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        fail(f"{label} must be a regular non-symlink file")
    if stat.S_IMODE(metadata.st_mode) != 0o600 or metadata.st_nlink != 1:
        fail(f"{label} must have mode 0600 and exactly one hard link")
    return metadata


def load_phase_journal():
    require_regular_0600(phase_journal, "phase journal")
    try:
        value = json.loads(phase_journal.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("phase journal is not valid JSON")
    if not isinstance(value, dict):
        fail("phase journal must be a JSON object")
    integrity = value.pop("journal_sha256", None)
    if not isinstance(integrity, str) or integrity != canonical_json_sha256(value):
        fail("phase journal integrity hash does not match its contents")
    value["journal_sha256"] = integrity
    expected_targets = {
        "testnet": [
            "taira-preflight", "testnet-nested-call-probe", "taira-preflight",
            "record-testnet-rwa-compliance", "deploy-testnet", "smoke-testnet-readonly",
            "smoke-testnet", "test-contract-console-testnet", "smoke-testnet-trader-readonly",
            "smoke-testnet-trader", "publish-trader-api",
        ],
        "production": [
            "production-preflight", "production-nested-call-probe", "production-preflight",
            "record-production-rwa-compliance", "deploy-production", "smoke-production-readonly",
            "smoke-production", "test-contract-console-production", "smoke-production-trader-readonly",
            "smoke-production-trader", "publish-production-trader-api",
        ],
    }[environment]
    expected_artifacts = {
        "testnet": [
            ["deployments/testnet/preflight.latest.json"],
            ["deployments/testnet/chain.latest.json", "deployments/testnet/nested_call_probe.latest.json"],
            ["deployments/testnet/preflight.latest.json"],
            ["deployments/testnet/rwa_compliance.latest.json"],
            ["deployments/testnet/deploy.latest.json", "deployments/testnet/contracts.latest.json"],
            ["deployments/testnet/smoke.latest.json"],
            ["deployments/testnet/smoke.latest.json"],
            ["deployments/testnet/contract_console_smoke.latest.json"],
            ["deployments/testnet/trader_readonly.latest.json"],
            ["deployments/testnet/trader.latest.json"],
            ["deployments/testnet/trader_api_bundle.latest.json"],
        ],
        "production": [
            ["deployments/production/preflight.latest.json"],
            ["deployments/production/chain.latest.json", "deployments/production/nested_call_probe.latest.json"],
            ["deployments/production/preflight.latest.json"],
            ["deployments/production/rwa_compliance.latest.json"],
            ["deployments/production/deploy.latest.json", "deployments/production/contracts.latest.json"],
            ["deployments/production/smoke.latest.json"],
            ["deployments/production/smoke.latest.json"],
            ["deployments/production/contract_console_smoke.latest.json"],
            ["deployments/production/trader_readonly.latest.json"],
            ["deployments/production/trader.latest.json"],
            ["deployments/production/trader_api_bundle.latest.json"],
        ],
    }[environment]
    if value.get("schema") != "soraswap-release-phase-journal/v1" or value.get("environment") != environment:
        fail("phase journal schema or environment does not match")
    if value.get("run_id") != closeout_token:
        fail("phase journal capability does not match the release runner")
    if value.get("expected_targets") != expected_targets:
        fail("phase journal target order does not match the release runner")
    if value.get("soraswap_rc") != rc_state_value:
        fail("phase journal signed SoraSwap RC identity does not match the checkpoint")
    if value.get("production_cutover_approval") != cutover_approval_state_value:
        fail("phase journal production cutover approval does not match the checkpoint")
    if value.get("source") != source_state_value:
        fail("phase journal source identity does not match the checkpoint source")
    receipt_root = root / "tmp" / "release-closeout" / f"{environment}.phase-receipts"
    if value.get("receipt_dir") != receipt_root.relative_to(root).as_posix():
        fail("phase journal receipt directory does not match the release runner")
    try:
        receipt_root_metadata = receipt_root.lstat()
    except OSError:
        fail("phase journal receipt directory is missing")
    if stat.S_ISLNK(receipt_root_metadata.st_mode) or not stat.S_ISDIR(receipt_root_metadata.st_mode) \
            or stat.S_IMODE(receipt_root_metadata.st_mode) != 0o700:
        fail("phase journal receipt directory must be a real mode-0700 directory")
    phases = value.get("phases")
    if not isinstance(phases, list) or len(phases) != len(expected_targets):
        fail("phase journal does not contain eleven completed phase receipts")
    seen_receipts = set()
    receipt_values = {}
    for index, (phase, target, expected_sources) in enumerate(
            zip(phases, expected_targets, expected_artifacts), start=1):
        if not isinstance(phase, dict) or phase.get("index") != index or phase.get("target") != target:
            fail("phase journal completed order is invalid")
        if not isinstance(phase.get("evidence"), list) \
                or len(phase["evidence"]) != len(expected_sources):
            fail("phase journal evidence receipt is missing")
        for receipt_index, (receipt, expected_source) in enumerate(
                zip(phase["evidence"], expected_sources), start=1):
            if not isinstance(receipt, dict) or not isinstance(receipt.get("path"), str) \
                    or not isinstance(receipt.get("source_path"), str):
                fail("phase journal evidence receipt is malformed")
            raw_receipt_path = receipt["path"]
            normalized = PurePosixPath(raw_receipt_path)
            receipt_path = receipt_root / f"phase{index:02d}-artifact{receipt_index:02d}.json"
            expected_relative = receipt_path.relative_to(root).as_posix()
            if normalized.is_absolute() \
                    or any(part in {"", ".", ".."} for part in normalized.parts) \
                    or normalized.as_posix() != raw_receipt_path \
                    or raw_receipt_path != expected_relative \
                    or raw_receipt_path in seen_receipts:
                fail("phase journal evidence receipt path is unsafe, duplicate, or misnumbered")
            if receipt["source_path"] != expected_source:
                fail("phase journal evidence receipt source does not match its phase artifact mapping")
            seen_receipts.add(raw_receipt_path)
            receipt_metadata = require_regular_0600(receipt_path, "phase journal evidence receipt")
            try:
                receipt_bytes = receipt_path.read_bytes()
                receipt_after = receipt_path.lstat()
                receipt_json = json.loads(receipt_bytes.decode("utf-8"))
            except (OSError, UnicodeError, json.JSONDecodeError):
                fail("phase journal evidence receipt is not valid JSON")
            receipt_generated_at = receipt_json.get("generated_at") if isinstance(receipt_json, dict) else None
            if (receipt_metadata.st_dev, receipt_metadata.st_ino, receipt_metadata.st_mode,
                    receipt_metadata.st_nlink, receipt_metadata.st_size) != (
                    receipt_after.st_dev, receipt_after.st_ino, receipt_after.st_mode,
                    receipt_after.st_nlink, receipt_after.st_size):
                fail("phase journal evidence receipt changed while it was read")
            if sha256_bytes(receipt_bytes) != receipt.get("sha256") \
                    or receipt_generated_at != receipt.get("generated_at"):
                fail("phase journal evidence receipt no longer matches its recorded hash and timestamp")
            receipt_values[(index, receipt_index)] = receipt_json

    def chain_fingerprint(receipt_value):
        if not isinstance(receipt_value, dict):
            return None
        candidate = receipt_value.get("chain_fingerprint")
        if not isinstance(candidate, dict):
            chain_state = receipt_value.get("chain")
            if isinstance(chain_state, dict):
                candidate = chain_state.get("fingerprint")
            else:
                candidate = receipt_value
        if not isinstance(candidate, dict):
            return None
        fingerprint = {
            "torii_url": candidate.get("torii_url"),
            "chain": candidate.get("chain"),
            "block_1_hash": candidate.get("block_1_hash"),
        }
        if not all(isinstance(item, str) and item for item in fingerprint.values()):
            return None
        return fingerprint

    canonical_fingerprint = chain_fingerprint(receipt_values.get((2, 1)))
    if canonical_fingerprint is None:
        fail("phase journal chain receipt lacks a complete fingerprint")
    for key, receipt_value in receipt_values.items():
        if chain_fingerprint(receipt_value) != canonical_fingerprint:
            fail(f"phase journal phase {key[0]} artifact {key[1]} has a different chain fingerprint")
    deploy_receipt = receipt_values.get((5, 1))
    contracts_receipt = receipt_values.get((5, 2))
    deploy_generated_at = deploy_receipt.get("generated_at") if isinstance(deploy_receipt, dict) else None
    contracts_generated_at = contracts_receipt.get("generated_at") if isinstance(contracts_receipt, dict) else None
    if not isinstance(deploy_generated_at, str) or not isinstance(contracts_generated_at, str):
        fail("phase journal deploy/contracts receipts lack generated_at identity")
    for (phase_number, artifact_number), receipt_value in receipt_values.items():
        if phase_number < 6:
            continue
        deploy_snapshot = receipt_value.get("deploy_snapshot") if isinstance(receipt_value, dict) else None
        contracts_snapshot = receipt_value.get("contracts_snapshot") if isinstance(receipt_value, dict) else None
        if not isinstance(deploy_snapshot, dict) or deploy_snapshot.get("generated_at") != deploy_generated_at \
                or chain_fingerprint(deploy_snapshot) != canonical_fingerprint:
            fail(f"phase journal phase {phase_number} artifact {artifact_number} does not bind the deploy snapshot")
        if not isinstance(contracts_snapshot, dict) or contracts_snapshot.get("generated_at") != contracts_generated_at \
                or chain_fingerprint(contracts_snapshot) != canonical_fingerprint:
            fail(f"phase journal phase {phase_number} artifact {artifact_number} does not bind the contracts snapshot")
    return value


try:
    source_state_value = json.loads(source_state_raw)
    rc_state_value = json.loads(rc_state_raw)
except json.JSONDecodeError:
    fail("source or signed RC state is not valid JSON")
if not isinstance(source_state_value, dict) or not isinstance(rc_state_value, dict):
    fail("source and signed RC state must be JSON objects")
if environment == "production":
    try:
        cutover_approval_state_value = json.loads(cutover_approval_state_raw)
    except json.JSONDecodeError:
        fail("production closeout requires verified cutover approval state")
    if not isinstance(cutover_approval_state_value, dict) \
            or cutover_approval_state_value.get("schema") != "soraswap-production-cutover-approval-state/v1":
        fail("production cutover approval state is invalid")
elif cutover_approval_state_raw:
    fail("Taira closeout does not accept production cutover approval state")
else:
    cutover_approval_state_value = None


stored = None
if action != "write":
    checkpoint_metadata = require_regular_0600(checkpoint, "checkpoint")
    try:
        checkpoint_bytes = checkpoint.read_bytes()
        checkpoint_after = checkpoint.lstat()
        stored = json.loads(checkpoint_bytes.decode("utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("is not valid JSON")
    if (checkpoint_metadata.st_dev, checkpoint_metadata.st_ino, checkpoint_metadata.st_mode,
            checkpoint_metadata.st_nlink, checkpoint_metadata.st_size) != (
            checkpoint_after.st_dev, checkpoint_after.st_ino, checkpoint_after.st_mode,
            checkpoint_after.st_nlink, checkpoint_after.st_size):
        fail("changed while it was being read")
    if not isinstance(stored, dict):
        fail("must be a JSON object")
    stored_integrity = stored.pop("checkpoint_sha256", None)
    if not isinstance(stored_integrity, str) or stored_integrity != canonical_json_sha256(stored):
        fail("integrity hash does not match its contents")
    stored_token = stored.pop("resume_token", None)
    if not isinstance(stored_token, str) or stored_token != closeout_token:
        fail("resume capability does not match the checkpoint")
    stored.pop("created_at", None)

current = {
    "schema": schema,
    "status": "pending_status_docs",
    "environment": environment,
    "rwa_release_enabled": rwa_release_enabled == "1",
    "soraswap_rc": rc_state_value,
    "production_cutover_approval": cutover_approval_state_value,
    "source": source_state_value,
    "evidence": evidence_state(),
    "local_acceptance": pin_state(),
}

if action == "write":
    if pin_enabled != "1":
        fail("exact-candidate local acceptance must be pinned")
    if checkpoint.exists() or checkpoint.is_symlink():
        fail(f"already exists: {checkpoint.relative_to(root).as_posix()}")
    checkpoint.parent.mkdir(parents=True, exist_ok=True)
    if checkpoint.parent.is_symlink() or checkpoint.parent.resolve(strict=True) != expected_checkpoint.parent:
        fail("checkpoint parent must be a real release-worktree directory")
    current["phase_journal"] = load_phase_journal()
    payload = dict(current)
    payload["created_at"] = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    payload["resume_token"] = secrets.token_hex(32)
    payload["checkpoint_sha256"] = canonical_json_sha256(payload)
    fd, temporary_raw = tempfile.mkstemp(prefix=f".{environment}.", suffix=".tmp", dir=checkpoint.parent)
    temporary = Path(temporary_raw)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            json.dump(payload, output, indent=2, sort_keys=True)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        try:
            os.link(temporary, checkpoint)
        except FileExistsError:
            fail(f"already exists: {checkpoint.relative_to(root).as_posix()}")
        temporary.unlink()
        directory_fd = os.open(checkpoint.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if temporary.exists():
            temporary.unlink()
    print(payload["resume_token"])
    raise SystemExit(0)

if action != "write":
    current["phase_journal"] = stored.get("phase_journal")

if action == "verify-base":
    stored.pop("local_acceptance", None)
    current.pop("local_acceptance", None)

if stored != current:
    for key in ("schema", "status", "environment", "rwa_release_enabled", "soraswap_rc", "production_cutover_approval", "source", "evidence", "local_acceptance", "phase_journal"):
        if stored.get(key) != current.get(key):
            fail(f"does not match current {key.replace('_', ' ')}")
    fail("does not match the prepared release state")

print(checkpoint.relative_to(root).as_posix())
PY
}

remove_release_closeout_checkpoint() {
  local current_token

  current_token="$(release_closeout_checkpoint_resume_token "$ROOT" "$public_env" "$release_closeout_checkpoint")" || return 1
  [[ "$current_token" == "$closeout_arg_token" ]] || {
    echo "release checklist failed: closeout checkpoint capability changed before completion" >&2
    return 1
  }
  release_closeout_checkpoint_remove \
    "$ROOT" "$public_env" "$release_closeout_checkpoint" "$closeout_arg_token" || return 1
  [[ ! -e "$release_closeout_checkpoint" && ! -L "$release_closeout_checkpoint" ]] || {
    echo "release checklist failed: closeout checkpoint could not be removed after completion" >&2
    return 1
  }
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

clear_inherited_iroha_tool_env() {
  local env_name

  for env_name in ${(k)parameters}; do
    case "$env_name" in
      IROHA*|KAGAMI*)
        unset "$env_name"
        ;;
    esac
  done
}

clear_inherited_make_control_env() {
  unset MAKEFLAGS MFLAGS GNUMAKEFLAGS MAKEFILES MAKEOVERRIDES
}

trim_whitespace() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

local_acceptance_target_uses_candidate() {
  case "$1" in
    lint|compile|dev-check|dev-build|dev-test|dev-schema|test-local-foundation-isolated|test-local-isolated)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

local_acceptance_target_is_isolated() {
  case "$1" in
    test-local-foundation-isolated|test-local-isolated)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

verify_local_acceptance_pin_unchanged() {
  local context="$1"
  local current_state

  [[ "$local_acceptance_pin_enabled" == "1" ]] || return 0
  if ! current_state="$(release_local_acceptance_pin_state_json \
    "$local_acceptance_iroha_root" \
    "$local_acceptance_bundle_dir" \
    "$local_acceptance_expected_git_sha")"; then
    echo "release checklist failed: pinned local acceptance inputs failed revalidation $context" >&2
    return 1
  fi
  if [[ "$current_state" != "$local_acceptance_pin_state_json" ]]; then
    echo "release checklist failed: pinned local acceptance identity changed $context" >&2
    return 1
  fi
}

configure_local_acceptance_pin() {
  local root_set=0 bundle_set=0 sha_set=0 setting_count=0
  local requested_root requested_bundle expected_git_sha pin_state

  [[ -n "${SORASWAP_LOCAL_ACCEPTANCE_IROHA_ROOT+x}" ]] && root_set=1
  [[ -n "${SORASWAP_LOCAL_ACCEPTANCE_BUNDLE_DIR+x}" ]] && bundle_set=1
  [[ -n "${SORASWAP_LOCAL_ACCEPTANCE_EXPECTED_GIT_SHA+x}" ]] && sha_set=1
  setting_count=$(( root_set + bundle_set + sha_set ))
  if (( setting_count != 0 && setting_count != 3 )); then
    echo "release checklist failed: SORASWAP_LOCAL_ACCEPTANCE_IROHA_ROOT, SORASWAP_LOCAL_ACCEPTANCE_BUNDLE_DIR, and SORASWAP_LOCAL_ACCEPTANCE_EXPECTED_GIT_SHA must be set together" >&2
    return 1
  fi
  (( setting_count != 0 )) || return 0

  requested_root="${SORASWAP_LOCAL_ACCEPTANCE_IROHA_ROOT:-}"
  requested_bundle="${SORASWAP_LOCAL_ACCEPTANCE_BUNDLE_DIR:-}"
  expected_git_sha="${SORASWAP_LOCAL_ACCEPTANCE_EXPECTED_GIT_SHA:-}"
  if ! pin_state="$(release_local_acceptance_pin_state_json \
    "$requested_root" "$requested_bundle" "$expected_git_sha")"; then
    echo "release checklist failed: exact-candidate local acceptance pin validation failed" >&2
    return 1
  fi
  local_acceptance_pin_state_json="$pin_state"
  local_acceptance_iroha_root="$(jq -r '.iroha_root' <<<"$pin_state")"
  local_acceptance_bundle_dir="$(jq -r '.bundle_dir' <<<"$pin_state")"
  local_acceptance_expected_git_sha="$(jq -r '.iroha_git_sha' <<<"$pin_state")"
  local_acceptance_bundle_name="$(jq -r '.bundle_name' <<<"$pin_state")"
  local_acceptance_kagami_bin="$local_acceptance_iroha_root/target/release/kagami"
  local_acceptance_checksums_sha256="$(jq -r '.checksums_sha256' <<<"$pin_state")"
  local_acceptance_manifest_sha256="$(jq -r '.manifest_sha256' <<<"$pin_state")"
  local_acceptance_iroha3d_sha256="$(jq -r '.iroha3d_sha256' <<<"$pin_state")"
  local_acceptance_iroha_sha256="$(jq -r '.iroha_sha256' <<<"$pin_state")"
  local_acceptance_kagami_sha256="$(jq -r '.kagami_sha256' <<<"$pin_state")"
  local_acceptance_archive_sha256="$(jq -r '.archive_sha256' <<<"$pin_state")"
  local_acceptance_archive_sidecar_sha256="$(jq -r '.archive_sidecar_sha256' <<<"$pin_state")"
  local_acceptance_pin_enabled=1
  verify_local_acceptance_pin_unchanged "during initial validation"
}

export_local_acceptance_pin_for_target() {
  local target="$1"

  [[ "$local_acceptance_pin_enabled" == "1" ]] || return 0
  local_acceptance_target_uses_candidate "$target" || return 0

  export SORASWAP_IROHA_ROOT="$local_acceptance_iroha_root"
  export SORASWAP_IROHA_CLI_BIN="$local_acceptance_bundle_dir/bin/iroha"
  export SORASWAP_SKIP_IROHA_CLI_BUILD=1
  if local_acceptance_target_is_isolated "$target"; then
    export IROHA3D_BIN="$local_acceptance_bundle_dir/bin/iroha3d"
    export IROHA_BIN="$local_acceptance_bundle_dir/bin/iroha"
    export KAGAMI_BIN="$local_acceptance_kagami_bin"
    export SORASWAP_SKIP_LOCALNET_TOOL_BUILD=1
    export SORASWAP_ISOLATED_LOCAL_UP_TIMEOUT_SECS=0
    export SORASWAP_ISOLATED_DEPLOY_TIMEOUT_SECS=0
    export SORASWAP_ISOLATED_SMOKE_TIMEOUT_SECS=0
    export SORASWAP_ISOLATED_TESTNET_SMOKE_TIMEOUT_SECS=0
  fi
}

require_production_cutover_evidence() {
  local pin_state rc_state source_state approval_state

  [[ "$public_env" == "production" ]] || return 0
  [[ "$local_acceptance_pin_enabled" == "1" ]] || {
    echo "release checklist failed: production cutover evidence requires the exact-candidate local acceptance pin" >&2
    exit 1
  }
  approval_state="${SORASWAP_INTERNAL_PRODUCTION_CUTOVER_APPROVAL_STATE_JSON:-}"
  [[ -n "$approval_state" ]] || {
    echo "release checklist failed: production cutover approval state is missing; run the controlled release-production runner" >&2
    exit 1
  }
  pin_state="$(release_local_acceptance_pin_state_json \
    "$local_acceptance_iroha_root" \
    "$local_acceptance_bundle_dir" \
    "$local_acceptance_expected_git_sha")" || exit 1
  rc_state="$(release_soraswap_rc_state_json "$ROOT" "${SORASWAP_RELEASE_EXPECTED_GIT_SHA:-}")" || exit 1
  source_state="$(release_closeout_source_state_json "$ROOT" production)" || exit 1
  "$ROOT/scripts/verify_production_cutover_evidence.sh" \
    --approval-state-json "$approval_state" \
    --soraswap-rc-state-json "$rc_state" \
    --soraswap-source-state-json "$source_state" \
    --iroha-state-json "$pin_state" \
    --chain-file "$evidence_dir/chain.latest.json" \
    --deploy-file "$evidence_dir/deploy.latest.json" \
    --contracts-file "$evidence_dir/contracts.latest.json" \
    --trader-api-file "$evidence_dir/trader_api_bundle.latest.json" \
    --approval-evidence "$evidence_dir/cutover_approval.latest.json" \
    --observation-evidence "$evidence_dir/observation.latest.json" >/dev/null
}

content_cid_from_hex() {
  local python_bin="${commands[python3]:-python3}"

  "$python_bin" - "$1" <<'PY'
import base64
import sys

raw = bytes.fromhex(sys.argv[1].strip())
print("b" + base64.b32encode(raw).decode("ascii").lower().rstrip("="))
PY
}

require_selected_environment() {
  local artifact_name="$1"
  local artifact_json="$2"

  if ! jq -e --arg public_env "$public_env" \
    '((.environment // "") | type == "string") and .environment == $public_env' \
    <<<"$artifact_json" >/dev/null; then
    echo "release checklist failed: $artifact_name must record environment \"$public_env\"" >&2
    exit 1
  fi
}

require_current_snapshots() {
  local artifact_name="$1"
  local artifact_json="$2"
  local description="${3:-does not reference the current contracts/deploy snapshots}"

  if ! jq -e \
    --arg public_env "$public_env" \
    --argjson contracts "$contracts_json" \
    --argjson deploy "$deploy_json" \
    '
      def snapshot_matches($snapshot; $current):
        ($snapshot | type) == "object"
        and ($snapshot.generated_at // null) == ($current.generated_at // null)
        and ($snapshot.status // null) == ($current.status // null)
        and ($snapshot.environment // null) == ($current.environment // null)
        and ($snapshot.environment // null) == $public_env
        and (($current.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
        and (($snapshot.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
        and ($snapshot.chain_fingerprint.torii_url // null) == ($current.chain_fingerprint.torii_url // null)
        and ($snapshot.chain_fingerprint.chain // null) == ($current.chain_fingerprint.chain // null)
        and ($snapshot.chain_fingerprint.block_1_hash // null) == ($current.chain_fingerprint.block_1_hash // null);

      snapshot_matches(.contracts_snapshot; $contracts)
      and snapshot_matches(.deploy_snapshot; $deploy)
      and (.deploy_snapshot.status // null) == ($deploy.status // null)
    ' <<<"$artifact_json" >/dev/null; then
    echo "release checklist failed: $artifact_name $description" >&2
    exit 1
  fi
}

require_snapshot_check_completed() {
  local artifact_name="$1"
  local artifact_json="$2"

  if ! jq -e '(.snapshot_check.status // "") == "completed"' <<<"$artifact_json" >/dev/null; then
    echo "release checklist failed: $artifact_name snapshot_check.status is missing or not completed" >&2
    exit 1
  fi
}

require_not_older_than_current_snapshots() {
  local artifact_name="$1"
  local artifact_json="$2"

  if ! jq -e \
    --argjson contracts "$contracts_json" \
    --argjson deploy "$deploy_json" \
    '
      ((.generated_at // "") | length > 0)
      and (.generated_at >= ($contracts.generated_at // ""))
      and (.generated_at >= ($deploy.generated_at // ""))
    ' <<<"$artifact_json" >/dev/null; then
    echo "release checklist failed: $artifact_name is older than current contracts/deploy snapshots" >&2
    exit 1
  fi
}

signed_public_smoke_command() {
  case "$public_env" in
    testnet)
      printf '%s\n' "SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make smoke-testnet"
      ;;
    production)
      printf '%s\n' "SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make smoke-production"
      ;;
  esac
}

require_public_smoke_mutation_evidence() {
  if ! jq -e '
    (.readonly_verification | type) == "object"
    and (.tx_hashes | type) == "object"
    and ((.tx_hashes | keys_unsorted | length) > 0)
  ' <<<"$smoke_json" >/dev/null; then
    echo "release checklist failed: smoke.latest.json is missing signed mutating smoke transaction evidence; rerun $(signed_public_smoke_command)" >&2
    exit 1
  fi

  require_not_older_than_current_snapshots "smoke.latest.json" "$smoke_json"

  if ! jq -e '
    def has_tx($root; $key):
      ($root.tx_hashes[$key] // "") as $tx
      | (($tx | type) == "string" and ($tx | test("^[0-9a-fA-F]{64}$")));
    def has_trigger_tx($root; $key):
      ($root.tx_hashes[$key] // "") as $tx
      | (($tx | type) == "string"
        and (
          ($tx | test("^[0-9a-fA-F]{64}$"))
          or ($tx | test("^hash:[0-9a-fA-F]{64}#[0-9a-fA-F]+$"))
        ));
    def numeric_scalar($root; $key):
      ($root.view_results[$key] // null) | type == "number";
    def numeric_array($root; $key; $min_len):
      ($root.view_results[$key] // null) as $value
      | (($value | type) == "array")
        and (($value | length) >= $min_len)
        and all($value[]; type == "number");
    def options_factory_config($root):
      ($root.view_results.options_factory_config // null) as $value
      | (($value | type) == "array")
        and (($value | length) >= 9)
        and all($value[0:3][]; type == "string" and length > 0)
        and ($value[1] != $value[2])
        and all($value[3:][]; type == "number");

    . as $root
    | all([
      "n3x_deposit_and_mint",
      "n3x_burn_and_redeem",
      "dlmm_router_route_swap",
      "dlmm_pool_collect_position_fees",
      "dlmm_pool_remove_position_liquidity",
      "launchpad_contribute",
      "launchpad_claim_allocation",
      "launchpad_finalize_activation",
      "launchpad_refund_allocation",
      "referral_bind_parent",
      "referral_bind",
      "referral_accrue",
      "referral_claim",
      "referral_parent_claim",
      "farms_fund_rewards",
      "farms_stake",
      "farms_claim",
      "farms_unstake",
      "perps_open_position",
      "perps_sync_funding",
      "perps_add_margin",
      "perps_remove_margin",
      "perps_close_position",
      "perps_open_liquidation_position",
      "options_buy_shout",
      "options_publish_shout_mark",
      "options_publish_shout_final_mark",
      "options_exercise_shout",
      "options_buy_outperformance",
      "options_settle_outperformance_series",
      "options_exercise_outperformance",
      "cover_register_policy",
      "cover_trigger_1",
      "cover_trigger_2",
      "cover_trigger_3",
      "cover_trigger_4",
      "cover_route_claim",
      "automation_enqueue",
      "automation_assign_executor",
      "automation_dispatch",
      "automation_pause",
      "automation_resume",
      "automation_retry",
      "automation_retry_dispatch",
      "automation_complete_run",
      "conditional_escrow_open"
    ][]; has_tx($root; .))
    and has_trigger_tx($root; "conditional_escrow_execute_trigger")
    and numeric_scalar($root; "n3x_quote_mint")
    and numeric_scalar($root; "n3x_quote_redeem")
    and numeric_scalar($root; "dlmm_router_quote_bin")
    and numeric_array($root; "n3x_mirror_state"; 4)
    and numeric_array($root; "dlmm_router_mirror_state"; 2)
    and numeric_array($root; "dlmm_pool_mirror_state"; 4)
    and numeric_array($root; "launchpad_mirror_sale"; 4)
    and numeric_array($root; "launchpad_mirror_sale_accounting"; 4)
    and numeric_array($root; "launchpad_activation_state"; 2)
    and numeric_array($root; "referral_mirror_member"; 4)
    and numeric_array($root; "farms_mirror_position"; 4)
    and options_factory_config($root)
    and numeric_array($root; "options_factory_shout_series"; 10)
    and numeric_array($root; "options_factory_outperformance_series"; 10)
    and numeric_array($root; "options_factory_automation"; 7)
    and numeric_array($root; "options_factory_shout_position"; 9)
    and numeric_array($root; "options_factory_outperformance_position"; 9)
    and numeric_array($root; "cover_policy_state"; 4)
    and numeric_array($root; "automation_mirror_job"; 4)
    and numeric_array($root; "conditional_escrow_state"; 4)
    and numeric_array($root; "epoch_auction_state"; 4)
  ' <<<"$smoke_json" >/dev/null; then
    echo "release checklist failed: smoke.latest.json is missing first-release module mutation/state and self-contained options oracle evidence" >&2
    exit 1
  fi

  if ! jq -e '
    def has_tx($key):
      (.tx_hashes[$key] // "") as $tx
      | (($tx | type) == "string" and ($tx | test("^[0-9a-fA-F]{64}$")));
    def positive_number:
      type == "number" and . > 0;
    def collateral_pool_state:
      (.view_results.perps_collateral_pool // null) as $value
      | (($value | type) == "array")
        and (($value | length) >= 4)
        and (($value[0] | type) == "string" and length > 0)
        and all($value[1:][]; type == "number");
    def has_liquidated_pass:
      any([
        .view_results.perps_liquidation_state,
        .view_results.perps_liquidation_queue_state,
        .view_results.perps_liquidation_recovery_state,
        .view_results.perps_liquidation_requeue_state,
        .view_results.perps_liquidation_execute_state
      ][]; ((.[3] // null) | positive_number) and ((.[6] // null) | positive_number))
      or (
        ((.view_results.perps_liquidation_position_state[1] // null) == 4)
        and ((.view_results.perps_liquidation_position_liquidation_state[1] // null) | positive_number)
        and ((.view_results.perps_liquidation_position_liquidation_state[2] // null) | positive_number)
      );

    has_tx("perps_liquidation_queue_pass")
    and has_tx("perps_liquidation_recovery_pass")
    and has_tx("perps_liquidation_requeue_pass")
    and has_tx("perps_liquidation_execute_pass")
    and has_tx("perps_pause_trigger_lifecycle")
    and has_tx("perps_restore_trigger_lifecycle")
    and collateral_pool_state
    and has_liquidated_pass
    and ((.view_results.perps_liquidation_position_state[1] // null) == 4)
    and ((.view_results.perps_liquidation_position_liquidation_state[1] // null) | positive_number)
    and ((.view_results.perps_liquidation_position_liquidation_state[2] // null) | positive_number)
  ' <<<"$smoke_json" >/dev/null; then
    echo "release checklist failed: smoke.latest.json is missing automatic perps liquidation evidence" >&2
    exit 1
  fi

  if ! jq -e --argjson rwa_release_enabled "$rwa_release_enabled_json" '
    (.release_modes | type) == "object"
    and (.release_modes.rwa | type) == "boolean"
    and .release_modes.rwa == $rwa_release_enabled
  ' <<<"$smoke_json" >/dev/null; then
    echo "release checklist failed: smoke.latest.json release_modes.rwa does not match SORASWAP_ENABLE_RWA_RELEASE" >&2
    exit 1
  fi

  if ! jq -e --argjson rwa_release_enabled "$rwa_release_enabled_json" '
    def has_tx($key):
      (.tx_hashes[$key] // "") as $tx
      | (($tx | type) == "string" and ($tx | test("^[0-9a-fA-F]{64}$")));
    def has_no_tx($key):
      (has_tx($key) | not);
    def positive_number:
      type == "number" and . > 0;
    def rwa_completed:
      has_tx("rwa_issue_lot")
      and has_tx("rwa_report_nav")
      and has_tx("rwa_request_redemption")
      and has_tx("rwa_settle_redemption")
      and ((.rejection_evidence.duplicate_rwa_issue // "") | length > 0)
      and (.view_results.rwa_market_state == [1,105,900,1]);
    def rwa_not_launched:
      has_no_tx("rwa_issue_lot")
      and has_no_tx("rwa_report_nav")
      and has_no_tx("rwa_request_redemption")
      and has_no_tx("rwa_settle_redemption")
      and ((.rejection_evidence.duplicate_rwa_issue // "") | length == 0)
      and (.view_results.rwa_market_state == [0,0,0,0]);

    has_tx("intent_open")
    and has_tx("intent_fill")
    and has_tx("vault_register")
    and has_tx("vault_deposit")
    and has_tx("vault_request_redeem")
    and has_tx("vault_claim_redeem")
    and has_tx("operator_register")
    and has_tx("operator_bond")
    and has_tx("operator_heartbeat")
    and has_tx("margin_register_market")
    and has_tx("margin_deposit_collateral")
    and has_tx("margin_lock_exposure")
    and has_tx("margin_liquidate_account")
    and has_tx("dlmm_configure_hook")
    and has_tx("dlmm_place_limit_order")
    and has_tx("dlmm_schedule_twamm")
    and has_tx("dlmm_record_hook_execution")
    and ((.rejection_evidence.intent_replay // "") | length > 0)
    and ((.rejection_evidence.unregistered_operator // "") | length > 0)
    and ((.rejection_evidence.unhealthy_margin_withdraw // "") | length > 0)
    and ((.rejection_evidence.disabled_dlmm_hook // "") | length > 0)
    and (.view_results.intent_state[0:5] == [1,2,10,9,30])
    and ((.view_results.intent_state[5] // null) | positive_number)
    and (.view_results.intent_state[6:9] == [1,1,10])
    and (.view_results.vault_state == [1,1,1,15,15])
    and (.view_results.operator_state == [1,100,125,8000,11,0,0])
    and (.view_results.margin_account_health == [0,0,10000,1])
    and (if $rwa_release_enabled then rwa_completed else rwa_not_launched end)
    and (.view_results.dlmm_hook_quote == [1,20,18,20,19])
  ' <<<"$smoke_json" >/dev/null; then
    echo "release checklist failed: smoke.latest.json is missing 2026 primitive mutation/rejection evidence" >&2
    exit 1
  fi
}

require_generated_at() {
  local artifact_name="$1"
  local artifact_json="$2"

  if ! jq -e '((.generated_at // "") | type == "string" and length > 0)' \
    <<<"$artifact_json" >/dev/null; then
    echo "release checklist failed: $artifact_name is missing generated_at" >&2
    exit 1
  fi
}

require_chain_fingerprint_fields() {
  local artifact_name="$1"
  local artifact_json="$2"

  if ! jq -e '
    ((.torii_url // "") | type == "string" and length > 0)
    and ((.chain // "") | type == "string" and length > 0)
    and ((.block_1_hash // "") | type == "string" and length > 0)
  ' <<<"$artifact_json" >/dev/null; then
    echo "release checklist failed: $artifact_name must include non-empty torii_url, chain, and block_1_hash" >&2
    exit 1
  fi
}

require_doc_mentions() {
  local doc_path="$1"
  local label="$2"
  local needle="$3"
  local doc_label

  [[ -n "$needle" ]] || return 0
  if ! grep -Fq -- "$needle" "$doc_path"; then
    doc_label="$(soraswap_display_path "$doc_path")"
    echo "release checklist failed: $doc_label does not mention current $public_display_label $label $needle" >&2
    exit 1
  fi
}

generated_at_from_json_or_empty() {
  local artifact_path="$1"

  [[ -f "$artifact_path" ]] || return 0
  jq -r '.generated_at // empty' "$artifact_path" 2>/dev/null || true
}

capture_local_doc_generated_at_values() {
  local_doc_chain_generated_at="$(generated_at_from_json_or_empty "$ROOT/deployments/local/chain.latest.json")"
  local_doc_deploy_generated_at="$(generated_at_from_json_or_empty "$ROOT/deployments/local/deploy.latest.json")"
  local_doc_contracts_generated_at="$(generated_at_from_json_or_empty "$ROOT/deployments/local/contracts.latest.json")"
  local_doc_smoke_generated_at="$(generated_at_from_json_or_empty "$ROOT/deployments/local/smoke.latest.json")"
  local_doc_telemetry_generated_at="$(generated_at_from_json_or_empty "$ROOT/artifacts/telemetry/defi_2026_primitives_latest.json")"
}

require_no_local_path_leaks() {
  local artifact_path="$1"

  if ! python3 - "$artifact_path" >/dev/null <<'PY'
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
pattern = re.compile(
    r"(?:file://(?:localhost)?/(?:Users/|private/var/folders/|var/folders/|private/tmp/|tmp/))"
    r"|(?:file:/(?:Users/|private/var/folders/|var/folders/|private/tmp/|tmp/))"
    r"|(?:(?<![A-Za-z0-9:/])(?:/Users/|/private/var/folders/|/var/folders/|/private/tmp/|/tmp/))"
)

def iter_strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for item in value:
            yield from iter_strings(item)
    elif isinstance(value, dict):
        for key, item in value.items():
            yield str(key)
            yield from iter_strings(item)

try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    data = path.read_text(encoding="utf-8", errors="replace")

if isinstance(data, str):
    strings = [data]
else:
    strings = iter_strings(data)

if any(pattern.search(value) for value in strings):
    raise SystemExit(1)
PY
  then
    echo "release checklist failed: $(soraswap_display_path "$artifact_path") contains local filesystem path diagnostics; rerun the evidence with current redaction helpers" >&2
    exit 1
  fi
}

require_no_sensitive_diagnostic_leaks() {
  local artifact_path="$1"
  local artifact_json redacted_json

  if ! jq -e . "$artifact_path" >/dev/null 2>&1; then
    return 0
  fi
  artifact_json="$(cat "$artifact_path")"
  redacted_json="$(soraswap_redact_sensitive_text "$artifact_json")"
  if ! json_equals "$artifact_json" "$redacted_json"; then
    echo "release checklist failed: $(soraswap_display_path "$artifact_path") contains unredacted sensitive diagnostics; rerun the evidence with current redaction helpers" >&2
    exit 1
  fi
}

require_public_status_docs_current() {
  local chain_block_1_hash preflight_generated preflight_status probe_generated doc_path
  typeset -a status_docs

  [[ "$closeout_mode" != "prepare" ]] || return 0

  case "$public_env" in
    testnet)
      status_docs=("${required_taira_status_docs[@]}")
      ;;
    production)
      status_docs=("${required_production_status_docs[@]}")
      ;;
  esac

  chain_block_1_hash="$(jq -r '.block_1_hash // empty' <<<"$chain_json")"
  preflight_generated="$(jq -r '.generated_at // empty' <<<"$preflight_json")"
  preflight_status="$(jq -r '.status // empty' <<<"$preflight_json")"
  probe_generated=""
  if nested_probe_artifact_is_current_for_hint; then
    probe_generated="$(jq -r '.generated_at // empty' "$evidence_dir/nested_call_probe.latest.json" 2>/dev/null || true)"
  fi

  for doc_path in "${status_docs[@]}"; do
    require_doc_mentions "$doc_path" "chain block-1 hash" "$chain_block_1_hash"
    if [[ "$preflight_status" != "ready" ]]; then
      require_doc_mentions "$doc_path" "preflight evidence" "$preflight_generated"
      if [[ -n "$probe_generated" ]]; then
        require_doc_mentions "$doc_path" "nested-call probe evidence" "$probe_generated"
      else
        require_doc_mentions "$doc_path" "nested-call probe absence" "nested_call_probe.latest_exists"
      fi
    fi
  done
}

require_local_evidence_docs_current() {
  local local_chain_generated local_deploy_generated local_contracts_generated local_smoke_generated
  local local_chain_doc_generated local_deploy_doc_generated local_contracts_doc_generated local_smoke_doc_generated
  local doc_path

  [[ "$closeout_mode" != "prepare" ]] || return 0

  local_chain_generated="$(
    jq -r '.generated_at // empty' "$ROOT/deployments/local/chain.latest.json"
  )"
  local_deploy_generated="$(
    jq -r '.generated_at // empty' "$ROOT/deployments/local/deploy.latest.json"
  )"
  local_contracts_generated="$(
    jq -r '.generated_at // empty' "$ROOT/deployments/local/contracts.latest.json"
  )"
  local_smoke_generated="$(
    jq -r '.generated_at // empty' "$ROOT/deployments/local/smoke.latest.json"
  )"
  local_chain_doc_generated="${local_doc_chain_generated_at:-$local_chain_generated}"
  local_deploy_doc_generated="${local_doc_deploy_generated_at:-$local_deploy_generated}"
  local_contracts_doc_generated="${local_doc_contracts_generated_at:-$local_contracts_generated}"
  local_smoke_doc_generated="${local_doc_smoke_generated_at:-$local_smoke_generated}"

  for doc_path in "${required_local_evidence_docs[@]}"; do
    require_doc_mentions "$doc_path" "retained local chain evidence generated_at" "$local_chain_doc_generated"
    require_doc_mentions "$doc_path" "retained local deploy evidence generated_at" "$local_deploy_doc_generated"
    require_doc_mentions "$doc_path" "retained local contracts evidence generated_at" "$local_contracts_doc_generated"
    require_doc_mentions "$doc_path" "retained local smoke evidence generated_at" "$local_smoke_doc_generated"
  done
}

print_missing_release_artifact_summary() {
  local artifact_path
  local missing_count=0

  for artifact_path in "${required_release_evidence[@]}" "${required_local_evidence[@]}"; do
    [[ -f "$artifact_path" ]] && continue
    if (( missing_count == 0 )); then
      echo "  missing release artifacts still required after preflight clears:" >&2
    fi
    echo "    $(soraswap_display_path "$artifact_path")" >&2
    if [[ "$artifact_path" == "$evidence_dir/nested_call_probe.latest.json" ]]; then
      echo "    refresh nested-call evidence with: $(signed_nested_probe_command)" >&2
    elif [[ "$artifact_path" == "$evidence_dir/rwa_compliance.latest.json" ]]; then
      echo "    record RWA evidence with: make record-${public_env}-rwa-compliance" >&2
    elif [[ "$artifact_path" == "$ROOT/artifacts/telemetry/defi_2026_primitives_latest.json" ]]; then
      echo "    generate local primitive telemetry with: make simulate-full" >&2
    elif [[ "$artifact_path" == "$ROOT/deployments/local/deploy.latest.json" \
      || "$artifact_path" == "$ROOT/deployments/local/contracts.latest.json" \
      || "$artifact_path" == "$ROOT/deployments/local/smoke.latest.json" ]]; then
      echo "    generate local deploy/smoke evidence with: make test-local-isolated" >&2
    fi
    missing_count=$(( missing_count + 1 ))
  done
}

signed_nested_probe_command() {
  case "$public_env" in
    testnet)
      echo "SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make testnet-nested-call-probe"
      ;;
    production)
      echo "SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make production-nested-call-probe"
      ;;
  esac
}

nested_probe_artifact_is_current_for_hint() {
  local probe_artifact="$evidence_dir/nested_call_probe.latest.json"

  [[ -s "$probe_artifact" ]] || return 1
  if ! jq -e type "$probe_artifact" >/dev/null 2>&1; then
    return 1
  fi
  jq -e \
    --arg public_env "$public_env" \
    --argjson chain "$chain_json" \
    '
      ((.generated_at // "") | type == "string" and length > 0)
      and ((.environment // "") | type == "string" and . == $public_env)
      and (.chain_fingerprint != null)
      and ((.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
      and (.chain_fingerprint.torii_url // null) == ($chain.torii_url // null)
      and (.chain_fingerprint.chain // null) == ($chain.chain // null)
      and (.chain_fingerprint.block_1_hash // null) == ($chain.block_1_hash // null)
    ' "$probe_artifact" >/dev/null 2>&1
}

print_taira_doctor_hint() {
  echo '    iroha -c "$SORASWAP_CLIENT_CONFIG" taira doctor --public-root "$PUBLIC_TORII_ROOT" --json' >&2
}

print_missing_preflight_artifact_hint() {
  local artifact_path="$1"
  local artifact_name="${artifact_path:t}"

  case "$artifact_name" in
    chain.latest.json)
      case "$public_env" in
        testnet)
          echo "next setup: make refresh-testnet-chain" >&2
          echo "then refresh signed probe evidence: SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make testnet-nested-call-probe" >&2
          ;;
        production)
          echo "next setup: make refresh-production-chain" >&2
          echo "then refresh signed probe evidence: SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make production-nested-call-probe" >&2
          ;;
      esac
      ;;
    preflight.latest.json)
      case "$public_env" in
        testnet)
          echo "next setup: SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make taira-preflight" >&2
          ;;
        production)
          echo "next setup: SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make production-preflight" >&2
          ;;
      esac
      ;;
  esac
}

print_production_preflight_setup_summary() {
  local production_preflight="$ROOT/deployments/production/preflight.latest.json"
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

require_taira_release_gate_for_production() {
  [[ "$public_env" == "production" ]] || return 0
  [[ "$taira_release_gate_checked" == "0" ]] || return 0

  local prereq_token="soraswap-prereq-${$}-${RANDOM}-${RANDOM}"

  echo "release checklist: verifying Taira prerequisite for production"
  if (
    unset SORASWAP_CLIENT_CONFIG SORASWAP_PRODUCTION_CLIENT_CONFIG SORASWAP_ALLOW_TESTNET_MUTATIONS SORASWAP_ALLOW_PRODUCTION_MUTATIONS
    unset SORASWAP_PUBLIC_DEPLOY_REUSE_CONTRACTS SORASWAP_TESTNET_DEPLOY_REUSE_CONTRACTS SORASWAP_PRODUCTION_DEPLOY_REUSE_CONTRACTS
    unset RELEASE_CHECKLIST_INTERNAL_TOKEN
    unset RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_TOKEN RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_JOURNAL
    clear_inherited_soraswap_env
    clear_inherited_make_control_env
    export SORASWAP_ROOT="$ROOT"
    export SORASWAP_PUBLIC_ENV=testnet
    export SORASWAP_RELEASE_ENV=testnet
    export RELEASE_CHECKLIST_INTERNAL_TOKEN="$prereq_token"
    0="$SCRIPT_ROOT/scripts/release_checklist.sh"
    source "$SCRIPT_ROOT/scripts/release_checklist.sh" --internal-production-prereq "$prereq_token"
  ); then
    :
  else
    local prereq_status="$?"
    print_production_preflight_setup_summary
    exit "$prereq_status"
  fi
  taira_release_gate_checked=1
}

if [[ "$closeout_mode" == "resume" ]]; then
  echo "release checklist: verifying pending $public_env closeout checkpoint before nonmutating validation"
  release_closeout_checkpoint_state verify-base 0 >/dev/null
fi

soraswap_require_contract_source_hygiene "$ROOT" "release checklist failed" || exit 1

require_taira_release_gate_for_production

for artifact_path in "${required_docs[@]}" "${required_preflight_evidence[@]}"; do
  if [[ ! -s "$artifact_path" ]]; then
    echo "missing required release artifact: $(soraswap_display_path "$artifact_path")" >&2
    print_missing_preflight_artifact_hint "$artifact_path"
    if [[ "$public_env" == "production" && "$artifact_path" == "$evidence_dir/"* ]]; then
      print_production_preflight_setup_summary
    fi
    exit 1
  fi
done

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
if (( ported_count == 0 )); then
  echo "release checklist failed: migration register must contain at least one ported production row" >&2
  exit 1
fi

chain_json="$(cat "$evidence_dir/chain.latest.json")"
preflight_json="$(cat "$evidence_dir/preflight.latest.json")"

for artifact_path in "${required_preflight_evidence[@]}"; do
  require_no_local_path_leaks "$artifact_path"
done
if [[ -f "$evidence_dir/nested_call_probe.latest.json" ]]; then
  require_no_local_path_leaks "$evidence_dir/nested_call_probe.latest.json"
fi

require_generated_at "chain.latest.json" "$chain_json"

require_selected_environment "chain.latest.json" "$chain_json"

require_chain_fingerprint_fields "chain.latest.json" "$chain_json"

require_generated_at "preflight.latest.json" "$preflight_json"

if ! jq -e --arg public_env "$public_env" \
  '((.target_environment // "") | type == "string") and .target_environment == $public_env' \
  <<<"$preflight_json" >/dev/null; then
  echo "release checklist failed: preflight.latest.json must record target_environment \"$public_env\"" >&2
  exit 1
fi

if ! jq -e --arg public_env "$public_env" \
  '((.chain.saved_snapshot_environment // "") | type == "string") and .chain.saved_snapshot_environment == $public_env' \
  <<<"$preflight_json" >/dev/null; then
  echo "release checklist failed: preflight.latest.json chain.saved_snapshot_environment must be \"$public_env\"" >&2
  exit 1
fi

for artifact_path in "${required_preflight_evidence[@]}"; do
  require_no_sensitive_diagnostic_leaks "$artifact_path"
done
if [[ -f "$evidence_dir/nested_call_probe.latest.json" ]]; then
  require_no_sensitive_diagnostic_leaks "$evidence_dir/nested_call_probe.latest.json"
fi

require_public_status_docs_current

if ! jq -e \
  --arg public_env "$public_env" \
  --argjson chain "$chain_json" \
  '
    .status == "ready"
    and ((.blockers // []) | length) == 0
    and ((.warnings // []) | length) == 0
    and (.environment.mutations_allowed // false) == true
    and (.environment.oracle_client_config_present // false) == true
    and (.environment.oracle_client_config_valid // false) == true
    and (.environment.oracle_account_derivable // false) == true
    and (.environment.oracle_account_distinct // false) == true
    and ((.environment.oracle_client_config_source // "") | length > 0)
    and (.endpoint.mcp_http_status // "") == "200"
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
    and ((.chain.fingerprint.torii_url // "") | type == "string" and length > 0)
    and .chain.fingerprint.torii_url == $chain.torii_url
    and .chain.fingerprint.chain == $chain.chain
    and .chain.fingerprint.block_1_hash == $chain.block_1_hash
    and (.nested_call_probe.latest_exists // false) == true
    and (.nested_call_probe.matches_current_chain // false) == true
    and (.nested_call_probe.supported // false) == true
    and (.signer.authority_derivable // false) == true
    and (.signer.account_exists // false) == true
    and (.signer.assets_query_available // false) == true
    and (((.signer.fee_balance // "0") | tonumber) > 0)
  ' <<<"$preflight_json" >/dev/null; then
  echo "release checklist failed: preflight.latest.json is not ready for the current $public_display_label chain" >&2
  soraswap_print_preflight_report_reasons "$evidence_dir/preflight.latest.json" ""
  nested_summary="$(jq -r '.nested_call_probe.summary // empty' <<<"$preflight_json" 2>/dev/null || true)"
  if [[ -n "$nested_summary" ]]; then
    echo "  nested-call probe: $(soraswap_redact_sensitive_text "$nested_summary")" >&2
  fi
  if nested_probe_artifact_is_current_for_hint; then
    nested_health_summary="$(nested_call_probe_health_summary_text "$evidence_dir/nested_call_probe.latest.json" 2>/dev/null || true)"
    if [[ -n "$nested_health_summary" ]]; then
      echo "  nested-call health: $(soraswap_redact_sensitive_text "$nested_health_summary")" >&2
    fi
  fi
  chain_refresh_hint_needed=false
  if jq -e '
    any((.blockers // [])[]?; tostring | test("saved chain\\.latest\\.json does not match the live|chain fingerprint|block-1 fingerprint"; "i"))
    or (.chain.saved_snapshot_matches == false)
  ' <<<"$preflight_json" >/dev/null 2>&1; then
    chain_refresh_hint_needed=true
  fi
  if [[ "$chain_refresh_hint_needed" == "true" ]]; then
    case "$public_env" in
      testnet)
        echo "  next chain refresh: make refresh-testnet-chain" >&2
        echo "  then refresh signed probe evidence: SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make testnet-nested-call-probe" >&2
        ;;
      production)
        echo "  next chain refresh: make refresh-production-chain" >&2
        echo "  then refresh signed probe evidence: SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make production-nested-call-probe" >&2
        ;;
    esac
  fi
  nested_probe_problem_hint_needed=false
  missing_nested_probe_hint_needed=false
  nested_runtime_hint_needed=false
  public_write_health_hint_needed=false
  if jq -e '
    any((.blockers // [])[]?; tostring | test("finality|write[-_ ]health|queued writes|tx_queue|transaction queue|stale committed|saturated"; "i"))
  ' <<<"$preflight_json" >/dev/null 2>&1; then
    public_write_health_hint_needed=true
  fi
  if [[ "$chain_refresh_hint_needed" != "true" ]]; then
    if jq -e '
      any((.blockers // [])[]?; tostring | test("nested[-_ ]call probe evidence is missing|current nested[-_ ]call probe evidence is missing"; "i"))
      or (.nested_call_probe.latest_exists == false)
      or (.nested_call_probe.matches_current_chain == false)
    ' <<<"$preflight_json" >/dev/null 2>&1; then
      missing_nested_probe_hint_needed=true
    fi
    if [[ "$missing_nested_probe_hint_needed" != "true" ]] && jq -e '
      any((.blockers // [])[]?; tostring | test("nested[-_ ]call|call_contract"; "i"))
      or (.nested_call_probe.supported == false)
      or (.nested_call_probe.nested_call_supported == false)
      or (.nested_call_probe.nested_asset_ops_supported == false)
    ' <<<"$preflight_json" >/dev/null 2>&1; then
      nested_probe_problem_hint_needed=true
    elif [[ "$missing_nested_probe_hint_needed" != "true" && -s "$evidence_dir/nested_call_probe.latest.json" ]] && jq -e '
      (.supported == false)
      or (.nested_call_supported == false)
      or (.nested_asset_ops_supported == false)
    ' "$evidence_dir/nested_call_probe.latest.json" >/dev/null 2>&1; then
      nested_probe_problem_hint_needed=true
    fi
    if [[ "$nested_probe_problem_hint_needed" == "true" ]]; then
      if nested_probe_artifact_is_current_for_hint; then
        nested_runtime_hint_needed=true
      else
        missing_nested_probe_hint_needed=true
      fi
    fi
  fi
  if [[ "$missing_nested_probe_hint_needed" == "true" ]]; then
    echo "  next signed probe: $(signed_nested_probe_command)" >&2
  fi
  if [[ "$public_env" == "testnet" && "$nested_runtime_hint_needed" == "true" ]]; then
    echo "  next runtime check: roll public Taira with the sibling ../iroha router and nested-transfer runtime fixes, then run:" >&2
    print_taira_doctor_hint
  elif [[ "$public_env" == "production" && "$nested_runtime_hint_needed" == "true" ]]; then
    echo "  next runtime check: roll the production public runtime with the sibling ../iroha router and nested-transfer runtime fixes, then rerun:" >&2
    echo "    SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make production-nested-call-probe" >&2
    echo "    SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make production-preflight" >&2
  fi
  if [[ "$public_write_health_hint_needed" == "true" ]]; then
    case "$public_env" in
      testnet)
        echo "  next public health check: inspect current Taira health with:" >&2
        print_taira_doctor_hint
        echo "  after Taira finality/write health is stable, rerun:" >&2
        echo "    SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make taira-preflight" >&2
        ;;
      production)
        echo "  next public health check: wait for stable production finality/write health, then rerun:" >&2
        echo "    SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make production-preflight" >&2
        ;;
    esac
  fi
  print_missing_release_artifact_summary
  exit 1
fi

for artifact_path in "${required_release_evidence[@]}"; do
  if [[ ! -f "$artifact_path" ]]; then
    echo "missing required release artifact: $(soraswap_display_path "$artifact_path")" >&2
    if [[ "$artifact_path" == "$evidence_dir/nested_call_probe.latest.json" ]]; then
      case "$public_env" in
        testnet)
          echo "refresh it with: SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make testnet-nested-call-probe" >&2
          ;;
        production)
          echo "refresh it with: SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make production-nested-call-probe" >&2
          ;;
      esac
    elif [[ "$artifact_path" == "$evidence_dir/rwa_compliance.latest.json" ]]; then
      echo "record it with: make record-${public_env}-rwa-compliance" >&2
    fi
    exit 1
  fi
done

deploy_json="$(cat "$evidence_dir/deploy.latest.json")"
contracts_json="$(cat "$evidence_dir/contracts.latest.json")"
probe_json="$(cat "$evidence_dir/nested_call_probe.latest.json")"
smoke_json="$(cat "$evidence_dir/smoke.latest.json")"
console_json="$(cat "$evidence_dir/contract_console_smoke.latest.json")"
trader_readonly_json="$(cat "$evidence_dir/trader_readonly.latest.json")"
trader_json="$(cat "$evidence_dir/trader.latest.json")"
trader_api_json="$(cat "$evidence_dir/trader_api_bundle.latest.json")"
rwa_compliance_json="$(cat "$evidence_dir/rwa_compliance.latest.json")"
for evidence_path in \
  "$evidence_dir/deploy.latest.json" \
  "$evidence_dir/nested_call_probe.latest.json" \
  "$evidence_dir/contracts.latest.json" \
  "$evidence_dir/smoke.latest.json" \
  "$evidence_dir/contract_console_smoke.latest.json" \
  "$evidence_dir/trader_readonly.latest.json" \
  "$evidence_dir/trader.latest.json" \
  "$evidence_dir/trader_api_bundle.latest.json" \
  "$evidence_dir/rwa_compliance.latest.json"; do
  if ! jq -e \
    --argjson chain "$chain_json" \
    '.chain_fingerprint != null
      and ((.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
      and .chain_fingerprint.torii_url == $chain.torii_url
      and .chain_fingerprint.chain == $chain.chain
      and .chain_fingerprint.block_1_hash == $chain.block_1_hash' \
    "$evidence_path" >/dev/null; then
    echo "release checklist failed: chain fingerprint mismatch for $(soraswap_display_path "$evidence_path")" >&2
    exit 1
  fi
done

require_generated_at "nested_call_probe.latest.json" "$probe_json"
if ! jq -e --argjson probe "$probe_json" '
  ((.generated_at // "") | type == "string" and length > 0)
  and (($probe.generated_at // "") | type == "string" and length > 0)
  and (.generated_at >= ($probe.generated_at // ""))
' <<<"$preflight_json" >/dev/null; then
  echo "release checklist failed: preflight.latest.json is older than current nested_call_probe.latest.json" >&2
  exit 1
fi
require_generated_at "deploy.latest.json" "$deploy_json"
if ! jq -e '.status == "completed"' <<<"$deploy_json" >/dev/null; then
  deploy_failure_summary="$(jq -r '
    def phase_problem:
      (.phases // {})
      | to_entries
      | map(select((.value.status // "") != "completed" and (.value.status // "") != "skipped"))
      | .[0] // null;
    (.status // "missing") as $deploy_status
    | phase_problem as $phase
    | "status=\($deploy_status)"
      + (
        if $phase == null then
          ""
        else
          "; phase \($phase.key) status=\($phase.value.status // "missing")"
          + (
            if ($phase.value.detail.exit_status // null) == null then
              ""
            else
              " exit_status=\($phase.value.detail.exit_status)"
            end
          )
        end
      )
  ' <<<"$deploy_json" 2>/dev/null || echo "status is not completed")"
  echo "release checklist failed: deployments/$public_env/deploy.latest.json is not completed: $(soraswap_redact_sensitive_text "$deploy_failure_summary")" >&2
  exit 1
fi
require_generated_at "contracts.latest.json" "$contracts_json"
if ! deployment_records_snapshot_matches_current_schema \
  "$evidence_dir/contracts.latest.json" \
  "$public_env"; then
  echo "release checklist failed: deployments/$public_env/contracts.latest.json does not match the closed current deployment-evidence schema" >&2
  exit 1
fi
if ! jq -e '.status == "completed"' <<<"$contracts_json" >/dev/null; then
  echo "release checklist failed: deployments/$public_env/contracts.latest.json is not completed" >&2
  exit 1
fi
if ! jq -e --argjson preflight "$preflight_json" '
  (($preflight.generated_at // "") | type == "string" and length > 0)
  and ((.generated_at // "") | type == "string" and length > 0)
  and (.generated_at >= ($preflight.generated_at // ""))
' <<<"$deploy_json" >/dev/null; then
  echo "release checklist failed: deploy.latest.json is older than current ready preflight" >&2
  exit 1
fi
if ! jq -e --argjson preflight "$preflight_json" --argjson deploy "$deploy_json" '
  (($preflight.generated_at // "") | type == "string" and length > 0)
  and (($deploy.generated_at // "") | type == "string" and length > 0)
  and ((.generated_at // "") | type == "string" and length > 0)
  and (.generated_at >= ($preflight.generated_at // ""))
  and (.generated_at >= ($deploy.generated_at // ""))
' <<<"$contracts_json" >/dev/null; then
  echo "release checklist failed: contracts.latest.json is older than current ready preflight or deploy report" >&2
  exit 1
fi
if ! jq -e --argjson contracts "$contracts_json" '
  def current_contract_snapshot_path($snapshot; $contracts_generated):
    ($snapshot | type) == "string"
    and ("contracts." + $contracts_generated + ".json") as $contracts_file
    | ($snapshot == $contracts_file or ($snapshot | endswith("/" + $contracts_file)));

  ($contracts.generated_at // "") as $contracts_generated
  | (($contracts_generated | type) == "string" and ($contracts_generated | length) > 0)
    and current_contract_snapshot_path((.phases.deployment_records_snapshot.detail.snapshot // ""); $contracts_generated)
' <<<"$deploy_json" >/dev/null; then
  echo "release checklist failed: deploy.latest.json deployment_records_snapshot detail does not reference current contracts.latest.json timestamp" >&2
  exit 1
fi
require_generated_at "smoke.latest.json" "$smoke_json"
require_generated_at "contract_console_smoke.latest.json" "$console_json"
require_generated_at "trader_readonly.latest.json" "$trader_readonly_json"
require_generated_at "trader.latest.json" "$trader_json"
require_generated_at "trader_api_bundle.latest.json" "$trader_api_json"

for artifact_path in "${required_preflight_evidence[@]}" "${required_release_evidence[@]}"; do
  require_no_local_path_leaks "$artifact_path"
done

require_selected_environment "chain.latest.json" "$chain_json"
require_selected_environment "deploy.latest.json" "$deploy_json"
require_selected_environment "contracts.latest.json" "$contracts_json"
require_selected_environment "nested_call_probe.latest.json" "$probe_json"
require_selected_environment "smoke.latest.json" "$smoke_json"
require_selected_environment "contract_console_smoke.latest.json" "$console_json"
require_selected_environment "trader_readonly.latest.json" "$trader_readonly_json"
require_selected_environment "trader.latest.json" "$trader_json"
require_selected_environment "trader_api_bundle.latest.json" "$trader_api_json"

if [[ ! -d "$ROOT/contracts" ]]; then
  echo "release checklist failed: contracts directory is missing at $(soraswap_display_path "$ROOT/contracts")" >&2
  exit 1
fi

required_contract_keys=()
for contract_source in "${(@f)$(find "$ROOT/contracts" -type f -name '*.ko' | LC_ALL=C sort)}"; do
  contract_key="${contract_source#$ROOT/contracts/}"
  contract_key="${contract_key%.ko}"
  required_contract_keys+=("${contract_key//\//.}")
done

if (( ${#required_contract_keys[@]} == 0 )); then
  echo "release checklist failed: no Kotodama contracts found under $(soraswap_display_path "$ROOT/contracts")" >&2
  exit 1
fi

contract_snapshot_keys=("${(@f)$(jq -r '
  (.contracts // [])[]?
  | select(type == "object")
  | (.contract_key // empty)
  | select(. != "")
' <<<"$contracts_json" | LC_ALL=C sort)}")

duplicate_contract_snapshot_keys=()
for contract_key in "${(@f)$(jq -r '
  [(.contracts // [])[]?
    | select(type == "object")
    | (.contract_key // empty)
    | select(. != "")]
  | group_by(.)
  | map(select(length > 1) | .[0])
  | .[]
' <<<"$contracts_json")}"; do
  [[ -n "$contract_key" ]] && duplicate_contract_snapshot_keys+=("$contract_key")
done

if (( ${#duplicate_contract_snapshot_keys[@]} > 0 )); then
  echo "release checklist failed: contracts.latest.json contains duplicate contract snapshots: ${duplicate_contract_snapshot_keys[*]}" >&2
  exit 1
fi

wrong_environment_contract_snapshot_keys=()
for contract_key in "${(@f)$(jq -r --arg public_env "$public_env" '
  (.contracts // [])[]?
  | select(type == "object")
  | select((((.environment // "") | type) != "string") or (.environment // "") != $public_env)
  | (.contract_key // "<unknown>")
' <<<"$contracts_json" | LC_ALL=C sort -u)}"; do
  [[ -n "$contract_key" ]] && wrong_environment_contract_snapshot_keys+=("$contract_key")
done

if (( ${#wrong_environment_contract_snapshot_keys[@]} > 0 )); then
  echo "release checklist failed: contracts.latest.json contains contract snapshots for the wrong environment: ${wrong_environment_contract_snapshot_keys[*]}" >&2
  exit 1
fi

contains_contract_key() {
  local needle="$1"
  local candidate

  for candidate in "${contract_snapshot_keys[@]}"; do
    if [[ "$candidate" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

contains_required_contract_key() {
  local needle="$1"
  local candidate

  for candidate in "${required_contract_keys[@]}"; do
    if [[ "$candidate" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

missing_contract_snapshot_keys=()
for contract_key in "${required_contract_keys[@]}"; do
  if ! contains_contract_key "$contract_key"; then
    missing_contract_snapshot_keys+=("$contract_key")
  fi
done

if (( ${#missing_contract_snapshot_keys[@]} > 0 )); then
  echo "release checklist failed: contracts.latest.json is missing required contract snapshots: ${missing_contract_snapshot_keys[*]}" >&2
  exit 1
fi

unexpected_contract_snapshot_keys=()
for contract_key in "${contract_snapshot_keys[@]}"; do
  required_match=false
  for required_contract_key in "${required_contract_keys[@]}"; do
    if [[ "$contract_key" == "$required_contract_key" ]]; then
      required_match=true
      break
    fi
  done
  if [[ "$required_match" != "true" ]]; then
    unexpected_contract_snapshot_keys+=("$contract_key")
  fi
done

if (( ${#unexpected_contract_snapshot_keys[@]} > 0 )); then
  echo "release checklist failed: contracts.latest.json contains stale or unknown contract snapshots: ${unexpected_contract_snapshot_keys[*]}" >&2
  exit 1
fi

for contract_deploy_path in "$evidence_dir"/*.deploy.json(N); do
  contract_deploy_json="$(cat "$contract_deploy_path")"
  require_generated_at "${contract_deploy_path:t}" "$contract_deploy_json"
  require_no_local_path_leaks "$contract_deploy_path"
  require_no_sensitive_diagnostic_leaks "$contract_deploy_path"
  contract_key="$(jq -r '.contract_key // empty' "$contract_deploy_path" 2>/dev/null || true)"
  if [[ -z "$contract_key" ]]; then
    echo "release checklist failed: $(soraswap_display_path "$contract_deploy_path") does not identify a current contract_key" >&2
    exit 1
  fi
  if [[ "${contract_deploy_path:t}" != "${contract_key}.deploy.json" ]]; then
    echo "release checklist failed: $(soraswap_display_path "$contract_deploy_path") contract_key does not match filename" >&2
    exit 1
  fi
  if ! deployment_record_matches_current_schema "$contract_deploy_path" "$public_env" "$contract_key"; then
    echo "release checklist failed: $(soraswap_display_path "$contract_deploy_path") does not match the closed current deployment-evidence schema" >&2
    exit 1
  fi
  if ! contains_required_contract_key "$contract_key"; then
    echo "release checklist failed: $(soraswap_display_path "$contract_deploy_path") is stale or unknown for current contracts/" >&2
    exit 1
  fi
  if ! contains_contract_key "$contract_key"; then
    echo "release checklist failed: $(soraswap_display_path "$contract_deploy_path") is not referenced by contracts.latest.json" >&2
    exit 1
  fi
done

for contract_manifest_path in "$evidence_dir"/*.manifest.json(N); do
  contract_key="${contract_manifest_path:t}"
  contract_key="${contract_key%.manifest.json}"
  if [[ -z "$contract_key" ]]; then
    echo "release checklist failed: $(soraswap_display_path "$contract_manifest_path") does not identify a current contract_key" >&2
    exit 1
  fi
  if ! contains_required_contract_key "$contract_key"; then
    echo "release checklist failed: $(soraswap_display_path "$contract_manifest_path") is stale or unknown for current contracts/" >&2
    exit 1
  fi
  if ! contains_contract_key "$contract_key"; then
    echo "release checklist failed: $(soraswap_display_path "$contract_manifest_path") is not referenced by contracts.latest.json" >&2
    exit 1
  fi
  contract_manifest_json="$(cat "$contract_manifest_path")"
  require_generated_at "${contract_manifest_path:t}" "$contract_manifest_json"
  require_selected_environment "${contract_manifest_path:t}" "$contract_manifest_json"
  require_no_local_path_leaks "$contract_manifest_path"
  require_no_sensitive_diagnostic_leaks "$contract_manifest_path"
  if ! jq -e --arg key "$contract_key" '.contract_key == $key' <<<"$contract_manifest_json" >/dev/null; then
    echo "release checklist failed: $(soraswap_display_path "$contract_manifest_path") manifest contract_key does not match filename" >&2
    exit 1
  fi
done

for contract_key in "${contract_snapshot_keys[@]}"; do
  contract_deploy_path="$evidence_dir/$contract_key.deploy.json"
  contract_manifest_path="$evidence_dir/$contract_key.manifest.json"
  if [[ ! -f "$contract_deploy_path" ]]; then
    echo "missing required release artifact: $(soraswap_display_path "$contract_deploy_path")" >&2
    exit 1
  fi
  if [[ ! -f "$contract_manifest_path" ]]; then
    echo "missing required release artifact: $(soraswap_display_path "$contract_manifest_path")" >&2
    exit 1
  fi
  contract_deploy_json="$(cat "$contract_deploy_path")"
  require_generated_at "${contract_deploy_path:t}" "$contract_deploy_json"
  require_no_local_path_leaks "$contract_deploy_path"
  require_no_sensitive_diagnostic_leaks "$contract_deploy_path"
  contract_manifest_json="$(cat "$contract_manifest_path")"
  require_generated_at "${contract_manifest_path:t}" "$contract_manifest_json"
  require_selected_environment "${contract_manifest_path:t}" "$contract_manifest_json"
  require_no_local_path_leaks "$contract_manifest_path"
  require_no_sensitive_diagnostic_leaks "$contract_manifest_path"
  if ! jq -e --arg key "$contract_key" '.contract_key == $key' <<<"$contract_manifest_json" >/dev/null; then
    echo "release checklist failed: $(soraswap_display_path "$contract_manifest_path") manifest contract_key does not match filename" >&2
    exit 1
  fi

  expected_contract_json="$(jq -c --arg key "$contract_key" '
    [(.contracts // [])[]? | select(type == "object") | select(.contract_key == $key)]
    | last
    // empty
  ' <<<"$contracts_json")"

  if ! jq -e \
    --arg key "$contract_key" \
    --argjson chain "$chain_json" \
    '.contract_key == $key
      and .chain_fingerprint != null
      and ((.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
      and .chain_fingerprint.torii_url == $chain.torii_url
      and .chain_fingerprint.chain == $chain.chain
      and .chain_fingerprint.block_1_hash == $chain.block_1_hash' \
    "$contract_deploy_path" >/dev/null; then
    echo "release checklist failed: $(soraswap_display_path "$contract_deploy_path") does not match contracts.latest.json and the current chain" >&2
    exit 1
  fi
  if ! jq -e --arg public_env "$public_env" \
    '((.environment // "") | type == "string") and .environment == $public_env' \
    "$contract_deploy_path" >/dev/null; then
    echo "release checklist failed: $(soraswap_display_path "$contract_deploy_path") was not recorded for selected environment $public_env" >&2
    exit 1
  fi

  expected_address="$(jq -r '.contract_address // ""' <<<"$expected_contract_json")"
  actual_address="$(jq -r '.contract_address // ""' "$contract_deploy_path")"
  if [[ -z "$expected_address" || -z "$actual_address" ]]; then
    echo "release checklist failed: $(soraswap_display_path "$contract_deploy_path") contract address is missing from contracts.latest.json or the deployment record" >&2
    exit 1
  fi
  if [[ "$expected_address" != "$actual_address" ]]; then
    echo "release checklist failed: $(soraswap_display_path "$contract_deploy_path") address does not match contracts.latest.json" >&2
    exit 1
  fi

  expected_nonce="$(jq -r '(.deploy_nonce // "") | tostring' <<<"$expected_contract_json")"
  actual_nonce="$(jq -r '(.deploy_nonce // "") | tostring' "$contract_deploy_path")"
  if [[ -z "$expected_nonce" || -z "$actual_nonce" ]]; then
    echo "release checklist failed: $(soraswap_display_path "$contract_deploy_path") deploy nonce is missing from contracts.latest.json or the deployment record" >&2
    exit 1
  fi
  if [[ "$expected_nonce" != "$actual_nonce" ]]; then
    echo "release checklist failed: $(soraswap_display_path "$contract_deploy_path") deploy nonce does not match contracts.latest.json" >&2
    exit 1
  fi

  expected_code_hash="$(jq -r '(.code_hash_hex // "") | ascii_downcase' <<<"$expected_contract_json")"
  expected_abi_hash="$(jq -r '(.abi_hash_hex // "") | ascii_downcase' <<<"$expected_contract_json")"
  if [[ -z "$expected_code_hash" || "$expected_code_hash" == "null" || -z "$expected_abi_hash" || "$expected_abi_hash" == "null" ]]; then
    echo "release checklist failed: contracts.latest.json is missing code_hash_hex or abi_hash_hex for $contract_key" >&2
    exit 1
  fi
  manifest_code_hash="$(manifest_code_hash_hex "$contract_manifest_path")"
  manifest_abi_hash="$(manifest_abi_hash_hex "$contract_manifest_path")"
  if [[ "$manifest_code_hash" != "$expected_code_hash" || "$manifest_abi_hash" != "$expected_abi_hash" ]]; then
    echo "release checklist failed: $(soraswap_display_path "$contract_manifest_path") hashes do not match contracts.latest.json" >&2
    exit 1
  fi

  if ! jq -e \
    --arg key "$contract_key" \
    --arg expected_address "$expected_address" \
    --arg expected_nonce "$expected_nonce" \
    --arg expected_code_hash "$expected_code_hash" \
    --arg expected_abi_hash "$expected_abi_hash" \
    '
      (.contract_key // "") == $key
      and (.deploy_strategy // "") == "ivm_contract_deploy"
      and ((.code_hash_hex // "") | ascii_downcase) == $expected_code_hash
      and ((.abi_hash_hex // "") | ascii_downcase) == $expected_abi_hash
      and .response.ok == true
      and .response.submitted == true
      and .response.contract_address == $expected_address
      and (((.response.deploy_nonce // null) | tostring) == $expected_nonce)
      and ((.response.code_hash_hex // "") | ascii_downcase) == $expected_code_hash
      and ((.response.commit_deployment_tx_hash // "") | type == "string" and length > 0)
      and .response.final.kind == "Committed"
      and .response.final.hash == .response.commit_deployment_tx_hash
    ' "$contract_deploy_path" >/dev/null; then
    echo "release checklist failed: $(soraswap_display_path "$contract_deploy_path") does not include one successful current native deploy response and code/ABI hash evidence" >&2
    exit 1
  fi
done

if ! jq -e '.status == "completed"' <<<"$deploy_json" >/dev/null; then
  echo "release checklist failed: deployments/$public_env/deploy.latest.json is not completed" >&2
  exit 1
fi

if ! jq -e '.status == "completed"' <<<"$smoke_json" >/dev/null; then
  echo "release checklist failed: smoke.latest.json is not completed" >&2
  exit 1
fi
require_public_smoke_mutation_evidence

if ! jq -e '.status == "completed"' <<<"$console_json" >/dev/null; then
  echo "release checklist failed: contract_console_smoke.latest.json is not completed" >&2
  exit 1
fi

if ! jq -e --arg public_env "$public_env" --argjson chain "$chain_json" --argjson rwa_release_enabled "$rwa_release_enabled_json" '
  def trim_ref:
    gsub("^\\s+|\\s+$"; "");
  def valid_external_ref:
    if type != "string" then false
    else
      (trim_ref) as $ref
      | ($ref | length > 0)
      and (($ref | test("[[:cntrl:]]")) | not)
      and (((($ref | startswith("<")) and ($ref | endswith(">"))) | not))
      and (($ref | test("change[_ -]?me|changeme|replace[_ -]?me|replaceme|todo|tbd|placeholder"; "i")) | not)
      and (($ref | test("^(none|null|n/?a|example)$"; "i")) | not)
          and (($ref | test("(^|[^A-Za-z0-9_-])(([A-Za-z0-9-]+\\.)*(example|invalid|test|localhost)|([A-Za-z0-9-]+\\.)*example\\.(com|org|net))([/:[:space:]]|$)|127\\.0\\.0\\.1|0\\.0\\.0\\.0|\\[::1\\]|\\[::\\]|external .* id or url"; "i")) | not)
        end;
  def current_chain:
    ((.generated_at // "") | type == "string" and length > 0)
    and (.environment // "") == $public_env
    and (.chain_fingerprint.torii_url // null) == ($chain.torii_url // null)
    and (.chain_fingerprint.chain // null) == ($chain.chain // null)
    and (.chain_fingerprint.block_1_hash // null) == ($chain.block_1_hash // null);
  def completed_refs:
    .status == "completed"
    and ((.issuer_approval_ref // "") | valid_external_ref)
    and ((.legal_review_ref // "") | valid_external_ref)
    and ((.compliance_policy_ref // "") | valid_external_ref)
    and ((.nav_source_ref // "") | valid_external_ref)
    and ((.redemption_terms_ref // "") | valid_external_ref);
  def not_applicable:
    .status == "not_applicable"
    and .rwa_release_enabled == false
    and ((.reason // "") | type == "string" and length > 0);
  current_chain and (if $rwa_release_enabled then completed_refs else not_applicable end)
' <<<"$rwa_compliance_json" >/dev/null; then
  echo "release checklist failed: rwa_compliance.latest.json must match the current chain fingerprint and include completed control-character-free, non-placeholder, non-local/wildcard, non-reserved-domain issuer_approval_ref, legal_review_ref, compliance_policy_ref, nav_source_ref, and redemption_terms_ref when SORASWAP_ENABLE_RWA_RELEASE=1, or record status not_applicable with rwa_release_enabled=false when the public RWA release is disabled" >&2
  exit 1
fi
rwa_compliance_notes="$(jq -r '.notes // empty' <<<"$rwa_compliance_json" 2>/dev/null || true)"
if [[ -n "$rwa_compliance_notes" && "$rwa_compliance_notes" != "$(soraswap_redact_sensitive_text "$rwa_compliance_notes")" ]]; then
  echo "release checklist failed: rwa_compliance.latest.json notes contain unredacted sensitive diagnostics; rerun make record-${public_env}-rwa-compliance" >&2
  exit 1
fi
if ! jq -e --argjson preflight "$preflight_json" '
  (($preflight.generated_at // "") | type == "string" and length > 0)
  and ((.generated_at // "") | type == "string" and length > 0)
  and (.generated_at >= ($preflight.generated_at // ""))
' <<<"$rwa_compliance_json" >/dev/null; then
  echo "release checklist failed: rwa_compliance.latest.json is older than current ready preflight" >&2
  exit 1
fi

if ! jq -e '.status == "completed"' <<<"$trader_readonly_json" >/dev/null; then
  trader_readonly_reason="$(jq -r '.blocked_reason // empty' <<<"$trader_readonly_json" 2>/dev/null || true)"
  if [[ -n "$trader_readonly_reason" ]]; then
    echo "release checklist failed: trader_readonly.latest.json is not completed: $(soraswap_redact_sensitive_text "$trader_readonly_reason")" >&2
  else
    echo "release checklist failed: trader_readonly.latest.json is not completed" >&2
  fi
  exit 1
fi

if ! jq -e '.status == "completed"' <<<"$trader_json" >/dev/null; then
  trader_reason="$(jq -r '.blocked_reason // empty' <<<"$trader_json" 2>/dev/null || true)"
  if [[ -n "$trader_reason" ]]; then
    echo "release checklist failed: trader.latest.json is not completed: $(soraswap_redact_sensitive_text "$trader_reason")" >&2
  else
    echo "release checklist failed: trader.latest.json is not completed" >&2
  fi
  exit 1
fi

if ! jq -e '.status == "completed"' <<<"$trader_api_json" >/dev/null; then
  echo "release checklist failed: trader_api_bundle.latest.json is not completed" >&2
  exit 1
fi

if ! jq -e '
  def positive_count:
    type == "number" and . > 0 and . == floor;
  def nonnegative_count:
    type == "number" and . >= 0 and . == floor;

  (.content_cid // "") as $cid
  | (($cid | test("^b[a-z2-7]+$"))
    and ((.manifest_digest_hex // "") | test("^[0-9a-fA-F]{64}$"))
    and (.cid_probe.status // "") == "completed"
    and ((.cid_probe.attempt_count // null) | positive_count)
    and ((.cid_probe.success_count // null) | nonnegative_count)
    and ((.cid_probe.manifest_match_count // null) | nonnegative_count)
    and (.cid_probe.success_count == .cid_probe.attempt_count)
    and (.cid_probe.manifest_match_count == .cid_probe.attempt_count)
    and ((.cid_probe.url // "") | endswith("/v1/app-api/cid/" + $cid)))
' <<<"$trader_api_json" >/dev/null; then
  echo "release checklist failed: trader_api_bundle.latest.json is missing CID, manifest digest, routes, or successful CID probe" >&2
  exit 1
fi

if ! jq -e '
  def has_route($method; $path; $adapter):
    any((.routes // [])[];
      (.method // "") == $method
      and (.path // "") == $path
      and (.adapter // "") == $adapter
    );

  ((.routes // []) | length) == 11
  and has_route("POST"; "/v1/contracts/view/batch"; "contract.view_batch.v1")
  and has_route("GET"; "/v1/contracts/rollups/swaps/fills"; "contract.rollups.swaps_fills.v1")
  and has_route("GET"; "/v1/contracts/rollups/swaps/candles"; "contract.rollups.swaps_candles.v1")
  and has_route("GET"; "/v1/contracts/rollups/trader/activity"; "contract.rollups.trader_activity.v1")
  and has_route("GET"; "/v1/contracts/rollups/trader/account"; "contract.rollups.trader_account.v1")
  and has_route("GET"; "/v1/contracts/rollups/intents"; "contract.rollups.intents.v1")
  and has_route("GET"; "/v1/contracts/rollups/vaults/positions"; "contract.rollups.vault_positions.v1")
  and has_route("GET"; "/v1/contracts/rollups/operators/status"; "contract.rollups.operators_status.v1")
  and has_route("GET"; "/v1/contracts/rollups/margin/health"; "contract.rollups.margin_health.v1")
  and has_route("GET"; "/v1/contracts/rollups/rwa/lots"; "contract.rollups.rwa_lots.v1")
  and has_route("GET"; "/v1/contracts/rollups/dlmm/hooks"; "contract.rollups.dlmm_hooks.v1")
' <<<"$trader_api_json" >/dev/null; then
  echo "release checklist failed: trader_api_bundle.latest.json does not expose the exact required trader API routes" >&2
  exit 1
fi

if ! jq -e '
  def has_route($routes; $method; $path; $adapter):
    any($routes[];
      (.method // "") == $method
      and (.path // "") == $path
      and (.adapter // "") == $adapter
    );

  def has_required_routes($routes):
    ($routes | length) == 11
    and has_route($routes; "POST"; "/v1/contracts/view/batch"; "contract.view_batch.v1")
    and has_route($routes; "GET"; "/v1/contracts/rollups/swaps/fills"; "contract.rollups.swaps_fills.v1")
    and has_route($routes; "GET"; "/v1/contracts/rollups/swaps/candles"; "contract.rollups.swaps_candles.v1")
    and has_route($routes; "GET"; "/v1/contracts/rollups/trader/activity"; "contract.rollups.trader_activity.v1")
    and has_route($routes; "GET"; "/v1/contracts/rollups/trader/account"; "contract.rollups.trader_account.v1")
    and has_route($routes; "GET"; "/v1/contracts/rollups/intents"; "contract.rollups.intents.v1")
    and has_route($routes; "GET"; "/v1/contracts/rollups/vaults/positions"; "contract.rollups.vault_positions.v1")
    and has_route($routes; "GET"; "/v1/contracts/rollups/operators/status"; "contract.rollups.operators_status.v1")
    and has_route($routes; "GET"; "/v1/contracts/rollups/margin/health"; "contract.rollups.margin_health.v1")
    and has_route($routes; "GET"; "/v1/contracts/rollups/rwa/lots"; "contract.rollups.rwa_lots.v1")
    and has_route($routes; "GET"; "/v1/contracts/rollups/dlmm/hooks"; "contract.rollups.dlmm_hooks.v1");

  (.cid_probe.parsed // {}) as $parsed
  | ((.app_id // "") | length > 0)
    and (($parsed.schema_version // 0) == 1)
    and (($parsed.app_id // "") == (.app_id // ""))
    and (($parsed.content_cid // "") == (.content_cid // ""))
    and (($parsed.manifest_digest_hex // "") == (.manifest_digest_hex // ""))
    and has_required_routes($parsed.routes // [])
' <<<"$trader_api_json" >/dev/null; then
  echo "release checklist failed: trader_api_bundle.latest.json CID probe did not return the expected trader API manifest" >&2
  exit 1
fi

if ! jq -e '
  ((.provider_ingest.state // "") == "awaiting_finalized_provider_assignment")
  and (.provider_ingest.queued == false)
  and (.provider_ingest.direct_http_ingest == false)
  and ((.provider_ingest.prepare.manifest_id_hex // "") | test("^[0-9a-fA-F]+$"))
  and ((.manifest_id_hex // "") == (.provider_ingest.prepare.manifest_id_hex // ""))
  and ((.provider_ingest.prepare.manifest_digest_hex // "") == (.manifest_digest_hex // ""))
  and ((.registry_submit.manifest_digest_hex // "") == (.manifest_digest_hex // ""))
  and (((.registry_submit.status // "") | tostring) | test("^2"))
' <<<"$trader_api_json" >/dev/null; then
  echo "release checklist failed: trader_api_bundle.latest.json is missing matching provider preparation or manifest registration evidence" >&2
  exit 1
fi

trader_api_manifest_id_hex="$(jq -r '.provider_ingest.prepare.manifest_id_hex // empty' <<<"$trader_api_json")"
trader_api_actual_cid="$(jq -r '.content_cid // empty' <<<"$trader_api_json")"
trader_api_expected_cid="$(content_cid_from_hex "$trader_api_manifest_id_hex" 2>/dev/null || true)"
if [[ -z "$trader_api_expected_cid" || "$trader_api_actual_cid" != "$trader_api_expected_cid" ]]; then
  echo "release checklist failed: trader_api_bundle.latest.json content_cid does not match the prepared manifest id" >&2
  exit 1
fi

if ! jq -e '(.deployment_record_check.status // "") == "completed"' <<<"$trader_api_json" >/dev/null; then
  echo "release checklist failed: trader_api_bundle.latest.json did not complete deployment-record freshness check" >&2
  exit 1
fi

require_not_older_than_current_snapshots "trader_api_bundle.latest.json" "$trader_api_json"

require_current_snapshots "trader_api_bundle.latest.json" "$trader_api_json"
require_snapshot_check_completed "trader_api_bundle.latest.json" "$trader_api_json"

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
if ! jq -e '
  ((.phases.preflight.detail.signer_ready_check.status // "") == "completed")
  and ((.phases.preflight.detail.signer_ready_check.debug_bypass_env // null) == null)
' <<<"$deploy_json" >/dev/null; then
  echo "release checklist failed: deploy.latest.json preflight did not prove signer readiness without debug bypass" >&2
  exit 1
fi

if ! jq -e '.supported == true' <<<"$probe_json" >/dev/null; then
  probe_summary="$(jq -r '.summary // empty' <<<"$probe_json" 2>/dev/null || true)"
  if [[ -n "$probe_summary" ]]; then
    echo "release checklist failed: $(soraswap_redact_sensitive_text "$probe_summary")" >&2
  else
    echo "release checklist failed: nested_call_probe.latest.json shows public $public_display_label nested call support is unavailable" >&2
  fi
  exit 1
fi

if ! jq -e \
  --arg public_env "$public_env" \
  --argjson probe "$probe_json" \
  '
    (.nested_call_probe.generated_at // null) == ($probe.generated_at // null)
    and (.nested_call_probe.environment // null) == ($probe.environment // null)
    and (.nested_call_probe.environment // null) == $public_env
    and (($probe.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
    and ((.nested_call_probe.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
    and (.nested_call_probe.chain_fingerprint.torii_url // null) == ($probe.chain_fingerprint.torii_url // null)
    and (.nested_call_probe.chain_fingerprint.chain // null) == ($probe.chain_fingerprint.chain // null)
    and (.nested_call_probe.chain_fingerprint.block_1_hash // null) == ($probe.chain_fingerprint.block_1_hash // null)
    and (.nested_call_probe.supported // false) == true
  ' <<<"$smoke_json" >/dev/null; then
  echo "release checklist failed: smoke.latest.json does not reference the current nested-call/contracts/deploy snapshots" >&2
  exit 1
fi
require_current_snapshots "smoke.latest.json" "$smoke_json" "does not reference the current nested-call/contracts/deploy snapshots"
require_snapshot_check_completed "smoke.latest.json" "$smoke_json"

if ! jq -e \
  --arg public_env "$public_env" \
  --argjson chain "$chain_json" \
  --argjson contracts "$contracts_json" \
  --argjson deploy "$deploy_json" \
  '
    def snapshot_matches($snapshot; $current):
      ($snapshot | type) == "object"
      and ($snapshot.generated_at // null) == ($current.generated_at // null)
      and ($snapshot.status // null) == ($current.status // null)
      and ($snapshot.environment // null) == ($current.environment // null)
      and ($snapshot.environment // null) == $public_env
      and (($current.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
      and (($snapshot.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
      and ($snapshot.chain_fingerprint.torii_url // null) == ($current.chain_fingerprint.torii_url // null)
      and ($snapshot.chain_fingerprint.chain // null) == ($current.chain_fingerprint.chain // null)
      and ($snapshot.chain_fingerprint.block_1_hash // null) == ($current.chain_fingerprint.block_1_hash // null);

    (.readonly_verification | type) == "object"
    and ((.readonly_verification.environment // "") == $public_env)
    and (((.readonly_verification.generated_at // "") | length) > 0)
    and ((.readonly_verification.generated_at // "") <= (.generated_at // ""))
    and (($chain.torii_url // "") | type == "string" and length > 0)
    and ((.readonly_verification.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
    and (.readonly_verification.chain_fingerprint.torii_url // null) == ($chain.torii_url // null)
    and (.readonly_verification.chain_fingerprint.chain // null) == ($chain.chain // null)
    and (.readonly_verification.chain_fingerprint.block_1_hash // null) == ($chain.block_1_hash // null)
    and snapshot_matches(.readonly_verification.contracts_snapshot; $contracts)
    and snapshot_matches(.readonly_verification.deploy_snapshot; $deploy)
    and (.readonly_verification.deploy_snapshot.status // null) == ($deploy.status // null)
  ' <<<"$smoke_json" >/dev/null; then
  echo "release checklist failed: smoke.latest.json does not embed current readonly smoke snapshot evidence" >&2
  exit 1
fi

require_current_snapshots "contract_console_smoke.latest.json" "$console_json"
require_snapshot_check_completed "contract_console_smoke.latest.json" "$console_json"

if ! jq -e '
  def hash32: type == "string" and test("^[0-9a-f]{64}$") and test("[^0]");
  (.bridge.torii_sccp_v1 // false) == true
  and ((.bridge.destination_message_id // "") | hash32)
  and ((.bridge.native_message_id // "") | hash32)
  and (.bridge.destination_message_id == .bridge.governed_route_provenance.destination.message_id_hex)
  and (.bridge.native_message_id == .bridge.governed_route_provenance.native.message_id_hex)
  and (.bridge.governed_route_provenance.destination.validated_by == "state_derived_sccp_proof_request")
  and (.bridge.governed_route_provenance.native.validated_by == "authoritative_typed_sccp_registry")
  and ((.bridge.governed_route_provenance.destination.route_configuration_hash_hex // "") | hash32)
  and ((.bridge.governed_route_provenance.native.route_configuration_hash_hex // "") | hash32)
  and ((.bridge.governed_route_provenance.native.counterparty_chain // "") | type == "string" and length > 0)
  and (.discovery.capabilities.response_json.registry_path == "/v1/sccp/registry")
  and (.discovery.capabilities.response_json.proof_request_path == "/v1/sccp/proof-requests/{message_id}")
  and (.discovery.capabilities.response_json.proof_submit_path == "/v1/bridge/proofs/submit")
  and (.discovery.capabilities.response_json.native_message_submit_path == "/v1/bridge/messages")
  and ((.discovery.registry.response_json // null) | type == "object")
  and ((.discovery.proof_request.response_json // null) | type == "object")
' <<<"$console_json" >/dev/null; then
  echo "release checklist failed: contract_console_smoke.latest.json does not prove current Torii SCCP V1 governed proof admission" >&2
  exit 1
fi

if ! jq -e '
  def tx_hash_hex:
    type == "string" and test("^[0-9a-fA-F]{64}$");
  (.bridge.submission_expectation // "") == "apply"
  and ((.submissions.proof_submit.tx_hash_hex // "") | tx_hash_hex)
  and ((.submissions.message_submit.tx_hash_hex // "") | tx_hash_hex)
' <<<"$console_json" >/dev/null; then
  echo "release checklist failed: contract_console_smoke.latest.json does not record valid bridge submission transaction hashes" >&2
  exit 1
fi

require_current_snapshots "trader_readonly.latest.json" "$trader_readonly_json"
require_current_snapshots "trader.latest.json" "$trader_json"
require_snapshot_check_completed "trader_readonly.latest.json" "$trader_readonly_json"
require_snapshot_check_completed "trader.latest.json" "$trader_json"

if ! jq -e '
  def required_route_keys:
    [
      "view_batch",
      "swaps_fills",
      "swaps_candles",
      "trader_activity",
      "trader_account",
      "intents",
      "vault_positions",
      "operators_status",
      "margin_health",
      "rwa_lots",
      "dlmm_hooks"
    ];

  def required_route_specs:
    {
      view_batch: {method: "POST", path: "/v1/contracts/view/batch"},
      swaps_fills: {method: "GET", path: "/v1/contracts/rollups/swaps/fills", required_query_params: ["authority", "limit"]},
      swaps_candles: {method: "GET", path: "/v1/contracts/rollups/swaps/candles", required_query_params: ["authority", "limit", "bucket_secs"]},
      trader_activity: {method: "GET", path: "/v1/contracts/rollups/trader/activity", required_query_params: ["authority", "limit"]},
      trader_account: {method: "GET", path: "/v1/contracts/rollups/trader/account", required_query_params: ["authority"]},
      intents: {method: "GET", path: "/v1/contracts/rollups/intents", required_query_params: ["authority", "limit"]},
      vault_positions: {method: "GET", path: "/v1/contracts/rollups/vaults/positions", required_query_params: ["authority", "limit"]},
      operators_status: {method: "GET", path: "/v1/contracts/rollups/operators/status", required_query_params: ["authority", "limit"]},
      margin_health: {method: "GET", path: "/v1/contracts/rollups/margin/health", required_query_params: ["authority", "limit"]},
      rwa_lots: {method: "GET", path: "/v1/contracts/rollups/rwa/lots", required_query_params: ["authority", "limit"]},
      dlmm_hooks: {method: "GET", path: "/v1/contracts/rollups/dlmm/hooks", required_query_params: ["authority", "limit"]}
    };

  def path_matches($actual; $expected):
    ($actual == $expected) or ($actual | startswith($expected + "?"));

  def has_query_param($actual; $param):
    $actual | test("[?&]" + $param + "=[^&#]+");

  def route_matches($actual; $spec):
    path_matches($actual; $spec.path)
    and all(($spec.required_query_params // [])[]; has_query_param($actual; .));

  def all_required_routes_ok($routes):
    ($routes | type) == "object"
    and ($routes | keys_unsorted) as $keys
    | (($keys - required_route_keys) | length) == 0
      and ((required_route_keys - $keys) | length) == 0
      and all(required_route_keys[];
        . as $key
        | (required_route_specs[$key]) as $spec
        | (($routes[$key] // {}).ok // false) == true
          and (($routes[$key] // {}).http_code // 0) == 200
          and (($routes[$key] // {}).method // "") == $spec.method
          and route_matches((($routes[$key] // {}).path // ""); $spec)
      );

  ((.route_probes.required_missing // []) | length) == 0
  and all_required_routes_ok(.route_probes.required_before // {})
' <<<"$trader_readonly_json" >/dev/null; then
  echo "release checklist failed: trader_readonly.latest.json does not prove all required trader routes returned HTTP 200 with required query parameters" >&2
  exit 1
fi

if ! jq -e '
  def required_route_keys:
    [
      "view_batch",
      "swaps_fills",
      "swaps_candles",
      "trader_activity",
      "trader_account",
      "intents",
      "vault_positions",
      "operators_status",
      "margin_health",
      "rwa_lots",
      "dlmm_hooks"
    ];

  def required_route_specs:
    {
      view_batch: {method: "POST", path: "/v1/contracts/view/batch"},
      swaps_fills: {method: "GET", path: "/v1/contracts/rollups/swaps/fills", required_query_params: ["authority", "limit"]},
      swaps_candles: {method: "GET", path: "/v1/contracts/rollups/swaps/candles", required_query_params: ["authority", "limit", "bucket_secs"]},
      trader_activity: {method: "GET", path: "/v1/contracts/rollups/trader/activity", required_query_params: ["authority", "limit"]},
      trader_account: {method: "GET", path: "/v1/contracts/rollups/trader/account", required_query_params: ["authority"]},
      intents: {method: "GET", path: "/v1/contracts/rollups/intents", required_query_params: ["authority", "limit"]},
      vault_positions: {method: "GET", path: "/v1/contracts/rollups/vaults/positions", required_query_params: ["authority", "limit"]},
      operators_status: {method: "GET", path: "/v1/contracts/rollups/operators/status", required_query_params: ["authority", "limit"]},
      margin_health: {method: "GET", path: "/v1/contracts/rollups/margin/health", required_query_params: ["authority", "limit"]},
      rwa_lots: {method: "GET", path: "/v1/contracts/rollups/rwa/lots", required_query_params: ["authority", "limit"]},
      dlmm_hooks: {method: "GET", path: "/v1/contracts/rollups/dlmm/hooks", required_query_params: ["authority", "limit"]}
    };

  def path_matches($actual; $expected):
    ($actual == $expected) or ($actual | startswith($expected + "?"));

  def has_query_param($actual; $param):
    $actual | test("[?&]" + $param + "=[^&#]+");

  def route_matches($actual; $spec):
    path_matches($actual; $spec.path)
    and all(($spec.required_query_params // [])[]; has_query_param($actual; .));

  def all_required_routes_ok($routes):
    ($routes | type) == "object"
    and ($routes | keys_unsorted) as $keys
    | (($keys - required_route_keys) | length) == 0
      and ((required_route_keys - $keys) | length) == 0
      and all(required_route_keys[];
        . as $key
        | (required_route_specs[$key]) as $spec
        | (($routes[$key] // {}).ok // false) == true
          and (($routes[$key] // {}).http_code // 0) == 200
          and (($routes[$key] // {}).method // "") == $spec.method
          and route_matches((($routes[$key] // {}).path // ""); $spec)
      );

  ((.route_probes.required_missing // []) | length) == 0
  and ((.route_probes.required_after_missing // []) | length) == 0
  and all_required_routes_ok(.route_probes.required_before // {})
  and all_required_routes_ok(.route_probes.required_after // {})
' <<<"$trader_json" >/dev/null; then
  echo "release checklist failed: trader.latest.json does not prove all required trader routes returned HTTP 200 with required query parameters before and after mutation" >&2
  exit 1
fi

if ! jq -e '
  def tx_hash_hex:
    type == "string" and test("^[0-9a-fA-F]{64}$");
  def positive_number:
    type == "number" and . > 0;
  def nonnegative_number:
    type == "number" and . >= 0;
  def numeric_value:
    if type == "number" then .
    elif type == "string" then (try tonumber catch null)
    else null end;

  (.mutation.swap.balances_before.xor // null | numeric_value) as $xor_before
  | (.mutation.swap.balances_after.xor // null | numeric_value) as $xor_after
  | (.mutation.swap.balances_before.usdt // null | numeric_value) as $usdt_before
  | (.mutation.swap.balances_after.usdt // null | numeric_value) as $usdt_after
  | (.mutation.signer_ready.status // "") == "completed"
  and (.mutation.swap.status // "") == "completed"
  and ((.mutation.swap.tx_hash // "") | tx_hash_hex)
  and ((.mutation.swap.contract_address // "") == (.contracts.swaps // ""))
  and ((.mutation.swap.entrypoint // "") == "route_swap")
  and ((.mutation.swap.amount_in // null) | positive_number)
  and ((.mutation.swap.input_is_base // 0) == 1)
  and ((.mutation.swap.min_out // null) | nonnegative_number)
  and ($xor_before != null)
  and ($xor_after != null)
  and ($usdt_before != null)
  and ($usdt_after != null)
  and ($xor_after < $xor_before)
  and ($usdt_after > $usdt_before)
' <<<"$trader_json" >/dev/null; then
  echo "release checklist failed: trader.latest.json is missing signed route_swap evidence with balance deltas" >&2
  exit 1
fi

if ! jq -e '(.bridge.route_provenance[0] // 0) == 1' <<<"$console_json" >/dev/null; then
  echo "release checklist failed: contract_console_smoke.latest.json does not prove a governed bridge route" >&2
  exit 1
fi

require_not_older_than_current_snapshots "contract_console_smoke.latest.json" "$console_json"
require_not_older_than_current_snapshots "trader_readonly.latest.json" "$trader_readonly_json"
require_not_older_than_current_snapshots "trader.latest.json" "$trader_json"

if ! jq -e '
  (.bridge.submission_expectation // "") == "apply"
  and ((.submissions.proof_status.status_kind // "") | test("^(Applied|Committed)$"))
  and ((.submissions.message_status.status_kind // "") | test("^(Applied|Committed)$"))
' <<<"$console_json" >/dev/null; then
  echo "release checklist failed: contract_console_smoke.latest.json does not record a valid bridge submission outcome" >&2
  exit 1
fi

require_taira_release_gate_for_production

for artifact_path in "${required_preflight_evidence[@]}" "${required_release_evidence[@]}"; do
  require_no_sensitive_diagnostic_leaks "$artifact_path"
done

if [[ "$public_env" == "testnet" && "$taira_prereq_only" == "1" ]]; then
  echo "release checklist ok"
  echo "  ported: $ported_count"
  echo "  reference-only: $reference_only_count"
  echo "  docs: ${#required_docs[@]} present"
  echo "  evidence: ${#required_evidence[@]} present under deployments/$public_env"
  echo "  local acceptance: skipped for production prerequisite"
  exit 0
fi

configure_local_acceptance_pin
require_production_cutover_evidence

if [[ "$closeout_mode" != "normal" && "$local_acceptance_pin_enabled" != "1" ]]; then
  echo "release checklist failed: full release closeout requires exact-candidate local acceptance pin settings" >&2
  exit 1
fi

if [[ "$closeout_mode" == "resume" ]]; then
  verify_local_acceptance_pin_unchanged "during status-doc closeout resume"
  release_closeout_checkpoint_state verify-all >/dev/null
fi

run_local_acceptance_target() {
  local target="$1"

  (
    unset RELEASE_CHECKLIST_INTERNAL_TOKEN
    unset SORASWAP_CLIENT_CONFIG SORASWAP_PRODUCTION_CLIENT_CONFIG
    unset SORASWAP_TORII_URL SORASWAP_TORII_API_TOKEN CHAIN
    unset ACCOUNT_CHAIN_DISCRIMINANT IROHA_ACCOUNT_CHAIN_DISCRIMINANT
    unset SORASWAP_ALLOW_TESTNET_MUTATIONS SORASWAP_ALLOW_PRODUCTION_MUTATIONS
    unset SORASWAP_PUBLIC_ENV SORASWAP_RELEASE_ENV
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
    unset SORASWAP_TAIRA_REPAIR_REPORT_DIR SORASWAP_TAIRA_REPAIR_SNAPSHOT_POLICY
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
    unset SORASWAP_TAIRA_ONBOARDING_TOKEN_FILE
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
    clear_inherited_iroha_tool_env
    clear_inherited_make_control_env
    unset RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_TOKEN RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_JOURNAL
    if [[ "$local_acceptance_pin_enabled" == "1" ]] && local_acceptance_target_uses_candidate "$target"; then
      verify_local_acceptance_pin_unchanged "before make $target"
      export_local_acceptance_pin_for_target "$target"
    fi
    if [[ "$closeout_mode" == "prepare" && "$target" == "check-shell-syntax" ]]; then
      zsh "$ROOT/scripts/check_shell_syntax.sh" --prepare-status-doc-closeout
    elif [[ "$closeout_mode" == "prepare" && "$target" == "test-public-env-helpers" ]]; then
      zsh "$ROOT/tests/public_env_helper_smoke.sh" --prepare-status-doc-closeout
    else
      make -C "$ROOT" "$target"
    fi
    if [[ "$local_acceptance_pin_enabled" == "1" ]] && local_acceptance_target_uses_candidate "$target"; then
      verify_local_acceptance_pin_unchanged "after make $target"
    fi
  )
}

capture_local_doc_generated_at_values

run_strict_closeout_diff_checks() {
  echo "release checklist: strict git diff --cached --check"
  git -C "$ROOT" diff --cached --check
  echo "release checklist: strict git diff --check"
  git -C "$ROOT" diff --check
  echo "release checklist: strict git diff HEAD --check"
  git -C "$ROOT" diff HEAD --check
}

if [[ "$closeout_mode" == "resume" ]]; then
  echo "release checklist: closeout resume reuses checkpointed local acceptance; signed public phases and local E2E will not rerun"
  echo "release checklist: strict make check-shell-syntax"
  zsh "$ROOT/scripts/check_shell_syntax.sh"
  echo "release checklist: strict generated-evidence redaction check"
  zsh "$ROOT/scripts/redact_generated_evidence.sh" --check
  run_strict_closeout_diff_checks
  verify_local_acceptance_pin_unchanged "immediately before intermediate closeout checkpoint verification"
  release_closeout_checkpoint_state verify-all >/dev/null
else
  for target in "${local_acceptance_targets[@]}"; do
    echo "release checklist: make $target"
    run_local_acceptance_target "$target"
  done
fi

for artifact_path in "${required_local_evidence[@]}"; do
  if [[ ! -f "$artifact_path" ]]; then
    echo "missing required release artifact: $(soraswap_display_path "$artifact_path")" >&2
    if [[ "$artifact_path" == "$ROOT/artifacts/telemetry/defi_2026_primitives_latest.json" ]]; then
      echo "generate local primitive telemetry with: make simulate-full" >&2
    elif [[ "$artifact_path" == "$ROOT/deployments/local/chain.latest.json" \
      || "$artifact_path" == "$ROOT/deployments/local/deploy.latest.json" \
      || "$artifact_path" == "$ROOT/deployments/local/contracts.latest.json" \
      || "$artifact_path" == "$ROOT/deployments/local/smoke.latest.json" ]]; then
      echo "generate local chain/deploy/smoke evidence with: make test-local-isolated" >&2
    fi
    exit 1
  fi
  require_no_local_path_leaks "$artifact_path"
  require_no_sensitive_diagnostic_leaks "$artifact_path"
done

local_chain_json="$(cat "$ROOT/deployments/local/chain.latest.json")"
if ! jq -e '
  ((.generated_at // "") | type == "string" and length > 0)
  and .environment == "local"
  and ((.torii_url // "") | type == "string" and length > 0)
  and ((.chain // "") | type == "string" and length > 0)
  and ((.block_1_hash // "") | type == "string" and length > 0)
' <<<"$local_chain_json" >/dev/null; then
  echo "release checklist failed: deployments/local/chain.latest.json must record a completed local chain fingerprint; rerun make test-local-isolated" >&2
  exit 1
fi

expected_local_contract_keys_json="$(expected_contract_ids | json_array_from_lines)"
if ! jq -e --argjson expected_keys "$expected_local_contract_keys_json" '
  ($expected_keys | unique | sort) as $expected
  | . as $root
  | ["preflight", "bootstrap_assets", "compile", "deploy", "bootstrap_contract_state", "deployment_records_snapshot"] as $required_phases
  | (($expected | length) > 0)
  and all($required_phases[]; (($root.phases[.].status // "") == "completed"))
  and ((.generated_at // "") | type == "string" and length > 0)
  and .environment == "local"
  and .status == "completed"
  and .phases.deploy.status == "completed"
  and .phases.deploy.detail.strategy == "ivm_contract_deploy_per_contract"
  and .phases.deploy.detail.deploy_scope == "full"
  and (.phases.deploy.detail.contract_count == ($expected | length))
  and ((.phases.deploy.detail | keys | sort) == ["contract_count", "deploy_scope", "strategy"])
  and .phases.bootstrap_contract_state.status == "completed"
  and .phases.deployment_records_snapshot.status == "completed"
' "$ROOT/deployments/local/deploy.latest.json" >/dev/null; then
  echo "release checklist failed: deployments/local/deploy.latest.json must record a completed full local deploy; rerun make test-local-isolated" >&2
  exit 1
fi
if ! deployment_records_snapshot_matches_current_schema \
  "$ROOT/deployments/local/contracts.latest.json" \
  local; then
  echo "release checklist failed: deployments/local/contracts.latest.json does not match the closed current deployment-evidence schema; rerun make test-local-isolated" >&2
  exit 1
fi
if ! jq -e --argjson expected_keys "$expected_local_contract_keys_json" '
  def hex_hash:
    type == "string" and test("^[0-9a-fA-F]{64}$");
  def matching_chain($snapshot_chain):
    (.chain_fingerprint != null)
    and ((.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
    and (.chain_fingerprint.torii_url // null) == ($snapshot_chain.torii_url // null)
    and (.chain_fingerprint.chain // null) == ($snapshot_chain.chain // null)
    and (.chain_fingerprint.block_1_hash // null) == ($snapshot_chain.block_1_hash // null);
  def complete_contract_snapshot($snapshot_chain):
    ((.contract_address // "") | type == "string" and length > 0)
    and ((.deploy_nonce // null) | type == "number" and . >= 0 and floor == .)
    and ((.code_hash_hex // "") | hex_hash)
    and ((.abi_hash_hex // "") | hex_hash)
    and matching_chain($snapshot_chain);
  def snapshot_keys:
    [.contracts[]? | select(type == "object") | (.contract_key? // empty) | select(. != "")];
  ($expected_keys | unique | sort) as $expected
  | . as $root
  | snapshot_keys as $actual
  | (($expected | length) > 0)
  and (($actual | length) == ($expected | length))
  and (($actual | unique | sort) == $expected)
  and ((.generated_at // "") | type == "string" and length > 0)
  and .environment == "local"
  and .status == "completed"
  and (.contracts | type == "array")
  and all(.contracts[]?; (type == "object") and ((.environment // "") == "local") and complete_contract_snapshot($root.chain_fingerprint // {}))
' "$ROOT/deployments/local/contracts.latest.json" >/dev/null; then
  echo "release checklist failed: deployments/local/contracts.latest.json must record every local contract exactly once from the full isolated deploy; rerun make test-local-isolated" >&2
  exit 1
fi
if ! jq -e '
  def has_tx($key):
    (.tx_hashes[$key] // "") as $tx
    | (($tx | type) == "string" and ($tx | test("^[0-9a-fA-F]{64}$")));
  def has_iroha_tx($key):
    (.tx_hashes[$key] // "") as $tx
    | (($tx | type) == "string" and (($tx | test("^[0-9a-fA-F]{64}$")) or ($tx | test("^hash:[0-9a-fA-F]{64}#[0-9a-fA-F]+$"))));
  def root_has_tx($root; $key):
    ($root.tx_hashes[$key] // "") as $tx
    | (($tx | type) == "string" and ($tx | test("^[0-9a-fA-F]{64}$")));
  def numeric_scalar($root; $key):
    ($root.view_results[$key] // null) | type == "number";
  def numeric_array($root; $key; $min_len):
    ($root.view_results[$key] // null) as $value
    | (($value | type) == "array")
      and (($value | length) >= $min_len)
      and all($value[]; type == "number");
  def options_factory_config($root):
    ($root.view_results.options_factory_config // null) as $value
    | (($value | type) == "array")
      and (($value | length) >= 9)
      and all($value[0:3][]; type == "string" and length > 0)
      and ($value[1] != $value[2])
      and all($value[3:][]; type == "number");
  def positive_number:
    type == "number" and . > 0;
  def collateral_pool_state:
    (.view_results.perps_collateral_pool // null) as $value
    | (($value | type) == "array")
      and (($value | length) >= 4)
      and (($value[0] | type) == "string" and length > 0)
      and all($value[1:][]; type == "number");
  def has_liquidated_pass:
    any([
      .view_results.perps_liquidation_state,
      .view_results.perps_liquidation_queue_state,
      .view_results.perps_liquidation_recovery_state,
      .view_results.perps_liquidation_requeue_state,
      .view_results.perps_liquidation_execute_state
    ][]; ((.[3] // null) | positive_number) and ((.[6] // null) | positive_number))
    or (
      ((.view_results.perps_liquidation_position_state[1] // null) == 4)
      and ((.view_results.perps_liquidation_position_liquidation_state[1] // null) | positive_number)
      and ((.view_results.perps_liquidation_position_liquidation_state[2] // null) | positive_number)
    );

  ((.generated_at // "") | type == "string" and length > 0)
  and .environment == "local"
  and .status == "completed"
  and .smoke_scope == "full"
  and (. as $root | all([
    "n3x_deposit_and_mint",
    "n3x_burn_and_redeem",
    "dlmm_router_route_swap",
    "dlmm_pool_collect_position_fees",
    "dlmm_pool_remove_position_liquidity",
    "launchpad_contribute",
    "launchpad_claim_allocation",
    "launchpad_finalize_activation",
    "launchpad_refund_allocation",
    "referral_bind_parent",
    "referral_bind",
    "referral_accrue",
    "referral_claim",
    "referral_parent_claim",
    "farms_fund_rewards",
    "farms_stake",
    "farms_claim",
    "farms_unstake",
    "perps_open_position",
    "perps_sync_funding",
    "perps_add_margin",
    "perps_remove_margin",
    "perps_close_position",
    "perps_open_liquidation_position",
    "options_buy_shout",
    "options_publish_shout_mark",
    "options_publish_shout_final_mark",
    "options_exercise_shout",
    "options_buy_outperformance",
    "options_settle_outperformance_series",
    "options_exercise_outperformance",
    "cover_register_policy",
    "cover_trigger_1",
    "cover_trigger_2",
    "cover_trigger_3",
    "cover_trigger_4",
    "cover_route_claim",
    "automation_enqueue",
    "automation_assign_executor",
    "automation_dispatch",
    "automation_pause",
    "automation_resume",
    "automation_retry",
    "automation_retry_dispatch",
    "automation_complete_run",
    "conditional_escrow_open"
  ][]; root_has_tx($root; .)))
  and (. as $root
    | numeric_scalar($root; "n3x_quote_mint")
    and numeric_scalar($root; "n3x_quote_redeem")
    and numeric_scalar($root; "dlmm_router_quote_bin")
    and numeric_array($root; "n3x_mirror_state"; 4)
    and numeric_array($root; "dlmm_router_mirror_state"; 2)
    and numeric_array($root; "dlmm_pool_mirror_state"; 4)
    and numeric_array($root; "launchpad_mirror_sale"; 4)
    and numeric_array($root; "launchpad_mirror_sale_accounting"; 4)
    and numeric_array($root; "launchpad_activation_state"; 2)
    and numeric_array($root; "referral_mirror_member"; 4)
    and numeric_array($root; "farms_mirror_position"; 4)
    and options_factory_config($root)
    and numeric_array($root; "options_factory_shout_series"; 10)
    and numeric_array($root; "options_factory_outperformance_series"; 10)
    and numeric_array($root; "options_factory_automation"; 7)
    and numeric_array($root; "options_factory_shout_position"; 9)
    and numeric_array($root; "options_factory_outperformance_position"; 9)
    and numeric_array($root; "cover_policy_state"; 4)
    and numeric_array($root; "automation_mirror_job"; 4)
    and numeric_array($root; "conditional_escrow_state"; 4)
    and numeric_array($root; "epoch_auction_state"; 4))
  and has_tx("perps_liquidation_queue_pass")
  and has_tx("perps_liquidation_recovery_pass")
  and has_tx("perps_liquidation_requeue_pass")
  and has_tx("perps_liquidation_execute_pass")
  and collateral_pool_state
  and has_tx("intent_open")
  and has_tx("intent_fill")
  and has_tx("vault_register")
  and has_tx("vault_deposit")
  and has_tx("vault_request_redeem")
  and has_tx("vault_claim_redeem")
  and has_tx("operator_register")
  and has_tx("operator_bond")
  and has_tx("operator_heartbeat")
  and has_tx("margin_register_market")
  and has_tx("margin_deposit_collateral")
  and has_tx("margin_lock_exposure")
  and has_tx("margin_liquidate_account")
  and has_tx("rwa_issue_lot")
  and has_tx("rwa_report_nav")
  and has_tx("rwa_request_redemption")
  and has_tx("rwa_settle_redemption")
  and has_tx("dlmm_configure_hook")
  and has_tx("dlmm_place_limit_order")
  and has_tx("dlmm_schedule_twamm")
  and has_tx("dlmm_record_hook_execution")
  and has_iroha_tx("conditional_escrow_execute_trigger")
  and ((.rejection_evidence.intent_replay // "") | length > 0)
  and ((.rejection_evidence.unregistered_operator // "") | length > 0)
  and ((.rejection_evidence.unhealthy_margin_withdraw // "") | length > 0)
  and ((.rejection_evidence.duplicate_rwa_issue // "") | length > 0)
  and ((.rejection_evidence.disabled_dlmm_hook // "") | length > 0)
  and has_liquidated_pass
  and ((.view_results.perps_liquidation_position_state[1] // null) == 4)
  and ((.view_results.perps_liquidation_position_liquidation_state[1] // null) | positive_number)
  and ((.view_results.perps_liquidation_position_liquidation_state[2] // null) | positive_number)
  and (.view_results.intent_state[0:5] == [1,2,10,9,30])
  and ((.view_results.intent_state[5] // null) | positive_number)
  and (.view_results.intent_state[6:9] == [1,1,10])
  and (.view_results.vault_state == [1,1,1,15,15])
  and (.view_results.operator_state == [1,100,125,8000,11,0,0])
  and (.view_results.margin_account_health == [0,0,10000,1])
  and (.view_results.rwa_market_state == [1,105,900,1])
  and (.view_results.dlmm_hook_quote == [1,20,18,20,19])
  and ((.trigger_evidence.missing_expected_trigger_ids // []) | type == "array" and length == 0)
  and (([
    "soraswap_epoch_auction_close",
    "soraswap_twamm_tick",
    "soraswap_range_governor_tick",
    "soraswap_options_factory_lifecycle_tick",
    "soraswap_cover_lifecycle_tick",
    "soraswap_launchpad_lifecycle_tick",
    "soraswap_vault_lifecycle_tick",
    "soraswap_perps_lifecycle_tick",
    "soraswap_escrow_settle"
  ] - ((.trigger_evidence.registered_trigger_ids // []) | map(select(type == "string")))) | length == 0)
  and (([
    "soraswap_range_governor_tick",
    "soraswap_twamm_tick",
    "soraswap_escrow_settle"
  ] - ((.trigger_evidence.active_trigger_ids // []) | map(select(type == "string")))) | length == 0)
  and ((.trigger_evidence.epoch_auction_native_close.ok // false) == true)
  and ((.trigger_evidence.epoch_auction_native_close.active_trigger_ids_after_close // []) | type == "array" and index("soraswap_epoch_auction_close") == null)
  and ((.decoded_state_ints // {}) | type == "object" and length > 0)
' "$ROOT/deployments/local/smoke.latest.json" >/dev/null; then
  echo "release checklist failed: deployments/local/smoke.latest.json must record completed full local smoke evidence; rerun make test-local-isolated" >&2
  exit 1
fi

if ! jq -n -e \
  --slurpfile chain "$ROOT/deployments/local/chain.latest.json" \
  --slurpfile deploy "$ROOT/deployments/local/deploy.latest.json" \
  --slurpfile contracts "$ROOT/deployments/local/contracts.latest.json" \
  --slurpfile smoke "$ROOT/deployments/local/smoke.latest.json" \
  '
    def current_contract_snapshot_path($snapshot; $contracts_generated):
      ($snapshot | type) == "string"
      and ("contracts." + $contracts_generated + ".json") as $contracts_file
      | ($snapshot == $contracts_file or ($snapshot | endswith("/" + $contracts_file)));
    def complete_chain_fingerprint($fingerprint):
      ($fingerprint | type) == "object"
      and (($fingerprint.torii_url // "") | type == "string" and length > 0)
      and (($fingerprint.chain // "") | type == "string" and length > 0)
      and (($fingerprint.block_1_hash // "") | type == "string" and length > 0);
    def same_chain_fingerprint($lhs; $rhs):
      complete_chain_fingerprint($lhs)
      and complete_chain_fingerprint($rhs)
      and (($lhs.torii_url // "") == ($rhs.torii_url // ""))
      and (($lhs.chain // "") == ($rhs.chain // ""))
      and (($lhs.block_1_hash // "") == ($rhs.block_1_hash // ""));
    def same_chain_snapshot($snapshot; $fingerprint):
      (($snapshot | type) == "object")
      and (($snapshot.generated_at // "") | type == "string" and length > 0)
      and (($snapshot.environment // "") == "local")
      and same_chain_fingerprint({
        torii_url: ($snapshot.torii_url // ""),
        chain: ($snapshot.chain // ""),
        block_1_hash: ($snapshot.block_1_hash // "")
      }; $fingerprint);

    ($deploy[0].generated_at // "") as $deploy_generated
    | ($contracts[0].generated_at // "") as $contracts_generated
    | ($smoke[0].generated_at // "") as $smoke_generated
    | (($deploy_generated | type) == "string" and ($deploy_generated | length) > 0)
      and (($contracts_generated | type) == "string" and ($contracts_generated | length) > 0)
      and (($smoke_generated | type) == "string" and ($smoke_generated | length) > 0)
      and ($contracts_generated >= $deploy_generated)
      and ($smoke_generated >= $deploy_generated)
      and ($smoke_generated >= $contracts_generated)
      and same_chain_fingerprint(($deploy[0].chain_fingerprint // {}); ($contracts[0].chain_fingerprint // {}))
      and same_chain_fingerprint(($deploy[0].chain_fingerprint // {}); ($smoke[0].chain_fingerprint // {}))
      and same_chain_snapshot($chain[0]; ($deploy[0].chain_fingerprint // {}))
      and same_chain_snapshot($chain[0]; ($contracts[0].chain_fingerprint // {}))
      and same_chain_snapshot($chain[0]; ($smoke[0].chain_fingerprint // {}))
      and current_contract_snapshot_path(($deploy[0].phases.deployment_records_snapshot.detail.snapshot // ""); $contracts_generated)
  ' >/dev/null; then
  echo "release checklist failed: deployments/local deploy/contracts/smoke evidence is stale or inconsistent; rerun make test-local-isolated" >&2
  exit 1
fi

require_local_evidence_docs_current

if ! jq -e '
  def nonempty_string:
    if type == "string" then length > 0 else false end;
  def number_gt($minimum):
    if type == "number" then . > $minimum else false end;
  def number_gte($minimum):
    if type == "number" then . >= $minimum else false end;
  def number_lte($maximum):
    if type == "number" then . <= $maximum else false end;
  def lhs_gte_rhs($lhs; $rhs):
    if (($lhs // null) | type == "number") and (($rhs // null) | type == "number") then
      $lhs >= $rhs
    else
      false
    end;

  ((.generated_at // null) | nonempty_string)
  and (.launchReady == true)
  and ((.intent.owner // null) | nonempty_string)
  and (.intent.status == "filled")
  and ((.intent.amountIn // null) | number_gt(0))
  and ((.intent.minOut // null) | number_gt(0))
  and ((.intent.amountOut // null) | number_gt(0))
  and lhs_gte_rhs(.intent.amountOut; .intent.minOut)
  and ((.intent.solverFeeBps // null) | (number_gt(0) and number_lte(10000)))
  and ((.intent.deadlineSlot // null) | number_gt(0))
  and ((.intent.solver // null) | nonempty_string)
  and (.vault.underlying == "n3x")
  and ((.vault.shares // null) | number_gt(0))
  and ((.vault.assets // null) | number_gt(0))
  and ((.vault.pendingRedeems // null) | number_gte(0))
  and (.operator.service == "solver")
  and ((.operator.bonded // null) | number_gt(0))
  and ((.operator.minBond // null) | number_gt(0))
  and lhs_gte_rhs(.operator.bonded; .operator.minBond)
  and ((.operator.healthBps // null) | number_gte(5000))
  and (.operator.jailed == false)
  and ((.operator.feesAccrued // null) | number_gte(0))
  and ((.hookOrder.amountIn // null) | number_gt(0))
  and ((.hookOrder.minOut // null) | number_gt(0))
  and ((.hookOrder.amountOut // null) | number_gt(0))
  and lhs_gte_rhs(.hookOrder.amountOut; .hookOrder.minOut)
  and ((.hookOrder.feePips // null) | number_gt(0))
  and ((.margin.collateral // null) | number_gt(0))
  and ((.margin.exposure // null) | number_gt(0))
  and ((.margin.healthBps // null) | number_gte(1000))
  and (.margin.liquidations == 0)
  and ((.rwa.navPerShare // null) | number_gt(0))
  and ((.rwa.totalShares // null) | number_gt(0))
  and ((.rwa.redemptionQueue // null) | number_gte(0))
  and (.rwa.frozen == false)
' "$ROOT/artifacts/telemetry/defi_2026_primitives_latest.json" >/dev/null; then
  echo "release checklist failed: defi_2026_primitives_latest.json does not prove all 2026 primitives with generated_at metadata" >&2
  echo "generate local primitive telemetry with: make simulate-full" >&2
  exit 1
fi

telemetry_generated_at="$(
  jq -r '.generated_at // empty' "$ROOT/artifacts/telemetry/defi_2026_primitives_latest.json"
)"
telemetry_doc_generated_at="${local_doc_telemetry_generated_at:-$telemetry_generated_at}"
if [[ "$closeout_mode" != "prepare" ]]; then
  for doc_path in "${required_local_telemetry_docs[@]}"; do
    require_doc_mentions "$doc_path" "primitive telemetry generated_at" "$telemetry_doc_generated_at"
  done
fi

case "$closeout_mode" in
  prepare)
    checkpoint_resume_token=""
    run_strict_closeout_diff_checks
    verify_local_acceptance_pin_unchanged "immediately before closeout checkpoint write"
    journal_token="$(release_phase_journal_state verify "$ROOT" "$public_env" "$release_closeout_phase_journal" "${release_closeout_expected_targets[@]}")" || exit 1
    [[ "$journal_token" == "$closeout_arg_token" ]] || {
      echo "release checklist failed: phase journal capability changed before checkpoint write" >&2
      exit 1
    }
    checkpoint_resume_token="$(release_closeout_checkpoint_state write)" || exit 1
    release_closeout_checkpoint_state verify-all 1 "$checkpoint_resume_token" >/dev/null
    strict_checkpoint_token="$(release_closeout_checkpoint_resume_token \
      "$ROOT" "$public_env" "$release_closeout_checkpoint")" || exit 1
    [[ "$strict_checkpoint_token" == "$checkpoint_resume_token" ]] || {
      echo "release checklist failed: closeout checkpoint identity changed before phase-journal removal" >&2
      exit 1
    }
    journal_token="$(release_phase_journal_state verify "$ROOT" "$public_env" "$release_closeout_phase_journal" "${release_closeout_expected_targets[@]}")" || exit 1
    [[ "$journal_token" == "$closeout_arg_token" ]] || {
      echo "release checklist failed: phase journal capability changed before journal removal" >&2
      exit 1
    }
    release_phase_journal_state remove "$ROOT" "$public_env" "$release_closeout_phase_journal" "${release_closeout_expected_targets[@]}"
    echo "release checklist: evidence and local acceptance validated; release remains pending status-doc closeout"
    echo "  checkpoint: $(soraswap_display_path "$release_closeout_checkpoint")"
    ;;
  resume)
    verify_local_acceptance_pin_unchanged "immediately before final closeout checkpoint verification"
    release_closeout_checkpoint_state verify-all >/dev/null
    echo "release checklist: strict closeout validation ok"
    ;;
  normal)
    echo "release checklist ok"
    ;;
esac
echo "  ported: $ported_count"
echo "  reference-only: $reference_only_count"
echo "  docs: ${#required_docs[@]} present"
echo "  evidence: ${#required_evidence[@]} present under deployments/$public_env"
if [[ "$local_acceptance_pin_enabled" == "1" ]]; then
  echo "  local acceptance provenance: pinned"
  echo "    iroha git sha: $local_acceptance_expected_git_sha"
  echo "    rollout bundle: $local_acceptance_bundle_name"
  echo "    rollout checksums sha256: $local_acceptance_checksums_sha256"
  echo "    rollout manifest sha256: $local_acceptance_manifest_sha256"
  echo "    rollout archive sha256: $local_acceptance_archive_sha256"
  echo "    rollout archive sidecar sha256: $local_acceptance_archive_sidecar_sha256"
  echo "    iroha3d sha256: $local_acceptance_iroha3d_sha256"
  echo "    iroha sha256: $local_acceptance_iroha_sha256"
  echo "    kagami sha256: $local_acceptance_kagami_sha256"
else
  echo "  local acceptance provenance: unpinned"
fi
echo "  local evidence generated_at: chain=$(jq -r '.generated_at' "$ROOT/deployments/local/chain.latest.json") deploy=$(jq -r '.generated_at' "$ROOT/deployments/local/deploy.latest.json") contracts=$(jq -r '.generated_at' "$ROOT/deployments/local/contracts.latest.json") smoke=$(jq -r '.generated_at' "$ROOT/deployments/local/smoke.latest.json") telemetry=$telemetry_generated_at"
if [[ "$closeout_mode" == "resume" ]]; then
  verify_local_acceptance_pin_unchanged "immediately before closeout checkpoint deletion"
  release_closeout_checkpoint_state verify-all >/dev/null
  verify_local_acceptance_pin_unchanged "at closeout checkpoint deletion"
  remove_release_closeout_checkpoint
  echo "release checklist ok; status-doc closeout completed"
fi
