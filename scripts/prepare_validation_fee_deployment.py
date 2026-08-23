#!/usr/bin/env python3
"""Validate and emit the immutable fresh-Taira validation-fee deploy plan."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - Python 3.11 is the release baseline.
    import tomli as tomllib  # type: ignore[no-redef]

import render_validation_fee_payout as payout_renderer


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SPEC = ROOT / "config" / "validation_fee" / "deployment.taira.p1.json"
EXPECTED_RELEASE_SPEC_SHA256 = (
    "e58c8e26357d2bc1b6afc72c7c30fbf3507ae162a31bc231d8111e5edd88ed82"
)
HASH_HEX = re.compile(r"^[0-9a-f]{64}$")
TX_HASH_HEX = HASH_HEX
EXPECTED_NETWORK = "taira"
EXPECTED_CHAIN_ID = "fc56984b-2be7-431d-840e-21514d1883f0"
EXPECTED_CHAIN_DISCRIMINANT = 369
EXPECTED_DATASPACE = "universal"
EXPECTED_SBD_ASSET_ID = "7ZepsJTHCVLKsrFFNZGSRGZgvBhv"
REVIEWED_IROHA_BASE_COMMIT = "3d7a3bc788a791a426f914f15b2ba1f04b86ea0d"
PINNED_GIT = Path("/usr/bin/git")
PINNED_GPG = Path("/opt/homebrew/Cellar/gnupg/2.5.21/bin/gpg")
PINNED_PYTHON = Path("/opt/homebrew/bin/python3")
PINNED_CARGO_HOME = Path("/Users/takemiyamakoto/.cargo")
PINNED_GNUPGHOME = Path("/Users/takemiyamakoto/.gnupg")
PINNED_DEVELOPER_DIR = Path("/Applications/Xcode.app/Contents/Developer")
PINNED_GIT_PATH = "/usr/bin:/bin:/opt/homebrew/bin"
SANITIZED_GIT_ENVIRONMENT = {
    "DEVELOPER_DIR": str(PINNED_DEVELOPER_DIR),
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_NO_REPLACE_OBJECTS": "1",
    "GIT_OPTIONAL_LOCKS": "0",
    "GIT_PAGER": "cat",
    "GIT_TERMINAL_PROMPT": "0",
    "GNUPGHOME": str(PINNED_GNUPGHOME),
    "HOME": "/Users/takemiyamakoto",
    "LANG": "C",
    "LC_ALL": "C",
    "PAGER": "cat",
    "PATH": PINNED_GIT_PATH,
    "TZ": "UTC",
}
PINNED_GIT_ARGV_PREFIX = (
    str(PINNED_GIT),
    "-c",
    f"gpg.program={PINNED_GPG}",
    "-c",
    "core.attributesFile=/dev/null",
    "-c",
    "core.excludesFile=/dev/null",
    "-c",
    "core.fsmonitor=false",
    "-c",
    "core.untrackedCache=false",
)
EXPECTED_POOL_ALIAS = "dlmm_pool::dlmm.universal"
EXPECTED_PAYOUT_ALIAS = "autonomous_payout::validation_fee.universal"
REJECTED_IROHA_SOURCE_COMMITS = (
    "e0951a97e469a68f7c70958fd2c70198b90bcedf",
    "1ed6222b057a2cae6d1c95527fdfad81f3230eb0",
)
IROHA_SOURCE_DIFF_DOMAIN = b"iroha-source-diff-v1\0"
IROHA_TRACKED_DIFF_DOMAIN = b"tracked-binary-diff-sha256\0"
IROHA_UNTRACKED_MANIFEST_DOMAIN = (
    b"untracked-path-blob-manifest-sha256\0"
)
IROHA_TRACKED_DIFF_ARGUMENTS = (
    "--no-pager",
    "diff",
    "--binary",
    "--full-index",
    "--no-renames",
    "--diff-algorithm=myers",
    "--no-ext-diff",
    "--no-textconv",
    "--ignore-submodules=none",
    "HEAD",
    "--",
    ".",
)


class PlanError(ValueError):
    """The reviewed deployment input does not match the release binding."""


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def sha256_file(path: Path) -> str:
    try:
        return sha256_bytes(path.read_bytes())
    except OSError as error:
        raise PlanError(f"cannot read required file {path}: {error}") from error


def stable_regular_file_bytes(path: Path, label: str) -> bytes:
    try:
        before = path.lstat()
        if stat.S_ISLNK(before.st_mode) or not stat.S_ISREG(before.st_mode):
            raise PlanError(f"{label} must be a regular non-symlink file")
        payload = path.read_bytes()
        after = path.lstat()
    except OSError as error:
        raise PlanError(f"cannot read {label} {path}: {error}") from error
    before_identity = (
        before.st_dev,
        before.st_ino,
        before.st_mode,
        before.st_size,
        before.st_mtime_ns,
    )
    after_identity = (
        after.st_dev,
        after.st_ino,
        after.st_mode,
        after.st_size,
        after.st_mtime_ns,
    )
    if before_identity != after_identity:
        raise PlanError(f"{label} changed while it was being verified")
    return payload


def provenance_tool_binding(path: Path, label: str) -> dict[str, Any]:
    resolved = path.resolve()
    payload = stable_regular_file_bytes(resolved, label)
    return {
        "invoked_path": str(path),
        "resolved_path": str(resolved),
        "sha256": sha256_bytes(payload),
        "size_bytes": len(payload),
    }


def validate_pinned_provenance_tools() -> dict[str, Any]:
    expected_python = PINNED_PYTHON.resolve()
    running_python = Path(sys.executable).resolve()
    if running_python != expected_python:
        raise PlanError(
            "validation-fee planner must run under pinned Python "
            f"{expected_python}, got {running_python}"
        )
    try:
        xcode_git = subprocess.run(
            ["/usr/bin/xcrun", "--find", "git"],
            check=True,
            capture_output=True,
            text=True,
            env=SANITIZED_GIT_ENVIRONMENT,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as error:
        raise PlanError("cannot resolve the pinned effective Xcode Git") from error
    return {
        "git_dispatcher": provenance_tool_binding(
            PINNED_GIT,
            "pinned Git dispatcher",
        ),
        "git_effective": provenance_tool_binding(
            Path(xcode_git),
            "effective Xcode Git",
        ),
        "gpg": provenance_tool_binding(
            PINNED_GPG,
            "pinned GPG verifier",
        ),
        "python": provenance_tool_binding(
            PINNED_PYTHON,
            "pinned validation-fee planner Python",
        ),
    }


def validate_iroha_binary_source_binding(
    iroha_binary: Path,
    expected_commit: str,
) -> None:
    try:
        binary = iroha_binary.read_bytes()
    except OSError as error:
        raise PlanError(
            f"cannot read iroha binary for source binding: {iroha_binary}: {error}"
        ) from error
    if expected_commit.encode("ascii") not in binary:
        raise PlanError(
            "iroha binary does not embed the reviewed Iroha source commit "
            f"{expected_commit}"
        )
    for rejected_commit in REJECTED_IROHA_SOURCE_COMMITS:
        if rejected_commit.encode("ascii") in binary:
            raise PlanError(
                "iroha binary embeds rejected stale Iroha source commit "
                f"{rejected_commit}"
            )


def validate_cargo_lock_binding(
    iroha_root: Path,
    expected_sha256: str,
    expected_size_bytes: int,
) -> dict[str, Any]:
    cargo_lock = iroha_root / "Cargo.lock"
    payload = stable_regular_file_bytes(cargo_lock, "reviewed Cargo.lock")
    observed_sha256 = sha256_bytes(payload)
    observed_size_bytes = len(payload)
    if observed_sha256 != expected_sha256:
        raise PlanError(
            "Cargo.lock hash differs from the reviewed release input: "
            f"{observed_sha256} != {expected_sha256}"
        )
    if observed_size_bytes != expected_size_bytes:
        raise PlanError(
            "Cargo.lock size differs from the reviewed release input: "
            f"{observed_size_bytes} != {expected_size_bytes}"
        )
    return {
        "path": "Cargo.lock",
        "sha256": observed_sha256,
        "size_bytes": observed_size_bytes,
        "regular_non_symlink": True,
    }


def _run_iroha_git_bytes(iroha_root: Path, *arguments: str) -> bytes:
    try:
        return subprocess.run(
            [
                *PINNED_GIT_ARGV_PREFIX,
                "-C",
                str(iroha_root),
                *arguments,
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=SANITIZED_GIT_ENVIRONMENT,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as error:
        stderr = getattr(error, "stderr", b"") or b""
        if isinstance(stderr, bytes):
            detail = stderr.decode("utf-8", errors="replace").strip()
        else:
            detail = str(stderr).strip()
        raise PlanError(
            "Iroha source verification failed for "
            f"{' '.join(arguments)}: {detail}"
        ) from error


def _stable_untracked_entry(
    iroha_root: Path,
    relative_path_bytes: bytes,
    object_format: str,
) -> dict[str, str]:
    root_bytes = os.fsencode(iroha_root)
    absolute_path = os.path.join(root_bytes, relative_path_bytes)
    try:
        before = os.lstat(absolute_path)
        if stat.S_ISLNK(before.st_mode):
            raise PlanError(
                "untracked Iroha source symlinks are forbidden because their "
                "target bytes are outside the reviewed closure"
            )
        elif stat.S_ISREG(before.st_mode):
            with open(absolute_path, "rb") as source:
                blob_bytes = source.read()
            git_mode = "100755" if before.st_mode & 0o111 else "100644"
        else:
            raise PlanError(
                "untracked Iroha source inputs must be regular files or symlinks"
            )
        after = os.lstat(absolute_path)
    except OSError as error:
        raise PlanError(
            "cannot read untracked Iroha source input "
            f"{os.fsdecode(relative_path_bytes)}: {error}"
        ) from error
    before_identity = (
        before.st_dev,
        before.st_ino,
        before.st_mode,
        before.st_size,
        before.st_mtime_ns,
    )
    after_identity = (
        after.st_dev,
        after.st_ino,
        after.st_mode,
        after.st_size,
        after.st_mtime_ns,
    )
    if before_identity != after_identity:
        raise PlanError(
            "untracked Iroha source changed while it was being verified"
        )

    git_hasher = hashlib.new(object_format)
    git_hasher.update(
        b"blob " + str(len(blob_bytes)).encode("ascii") + b"\0"
    )
    git_hasher.update(blob_bytes)
    return {
        "blob_sha256": sha256_bytes(blob_bytes),
        "git_blob_oid": git_hasher.hexdigest(),
        "git_mode": git_mode,
        "path": os.fsdecode(relative_path_bytes),
        "path_bytes_base64": base64.b64encode(
            relative_path_bytes
        ).decode("ascii"),
    }


def iroha_untracked_manifest_bytes(
    entries: list[dict[str, str]],
) -> bytes:
    return b"".join(
        json.dumps(
            entry,
            ensure_ascii=True,
            separators=(",", ":"),
            sort_keys=True,
        ).encode("utf-8")
        + b"\n"
        for entry in entries
    )


def capture_iroha_source_closure(iroha_root: Path) -> dict[str, Any]:
    iroha_root = iroha_root.resolve()
    object_format = _run_iroha_git_bytes(
        iroha_root,
        "rev-parse",
        "--show-object-format",
    ).decode("ascii").strip()
    if object_format != "sha1":
        raise PlanError(
            "reviewed Iroha source must use the SHA-1 Git object format"
        )

    index_entries = _run_iroha_git_bytes(
        iroha_root,
        "ls-files",
        "-s",
        "-z",
        "--",
    ).split(b"\0")
    if any(entry.startswith(b"160000 ") for entry in index_entries if entry):
        raise PlanError(
            "reviewed Iroha source must not contain unbound Git submodules"
        )

    tracked_diff = _run_iroha_git_bytes(
        iroha_root,
        *IROHA_TRACKED_DIFF_ARGUMENTS,
    )
    tracked_diff_sha256 = sha256_bytes(tracked_diff)
    untracked_raw = _run_iroha_git_bytes(
        iroha_root,
        "ls-files",
        "--others",
        "--exclude-standard",
        "-z",
        "--",
    )
    untracked_paths = sorted(
        {path for path in untracked_raw.split(b"\0") if path}
    )
    untracked_entries = [
        _stable_untracked_entry(iroha_root, path, object_format)
        for path in untracked_paths
    ]
    untracked_manifest_sha256 = sha256_bytes(
        iroha_untracked_manifest_bytes(untracked_entries)
    )
    combined = hashlib.sha256()
    combined.update(IROHA_SOURCE_DIFF_DOMAIN)
    combined.update(IROHA_TRACKED_DIFF_DOMAIN)
    combined.update(bytes.fromhex(tracked_diff_sha256))
    combined.update(IROHA_UNTRACKED_MANIFEST_DOMAIN)
    combined.update(bytes.fromhex(untracked_manifest_sha256))
    return {
        "git_object_format": object_format,
        "tracked_binary_diff_sha256": tracked_diff_sha256,
        "untracked_file_count": len(untracked_entries),
        "untracked_path_blob_manifest": untracked_entries,
        "untracked_path_blob_manifest_sha256": untracked_manifest_sha256,
        "fingerprint_sha256": combined.hexdigest(),
    }


def expected_iroha_source_closure(
    spec: dict[str, Any],
) -> dict[str, Any]:
    return {
        "git_object_format": "sha1",
        "tracked_binary_diff_sha256": (
            spec["iroha_source_tracked_binary_diff_sha256"]
        ),
        "untracked_file_count": spec[
            "iroha_source_untracked_file_count"
        ],
        "untracked_path_blob_manifest": spec[
            "iroha_source_untracked_path_blob_manifest"
        ],
        "untracked_path_blob_manifest_sha256": spec[
            "iroha_source_untracked_path_blob_manifest_sha256"
        ],
        "fingerprint_sha256": spec[
            "iroha_source_fingerprint_sha256"
        ],
    }


def require_iroha_source_closure(
    observed: dict[str, Any],
    spec: dict[str, Any],
) -> None:
    if observed != expected_iroha_source_closure(spec):
        raise PlanError(
            "reviewed Iroha source tracked diff or untracked path/blob "
            "closure differs from the deployment spec"
        )


def require_reviewed_iroha_head(
    git: Any,
    expected_commit: str,
    phase: str,
) -> None:
    head = git("rev-parse", "--verify", "HEAD").stdout.strip()
    if head != expected_commit:
        raise PlanError(
            f"Iroha HEAD {head} does not equal reviewed commit "
            f"{expected_commit} during {phase}"
        )
    git("verify-commit", expected_commit)


def parse_json_file(path: Path) -> Any:
    try:
        return payout_renderer.parse_config_text(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, payout_renderer.ConfigError) as error:
        raise PlanError(f"invalid JSON in {path}: {error}") from error


def require_exact_keys(value: Any, expected: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise PlanError(f"{label} must be an object")
    actual = set(value)
    missing = sorted(expected - actual)
    unknown = sorted(actual - expected)
    if missing:
        raise PlanError(f"{label} is missing fields: {', '.join(missing)}")
    if unknown:
        raise PlanError(f"{label} has unknown fields: {', '.join(unknown)}")
    return value


def require_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise PlanError(f"{label} must be a non-empty string")
    return value


def require_int(value: Any, label: str) -> int:
    if type(value) is not int or value < 0:
        raise PlanError(f"{label} must be a non-negative decimal integer")
    return value


def require_hash(value: Any, label: str) -> str:
    value = require_string(value, label)
    if not HASH_HEX.fullmatch(value):
        raise PlanError(f"{label} must be exactly 64 lowercase hexadecimal characters")
    return value


def resolve_repo_path(root: Path, value: Any, label: str) -> Path:
    raw = require_string(value, label)
    relative = Path(raw)
    if relative.is_absolute() or ".." in relative.parts:
        raise PlanError(f"{label} must be a repository-relative path without '..'")
    path = (root / relative).resolve()
    try:
        path.relative_to(root.resolve())
    except ValueError as error:
        raise PlanError(f"{label} escapes the repository") from error
    return path


def normalize_manifest_hash(value: Any, label: str) -> str:
    raw = require_string(value, label)
    if raw.startswith("hash:"):
        raw = raw[5:]
    raw = raw.split("#", 1)[0].lower()
    return require_hash(raw, label)


def parse_last_json(text: str, label: str) -> Any:
    stripped = text.strip()
    try:
        return json.loads(stripped)
    except json.JSONDecodeError:
        pass
    decoder = json.JSONDecoder()
    selected: Any = None
    selected_span = -1
    for index, character in enumerate(text):
        if character not in "[{":
            continue
        try:
            value, end = decoder.raw_decode(text[index:])
        except json.JSONDecodeError:
            continue
        if end > selected_span:
            selected = value
            selected_span = end
    if selected is None:
        raise PlanError(f"{label} did not return JSON")
    return selected


def run_json(command: list[str], label: str) -> Any:
    try:
        completed = subprocess.run(
            command,
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        stderr = getattr(error, "stderr", "") or ""
        raise PlanError(f"{label} failed: {stderr.strip()}") from error
    output = completed.stdout if completed.stdout.strip() else completed.stderr
    return parse_last_json(output, label)


def validate_contract_spec(raw: Any, label: str) -> dict[str, Any]:
    base_keys = {
        "order",
        "key",
        "source",
        "source_sha256",
        "artifact",
        "artifact_sha256",
        "manifest_sha256",
        "alias",
        "deploy_nonce",
        "contract_address",
        "subject_account_id",
        "code_hash",
        "abi_hash",
    }
    if isinstance(raw, dict) and raw.get("key") == "payout":
        base_keys |= {"render_metadata", "render_metadata_sha256"}
    value = require_exact_keys(raw, base_keys, label)
    require_int(value["order"], f"{label}.order")
    require_string(value["key"], f"{label}.key")
    require_string(value["alias"], f"{label}.alias")
    require_int(value["deploy_nonce"], f"{label}.deploy_nonce")
    require_string(value["contract_address"], f"{label}.contract_address")
    require_string(value["subject_account_id"], f"{label}.subject_account_id")
    for field in (
        "source_sha256",
        "artifact_sha256",
        "manifest_sha256",
        "code_hash",
        "abi_hash",
    ):
        require_hash(value[field], f"{label}.{field}")
    if value.get("key") == "payout":
        require_hash(value["render_metadata_sha256"], f"{label}.render_metadata_sha256")
    return value


def validate_permission_spec(raw: Any, label: str) -> dict[str, Any]:
    value = require_exact_keys(raw, {"holder", "name", "payload"}, label)
    require_string(value["holder"], f"{label}.holder")
    require_string(value["name"], f"{label}.name")
    if not isinstance(value["payload"], dict) or not value["payload"]:
        raise PlanError(f"{label}.payload must be a non-empty object")
    return value


def validate_iroha_source_closure_spec(spec: dict[str, Any]) -> None:
    tracked_hash = require_hash(
        spec["iroha_source_tracked_binary_diff_sha256"],
        "deployment spec.iroha_source_tracked_binary_diff_sha256",
    )
    manifest_hash = require_hash(
        spec["iroha_source_untracked_path_blob_manifest_sha256"],
        "deployment spec.iroha_source_untracked_path_blob_manifest_sha256",
    )
    fingerprint = require_hash(
        spec["iroha_source_fingerprint_sha256"],
        "deployment spec.iroha_source_fingerprint_sha256",
    )
    file_count = require_int(
        spec["iroha_source_untracked_file_count"],
        "deployment spec.iroha_source_untracked_file_count",
    )
    raw_manifest = spec["iroha_source_untracked_path_blob_manifest"]
    if not isinstance(raw_manifest, list):
        raise PlanError(
            "deployment spec.iroha_source_untracked_path_blob_manifest "
            "must be an array"
        )
    entries: list[dict[str, str]] = []
    decoded_paths: list[bytes] = []
    for index, raw_entry in enumerate(raw_manifest):
        label = (
            "deployment spec.iroha_source_untracked_path_blob_manifest"
            f"[{index}]"
        )
        entry = require_exact_keys(
            raw_entry,
            {
                "blob_sha256",
                "git_blob_oid",
                "git_mode",
                "path",
                "path_bytes_base64",
            },
            label,
        )
        require_hash(entry["blob_sha256"], f"{label}.blob_sha256")
        git_blob_oid = require_string(
            entry["git_blob_oid"],
            f"{label}.git_blob_oid",
        )
        if not re.fullmatch(r"[0-9a-f]{40}", git_blob_oid):
            raise PlanError(
                f"{label}.git_blob_oid must be a full SHA-1 object ID"
            )
        if entry["git_mode"] not in {"100644", "100755"}:
            raise PlanError(
                f"{label}.git_mode must be 100644 or 100755"
            )
        path = require_string(entry["path"], f"{label}.path")
        encoded_path = require_string(
            entry["path_bytes_base64"],
            f"{label}.path_bytes_base64",
        )
        try:
            decoded_path = base64.b64decode(
                encoded_path,
                validate=True,
            )
        except ValueError as error:
            raise PlanError(
                f"{label}.path_bytes_base64 must be canonical base64"
            ) from error
        if (
            not decoded_path
            or base64.b64encode(decoded_path).decode("ascii") != encoded_path
            or os.fsdecode(decoded_path) != path
            or decoded_path.startswith(b"/")
            or any(
                component in {b"", b".", b".."}
                for component in decoded_path.split(b"/")
            )
        ):
            raise PlanError(
                f"{label} does not identify one canonical relative path"
            )
        entries.append(entry)
        decoded_paths.append(decoded_path)
    if decoded_paths != sorted(set(decoded_paths)):
        raise PlanError(
            "deployment spec untracked Iroha source manifest must contain "
            "unique entries in raw path-byte order"
        )
    if file_count != len(entries):
        raise PlanError(
            "deployment spec untracked Iroha source count does not match "
            "its manifest"
        )
    observed_manifest_hash = sha256_bytes(
        iroha_untracked_manifest_bytes(entries)
    )
    if observed_manifest_hash != manifest_hash:
        raise PlanError(
            "deployment spec untracked Iroha source manifest hash differs: "
            f"{observed_manifest_hash} != {manifest_hash}"
        )
    combined = hashlib.sha256()
    combined.update(IROHA_SOURCE_DIFF_DOMAIN)
    combined.update(IROHA_TRACKED_DIFF_DOMAIN)
    combined.update(bytes.fromhex(tracked_hash))
    combined.update(IROHA_UNTRACKED_MANIFEST_DOMAIN)
    combined.update(bytes.fromhex(manifest_hash))
    observed_fingerprint = combined.hexdigest()
    if observed_fingerprint != fingerprint:
        raise PlanError(
            "deployment spec Iroha source fingerprint differs from its "
            f"component hashes: {observed_fingerprint} != {fingerprint}"
        )


def validate_spec(raw: Any, enforce_release_digest: bool = True) -> dict[str, Any]:
    expected = {
        "schema_version",
        "network",
        "chain_id",
        "chain_discriminant",
        "genesis_sha256",
        "authority_account_id",
        "dataspace",
        "required_starting_deploy_nonce",
        "required_final_deploy_nonce",
        "iroha_source_commit",
        "iroha_source_tracked_binary_diff_sha256",
        "iroha_source_untracked_file_count",
        "iroha_source_untracked_path_blob_manifest",
        "iroha_source_untracked_path_blob_manifest_sha256",
        "iroha_source_fingerprint_sha256",
        "cargo_lock_sha256",
        "cargo_lock_size_bytes",
        "tool_binary_sha256",
        "payout_binding_file",
        "payout_binding_sha256",
        "contracts",
        "pre_deploy_accounts",
        "protected_permissions",
    }
    spec = require_exact_keys(raw, expected, "deployment spec")
    if spec["schema_version"] != 1 or type(spec["schema_version"]) is not int:
        raise PlanError("deployment spec schema_version must be exactly 1")
    for field in (
        "network",
        "chain_id",
        "authority_account_id",
        "dataspace",
        "iroha_source_commit",
        "payout_binding_file",
    ):
        require_string(spec[field], f"deployment spec.{field}")
    for field in (
        "chain_discriminant",
        "required_starting_deploy_nonce",
        "required_final_deploy_nonce",
        "cargo_lock_size_bytes",
    ):
        require_int(spec[field], f"deployment spec.{field}")
    require_hash(spec["genesis_sha256"], "deployment spec.genesis_sha256")
    require_hash(spec["payout_binding_sha256"], "deployment spec.payout_binding_sha256")
    require_hash(spec["cargo_lock_sha256"], "deployment spec.cargo_lock_sha256")
    validate_iroha_source_closure_spec(spec)
    if spec["cargo_lock_size_bytes"] == 0:
        raise PlanError("deployment spec.cargo_lock_size_bytes must be positive")
    if not re.fullmatch(r"[0-9a-f]{40}", spec["iroha_source_commit"]):
        raise PlanError(
            "deployment spec.iroha_source_commit must be exactly 40 lowercase "
            "hexadecimal characters"
        )
    if spec["iroha_source_commit"] != REVIEWED_IROHA_BASE_COMMIT:
        raise PlanError(
            "deployment spec.iroha_source_commit must equal the signed "
            f"reviewed base {REVIEWED_IROHA_BASE_COMMIT}"
        )

    binary_hashes = require_exact_keys(
        spec["tool_binary_sha256"],
        {"iroha", "koto", "account_literal_reencode", "split_contract_deploy"},
        "deployment spec.tool_binary_sha256",
    )
    for key, value in binary_hashes.items():
        require_hash(value, f"deployment spec.tool_binary_sha256.{key}")

    contracts = spec["contracts"]
    if not isinstance(contracts, list) or len(contracts) != 2:
        raise PlanError("deployment spec.contracts must contain exactly pool and payout")
    checked_contracts = [
        validate_contract_spec(contract, f"deployment spec.contracts[{index}]")
        for index, contract in enumerate(contracts)
    ]
    if [contract["key"] for contract in checked_contracts] != ["pool", "payout"]:
        raise PlanError("deployment contracts must be ordered pool then payout")
    if [contract["order"] for contract in checked_contracts] != [1, 2]:
        raise PlanError("deployment contract order must be exactly 1 then 2")
    if [contract["deploy_nonce"] for contract in checked_contracts] != [0, 1]:
        raise PlanError("deployment nonces must be exactly pool=0 and payout=1")
    if [contract["alias"] for contract in checked_contracts] != [
        EXPECTED_POOL_ALIAS,
        EXPECTED_PAYOUT_ALIAS,
    ]:
        raise PlanError("deployment aliases must be the exact P1 pool and payout aliases")
    if len({contract["contract_address"] for contract in checked_contracts}) != 2:
        raise PlanError("pool and payout contract addresses must differ")
    if len({contract["subject_account_id"] for contract in checked_contracts}) != 2:
        raise PlanError("pool and payout subject accounts must differ")
    if spec["required_starting_deploy_nonce"] != 0:
        raise PlanError("required starting deploy nonce must be exactly 0")
    if spec["required_final_deploy_nonce"] != 2:
        raise PlanError("required final deploy nonce must be exactly 2")
    if spec["network"] != EXPECTED_NETWORK:
        raise PlanError("deployment network must be exactly taira")
    if spec["chain_id"] != EXPECTED_CHAIN_ID:
        raise PlanError("deployment chain_id must be the reviewed fresh Taira chain")
    if spec["chain_discriminant"] != EXPECTED_CHAIN_DISCRIMINANT:
        raise PlanError("deployment chain discriminant must be exactly 369")
    if spec["dataspace"] != EXPECTED_DATASPACE:
        raise PlanError("deployment dataspace must be exactly universal")

    accounts = spec["pre_deploy_accounts"]
    if not isinstance(accounts, list) or len(accounts) != 2:
        raise PlanError("pre_deploy_accounts must contain exactly two contract subjects")
    for index, account in enumerate(accounts):
        account_keys = {"order", "account_id", "purpose"}
        if index == 1:
            account_keys.add("required_before_contract_order")
        checked = require_exact_keys(
            account, account_keys, f"deployment spec.pre_deploy_accounts[{index}]"
        )
        require_int(checked["order"], f"pre_deploy_accounts[{index}].order")
        require_string(checked["account_id"], f"pre_deploy_accounts[{index}].account_id")
        require_string(checked["purpose"], f"pre_deploy_accounts[{index}].purpose")
    if accounts[0]["account_id"] != checked_contracts[0]["subject_account_id"]:
        raise PlanError("pool pre-deploy account does not equal the pool subject")
    if accounts[1]["account_id"] != checked_contracts[1]["subject_account_id"]:
        raise PlanError("payout pre-deploy account does not equal the payout subject")
    if accounts[1].get("required_before_contract_order") != 2:
        raise PlanError("payout subject must be registered before contract order 2")
    if [account["order"] for account in accounts] != [1, 2]:
        raise PlanError("pre-deploy account order must be exactly pool=1 then payout=2")
    if [account["purpose"] for account in accounts] != [
        "pool_contract_subject",
        "payout_contract_subject",
    ]:
        raise PlanError("pre-deploy account purposes must be the exact P1 purposes")

    permissions = spec["protected_permissions"]
    if not isinstance(permissions, list) or len(permissions) != 3:
        raise PlanError("protected_permissions must contain exactly three typed permissions")
    checked_permissions = [
        validate_permission_spec(
            permission, f"deployment spec.protected_permissions[{index}]"
        )
        for index, permission in enumerate(permissions)
    ]
    pool, payout = checked_contracts
    expected_permissions = [
        {
            "holder": payout["subject_account_id"],
            "name": "CanInvokeContractEntrypoint",
            "payload": {
                "contract": payout["contract_address"],
                "entrypoint": "autonomous_validation_fee_tick",
            },
        },
        {
            "holder": payout["subject_account_id"],
            "name": "CanInvokeContractEntrypoint",
            "payload": {
                "contract": pool["contract_address"],
                "entrypoint": "swap_exact_in_quote_public",
            },
        },
        {
            "holder": pool["subject_account_id"],
            "name": "CanTransferAsset",
            "payload": {
                "asset": (
                    f"{EXPECTED_SBD_ASSET_ID}#{payout['subject_account_id']}"
                    "#dataspace:0"
                )
            },
        },
    ]
    if checked_permissions != expected_permissions:
        raise PlanError(
            "protected permissions must be the exact ordered P1 payout lifecycle selectors"
        )

    if enforce_release_digest:
        digest = sha256_bytes(canonical_json_bytes(spec))
        if digest != EXPECTED_RELEASE_SPEC_SHA256:
            raise PlanError(
                "deployment spec differs from the reviewed P1 release binding: "
                f"{digest} != {EXPECTED_RELEASE_SPEC_SHA256}"
            )
    return spec


def audit_cargo_source_inputs(
    iroha_root: Path,
    git: Any,
) -> dict[str, Any]:
    tracked_paths = {
        path
        for path in git("ls-files", "-z", "--").stdout.split("\0")
        if path
    }
    ignored_paths = sorted(
        path
        for path in git(
            "ls-files",
            "--others",
            "--ignored",
            "--exclude-standard",
            "-z",
            "--",
        ).stdout.split("\0")
        if path
    )
    if ignored_paths != ["Cargo.lock"]:
        raise PlanError(
            "ignored Iroha source inputs must contain exactly the separately "
            "bound Cargo.lock"
        )

    cargo_config_inputs: list[dict[str, Any]] = []
    config_directories: list[Path] = []
    cursor = iroha_root
    while True:
        config_directories.append(cursor / ".cargo")
        if cursor.parent == cursor:
            break
        cursor = cursor.parent
    config_directories.append(PINNED_CARGO_HOME.resolve())
    for directory in dict.fromkeys(config_directories):
        for basename in ("config", "config.toml"):
            candidate = directory / basename
            if not candidate.exists() and not candidate.is_symlink():
                continue
            payload = stable_regular_file_bytes(
                candidate,
                f"Cargo configuration {candidate}",
            )
            resolved = candidate.resolve()
            try:
                relative = resolved.relative_to(iroha_root).as_posix()
            except ValueError as error:
                raise PlanError(
                    "Cargo configuration outside the reviewed Iroha source "
                    f"is forbidden: {candidate}"
                ) from error
            if relative not in tracked_paths:
                raise PlanError(
                    f"Cargo configuration is not tracked: {relative}"
                )
            cargo_config_inputs.append(
                {
                    "path": relative,
                    "sha256": sha256_bytes(payload),
                    "size_bytes": len(payload),
                    "tracked": True,
                }
            )

    path_dependencies: list[dict[str, str]] = []

    def audit_dependency_table(
        manifest_path: str,
        table_name: str,
        table: Any,
    ) -> None:
        if not isinstance(table, dict):
            return
        for dependency_name, dependency in table.items():
            if not isinstance(dependency, dict):
                continue
            declared_path = dependency.get("path")
            if not isinstance(declared_path, str):
                continue
            manifest_directory = (iroha_root / manifest_path).parent
            lexical_path = Path(
                os.path.abspath(manifest_directory / declared_path)
            )
            resolved_path = lexical_path.resolve(strict=False)
            try:
                resolved_path.relative_to(iroha_root)
            except ValueError as error:
                raise PlanError(
                    "Cargo path dependency escapes the reviewed Iroha source: "
                    f"{manifest_path}:{table_name}:{dependency_name}"
                ) from error
            status = "declared_missing"
            dependency_manifest = resolved_path / "Cargo.toml"
            resolved_manifest = dependency_manifest.relative_to(
                iroha_root
            ).as_posix()
            if lexical_path.exists() or lexical_path.is_symlink():
                if lexical_path != resolved_path:
                    raise PlanError(
                        "Cargo path dependency contains a symlinked path: "
                        f"{manifest_path}:{table_name}:{dependency_name}"
                    )
                stable_regular_file_bytes(
                    dependency_manifest,
                    f"Cargo path dependency manifest {resolved_manifest}",
                )
                if resolved_manifest not in tracked_paths:
                    raise PlanError(
                        "Cargo path dependency manifest is not tracked: "
                        f"{resolved_manifest}"
                    )
                status = "tracked_present"
            path_dependencies.append(
                {
                    "declared_path": declared_path,
                    "dependency": str(dependency_name),
                    "manifest": manifest_path,
                    "resolved_manifest": resolved_manifest,
                    "status": status,
                    "table": table_name,
                }
            )

    manifest_paths = sorted(
        path
        for path in tracked_paths
        if path == "Cargo.toml" or path.endswith("/Cargo.toml")
    )
    for manifest_path in manifest_paths:
        try:
            manifest = tomllib.loads(
                stable_regular_file_bytes(
                    iroha_root / manifest_path,
                    f"Cargo manifest {manifest_path}",
                ).decode("utf-8")
            )
        except (UnicodeDecodeError, tomllib.TOMLDecodeError) as error:
            raise PlanError(
                f"invalid tracked Cargo manifest {manifest_path}: {error}"
            ) from error
        for table_name in (
            "dependencies",
            "dev-dependencies",
            "build-dependencies",
        ):
            audit_dependency_table(
                manifest_path,
                table_name,
                manifest.get(table_name),
            )
        workspace = manifest.get("workspace")
        if isinstance(workspace, dict):
            audit_dependency_table(
                manifest_path,
                "workspace.dependencies",
                workspace.get("dependencies"),
            )
        targets = manifest.get("target")
        if isinstance(targets, dict):
            for target_name, target in targets.items():
                if not isinstance(target, dict):
                    continue
                for table_name in (
                    "dependencies",
                    "dev-dependencies",
                    "build-dependencies",
                ):
                    audit_dependency_table(
                        manifest_path,
                        f"target.{target_name}.{table_name}",
                        target.get(table_name),
                    )
        patches = manifest.get("patch")
        if isinstance(patches, dict):
            for registry_name, patch in patches.items():
                audit_dependency_table(
                    manifest_path,
                    f"patch.{registry_name}",
                    patch,
                )
        audit_dependency_table(
            manifest_path,
            "replace",
            manifest.get("replace"),
        )
    path_dependencies.sort(
        key=lambda item: (
            item["manifest"],
            item["table"],
            item["dependency"],
            item["declared_path"],
        )
    )
    return {
        "ignored_inputs": ignored_paths,
        "cargo_config_inputs": cargo_config_inputs,
        "path_dependency_count": len(path_dependencies),
        "path_dependency_audit_sha256": sha256_bytes(
            canonical_json_bytes(path_dependencies)
        ),
        "path_dependencies": path_dependencies,
    }


def audit_iroha_git_admin(
    iroha_root: Path,
    git: Any,
) -> dict[str, Any]:
    git_directory = Path(
        git("rev-parse", "--absolute-git-dir").stdout.strip()
    ).resolve()
    expected_git_directory = iroha_root / ".git"
    if git_directory != expected_git_directory:
        raise PlanError(
            "reviewed Iroha source must be a standalone clone with an "
            "in-tree .git directory"
        )
    try:
        git_directory_stat = git_directory.lstat()
    except OSError as error:
        raise PlanError("cannot inspect reviewed Iroha .git directory") from error
    if (
        stat.S_ISLNK(git_directory_stat.st_mode)
        or not stat.S_ISDIR(git_directory_stat.st_mode)
    ):
        raise PlanError("reviewed Iroha .git must be a real directory")
    common_text = git("rev-parse", "--git-common-dir").stdout.strip()
    common_directory = (
        Path(common_text)
        if Path(common_text).is_absolute()
        else iroha_root / common_text
    ).resolve()
    if common_directory != git_directory:
        raise PlanError(
            "reviewed Iroha source must not use a shared Git common directory"
        )
    if git("rev-parse", "--is-shallow-repository").stdout.strip() != "false":
        raise PlanError("reviewed Iroha source must not be a shallow clone")
    if (git_directory / "objects" / "info" / "alternates").exists():
        raise PlanError(
            "reviewed Iroha source must not use alternate Git object storage"
        )
    if git(
        "for-each-ref",
        "--format=%(refname)",
        "refs/replace",
    ).stdout.strip():
        raise PlanError(
            "reviewed Iroha source must not contain Git replacement refs"
        )
    local_config = _run_iroha_git_bytes(
        iroha_root,
        "config",
        "--local",
        "--null",
        "--list",
    )
    lower_config = local_config.lower()
    dangerous_keys = (
        b"gpg.program",
        b"core.worktree",
        b"core.attributesfile",
        b"core.excludesfile",
        b"core.fsmonitor",
        b"diff.",
        b"filter.",
        b"include.",
        b"includeif.",
    )
    if any(key in lower_config for key in dangerous_keys):
        raise PlanError(
            "reviewed Iroha local Git config contains a provenance-shaping key"
        )
    inputs: dict[str, Any] = {
        "local_config": {
            "sha256": sha256_bytes(local_config),
            "size_bytes": len(local_config),
        }
    }
    for basename in ("HEAD", "config", "index", "packed-refs"):
        path = git_directory / basename
        if not path.exists() and not path.is_symlink():
            continue
        payload = stable_regular_file_bytes(
            path,
            f"reviewed Git administrative input {basename}",
        )
        inputs[basename] = {
            "sha256": sha256_bytes(payload),
            "size_bytes": len(payload),
        }
    return {
        "admin_inputs": inputs,
        "git_argv_prefix": list(PINNED_GIT_ARGV_PREFIX),
        "git_environment": SANITIZED_GIT_ENVIRONMENT,
    }


def validate_toolchain(
    root: Path,
    spec: dict[str, Any],
    tools: dict[str, Path],
    iroha_root: Path,
    enforce_source_state: bool,
) -> dict[str, Any]:
    observed_hashes: dict[str, str] = {}
    for name, path in tools.items():
        if not path.is_file():
            raise PlanError(f"required {name} binary is missing: {path}")
        observed_hashes[name] = sha256_file(path)
        expected = spec["tool_binary_sha256"][name]
        if observed_hashes[name] != expected:
            raise PlanError(
                f"{name} binary hash differs from the reviewed toolchain: "
                f"{observed_hashes[name]} != {expected}"
            )

    validate_iroha_binary_source_binding(
        tools["iroha"],
        spec["iroha_source_commit"],
    )

    iroha_root = iroha_root.resolve()
    default_iroha_root = (root.parent / "iroha").resolve()
    source: dict[str, Any] = {
        "root": (
            "../iroha"
            if iroha_root == default_iroha_root
            else "explicit_reviewed_worktree"
        ),
        "commit": spec["iroha_source_commit"],
        "head_matches": None,
        "provenance_tools": None,
        "source_closure_matches": None,
        "signature_verified": None,
    }
    if enforce_source_state:
        provenance_tools = validate_pinned_provenance_tools()

        def git(*arguments: str) -> subprocess.CompletedProcess[str]:
            stdout = _run_iroha_git_bytes(iroha_root, *arguments)
            return subprocess.CompletedProcess(
                [
                    *PINNED_GIT_ARGV_PREFIX,
                    "-C",
                    str(iroha_root),
                    *arguments,
                ],
                0,
                stdout=stdout.decode("utf-8", errors="surrogateescape"),
                stderr="",
            )

        if not bool(os.statvfs(iroha_root).f_flag & os.ST_RDONLY):
            raise PlanError(
                "reviewed Iroha source must be mounted from an immutable "
                "read-only filesystem copy"
            )
        git_admin = audit_iroha_git_admin(iroha_root, git)
        require_reviewed_iroha_head(
            git,
            spec["iroha_source_commit"],
            "initial source verification",
        )
        source_closure = capture_iroha_source_closure(iroha_root)
        require_iroha_source_closure(source_closure, spec)
        cargo_lock = validate_cargo_lock_binding(
            iroha_root,
            spec["cargo_lock_sha256"],
            spec["cargo_lock_size_bytes"],
        )
        cargo_inputs = audit_cargo_source_inputs(iroha_root, git)
        after_source_closure = capture_iroha_source_closure(iroha_root)
        if after_source_closure != source_closure:
            raise PlanError(
                "reviewed Iroha source closure changed while it was being "
                "verified"
            )
        if audit_iroha_git_admin(iroha_root, git) != git_admin:
            raise PlanError(
                "reviewed Iroha Git administrative inputs changed during "
                "verification"
            )
        if validate_pinned_provenance_tools() != provenance_tools:
            raise PlanError(
                "pinned provenance tools changed during Iroha verification"
            )
        require_reviewed_iroha_head(
            git,
            spec["iroha_source_commit"],
            "final source verification",
        )
        source |= {
            "head_matches": True,
            "provenance_tools": provenance_tools,
            "git_admin": git_admin,
            "source_closure_matches": True,
            "signature_verified": True,
            "source_closure": source_closure,
            "cargo_lock": cargo_lock,
            "cargo_inputs": cargo_inputs,
        }

    return {"binaries": observed_hashes, "source": source}


def validate_alias_manifests(root: Path, contracts: list[dict[str, Any]]) -> None:
    manifest_paths = {
        "pool": root / "iroha.contracts.toml",
        "payout": root / "validation_fee" / "iroha.contracts.toml",
    }
    names = {
        "pool": "dlmm.dlmm_pool",
        "payout": "validation_fee.autonomous_payout",
    }
    for contract in contracts:
        key = contract["key"]
        manifest_path = manifest_paths[key]
        try:
            manifest = tomllib.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, tomllib.TOMLDecodeError) as error:
            raise PlanError(f"invalid contract manifest {manifest_path}: {error}") from error
        matches = [
            item
            for item in manifest.get("contracts", [])
            if isinstance(item, dict) and item.get("name") == names[key]
        ]
        if len(matches) != 1:
            raise PlanError(f"{manifest_path} must define exactly one {names[key]} contract")
        entry = matches[0]
        if entry.get("alias") != contract["alias"]:
            raise PlanError(f"{key} alias does not match the reviewed deployment spec")
        manifest_root = manifest_path.parent
        for field in ("source", "artifact"):
            declared = entry.get(field)
            if not isinstance(declared, str):
                raise PlanError(f"{manifest_path} {names[key]} is missing {field}")
            actual = (manifest_root / declared).resolve()
            expected = resolve_repo_path(root, contract[field], f"{key}.{field}")
            if actual != expected:
                raise PlanError(
                    f"{manifest_path} {field} resolves to {actual}, expected {expected}"
                )


def validate_binding(root: Path, spec: dict[str, Any]) -> dict[str, Any]:
    binding_path = resolve_repo_path(
        root, spec["payout_binding_file"], "deployment spec.payout_binding_file"
    )
    try:
        raw = payout_renderer.parse_config_text(binding_path.read_text(encoding="utf-8"))
        binding = payout_renderer.validate_config(raw)
    except (OSError, json.JSONDecodeError, payout_renderer.ConfigError) as error:
        raise PlanError(f"invalid payout binding {binding_path}: {error}") from error
    binding_hash = sha256_bytes(canonical_json_bytes(binding))
    if binding_hash != spec["payout_binding_sha256"]:
        raise PlanError(
            f"payout binding hash differs: {binding_hash} != "
            f"{spec['payout_binding_sha256']}"
        )
    pool, payout = spec["contracts"]
    expected_fields = {
        "pool_contract_address": pool["contract_address"],
        "pool_vault_account_id": pool["subject_account_id"],
        "payout_vault_account_id": payout["subject_account_id"],
    }
    for field, expected in expected_fields.items():
        if binding[field] != expected:
            raise PlanError(f"payout binding {field} differs from deterministic deployment")
    return binding


def validate_contract_files(
    root: Path,
    spec: dict[str, Any],
    iroha_bin: Path,
) -> list[dict[str, Any]]:
    validated: list[dict[str, Any]] = []
    for contract in spec["contracts"]:
        key = contract["key"]
        source = resolve_repo_path(root, contract["source"], f"{key}.source")
        artifact = resolve_repo_path(root, contract["artifact"], f"{key}.artifact")
        manifest = artifact.with_suffix(".manifest.json")
        observed = {
            "source_sha256": sha256_file(source),
            "artifact_sha256": sha256_file(artifact),
            "manifest_sha256": sha256_file(manifest),
        }
        for field, actual in observed.items():
            if actual != contract[field]:
                raise PlanError(
                    f"{key} {field} differs from the reviewed artifact: "
                    f"{actual} != {contract[field]}"
                )

        embedded = run_json(
            [
                str(iroha_bin),
                "--machine",
                "--output-format",
                "json",
                "contract",
                "manifest",
                "build",
                "--code-file",
                str(artifact),
            ],
            f"{key} embedded manifest inspection",
        )
        if not isinstance(embedded, dict):
            raise PlanError(f"{key} embedded manifest inspection returned a non-object")
        code_hash = normalize_manifest_hash(embedded.get("code_hash"), f"{key}.code_hash")
        abi_hash = normalize_manifest_hash(embedded.get("abi_hash"), f"{key}.abi_hash")
        if code_hash != contract["code_hash"] or abi_hash != contract["abi_hash"]:
            raise PlanError(f"{key} embedded code/ABI hash differs from the reviewed spec")

        if key == "payout":
            metadata_path = resolve_repo_path(
                root, contract["render_metadata"], "payout.render_metadata"
            )
            metadata_hash = sha256_file(metadata_path)
            if metadata_hash != contract["render_metadata_sha256"]:
                raise PlanError("payout render metadata file hash differs")
            metadata = parse_json_file(metadata_path)
            expected_metadata = payout_renderer._metadata(  # noqa: SLF001
                validate_binding(root, spec),
                source.read_text(encoding="utf-8"),
            )
            if metadata != expected_metadata:
                raise PlanError("payout render metadata does not match the exact binding/source")
            rendered = payout_renderer.render_source(validate_binding(root, spec))
            if source.read_text(encoding="utf-8") != rendered:
                raise PlanError("payout rendered source differs from the exact binding")

        validated.append(
            {
                **contract,
                "observed": {
                    **observed,
                    "code_hash": code_hash,
                    "abi_hash": abi_hash,
                },
            }
        )
    return validated


def validate_derivations(
    spec: dict[str, Any],
    contracts: list[dict[str, Any]],
    iroha_bin: Path,
    account_helper: Path,
) -> None:
    for contract in contracts:
        derived = run_json(
            [
                str(iroha_bin),
                "--machine",
                "--output-format",
                "json",
                "contract",
                "derive-address",
                "--authority",
                spec["authority_account_id"],
                "--dataspace",
                spec["dataspace"],
                "--deploy-nonce",
                str(contract["deploy_nonce"]),
                "--chain-discriminant",
                str(spec["chain_discriminant"]),
            ],
            f"{contract['key']} address derivation",
        )
        if not isinstance(derived, dict):
            raise PlanError(f"{contract['key']} address derivation returned a non-object")
        expected_derivation = {
            "contract_address": contract["contract_address"],
            "dataspace": spec["dataspace"],
            "deploy_nonce": contract["deploy_nonce"],
            "chain_discriminant": spec["chain_discriminant"],
        }
        for field, expected in expected_derivation.items():
            if derived.get(field) != expected:
                raise PlanError(
                    f"{contract['key']} derived {field} differs: "
                    f"{derived.get(field)!r} != {expected!r}"
                )
        try:
            subject = subprocess.run(
                [
                    str(account_helper),
                    "--contract-address",
                    contract["contract_address"],
                    "--to-chain-discriminant",
                    str(spec["chain_discriminant"]),
                ],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
        except (OSError, subprocess.CalledProcessError) as error:
            stderr = getattr(error, "stderr", "") or ""
            raise PlanError(
                f"{contract['key']} subject derivation failed: {stderr.strip()}"
            ) from error
        if subject != contract["subject_account_id"]:
            raise PlanError(
                f"{contract['key']} subject derivation differs: "
                f"{subject!r} != {contract['subject_account_id']!r}"
            )


def build_plan(
    root: Path,
    spec_path: Path,
    tools: dict[str, Path],
    *,
    iroha_source_root: Path | None = None,
    enforce_release_digest: bool = True,
    enforce_source_state: bool = True,
) -> dict[str, Any]:
    spec = validate_spec(
        parse_json_file(spec_path),
        enforce_release_digest=enforce_release_digest,
    )
    validate_binding(root, spec)
    validate_alias_manifests(root, spec["contracts"])
    if iroha_source_root is None:
        iroha_source_root = root.parent / "iroha"
    toolchain = validate_toolchain(
        root,
        spec,
        tools,
        iroha_source_root,
        enforce_source_state,
    )
    contracts = validate_contract_files(root, spec, tools["iroha"])
    validate_derivations(
        spec,
        contracts,
        tools["iroha"],
        tools["account_literal_reencode"],
    )
    spec_hash = sha256_bytes(canonical_json_bytes(spec))
    plan = {
        "schema_version": 1,
        "status": "undeployed_plan",
        "network": spec["network"],
        "chain_id": spec["chain_id"],
        "chain_discriminant": spec["chain_discriminant"],
        "genesis_sha256": spec["genesis_sha256"],
        "authority_account_id": spec["authority_account_id"],
        "dataspace": spec["dataspace"],
        "deployment_spec_sha256": spec_hash,
        "required_starting_deploy_nonce": spec["required_starting_deploy_nonce"],
        "required_final_deploy_nonce": spec["required_final_deploy_nonce"],
        "sequence": [
            {
                "order": 1,
                "action": "register_contract_subject",
                **spec["pre_deploy_accounts"][0],
            },
            {
                "order": 2,
                "action": "register_contract_subject",
                **spec["pre_deploy_accounts"][1],
            },
            {
                "order": 3,
                "action": "deploy_contract",
                "contract_key": "pool",
                "deploy_nonce": 0,
                "contract_address": contracts[0]["contract_address"],
                "alias": contracts[0]["alias"],
            },
            {
                "order": 4,
                "action": "deploy_contract",
                "contract_key": "payout",
                "deploy_nonce": 1,
                "contract_address": contracts[1]["contract_address"],
                "alias": contracts[1]["alias"],
            },
        ],
        "contracts": contracts,
        "payout_binding": {
            "file": spec["payout_binding_file"],
            "sha256": spec["payout_binding_sha256"],
        },
        "protected_permissions": spec["protected_permissions"],
        "preconditions": {
            "aliases_absent": [contract["alias"] for contract in contracts],
            "protected_permissions_absent": True,
            "protected_role_permissions_absent": True,
            "direct_deployment_receipts_required": True,
            "preexisting_contract_subject_accounts_forbidden": True,
        },
        "prohibited_actions": {
            "protected_permission_grants": True,
            "role_grants": True,
            "parliament_activation": True,
            "validation_fee_lifecycle_activation": True,
        },
        "toolchain": toolchain,
    }
    return {
        "plan_sha256": sha256_bytes(canonical_json_bytes(plan)),
        "plan": plan,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Validate the reviewed fresh-fc569 P1 pool/wrapper artifacts and emit "
            "their deterministic, non-mutating deployment plan."
        )
    )
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--spec", type=Path, default=DEFAULT_SPEC)
    parser.add_argument(
        "--iroha-bin",
        type=Path,
        default=ROOT.parent / "iroha" / "target" / "debug" / "iroha",
    )
    parser.add_argument(
        "--koto-bin",
        type=Path,
        default=ROOT.parent / "iroha" / "target" / "debug" / "koto",
    )
    parser.add_argument(
        "--account-helper",
        type=Path,
        default=(
            ROOT.parent
            / "iroha"
            / "target"
            / "debug"
            / "account_literal_reencode"
        ),
    )
    parser.add_argument(
        "--split-deploy-bin",
        type=Path,
        default=(
            ROOT.parent / "iroha" / "target" / "debug" / "split_contract_deploy"
        ),
    )
    parser.add_argument(
        "--iroha-source-root",
        type=Path,
        default=ROOT.parent / "iroha",
        help=(
            "immutable read-only standalone Iroha clone containing the exact "
            "reviewed implementation closure over the signed base commit; it "
            "need not contain the external release target"
        ),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    tools = {
        "iroha": args.iroha_bin.resolve(),
        "koto": args.koto_bin.resolve(),
        "account_literal_reencode": args.account_helper.resolve(),
        "split_contract_deploy": args.split_deploy_bin.resolve(),
    }
    try:
        result = build_plan(
            args.root.resolve(),
            args.spec.resolve(),
            tools,
            iroha_source_root=args.iroha_source_root.resolve(),
        )
    except PlanError as error:
        print(f"validation-fee deployment plan rejected: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
