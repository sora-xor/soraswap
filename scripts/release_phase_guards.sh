#!/bin/zsh

release_local_acceptance_pin_state_json() {
  local requested_root="$1"
  local requested_bundle="$2"
  local expected_git_sha="$3"
  local python_bin="${commands[python3]:-python3}"

  "$python_bin" - "$requested_root" "$requested_bundle" "$expected_git_sha" <<'PY'
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import tarfile
from pathlib import Path, PurePosixPath

root_raw, bundle_raw, expected_git_sha = sys.argv[1:]


def fail(message):
    raise SystemExit(f"local acceptance pin failed: {message}")


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def read_regular(path, label, executable=False):
    try:
        before = path.lstat()
    except OSError:
        fail(f"{label} is missing")
    if stat.S_ISLNK(before.st_mode) or not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        fail(f"{label} must be a regular non-symlink file with exactly one hard link")
    if executable and not os.access(path, os.X_OK):
        fail(f"{label} must be executable")
    try:
        data = path.read_bytes()
        after = path.lstat()
    except OSError:
        fail(f"{label} changed while it was being read")
    identity = lambda metadata: (
        metadata.st_dev, metadata.st_ino, metadata.st_mode,
        metadata.st_nlink, metadata.st_size, metadata.st_mtime_ns,
    )
    if identity(before) != identity(after):
        fail(f"{label} changed while it was being read")
    return data, before


def require_real_directory(path, label):
    try:
        metadata = path.lstat()
    except OSError:
        fail(f"{label} is missing")
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        fail(f"{label} must be a real directory")


def git_output(root, *arguments):
    try:
        return subprocess.check_output(
            ["git", "-C", str(root), *arguments], stderr=subprocess.DEVNULL
        )
    except (OSError, subprocess.CalledProcessError):
        fail("Iroha candidate is not a readable Git worktree")


if re.fullmatch(r"[0-9a-f]{40}", expected_git_sha) is None:
    fail("expected Iroha Git SHA must be 40 lowercase hexadecimal characters")

root_input = Path(os.path.abspath(root_raw))
bundle_input = Path(os.path.abspath(bundle_raw))
require_real_directory(root_input, "Iroha candidate root")
require_real_directory(bundle_input, "rollout bundle directory")
root = root_input.resolve(strict=True)
bundle = bundle_input.resolve(strict=True)
if root == bundle:
    fail("Iroha candidate and rollout bundle must be distinct directories")

try:
    git_root = Path(git_output(root, "rev-parse", "--show-toplevel").decode("utf-8").strip()).resolve(strict=True)
except (OSError, UnicodeError):
    fail("Iroha candidate Git root is invalid")
if git_root != root:
    fail("Iroha candidate path must name the Git worktree root")
git_head = git_output(root, "rev-parse", "HEAD").decode("ascii").strip()
if git_head != expected_git_sha:
    fail("Iroha candidate HEAD does not match the expected Git SHA")
status = git_output(
    root, "status", "--porcelain=v1", "--untracked-files=normal", "--ignore-submodules=none"
)
if status:
    fail("Iroha candidate worktree must be clean")
try:
    subprocess.run(
        ["git", "-C", str(root), "verify-commit", expected_git_sha],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
except (OSError, subprocess.CalledProcessError):
    fail("Iroha candidate commit signature is not verifiable")

manifest_path = bundle / "rollout.manifest.json"
checksums_path = bundle / "sha256sums.txt"
irohad_path = bundle / "bin" / "irohad"
iroha_path = bundle / "bin" / "iroha"
kagami_path = root / "target" / "release" / "kagami"
archive_path = bundle.parent / f"{bundle.name}.tar.gz"
archive_sidecar_path = bundle.parent / f"{bundle.name}.tar.gz.sha256"

manifest_bytes, _ = read_regular(manifest_path, "rollout manifest")
checksums_bytes, _ = read_regular(checksums_path, "bundle checksum manifest")
irohad_bytes, _ = read_regular(irohad_path, "bundle bin/irohad", executable=True)
iroha_bytes, _ = read_regular(iroha_path, "bundle bin/iroha", executable=True)
kagami_bytes, kagami_metadata = read_regular(kagami_path, "candidate target/release/kagami", executable=True)
archive_bytes, archive_metadata = read_regular(archive_path, "rollout archive")
sidecar_bytes, _ = read_regular(archive_sidecar_path, "rollout archive checksum sidecar")

try:
    manifest = json.loads(manifest_bytes.decode("utf-8"))
except (UnicodeError, json.JSONDecodeError):
    fail("rollout manifest is not valid JSON")
if not isinstance(manifest, dict):
    fail("rollout manifest must be a JSON object")
required_checks = {
    "soraswap_smart_contract_deploy_router_regression",
    "soraswap_three_hop_nested_transfer_canary",
}
completed_checks = {
    item.get("name")
    for item in manifest.get("prebundle_checks", [])
    if isinstance(item, dict) and item.get("skipped") is False
}
features = manifest.get("irohad_features")
if not (
    manifest.get("git_head") == expected_git_sha
    and manifest.get("git_signature_verified") is True
    and manifest.get("git_tree_clean") is True
    and manifest.get("git_status_lines") == []
    and manifest.get("cargo_profile") == "release"
    and manifest.get("bundle_name") == bundle.name
    and isinstance(features, list)
    and len(features) == 2
    and len(set(features)) == 2
    and sorted(features) == ["embedded-soracloud-runtime", "sccp-test-fixtures"]
    and isinstance(manifest.get("binaries"), list)
    and "bin/irohad" in manifest["binaries"]
    and "bin/iroha" in manifest["binaries"]
    and required_checks <= completed_checks
):
    fail("rollout manifest does not prove the signed clean release candidate, exact features, and required regressions")

sha_bytes = expected_git_sha.encode("ascii")
if sha_bytes not in irohad_bytes:
    fail("bundle bin/irohad does not embed the expected Iroha Git SHA")
if sha_bytes not in iroha_bytes:
    fail("bundle bin/iroha does not embed the expected Iroha Git SHA")

if not checksums_bytes or not checksums_bytes.endswith(b"\n"):
    fail("bundle checksum manifest must end in exactly formatted newline-delimited entries")
try:
    checksum_lines = checksums_bytes[:-1].decode("utf-8").split("\n")
except UnicodeError:
    fail("bundle checksum manifest is not UTF-8")
checksum_pattern = re.compile(r"([0-9a-f]{64})  ([^\r\n]+)")
listed = []
listed_hashes = {}
for line in checksum_lines:
    match = checksum_pattern.fullmatch(line)
    if match is None:
        fail("bundle checksum manifest has a non-canonical entry")
    expected_digest, raw_relative = match.groups()
    relative = PurePosixPath(raw_relative)
    if (
        relative.is_absolute() or not relative.parts
        or any(part in {"", ".", ".."} for part in relative.parts)
        or relative.as_posix() != raw_relative
        or raw_relative in listed_hashes
    ):
        fail("bundle checksum manifest has an unsafe or duplicate path")
    candidate = bundle.joinpath(*relative.parts)
    candidate_bytes, _ = read_regular(candidate, f"checksummed bundle file {raw_relative}")
    if sha256_bytes(candidate_bytes) != expected_digest:
        fail(f"bundle checksum mismatch for {raw_relative}")
    listed.append(raw_relative)
    listed_hashes[raw_relative] = expected_digest
if listed != sorted(listed):
    fail("bundle checksum manifest paths must be sorted")

actual_files = {}
actual_directories = {bundle.name: bundle}
for candidate in bundle.rglob("*"):
    relative = candidate.relative_to(bundle).as_posix()
    try:
        metadata = candidate.lstat()
    except OSError:
        fail(f"bundle entry is unreadable: {relative}")
    if stat.S_ISLNK(metadata.st_mode):
        fail(f"bundle entry must not be a symlink: {relative}")
    if stat.S_ISDIR(metadata.st_mode):
        actual_directories[f"{bundle.name}/{relative}"] = candidate
    elif stat.S_ISREG(metadata.st_mode):
        if metadata.st_nlink != 1:
            fail(f"bundle file must have exactly one hard link: {relative}")
        if relative != "sha256sums.txt":
            actual_files[relative] = candidate
    else:
        fail(f"bundle entry has an unsupported type: {relative}")
if set(listed) != set(actual_files):
    fail("bundle checksum manifest does not exactly cover every regular bundle file")
if not {"bin/irohad", "bin/iroha", "rollout.manifest.json"} <= set(actual_files):
    fail("bundle checksum manifest omits a required release file")

sidecar_match = re.fullmatch(
    rb"([0-9a-f]{64})  ([^\r\n]+)\n", sidecar_bytes
)
archive_sha256 = sha256_bytes(archive_bytes)
if (
    sidecar_match is None
    or sidecar_match.group(2).decode("utf-8", errors="strict") != archive_path.name
    or sidecar_match.group(1).decode("ascii") != archive_sha256
):
    fail("rollout archive checksum sidecar is not canonical or does not match the archive")

expected_archive_files = {
    f"{bundle.name}/{relative}": path for relative, path in actual_files.items()
}
expected_archive_files[f"{bundle.name}/sha256sums.txt"] = checksums_path
archive_members = {}
try:
    with tarfile.open(archive_path, mode="r:gz") as archive:
        for member in archive.getmembers():
            raw_name = member.name.rstrip("/")
            normalized = PurePosixPath(raw_name)
            if (
                not raw_name or normalized.is_absolute()
                or any(part in {"", ".", ".."} for part in normalized.parts)
                or normalized.as_posix() != raw_name
                or raw_name in archive_members
            ):
                fail("rollout archive contains an unsafe or duplicate member")
            if not (member.isdir() or member.isreg()):
                fail("rollout archive contains a link or special-file member")
            archive_members[raw_name] = member
        expected_names = set(actual_directories) | set(expected_archive_files)
        if set(archive_members) != expected_names:
            fail("rollout archive member set does not exactly match the rollout bundle")
        for name, path in expected_archive_files.items():
            member = archive_members[name]
            if not member.isreg():
                fail(f"rollout archive member has the wrong type: {name}")
            source_bytes, source_metadata = read_regular(path, f"bundle file {name}")
            extracted = archive.extractfile(member)
            if extracted is None or extracted.read() != source_bytes:
                fail(f"rollout archive member content differs from the bundle: {name}")
            if stat.S_IMODE(source_metadata.st_mode) != stat.S_IMODE(member.mode):
                fail(f"rollout archive member mode differs from the bundle: {name}")
        for name in actual_directories:
            if not archive_members[name].isdir():
                fail(f"rollout archive member has the wrong type: {name}")
except (OSError, tarfile.TarError, UnicodeError):
    fail("rollout archive is not a readable canonical gzip tar archive")

freshness_inputs = [
    root / "Cargo.toml",
    root / "Cargo.lock",
    root / "crates" / "iroha_kagami",
    root / "crates" / "iroha_swarm",
    root / "crates" / "iroha_test_samples",
]
for source in freshness_inputs:
    if not source.exists():
        continue
    candidates = source.rglob("*") if source.is_dir() else (source,)
    for candidate in candidates:
        try:
            metadata = candidate.stat()
        except OSError:
            fail("candidate source freshness is unreadable")
        if stat.S_ISREG(metadata.st_mode) and metadata.st_mtime_ns > kagami_metadata.st_mtime_ns:
            fail("candidate target/release/kagami is older than candidate sources")

print(json.dumps({
    "iroha_root": str(root),
    "bundle_dir": str(bundle),
    "iroha_git_sha": expected_git_sha,
    "bundle_name": bundle.name,
    "checksums_sha256": sha256_bytes(checksums_bytes),
    "manifest_sha256": sha256_bytes(manifest_bytes),
    "irohad_sha256": sha256_bytes(irohad_bytes),
    "iroha_sha256": sha256_bytes(iroha_bytes),
    "kagami_sha256": sha256_bytes(kagami_bytes),
    "archive_sha256": archive_sha256,
    "archive_sidecar_sha256": sha256_bytes(sidecar_bytes),
}, sort_keys=True, separators=(",", ":")))
PY
}

release_soraswap_rc_state_json() {
  local root="$1"
  local expected_git_sha="$2"
  local python_bin="${commands[python3]:-python3}"

  "$python_bin" - "$root" "$expected_git_sha" <<'PY'
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path

root_raw, expected_git_sha = sys.argv[1:]


def fail(message):
    raise SystemExit(f"SoraSwap RC validation failed: {message}")


if re.fullmatch(r"[0-9a-f]{40}", expected_git_sha) is None:
    fail("SORASWAP_RELEASE_EXPECTED_GIT_SHA must be 40 lowercase hexadecimal characters")
root_input = Path(os.path.abspath(root_raw))
try:
    metadata = root_input.lstat()
except OSError:
    fail("release worktree root is missing")
if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
    fail("release worktree root must be a real directory")
root = root_input.resolve(strict=True)


def git_output(*arguments):
    try:
        return subprocess.check_output(
            ["git", "-C", str(root), *arguments], stderr=subprocess.DEVNULL
        ).decode("ascii").strip()
    except (OSError, UnicodeError, subprocess.CalledProcessError):
        fail("release worktree Git identity is unreadable")


try:
    git_root = Path(git_output("rev-parse", "--show-toplevel")).resolve(strict=True)
except OSError:
    fail("release worktree Git root is invalid")
if git_root != root:
    fail("release root must name the SoraSwap Git worktree root")
head = git_output("rev-parse", "HEAD")
if head != expected_git_sha:
    fail("SoraSwap HEAD does not match SORASWAP_RELEASE_EXPECTED_GIT_SHA")
try:
    subprocess.run(
        ["git", "-C", str(root), "verify-commit", expected_git_sha],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
except (OSError, subprocess.CalledProcessError):
    fail("SoraSwap RC commit signature is not verifiable")
tree = git_output("rev-parse", f"{expected_git_sha}^{{tree}}")
if re.fullmatch(r"[0-9a-f]{40}", tree) is None:
    fail("SoraSwap RC tree identity is invalid")
print(json.dumps({"git_sha": head, "tree_sha": tree}, sort_keys=True, separators=(",", ":")))
PY
}

release_closeout_expected_phase_targets() {
  local environment="$1"

  case "$environment" in
    testnet)
      printf '%s\n' \
        taira-preflight \
        testnet-nested-call-probe \
        taira-preflight \
        record-testnet-rwa-compliance \
        deploy-testnet \
        smoke-testnet-readonly \
        smoke-testnet \
        test-contract-console-testnet \
        smoke-testnet-trader-readonly \
        smoke-testnet-trader \
        publish-trader-api
      ;;
    production)
      printf '%s\n' \
        production-preflight \
        production-nested-call-probe \
        production-preflight \
        record-production-rwa-compliance \
        deploy-production \
        smoke-production-readonly \
        smoke-production \
        test-contract-console-production \
        smoke-production-trader-readonly \
        smoke-production-trader \
        publish-production-trader-api
      ;;
    *)
      echo "release phase journal failed: unsupported environment $environment" >&2
      return 1
      ;;
  esac
}

release_phase_artifact_snapshot_json() {
  local root="$1"
  local python_bin="${commands[python3]:-python3}"
  shift

  "$python_bin" - "$root" "$@" <<'PY'
import hashlib
import json
import os
import stat
import sys
import time
from pathlib import Path

root_raw, *path_values = sys.argv[1:]
root_input = Path(os.path.abspath(root_raw))
root = root_input.resolve(strict=True)


def fail(message):
    raise SystemExit(f"release phase freshness failed: {message}")


artifacts = []
seen = set()
for raw_path in path_values:
    path_input = Path(os.path.abspath(raw_path))
    try:
        relative_path = path_input.relative_to(root_input)
    except ValueError:
        fail("artifact path escapes the release worktree")
    relative = relative_path.as_posix()
    if relative in seen:
        fail(f"duplicate artifact path: {relative}")
    seen.add(relative)
    path = root / relative_path
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        artifacts.append({"path": relative, "exists": False})
        continue
    except OSError:
        fail(f"artifact is unreadable before the phase: {relative}")
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
        fail(f"artifact must be a regular non-symlink file with exactly one hard link: {relative}")
    try:
        raw = path.read_bytes()
        after = path.lstat()
    except OSError:
        fail(f"artifact changed while its pre-phase identity was captured: {relative}")
    identity = lambda item: (item.st_dev, item.st_ino, item.st_mode, item.st_nlink, item.st_size, item.st_mtime_ns)
    if identity(metadata) != identity(after):
        fail(f"artifact changed while its pre-phase identity was captured: {relative}")
    generated_at = None
    try:
        value = json.loads(raw.decode("utf-8"))
        if isinstance(value, dict) and isinstance(value.get("generated_at"), str):
            generated_at = value["generated_at"]
    except (UnicodeError, json.JSONDecodeError):
        pass
    artifacts.append({
        "path": relative,
        "exists": True,
        "device": metadata.st_dev,
        "inode": metadata.st_ino,
        "sha256": hashlib.sha256(raw).hexdigest(),
        "generated_at": generated_at,
    })

print(json.dumps({
    "captured_at_epoch_second": int(time.time()),
    "artifacts": artifacts,
}, sort_keys=True, separators=(",", ":")))
PY
}

release_phase_require_regenerated_artifacts() {
  local root="$1"
  local snapshot_json="$2"
  local python_bin="${commands[python3]:-python3}"
  shift 2

  "$python_bin" - "$root" "$snapshot_json" "$@" <<'PY'
import datetime as dt
import hashlib
import json
import os
import stat
import sys
import time
from pathlib import Path

root_raw, snapshot_raw, *path_values = sys.argv[1:]
root_input = Path(os.path.abspath(root_raw))
root = root_input.resolve(strict=True)


def fail(message):
    raise SystemExit(f"release phase freshness failed: {message}")


def parse_generated_at(value):
    if not isinstance(value, str) or not value:
        return None
    candidates = ("%Y%m%dT%H%M%SZ", "%Y-%m-%dT%H:%M:%SZ")
    for pattern in candidates:
        try:
            return int(dt.datetime.strptime(value, pattern).replace(tzinfo=dt.timezone.utc).timestamp())
        except ValueError:
            pass
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return int(parsed.timestamp())


try:
    snapshot = json.loads(snapshot_raw)
except json.JSONDecodeError:
    fail("pre-phase artifact snapshot is not valid JSON")
if not isinstance(snapshot, dict) or not isinstance(snapshot.get("artifacts"), list) \
        or not isinstance(snapshot.get("captured_at_epoch_second"), int):
    fail("pre-phase artifact snapshot is malformed")
expected_paths = []
for raw_path in path_values:
    path_input = Path(os.path.abspath(raw_path))
    try:
        expected_paths.append(path_input.relative_to(root_input).as_posix())
    except ValueError:
        fail("artifact path escapes the release worktree")
if [item.get("path") for item in snapshot["artifacts"] if isinstance(item, dict)] != expected_paths:
    fail("post-phase artifact paths differ from the pre-phase snapshot")

phase_started = snapshot["captured_at_epoch_second"]
now = int(time.time())
for before, relative in zip(snapshot["artifacts"], expected_paths):
    path = root / relative
    try:
        metadata = path.lstat()
    except OSError:
        fail(f"phase did not produce its required artifact: {relative}")
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
        fail(f"post-phase artifact must be a regular non-symlink file with exactly one hard link: {relative}")
    try:
        raw = path.read_bytes()
        after = path.lstat()
        value = json.loads(raw.decode("utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail(f"post-phase artifact is not stable valid JSON: {relative}")
    identity = lambda item: (item.st_dev, item.st_ino, item.st_mode, item.st_nlink, item.st_size, item.st_mtime_ns)
    if identity(metadata) != identity(after):
        fail(f"post-phase artifact changed while it was read: {relative}")
    generated_at = value.get("generated_at") if isinstance(value, dict) else None
    generated_epoch = parse_generated_at(generated_at)
    if generated_epoch is None or generated_epoch < phase_started or generated_epoch > now + 300:
        fail(f"post-phase artifact generated_at is not fresh for this phase: {relative}")
    digest = hashlib.sha256(raw).hexdigest()
    if before.get("exists") is True:
        if (metadata.st_dev, metadata.st_ino) == (before.get("device"), before.get("inode")):
            fail(f"phase reused the prior artifact file identity: {relative}")
        if digest == before.get("sha256"):
            fail(f"phase reused the prior artifact bytes: {relative}")
        if generated_at == before.get("generated_at"):
            fail(f"phase reused the prior artifact generated_at: {relative}")
PY
}

release_phase_journal_state() {
  local action="$1"
  local root="$2"
  local environment="$3"
  local journal="$4"
  local python_bin="${commands[python3]:-python3}"
  local rc_state source_state cutover_approval_state
  shift 4

  rc_state="$(release_soraswap_rc_state_json "$root" "${SORASWAP_RELEASE_EXPECTED_GIT_SHA:-}")" || return 1
  source_state="$(release_closeout_source_state_json "$root" "$environment")" || return 1
  cutover_approval_state="${SORASWAP_INTERNAL_PRODUCTION_CUTOVER_APPROVAL_STATE_JSON:-}"

  "$python_bin" - "$action" "$root" "$environment" "$journal" "$rc_state" "$source_state" "$cutover_approval_state" "$@" <<'PY'
import datetime as dt
import hashlib
import json
import os
import secrets
import stat
import sys
import tempfile
from pathlib import Path, PurePosixPath

action, root_raw, environment, journal_raw, rc_state_raw, source_state_raw, cutover_approval_raw, *arguments = sys.argv[1:]
schema = "soraswap-release-phase-journal/v1"


def fail(message):
    raise SystemExit(f"release phase journal failed: {message}")


def canonical_hash(value):
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def file_hash(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fsync_directory(path):
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def require_safe_parent(path, create=False):
    parent = path.parent
    if create:
        parent.mkdir(parents=True, exist_ok=True)
    try:
        metadata = parent.lstat()
    except OSError:
        fail("parent directory is missing")
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        fail("parent path must be a real directory")
    if parent.resolve(strict=True) != expected.parent:
        fail("parent path escapes the release worktree")


def require_regular_0600(path):
    try:
        metadata = path.lstat()
    except OSError:
        fail(f"is missing: {path.relative_to(root).as_posix()}")
    if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        fail("must be a regular non-symlink file")
    if stat.S_IMODE(metadata.st_mode) != 0o600:
        fail("must have mode 0600")
    if metadata.st_nlink != 1:
        fail("must have exactly one hard link")
    return metadata


def require_receipt_root():
    try:
        metadata = receipt_root.lstat()
    except OSError:
        fail("receipt directory is missing")
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        fail("receipt directory must be a real directory")
    if stat.S_IMODE(metadata.st_mode) != 0o700:
        fail("receipt directory must have mode 0700")
    if receipt_root.resolve(strict=True) != expected.parent / receipt_root.name:
        fail("receipt directory escapes the release worktree")


def load_journal():
    require_safe_parent(journal)
    require_receipt_root()
    metadata = require_regular_0600(journal)
    try:
        raw = journal.read_bytes()
        after = journal.lstat()
        value = json.loads(raw.decode("utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("is not valid JSON")
    if not isinstance(value, dict):
        fail("must be a JSON object")
    if (metadata.st_dev, metadata.st_ino, metadata.st_mode, metadata.st_nlink, metadata.st_size) != (
            after.st_dev, after.st_ino, after.st_mode, after.st_nlink, after.st_size):
        fail("changed while it was being read")
    integrity = value.pop("journal_sha256", None)
    if not isinstance(integrity, str) or integrity != canonical_hash(value):
        fail("integrity hash does not match its contents")
    value["journal_sha256"] = integrity
    if value.get("schema") != schema or value.get("environment") != environment:
        fail("schema or environment does not match the release")
    run_id = value.get("run_id")
    if not isinstance(run_id, str) or len(run_id) != 64 or any(ch not in "0123456789abcdef" for ch in run_id):
        fail("run id is invalid")
    if value.get("receipt_dir") != receipt_root.relative_to(root).as_posix():
        fail("receipt directory does not match the selected release environment")
    return value, metadata, hashlib.sha256(raw).hexdigest()


def atomic_replace(path, value, prior_metadata, prior_file_hash):
    payload = dict(value)
    payload.pop("journal_sha256", None)
    payload["journal_sha256"] = canonical_hash(payload)
    descriptor, temporary_raw = tempfile.mkstemp(prefix=f".{environment}.", suffix=".journal.tmp", dir=path.parent)
    temporary = Path(temporary_raw)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            json.dump(payload, output, indent=2, sort_keys=True)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        current = require_regular_0600(path)
        if (current.st_dev, current.st_ino) != (prior_metadata.st_dev, prior_metadata.st_ino):
            fail("changed concurrently")
        if file_hash(path) != prior_file_hash:
            fail("contents changed concurrently")
        os.replace(temporary, path)
        fsync_directory(path.parent)
    finally:
        if temporary.exists():
            temporary.unlink()


if environment not in {"testnet", "production"}:
    fail(f"unsupported environment {environment}")
if action not in {"create", "record", "verify", "token", "remove"}:
    fail(f"unsupported action {action}")
try:
    rc_state = json.loads(rc_state_raw)
    source_state = json.loads(source_state_raw)
except json.JSONDecodeError:
    fail("release source identity is not valid JSON")
if not isinstance(rc_state, dict) or not isinstance(source_state, dict):
    fail("release source identity must be a JSON object")
if environment == "production":
    try:
        cutover_approval = json.loads(cutover_approval_raw)
    except json.JSONDecodeError:
        fail("production phase journal requires verified cutover approval state")
    if not isinstance(cutover_approval, dict) \
            or cutover_approval.get("schema") != "soraswap-production-cutover-approval-state/v1":
        fail("production phase journal cutover approval state is invalid")
elif cutover_approval_raw:
    fail("Taira phase journal does not accept production cutover approval state")
else:
    cutover_approval = None

phase_specs = {
    "testnet": [
        ("taira-preflight", ["deployments/testnet/preflight.latest.json"]),
        ("testnet-nested-call-probe", [
            "deployments/testnet/chain.latest.json",
            "deployments/testnet/nested_call_probe.latest.json",
        ]),
        ("taira-preflight", ["deployments/testnet/preflight.latest.json"]),
        ("record-testnet-rwa-compliance", ["deployments/testnet/rwa_compliance.latest.json"]),
        ("deploy-testnet", [
            "deployments/testnet/deploy.latest.json",
            "deployments/testnet/contracts.latest.json",
        ]),
        ("smoke-testnet-readonly", ["deployments/testnet/smoke.latest.json"]),
        ("smoke-testnet", ["deployments/testnet/smoke.latest.json"]),
        ("test-contract-console-testnet", ["deployments/testnet/contract_console_smoke.latest.json"]),
        ("smoke-testnet-trader-readonly", ["deployments/testnet/trader_readonly.latest.json"]),
        ("smoke-testnet-trader", ["deployments/testnet/trader.latest.json"]),
        ("publish-trader-api", ["deployments/testnet/trader_api_bundle.latest.json"]),
    ],
    "production": [
        ("production-preflight", ["deployments/production/preflight.latest.json"]),
        ("production-nested-call-probe", [
            "deployments/production/chain.latest.json",
            "deployments/production/nested_call_probe.latest.json",
        ]),
        ("production-preflight", ["deployments/production/preflight.latest.json"]),
        ("record-production-rwa-compliance", ["deployments/production/rwa_compliance.latest.json"]),
        ("deploy-production", [
            "deployments/production/deploy.latest.json",
            "deployments/production/contracts.latest.json",
        ]),
        ("smoke-production-readonly", ["deployments/production/smoke.latest.json"]),
        ("smoke-production", ["deployments/production/smoke.latest.json"]),
        ("test-contract-console-production", ["deployments/production/contract_console_smoke.latest.json"]),
        ("smoke-production-trader-readonly", ["deployments/production/trader_readonly.latest.json"]),
        ("smoke-production-trader", ["deployments/production/trader.latest.json"]),
        ("publish-production-trader-api", ["deployments/production/trader_api_bundle.latest.json"]),
    ],
}[environment]
canonical_targets = [target for target, _ in phase_specs]

root_input = Path(os.path.abspath(root_raw))
expected_input = root_input / "tmp" / "release-closeout" / f"{environment}.phase-journal.json"
if Path(os.path.abspath(journal_raw)) != expected_input:
    fail("path does not match the selected release environment")
try:
    root = root_input.resolve(strict=True)
except OSError:
    fail("release root is missing")
expected = root / "tmp" / "release-closeout" / f"{environment}.phase-journal.json"
journal = expected
receipt_root = root / "tmp" / "release-closeout" / f"{environment}.phase-receipts"

if action == "create":
    expected_targets = arguments
    if expected_targets != canonical_targets:
        fail("create requires the exact eleven ordered phase targets")
    require_safe_parent(journal, create=True)
    if journal.exists() or journal.is_symlink() or receipt_root.exists() or receipt_root.is_symlink():
        fail(f"already exists: {journal.relative_to(root).as_posix()}")
    try:
        receipt_root.mkdir(mode=0o700)
    except FileExistsError:
        fail(f"receipt directory already exists: {receipt_root.relative_to(root).as_posix()}")
    if receipt_root.is_symlink() or not receipt_root.is_dir() or stat.S_IMODE(receipt_root.stat().st_mode) != 0o700:
        fail("receipt directory must be a real mode-0700 directory")
    value = {
        "schema": schema,
        "environment": environment,
        "run_id": secrets.token_hex(32),
        "started_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "receipt_dir": receipt_root.relative_to(root).as_posix(),
        "expected_targets": expected_targets,
        "soraswap_rc": rc_state,
        "source": source_state,
        "production_cutover_approval": cutover_approval,
        "phases": [],
    }
    value["journal_sha256"] = canonical_hash(value)
    descriptor, temporary_raw = tempfile.mkstemp(prefix=f".{environment}.", suffix=".journal.create", dir=journal.parent)
    temporary = Path(temporary_raw)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            json.dump(value, output, indent=2, sort_keys=True)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        try:
            os.link(temporary, journal)
        except FileExistsError:
            fail(f"already exists: {journal.relative_to(root).as_posix()}")
        temporary.unlink()
        fsync_directory(journal.parent)
    finally:
        if temporary.exists():
            temporary.unlink()
    require_regular_0600(journal)
    print(value["run_id"])
    raise SystemExit(0)

value, metadata, loaded_file_hash = load_journal()
if value.get("soraswap_rc") != rc_state or value.get("source") != source_state:
    fail("signed SoraSwap RC or release source identity changed during the release")
if value.get("production_cutover_approval") != cutover_approval:
    fail("production cutover approval identity changed during the release")

if action == "token":
    print(value["run_id"])
    raise SystemExit(0)

if action == "record":
    if len(arguments) < 3:
        fail("record requires an index, target, and at least one evidence path")
    try:
        phase_index = int(arguments[0])
    except ValueError:
        fail("phase index is not an integer")
    target = arguments[1]
    evidence_raw = arguments[2:]
    expected_targets = value.get("expected_targets")
    phases = value.get("phases")
    if not isinstance(expected_targets, list) or not isinstance(phases, list):
        fail("target or phase lists are malformed")
    if phase_index != len(phases) + 1 or phase_index < 1 or phase_index > len(expected_targets):
        fail("phase index is not the next ordered phase")
    if expected_targets[phase_index - 1] != target:
        fail("phase target is out of order")
    expected_sources = phase_specs[phase_index - 1][1]
    normalized_sources = []
    for raw_path in evidence_raw:
        path_input = Path(os.path.abspath(raw_path))
        try:
            normalized_sources.append(path_input.relative_to(root_input).as_posix())
        except ValueError:
            fail("evidence path escapes the release worktree")
    if normalized_sources != expected_sources:
        fail("phase evidence paths do not match the exact runner artifact mapping")
    receipts = []
    for receipt_index, raw_path in enumerate(evidence_raw, start=1):
        path_input = Path(os.path.abspath(raw_path))
        relative_path = path_input.relative_to(root_input)
        relative = relative_path.as_posix()
        path = root / relative_path
        try:
            artifact_metadata = path.lstat()
        except OSError:
            fail(f"evidence is missing: {relative}")
        if not stat.S_ISREG(artifact_metadata.st_mode) or stat.S_ISLNK(artifact_metadata.st_mode) or artifact_metadata.st_nlink != 1:
            fail(f"evidence must be a regular non-symlink file: {relative}")
        try:
            artifact_bytes = path.read_bytes()
            artifact_after = path.lstat()
            artifact = json.loads(artifact_bytes.decode("utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError):
            fail(f"evidence is not valid JSON: {relative}")
        if (artifact_metadata.st_dev, artifact_metadata.st_ino, artifact_metadata.st_mode,
                artifact_metadata.st_nlink, artifact_metadata.st_size) != (
                artifact_after.st_dev, artifact_after.st_ino, artifact_after.st_mode,
                artifact_after.st_nlink, artifact_after.st_size):
            fail(f"evidence changed while it was being read: {relative}")
        generated_at = artifact.get("generated_at") if isinstance(artifact, dict) else None
        if not isinstance(generated_at, str) or not generated_at:
            fail(f"evidence lacks generated_at: {relative}")
        receipt_path = receipt_root / f"phase{phase_index:02d}-artifact{receipt_index:02d}.json"
        descriptor, temporary_raw = tempfile.mkstemp(prefix=f".phase{phase_index:02d}.", suffix=".receipt.tmp", dir=receipt_root)
        temporary = Path(temporary_raw)
        try:
            os.fchmod(descriptor, 0o600)
            with os.fdopen(descriptor, "wb") as output:
                output.write(artifact_bytes)
                output.flush()
                os.fsync(output.fileno())
            try:
                os.link(temporary, receipt_path)
            except FileExistsError:
                fail(f"receipt already exists: {receipt_path.relative_to(root).as_posix()}")
            temporary.unlink()
            fsync_directory(receipt_root)
        finally:
            if temporary.exists():
                temporary.unlink()
        receipt_metadata = require_regular_0600(receipt_path)
        if receipt_metadata.st_nlink != 1:
            fail("evidence receipt must have exactly one hard link")
        receipts.append({
            "path": receipt_path.relative_to(root).as_posix(),
            "source_path": relative,
            "sha256": hashlib.sha256(artifact_bytes).hexdigest(),
            "generated_at": generated_at,
        })
    phases.append({
        "index": phase_index,
        "target": target,
        "completed_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "evidence": receipts,
    })
    value["phases"] = phases
    atomic_replace(journal, value, metadata, loaded_file_hash)
    raise SystemExit(0)

expected_targets = arguments
if expected_targets != canonical_targets or value.get("expected_targets") != expected_targets:
    fail("ordered phase target list does not match the release runner")
phases = value.get("phases")
if not isinstance(phases, list) or len(phases) != len(expected_targets):
    fail("does not contain all eleven completed phases")
seen_receipt_paths = set()
receipt_values = {}
for index, (phase, target) in enumerate(zip(phases, expected_targets), start=1):
    if not isinstance(phase, dict) or phase.get("index") != index or phase.get("target") != target:
        fail("completed phase order is invalid")
    completed_at = phase.get("completed_at")
    receipts = phase.get("evidence")
    expected_sources = phase_specs[index - 1][1]
    if not isinstance(completed_at, str) or not completed_at or not isinstance(receipts, list) \
            or len(receipts) != len(expected_sources):
        fail("completed phase receipt is incomplete")
    for receipt_index, (receipt, expected_source) in enumerate(zip(receipts, expected_sources), start=1):
        if not isinstance(receipt, dict):
            fail("evidence receipt is malformed")
        if not isinstance(receipt.get("path"), str) or not receipt["path"]:
            fail("evidence receipt path is missing")
        if not isinstance(receipt.get("source_path"), str) or not receipt["source_path"]:
            fail("evidence receipt source path is missing")
        if not isinstance(receipt.get("generated_at"), str) or not receipt["generated_at"]:
            fail("evidence receipt timestamp is missing")
        digest = receipt.get("sha256")
        if not isinstance(digest, str) or len(digest) != 64 or any(ch not in "0123456789abcdef" for ch in digest):
            fail("evidence receipt hash is invalid")
        raw_receipt_path = receipt["path"]
        normalized_receipt_path = PurePosixPath(raw_receipt_path)
        expected_receipt_path = receipt_root / f"phase{index:02d}-artifact{receipt_index:02d}.json"
        expected_receipt_relative = expected_receipt_path.relative_to(root).as_posix()
        if normalized_receipt_path.is_absolute() \
                or any(part in {"", ".", ".."} for part in normalized_receipt_path.parts) \
                or normalized_receipt_path.as_posix() != raw_receipt_path \
                or raw_receipt_path != expected_receipt_relative \
                or raw_receipt_path in seen_receipt_paths:
            fail("evidence receipt path is unsafe, duplicate, or does not match its phase index")
        if receipt["source_path"] != expected_source:
            fail("evidence receipt source path does not match its phase artifact mapping")
        seen_receipt_paths.add(raw_receipt_path)
        receipt_path = expected_receipt_path
        receipt_metadata = require_regular_0600(receipt_path)
        if receipt_metadata.st_nlink != 1:
            fail("evidence receipt must have exactly one hard link")
        try:
            receipt_bytes = receipt_path.read_bytes()
            receipt_after = receipt_path.lstat()
            receipt_value = json.loads(receipt_bytes.decode("utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError):
            fail("evidence receipt is not valid JSON")
        if (receipt_metadata.st_dev, receipt_metadata.st_ino, receipt_metadata.st_mode,
                receipt_metadata.st_nlink, receipt_metadata.st_size) != (
                receipt_after.st_dev, receipt_after.st_ino, receipt_after.st_mode,
                receipt_after.st_nlink, receipt_after.st_size):
            fail("evidence receipt changed while it was being read")
        receipt_generated_at = receipt_value.get("generated_at") if isinstance(receipt_value, dict) else None
        if hashlib.sha256(receipt_bytes).hexdigest() != digest \
                or receipt_generated_at != receipt["generated_at"]:
            fail("evidence receipt no longer matches its recorded hash and timestamp")
        receipt_values[(index, receipt_index)] = receipt_value


def chain_fingerprint(value):
    if not isinstance(value, dict):
        return None
    candidate = value.get("chain_fingerprint")
    if not isinstance(candidate, dict):
        chain_state = value.get("chain")
        if isinstance(chain_state, dict):
            candidate = chain_state.get("fingerprint")
        else:
            candidate = value
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
    fail("chain snapshot receipt lacks a complete fingerprint")
for key, receipt_value in receipt_values.items():
    if chain_fingerprint(receipt_value) != canonical_fingerprint:
        fail(f"phase {key[0]} artifact {key[1]} does not match the release chain fingerprint")

deploy_receipt = receipt_values.get((5, 1))
contracts_receipt = receipt_values.get((5, 2))
deploy_generated_at = deploy_receipt.get("generated_at") if isinstance(deploy_receipt, dict) else None
contracts_generated_at = contracts_receipt.get("generated_at") if isinstance(contracts_receipt, dict) else None
if not isinstance(deploy_generated_at, str) or not isinstance(contracts_generated_at, str):
    fail("deploy/contracts receipts lack generated_at identity")
for (phase_number, artifact_number), receipt_value in receipt_values.items():
    if phase_number < 6:
        continue
    deploy_snapshot = receipt_value.get("deploy_snapshot") if isinstance(receipt_value, dict) else None
    contracts_snapshot = receipt_value.get("contracts_snapshot") if isinstance(receipt_value, dict) else None
    if not isinstance(deploy_snapshot, dict) or deploy_snapshot.get("generated_at") != deploy_generated_at \
            or chain_fingerprint(deploy_snapshot) != canonical_fingerprint:
        fail(f"phase {phase_number} artifact {artifact_number} does not bind the phase-5 deploy snapshot")
    if not isinstance(contracts_snapshot, dict) or contracts_snapshot.get("generated_at") != contracts_generated_at \
            or chain_fingerprint(contracts_snapshot) != canonical_fingerprint:
        fail(f"phase {phase_number} artifact {artifact_number} does not bind the phase-5 contracts snapshot")

if action == "verify":
    print(value["run_id"])
    raise SystemExit(0)

if action == "remove":
    if len(arguments) != 11:
        fail("remove requires the exact ordered phase target list")
    expected_receipts = {
        root / receipt["path"]
        for phase in phases
        for receipt in phase["evidence"]
    }
    actual_receipts = set(receipt_root.iterdir())
    if actual_receipts != expected_receipts:
        fail("receipt directory contains unexpected or missing files")
    for receipt_path in sorted(expected_receipts):
        require_regular_0600(receipt_path)
        receipt_path.unlink()
    receipt_root.rmdir()
    journal.unlink()
    fsync_directory(journal.parent)
    raise SystemExit(0)
PY
}

release_closeout_checkpoint_resume_token() {
  local root="$1"
  local environment="$2"
  local checkpoint="$3"
  local python_bin="${commands[python3]:-python3}"

  "$python_bin" - "$root" "$environment" "$checkpoint" <<'PY'
import hashlib
import json
import os
import stat
import sys
from pathlib import Path

root_raw, environment, checkpoint_raw = sys.argv[1:]


def fail(message):
    raise SystemExit(f"release closeout checkpoint failed: {message}")


def canonical_hash(value):
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


if environment not in {"testnet", "production"}:
    fail(f"unsupported environment {environment}")
root_input = Path(os.path.abspath(root_raw))
expected_input = root_input / "tmp" / "release-closeout" / f"{environment}.pending.json"
if Path(os.path.abspath(checkpoint_raw)) != expected_input:
    fail("path does not match the selected release environment")
try:
    root = root_input.resolve(strict=True)
except OSError:
    fail("release root is missing")
expected = root / "tmp" / "release-closeout" / f"{environment}.pending.json"
checkpoint = expected
if checkpoint.parent.is_symlink() or checkpoint.parent.resolve(strict=True) != expected.parent:
    fail("parent path must be a real release-worktree directory")
try:
    metadata = checkpoint.lstat()
except OSError:
    fail(f"is missing: {checkpoint.relative_to(root).as_posix()}")
if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
    fail("must be a regular non-symlink file")
if stat.S_IMODE(metadata.st_mode) != 0o600 or metadata.st_nlink != 1:
    fail("must have mode 0600 and exactly one hard link")
try:
    raw = checkpoint.read_bytes()
    after = checkpoint.lstat()
    value = json.loads(raw.decode("utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError):
    fail("is not valid JSON")
if (metadata.st_dev, metadata.st_ino, metadata.st_mode, metadata.st_nlink, metadata.st_size) != (
        after.st_dev, after.st_ino, after.st_mode, after.st_nlink, after.st_size):
    fail("changed while it was being read")
if not isinstance(value, dict):
    fail("must be a JSON object")
integrity = value.pop("checkpoint_sha256", None)
if not isinstance(integrity, str) or integrity != canonical_hash(value):
    fail("integrity hash does not match its contents")
if value.get("schema") != "soraswap-release-closeout/v2" or value.get("environment") != environment:
    fail("schema or environment does not match the release")
token = value.get("resume_token")
if not isinstance(token, str) or len(token) != 64 or any(ch not in "0123456789abcdef" for ch in token):
    fail("resume token is invalid")
print(token)
PY
}

release_closeout_checkpoint_remove() {
  local root="$1"
  local environment="$2"
  local checkpoint="$3"
  local expected_token="$4"
  local python_bin="${commands[python3]:-python3}"

  "$python_bin" - "$root" "$environment" "$checkpoint" "$expected_token" <<'PY'
import hashlib
import json
import os
import stat
import sys
from pathlib import Path

root_raw, environment, checkpoint_raw, expected_token = sys.argv[1:]


def fail(message):
    raise SystemExit(f"release closeout checkpoint failed: {message}")


def canonical_hash(value):
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


if environment not in {"testnet", "production"}:
    fail(f"unsupported environment {environment}")
root_input = Path(os.path.abspath(root_raw))
expected_input = root_input / "tmp" / "release-closeout" / f"{environment}.pending.json"
if Path(os.path.abspath(checkpoint_raw)) != expected_input:
    fail("path does not match the selected release environment")
root = root_input.resolve(strict=True)
checkpoint = root / "tmp" / "release-closeout" / f"{environment}.pending.json"
if checkpoint.parent.is_symlink() or checkpoint.parent.resolve(strict=True) != checkpoint.parent:
    fail("parent path must be a real release-worktree directory")

flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
try:
    descriptor = os.open(checkpoint, flags)
except OSError:
    fail("checkpoint is missing or unsafe")
try:
    metadata = os.fstat(descriptor)
    if not stat.S_ISREG(metadata.st_mode) or stat.S_IMODE(metadata.st_mode) != 0o600 or metadata.st_nlink != 1:
        fail("checkpoint must be a mode-0600 regular file with exactly one hard link")
    chunks = []
    while True:
        chunk = os.read(descriptor, 1024 * 1024)
        if not chunk:
            break
        chunks.append(chunk)
    raw = b"".join(chunks)
finally:
    os.close(descriptor)
try:
    value = json.loads(raw.decode("utf-8"))
except (UnicodeError, json.JSONDecodeError):
    fail("checkpoint is not valid JSON")
if not isinstance(value, dict):
    fail("checkpoint must be a JSON object")
integrity = value.pop("checkpoint_sha256", None)
if not isinstance(integrity, str) or integrity != canonical_hash(value):
    fail("checkpoint integrity hash does not match its contents")
if value.get("schema") != "soraswap-release-closeout/v2" or value.get("environment") != environment:
    fail("checkpoint schema or environment does not match the release")
if value.get("resume_token") != expected_token:
    fail("checkpoint resume capability does not match")

try:
    current = checkpoint.lstat()
except OSError:
    fail("checkpoint changed before deletion")
identity = lambda item: (
    item.st_dev, item.st_ino, item.st_mode, item.st_nlink,
    item.st_size, item.st_mtime_ns,
)
if identity(current) != identity(metadata):
    fail("checkpoint identity changed before deletion")
try:
    current_descriptor = os.open(checkpoint, flags)
    try:
        current_metadata = os.fstat(current_descriptor)
        current_chunks = []
        while True:
            chunk = os.read(current_descriptor, 1024 * 1024)
            if not chunk:
                break
            current_chunks.append(chunk)
    finally:
        os.close(current_descriptor)
except OSError:
    fail("checkpoint changed before deletion")
if identity(current_metadata) != identity(metadata) or b"".join(current_chunks) != raw:
    fail("checkpoint bytes changed before deletion")
os.unlink(checkpoint)
directory_descriptor = os.open(checkpoint.parent, os.O_RDONLY)
try:
    os.fsync(directory_descriptor)
finally:
    os.close(directory_descriptor)
PY
}

release_closeout_source_state_json() {
  local root="$1"
  local environment="$2"
  local python_bin="${commands[python3]:-python3}"

  "$python_bin" - "$root" "$environment" <<'PY'
import hashlib
import os
import stat
import subprocess
import sys
from pathlib import Path

root_raw, environment = sys.argv[1:]


def fail(message):
    raise SystemExit(f"release checklist failed: closeout checkpoint {message}")


def git_output(*arguments):
    try:
        return subprocess.check_output(
            ["git", "-C", str(root), *arguments], stderr=subprocess.DEVNULL
        )
    except (OSError, subprocess.CalledProcessError):
        fail("requires a readable Git worktree")


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


if environment not in {"testnet", "production"}:
    fail(f"unsupported closeout environment {environment}")
try:
    root = Path(root_raw).resolve(strict=True)
except OSError:
    fail("release root is missing")

status_docs = {
    "testnet": {
        "docs/release/smart_contract_production_audit.md",
        "docs/release/production_readiness_checklist.md",
        "docs/release/taira_devex_critique.md",
    },
    "production": {
        "docs/release/smart_contract_production_audit.md",
        "docs/release/production_readiness_checklist.md",
    },
}[environment]

head = git_output("rev-parse", "HEAD").decode("ascii").strip()
if len(head) != 40:
    fail("Git HEAD is invalid")
index_tree = git_output("write-tree").decode("ascii").strip()
if len(index_tree) != 40:
    fail("Git index tree is invalid")

head_entries = {}
for record in git_output("ls-tree", "-rz", "--full-tree", head).split(b"\0"):
    if not record:
        continue
    try:
        metadata, raw_path = record.split(b"\t", 1)
        raw_mode, raw_type, raw_object = metadata.split(b" ", 2)
        relative = raw_path.decode("utf-8", errors="surrogateescape")
        mode = raw_mode.decode("ascii")
        object_type = raw_type.decode("ascii")
        object_id = raw_object.decode("ascii")
    except (ValueError, UnicodeError):
        fail("cannot parse the HEAD tree")
    if object_type != "blob" or mode not in {"100644", "100755", "120000"}:
        fail(f"unsupported tracked source entry in HEAD: {relative}")
    head_entries[relative] = (mode, object_id)

index_entries = {}
for record in git_output("ls-files", "--stage", "-z").split(b"\0"):
    if not record:
        continue
    try:
        metadata, raw_path = record.split(b"\t", 1)
        raw_mode, raw_object, raw_stage = metadata.split(b" ", 2)
        relative = raw_path.decode("utf-8", errors="surrogateescape")
        mode = raw_mode.decode("ascii")
        object_id = raw_object.decode("ascii")
        stage = raw_stage.decode("ascii")
    except (ValueError, UnicodeError):
        fail("cannot parse the Git index")
    if stage != "0" or relative in index_entries:
        fail(f"Git index has unresolved identity for tracked source: {relative}")
    index_entries[relative] = (mode, object_id)

for relative in sorted(set(head_entries) | set(index_entries)):
    if relative not in head_entries:
        fail(f"Git index adds non-HEAD source: {relative}")
    if relative not in index_entries:
        fail(f"Git index deletes tracked source: {relative}")
    head_mode, head_object = head_entries[relative]
    index_mode, index_object = index_entries[relative]
    if index_mode != head_mode:
        fail(f"Git index changes tracked source mode or type: {relative}")
    if relative not in status_docs and index_object != head_object:
        fail(f"Git index changes tracked non-status-doc source: {relative}")

untracked = [
    record.decode("utf-8", errors="surrogateescape")
    for record in git_output("ls-files", "--others", "--exclude-standard", "-z").split(b"\0")
    if record
]
if untracked:
    fail(f"non-ignored untracked source is present: {sorted(untracked)[0]}")

entries = []
status_identities = []
for relative in sorted(head_entries):
    head_mode, head_object = head_entries[relative]
    path = root / relative
    try:
        metadata = path.lstat()
    except OSError:
        fail(f"tracked source is missing: {relative}")

    if relative in status_docs:
        if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode) or metadata.st_nlink != 1:
            fail(f"tracked status doc must remain a regular file: {relative}")
        current_mode = "100755" if metadata.st_mode & 0o111 else "100644"
        if current_mode != head_mode:
            fail(f"tracked status doc mode differs from HEAD: {relative}")
        current = path.read_bytes()
        staged = git_output("cat-file", "blob", index_entries[relative][1])
        if current != staged:
            fail(f"tracked status doc index bytes differ from the validated worktree file: {relative}")
        status_identities.append((relative, sha256_bytes(head_mode.encode("ascii") + b"\0" + head_object.encode("ascii"))))
        continue

    if head_mode == "120000":
        if not stat.S_ISLNK(metadata.st_mode):
            fail(f"tracked source type differs from HEAD: {relative}")
        current = os.readlink(path).encode("utf-8", errors="surrogateescape")
        current_mode = "120000"
    else:
        if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            fail(f"tracked source type differs from HEAD: {relative}")
        current = path.read_bytes()
        current_mode = "100755" if metadata.st_mode & 0o111 else "100644"
    if current_mode != head_mode:
        fail(f"tracked non-status-doc mode differs from HEAD: {relative}")
    committed = git_output("cat-file", "blob", head_object)
    if current != committed:
        fail(f"tracked non-status-doc source differs from HEAD: {relative}")
    entries.append((relative, sha256_bytes(head_mode.encode("ascii") + b"\0" + current)))

missing_status_docs = sorted(status_docs - set(head_entries))
if missing_status_docs:
    fail(f"required status doc is not tracked in HEAD: {missing_status_docs[0]}")

head_after = git_output("rev-parse", "HEAD").decode("ascii").strip()
index_tree_after = git_output("write-tree").decode("ascii").strip()
untracked_after = [
    record.decode("utf-8", errors="surrogateescape")
    for record in git_output("ls-files", "--others", "--exclude-standard", "-z").split(b"\0")
    if record
]
if head_after != head or index_tree_after != index_tree or untracked_after != untracked:
    fail("Git HEAD, index, or untracked source changed while source state was being captured")

import json
print(json.dumps({
    "git_head": head,
    "tracked_non_status_doc_count": len(entries),
    "tracked_non_status_doc_sha256": aggregate(entries),
    "tracked_status_doc_count": len(status_identities),
    "tracked_status_doc_identity_sha256": aggregate(status_identities),
}, sort_keys=True, separators=(",", ":")))
PY
}

release_phase_guard_display_path() {
  local path="${1:-}"

  if (( $+functions[soraswap_display_path] )); then
    soraswap_display_path "$path"
    return
  fi
  if [[ "$path" == /* ]]; then
    printf '%s\n' "${path:t}"
  else
    printf '%s\n' "$path"
  fi
}

release_phase_guard_redact_text() {
  local value="${1:-}"

  if (( $+functions[soraswap_redact_sensitive_text] )); then
    soraswap_redact_sensitive_text "$value"
    return
  fi

  perl -0pe '
    s~\b([a-z][a-z0-9+.-]*://)[^/\s:@?#]+(?::[^/\s@?#]*)?@~${1}[redacted]@~gim;
    s~([?&#](?:private[-_]?key|secret|mnemonic|api[-_]?token|access[-_]?token|refresh[-_]?token|api[-_]?key|authorization|bearer[-_]?token|client[-_]?secret|token|password|passphrase)=)[^&#\s",}\]]+~${1}[redacted]~gim;
    s/((?:authorization)\s*[:=]\s*)Bearer\s+[^,\r\n[:space:]]+/$1"[redacted]"/gim;
    s/((?:authorization)\s*[:=]\s*)Basic\s+[A-Za-z0-9+\/=]+/$1"[redacted]"/gim;
    s/((?:--?)authorization(?:=|\s+))Bearer\s+[^,\r\n[:space:]]+/$1"[redacted]"/gim;
    s/((?:--?)authorization(?:=|\s+))Basic\s+[A-Za-z0-9+\/=]+/$1"[redacted]"/gim;
    s/(?<![?&#A-Za-z0-9_-])((?:"(?:private[_ -]?key|privateKey|secret|mnemonic|api[_ -]?token|apiToken|access[_ -]?token|accessToken|refresh[_ -]?token|refreshToken|api[_ -]?key|apiKey|authorization|bearer[_ -]?token|bearerToken|client[_ -]?secret|clientSecret|token|password|passphrase)"|(?:private[_ -]?key|privateKey|secret|mnemonic|api[_ -]?token|apiToken|access[_ -]?token|accessToken|refresh[_ -]?token|refreshToken|api[_ -]?key|apiKey|authorization|bearer[_ -]?token|bearerToken|client[_ -]?secret|clientSecret|token|password|passphrase))\s*[:=]\s*)("[^"]*"|'\''[^'\'']*'\''|[^,}\s]+)/$1"[redacted]"/gim;
    s/(?<![?&#A-Za-z0-9_-])((?:--?)(?:private[-_]?key|secret|mnemonic|api[-_]?token|access[-_]?token|refresh[-_]?token|api[-_]?key|authorization|bearer[-_]?token|client[-_]?secret|token|password|passphrase)(?:=|\s+))("[^"]*"|'\''[^'\'']*'\''|[^,\s]+)/$1"[redacted]"/gim;
    s#file://(?:localhost)?/(?:Users|private/var/folders|var/folders|private/tmp|tmp)/[^\s",}\]]+#[runtime-path]/redacted#ge;
    s#file:/(?:Users|private/var/folders|var/folders|private/tmp|tmp)/[^\s",}\]]+#[runtime-path]/redacted#ge;
    s#(?<![A-Za-z0-9:/])(?:/private)?/var/folders/[^\s",}\]]+#[runtime-path]/redacted#ge;
    s#(?<![A-Za-z0-9:/])(?:/private)?/tmp/[^\s",}\]]+#[runtime-path]/redacted#ge;
    s#(?<![A-Za-z0-9:/])/Users/[^\s",}\]]+#[local-path]/redacted#ge;
  ' <<<"$value"
}

release_phase_guard_rwa_release_enabled_json() {
  local env="$1"
  local default_value value

  if (( $+functions[soraswap_rwa_release_enabled_json_for_env] )); then
    soraswap_rwa_release_enabled_json_for_env "$env"
    return
  fi

  case "$env" in
    local)
      default_value=1
      ;;
    testnet|production)
      default_value=0
      ;;
    *)
      default_value=0
      ;;
  esac
  value="${SORASWAP_ENABLE_RWA_RELEASE:-$default_value}"
  case "$value" in
    0)
      printf '%s\n' false
      ;;
    1)
      printf '%s\n' true
      ;;
    *)
      return 1
      ;;
  esac
}

release_phase_guard_print_details() {
  local artifact="$1"
  local artifact_status summary blocked_reason deployment_record_status snapshot_check_status cid_probe_status blocker

  artifact_status="$(jq -r '.status // empty' "$artifact" 2>/dev/null || true)"
  [[ -z "$artifact_status" ]] || echo "  status: $artifact_status" >&2

  jq -r '(.phases // {}) | to_entries[]? | "  phase.\(.key).status: \(.value.status // "missing")"' "$artifact" >&2 2>/dev/null || true
  jq -r '
    if (.generated_at // null) != null then
      "  generated_at: \(.generated_at)"
    else empty end,
    if (.environment // null) != null then
      "  environment: \(.environment)"
    else empty end,
    if (.phases.deployment_records_snapshot.detail.snapshot // null) != null then
      "  phase.deployment_records_snapshot.detail.snapshot: \(.phases.deployment_records_snapshot.detail.snapshot)"
    else empty end,
    if (.phases.preflight.detail.signer_ready_check.status // null) != null then
      "  phase.preflight.signer_ready_check.status: \(.phases.preflight.detail.signer_ready_check.status)"
    else empty end,
    if (.phases.preflight.detail.signer_ready_check.debug_bypass_env // null) != null then
      "  phase.preflight.signer_ready_check.debug_bypass_env: \(.phases.preflight.detail.signer_ready_check.debug_bypass_env)"
    else empty end
  ' "$artifact" >&2 2>/dev/null || true

  while IFS= read -r blocker; do
    [[ -n "$blocker" ]] || continue
    echo "  blocker: $(release_phase_guard_redact_text "$blocker")" >&2
  done < <(jq -r '(.blockers // [])[]? | tostring' "$artifact" 2>/dev/null || true)

  blocked_reason="$(jq -r '.blocked_reason // empty' "$artifact" 2>/dev/null || true)"
  [[ -z "$blocked_reason" ]] || echo "  blocked_reason: $(release_phase_guard_redact_text "$blocked_reason")" >&2

  summary="$(jq -r '.summary // .nested_call_probe.summary // empty' "$artifact" 2>/dev/null || true)"
  [[ -z "$summary" ]] || echo "  summary: $(release_phase_guard_redact_text "$summary")" >&2

  deployment_record_status="$(jq -r '.deployment_record_check.status // empty' "$artifact" 2>/dev/null || true)"
  [[ -z "$deployment_record_status" ]] || echo "  deployment_record_check.status: $deployment_record_status" >&2

  snapshot_check_status="$(jq -r '.snapshot_check.status // empty' "$artifact" 2>/dev/null || true)"
  [[ -z "$snapshot_check_status" ]] || echo "  snapshot_check.status: $snapshot_check_status" >&2

  cid_probe_status="$(jq -r '.cid_probe.status // empty' "$artifact" 2>/dev/null || true)"
  [[ -z "$cid_probe_status" ]] || echo "  cid_probe.status: $cid_probe_status" >&2

  jq -r '
    if (.chain_fingerprint.torii_url // null) != null then
      "  chain_fingerprint.torii_url: \(.chain_fingerprint.torii_url)"
    else empty end,
    if (.chain_fingerprint.chain // null) != null then
      "  chain_fingerprint.chain: \(.chain_fingerprint.chain)"
    else empty end,
    if (.chain_fingerprint.block_1_hash // null) != null then
      "  chain_fingerprint.block_1_hash: \(.chain_fingerprint.block_1_hash)"
    else empty end,
    if (.contracts_snapshot.generated_at // null) != null then
      "  contracts_snapshot.generated_at: \(.contracts_snapshot.generated_at)"
    else empty end,
    if (.contracts_snapshot.status // null) != null then
      "  contracts_snapshot.status: \(.contracts_snapshot.status)"
    else empty end,
    if (.contracts_snapshot.environment // null) != null then
      "  contracts_snapshot.environment: \(.contracts_snapshot.environment)"
    else empty end,
    if (.contracts_snapshot.chain_fingerprint.torii_url // null) != null then
      "  contracts_snapshot.chain_fingerprint.torii_url: \(.contracts_snapshot.chain_fingerprint.torii_url)"
    else empty end,
    if (.contracts_snapshot.chain_fingerprint.chain // null) != null then
      "  contracts_snapshot.chain_fingerprint.chain: \(.contracts_snapshot.chain_fingerprint.chain)"
    else empty end,
    if (.contracts_snapshot.chain_fingerprint.block_1_hash // null) != null then
      "  contracts_snapshot.chain_fingerprint.block_1_hash: \(.contracts_snapshot.chain_fingerprint.block_1_hash)"
    else empty end,
    if (.deploy_snapshot.generated_at // null) != null then
      "  deploy_snapshot.generated_at: \(.deploy_snapshot.generated_at)"
    else empty end,
    if (.deploy_snapshot.environment // null) != null then
      "  deploy_snapshot.environment: \(.deploy_snapshot.environment)"
    else empty end,
    if (.deploy_snapshot.chain_fingerprint.torii_url // null) != null then
      "  deploy_snapshot.chain_fingerprint.torii_url: \(.deploy_snapshot.chain_fingerprint.torii_url)"
    else empty end,
    if (.deploy_snapshot.chain_fingerprint.chain // null) != null then
      "  deploy_snapshot.chain_fingerprint.chain: \(.deploy_snapshot.chain_fingerprint.chain)"
    else empty end,
    if (.deploy_snapshot.chain_fingerprint.block_1_hash // null) != null then
      "  deploy_snapshot.chain_fingerprint.block_1_hash: \(.deploy_snapshot.chain_fingerprint.block_1_hash)"
    else empty end,
    if (.deploy_snapshot.status // null) != null then
      "  deploy_snapshot.status: \(.deploy_snapshot.status)"
    else empty end,
    if (.readonly_verification.contracts_snapshot.generated_at // null) != null then
      "  readonly_verification.contracts_snapshot.generated_at: \(.readonly_verification.contracts_snapshot.generated_at)"
    else empty end,
    if (.readonly_verification.contracts_snapshot.status // null) != null then
      "  readonly_verification.contracts_snapshot.status: \(.readonly_verification.contracts_snapshot.status)"
    else empty end,
    if (.readonly_verification.contracts_snapshot.environment // null) != null then
      "  readonly_verification.contracts_snapshot.environment: \(.readonly_verification.contracts_snapshot.environment)"
    else empty end,
    if (.readonly_verification.contracts_snapshot.chain_fingerprint.torii_url // null) != null then
      "  readonly_verification.contracts_snapshot.chain_fingerprint.torii_url: \(.readonly_verification.contracts_snapshot.chain_fingerprint.torii_url)"
    else empty end,
    if (.readonly_verification.contracts_snapshot.chain_fingerprint.chain // null) != null then
      "  readonly_verification.contracts_snapshot.chain_fingerprint.chain: \(.readonly_verification.contracts_snapshot.chain_fingerprint.chain)"
    else empty end,
    if (.readonly_verification.contracts_snapshot.chain_fingerprint.block_1_hash // null) != null then
      "  readonly_verification.contracts_snapshot.chain_fingerprint.block_1_hash: \(.readonly_verification.contracts_snapshot.chain_fingerprint.block_1_hash)"
    else empty end,
    if (.readonly_verification.deploy_snapshot.generated_at // null) != null then
      "  readonly_verification.deploy_snapshot.generated_at: \(.readonly_verification.deploy_snapshot.generated_at)"
    else empty end,
    if (.readonly_verification.deploy_snapshot.status // null) != null then
      "  readonly_verification.deploy_snapshot.status: \(.readonly_verification.deploy_snapshot.status)"
    else empty end,
    if (.readonly_verification.deploy_snapshot.environment // null) != null then
      "  readonly_verification.deploy_snapshot.environment: \(.readonly_verification.deploy_snapshot.environment)"
    else empty end,
    if (.readonly_verification.deploy_snapshot.chain_fingerprint.torii_url // null) != null then
      "  readonly_verification.deploy_snapshot.chain_fingerprint.torii_url: \(.readonly_verification.deploy_snapshot.chain_fingerprint.torii_url)"
    else empty end,
    if (.readonly_verification.deploy_snapshot.chain_fingerprint.chain // null) != null then
      "  readonly_verification.deploy_snapshot.chain_fingerprint.chain: \(.readonly_verification.deploy_snapshot.chain_fingerprint.chain)"
    else empty end,
    if (.readonly_verification.deploy_snapshot.chain_fingerprint.block_1_hash // null) != null then
      "  readonly_verification.deploy_snapshot.chain_fingerprint.block_1_hash: \(.readonly_verification.deploy_snapshot.chain_fingerprint.block_1_hash)"
    else empty end
  ' "$artifact" >&2 2>/dev/null || true
}

release_phase_guard_require_json() {
  local prefix="$1"
  local artifact="$2"

  if [[ ! -s "$artifact" ]]; then
    echo "$prefix: evidence guard failed for ${artifact:t}: missing or empty artifact" >&2
    return 1
  fi
  if ! jq -e type "$artifact" >/dev/null 2>&1; then
    echo "$prefix: evidence guard failed for ${artifact:t}: invalid JSON" >&2
    return 1
  fi
}

release_phase_guard_require_no_local_path_leaks() {
  local prefix="$1"
  local artifact="$2"

  release_phase_guard_require_json "$prefix" "$artifact" || return 1
  if ! python3 - "$artifact" >/dev/null <<'PY'
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

data = json.loads(path.read_text(encoding="utf-8"))
if any(pattern.search(value) for value in iter_strings(data)):
    raise SystemExit(1)
PY
  then
    echo "$prefix: evidence guard failed for ${artifact:t}: contains local filesystem path diagnostics; rerun the evidence with current redaction helpers" >&2
    return 1
  fi
}

release_phase_guard_require_no_sensitive_diagnostic_leaks() {
  local prefix="$1"
  local artifact="$2"

  release_phase_guard_require_json "$prefix" "$artifact" || return 1
  if ! python3 - "$artifact" >/dev/null <<'PY'
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])

SENSITIVE_KEYS = {
    "privatekey",
    "secret",
    "mnemonic",
    "token",
    "accesstoken",
    "refreshtoken",
    "apitoken",
    "apikey",
    "authorization",
    "bearertoken",
    "clientsecret",
    "password",
    "passphrase",
}
SENSITIVE_PATTERNS = [
    re.compile(r"\b[a-z][a-z0-9+.-]*://(?!\[redacted\]@)[^/\s:@?#]+(?::[^/\s@?#]*)?@", re.IGNORECASE),
    re.compile(
        r"[?&#](?:private[-_]?key|secret|mnemonic|api[-_]?token|access[-_]?token|refresh[-_]?token|api[-_]?key|authorization|bearer[-_]?token|client[-_]?secret|token|password|passphrase)=(?!\[redacted\](?:[&#\s\"',}\]]|$))[^&#\s\"',}\]]+",
        re.IGNORECASE,
    ),
    re.compile(r"((?:authorization)\s*[:=]\s*)Bearer\s+[^,\r\n\s]+", re.IGNORECASE),
    re.compile(r"((?:authorization)\s*[:=]\s*)Basic\s+[A-Za-z0-9+/=]+", re.IGNORECASE),
    re.compile(r"((?:--?)authorization(?:=|\s+))Bearer\s+[^,\r\n\s]+", re.IGNORECASE),
    re.compile(r"((?:--?)authorization(?:=|\s+))Basic\s+[A-Za-z0-9+/=]+", re.IGNORECASE),
    re.compile(
        r"(?<![?&#A-Za-z0-9_-])((?:\"(?:private[_ -]?key|privateKey|secret|mnemonic|api[_ -]?token|apiToken|access[_ -]?token|accessToken|refresh[_ -]?token|refreshToken|api[_ -]?key|apiKey|authorization|bearer[_ -]?token|bearerToken|client[_ -]?secret|clientSecret|token|password|passphrase)\"|(?:private[_ -]?key|privateKey|secret|mnemonic|api[_ -]?token|apiToken|access[_ -]?token|accessToken|refresh[_ -]?token|refreshToken|api[_ -]?key|apiKey|authorization|bearer[_ -]?token|bearerToken|client[_ -]?secret|clientSecret|token|password|passphrase))\s*[:=]\s*)(\"[^\"]*\"|[^,}\s]+)",
        re.IGNORECASE,
    ),
    re.compile(
        r"(?<![?&#A-Za-z0-9_-])((?:--?)(?:private[-_]?key|secret|mnemonic|api[-_]?token|access[-_]?token|refresh[-_]?token|api[-_]?key|authorization|bearer[-_]?token|client[-_]?secret|token|password|passphrase)(?:=|\s+))(\"[^\"]*\"|[^,\s]+)",
        re.IGNORECASE,
    ),
]


def sensitive_key(value):
    normalized = re.sub(r"[^a-z0-9]", "", str(value).lower())
    return normalized in SENSITIVE_KEYS


def sensitive_text(value):
    text = str(value)
    return any(pattern.search(text) for pattern in SENSITIVE_PATTERNS)


def has_sensitive(value):
    if isinstance(value, str):
        return sensitive_text(value)
    if isinstance(value, list):
        return any(has_sensitive(item) for item in value)
    if isinstance(value, dict):
        for key, item in value.items():
            if sensitive_text(key):
                return True
            if sensitive_key(key) and item != "[redacted]":
                return True
            if has_sensitive(item):
                return True
    return False


if has_sensitive(json.loads(path.read_text(encoding="utf-8"))):
    raise SystemExit(1)
PY
  then
    echo "$prefix: evidence guard failed for ${artifact:t}: contains unredacted sensitive diagnostics; rerun the evidence with current redaction helpers" >&2
    return 1
  fi
}

release_phase_guard_require_condition() {
  local prefix="$1"
  local env="$2"
  local artifact="$3"
  local description="$4"
  local jq_filter="$5"

  release_phase_guard_require_json "$prefix" "$artifact" || return 1
  if ! jq -e --arg release_env "$env" "$jq_filter" "$artifact" >/dev/null 2>&1; then
    echo "$prefix: evidence guard failed for ${artifact:t}: $description" >&2
    release_phase_guard_print_details "$artifact"
    return 1
  fi
}

release_phase_guard_require_snapshot_check_completed() {
  local prefix="$1"
  local env="$2"
  local artifact="$3"

  release_phase_guard_require_json "$prefix" "$artifact" || return 1
  release_phase_guard_require_condition "$prefix" "$env" "$artifact" \
    "snapshot freshness check must be present and completed" \
    '(.snapshot_check.status // "") == "completed"' || return 1
}

release_phase_guard_trim() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

release_phase_guard_repo_root() {
  local evidence_dir="$1"
  local inferred_root

  inferred_root="$(cd "$evidence_dir/../.." && pwd 2>/dev/null || true)"
  if [[ -n "$inferred_root" ]]; then
    printf '%s\n' "$inferred_root"
    return 0
  fi
  if [[ -n "${SORASWAP_ROOT:-}" ]]; then
    printf '%s\n' "$SORASWAP_ROOT"
    return 0
  fi
  return 1
}

release_phase_guard_require_migration_register() {
  local prefix="$1"
  local evidence_dir="$2"
  local repo_root register line row_status
  local ported_count=0
  typeset -a non_ported_lines

  repo_root="$(release_phase_guard_repo_root "$evidence_dir" 2>/dev/null || true)"
  register="$repo_root/docs/parity/migration_register.md"
  if [[ -z "$repo_root" || ! -s "$register" ]]; then
    echo "$prefix: evidence guard failed for migration_register.md: missing or empty migration register at $(release_phase_guard_display_path "$register")" >&2
    return 1
  fi

  while IFS= read -r line; do
    [[ "$line" == \|* ]] || continue
    [[ "$line" == *"| Status |"* ]] && continue
    [[ "$line" == *"| --- |"* ]] && continue

    IFS='|' read -r _ _ _ row_status _ <<<"$line"
    row_status="$(release_phase_guard_trim "$row_status")"
    case "$row_status" in
      ported)
        ported_count=$(( ported_count + 1 ))
        ;;
      reference-only)
        ;;
      *)
        non_ported_lines+=("$line")
        ;;
    esac
  done < "$register"

  if (( ${#non_ported_lines[@]} > 0 )); then
    echo "$prefix: evidence guard failed for migration_register.md: migration register still contains non-ported production rows" >&2
    printf '%s\n' "${non_ported_lines[@]}" >&2
    return 1
  fi
  if (( ported_count == 0 )); then
    echo "$prefix: evidence guard failed for migration_register.md: migration register must contain at least one ported production row" >&2
    return 1
  fi
}

release_phase_guard_manifest_hash() {
  local manifest_path="$1"
  local field="$2"

  jq -r --arg field "$field" '
    (getpath([$field]) // "")
    | tostring
    | sub("^hash:"; "")
    | split("#")[0]
    | sub("^0x"; "")
    | ascii_downcase
  ' "$manifest_path" 2>/dev/null
}

release_phase_guard_content_cid_from_hex() {
  local python_bin="${commands[python3]:-python3}"

  "$python_bin" - "$1" <<'PY'
import base64
import sys

raw = bytes.fromhex(sys.argv[1].strip())
print("b" + base64.b32encode(raw).decode("ascii").lower().rstrip("="))
PY
}

release_phase_guard_require_metadata() {
  local prefix="$1"
  local env="$2"
  local artifact="$3"
  local environment_field="$4"

  release_phase_guard_require_condition "$prefix" "$env" "$artifact" \
    "missing generated_at" \
    '((.generated_at // "") | type == "string" and length > 0)' || return 1
  release_phase_guard_require_no_local_path_leaks "$prefix" "$artifact" || return 1
  if [[ "${artifact:t}" != "rwa_compliance.latest.json" ]]; then
    release_phase_guard_require_no_sensitive_diagnostic_leaks "$prefix" "$artifact" || return 1
  fi
  release_phase_guard_require_json "$prefix" "$artifact" || return 1
  if ! jq -e --arg release_env "$env" --arg environment_field "$environment_field" \
    '((getpath([$environment_field]) // "") | type == "string") and getpath([$environment_field]) == $release_env' \
    "$artifact" >/dev/null 2>&1; then
    echo "$prefix: evidence guard failed for ${artifact:t}: must record selected environment" >&2
    release_phase_guard_print_details "$artifact"
    return 1
  fi
}

release_phase_guard_require_release_ready_preflight_basics() {
  local prefix="$1"
  local env="$2"
  local evidence_dir="$3"
  local preflight_artifact="${4:-$evidence_dir/preflight.latest.json}"

  release_phase_guard_require_metadata "$prefix" "$env" "$preflight_artifact" target_environment || return 1
  release_phase_guard_require_condition "$prefix" "$env" "$preflight_artifact" \
    "preflight must prove release-ready public environment basics" \
    '.status == "ready"
      and ((.blockers // []) | length) == 0
      and ((.warnings // []) | length) == 0
      and (.environment.mutations_allowed // false) == true
      and (.environment.oracle_public_key_present // false) == true
      and (.environment.oracle_private_key_present // false) == true
      and (.environment.oracle_keypair_verified // false) == true
      and ((.environment.oracle_public_key_source // "") | type == "string" and length > 0)
      and ((.environment.oracle_private_key_source // "") | type == "string" and length > 0)
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
      and ((.chain.fingerprint.torii_url // "") | type == "string" and length > 0)
      and ((.chain.fingerprint.chain // "") | type == "string" and length > 0)
      and ((.chain.fingerprint.block_1_hash // "") | type == "string" and length > 0)
      and (.signer.authority_derivable // false) == true
      and (.signer.account_exists // false) == true
      and (.signer.assets_query_available // false) == true
      and (((.signer.fee_balance // "0") | tonumber) > 0)' || return 1
}

release_phase_guard_require_current_snapshots() {
  local prefix="$1"
  local env="$2"
  local evidence_dir="$3"
  local artifact="$4"
  local contracts_artifact="$evidence_dir/contracts.latest.json"
  local deploy_artifact="$evidence_dir/deploy.latest.json"

  release_phase_guard_require_json "$prefix" "$artifact" || return 1
  release_phase_guard_require_json "$prefix" "$contracts_artifact" || return 1
  release_phase_guard_require_json "$prefix" "$deploy_artifact" || return 1
  if ! jq -e \
    --arg release_env "$env" \
    --slurpfile contracts "$contracts_artifact" \
    --slurpfile deploy "$deploy_artifact" \
    'def snapshot_matches($snapshot; $current):
        ($snapshot | type) == "object"
        and ($snapshot.generated_at // null) == ($current.generated_at // null)
        and (($current.generated_at // "") | type == "string" and length > 0)
        and (($snapshot.generated_at // "") | type == "string" and length > 0)
        and ($snapshot.status // null) == ($current.status // null)
        and ($snapshot.environment // null) == ($current.environment // null)
        and ($snapshot.environment // null) == $release_env
        and (($current.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
        and (($snapshot.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
        and ($snapshot.chain_fingerprint.torii_url // null) == ($current.chain_fingerprint.torii_url // null)
        and ($snapshot.chain_fingerprint.chain // null) == ($current.chain_fingerprint.chain // null)
        and ($snapshot.chain_fingerprint.block_1_hash // null) == ($current.chain_fingerprint.block_1_hash // null);

      snapshot_matches(.contracts_snapshot; $contracts[0])
      and snapshot_matches(.deploy_snapshot; $deploy[0])
      and ($contracts[0].status // null) == "completed"
      and ($deploy[0].status // null) == "completed"
      and (.deploy_snapshot.status // null) == ($deploy[0].status // null)' \
    "$artifact" >/dev/null 2>&1; then
    echo "$prefix: evidence guard failed for ${artifact:t}: must reference current contracts/deploy snapshots" >&2
    release_phase_guard_print_details "$artifact"
    return 1
  fi
}

release_phase_guard_require_not_older_than_current_snapshots() {
  local prefix="$1"
  local evidence_dir="$2"
  local artifact="$3"
  local contracts_artifact="$evidence_dir/contracts.latest.json"
  local deploy_artifact="$evidence_dir/deploy.latest.json"

  release_phase_guard_require_json "$prefix" "$artifact" || return 1
  release_phase_guard_require_json "$prefix" "$contracts_artifact" || return 1
  release_phase_guard_require_json "$prefix" "$deploy_artifact" || return 1
  if ! jq -e \
    --slurpfile contracts "$contracts_artifact" \
    --slurpfile deploy "$deploy_artifact" \
    '((.generated_at // "") | length > 0)
      and (.generated_at >= ($contracts[0].generated_at // ""))
      and (.generated_at >= ($deploy[0].generated_at // ""))' \
    "$artifact" >/dev/null 2>&1; then
    echo "$prefix: evidence guard failed for ${artifact:t}: must not be older than current contracts/deploy snapshots" >&2
    release_phase_guard_print_details "$artifact"
    return 1
  fi
}

release_phase_guard_require_chain_artifact_fields() {
  local prefix="$1"
  local chain_artifact="$2"

  release_phase_guard_require_json "$prefix" "$chain_artifact" || return 1
  if ! jq -e '
    ((.generated_at // "") | type == "string" and length > 0)
    and ((.torii_url // "") | type == "string" and length > 0)
    and ((.chain // "") | type == "string" and length > 0)
    and ((.block_1_hash // "") | type == "string" and length > 0)
  ' "$chain_artifact" >/dev/null 2>&1; then
    echo "$prefix: evidence guard failed for ${chain_artifact:t}: must include non-empty generated_at, torii_url, chain, and block_1_hash" >&2
    release_phase_guard_print_details "$chain_artifact"
    return 1
  fi
}

release_phase_guard_signed_nested_probe_command() {
  local env="$1"

  case "$env" in
    testnet)
      echo "SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make testnet-nested-call-probe"
      ;;
    production)
      echo "SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make production-nested-call-probe"
      ;;
    *)
      echo "make ${env}-nested-call-probe"
      ;;
  esac
}

release_phase_guard_print_chain_refresh_hint() {
  local env="$1"

  case "$env" in
    testnet)
      echo "  next chain refresh: make refresh-testnet-chain" >&2
      echo "  then refresh signed probe evidence: $(release_phase_guard_signed_nested_probe_command "$env")" >&2
      ;;
    production)
      echo "  next chain refresh: make refresh-production-chain" >&2
      echo "  then refresh signed probe evidence: $(release_phase_guard_signed_nested_probe_command "$env")" >&2
      ;;
  esac
}

release_phase_guard_print_nested_probe_recovery_hint() {
  local env="$1"
  local evidence_dir="$2"
  local probe_artifact="$evidence_dir/nested_call_probe.latest.json"
  local chain_artifact="$evidence_dir/chain.latest.json"

  if [[ ! -s "$probe_artifact" ]]; then
    echo "  next signed probe: $(release_phase_guard_signed_nested_probe_command "$env")" >&2
    return
  fi
  if ! jq -e type "$probe_artifact" >/dev/null 2>&1; then
    echo "  next signed probe: $(release_phase_guard_signed_nested_probe_command "$env")" >&2
    return
  fi
  if ! jq -e --arg release_env "$env" '
    ((.generated_at // "") | type == "string" and length > 0)
    and ((.environment // "") | type == "string" and . == $release_env)
  ' "$probe_artifact" >/dev/null 2>&1; then
    echo "  next signed probe: $(release_phase_guard_signed_nested_probe_command "$env")" >&2
    return
  fi
  if [[ -s "$chain_artifact" ]] && jq -e type "$chain_artifact" >/dev/null 2>&1; then
    if ! jq -e \
      --slurpfile chain "$chain_artifact" \
      '(.chain_fingerprint != null)
        and ((.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
        and (.chain_fingerprint.torii_url // null) == ($chain[0].torii_url // null)
        and (.chain_fingerprint.chain // null) == ($chain[0].chain // null)
        and (.chain_fingerprint.block_1_hash // null) == ($chain[0].block_1_hash // null)' \
      "$probe_artifact" >/dev/null 2>&1; then
      echo "  next signed probe: $(release_phase_guard_signed_nested_probe_command "$env")" >&2
      return
    fi
  fi
  if jq -e \
    '(.supported == false)
      or (((.summary // "") | type == "string") and ((.summary // "") | length > 0))' \
    "$probe_artifact" >/dev/null 2>&1; then
    case "$env" in
      testnet)
        echo "  next runtime check: roll public Taira with the sibling ../iroha router and nested-transfer runtime fixes, then run:" >&2
        echo '    bash ../iroha/configs/soranexus/taira/verify_soraswap_rollout.sh --public-root "$PUBLIC_TORII_ROOT" --write-config /run/secrets/taira-canary-client.toml --soraswap-client-config "$SORASWAP_CLIENT_CONFIG" --allow-testnet-mutations' >&2
        ;;
      production)
        echo "  next runtime check: roll the production public runtime with the sibling ../iroha router and nested-transfer runtime fixes, then rerun:" >&2
        echo "    $(release_phase_guard_signed_nested_probe_command "$env")" >&2
        ;;
    esac
    return
  fi

  echo "  next signed probe: $(release_phase_guard_signed_nested_probe_command "$env")" >&2
}

release_phase_guard_print_preflight_recovery_hint() {
  local env="$1"
  local evidence_dir="$2"
  local preflight_artifact="$3"

  if jq -e '
    (.chain.saved_snapshot_exists == false)
      or (.chain.saved_snapshot_matches == false)
  ' "$preflight_artifact" >/dev/null 2>&1; then
    release_phase_guard_print_chain_refresh_hint "$env"
    return
  fi
  if jq -e '
    (.nested_call_probe.latest_exists == false)
      or (.nested_call_probe.matches_current_chain == false)
  ' "$preflight_artifact" >/dev/null 2>&1; then
    echo "  next signed probe: $(release_phase_guard_signed_nested_probe_command "$env")" >&2
    return
  fi

  release_phase_guard_print_nested_probe_recovery_hint "$env" "$evidence_dir"
}

release_phase_guard_require_supported_nested_probe() {
  local prefix="$1"
  local env="$2"
  local evidence_dir="$3"
  local probe_artifact="$evidence_dir/nested_call_probe.latest.json"

  if ! release_phase_guard_require_metadata "$prefix" "$env" "$probe_artifact" environment; then
    release_phase_guard_print_nested_probe_recovery_hint "$env" "$evidence_dir"
    return 1
  fi
  if ! release_phase_guard_require_current_chain "$prefix" "$evidence_dir" "$probe_artifact" "$env"; then
    release_phase_guard_print_nested_probe_recovery_hint "$env" "$evidence_dir"
    return 1
  fi
  if ! release_phase_guard_require_condition "$prefix" "$env" "$probe_artifact" \
    "nested-call probe must be supported" \
    '.supported == true'; then
    release_phase_guard_print_nested_probe_recovery_hint "$env" "$evidence_dir"
    return 1
  fi
}

release_phase_guard_require_current_nested_probe() {
  local prefix="$1"
  local env="$2"
  local evidence_dir="$3"
  local artifact="$4"
  local probe_artifact="$evidence_dir/nested_call_probe.latest.json"

  release_phase_guard_require_json "$prefix" "$artifact" || return 1
  release_phase_guard_require_supported_nested_probe "$prefix" "$env" "$evidence_dir" || return 1
  if ! jq -e \
    --arg release_env "$env" \
    --slurpfile probe "$probe_artifact" \
    '(.nested_call_probe.generated_at // null) == ($probe[0].generated_at // null)
      and (.nested_call_probe.environment // null) == ($probe[0].environment // null)
      and (.nested_call_probe.environment // null) == $release_env
      and (($probe[0].chain_fingerprint.torii_url // "") | type == "string" and length > 0)
      and ((.nested_call_probe.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
      and (.nested_call_probe.chain_fingerprint.torii_url // null) == ($probe[0].chain_fingerprint.torii_url // null)
      and (.nested_call_probe.chain_fingerprint.chain // null) == ($probe[0].chain_fingerprint.chain // null)
      and (.nested_call_probe.chain_fingerprint.block_1_hash // null) == ($probe[0].chain_fingerprint.block_1_hash // null)
      and (.nested_call_probe.supported // false) == true
      and ($probe[0].supported // false) == true' \
    "$artifact" >/dev/null 2>&1; then
    echo "$prefix: evidence guard failed for ${artifact:t}: must reference current supported nested-call evidence" >&2
    release_phase_guard_print_details "$artifact"
    return 1
  fi
}

release_phase_guard_require_preflight_not_older_than_current_nested_probe() {
  local prefix="$1"
  local env="$2"
  local evidence_dir="$3"
  local preflight_artifact="$4"
  local probe_artifact="$evidence_dir/nested_call_probe.latest.json"

  release_phase_guard_require_metadata "$prefix" "$env" "$probe_artifact" environment || return 1
  if ! jq -e \
    --slurpfile probe "$probe_artifact" \
    '((.generated_at // "") | type == "string" and length > 0)
      and (($probe[0].generated_at // "") | type == "string" and length > 0)
      and (.generated_at >= ($probe[0].generated_at // ""))' \
    "$preflight_artifact" >/dev/null 2>&1; then
    echo "$prefix: evidence guard failed for ${preflight_artifact:t}: preflight must be no older than current nested-call probe" >&2
    release_phase_guard_print_details "$preflight_artifact"
    return 1
  fi
}

release_phase_guard_require_preflight_current_chain() {
  local prefix="$1"
  local env="$2"
  local evidence_dir="$3"
  local preflight_artifact="$4"
  local chain_artifact="$evidence_dir/chain.latest.json"

  release_phase_guard_require_json "$prefix" "$preflight_artifact" || return 1
  release_phase_guard_require_metadata "$prefix" "$env" "$chain_artifact" environment || return 1
  release_phase_guard_require_chain_artifact_fields "$prefix" "$chain_artifact" || return 1
  if ! jq -e \
    --arg release_env "$env" \
    --slurpfile chain "$chain_artifact" \
    '(.chain.fingerprint_available // false) == true
      and (.chain.saved_snapshot_exists // false) == true
      and (.chain.saved_snapshot_matches // false) == true
      and (.chain.saved_snapshot_environment // "") == $release_env
      and ((.chain.fingerprint.torii_url // "") | type == "string" and length > 0)
      and (.chain.fingerprint.torii_url // null) == ($chain[0].torii_url // null)
      and (.chain.fingerprint.chain // null) == ($chain[0].chain // null)
      and (.chain.fingerprint.block_1_hash // null) == ($chain[0].block_1_hash // null)' \
    "$preflight_artifact" >/dev/null 2>&1; then
    echo "$prefix: evidence guard failed for ${preflight_artifact:t}: preflight must match the current saved chain artifact" >&2
    release_phase_guard_print_details "$preflight_artifact"
    return 1
  fi
}

release_phase_guard_require_current_ready_preflight() {
  local prefix="$1"
  local env="$2"
  local evidence_dir="$3"
  local preflight_artifact="${4:-$evidence_dir/preflight.latest.json}"

  release_phase_guard_require_release_ready_preflight_basics "$prefix" "$env" "$evidence_dir" "$preflight_artifact" || return 1
  release_phase_guard_require_condition "$prefix" "$env" "$preflight_artifact" \
    "preflight must reference current saved chain and supported nested-call evidence" \
    '(.chain.saved_snapshot_exists // false) == true
      and (.chain.saved_snapshot_matches // false) == true
      and (.chain.saved_snapshot_environment // "") == $release_env
      and (.nested_call_probe.latest_exists // false) == true
      and (.nested_call_probe.matches_current_chain // false) == true
      and (.nested_call_probe.supported // false) == true' || {
        release_phase_guard_print_preflight_recovery_hint "$env" "$evidence_dir" "$preflight_artifact"
        return 1
      }
  release_phase_guard_require_preflight_current_chain "$prefix" "$env" "$evidence_dir" "$preflight_artifact" || return 1
  release_phase_guard_require_supported_nested_probe "$prefix" "$env" "$evidence_dir" || return 1
  release_phase_guard_require_preflight_not_older_than_current_nested_probe "$prefix" "$env" "$evidence_dir" "$preflight_artifact" || return 1
}

release_phase_guard_require_smoke_readonly_verification() {
  local prefix="$1"
  local env="$2"
  local evidence_dir="$3"
  local artifact="$4"
  local chain_artifact="$evidence_dir/chain.latest.json"
  local contracts_artifact="$evidence_dir/contracts.latest.json"
  local deploy_artifact="$evidence_dir/deploy.latest.json"

  release_phase_guard_require_json "$prefix" "$artifact" || return 1
  release_phase_guard_require_json "$prefix" "$chain_artifact" || return 1
  release_phase_guard_require_json "$prefix" "$contracts_artifact" || return 1
  release_phase_guard_require_json "$prefix" "$deploy_artifact" || return 1
  if ! jq -e \
    --arg release_env "$env" \
    --slurpfile chain "$chain_artifact" \
    --slurpfile contracts "$contracts_artifact" \
    --slurpfile deploy "$deploy_artifact" \
    'def snapshot_matches($snapshot; $current):
        ($snapshot | type) == "object"
        and ($snapshot.generated_at // null) == ($current.generated_at // null)
        and ($snapshot.status // null) == ($current.status // null)
        and ($snapshot.environment // null) == ($current.environment // null)
        and ($snapshot.environment // null) == $release_env
        and (($current.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
        and (($snapshot.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
        and ($snapshot.chain_fingerprint.torii_url // null) == ($current.chain_fingerprint.torii_url // null)
        and ($snapshot.chain_fingerprint.chain // null) == ($current.chain_fingerprint.chain // null)
        and ($snapshot.chain_fingerprint.block_1_hash // null) == ($current.chain_fingerprint.block_1_hash // null);

      (.readonly_verification | type) == "object"
      and ((.readonly_verification.environment // "") == $release_env)
      and (((.readonly_verification.generated_at // "") | length) > 0)
      and ((.readonly_verification.generated_at // "") <= (.generated_at // ""))
      and (($chain[0].torii_url // "") | type == "string" and length > 0)
      and ((.readonly_verification.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
      and (.readonly_verification.chain_fingerprint.torii_url // null) == ($chain[0].torii_url // null)
      and (.readonly_verification.chain_fingerprint.chain // null) == ($chain[0].chain // null)
      and (.readonly_verification.chain_fingerprint.block_1_hash // null) == ($chain[0].block_1_hash // null)
      and snapshot_matches(.readonly_verification.contracts_snapshot; $contracts[0])
      and snapshot_matches(.readonly_verification.deploy_snapshot; $deploy[0])
      and (.readonly_verification.deploy_snapshot.status // null) == ($deploy[0].status // null)' \
    "$artifact" >/dev/null 2>&1; then
    echo "$prefix: evidence guard failed for ${artifact:t}: must embed current readonly smoke verification" >&2
    release_phase_guard_print_details "$artifact"
    return 1
  fi
}

release_phase_guard_require_smoke_perps_liquidation() {
  local prefix="$1"
  local env="$2"
  local artifact="$3"

  release_phase_guard_require_condition "$prefix" "$env" "$artifact" \
    "mutating smoke must prove automatic perps liquidation evidence" \
    'def has_tx($key):
        (.tx_hashes[$key] // "") as $tx
        | (($tx | type) == "string" and ($tx | test("^[0-9a-fA-F]{64}$")));
      def positive_number:
        type == "number" and . > 0;
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
          and ((.view_results.risk_bucket_1_liquidation_liability[3] // null) | positive_number)
        );

      has_tx("perps_liquidation_queue_pass")
      and has_tx("perps_liquidation_recovery_pass")
      and has_tx("perps_liquidation_requeue_pass")
      and has_tx("perps_liquidation_execute_pass")
      and has_tx("perps_pause_trigger_lifecycle")
      and has_tx("perps_restore_trigger_lifecycle")
      and has_liquidated_pass
      and ((.view_results.perps_liquidation_position_state[1] // null) == 4)
      and ((.view_results.perps_liquidation_position_liquidation_state[1] // null) | positive_number)
      and ((.view_results.perps_liquidation_position_liquidation_state[2] // null) | positive_number)
      and ((.view_results.risk_bucket_1_liquidation_liability[3] // null) | positive_number)'
}

release_phase_guard_require_smoke_first_release_mutations() {
  local prefix="$1"
  local env="$2"
  local artifact="$3"

  release_phase_guard_require_condition "$prefix" "$env" "$artifact" \
    "mutating smoke must prove first-release module mutation, state, and risk-vault evidence" \
    'def has_tx($root; $key):
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
        "options_record_shout",
        "options_exercise_shout",
        "options_buy_outperformance",
        "options_settle_outperformance_series",
        "options_exercise_outperformance",
        "cover_register_policy",
        "cover_stale_reset_observation",
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
      and numeric_array($root; "options_shout_series"; 4)
      and numeric_array($root; "options_outperformance_series"; 4)
      and numeric_array($root; "cover_policy_state"; 4)
      and numeric_array($root; "automation_mirror_job"; 4)
      and numeric_array($root; "conditional_escrow_state"; 4)
      and numeric_array($root; "epoch_auction_state"; 4)
      and numeric_array($root; "risk_bucket_1"; 4)
      and numeric_array($root; "risk_bucket_2"; 4)
      and numeric_array($root; "risk_bucket_3"; 4)
      and numeric_array($root; "risk_vault_state"; 4)
      and numeric_array($root; "risk_bucket_1_liability"; 4)
      and numeric_array($root; "risk_bucket_2_shout_liability"; 4)
      and numeric_array($root; "risk_bucket_3_liability"; 4)'
}

release_phase_guard_require_smoke_primitive_mutations() {
  local prefix="$1"
  local env="$2"
  local artifact="$3"
  local rwa_release_enabled_json

  if ! rwa_release_enabled_json="$(release_phase_guard_rwa_release_enabled_json "$env")"; then
    echo "$prefix: evidence guard failed for ${artifact:t}: SORASWAP_ENABLE_RWA_RELEASE must be 0 or 1" >&2
    return 1
  fi
  release_phase_guard_require_json "$prefix" "$artifact" || return 1
  if ! jq -e --arg release_env "$env" --argjson rwa_release_enabled "$rwa_release_enabled_json" \
    '(.release_modes | type) == "object"
      and (.release_modes.rwa | type) == "boolean"
      and .release_modes.rwa == $rwa_release_enabled' \
    "$artifact" >/dev/null 2>&1; then
    echo "$prefix: evidence guard failed for ${artifact:t}: mutating smoke release_modes.rwa must match SORASWAP_ENABLE_RWA_RELEASE" >&2
    release_phase_guard_print_details "$artifact"
    return 1
  fi

  release_phase_guard_require_condition "$prefix" "$env" "$artifact" \
    "mutating smoke must prove 2026 primitive mutation and rejection evidence" \
    'def has_tx($key):
        (.tx_hashes[$key] // "") as $tx
        | (($tx | type) == "string" and ($tx | test("^[0-9a-fA-F]{64}$")));
      def has_no_tx($key):
        (has_tx($key) | not);
      def positive_number:
        type == "number" and . > 0;
      def rwa_release_enabled:
        (.release_modes.rwa // false) == true;
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
      and (if rwa_release_enabled then rwa_completed else rwa_not_launched end)
      and (.view_results.dlmm_hook_quote == [1,20,18,20,19])'
}

release_phase_guard_require_current_chain() {
  local prefix="$1"
  local evidence_dir="$2"
  local artifact="$3"
  local expected_env="${4:-}"
  local chain_artifact="$evidence_dir/chain.latest.json"

  release_phase_guard_require_json "$prefix" "$artifact" || return 1
  if [[ -n "$expected_env" ]]; then
    release_phase_guard_require_metadata "$prefix" "$expected_env" "$chain_artifact" environment || return 1
  else
    release_phase_guard_require_json "$prefix" "$chain_artifact" || return 1
  fi
  release_phase_guard_require_chain_artifact_fields "$prefix" "$chain_artifact" || return 1
  if ! jq -e \
    --arg expected_env "$expected_env" \
    --slurpfile chain "$chain_artifact" \
    '(.chain_fingerprint != null)
      and ((.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
      and (.chain_fingerprint.torii_url // null) == ($chain[0].torii_url // null)
      and (.chain_fingerprint.chain // null) == ($chain[0].chain // null)
      and (.chain_fingerprint.block_1_hash // null) == ($chain[0].block_1_hash // null)
      and ($expected_env == "" or (($chain[0].environment // "") == $expected_env))' \
    "$artifact" >/dev/null 2>&1; then
    echo "$prefix: evidence guard failed for ${artifact:t}: must match current chain fingerprint and selected environment" >&2
    release_phase_guard_print_details "$artifact"
    return 1
  fi
}

release_phase_guard_require_current_chain_evidence() {
  local prefix="$1"
  local env="$2"
  local evidence_dir="$3"
  local artifact="$4"

  release_phase_guard_require_current_chain "$prefix" "$evidence_dir" "$artifact" "$env"
}

release_phase_guard_require_not_older_than_current_preflight() {
  local prefix="$1"
  local env="$2"
  local evidence_dir="$3"
  local artifact="$4"
  local preflight_artifact="$evidence_dir/preflight.latest.json"

  release_phase_guard_require_json "$prefix" "$artifact" || return 1
  release_phase_guard_require_current_ready_preflight "$prefix" "$env" "$evidence_dir" "$preflight_artifact" || return 1
  if ! jq -e \
    --slurpfile preflight "$preflight_artifact" \
    '(($preflight[0].generated_at // "") | type == "string" and length > 0)
      and ((.generated_at // "") | type == "string" and length > 0)
      and (.generated_at >= ($preflight[0].generated_at // ""))' \
    "$artifact" >/dev/null 2>&1; then
    echo "$prefix: evidence guard failed for ${artifact:t}: must be recorded no older than the current ready preflight" >&2
    release_phase_guard_print_details "$artifact"
    return 1
  fi
}

release_phase_guard_require_contracts_not_older_than_deploy() {
  local prefix="$1"
  local evidence_dir="$2"
  local contracts_artifact="$evidence_dir/contracts.latest.json"
  local deploy_artifact="$evidence_dir/deploy.latest.json"

  release_phase_guard_require_json "$prefix" "$contracts_artifact" || return 1
  release_phase_guard_require_json "$prefix" "$deploy_artifact" || return 1
  if ! jq -e \
    --slurpfile deploy "$deploy_artifact" \
    '((.generated_at // "") | type == "string" and length > 0)
      and (($deploy[0].generated_at // "") | type == "string" and length > 0)
      and (.generated_at >= ($deploy[0].generated_at // ""))' \
    "$contracts_artifact" >/dev/null 2>&1; then
    echo "$prefix: evidence guard failed for ${contracts_artifact:t}: contracts snapshot must be no older than deploy report" >&2
    release_phase_guard_print_details "$contracts_artifact"
    return 1
  fi
}

release_phase_guard_require_deploy_snapshot_current_contracts() {
  local prefix="$1"
  local evidence_dir="$2"
  local contracts_artifact="$evidence_dir/contracts.latest.json"
  local deploy_artifact="$evidence_dir/deploy.latest.json"

  release_phase_guard_require_json "$prefix" "$contracts_artifact" || return 1
  release_phase_guard_require_json "$prefix" "$deploy_artifact" || return 1
  if ! jq -n -e \
    --slurpfile contracts "$contracts_artifact" \
    --slurpfile deploy "$deploy_artifact" \
    '
      def current_contract_snapshot_path($snapshot; $contracts_generated):
        ($snapshot | type) == "string"
        and ("contracts." + $contracts_generated + ".json") as $contracts_file
        | ($snapshot == $contracts_file or ($snapshot | endswith("/" + $contracts_file)));

      ($contracts[0].generated_at // "") as $contracts_generated
      | (($contracts_generated | type) == "string" and ($contracts_generated | length) > 0)
        and current_contract_snapshot_path(($deploy[0].phases.deployment_records_snapshot.detail.snapshot // ""); $contracts_generated)
    ' >/dev/null 2>&1; then
    echo "$prefix: evidence guard failed for ${deploy_artifact:t}: deployment-record snapshot detail must reference current contracts snapshot" >&2
    release_phase_guard_print_details "$deploy_artifact"
    return 1
  fi
}

release_phase_guard_require_completed_deploy_phases() {
  local prefix="$1"
  local env="$2"
  local artifact="$3"

  release_phase_guard_require_condition "$prefix" "$env" "$artifact" \
    "deploy report must complete all required release phases and prove signer readiness without debug bypass" \
    '(.phases.preflight.status == "completed")
      and (.phases.compile.status == "completed")
      and (.phases.nested_call_probe.status == "completed")
      and (.phases.deploy.status == "completed")
      and (.phases.bootstrap_contract_state.status == "completed")
      and (.phases.deployment_records_snapshot.status == "completed")
      and ((.phases.preflight.detail.signer_ready_check.status // "") == "completed")
      and ((.phases.preflight.detail.signer_ready_check.debug_bypass_env // null) == null)'
}

release_phase_guard_require_deployment_records_proof() {
  local prefix="$1"
  local env="$2"
  local evidence_dir="$3"
  local contracts_artifact="$evidence_dir/contracts.latest.json"
  local contract_count contract_entry contract_key expected_address expected_nonce
  local expected_code_hash expected_abi_hash manifest_code_hash manifest_abi_hash
  local record_path manifest_path
  local record_key
  local manifest_key
  local expected_contract_key expected_evidence_dir
  typeset -A contract_snapshot_key_map
  typeset -A contract_snapshot_key_count
  typeset -A expected_contract_key_map

  release_phase_guard_require_json "$prefix" "$contracts_artifact" || return 1
  contract_count="$(jq -r '(.contracts // []) | length' "$contracts_artifact" 2>/dev/null || echo 0)"
  if [[ "$contract_count" == "0" ]]; then
    echo "$prefix: evidence guard failed for ${contracts_artifact:t}: contracts snapshot must include deployed contracts" >&2
    release_phase_guard_print_details "$contracts_artifact"
    return 1
  fi

  while IFS= read -r contract_key; do
    [[ -n "$contract_key" ]] || continue
    contract_snapshot_key_map[$contract_key]=1
    contract_snapshot_key_count[$contract_key]=$(( ${contract_snapshot_key_count[$contract_key]:-0} + 1 ))
  done < <(jq -r '(.contracts // [])[]? | select(type == "object") | (.contract_key? // .name? // empty)' "$contracts_artifact")

  for contract_key in "${(@ko)contract_snapshot_key_count}"; do
    if (( ${contract_snapshot_key_count[$contract_key]:-0} > 1 )); then
      echo "$prefix: evidence guard failed for ${contracts_artifact:t}: duplicate contract snapshot for $contract_key" >&2
      release_phase_guard_print_details "$contracts_artifact"
      return 1
    fi
  done

  while IFS= read -r contract_key; do
    [[ -n "$contract_key" ]] || continue
    if ! jq -e --arg key "$contract_key" --arg release_env "$env" '
      any((.contracts // [])[]?;
        ((.contract_key? // .name? // empty) == $key)
        and ((.environment // "") == $release_env)
      )
    ' "$contracts_artifact" >/dev/null 2>&1; then
      echo "$prefix: evidence guard failed for ${contracts_artifact:t}: contract snapshot entry must record selected environment for $contract_key" >&2
      release_phase_guard_print_details "$contracts_artifact"
      return 1
    fi
  done < <(jq -r '(.contracts // [])[]? | select(type == "object") | (.contract_key? // .name? // empty)' "$contracts_artifact")

  if (( $+functions[expected_contract_ids] )) && (( $+functions[deployments_dir_for_env] )); then
    expected_evidence_dir="$(deployments_dir_for_env "$env")"
    if [[ "${evidence_dir:A}" == "${expected_evidence_dir:A}" ]]; then
      while IFS= read -r expected_contract_key; do
        [[ -n "$expected_contract_key" ]] || continue
        expected_contract_key_map[$expected_contract_key]=1
      done < <(expected_contract_ids)

      for expected_contract_key in "${(@k)expected_contract_key_map}"; do
        if [[ -z "${contract_snapshot_key_map[$expected_contract_key]:-}" ]]; then
          echo "$prefix: evidence guard failed for ${contracts_artifact:t}: missing required contract snapshot for $expected_contract_key" >&2
          release_phase_guard_print_details "$contracts_artifact"
          return 1
        fi
      done

      for contract_key in "${(@k)contract_snapshot_key_map}"; do
        if [[ -z "${expected_contract_key_map[$contract_key]:-}" ]]; then
          echo "$prefix: evidence guard failed for ${contracts_artifact:t}: stale or unknown contract snapshot for $contract_key" >&2
          release_phase_guard_print_details "$contracts_artifact"
          return 1
        fi
      done
    fi
  fi

  while IFS= read -r contract_entry; do
    contract_key="$(jq -r '.contract_key? // .name? // empty' <<<"$contract_entry")"
    expected_address="$(jq -r '.contract_address // .instance.contract_address // .instance.contract_id // empty' <<<"$contract_entry")"
    expected_nonce="$(jq -r '(.deploy_nonce // .instance.deploy_nonce // empty) | tostring' <<<"$contract_entry")"
    expected_code_hash="$(jq -r '(.code_hash_hex // .code_hash // .instance.code_hash_hex // "") | ascii_downcase | sub("^0x"; "")' <<<"$contract_entry")"
    expected_abi_hash="$(jq -r '(.abi_hash_hex // .abi_hash // .instance.abi_hash_hex // "") | ascii_downcase | sub("^0x"; "")' <<<"$contract_entry")"
    if [[ -z "$contract_key" || -z "$expected_address" || -z "$expected_nonce" || "$expected_nonce" == "null" \
      || -z "$expected_code_hash" || "$expected_code_hash" == "null" \
      || -z "$expected_abi_hash" || "$expected_abi_hash" == "null" ]]; then
      echo "$prefix: evidence guard failed for ${contracts_artifact:t}: contract snapshot entries must include contract_key, address, deploy nonce, code hash, and ABI hash" >&2
      release_phase_guard_print_details "$contracts_artifact"
      return 1
    fi

    record_path="$evidence_dir/${contract_key}.deploy.json"
    manifest_path="$evidence_dir/${contract_key}.manifest.json"
    release_phase_guard_require_metadata "$prefix" "$env" "$record_path" environment || return 1
    release_phase_guard_require_current_chain "$prefix" "$evidence_dir" "$record_path" "$env" || return 1
    release_phase_guard_require_json "$prefix" "$manifest_path" || return 1
    release_phase_guard_require_metadata "$prefix" "$env" "$manifest_path" environment || return 1
    if ! jq -e --arg key "$contract_key" '.contract_key == $key' "$manifest_path" >/dev/null 2>&1; then
      echo "$prefix: evidence guard failed for ${manifest_path:t}: manifest contract_key must match filename" >&2
      release_phase_guard_print_details "$manifest_path"
      return 1
    fi
    manifest_code_hash="$(release_phase_guard_manifest_hash "$manifest_path" code_hash)"
    manifest_abi_hash="$(release_phase_guard_manifest_hash "$manifest_path" abi_hash)"
    if [[ "$manifest_code_hash" != "$expected_code_hash" || "$manifest_abi_hash" != "$expected_abi_hash" ]]; then
      echo "$prefix: evidence guard failed for ${manifest_path:t}: manifest hashes must match current contracts snapshot" >&2
      release_phase_guard_print_details "$manifest_path"
      return 1
    fi
    if ! jq -e \
      --arg key "$contract_key" \
      --arg expected_address "$expected_address" \
      --arg expected_nonce "$expected_nonce" \
      --arg expected_code_hash "$expected_code_hash" \
      --arg expected_abi_hash "$expected_abi_hash" \
      '
        (.contract_key // "") == $key
        and ((.code_hash_hex // "") | ascii_downcase | sub("^0x"; "")) == $expected_code_hash
        and ((.abi_hash_hex // "") | ascii_downcase | sub("^0x"; "")) == $expected_abi_hash
        and (.response.ok // false) == true
        and ((.response.contract_address // .response.contract_id // "") == $expected_address)
        and (((.response.deploy_nonce // null) | tostring) == $expected_nonce)
        and ((.response.code_hash_hex // "") | ascii_downcase | sub("^0x"; "")) == $expected_code_hash
        and ((.response.abi_hash_hex // "") | ascii_downcase | sub("^0x"; "")) == $expected_abi_hash
        and ((.instance.contract_address // .instance.contract_id // "") == $expected_address)
        and (((.instance.deploy_nonce // null) | tostring) == $expected_nonce)
        and ((.instance.code_hash_hex // "") | ascii_downcase | sub("^0x"; "")) == $expected_code_hash
        and ((.instance.abi_hash_hex // "") | ascii_downcase | sub("^0x"; "")) == $expected_abi_hash
        and (
          (.deploy_strategy // "") != "bundle"
          or (
            (.bundle_receipt.status // "") == "deployed"
            and ((.bundle_receipt.name // .bundle_receipt.contract_key // "") == $key)
            and ((.bundle_receipt.contract_address // "") == $expected_address)
            and (((.bundle_receipt.deploy_nonce // null) | tostring) == $expected_nonce)
            and ((.bundle_receipt.code_hash_hex // "") | ascii_downcase | sub("^0x"; "")) == $expected_code_hash
            and ((.bundle_receipt.abi_hash_hex // "") | ascii_downcase | sub("^0x"; "")) == $expected_abi_hash
          )
        )
      ' "$record_path" >/dev/null 2>&1; then
      echo "$prefix: evidence guard failed for ${record_path:t}: deploy record must include successful response, instance, bundle receipt, and code/ABI hash evidence" >&2
      release_phase_guard_print_details "$record_path"
      return 1
    fi
  done < <(jq -c '(.contracts // [])[]? | select(type == "object")' "$contracts_artifact")

  for record_path in "$evidence_dir"/*.deploy.json(N); do
    if [[ "${record_path:t}" == "soraswap.bundle.deploy.json" \
      || "${record_path:t}" == "soraswap.foundation.bundle.deploy.json" ]]; then
      continue
    fi
    release_phase_guard_require_json "$prefix" "$record_path" || return 1
    record_key="$(jq -r '.contract_key // empty' "$record_path" 2>/dev/null || true)"
    if [[ -z "$record_key" ]]; then
      echo "$prefix: evidence guard failed for ${record_path:t}: deploy record must identify contract_key" >&2
      release_phase_guard_print_details "$record_path"
      return 1
    fi
    if [[ -z "${contract_snapshot_key_map[$record_key]:-}" ]]; then
      echo "$prefix: evidence guard failed for ${record_path:t}: stale or unknown deploy record for current contracts snapshot" >&2
      release_phase_guard_print_details "$record_path"
      return 1
    fi
  done

  for manifest_path in "$evidence_dir"/*.manifest.json(N); do
    manifest_key="${manifest_path:t}"
    manifest_key="${manifest_key%.manifest.json}"
    if [[ -z "$manifest_key" ]]; then
      echo "$prefix: evidence guard failed for ${manifest_path:t}: manifest must identify contract_key" >&2
      release_phase_guard_print_details "$manifest_path"
      return 1
    fi
    if [[ -z "${contract_snapshot_key_map[$manifest_key]:-}" ]]; then
      echo "$prefix: evidence guard failed for ${manifest_path:t}: stale or unknown manifest for current contracts snapshot" >&2
      release_phase_guard_print_details "$manifest_path"
      return 1
    fi
    release_phase_guard_require_metadata "$prefix" "$env" "$manifest_path" environment || return 1
    if ! jq -e --arg key "$manifest_key" '.contract_key == $key' "$manifest_path" >/dev/null 2>&1; then
      echo "$prefix: evidence guard failed for ${manifest_path:t}: manifest contract_key must match filename" >&2
      release_phase_guard_print_details "$manifest_path"
      return 1
    fi
  done
}

release_phase_guard_require_bundle_receipt_proof() {
  local prefix="$1"
  local env="$2"
  local evidence_dir="$3"
  local contracts_artifact="$evidence_dir/contracts.latest.json"
  local chain_artifact="$evidence_dir/chain.latest.json"
  local receipt_artifact="$evidence_dir/soraswap.bundle.deploy.json"

  [[ -e "$receipt_artifact" ]] || return 0

  release_phase_guard_require_metadata "$prefix" "$env" "$receipt_artifact" environment || return 1
  release_phase_guard_require_json "$prefix" "$chain_artifact" || return 1
  release_phase_guard_require_json "$prefix" "$contracts_artifact" || return 1
  if ! jq -n -e \
    --arg release_env "$env" \
    --slurpfile receipt "$receipt_artifact" \
    --slurpfile chain "$chain_artifact" \
    --slurpfile contracts "$contracts_artifact" \
    '
      def key_of:
        .contract_key? // .name? // "";
      def hash_norm:
        tostring | sub("^hash:"; "") | sub("^0x"; "") | ascii_downcase;
      def contract_key_set($items):
        [($items // [])[]? | select(type == "object") | key_of | select(length > 0)] | sort;
      def field_address($item):
        $item.contract_address // $item.instance.contract_address // $item.instance.contract_id // "";
      def field_nonce($item):
        ($item.deploy_nonce // $item.instance.deploy_nonce // null) | tostring;
      def field_code_hash($item):
        ($item.code_hash_hex // $item.code_hash // $item.instance.code_hash_hex // "") | hash_norm;
      def field_abi_hash($item):
        ($item.abi_hash_hex // $item.abi_hash // $item.instance.abi_hash_hex // "") | hash_norm;

      $receipt[0] as $bundle
      | $contracts[0] as $snapshot
      | ($snapshot.contracts // []) as $snapshot_contracts
      | ($bundle.contracts // []) as $bundle_contracts
      | ($bundle.ok == true)
        and (($bundle.generated_at // "") | type == "string" and length > 0)
        and (($bundle.environment // "") == $release_env)
        and (($bundle.chain_fingerprint.torii_url // "") == ($chain[0].torii_url // ""))
        and (($bundle.chain_fingerprint.chain // "") == ($chain[0].chain // ""))
        and (($bundle.chain_fingerprint.block_1_hash // "") == ($chain[0].block_1_hash // ""))
        and (($bundle_contracts | type) == "array")
        and (($bundle_contracts | length) > 0)
        and (contract_key_set($bundle_contracts) == contract_key_set($snapshot_contracts))
        and all($snapshot_contracts[]?;
          . as $expected
          | (key_of) as $key
          | [$bundle_contracts[]? | select(key_of == $key)] as $matches
          | ($matches | length) == 1
            and (($matches[0].status // "") == "deployed")
            and (field_address($matches[0]) == field_address($expected))
            and (field_nonce($matches[0]) == field_nonce($expected))
            and (field_code_hash($matches[0]) == field_code_hash($expected))
            and (field_abi_hash($matches[0]) == field_abi_hash($expected))
        )
    ' >/dev/null 2>&1; then
    echo "$prefix: evidence guard failed for ${receipt_artifact:t}: bundle receipt must match current chain and contracts snapshot" >&2
    release_phase_guard_print_details "$receipt_artifact"
    return 1
  fi
}

release_phase_guard_require_rwa_external_refs() {
  local prefix="$1"
  local env="$2"
  local artifact="$3"

  release_phase_guard_require_condition "$prefix" "$env" "$artifact" \
    "RWA compliance evidence must include control-character-free, non-placeholder, non-local/wildcard, non-reserved-domain external references" \
    'def trim_ref:
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
      ((.issuer_approval_ref // "") | valid_external_ref)
      and ((.legal_review_ref // "") | valid_external_ref)
      and ((.compliance_policy_ref // "") | valid_external_ref)
      and ((.nav_source_ref // "") | valid_external_ref)
	      and ((.redemption_terms_ref // "") | valid_external_ref)'
}

release_phase_guard_require_redacted_rwa_notes() {
  local prefix="$1"
  local artifact="$2"
  local notes redacted_notes

  release_phase_guard_require_json "$prefix" "$artifact" || return 1
  notes="$(jq -r '.notes // empty' "$artifact" 2>/dev/null || true)"
  [[ -z "$notes" ]] && return 0

  redacted_notes="$(release_phase_guard_redact_text "$notes")"
  if [[ "$notes" != "$redacted_notes" ]]; then
    echo "$prefix: evidence guard failed for ${artifact:t}: RWA compliance notes must be redacted; rerun the evidence with current redaction helpers" >&2
    release_phase_guard_print_details "$artifact"
    return 1
  fi
}

release_phase_guard_require_trader_api_cid_probe() {
  local prefix="$1"
  local env="$2"
  local artifact="$3"

  release_phase_guard_require_condition "$prefix" "$env" "$artifact" \
    "trader API CID probe must prove the exact published content CID" \
    'def positive_count:
        type == "number" and . > 0 and . == floor;
      def nonnegative_count:
        type == "number" and . >= 0 and . == floor;

      (.content_cid // "") as $cid
      | (($cid | test("^b[a-z2-7]+$"))
        and ((.manifest_digest_hex // "") | test("^[0-9a-fA-F]{64}$"))
        and ((.cid_probe.attempt_count // null) | positive_count)
        and ((.cid_probe.success_count // null) | nonnegative_count)
        and ((.cid_probe.manifest_match_count // null) | nonnegative_count)
        and (.cid_probe.success_count == .cid_probe.attempt_count)
        and (.cid_probe.manifest_match_count == .cid_probe.attempt_count)
        and ((.cid_probe.url // "") | endswith("/v1/app-api/cid/" + $cid)))'
}

release_phase_guard_require_trader_api_routes() {
  local prefix="$1"
  local env="$2"
  local artifact="$3"

  release_phase_guard_require_condition "$prefix" "$env" "$artifact" \
    "trader API bundle must expose and serve the exact required route manifest" \
    'def has_route($routes; $method; $path; $adapter):
        any(($routes // [])[];
          (.method // "") == $method
          and (.path // "") == $path
          and (.adapter // "") == $adapter
        );

      def has_required_routes($routes):
        (($routes // []) | length) == 11
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
        and has_required_routes(.routes // [])
        and (($parsed.schema_version // 0) == 1)
        and (($parsed.app_id // "") == (.app_id // ""))
        and (($parsed.content_cid // "") == (.content_cid // ""))
        and (($parsed.manifest_digest_hex // "") == (.manifest_digest_hex // ""))
        and has_required_routes($parsed.routes // [])'
}

release_phase_guard_require_trader_api_receipts() {
  local prefix="$1"
  local env="$2"
  local artifact="$3"

  release_phase_guard_require_condition "$prefix" "$env" "$artifact" \
    "trader API bundle must include matching SoraFS pin and registry receipts" \
    '((.pin_summary.manifest_id_hex // "") | test("^[0-9a-fA-F]+$"))
      and ((.manifest_id_hex // "") == (.pin_summary.manifest_id_hex // ""))
      and ((.pin_summary.manifest_digest_hex // "") == (.manifest_digest_hex // ""))
      and (((.pin_summary.status // "") | tostring) | test("^(200|201|202|204|409)$"))
      and ((.registry_submit.manifest_digest_hex // "") == (.manifest_digest_hex // ""))
      and (((.registry_submit.status // "") | tostring) | test("^2"))'
}

release_phase_guard_require_trader_api_content_cid() {
  local prefix="$1"
  local env="$2"
  local artifact="$3"
  local manifest_id_hex actual_cid expected_cid

  release_phase_guard_require_json "$prefix" "$artifact" || return 1
  manifest_id_hex="$(jq -r '.pin_summary.manifest_id_hex // empty' "$artifact" 2>/dev/null || true)"
  actual_cid="$(jq -r '.content_cid // empty' "$artifact" 2>/dev/null || true)"
  expected_cid="$(release_phase_guard_content_cid_from_hex "$manifest_id_hex" 2>/dev/null || true)"
  if [[ -z "$expected_cid" || "$actual_cid" != "$expected_cid" ]]; then
    echo "$prefix: evidence guard failed for ${artifact:t}: content_cid must match the pinned SoraFS manifest id" >&2
    release_phase_guard_print_details "$artifact"
    return 1
  fi
}

release_phase_guard_require_trader_readonly_routes() {
  local prefix="$1"
  local env="$2"
  local artifact="$3"

  release_phase_guard_require_condition "$prefix" "$env" "$artifact" \
    "trader readonly must prove all required trader routes returned HTTP 200 with required query parameters" \
    'def required_route_keys:
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
      and all_required_routes_ok(.route_probes.required_before // {})'
}

release_phase_guard_require_trader_mutating_routes() {
  local prefix="$1"
  local env="$2"
  local artifact="$3"

  release_phase_guard_require_condition "$prefix" "$env" "$artifact" \
    "trader smoke must prove required trader routes before and after mutation with required query parameters" \
    'def required_route_keys:
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
      and all_required_routes_ok(.route_probes.required_after // {})'
}

release_phase_guard_require_trader_mutation_swap() {
  local prefix="$1"
  local env="$2"
  local artifact="$3"

  release_phase_guard_require_condition "$prefix" "$env" "$artifact" \
    "trader smoke must prove signed route_swap with balance deltas" \
    'def tx_hash_hex:
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
      and ($usdt_after > $usdt_before)'
}

release_phase_guard_require_contract_console_outcome() {
  local prefix="$1"
  local env="$2"
  local artifact="$3"

  release_phase_guard_require_condition "$prefix" "$env" "$artifact" \
    "contract-console smoke must prove a governed bridge route and valid submission outcome" \
    '(.bridge.route_provenance[0] // 0) == 1
      and (.bridge.submission_expectation // "") == "apply"
      and ((.submissions.proof_status.status_kind // "") | test("^(Applied|Committed)$"))
      and ((.submissions.message_status.status_kind // "") | test("^(Applied|Committed)$"))'
}

release_phase_guard_verify_target() {
  local prefix="$1"
  local env="$2"
  local evidence_dir="$3"
  local target="$4"
  local rwa_release_enabled_json

  case "$target" in
    *-preflight|record-*-rwa-compliance|*-nested-call-probe|deploy-*|smoke-*-trader-readonly|smoke-*-trader|smoke-*-readonly|smoke-testnet|smoke-production|test-contract-console-*|publish-*trader-api)
      release_phase_guard_require_migration_register "$prefix" "$evidence_dir" || return 1
      ;;
  esac

  case "$target" in
    *-preflight)
      release_phase_guard_require_release_ready_preflight_basics "$prefix" "$env" "$evidence_dir" "$evidence_dir/preflight.latest.json" || return 1
      if [[ "${SORASWAP_PREFLIGHT_SKIP_EXISTING_NESTED_PROBE_CHECK:-0}" != "1" ]]; then
        release_phase_guard_require_condition "$prefix" "$env" "$evidence_dir/preflight.latest.json" \
          "preflight must reference current saved chain and supported nested-call evidence" \
          '(.chain.saved_snapshot_exists // false) == true
            and (.chain.saved_snapshot_matches // false) == true
            and (.chain.saved_snapshot_environment // "") == $release_env
            and (.nested_call_probe.latest_exists // false) == true
            and (.nested_call_probe.matches_current_chain // false) == true
            and (.nested_call_probe.supported // false) == true' || {
              release_phase_guard_print_preflight_recovery_hint "$env" "$evidence_dir" "$evidence_dir/preflight.latest.json"
              return 1
            }
        release_phase_guard_require_preflight_current_chain "$prefix" "$env" "$evidence_dir" "$evidence_dir/preflight.latest.json" || return 1
        release_phase_guard_require_supported_nested_probe "$prefix" "$env" "$evidence_dir" || return 1
        release_phase_guard_require_preflight_not_older_than_current_nested_probe "$prefix" "$env" "$evidence_dir" "$evidence_dir/preflight.latest.json" || return 1
      fi
      ;;
    record-*-rwa-compliance)
      release_phase_guard_require_metadata "$prefix" "$env" "$evidence_dir/rwa_compliance.latest.json" environment || return 1
      release_phase_guard_require_current_chain_evidence "$prefix" "$env" "$evidence_dir" "$evidence_dir/rwa_compliance.latest.json" || return 1
      release_phase_guard_require_not_older_than_current_preflight "$prefix" "$env" "$evidence_dir" "$evidence_dir/rwa_compliance.latest.json" || return 1
      if ! rwa_release_enabled_json="$(release_phase_guard_rwa_release_enabled_json "$env")"; then
        echo "$prefix: evidence guard failed for rwa_compliance.latest.json: SORASWAP_ENABLE_RWA_RELEASE must be 0 or 1" >&2
        return 1
      fi
      release_phase_guard_require_json "$prefix" "$evidence_dir/rwa_compliance.latest.json" || return 1
      if ! jq -e --arg release_env "$env" --argjson rwa_release_enabled "$rwa_release_enabled_json" \
        'if $rwa_release_enabled then
          .status == "completed"
        else
          .status == "not_applicable"
          and .rwa_release_enabled == false
          and ((.reason // "") | type == "string" and length > 0)
        end' \
        "$evidence_dir/rwa_compliance.latest.json" >/dev/null 2>&1; then
        echo "$prefix: evidence guard failed for rwa_compliance.latest.json: RWA compliance status must match SORASWAP_ENABLE_RWA_RELEASE mode" >&2
        release_phase_guard_print_details "$evidence_dir/rwa_compliance.latest.json"
        return 1
      fi
      if jq -e '.status == "completed"' "$evidence_dir/rwa_compliance.latest.json" >/dev/null 2>&1; then
        release_phase_guard_require_rwa_external_refs "$prefix" "$env" "$evidence_dir/rwa_compliance.latest.json" || return 1
      fi
      release_phase_guard_require_redacted_rwa_notes "$prefix" "$evidence_dir/rwa_compliance.latest.json" || return 1
      release_phase_guard_require_no_sensitive_diagnostic_leaks "$prefix" "$evidence_dir/rwa_compliance.latest.json" || return 1
      ;;
    *-nested-call-probe)
      release_phase_guard_require_metadata "$prefix" "$env" "$evidence_dir/chain.latest.json" environment || return 1
      release_phase_guard_require_supported_nested_probe "$prefix" "$env" "$evidence_dir" || return 1
      ;;
    deploy-*)
      release_phase_guard_require_metadata "$prefix" "$env" "$evidence_dir/deploy.latest.json" environment || return 1
      release_phase_guard_require_metadata "$prefix" "$env" "$evidence_dir/contracts.latest.json" environment || return 1
      release_phase_guard_require_current_chain "$prefix" "$evidence_dir" "$evidence_dir/deploy.latest.json" "$env" || return 1
      release_phase_guard_require_current_chain "$prefix" "$evidence_dir" "$evidence_dir/contracts.latest.json" "$env" || return 1
      release_phase_guard_require_not_older_than_current_preflight "$prefix" "$env" "$evidence_dir" "$evidence_dir/deploy.latest.json" || return 1
      release_phase_guard_require_not_older_than_current_preflight "$prefix" "$env" "$evidence_dir" "$evidence_dir/contracts.latest.json" || return 1
      release_phase_guard_require_contracts_not_older_than_deploy "$prefix" "$evidence_dir" || return 1
      release_phase_guard_require_condition "$prefix" "$env" "$evidence_dir/deploy.latest.json" \
        "deploy status must be completed" \
        '.status == "completed"' || return 1
      release_phase_guard_require_condition "$prefix" "$env" "$evidence_dir/contracts.latest.json" \
        "contracts snapshot status must be completed" \
        '.status == "completed"' || return 1
      release_phase_guard_require_completed_deploy_phases "$prefix" "$env" "$evidence_dir/deploy.latest.json" || return 1
      release_phase_guard_require_deploy_snapshot_current_contracts "$prefix" "$evidence_dir" || return 1
      release_phase_guard_require_deployment_records_proof "$prefix" "$env" "$evidence_dir" || return 1
      release_phase_guard_require_bundle_receipt_proof "$prefix" "$env" "$evidence_dir" || return 1
      ;;
    smoke-*-trader-readonly)
      release_phase_guard_require_current_ready_preflight "$prefix" "$env" "$evidence_dir" || return 1
      release_phase_guard_require_metadata "$prefix" "$env" "$evidence_dir/trader_readonly.latest.json" environment || return 1
      release_phase_guard_require_current_chain "$prefix" "$evidence_dir" "$evidence_dir/trader_readonly.latest.json" "$env" || return 1
      release_phase_guard_require_current_snapshots "$prefix" "$env" "$evidence_dir" "$evidence_dir/trader_readonly.latest.json" || return 1
      release_phase_guard_require_not_older_than_current_snapshots "$prefix" "$evidence_dir" "$evidence_dir/trader_readonly.latest.json" || return 1
      release_phase_guard_require_condition "$prefix" "$env" "$evidence_dir/trader_readonly.latest.json" \
        "trader readonly status must be completed" \
        '.status == "completed"' || return 1
      release_phase_guard_require_trader_readonly_routes "$prefix" "$env" "$evidence_dir/trader_readonly.latest.json" || return 1
      release_phase_guard_require_snapshot_check_completed "$prefix" "$env" "$evidence_dir/trader_readonly.latest.json" || return 1
      ;;
    smoke-*-trader)
      release_phase_guard_require_current_ready_preflight "$prefix" "$env" "$evidence_dir" || return 1
      release_phase_guard_require_metadata "$prefix" "$env" "$evidence_dir/trader.latest.json" environment || return 1
      release_phase_guard_require_current_chain "$prefix" "$evidence_dir" "$evidence_dir/trader.latest.json" "$env" || return 1
      release_phase_guard_require_current_snapshots "$prefix" "$env" "$evidence_dir" "$evidence_dir/trader.latest.json" || return 1
      release_phase_guard_require_not_older_than_current_snapshots "$prefix" "$evidence_dir" "$evidence_dir/trader.latest.json" || return 1
      release_phase_guard_require_condition "$prefix" "$env" "$evidence_dir/trader.latest.json" \
        "trader smoke status must be completed" \
        '.status == "completed"' || return 1
      release_phase_guard_require_trader_mutating_routes "$prefix" "$env" "$evidence_dir/trader.latest.json" || return 1
      release_phase_guard_require_trader_mutation_swap "$prefix" "$env" "$evidence_dir/trader.latest.json" || return 1
      release_phase_guard_require_snapshot_check_completed "$prefix" "$env" "$evidence_dir/trader.latest.json" || return 1
      ;;
    smoke-*-readonly)
      release_phase_guard_require_current_ready_preflight "$prefix" "$env" "$evidence_dir" || return 1
      release_phase_guard_require_metadata "$prefix" "$env" "$evidence_dir/smoke.latest.json" environment || return 1
      release_phase_guard_require_current_chain "$prefix" "$evidence_dir" "$evidence_dir/smoke.latest.json" "$env" || return 1
      release_phase_guard_require_current_snapshots "$prefix" "$env" "$evidence_dir" "$evidence_dir/smoke.latest.json" || return 1
      release_phase_guard_require_not_older_than_current_snapshots "$prefix" "$evidence_dir" "$evidence_dir/smoke.latest.json" || return 1
      release_phase_guard_require_condition "$prefix" "$env" "$evidence_dir/smoke.latest.json" \
        "readonly smoke status must be completed" \
        '.status == "completed"' || return 1
      release_phase_guard_require_snapshot_check_completed "$prefix" "$env" "$evidence_dir/smoke.latest.json" || return 1
      ;;
    smoke-testnet|smoke-production)
      release_phase_guard_require_current_ready_preflight "$prefix" "$env" "$evidence_dir" || return 1
      release_phase_guard_require_metadata "$prefix" "$env" "$evidence_dir/smoke.latest.json" environment || return 1
      release_phase_guard_require_current_chain "$prefix" "$evidence_dir" "$evidence_dir/smoke.latest.json" "$env" || return 1
      release_phase_guard_require_current_snapshots "$prefix" "$env" "$evidence_dir" "$evidence_dir/smoke.latest.json" || return 1
      release_phase_guard_require_not_older_than_current_snapshots "$prefix" "$evidence_dir" "$evidence_dir/smoke.latest.json" || return 1
      release_phase_guard_require_condition "$prefix" "$env" "$evidence_dir/smoke.latest.json" \
        "mutating smoke status must be completed" \
        '.status == "completed"' || return 1
      release_phase_guard_require_condition "$prefix" "$env" "$evidence_dir/smoke.latest.json" \
        "mutating smoke must reference supported nested-call evidence" \
        '(.nested_call_probe.supported // false) == true' || return 1
      release_phase_guard_require_current_nested_probe "$prefix" "$env" "$evidence_dir" "$evidence_dir/smoke.latest.json" || return 1
      release_phase_guard_require_smoke_readonly_verification "$prefix" "$env" "$evidence_dir" "$evidence_dir/smoke.latest.json" || return 1
      release_phase_guard_require_smoke_perps_liquidation "$prefix" "$env" "$evidence_dir/smoke.latest.json" || return 1
      release_phase_guard_require_smoke_primitive_mutations "$prefix" "$env" "$evidence_dir/smoke.latest.json" || return 1
      release_phase_guard_require_smoke_first_release_mutations "$prefix" "$env" "$evidence_dir/smoke.latest.json" || return 1
      release_phase_guard_require_snapshot_check_completed "$prefix" "$env" "$evidence_dir/smoke.latest.json" || return 1
      ;;
    test-contract-console-*)
      release_phase_guard_require_current_ready_preflight "$prefix" "$env" "$evidence_dir" || return 1
      release_phase_guard_require_metadata "$prefix" "$env" "$evidence_dir/contract_console_smoke.latest.json" environment || return 1
      release_phase_guard_require_current_chain "$prefix" "$evidence_dir" "$evidence_dir/contract_console_smoke.latest.json" "$env" || return 1
      release_phase_guard_require_current_snapshots "$prefix" "$env" "$evidence_dir" "$evidence_dir/contract_console_smoke.latest.json" || return 1
      release_phase_guard_require_not_older_than_current_snapshots "$prefix" "$evidence_dir" "$evidence_dir/contract_console_smoke.latest.json" || return 1
      release_phase_guard_require_condition "$prefix" "$env" "$evidence_dir/contract_console_smoke.latest.json" \
        "contract-console smoke status must be completed" \
        '.status == "completed"' || return 1
      release_phase_guard_require_condition "$prefix" "$env" "$evidence_dir/contract_console_smoke.latest.json" \
        "contract-console smoke must prove current Torii SCCP V1 governed proof admission" \
        'def hash32: type == "string" and test("^[0-9a-f]{64}$") and test("[^0]");
          (.bridge.torii_sccp_v1 // false) == true
          and ((.bridge.destination_message_id // "") | hash32)
          and ((.bridge.native_message_id // "") | hash32)
          and (.bridge.destination_message_id == .bridge.governed_route_provenance.destination.message_id_hex)
          and (.bridge.native_message_id == .bridge.governed_route_provenance.native.message_id_hex)
          and (.bridge.governed_route_provenance.destination.validated_by == "state_derived_sccp_proof_request")
          and (.bridge.governed_route_provenance.native.validated_by == "authoritative_typed_sccp_registry")
          and ((.bridge.governed_route_provenance.destination.route_configuration_hash_hex // "") | hash32)
          and ((.bridge.governed_route_provenance.native.route_configuration_hash_hex // "") | hash32)' || return 1
      release_phase_guard_require_condition "$prefix" "$env" "$evidence_dir/contract_console_smoke.latest.json" \
        "contract-console smoke must record valid bridge submission evidence" \
        'def tx_hash_hex:
            type == "string" and test("^[0-9a-fA-F]{64}$");
          (.bridge.submission_expectation // "") == "apply"
          and ((.submissions.proof_submit.tx_hash_hex // "") | tx_hash_hex)
          and ((.submissions.message_submit.tx_hash_hex // "") | tx_hash_hex)' || return 1
      release_phase_guard_require_contract_console_outcome "$prefix" "$env" "$evidence_dir/contract_console_smoke.latest.json" || return 1
      release_phase_guard_require_snapshot_check_completed "$prefix" "$env" "$evidence_dir/contract_console_smoke.latest.json" || return 1
      ;;
    publish-*trader-api)
      release_phase_guard_require_current_ready_preflight "$prefix" "$env" "$evidence_dir" || return 1
      release_phase_guard_require_metadata "$prefix" "$env" "$evidence_dir/trader_api_bundle.latest.json" environment || return 1
      release_phase_guard_require_current_chain "$prefix" "$evidence_dir" "$evidence_dir/trader_api_bundle.latest.json" "$env" || return 1
      release_phase_guard_require_current_snapshots "$prefix" "$env" "$evidence_dir" "$evidence_dir/trader_api_bundle.latest.json" || return 1
      release_phase_guard_require_not_older_than_current_snapshots "$prefix" "$evidence_dir" "$evidence_dir/trader_api_bundle.latest.json" || return 1
      release_phase_guard_require_snapshot_check_completed "$prefix" "$env" "$evidence_dir/trader_api_bundle.latest.json" || return 1
      release_phase_guard_require_condition "$prefix" "$env" "$evidence_dir/trader_api_bundle.latest.json" \
        "trader API bundle status must be completed" \
        '.status == "completed"' || return 1
      release_phase_guard_require_condition "$prefix" "$env" "$evidence_dir/trader_api_bundle.latest.json" \
        "deployment-record freshness check must be completed" \
        '(.deployment_record_check.status // "") == "completed"' || return 1
      release_phase_guard_require_condition "$prefix" "$env" "$evidence_dir/trader_api_bundle.latest.json" \
        "CID probe status must be completed" \
        '(.cid_probe.status // "") == "completed"' || return 1
      release_phase_guard_require_trader_api_cid_probe "$prefix" "$env" "$evidence_dir/trader_api_bundle.latest.json" || return 1
      release_phase_guard_require_trader_api_routes "$prefix" "$env" "$evidence_dir/trader_api_bundle.latest.json" || return 1
      release_phase_guard_require_trader_api_receipts "$prefix" "$env" "$evidence_dir/trader_api_bundle.latest.json" || return 1
      release_phase_guard_require_trader_api_content_cid "$prefix" "$env" "$evidence_dir/trader_api_bundle.latest.json" || return 1
      ;;
    release-production-checklist)
      release_phase_guard_require_json "$prefix" "$evidence_dir/observation.latest.json" || return 1
      release_phase_guard_require_condition "$prefix" "$env" "$evidence_dir/observation.latest.json" \
        "production observation must be completed, non-test, and preserve the fail-closed derivatives boundary" \
        '(.schema // "") == "soraswap-production-observation-evidence/v1"
          and (.status // "") == "completed"
          and (.environment // "") == "production"
          and (.test_only // true) == false
          and (.sample_count // 0) == 61
          and (.required_duration_seconds // 0) == 1800
          and (.required_interval_seconds // 0) == 30
          and (.summary.shared_derivatives_pause_outcome // "") == "not_required"
          and (.summary.shared_derivatives_pause_boundary // "") == "external_fail_closed"' || return 1
      release_phase_guard_require_no_sensitive_diagnostic_leaks \
        "$prefix" "$evidence_dir/observation.latest.json" || return 1
      ;;
    release-checklist)
      ;;
    *)
      echo "$prefix: evidence guard failed for target $target: unknown release phase target" >&2
      return 1
      ;;
  esac
}
