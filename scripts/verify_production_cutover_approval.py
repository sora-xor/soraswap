#!/usr/bin/env python3
"""Verify an independently signed, RC-bound production cutover approval."""

from __future__ import annotations

import argparse
import base64
import binascii
import datetime as dt
import hashlib
import json
import os
import ipaddress
import re
import secrets
import stat
import struct
import subprocess
import sys
import tempfile
from decimal import Decimal, InvalidOperation
from pathlib import Path
from urllib.parse import urlsplit


POLICY_RELATIVE = Path("config/production/cutover-trust-policy.json")
POLICY_SCHEMA = "soraswap-production-cutover-trust-policy/v1"
APPROVAL_SCHEMA = "soraswap-production-cutover-approval/v1"
EVIDENCE_SCHEMA = "soraswap-production-cutover-approval-evidence/v1"
NAMESPACE = "soraswap-production-cutover-v1"
REQUIRED_ROLES = {"security", "operations"}
FEATURES = ["embedded-soracloud-runtime", "sccp-test-fixtures"]
CONTROL_KEYS = {
    "custody",
    "rotation",
    "admin",
    "pause",
    "rollback",
    "monitoring",
    "incident_response",
}
PLACEHOLDER = re.compile(
    r"(?i)(replace(?:_with)?|change[ _-]?me|placeholder|\btodo\b|\btbd\b|"
    r"example\.(?:com|org|net|invalid|test)|localhost|127\.0\.0\.1|0\.0\.0\.0|"
    r"(?:^|/)(?:Users|tmp|private/tmp)/)"
)
HEX40 = re.compile(r"[0-9a-f]{40}")
HEX64 = re.compile(r"[0-9a-f]{64}")
DECIMAL = re.compile(r"[0-9]+(?:\.[0-9]+)?")
CANONICAL_DECIMAL = re.compile(r"(?:0|[1-9][0-9]*)(?:\.[0-9]*[1-9])?")
APPROVER_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:@/+-]{5,127}")
CONTENT_CID = re.compile(r"b[a-z2-7]{20,}")
APP_ID = re.compile(r"[a-z][a-z0-9_.-]{2,63}")
POLICY_KEYS = {
    "schema", "environment", "policy_id", "signature_namespace",
    "required_signature_count", "required_roles", "trusted_approvers",
    "allowed_monitoring_origins", "approval_max_age_seconds", "observation",
}
APPROVAL_KEYS = {
    "schema", "environment", "approval_id", "policy_sha256", "issued_at",
    "expires_at", "review", "findings", "bindings", "authorities",
    "minimum_fee_balance", "controls", "observation", "signatures",
}
BINDING_KEYS = {
    "chain_fingerprint", "soraswap_git_sha", "soraswap_tree_sha",
    "soraswap_source_sha256", "iroha_git_sha", "bundle_name",
    "checksums_sha256", "manifest_sha256", "iroha3d_sha256", "iroha_sha256",
    "kagami_sha256", "archive_sha256", "archive_sidecar_sha256",
    "iroha3d_features",
}
AUTHORITY_KEYS = {"signer", "oracle", "admin", "treasury", "bridge"}
OBSERVATION_KEYS = {
    "monitoring_snapshot_url", "maximum_monitoring_sample_age_seconds",
    "validator_count", "validator_set_sha256", "maximum_finality_age_ms",
    "maximum_oracle_age_seconds",
    "oracle_watch_sha256", "minimum_fee_balance", "balance_watch_sha256",
    "readonly_route_set_sha256", "trader_api_probe_url",
    "trader_api_content_cid", "trader_api_app_id", "trader_api_routes_sha256",
    "derivatives_pause_mode",
}
SOURCE_STATE_KEYS = {
    "git_head", "tracked_non_status_doc_count", "tracked_non_status_doc_sha256",
    "tracked_status_doc_count", "tracked_status_doc_identity_sha256",
}
IROHA_STATE_KEYS = {
    "iroha_root", "bundle_dir", "iroha_git_sha", "bundle_name",
    "checksums_sha256", "manifest_sha256", "iroha3d_sha256", "iroha_sha256",
    "kagami_sha256", "archive_sha256", "archive_sidecar_sha256",
}


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"production cutover approval failed: {message}")


def canonical_bytes(value: object) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_identity(metadata: os.stat_result) -> tuple[int, ...]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_nlink,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def directory_identity(metadata: os.stat_result) -> tuple[int, ...]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
    )


def open_directory_chain(path: Path, label: str) -> tuple[list[int], list[tuple[str, tuple[int, ...]]]]:
    """Open every directory component without following links and retain the chain."""
    path = Path(os.path.abspath(path))
    if not path.is_absolute():
        fail(f"{label} path must be absolute")
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptors: list[int] = []
    links: list[tuple[str, tuple[int, ...]]] = []
    try:
        current = os.open("/", flags)
        descriptors.append(current)
        for component in path.parts[1:]:
            if component in {"", ".", ".."}:
                fail(f"{label} path contains an unsafe component")
            parent_before = os.fstat(current)
            child = os.open(component, flags, dir_fd=current)
            child_metadata = os.fstat(child)
            named_metadata = os.stat(component, dir_fd=current, follow_symlinks=False)
            parent_after = os.fstat(current)
            if directory_identity(parent_before) != directory_identity(parent_after):
                os.close(child)
                fail(f"{label} directory changed while it was opened")
            if not stat.S_ISDIR(child_metadata.st_mode) or directory_identity(child_metadata) != directory_identity(named_metadata):
                os.close(child)
                fail(f"{label} path contains a replaced or non-directory component")
            links.append((component, directory_identity(child_metadata)))
            descriptors.append(child)
            current = child
        return descriptors, links
    except SystemExit:
        close_descriptors(descriptors)
        raise
    except OSError:
        for descriptor in reversed(descriptors):
            try:
                os.close(descriptor)
            except OSError:
                pass
        fail(f"{label} path is missing, linked, or changed")


def verify_directory_chain(
    descriptors: list[int], links: list[tuple[str, tuple[int, ...]]], label: str
) -> None:
    for index, (component, expected) in enumerate(links):
        try:
            current = os.fstat(descriptors[index + 1])
            named = os.stat(component, dir_fd=descriptors[index], follow_symlinks=False)
        except OSError:
            fail(f"{label} directory chain changed")
        if directory_identity(current) != expected or directory_identity(named) != expected:
            fail(f"{label} directory chain changed")


def close_descriptors(descriptors: list[int]) -> None:
    for descriptor in reversed(descriptors):
        try:
            os.close(descriptor)
        except OSError:
            pass


def read_regular(
    path: Path, label: str, expected_mode: int | None = None
) -> tuple[bytes, os.stat_result]:
    path = Path(os.path.abspath(path))
    descriptors, links = open_directory_chain(path.parent, label)
    parent_descriptor = descriptors[-1]
    descriptor = -1
    try:
        parent_before = os.fstat(parent_descriptor)
        descriptor = os.open(
            path.name,
            os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0),
            dir_fd=parent_descriptor,
        )
        before = os.fstat(descriptor)
        named_before = os.stat(path.name, dir_fd=parent_descriptor, follow_symlinks=False)
    except OSError:
        close_descriptors(descriptors)
        fail(f"{label} is missing")
    if not stat.S_ISREG(before.st_mode) or file_identity(before) != file_identity(named_before):
        os.close(descriptor)
        close_descriptors(descriptors)
        fail(f"{label} must be a regular non-symlink file")
    if before.st_nlink != 1:
        os.close(descriptor)
        close_descriptors(descriptors)
        fail(f"{label} must have exactly one hard link")
    if expected_mode is not None and stat.S_IMODE(before.st_mode) != expected_mode:
        os.close(descriptor)
        close_descriptors(descriptors)
        fail(f"{label} must have mode {expected_mode:04o}")
    try:
        chunks: list[bytes] = []
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        if os.read(descriptor, 1) != b"":
            fail(f"{label} did not remain at EOF")
        after = os.fstat(descriptor)
        named_after = os.stat(path.name, dir_fd=parent_descriptor, follow_symlinks=False)
        parent_after = os.fstat(parent_descriptor)
        verify_directory_chain(descriptors, links, label)
    except OSError:
        os.close(descriptor)
        close_descriptors(descriptors)
        fail(f"{label} changed while it was read")
    finally:
        if descriptor >= 0:
            try:
                os.close(descriptor)
            except OSError:
                pass
        close_descriptors(descriptors)
    if (
        file_identity(before) != file_identity(after)
        or file_identity(before) != file_identity(named_after)
        or directory_identity(parent_before) != directory_identity(parent_after)
    ):
        fail(f"{label} changed while it was read")
    return b"".join(chunks), before


def parse_json(data: bytes, label: str) -> dict:
    try:
        value = json.loads(data.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError):
        fail(f"{label} is not valid UTF-8 JSON")
    if not isinstance(value, dict):
        fail(f"{label} must be a JSON object")
    return value


def parse_state(raw: str, label: str) -> dict:
    try:
        value = json.loads(raw)
    except json.JSONDecodeError:
        fail(f"{label} is not valid JSON")
    if not isinstance(value, dict):
        fail(f"{label} must be a JSON object")
    return value


def parse_time(value: object, label: str) -> dt.datetime:
    if not isinstance(value, str) or not value:
        fail(f"{label} must be a non-empty UTC timestamp")
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        fail(f"{label} must be an ISO-8601 timestamp")
    if parsed.tzinfo is None:
        fail(f"{label} must include a timezone")
    return parsed.astimezone(dt.timezone.utc)


def require_real_reference(value: object, label: str) -> str:
    if not isinstance(value, str) or len(value.strip()) < 12:
        fail(f"{label} must contain a concrete external reference")
    value = value.strip()
    if any(ord(character) < 0x20 for character in value) or PLACEHOLDER.search(value):
        fail(f"{label} contains placeholder, local, or control-character content")
    return value


def require_https_origin(value: object, label: str) -> str:
    reference = require_real_reference(value, label)
    parsed = urlsplit(reference)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        fail(f"{label} must be an HTTPS origin without embedded credentials")
    if parsed.path not in {"", "/"} or parsed.query or parsed.fragment:
        fail(f"{label} must contain only an HTTPS origin")
    return normalized_https_origin(parsed, label)


def require_https_url(value: object, label: str) -> str:
    reference = require_real_reference(value, label)
    parsed = urlsplit(reference)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        fail(f"{label} must be an HTTPS URL without embedded credentials")
    if parsed.query or parsed.fragment:
        fail(f"{label} must not contain a query or fragment")
    origin = normalized_https_origin(parsed, label)
    return origin + (parsed.path or "/")


def normalized_https_origin(parsed, label: str) -> str:
    try:
        port = parsed.port
    except ValueError:
        fail(f"{label} contains an invalid port")
    host = str(parsed.hostname or "").lower().rstrip(".")
    if not host:
        fail(f"{label} is missing a host")
    if host in {"localhost", "0.0.0.0"} or host.endswith(
        (".localhost", ".example", ".invalid", ".test")
    ) or host in {"example.com", "example.org", "example.net"}:
        fail(f"{label} uses a local or reserved host")
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        address = None
    if address is not None and (
        address.is_loopback or address.is_unspecified or address.is_private
        or address.is_link_local or address.is_reserved or address.is_multicast
    ):
        fail(f"{label} uses a non-public address")
    rendered_host = f"[{host}]" if ":" in host else host
    return f"https://{rendered_host}" + (f":{port}" if port not in {None, 443} else "")


def require_hash(value: object, label: str) -> str:
    if not isinstance(value, str) or HEX64.fullmatch(value) is None:
        fail(f"{label} must be 64 lowercase hexadecimal characters")
    return value


def require_approver_id(value: object, label: str) -> str:
    value = require_real_reference(value, label)
    if APPROVER_ID.fullmatch(value) is None:
        fail(f"{label} contains unsafe principal characters")
    return value


def parse_ed25519_public_key(value: object, label: str) -> tuple[str, str]:
    if not isinstance(value, str) or re.fullmatch(r"ssh-ed25519 [A-Za-z0-9+/]+={0,2}", value) is None:
        fail(f"{label} must be an exact comment-free SSH Ed25519 public key")
    encoded = value.split(" ", 1)[1]
    try:
        blob = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error):
        fail(f"{label} has invalid base64")
    if base64.b64encode(blob).decode("ascii") != encoded:
        fail(f"{label} is not canonical base64")
    try:
        algorithm_length = struct.unpack(">I", blob[:4])[0]
        cursor = 4
        algorithm = blob[cursor:cursor + algorithm_length]
        cursor += algorithm_length
        key_length = struct.unpack(">I", blob[cursor:cursor + 4])[0]
        cursor += 4
        key = blob[cursor:cursor + key_length]
        cursor += key_length
    except (struct.error, IndexError):
        fail(f"{label} has a malformed SSH wire encoding")
    if algorithm != b"ssh-ed25519" or key_length != 32 or len(key) != 32 or cursor != len(blob):
        fail(f"{label} is not an SSH Ed25519 key blob")
    return value, sha256(blob)


def git_bytes(root: Path, *arguments: str) -> bytes:
    try:
        return subprocess.check_output(
            ["git", "-C", str(root), *arguments], stderr=subprocess.DEVNULL
        )
    except (OSError, subprocess.CalledProcessError):
        fail("signed SoraSwap RC Git identity is unreadable")


def verify_policy_is_rc_bound(
    root: Path, expected_sha: str, policy_path: Path, policy_bytes: bytes
) -> None:
    if policy_path != root / POLICY_RELATIVE:
        fail(f"trust policy must be the RC-bound {POLICY_RELATIVE.as_posix()}")
    head = git_bytes(root, "rev-parse", "HEAD").decode("ascii").strip()
    if head != expected_sha:
        fail("SoraSwap HEAD does not match the approved signed RC")
    try:
        subprocess.run(
            ["git", "-C", str(root), "verify-commit", expected_sha],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError):
        fail("SoraSwap RC commit signature is not verifiable")
    tree_entry = git_bytes(
        root, "ls-tree", expected_sha, "--", POLICY_RELATIVE.as_posix()
    ).decode("utf-8").strip()
    match = re.fullmatch(
        rf"100644 blob [0-9a-f]{{40}}\t{re.escape(POLICY_RELATIVE.as_posix())}",
        tree_entry,
    )
    if match is None:
        fail("real trust policy is not a mode-100644 file in the signed SoraSwap RC")
    committed = git_bytes(root, "show", f"{expected_sha}:{POLICY_RELATIVE.as_posix()}")
    if committed != policy_bytes:
        fail("worktree trust policy bytes differ from the signed SoraSwap RC")


def validate_policy(policy: dict) -> tuple[dict[str, dict], set[str], list[str], int, dict]:
    if set(policy) != POLICY_KEYS:
        fail("trust policy fields do not match the v1 schema")
    if policy.get("schema") != POLICY_SCHEMA or policy.get("environment") != "production":
        fail("trust policy schema or environment is invalid")
    require_real_reference(policy.get("policy_id"), "trust policy id")
    if policy.get("signature_namespace") != NAMESPACE:
        fail("trust policy signature namespace is invalid")
    threshold = policy.get("required_signature_count")
    if not isinstance(threshold, int) or isinstance(threshold, bool) or threshold < 2:
        fail("trust policy must require at least two independent signatures")
    roles_raw = policy.get("required_roles")
    if not isinstance(roles_raw, list) or len(set(roles_raw)) != len(roles_raw) \
            or any(role not in {"security", "operations", "risk", "compliance"} for role in roles_raw):
        fail("trust policy required roles are invalid or duplicated")
    roles = set(roles_raw)
    if not REQUIRED_ROLES <= roles:
        fail("trust policy must require independent security and operations roles")
    if threshold < len(roles):
        fail("trust policy signature threshold cannot be below its required role count")
    approvers_raw = policy.get("trusted_approvers")
    if not isinstance(approvers_raw, list) or len(approvers_raw) < threshold:
        fail("trust policy does not contain enough trusted approvers")
    approvers: dict[str, dict] = {}
    key_fingerprints: set[str] = set()
    for item in approvers_raw:
        if not isinstance(item, dict) or set(item) != {"id", "role", "public_key", "independent"}:
            fail("trusted approver entry is malformed")
        approver_id = require_approver_id(item.get("id"), "trusted approver id")
        if approver_id in approvers:
            fail("trust policy contains a duplicate approver id")
        if item.get("role") not in roles or item.get("independent") is not True:
            fail("trusted approver is not an independent required-role reviewer")
        public_key, key_fingerprint = parse_ed25519_public_key(
            item.get("public_key"), f"trusted approver {approver_id} public key"
        )
        if key_fingerprint in key_fingerprints:
            fail("trusted approvers must use distinct signing keys")
        key_fingerprints.add(key_fingerprint)
        approvers[approver_id] = {**item, "public_key": public_key, "key_sha256": key_fingerprint}
    for role in roles:
        if not any(item["role"] == role for item in approvers.values()):
            fail(f"trust policy has no independent approver for required role {role}")
    origins_raw = policy.get("allowed_monitoring_origins")
    if not isinstance(origins_raw, list) or not origins_raw:
        fail("trust policy must define at least one monitoring origin")
    origins = [require_https_origin(value, "allowed monitoring origin") for value in origins_raw]
    if len(set(origins)) != len(origins):
        fail("trust policy monitoring origins are duplicated")
    max_age = policy.get("approval_max_age_seconds")
    if not isinstance(max_age, int) or isinstance(max_age, bool) or not 300 <= max_age <= 86400:
        fail("trust policy approval age must be between 300 and 86400 seconds")
    observation = policy.get("observation")
    expected_observation = {
        "duration_seconds": 1800,
        "interval_seconds": 30,
        "minimum_samples": 61,
        "maximum_monitoring_sample_age_seconds": 30,
        "minimum_validator_count": 4,
        "maximum_finality_age_ms": 30000,
        "derivatives_pause_mode": "external_fail_closed",
    }
    if observation != expected_observation:
        fail("trust policy cannot weaken the fixed production observation controls")
    return approvers, roles, origins, max_age, expected_observation


def validate_signature(
    approver_id: str, public_key: str, encoded: object, message: bytes
) -> str:
    if not isinstance(encoded, str):
        fail(f"signature for {approver_id} is missing")
    try:
        signature = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error):
        fail(f"signature for {approver_id} is not canonical base64")
    if base64.b64encode(signature).decode("ascii") != encoded:
        fail(f"signature for {approver_id} is not canonical base64")
    if len(signature) > 16384 \
            or not signature.startswith(b"-----BEGIN SSH SIGNATURE-----\n") \
            or not signature.endswith(b"-----END SSH SIGNATURE-----\n"):
        fail(f"signature for {approver_id} is not an OpenSSH sshsig")
    with tempfile.TemporaryDirectory(prefix="soraswap-cutover-signature.") as temporary_raw:
        temporary = Path(temporary_raw)
        allowed = temporary / "allowed_signers"
        signature_path = temporary / "approval.sig"
        allowed.write_text(f"{approver_id} {public_key}\n", encoding="utf-8")
        signature_path.write_bytes(signature)
        os.chmod(allowed, 0o600)
        os.chmod(signature_path, 0o600)
        try:
            subprocess.run(
                [
                    "ssh-keygen",
                    "-Y",
                    "verify",
                    "-f",
                    str(allowed),
                    "-I",
                    approver_id,
                    "-n",
                    NAMESPACE,
                    "-s",
                    str(signature_path),
                ],
                input=message,
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except (OSError, subprocess.CalledProcessError):
            fail(f"signature verification failed for trusted approver {approver_id}")
    return sha256(signature)


def atomic_create(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path = Path(os.path.abspath(path))
    descriptors, links = open_directory_chain(path.parent, "cutover approval evidence")
    parent_descriptor = descriptors[-1]
    parent_before = os.fstat(parent_descriptor)
    temporary_name = f".cutover-approval.{secrets.token_hex(24)}.tmp"
    descriptor = -1
    temporary_identity: tuple[int, ...] | None = None
    try:
        try:
            os.stat(path.name, dir_fd=parent_descriptor, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            fail("cutover approval evidence already exists; archive the prior release evidence explicitly")
        descriptor = os.open(
            temporary_name,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
            0o600,
            dir_fd=parent_descriptor,
        )
        os.fchmod(descriptor, 0o600)
        temporary_metadata = os.fstat(descriptor)
        temporary_identity = file_identity(temporary_metadata)
        if not stat.S_ISREG(temporary_metadata.st_mode) or temporary_metadata.st_nlink != 1:
            fail("cutover approval evidence temporary file is unsafe")
        payload = json.dumps(value, indent=2, sort_keys=True).encode("utf-8") + b"\n"
        offset = 0
        while offset < len(payload):
            offset += os.write(descriptor, payload[offset:])
        os.fsync(descriptor)
        if file_identity(os.fstat(descriptor)) != file_identity(
            os.stat(temporary_name, dir_fd=parent_descriptor, follow_symlinks=False)
        ):
            fail("cutover approval evidence temporary file changed")
        try:
            os.link(
                temporary_name,
                path.name,
                src_dir_fd=parent_descriptor,
                dst_dir_fd=parent_descriptor,
                follow_symlinks=False,
            )
        except FileExistsError:
            fail("cutover approval evidence appeared concurrently")
        target_metadata = os.stat(path.name, dir_fd=parent_descriptor, follow_symlinks=False)
        if file_identity(os.fstat(descriptor)) != file_identity(target_metadata):
            fail("cutover approval evidence target changed")
        named_temporary = os.stat(temporary_name, dir_fd=parent_descriptor, follow_symlinks=False)
        if temporary_identity is None or file_identity(named_temporary)[:2] != temporary_identity[:2]:
            fail("cutover approval evidence temporary name changed")
        os.unlink(temporary_name, dir_fd=parent_descriptor)
        temporary_identity = None
        os.fsync(parent_descriptor)
        verify_directory_chain(descriptors, links, "cutover approval evidence")
        parent_after = os.fstat(parent_descriptor)
        if file_identity(parent_before)[:2] != file_identity(parent_after)[:2]:
            fail("cutover approval evidence parent changed")
    finally:
        if descriptor >= 0:
            try:
                os.close(descriptor)
            except OSError:
                pass
        if temporary_identity is not None:
            try:
                named = os.stat(temporary_name, dir_fd=parent_descriptor, follow_symlinks=False)
                if file_identity(named)[:2] == temporary_identity[:2]:
                    os.unlink(temporary_name, dir_fd=parent_descriptor)
            except OSError:
                pass
        close_descriptors(descriptors)


def verify_evidence(path: Path, root: Path, stable_state: dict) -> None:
    expected = root / "deployments" / "production" / "cutover_approval.latest.json"
    path = Path(os.path.abspath(path))
    if path != expected:
        fail("cutover approval evidence must use deployments/production/cutover_approval.latest.json")
    evidence_bytes, _ = read_regular(path, "cutover approval evidence", 0o600)
    evidence = parse_json(evidence_bytes, "cutover approval evidence")
    if evidence.get("schema") != EVIDENCE_SCHEMA or evidence.get("status") != "verified":
        fail("cutover approval evidence schema or status is invalid")
    if evidence.get("test_only") is not False:
        fail("cutover approval evidence is marked test-only")
    try:
        parse_time(evidence.get("generated_at"), "cutover approval evidence generated_at")
    except SystemExit:
        # Evidence timestamps use the compact UTC form used by other release artifacts.
        try:
            dt.datetime.strptime(str(evidence.get("generated_at")), "%Y%m%dT%H%M%SZ")
        except ValueError:
            fail("cutover approval evidence generated_at is invalid")
    observed_state = dict(evidence)
    observed_state.pop("status", None)
    observed_state.pop("generated_at", None)
    observed_state.pop("test_only", None)
    observed_state["schema"] = stable_state["schema"]
    if observed_state != stable_state:
        fail("cutover approval evidence does not match the current signed approval state")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--policy", required=True)
    parser.add_argument("--approval", required=True)
    parser.add_argument("--expected-soraswap-sha", required=True)
    parser.add_argument("--soraswap-rc-state-json", required=True)
    parser.add_argument("--soraswap-source-state-json", required=True)
    parser.add_argument("--iroha-state-json", required=True)
    parser.add_argument("--chain-file", required=True)
    parser.add_argument("--signer-authority", required=True)
    parser.add_argument("--oracle-authority", required=True)
    parser.add_argument("--admin-authority", required=True)
    parser.add_argument("--treasury-authority", required=True)
    parser.add_argument("--bridge-authority", required=True)
    parser.add_argument("--minimum-fee-balance", required=True)
    parser.add_argument("--write-evidence")
    parser.add_argument("--verify-evidence")
    args = parser.parse_args()

    if args.write_evidence and args.verify_evidence:
        fail("write-evidence and verify-evidence are mutually exclusive")

    root_input = Path(os.path.abspath(args.root))
    try:
        root_metadata = root_input.lstat()
    except OSError:
        fail("release root is missing")
    if stat.S_ISLNK(root_metadata.st_mode) or not stat.S_ISDIR(root_metadata.st_mode):
        fail("release root must be a real directory")
    root = root_input.resolve(strict=True)
    if root != root_input:
        fail("release root path must not traverse links")
    if not HEX40.fullmatch(args.expected_soraswap_sha):
        fail("expected SoraSwap SHA must be 40 lowercase hexadecimal characters")

    policy_path = Path(os.path.abspath(args.policy))
    approval_path = Path(os.path.abspath(args.approval))
    if policy_path != root / POLICY_RELATIVE:
        fail(f"trust policy must use {POLICY_RELATIVE.as_posix()}")
    if approval_path != root / "config/production/cutover-approval.json":
        fail("signed approval must use config/production/cutover-approval.json")
    policy_bytes, _ = read_regular(
        policy_path, "RC-bound cutover trust policy", 0o644
    )
    approval_bytes, _ = read_regular(approval_path, "signed cutover approval", 0o600)
    policy = parse_json(policy_bytes, "cutover trust policy")
    approval = parse_json(approval_bytes, "cutover approval")
    verify_policy_is_rc_bound(root, args.expected_soraswap_sha, policy_path, policy_bytes)
    approvers, required_roles, origins, max_age, policy_observation = validate_policy(policy)

    if set(approval) != APPROVAL_KEYS:
        fail("approval fields do not match the v1 schema")
    if approval.get("schema") != APPROVAL_SCHEMA or approval.get("environment") != "production":
        fail("approval schema or environment is invalid")
    approval_id = require_real_reference(approval.get("approval_id"), "approval id")
    policy_hash = sha256(policy_bytes)
    if approval.get("policy_sha256") != policy_hash:
        fail("approval does not bind the exact RC trust policy bytes")

    now = dt.datetime.now(dt.timezone.utc)
    issued_at = parse_time(approval.get("issued_at"), "approval issued_at")
    expires_at = parse_time(approval.get("expires_at"), "approval expires_at")
    if issued_at > now + dt.timedelta(minutes=5) or now - issued_at > dt.timedelta(seconds=max_age):
        fail("approval is stale or issued implausibly in the future")
    if expires_at <= now or expires_at > issued_at + dt.timedelta(seconds=max_age):
        fail("approval expiry is stale or exceeds the RC policy maximum age")
    review = approval.get("review")
    if not isinstance(review, dict) or set(review) != {"identity", "reviewed_at", "independent"} \
            or review.get("independent") is not True:
        fail("approval lacks an independent review identity and time")
    review_identity = require_approver_id(review.get("identity"), "review identity")
    reviewed_at = parse_time(review.get("reviewed_at"), "review reviewed_at")
    if abs((reviewed_at - issued_at).total_seconds()) > 300:
        fail("review time is not coherent with approval issuance")
    if reviewed_at > now + dt.timedelta(minutes=5):
        fail("review time is implausibly in the future")

    findings = approval.get("findings")
    if findings != {"unresolved_critical": 0, "unresolved_high": 0, "unresolved": []}:
        fail("approval must record zero unresolved Critical and High findings")

    rc_state = parse_state(args.soraswap_rc_state_json, "SoraSwap RC state")
    source_state = parse_state(args.soraswap_source_state_json, "SoraSwap source state")
    iroha_state = parse_state(args.iroha_state_json, "Iroha candidate state")
    if set(rc_state) != {"git_sha", "tree_sha"}:
        fail("SoraSwap RC state fields are invalid")
    if set(source_state) != SOURCE_STATE_KEYS:
        fail("SoraSwap source state fields are invalid")
    if set(iroha_state) != IROHA_STATE_KEYS:
        fail("Iroha candidate state fields are invalid")
    if rc_state.get("git_sha") != args.expected_soraswap_sha or source_state.get("git_head") != args.expected_soraswap_sha:
        fail("SoraSwap RC/source state does not match the expected signed commit")
    for key in ("tracked_non_status_doc_count", "tracked_status_doc_count"):
        if not isinstance(source_state.get(key), int) or isinstance(source_state.get(key), bool) \
                or source_state[key] < 1:
            fail(f"SoraSwap source state {key} is invalid")
    for key in ("tracked_non_status_doc_sha256", "tracked_status_doc_identity_sha256"):
        require_hash(source_state.get(key), f"SoraSwap source state {key}")
    chain_bytes, _ = read_regular(Path(os.path.abspath(args.chain_file)), "production chain fingerprint")
    chain = parse_json(chain_bytes, "production chain fingerprint")
    if chain.get("environment") != "production":
        fail("production chain fingerprint has the wrong environment")
    chain_fingerprint = {
        "torii_url": require_https_origin(chain.get("torii_url"), "production chain Torii URL"),
        "chain": chain.get("chain"),
        "block_1_hash": chain.get("block_1_hash"),
    }
    if not all(isinstance(value, str) and value for value in chain_fingerprint.values()):
        fail("production chain fingerprint is incomplete")
    require_real_reference(chain_fingerprint["chain"], "production chain id")
    require_hash(chain_fingerprint["block_1_hash"], "production chain block-1 hash")

    expected_bindings = {
        "chain_fingerprint": chain_fingerprint,
        "soraswap_git_sha": args.expected_soraswap_sha,
        "soraswap_tree_sha": rc_state.get("tree_sha"),
        "soraswap_source_sha256": sha256(canonical_bytes(source_state)),
        "iroha_git_sha": iroha_state.get("iroha_git_sha"),
        "bundle_name": iroha_state.get("bundle_name"),
        "checksums_sha256": iroha_state.get("checksums_sha256"),
        "manifest_sha256": iroha_state.get("manifest_sha256"),
        "iroha3d_sha256": iroha_state.get("iroha3d_sha256"),
        "iroha_sha256": iroha_state.get("iroha_sha256"),
        "kagami_sha256": iroha_state.get("kagami_sha256"),
        "archive_sha256": iroha_state.get("archive_sha256"),
        "archive_sidecar_sha256": iroha_state.get("archive_sidecar_sha256"),
        "iroha3d_features": FEATURES,
    }
    if not HEX40.fullmatch(str(expected_bindings["soraswap_tree_sha"] or "")):
        fail("SoraSwap RC tree SHA is invalid")
    if not HEX40.fullmatch(str(expected_bindings["iroha_git_sha"] or "")):
        fail("Iroha candidate SHA is invalid")
    if not isinstance(expected_bindings["bundle_name"], str) \
            or re.fullmatch(r"taira-rollout-[A-Za-z0-9._-]+-release", expected_bindings["bundle_name"]) is None:
        fail("Iroha candidate bundle name is invalid")
    for key in (
        "checksums_sha256", "manifest_sha256", "iroha3d_sha256", "iroha_sha256",
        "kagami_sha256", "archive_sha256", "archive_sidecar_sha256",
    ):
        if not HEX64.fullmatch(str(expected_bindings[key] or "")):
            fail(f"Iroha candidate {key} is invalid")
    if not isinstance(approval.get("bindings"), dict) or set(approval["bindings"]) != BINDING_KEYS \
            or approval.get("bindings") != expected_bindings:
        fail("approval bindings do not match the exact chain, RC source, or Iroha bundle")

    authorities = {
        "signer": require_real_reference(args.signer_authority, "production signer authority"),
        "oracle": require_real_reference(args.oracle_authority, "production oracle authority"),
        "admin": require_real_reference(args.admin_authority, "production admin authority"),
        "treasury": require_real_reference(args.treasury_authority, "production treasury authority"),
        "bridge": require_real_reference(args.bridge_authority, "production bridge authority"),
    }
    if not isinstance(approval.get("authorities"), dict) or set(approval["authorities"]) != AUTHORITY_KEYS \
            or approval.get("authorities") != authorities:
        fail("approval authorities do not match the production runtime inputs")
    if len(set(authorities.values())) != len(authorities):
        fail("production signer, oracle, admin, treasury, and bridge authorities must be distinct")
    try:
        minimum_fee = Decimal(args.minimum_fee_balance)
    except InvalidOperation:
        fail("minimum fee balance is not a decimal")
    if not CANONICAL_DECIMAL.fullmatch(args.minimum_fee_balance) or minimum_fee <= 0:
        fail("minimum fee balance must be an explicit positive canonical decimal")
    if approval.get("minimum_fee_balance") != args.minimum_fee_balance:
        fail("approval minimum fee balance does not match the production gate")

    controls = approval.get("controls")
    if not isinstance(controls, dict) or set(controls) != CONTROL_KEYS:
        fail("approval must bind every custody/rotation/admin/pause/rollback/monitoring/incident-response reference")
    controls = {key: require_real_reference(controls[key], f"{key} control reference") for key in sorted(CONTROL_KEYS)}

    observation = approval.get("observation")
    if not isinstance(observation, dict) or set(observation) != OBSERVATION_KEYS:
        fail("approval observation policy is malformed")
    monitoring_url = require_https_url(observation.get("monitoring_snapshot_url"), "monitoring snapshot URL")
    monitoring_parts = urlsplit(monitoring_url)
    monitoring_origin = normalized_https_origin(monitoring_parts, "monitoring snapshot URL")
    if monitoring_origin not in origins:
        fail("approval monitoring endpoint is not anchored by the signed RC policy")
    maximum_oracle_age = observation.get("maximum_oracle_age_seconds")
    if not isinstance(maximum_oracle_age, int) or isinstance(maximum_oracle_age, bool) or not 1 <= maximum_oracle_age <= 300:
        fail("approval oracle freshness bound must be between 1 and 300 seconds")
    if observation.get("minimum_fee_balance") != args.minimum_fee_balance:
        fail("approval observation minimum fee does not match the cutover minimum")
    if observation.get("maximum_monitoring_sample_age_seconds") != policy_observation["maximum_monitoring_sample_age_seconds"]:
        fail("approval monitoring freshness bound differs from the RC trust policy")
    validator_count = observation.get("validator_count")
    if not isinstance(validator_count, int) or isinstance(validator_count, bool) \
            or validator_count < policy_observation["minimum_validator_count"]:
        fail("approval validator count is below the RC trust policy minimum")
    if observation.get("maximum_finality_age_ms") != policy_observation["maximum_finality_age_ms"]:
        fail("approval finality-age bound differs from the RC trust policy")
    if observation.get("derivatives_pause_mode") != policy_observation["derivatives_pause_mode"]:
        fail("approval derivatives pause mode is not the fail-closed external control")
    for key in (
        "validator_set_sha256", "oracle_watch_sha256", "balance_watch_sha256",
        "readonly_route_set_sha256", "trader_api_routes_sha256",
    ):
        require_hash(observation.get(key), f"approval observation {key}")
    trader_probe_url = require_https_url(
        observation.get("trader_api_probe_url"), "approved trader API probe URL"
    )
    trader_cid = observation.get("trader_api_content_cid")
    torii_origin = require_https_origin(chain_fingerprint["torii_url"], "production chain Torii URL")
    if monitoring_origin == torii_origin:
        fail("monitoring snapshot origin must be independent from the production Torii origin")
    trader_parts = urlsplit(trader_probe_url)
    expected_trader_path = f"/v1/app-api/cid/{trader_cid}"
    if not isinstance(trader_cid, str) or CONTENT_CID.fullmatch(trader_cid) is None \
            or normalized_https_origin(trader_parts, "approved trader API probe URL") != torii_origin \
            or trader_parts.path != expected_trader_path:
        fail("approved trader API probe URL/CID binding is invalid")
    trader_app_id = observation.get("trader_api_app_id")
    if not isinstance(trader_app_id, str) or APP_ID.fullmatch(trader_app_id) is None:
        fail("approved trader API app id is invalid")

    signatures = approval.get("signatures")
    if not isinstance(signatures, list) or len(signatures) < policy["required_signature_count"]:
        fail("approval does not contain the required signature threshold")
    payload = dict(approval)
    payload.pop("signatures", None)
    message = canonical_bytes(payload)
    seen_ids: set[str] = set()
    signed_roles: set[str] = set()
    signature_evidence = []
    for signature in signatures:
        if not isinstance(signature, dict) or set(signature) != {"approver_id", "signature_base64"}:
            fail("approval signature entry is malformed")
        approver_id = require_approver_id(signature.get("approver_id"), "approval signer id")
        if approver_id not in approvers or approver_id in seen_ids:
            fail("approval contains an untrusted or duplicate signer")
        if approver_id in authorities.values():
            fail("cutover approver is not independent from a production authority")
        seen_ids.add(approver_id)
        approver = approvers[approver_id]
        signature_hash = validate_signature(
            approver_id, approver["public_key"], signature.get("signature_base64"), message
        )
        signed_roles.add(approver["role"])
        signature_evidence.append({
            "approver_id": approver_id,
            "role": approver["role"],
            "public_key_sha256": approver["key_sha256"],
            "signature_sha256": signature_hash,
        })
    if len(seen_ids) < policy["required_signature_count"] or not required_roles <= signed_roles:
        fail("approval signatures do not satisfy the independent role threshold")
    if review_identity not in seen_ids:
        fail("recorded review identity did not sign the approval")

    stable_state = {
        "schema": "soraswap-production-cutover-approval-state/v1",
        "environment": "production",
        "approval_id": approval_id,
        "policy_id": policy["policy_id"],
        "policy_sha256": policy_hash,
        "approval_sha256": sha256(approval_bytes),
        "approval_payload_sha256": sha256(message),
        "issued_at": approval["issued_at"],
        "expires_at": approval["expires_at"],
        "review": review,
        "bindings": expected_bindings,
        "authorities": authorities,
        "minimum_fee_balance": args.minimum_fee_balance,
        "controls": controls,
        "observation": {
            **observation,
            "duration_seconds": 1800,
            "interval_seconds": 30,
            "minimum_samples": 61,
        },
        "signatures": sorted(signature_evidence, key=lambda item: item["approver_id"]),
    }
    if args.write_evidence:
        evidence_path = Path(os.path.abspath(args.write_evidence))
        expected_parent = root / "deployments" / "production"
        if evidence_path != expected_parent / "cutover_approval.latest.json":
            fail("cutover approval evidence must use deployments/production/cutover_approval.latest.json")
        evidence = {
            **stable_state,
            "schema": EVIDENCE_SCHEMA,
            "status": "verified",
            "generated_at": now.strftime("%Y%m%dT%H%M%SZ"),
            "test_only": False,
        }
        atomic_create(evidence_path, evidence)
        verify_evidence(evidence_path, root, stable_state)
    if args.verify_evidence:
        verify_evidence(Path(args.verify_evidence), root, stable_state)
    print(json.dumps(stable_state, sort_keys=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
