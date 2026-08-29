#!/usr/bin/env python3
"""Observe the production cutover for an immutable thirty-minute window."""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import json
import os
import re
import secrets
import stat
import sys
import time
import tomllib
import urllib.error
import urllib.request
from decimal import Decimal, InvalidOperation
from pathlib import Path
from urllib.parse import urljoin, urlsplit


DURATION_SECONDS = 1800
INTERVAL_SECONDS = 30
MINIMUM_SAMPLES = 61
TEST_SENTINEL = "soraswap-internal-observation-fixture-v1"
SCHEMA = "soraswap-production-observation-evidence/v1"
FIXTURE_SCHEMA = "soraswap-production-observation-fixture/v1"
MONITORING_SCHEMA = "soraswap-production-monitoring-snapshot/v1"
HEX64 = re.compile(r"[0-9a-f]{64}")
HASH_LITERAL = re.compile(r"hash:[0-9A-F]{64}#[0-9A-F]{4}")
UPPER_HEX64 = re.compile(r"[0-9A-F]{64}")
CANONICAL_DECIMAL = re.compile(r"(?:0|[1-9][0-9]*)(?:\.[0-9]*[1-9])?")
WATCH_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:@/#-]{2,127}")
SAMPLE_KEYS = {
    "sampled_at", "monitoring_sampled_at", "monitoring_sequence",
    "status_block_height", "status_queue_size", "status_queue_queued",
    "status_queue_inflight", "status_time_since_last_block_ms",
    "sumeragi", "validators", "validator_set_sha256",
    "api_failures", "oracles", "balances", "readonly_routes", "trader_api",
    "shared_derivatives_regression", "derivatives_pause_mode",
}
VALIDATOR_KEYS = {
    "id", "status_block_height", "finality_age_ms", "status_queue_size",
    "status_queue_queued", "status_queue_inflight", "sumeragi", "api_failures",
}
MONITORING_KEYS = {
    "schema", "sampled_at", "sequence", "bindings", "validator_set_sha256",
    "validators", "api_failures", "oracles", "balances", "readonly_routes",
    "shared_derivatives_regression",
}
SUMERAGI_STATUS_REQUIRED_KEYS = {
    "protocol_version", "node_fingerprint", "build_fingerprint", "config_fingerprint",
    "restart_required", "height_context_id", "height", "view", "phase", "leader",
    "body_state", "last_committed_height", "height_context", "liveness",
}
SUMERAGI_STATUS_OPTIONAL_KEYS = {
    "locked_prepare_qc", "highest_prepare_qc", "last_timeout_certificate",
    "pending_persistence_id", "last_committed_subject", "last_commit_qc",
}
SUMERAGI_PHASES = {
    "awaiting_proposal", "reconstructing_payload", "validating_payload", "prepare",
    "commit", "pending_apply",
}
SUMERAGI_BODY_STATES = {
    "missing", "reconstructing", "stored", "validated", "pending_apply", "applied",
}
SUMERAGI_WORK_STAGES = {"idle", "queued", "running", "complete"}
SUMERAGI_WORK_KEYS = {
    "candidate", "body_recovery", "body_store", "validation", "application",
    "successor_height",
}
SUMERAGI_QUEUE_KINDS = {
    "ingress", "deferred_normal", "deferred_progress", "deferred_completion",
    "runtime_normal", "runtime_progress", "runtime_completion", "effect_completion",
    "network_ingress", "effect_dispatch",
}
SUMERAGI_BLOCKERS = {
    "missing_proposal", "body_unavailable", "prepare_quorum_missing",
    "commit_quorum_missing", "timeout_certificate_missing", "scheduler_starvation",
    "application_pending", "successor_activation_pending", "local_control_pending",
}
SUMERAGI_IGNORE_REASONS = {
    "wrong_height", "wrong_view", "stale_generation", "busy", "duplicate",
    "no_matching_work", "observer", "view_closed", "already_decided",
    "recovery_pending", "irrelevant_view", "unsafe_proposal",
}
SUMERAGI_OUTBOUND_INTENT_KINDS = {
    "proposal", "prepare_vote", "commit_vote", "prepare_qc", "commit_qc",
    "timeout_vote", "timeout_certificate",
}
SUMERAGI_OUTBOUND_INTENT_STAGES = {
    "pending_persistence", "pending_signature", "queued", "sent",
}
SUMERAGI_PROGRESS_TRANSITIONS = {
    "proposal_admitted", "body_available", "body_stored", "body_validated",
    "prepare_vote_admitted", "commit_vote_admitted", "timeout_vote_admitted",
    "prepare_quorum", "lock_installed", "commit_quorum",
    "timeout_certificate_installed", "decision_persisted", "applied",
    "successor_height_activated", "recovery_replayed",
}
SUMERAGI_NATIVE_AMX_EMPTY_ROOT = (
    "hash:45A5D35A09D284480FBA74A402D7F303B82DA0C153FC1E1083AEFC822ED07C2D#7C0F"
)
SUMERAGI_UINT32_MAX = (1 << 32) - 1
SUMERAGI_UINT64_MAX = (1 << 64) - 1
SUMERAGI_LIVENESS_REQUIRED_KEYS = {
    "generation", "prepare_quorums", "commit_quorums", "timeout_quorums",
    "outbound_intents", "work", "queues", "no_progress_age_ms", "ignore_counts",
}
SUMERAGI_LIVENESS_OPTIONAL_KEYS = {"last_progress", "blocker"}
FORBIDDEN_OVERRIDE_NAMES = (
    "SORASWAP_PRODUCTION_OBSERVATION_DURATION_SECS",
    "SORASWAP_PRODUCTION_OBSERVATION_INTERVAL_SECS",
    "SORASWAP_PRODUCTION_OBSERVATION_MINIMUM_SAMPLES",
    "SORASWAP_PRODUCTION_OBSERVATION_FIXTURE",
    "SORASWAP_PRODUCTION_OBSERVATION_TEST_MODE",
    "SORASWAP_PRODUCTION_OBSERVATION_TEST_TOKEN",
    "SORASWAP_PRODUCTION_OBSERVATION_SAMPLE_COMMAND",
)


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"production observation failed: {message}")


def canonical_bytes(value: object) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def identity(metadata: os.stat_result) -> tuple[int, ...]:
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
    return metadata.st_dev, metadata.st_ino, metadata.st_mode


def open_directory_chain(path: Path, label: str) -> tuple[list[int], list[tuple[str, tuple[int, ...]]]]:
    path = Path(os.path.abspath(path))
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
            if directory_identity(parent_before) != directory_identity(parent_after) \
                    or not stat.S_ISDIR(child_metadata.st_mode) \
                    or directory_identity(child_metadata) != directory_identity(named_metadata):
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
        close_descriptors(descriptors)
        fail(f"{label} path is missing, linked, or changed")


def close_descriptors(descriptors: list[int]) -> None:
    for descriptor in reversed(descriptors):
        try:
            os.close(descriptor)
        except OSError:
            pass


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
    if not stat.S_ISREG(before.st_mode) or identity(before) != identity(named_before):
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
        chunks = []
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        after = os.fstat(descriptor)
        named_after = os.stat(path.name, dir_fd=parent_descriptor, follow_symlinks=False)
        parent_after = os.fstat(parent_descriptor)
        verify_directory_chain(descriptors, links, label)
    except OSError:
        fail(f"{label} changed while it was read")
    finally:
        try:
            os.close(descriptor)
        except OSError:
            pass
        close_descriptors(descriptors)
    if identity(before) != identity(after) or identity(before) != identity(named_after) \
            or directory_identity(parent_before) != directory_identity(parent_after):
        fail(f"{label} changed while it was read")
    return b"".join(chunks), before


def json_object(data: bytes, label: str) -> dict:
    try:
        value = json.loads(data.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError):
        fail(f"{label} is not valid UTF-8 JSON")
    if not isinstance(value, dict):
        fail(f"{label} must be a JSON object")
    return value


def state(raw: str, label: str) -> dict:
    try:
        value = json.loads(raw)
    except json.JSONDecodeError:
        fail(f"{label} is not valid JSON")
    if not isinstance(value, dict):
        fail(f"{label} must be a JSON object")
    return value


def parse_time(value: object, label: str) -> dt.datetime:
    if not isinstance(value, str):
        fail(f"{label} is missing")
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        try:
            parsed = dt.datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(
                tzinfo=dt.timezone.utc
            )
        except ValueError:
            fail(f"{label} is not a UTC timestamp")
    if parsed.tzinfo is None:
        fail(f"{label} must include a timezone")
    return parsed.astimezone(dt.timezone.utc)


def chain_fingerprint(value: dict) -> dict | None:
    candidate = value.get("chain_fingerprint")
    if not isinstance(candidate, dict):
        candidate = value
    try:
        torii_url = strict_https_url(candidate.get("torii_url"), "chain fingerprint Torii URL", True)
    except SystemExit:
        return None
    result = {
        "torii_url": torii_url,
        "chain": candidate.get("chain"),
        "block_1_hash": candidate.get("block_1_hash"),
    }
    if not all(isinstance(item, str) and item for item in result.values()):
        return None
    return result


def strict_https_url(value: object, label: str, root_only: bool = False) -> str:
    if not isinstance(value, str) or not value:
        fail(f"{label} is missing")
    try:
        parsed = urlsplit(value)
        port = parsed.port
    except ValueError:
        fail(f"{label} is invalid")
    if parsed.scheme.lower() != "https" or not parsed.hostname:
        fail(f"{label} must be an absolute HTTPS URL")
    if parsed.username is not None or parsed.password is not None:
        fail(f"{label} must not contain userinfo")
    if parsed.query or parsed.fragment:
        fail(f"{label} must not contain a query or fragment")
    if root_only and parsed.path not in {"", "/"}:
        fail(f"{label} must be a root URL")
    host = parsed.hostname.lower()
    host_literal = f"[{host}]" if ":" in host else host
    origin = f"https://{host_literal}"
    if port is not None and port != 443:
        origin += f":{port}"
    normalized_path = parsed.path or "/"
    return origin if root_only else origin + normalized_path


def url_origin(value: str, label: str) -> str:
    normalized = strict_https_url(value, label)
    parsed = urlsplit(normalized)
    return f"{parsed.scheme}://{parsed.netloc}"


def load_client_config(path: Path, fingerprint: dict, root: Path) -> tuple[str, str | None]:
    path = Path(os.path.abspath(path))
    if path != root / "config/production/production.client.toml":
        fail("production observer must use config/production/production.client.toml")
    raw, metadata = read_regular(path, "production observer client config", 0o600)
    try:
        config = tomllib.loads(raw.decode("utf-8"))
    except (UnicodeError, tomllib.TOMLDecodeError):
        fail("production observer client config is not valid UTF-8 TOML")
    torii = strict_https_url(config.get("torii_url"), "client config Torii URL", True)
    approved_torii = strict_https_url(fingerprint.get("torii_url"), "approved Torii URL", True)
    if torii != approved_torii or config.get("chain") != fingerprint.get("chain"):
        fail("observer client config does not match the approved production chain")
    auth = config.get("basic_auth")
    if auth is None:
        return torii, None
    if not isinstance(auth, dict) or set(auth) != {"web_login", "password"}:
        fail("client config basic_auth must contain only web_login and password")
    login = auth.get("web_login")
    password = auth.get("password")
    if not isinstance(login, str) or not isinstance(password, str) or not login or not password:
        fail("client config Basic auth values must be non-empty strings")
    if ":" in login or any(ord(character) < 0x20 or ord(character) == 0x7F for character in login + password):
        fail("client config Basic auth values are unsafe")
    token = base64.b64encode(f"{login}:{password}".encode("utf-8")).decode("ascii")
    return torii, f"Basic {token}"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):  # type: ignore[no-untyped-def]
        return None


NO_REDIRECT_OPENER = urllib.request.build_opener(NoRedirect())


def fetch_json_value(
    url: str, torii_origin: str, basic_authorization: str | None, allow_torii_auth: bool
) -> object:
    normalized_url = strict_https_url(url, "observation endpoint")
    request_origin = url_origin(normalized_url, "observation endpoint")
    headers = {
        "Accept": "application/json",
        "User-Agent": "soraswap-production-observer/1",
    }
    if allow_torii_auth and basic_authorization is not None:
        if request_origin != torii_origin:
            raise RuntimeError("refused to send Torii Basic auth to a different origin")
        headers["Authorization"] = basic_authorization
    request = urllib.request.Request(normalized_url, headers=headers)
    try:
        with NO_REDIRECT_OPENER.open(request, timeout=10) as response:
            if response.status != 200:
                raise ValueError(f"HTTP {response.status}")
            content_type = response.headers.get_content_type().lower()
            if content_type != "application/json" and not content_type.endswith("+json"):
                raise ValueError(f"unexpected content type {content_type}")
            raw = response.read(4 * 1024 * 1024 + 1)
    except (OSError, urllib.error.URLError, urllib.error.HTTPError, ValueError) as error:
        raise RuntimeError(str(error)) from error
    if len(raw) > 4 * 1024 * 1024:
        raise RuntimeError("response exceeds 4 MiB")
    try:
        value = json.loads(raw.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError) as error:
        raise RuntimeError("response is not valid JSON") from error
    return value


def require_nonnegative_integer(value: object, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        fail(f"{label} must be a nonnegative integer")
    return value


def require_positive_integer(value: object, label: str) -> int:
    value = require_nonnegative_integer(value, label)
    if value < 1:
        fail(f"{label} must be a positive integer")
    return value


def require_hash(value: object, label: str) -> str:
    if not isinstance(value, str) or HEX64.fullmatch(value) is None:
        fail(f"{label} must be 64 lowercase hexadecimal characters")
    return value


def require_canonical_decimal(value: object, label: str) -> Decimal:
    if not isinstance(value, str) or CANONICAL_DECIMAL.fullmatch(value) is None:
        fail(f"{label} must be a canonical nonnegative decimal string")
    try:
        return Decimal(value)
    except InvalidOperation:
        fail(f"{label} is not numeric")


def watch_hash(items: list[dict], fields: tuple[str, ...]) -> str:
    identities = [{field: item[field] for field in fields} for item in items]
    return sha256(canonical_bytes(identities))


def require_object(value: object, label: str) -> dict:
    if not isinstance(value, dict):
        fail(f"{label} must be a JSON object")
    return value


def require_hash_literal(value: object, label: str) -> str:
    if not isinstance(value, str) or HASH_LITERAL.fullmatch(value) is None:
        fail(f"{label} must be a canonical Iroha hash literal")
    return value


def require_tagged_unit(
    value: object,
    *,
    label: str,
    tag: str,
    allowed: set[str],
) -> str:
    if not isinstance(value, dict):
        fail(f"{label} is not the exact current tagged-enum shape")
    payload = value
    if set(payload) != {tag, "details"} or payload.get("details") is not None \
            or payload.get(tag) not in allowed:
        fail(f"{label} is not the exact current tagged-enum shape")
    return payload[tag]


def require_exact_object(
    value: object,
    label: str,
    required: set[str],
    optional: set[str] | None = None,
) -> dict:
    payload = require_object(value, label)
    optional = optional or set()
    keys = set(payload)
    if not required <= keys or not keys <= required | optional:
        fail(f"{label} fields do not match the current Iroha API")
    return payload


def require_bounded_integer(
    value: object,
    label: str,
    maximum: int,
    *,
    positive: bool = False,
) -> int:
    integer = (
        require_positive_integer(value, label)
        if positive
        else require_nonnegative_integer(value, label)
    )
    if integer > maximum:
        fail(f"{label} exceeds the current Iroha integer bound")
    return integer


def validate_height_context_id(value: object, label: str) -> list:
    if not isinstance(value, list) or len(value) != 1:
        fail(f"{label} must be the exact one-hash tuple")
    require_hash_literal(value[0], label)
    return value


def validate_consensus_round(value: object, label: str) -> dict:
    round_status = require_exact_object(
        value, label, {"context_id", "height", "view"}
    )
    validate_height_context_id(round_status.get("context_id"), f"{label} context_id")
    require_bounded_integer(
        round_status.get("height"), f"{label} height", SUMERAGI_UINT64_MAX, positive=True
    )
    require_bounded_integer(
        round_status.get("view"), f"{label} view", SUMERAGI_UINT64_MAX
    )
    return round_status


def validate_block_subject(value: object, label: str) -> dict:
    subject = require_exact_object(
        value, label, {"parent_block_hash", "block_hash", "payload_hash"}
    )
    parent = subject.get("parent_block_hash")
    if parent is not None:
        require_hash_literal(parent, f"{label} parent_block_hash")
    require_hash_literal(subject.get("block_hash"), f"{label} block_hash")
    require_hash_literal(subject.get("payload_hash"), f"{label} payload_hash")
    return subject


def validate_merkle_tree_commitment(value: object, label: str) -> dict:
    commitment = require_exact_object(value, label, {"root", "leaf_count"})
    require_hash_literal(commitment.get("root"), f"{label} root")
    require_bounded_integer(
        commitment.get("leaf_count"),
        f"{label} leaf_count",
        SUMERAGI_UINT64_MAX,
        positive=True,
    )
    return commitment


def validate_execution_commitment(value: object, label: str) -> dict:
    required = {
        "parent_state_root", "post_state_root", "ordinary_writes_root",
        "topup_anchor_root", "topup_anchor_count",
        "native_amx_application_manifest_version",
        "native_amx_application_manifest_root",
        "native_amx_application_manifest_count", "lane_finality_manifest",
        "merge_carrier", "executed_block_wire_len", "executed_block_wire_hash",
    }
    commitment = require_exact_object(value, label, required)
    for field in (
        "parent_state_root", "post_state_root", "ordinary_writes_root",
        "native_amx_application_manifest_root", "executed_block_wire_hash",
    ):
        require_hash_literal(commitment.get(field), f"{label} {field}")

    topup_count = require_bounded_integer(
        commitment.get("topup_anchor_count"), f"{label} topup_anchor_count", 16
    )
    topup_root = commitment.get("topup_anchor_root")
    if topup_root is not None:
        require_hash_literal(topup_root, f"{label} topup_anchor_root")
    if (topup_count == 0) != (topup_root is None):
        fail(f"{label} top-up root/count projection is inconsistent")

    if commitment.get("native_amx_application_manifest_version") != 1:
        fail(f"{label} native AMX application manifest version is not current")
    native_count = require_bounded_integer(
        commitment.get("native_amx_application_manifest_count"),
        f"{label} native_amx_application_manifest_count",
        1024,
    )
    native_root = commitment["native_amx_application_manifest_root"]
    if (native_count == 0) != (native_root == SUMERAGI_NATIVE_AMX_EMPTY_ROOT):
        fail(f"{label} native AMX application manifest root/count is inconsistent")

    lane_manifest = commitment.get("lane_finality_manifest")
    if lane_manifest is not None:
        validate_merkle_tree_commitment(
            lane_manifest, f"{label} lane_finality_manifest"
        )
    merge_carrier = commitment.get("merge_carrier")
    if merge_carrier is not None:
        merge = require_exact_object(
            merge_carrier, f"{label} merge_carrier", {"version", "entry_hash"}
        )
        if merge.get("version") != 1:
            fail(f"{label} merge carrier version is not current")
        require_hash_literal(merge.get("entry_hash"), f"{label} merge_carrier entry_hash")
    require_bounded_integer(
        commitment.get("executed_block_wire_len"),
        f"{label} executed_block_wire_len",
        SUMERAGI_UINT64_MAX,
        positive=True,
    )
    return commitment


def validate_quorum_certificate_ref(value: object, label: str) -> dict:
    certificate = require_exact_object(
        value,
        label,
        {"round", "proposal_round", "phase", "subject", "execution_commitment"},
    )
    validate_consensus_round(certificate.get("round"), f"{label} round")
    validate_consensus_round(
        certificate.get("proposal_round"), f"{label} proposal_round"
    )
    require_tagged_unit(
        certificate.get("phase"),
        label=f"{label} phase",
        tag="phase",
        allowed={"prepare", "commit"},
    )
    validate_block_subject(certificate.get("subject"), f"{label} subject")
    validate_execution_commitment(
        certificate.get("execution_commitment"), f"{label} execution_commitment"
    )
    return certificate


def validate_timeout_certificate_ref(value: object, label: str) -> dict:
    certificate = require_exact_object(
        value, label, {"round", "highest_prepare_qc", "certificate_hash"}
    )
    validate_consensus_round(certificate.get("round"), f"{label} round")
    highest = certificate.get("highest_prepare_qc")
    if highest is not None:
        validate_quorum_certificate_ref(highest, f"{label} highest_prepare_qc")
    require_hash_literal(certificate.get("certificate_hash"), f"{label} certificate_hash")
    return certificate


def validate_partial_quorum_fields(value: dict, label: str) -> tuple[int, int, int, int]:
    signer_count = require_bounded_integer(
        value.get("signer_count"), f"{label} signer_count", 31
    )
    signed_power = require_bounded_integer(
        value.get("signed_power"), f"{label} signed_power", SUMERAGI_UINT64_MAX
    )
    min_signers = require_bounded_integer(
        value.get("min_signers"), f"{label} min_signers", 31, positive=True
    )
    total_power = require_bounded_integer(
        value.get("total_power"),
        f"{label} total_power",
        SUMERAGI_UINT64_MAX,
        positive=True,
    )
    return signer_count, signed_power, min_signers, total_power


def validate_vote_quorum_status(value: object, label: str) -> dict:
    quorum = require_exact_object(
        value,
        label,
        {
            "round", "proposal_round", "subject", "execution_commitment",
            "signer_count", "signed_power", "min_signers", "total_power",
        },
    )
    validate_consensus_round(quorum.get("round"), f"{label} round")
    validate_consensus_round(quorum.get("proposal_round"), f"{label} proposal_round")
    validate_block_subject(quorum.get("subject"), f"{label} subject")
    validate_execution_commitment(
        quorum.get("execution_commitment"), f"{label} execution_commitment"
    )
    validate_partial_quorum_fields(quorum, label)
    return quorum


def validate_timeout_quorum_status(value: object, label: str) -> dict:
    quorum = require_exact_object(
        value,
        label,
        {
            "round", "signer_count", "signed_power", "min_signers", "total_power",
            "certificate_formed",
        },
    )
    validate_consensus_round(quorum.get("round"), f"{label} round")
    validate_partial_quorum_fields(quorum, label)
    if not isinstance(quorum.get("certificate_formed"), bool):
        fail(f"{label} certificate_formed must be boolean")
    return quorum


def validate_outbound_intent_status(value: object, label: str) -> tuple[dict, str]:
    intent = require_exact_object(
        value,
        label,
        {"kind", "round", "stage"},
        {"proposal_round", "subject", "execution_commitment"},
    )
    kind = require_tagged_unit(
        intent.get("kind"),
        label=f"{label} kind",
        tag="kind",
        allowed=SUMERAGI_OUTBOUND_INTENT_KINDS,
    )
    validate_consensus_round(intent.get("round"), f"{label} round")
    require_tagged_unit(
        intent.get("stage"),
        label=f"{label} stage",
        tag="stage",
        allowed=SUMERAGI_OUTBOUND_INTENT_STAGES,
    )
    optional_fields = {"proposal_round", "subject", "execution_commitment"}
    observed_optional = set(intent) & optional_fields
    if kind == "proposal":
        expected_optional = {"proposal_round", "subject"}
    elif kind in {"timeout_vote", "timeout_certificate"}:
        expected_optional = set()
    else:
        expected_optional = optional_fields
    if observed_optional != expected_optional:
        fail(f"{label} fields do not match the current outbound-intent kind")
    if "proposal_round" in intent:
        validate_consensus_round(intent["proposal_round"], f"{label} proposal_round")
    if "subject" in intent:
        validate_block_subject(intent["subject"], f"{label} subject")
    if "execution_commitment" in intent:
        validate_execution_commitment(
            intent["execution_commitment"], f"{label} execution_commitment"
        )
    return intent, kind


def validate_progress_status(value: object, label: str) -> tuple[dict, str]:
    progress = require_exact_object(
        value, label, {"generation", "round", "transition", "age_ms"}
    )
    require_bounded_integer(
        progress.get("generation"), f"{label} generation", SUMERAGI_UINT64_MAX
    )
    validate_consensus_round(progress.get("round"), f"{label} round")
    transition = require_tagged_unit(
        progress.get("transition"),
        label=f"{label} transition",
        tag="transition",
        allowed=SUMERAGI_PROGRESS_TRANSITIONS,
    )
    require_bounded_integer(
        progress.get("age_ms"), f"{label} age_ms", SUMERAGI_UINT64_MAX
    )
    return progress, transition


def validate_sumeragi_v2_status(value: object, label: str) -> dict:
    status = require_object(value, label)
    keys = set(status)
    if not SUMERAGI_STATUS_REQUIRED_KEYS <= keys \
            or not keys <= SUMERAGI_STATUS_REQUIRED_KEYS | SUMERAGI_STATUS_OPTIONAL_KEYS:
        fail(f"{label} fields do not match SumeragiV2Status")
    if status.get("protocol_version") != 4:
        fail(f"{label} protocol_version must be the current Sumeragi v2 protocol version 4")
    for field in ("node_fingerprint", "build_fingerprint", "config_fingerprint"):
        require_hash_literal(status.get(field), f"{label} {field}")
    if not isinstance(status.get("restart_required"), bool):
        fail(f"{label} restart_required must be boolean")
    context_id = validate_height_context_id(
        status.get("height_context_id"), f"{label} height_context_id"
    )
    height = require_bounded_integer(
        status.get("height"), f"{label} height", SUMERAGI_UINT64_MAX, positive=True
    )
    view = require_bounded_integer(
        status.get("view"), f"{label} view", SUMERAGI_UINT64_MAX
    )
    phase = require_tagged_unit(
        status.get("phase"), label=f"{label} phase", tag="phase", allowed=SUMERAGI_PHASES
    )
    leader = require_bounded_integer(
        status.get("leader"), f"{label} leader", SUMERAGI_UINT32_MAX
    )
    body_state = require_tagged_unit(
        status.get("body_state"),
        label=f"{label} body_state",
        tag="state",
        allowed=SUMERAGI_BODY_STATES,
    )
    valid_phase_body = {
        "awaiting_proposal": {"missing"},
        "reconstructing_payload": {"reconstructing"},
        "validating_payload": {"stored"},
        "prepare": {"validated"},
        "commit": {"validated"},
        "pending_apply": {"pending_apply", "applied"},
    }
    if body_state not in valid_phase_body[phase]:
        fail(f"{label} phase/body_state pairing is invalid")
    committed_height = require_bounded_integer(
        status.get("last_committed_height"),
        f"{label} last_committed_height",
        SUMERAGI_UINT64_MAX,
    )
    if phase == "pending_apply":
        if committed_height != height:
            fail(f"{label} pending_apply commit frontier is inconsistent")
    elif committed_height >= height:
        fail(f"{label} active height must be above its committed frontier")

    height_context = require_object(status.get("height_context"), f"{label} height_context")
    if set(height_context) != {
        "epoch", "epoch_end_height", "mode", "epoch_seed", "validator_count", "quorum"
    }:
        fail(f"{label} height_context fields do not match SumeragiV2HeightContextStatus")
    require_bounded_integer(
        height_context.get("epoch"),
        f"{label} height_context epoch",
        SUMERAGI_UINT64_MAX,
    )
    epoch_end = require_bounded_integer(
        height_context.get("epoch_end_height"),
        f"{label} height_context epoch_end_height",
        SUMERAGI_UINT64_MAX,
        positive=True,
    )
    if epoch_end < height:
        fail(f"{label} height_context epoch ends before the active height")
    require_tagged_unit(
        height_context.get("mode"),
        label=f"{label} height_context mode",
        tag="mode",
        allowed={"permissioned", "npos"},
    )
    epoch_seed = height_context.get("epoch_seed")
    if not isinstance(epoch_seed, str) or UPPER_HEX64.fullmatch(epoch_seed) is None:
        fail(f"{label} height_context epoch_seed must be canonical uppercase hex")
    validator_count = require_bounded_integer(
        height_context.get("validator_count"),
        f"{label} height_context validator_count",
        SUMERAGI_UINT32_MAX,
        positive=True,
    )
    if validator_count < 4 or validator_count > 31 or validator_count % 3 != 1:
        fail(f"{label} height_context validator_count is not a bounded 3f+1 roster")
    if leader >= validator_count:
        fail(f"{label} leader is outside the frozen validator roster")
    quorum = require_object(height_context.get("quorum"), f"{label} height_context quorum")
    expected_min_signers = 2 * ((validator_count - 1) // 3) + 1
    if set(quorum) != {"min_signers", "total_power"} \
            or quorum.get("min_signers") != expected_min_signers \
            or quorum.get("total_power") != validator_count:
        fail(f"{label} height_context quorum is not the canonical equal-vote quorum")

    locked_prepare_qc = None
    if "locked_prepare_qc" in status:
        locked_prepare_qc = validate_quorum_certificate_ref(
            status["locked_prepare_qc"], f"{label} locked_prepare_qc"
        )
    highest_prepare_qc = None
    if "highest_prepare_qc" in status:
        highest_prepare_qc = validate_quorum_certificate_ref(
            status["highest_prepare_qc"], f"{label} highest_prepare_qc"
        )

    def validate_active_prepare(certificate: dict, certificate_label: str) -> None:
        round_status = certificate["round"]
        if round_status["context_id"] != context_id:
            fail(f"{certificate_label} context does not match the active height")
        if round_status["height"] != height:
            fail(f"{certificate_label} height does not match the active height")
        if certificate["phase"]["phase"] != "prepare":
            fail(f"{certificate_label} is not a PrepareQC")
        if certificate["proposal_round"] != round_status:
            fail(f"{certificate_label} proposal round differs from its voting round")
        if round_status["view"] > view:
            fail(f"{certificate_label} belongs to a future view")

    if locked_prepare_qc is not None:
        validate_active_prepare(locked_prepare_qc, f"{label} locked_prepare_qc")
    if highest_prepare_qc is not None:
        validate_active_prepare(highest_prepare_qc, f"{label} highest_prepare_qc")
    if locked_prepare_qc is not None and highest_prepare_qc is None:
        fail(f"{label} locked_prepare_qc requires highest_prepare_qc")
    if locked_prepare_qc is not None and highest_prepare_qc is not None:
        locked_view = locked_prepare_qc["round"]["view"]
        highest_view = highest_prepare_qc["round"]["view"]
        if locked_view > highest_view \
                or (locked_view == highest_view and locked_prepare_qc != highest_prepare_qc):
            fail(f"{label} PrepareQC lock/highest relationship is invalid")
    if phase == "commit" and locked_prepare_qc is None:
        fail(f"{label} commit phase does not carry its persisted PrepareQC lock")
    if phase == "prepare" and locked_prepare_qc is not None:
        fail(f"{label} prepare phase unexpectedly carries a PrepareQC lock")

    if "last_timeout_certificate" in status:
        timeout = validate_timeout_certificate_ref(
            status["last_timeout_certificate"], f"{label} last_timeout_certificate"
        )
        timeout_round = timeout["round"]
        if timeout_round["context_id"] != context_id \
                or timeout_round["height"] != height \
                or timeout_round["view"] >= view:
            fail(f"{label} last_timeout_certificate does not precede the active view")
        timeout_highest = timeout["highest_prepare_qc"]
        if timeout_highest is not None:
            validate_active_prepare(
                timeout_highest, f"{label} last_timeout_certificate highest_prepare_qc"
            )
            if timeout_highest["round"]["view"] > timeout_round["view"]:
                fail(f"{label} last_timeout_certificate carries a future PrepareQC")

    if "pending_persistence_id" in status:
        require_bounded_integer(
            status["pending_persistence_id"],
            f"{label} pending_persistence_id",
            SUMERAGI_UINT64_MAX,
            positive=True,
        )
    last_committed_subject = None
    if "last_committed_subject" in status:
        last_committed_subject = validate_block_subject(
            status["last_committed_subject"], f"{label} last_committed_subject"
        )
    last_commit_qc = None
    if "last_commit_qc" in status:
        last_commit_qc = require_exact_object(
            status["last_commit_qc"],
            f"{label} last_commit_qc",
            {
                "certificate", "validator_count", "signer_count", "min_signers",
                "signed_power", "total_power",
            },
        )
        commit_certificate = validate_quorum_certificate_ref(
            last_commit_qc.get("certificate"), f"{label} last_commit_qc certificate"
        )
        commit_validator_count = require_bounded_integer(
            last_commit_qc.get("validator_count"),
            f"{label} last_commit_qc validator_count",
            31,
            positive=True,
        )
        commit_signer_count, commit_signed_power, commit_min_signers, commit_total_power = (
            validate_partial_quorum_fields(last_commit_qc, f"{label} last_commit_qc")
        )
        canonical_commit_min = 2 * ((commit_validator_count - 1) // 3) + 1
        if commit_validator_count < 4 or commit_validator_count % 3 != 1 \
                or commit_min_signers != canonical_commit_min \
                or commit_signer_count != commit_min_signers \
                or commit_signer_count > commit_validator_count \
                or commit_signed_power != commit_signer_count \
                or commit_total_power != commit_validator_count:
            fail(f"{label} last_commit_qc quorum projection is invalid")
        if commit_certificate["phase"]["phase"] != "commit" \
                or commit_certificate["round"]["height"] != committed_height \
                or commit_certificate["proposal_round"] != commit_certificate["round"]:
            fail(f"{label} last_commit_qc certificate does not authenticate the commit frontier")
        if committed_height == height \
                and commit_certificate["round"]["context_id"] != context_id:
            fail(f"{label} last_commit_qc context differs from the active commit frontier")
        if commit_certificate["round"]["context_id"] == context_id \
                and (
                    commit_validator_count != validator_count
                    or commit_min_signers != expected_min_signers
                    or commit_total_power != validator_count
                ):
            fail(f"{label} last_commit_qc quorum differs from the active height context")

    if (last_committed_subject is None) != (last_commit_qc is None):
        fail(f"{label} commit frontier authentication is incomplete")
    if committed_height == 0 and last_committed_subject is not None:
        fail(f"{label} genesis commit frontier unexpectedly carries authentication")
    if last_commit_qc is not None:
        if last_commit_qc["certificate"]["subject"] != last_committed_subject:
            fail(f"{label} last_commit_qc subject differs from the commit frontier")
    if phase == "pending_apply" \
            and (last_committed_subject is None or last_commit_qc is None):
        fail(f"{label} pending_apply commit frontier is unauthenticated")

    liveness = require_object(status.get("liveness"), f"{label} liveness")
    liveness_keys = set(liveness)
    if not SUMERAGI_LIVENESS_REQUIRED_KEYS <= liveness_keys \
            or not liveness_keys <= SUMERAGI_LIVENESS_REQUIRED_KEYS | SUMERAGI_LIVENESS_OPTIONAL_KEYS:
        fail(f"{label} liveness fields do not match SumeragiV2LivenessStatus")
    generation = require_bounded_integer(
        liveness.get("generation"),
        f"{label} liveness generation",
        SUMERAGI_UINT64_MAX,
    )

    def validate_liveness_round(
        round_status: dict, round_label: str, *, allow_future_finality: bool = False
    ) -> None:
        if round_status["context_id"] != context_id or round_status["height"] != height:
            fail(f"{round_label} does not belong to the active height context")
        if not allow_future_finality and round_status["view"] > view:
            fail(f"{round_label} belongs to a future view")

    for field, maximum in (
        ("prepare_quorums", 31), ("commit_quorums", 32), ("timeout_quorums", 31),
        ("outbound_intents", 7),
    ):
        rows = liveness.get(field)
        if not isinstance(rows, list) or len(rows) > maximum:
            fail(f"{label} liveness {field} must be a bounded array of current typed records")

    for field in ("prepare_quorums", "commit_quorums"):
        for index, raw_quorum in enumerate(liveness[field], 1):
            quorum_status = validate_vote_quorum_status(
                raw_quorum, f"{label} liveness {field} {index}"
            )
            validate_liveness_round(
                quorum_status["round"], f"{label} liveness {field} {index} round"
            )
            validate_liveness_round(
                quorum_status["proposal_round"],
                f"{label} liveness {field} {index} proposal_round",
            )
            signer_count, signed_power, min_signers, total_power = (
                validate_partial_quorum_fields(
                    quorum_status, f"{label} liveness {field} {index}"
                )
            )
            if quorum_status["proposal_round"] != quorum_status["round"] \
                    or signer_count > validator_count \
                    or signed_power != signer_count \
                    or min_signers != expected_min_signers \
                    or total_power != validator_count:
                fail(f"{label} liveness {field} {index} quorum projection is invalid")

    for index, raw_quorum in enumerate(liveness["timeout_quorums"], 1):
        quorum_status = validate_timeout_quorum_status(
            raw_quorum, f"{label} liveness timeout_quorums {index}"
        )
        validate_liveness_round(
            quorum_status["round"], f"{label} liveness timeout_quorums {index} round"
        )
        signer_count, signed_power, min_signers, total_power = (
            validate_partial_quorum_fields(
                quorum_status, f"{label} liveness timeout_quorums {index}"
            )
        )
        if signer_count > validator_count \
                or signed_power != signer_count \
                or min_signers != expected_min_signers \
                or total_power != validator_count \
                or (quorum_status["certificate_formed"] and signer_count < min_signers):
            fail(f"{label} liveness timeout_quorums {index} quorum projection is invalid")

    for index, raw_intent in enumerate(liveness["outbound_intents"], 1):
        intent, intent_kind = validate_outbound_intent_status(
            raw_intent, f"{label} liveness outbound_intents {index}"
        )
        validate_liveness_round(
            intent["round"],
            f"{label} liveness outbound_intents {index} round",
            allow_future_finality=intent_kind == "commit_qc",
        )
        if "proposal_round" in intent:
            validate_liveness_round(
                intent["proposal_round"],
                f"{label} liveness outbound_intents {index} proposal_round",
                allow_future_finality=True,
            )
            if intent["proposal_round"] != intent["round"]:
                fail(f"{label} liveness outbound_intents {index} proposal round is invalid")
    work = require_object(liveness.get("work"), f"{label} liveness work")
    if set(work) != SUMERAGI_WORK_KEYS:
        fail(f"{label} liveness work fields do not match SumeragiV2WorkStatus")
    for field in SUMERAGI_WORK_KEYS:
        require_tagged_unit(
            work.get(field),
            label=f"{label} liveness work {field}",
            tag="stage",
            allowed=SUMERAGI_WORK_STAGES,
        )
    queues = liveness.get("queues")
    if not isinstance(queues, list) or len(queues) > len(SUMERAGI_QUEUE_KINDS):
        fail(f"{label} liveness queues are malformed")
    observed_queues: set[str] = set()
    for index, raw_queue in enumerate(queues, 1):
        queue = require_object(raw_queue, f"{label} liveness queue {index}")
        if set(queue) not in (
            {"queue", "depth", "capacity", "service_debt"},
            {"queue", "depth", "capacity", "oldest_age_ms", "service_debt"},
        ):
            fail(f"{label} liveness queue {index} fields do not match SumeragiV2QueueStatus")
        queue_kind = require_tagged_unit(
            queue.get("queue"),
            label=f"{label} liveness queue {index} kind",
            tag="queue",
            allowed=SUMERAGI_QUEUE_KINDS,
        )
        if queue_kind in observed_queues:
            fail(f"{label} liveness queue kinds are duplicated")
        observed_queues.add(queue_kind)
        depth = require_bounded_integer(
            queue.get("depth"),
            f"{label} liveness queue {index} depth",
            SUMERAGI_UINT32_MAX,
        )
        capacity = require_bounded_integer(
            queue.get("capacity"),
            f"{label} liveness queue {index} capacity",
            SUMERAGI_UINT32_MAX,
            positive=True,
        )
        require_bounded_integer(
            queue.get("service_debt"),
            f"{label} liveness queue {index} service_debt",
            SUMERAGI_UINT64_MAX,
        )
        if depth > capacity or (depth == 0) != ("oldest_age_ms" not in queue):
            fail(f"{label} liveness queue {index} occupancy is inconsistent")
        if "oldest_age_ms" in queue:
            require_bounded_integer(
                queue["oldest_age_ms"],
                f"{label} liveness queue {index} oldest_age_ms",
                SUMERAGI_UINT64_MAX,
            )
    require_bounded_integer(
        liveness.get("no_progress_age_ms"),
        f"{label} liveness no_progress_age_ms",
        SUMERAGI_UINT64_MAX,
    )
    if "blocker" in liveness:
        require_tagged_unit(
            liveness["blocker"],
            label=f"{label} liveness blocker",
            tag="blocker",
            allowed=SUMERAGI_BLOCKERS,
        )
    ignore_counts = liveness.get("ignore_counts")
    if not isinstance(ignore_counts, list) or len(ignore_counts) > len(SUMERAGI_IGNORE_REASONS):
        fail(f"{label} liveness ignore_counts are malformed")
    observed_reasons: set[str] = set()
    for index, raw_entry in enumerate(ignore_counts, 1):
        entry = require_object(raw_entry, f"{label} liveness ignore count {index}")
        if set(entry) != {"reason", "count"}:
            fail(f"{label} liveness ignore count {index} fields are malformed")
        reason = require_tagged_unit(
            entry.get("reason"),
            label=f"{label} liveness ignore count {index} reason",
            tag="reason",
            allowed=SUMERAGI_IGNORE_REASONS,
        )
        if reason in observed_reasons:
            fail(f"{label} liveness ignore reasons are duplicated")
        observed_reasons.add(reason)
        require_bounded_integer(
            entry.get("count"),
            f"{label} liveness ignore count {index}",
            SUMERAGI_UINT64_MAX,
        )
    if "last_progress" in liveness:
        progress, transition = validate_progress_status(
            liveness["last_progress"], f"{label} liveness last_progress"
        )
        validate_liveness_round(
            progress["round"],
            f"{label} liveness last_progress round",
            allow_future_finality=transition in {"commit_quorum", "decision_persisted"},
        )
        if progress["generation"] > generation:
            fail(f"{label} liveness last_progress belongs to a future generation")
    return status


def require_healthy_sumeragi_v2_status(status: dict, label: str, maximum_age_ms: int) -> None:
    if status["restart_required"]:
        fail(f"{label} requires a Sumeragi restart")
    liveness = status["liveness"]
    if "blocker" in liveness:
        fail(f"{label} reports a Sumeragi v2 liveness blocker")
    if liveness["no_progress_age_ms"] > maximum_age_ms:
        fail(f"{label} Sumeragi v2 no-progress age exceeded the approved maximum")
    for queue in liveness["queues"]:
        if queue["depth"] >= queue["capacity"]:
            fail(f"{label} Sumeragi v2 queue reached capacity")
        if queue.get("oldest_age_ms", 0) > maximum_age_ms:
            fail(f"{label} Sumeragi v2 queue age exceeded the approved maximum")


def routes_sha256(routes: object) -> str:
    if not isinstance(routes, list) or not routes:
        fail("trader API routes must be a non-empty array")
    return sha256(canonical_bytes(routes))


def validate_trader_manifest(manifest: object, approval: dict, trader_api: dict) -> dict:
    manifest = require_object(manifest, "trader API CID response")
    expected_routes = trader_api.get("routes")
    expected = {
        "schema_version": 1,
        "app_id": approval["observation"]["trader_api_app_id"],
        "content_cid": approval["observation"]["trader_api_content_cid"],
        "manifest_digest_hex": trader_api.get("manifest_digest_hex"),
        "routes": expected_routes,
    }
    if manifest != expected:
        fail("trader API CID response is not the exact approved manifest")
    observed_routes_hash = routes_sha256(expected_routes)
    if observed_routes_hash != approval["observation"]["trader_api_routes_sha256"]:
        fail("trader API routes do not match the approved routes hash")
    return {
        "app_id": expected["app_id"],
        "content_cid": expected["content_cid"],
        "routes_sha256": observed_routes_hash,
        "manifest_sha256": sha256(canonical_bytes(manifest)),
    }


def collect_live_sample(
    chain: dict,
    approval: dict,
    trader_api: dict,
    monitoring_bindings: dict,
    torii_root: str,
    basic_authorization: str | None,
) -> dict:
    torii = torii_root.rstrip("/") + "/"
    blocks_url = urljoin(torii, "status/blocks")
    status_url = urljoin(torii, "status")
    sumeragi_url = urljoin(torii, "v1/sumeragi/status")
    monitoring_url = approval["observation"]["monitoring_snapshot_url"]
    cid_url = approval["observation"]["trader_api_probe_url"]
    torii_origin = url_origin(torii_root, "Torii root")
    failures = []
    responses = {}
    for label, url in (
        ("blocks", blocks_url),
        ("status", status_url),
        ("sumeragi", sumeragi_url),
        ("monitoring", monitoring_url),
        ("trader_api", cid_url),
    ):
        try:
            endpoint_origin = url_origin(url, f"{label} endpoint")
            allow_auth = label in {"blocks", "status", "sumeragi", "trader_api"} \
                and endpoint_origin == torii_origin
            responses[label] = fetch_json_value(
                url, torii_origin, basic_authorization, allow_auth
            )
        except RuntimeError as error:
            failures.append(f"{label}: {error}")
    sampled_at = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    if failures:
        return {"sampled_at": sampled_at, "api_failures": len(failures), "errors": failures}
    block_height = require_positive_integer(responses["blocks"], "/status/blocks response")
    status = require_object(responses["status"], "/status response")
    sumeragi = validate_sumeragi_v2_status(responses["sumeragi"], "Sumeragi response")
    monitoring = require_object(responses["monitoring"], "monitoring response")
    if set(monitoring) != MONITORING_KEYS or monitoring.get("schema") != MONITORING_SCHEMA:
        fail("monitoring response schema is invalid")
    if monitoring.get("bindings") != monitoring_bindings:
        fail("monitoring response does not bind the exact chain/RC/deploy/contracts state")
    status_block_height = require_positive_integer(status.get("blocks"), "/status blocks")
    if status_block_height != block_height:
        fail("/status and /status/blocks disagree on committed height")
    trader_proof = validate_trader_manifest(responses["trader_api"], approval, trader_api)
    return {
        "sampled_at": sampled_at,
        "monitoring_sampled_at": monitoring.get("sampled_at"),
        "monitoring_sequence": monitoring.get("sequence"),
        "status_block_height": block_height,
        "status_queue_size": status.get("queue_size"),
        "status_queue_queued": status.get("queue_queued"),
        "status_queue_inflight": status.get("queue_inflight"),
        "status_time_since_last_block_ms": status.get("time_since_last_block_ms"),
        "sumeragi": sumeragi,
        "validators": monitoring.get("validators"),
        "validator_set_sha256": monitoring.get("validator_set_sha256"),
        "api_failures": monitoring.get("api_failures"),
        "oracles": monitoring.get("oracles"),
        "balances": monitoring.get("balances"),
        "readonly_routes": monitoring.get("readonly_routes"),
        "trader_api": trader_proof,
        "shared_derivatives_regression": monitoring.get("shared_derivatives_regression"),
        "derivatives_pause_mode": approval["observation"]["derivatives_pause_mode"],
    }


def validate_sample(
    sample: dict,
    index: int,
    maximum_oracle_age: int,
    minimum_fee: Decimal,
    approval: dict,
    previous_monitoring_time: dt.datetime | None,
    previous_monitoring_sequence: int | None,
) -> dict[str, tuple[str, Decimal]]:
    prefix = f"sample {index}"
    if set(sample) != SAMPLE_KEYS:
        fail(f"{prefix} fields do not match the production observation schema")
    sampled_at = parse_time(sample.get("sampled_at"), f"{prefix} sampled_at")
    monitoring_at = parse_time(
        sample.get("monitoring_sampled_at"), f"{prefix} monitoring_sampled_at"
    )
    maximum_monitoring_age = approval["observation"]["maximum_monitoring_sample_age_seconds"]
    monitoring_age = (sampled_at - monitoring_at).total_seconds()
    if monitoring_age < -5 or monitoring_age > maximum_monitoring_age:
        fail(f"{prefix} monitoring snapshot is stale or implausibly future-dated")
    sequence = require_nonnegative_integer(
        sample.get("monitoring_sequence"), f"{prefix} monitoring_sequence"
    )
    if previous_monitoring_time is not None and monitoring_at <= previous_monitoring_time:
        fail(f"{prefix} monitoring timestamp was repeated or moved backwards")
    if previous_monitoring_sequence is not None and sequence <= previous_monitoring_sequence:
        fail(f"{prefix} monitoring sequence was repeated or moved backwards")
    require_positive_integer(sample.get("status_block_height"), f"{prefix} status_block_height")
    integer_fields = (
        "status_queue_size",
        "status_queue_queued",
        "status_queue_inflight",
        "status_time_since_last_block_ms",
        "api_failures",
    )
    for field in integer_fields:
        value = sample.get(field)
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            fail(f"{prefix} {field} must be a nonnegative integer")
    if any(sample[field] != 0 for field in (
        "status_queue_size", "status_queue_queued", "status_queue_inflight",
    )):
        fail(f"{prefix} transaction queue did not drain to zero")
    if sample["api_failures"] != 0:
        fail(f"{prefix} recorded API failures")
    if sample["status_time_since_last_block_ms"] > approval["observation"]["maximum_finality_age_ms"]:
        fail(f"{prefix} public Torii finality age exceeded the approved maximum")
    public_sumeragi = validate_sumeragi_v2_status(sample.get("sumeragi"), f"{prefix} Sumeragi")
    require_healthy_sumeragi_v2_status(
        public_sumeragi,
        f"{prefix} public Torii",
        approval["observation"]["maximum_finality_age_ms"],
    )
    validators = sample.get("validators")
    expected_validator_count = approval["observation"]["validator_count"]
    if not isinstance(validators, list) or len(validators) != expected_validator_count:
        fail(f"{prefix} monitoring snapshot does not contain the approved validator set")
    validator_ids: list[str] = []
    for validator_index, validator_raw in enumerate(validators, 1):
        validator = require_object(validator_raw, f"{prefix} validator {validator_index}")
        validator_id = validator.get("id")
        if set(validator) != VALIDATOR_KEYS \
                or not isinstance(validator_id, str) \
                or HASH_LITERAL.fullmatch(validator_id) is None \
                or validator_id in validator_ids:
            fail(f"{prefix} validator identities are missing or duplicated")
        validator_ids.append(validator_id)
        require_positive_integer(
            validator.get("status_block_height"),
            f"{prefix} validator {validator_id} status_block_height",
        )
        for field in VALIDATOR_KEYS - {"id", "status_block_height", "sumeragi"}:
            require_nonnegative_integer(
                validator.get(field), f"{prefix} validator {validator_id} {field}"
            )
        validator_sumeragi = validate_sumeragi_v2_status(
            validator.get("sumeragi"), f"{prefix} validator {validator_id} Sumeragi"
        )
        if validator_sumeragi["node_fingerprint"] != validator_id:
            fail(f"{prefix} validator identity does not match its Sumeragi node fingerprint")
        require_healthy_sumeragi_v2_status(
            validator_sumeragi,
            f"{prefix} validator {validator_id}",
            approval["observation"]["maximum_finality_age_ms"],
        )
        if validator["finality_age_ms"] > approval["observation"]["maximum_finality_age_ms"]:
            fail(f"{prefix} validator {validator_id} exceeded the approved finality age")
        if any(validator[field] != 0 for field in (
            "status_queue_size", "status_queue_queued", "status_queue_inflight",
            "api_failures",
        )):
            fail(f"{prefix} validator {validator_id} transaction-queue or API health is nonzero")
    if validator_ids != sorted(validator_ids):
        fail(f"{prefix} validators are not in canonical identity order")
    validator_set_hash = sha256(canonical_bytes(validator_ids))
    if sample.get("validator_set_sha256") != validator_set_hash \
            or validator_set_hash != approval["observation"]["validator_set_sha256"]:
        fail(f"{prefix} validator set does not match the signed approval")
    validator_statuses = [validator["sumeragi"] for validator in validators]
    shared_fields = (
        "protocol_version", "build_fingerprint", "config_fingerprint", "height_context_id",
        "height", "last_committed_height", "height_context",
    )
    for field in shared_fields:
        values = {canonical_bytes(status[field]) for status in validator_statuses}
        if len(values) != 1:
            fail(f"{prefix} validators disagree on Sumeragi v2 {field}")
        if canonical_bytes(public_sumeragi[field]) not in values:
            fail(f"{prefix} public Torii Sumeragi v2 {field} differs from the validator set")
    if public_sumeragi["node_fingerprint"] not in validator_ids:
        fail(f"{prefix} public Torii Sumeragi node is outside the approved validator set")
    committed_height = public_sumeragi["last_committed_height"]
    if sample["status_block_height"] != committed_height \
            or any(validator["status_block_height"] != committed_height for validator in validators):
        fail(f"{prefix} committed block height is incoherent with Sumeragi v2 finality")

    oracles = require_object(sample.get("oracles"), f"{prefix} oracle watch")
    if set(oracles) != {"watch_sha256", "feeds"} or not isinstance(oracles.get("feeds"), list) \
            or not oracles["feeds"]:
        fail(f"{prefix} oracle watch is malformed")
    oracle_ids = []
    for feed_index, feed_raw in enumerate(oracles["feeds"], 1):
        feed = require_object(feed_raw, f"{prefix} oracle feed {feed_index}")
        if set(feed) != {"id", "age_seconds"} or not isinstance(feed.get("id"), str) \
                or WATCH_ID.fullmatch(feed["id"]) is None or feed["id"] in oracle_ids:
            fail(f"{prefix} oracle feed identities are malformed or duplicated")
        oracle_ids.append(feed["id"])
        if require_nonnegative_integer(feed.get("age_seconds"), f"{prefix} oracle {feed['id']} age") \
                > maximum_oracle_age:
            fail(f"{prefix} oracle freshness exceeded the approved maximum")
    if oracle_ids != sorted(oracle_ids):
        fail(f"{prefix} oracle feeds are not in canonical identity order")
    oracle_hash = sha256(canonical_bytes([{"id": value} for value in oracle_ids]))
    if oracles.get("watch_sha256") != oracle_hash \
            or oracle_hash != approval["observation"]["oracle_watch_sha256"]:
        fail(f"{prefix} oracle watch set does not match the signed approval")

    balances = require_object(sample.get("balances"), f"{prefix} balance watch")
    if set(balances) != {"watch_sha256", "entries"} \
            or not isinstance(balances.get("entries"), list) or not balances["entries"]:
        fail(f"{prefix} balance watch is malformed")
    balance_values: dict[str, tuple[str, Decimal]] = {}
    identities = []
    signer_fee_count = 0
    for balance_index, balance_raw in enumerate(balances["entries"], 1):
        balance = require_object(balance_raw, f"{prefix} balance {balance_index}")
        balance_id = balance.get("id")
        kind = balance.get("kind")
        if set(balance) != {"id", "kind", "amount"} or not isinstance(balance_id, str) \
                or WATCH_ID.fullmatch(balance_id) is None or balance_id in balance_values \
                or kind not in {"signer_fee", "watched"}:
            fail(f"{prefix} balance identities are malformed or duplicated")
        amount = require_canonical_decimal(balance.get("amount"), f"{prefix} balance {balance_id} amount")
        balance_values[balance_id] = (kind, amount)
        identities.append({"id": balance_id, "kind": kind})
        if kind == "signer_fee":
            signer_fee_count += 1
            if amount < minimum_fee:
                fail(f"{prefix} fee balance fell below the approved minimum")
    if list(balance_values) != sorted(balance_values) or signer_fee_count != 1:
        fail(f"{prefix} balance watch order or signer-fee identity is invalid")
    balance_hash = sha256(canonical_bytes(identities))
    if balances.get("watch_sha256") != balance_hash \
            or balance_hash != approval["observation"]["balance_watch_sha256"]:
        fail(f"{prefix} balance watch set does not match the signed approval")

    readonly = require_object(sample.get("readonly_routes"), f"{prefix} readonly routes")
    if set(readonly) != {"set_sha256", "ok", "failure_count"} \
            or readonly.get("set_sha256") != approval["observation"]["readonly_route_set_sha256"] \
            or readonly.get("ok") is not True \
            or require_nonnegative_integer(readonly.get("failure_count"), f"{prefix} readonly route failures") != 0:
        fail(f"{prefix} readonly routes regressed or changed identity")
    trader = require_object(sample.get("trader_api"), f"{prefix} trader API proof")
    expected_trader = approval["observation"]
    if trader.get("app_id") != expected_trader["trader_api_app_id"] \
            or trader.get("content_cid") != expected_trader["trader_api_content_cid"] \
            or trader.get("routes_sha256") != expected_trader["trader_api_routes_sha256"] \
            or not HEX64.fullmatch(str(trader.get("manifest_sha256") or "")):
        fail(f"{prefix} trader API manifest/CID proof changed")
    regression = sample.get("shared_derivatives_regression")
    if not isinstance(regression, bool):
        fail(f"{prefix} shared-derivatives regression state is malformed")
    if sample.get("derivatives_pause_mode") != "external_fail_closed":
        fail(f"{prefix} derivatives pause boundary is not fail-closed")
    if regression:
        fail(
            f"{prefix} detected a shared derivatives regression; coordinated perps/options/cover "
            "pause is an external production control, so cutover observation stopped without "
            "claiming that a pause was executed"
        )
    return balance_values


def atomic_replace(path: Path, value: dict, test_mode: bool, root: Path) -> None:
    path = Path(os.path.abspath(path))
    if not test_mode and path != root / "deployments/production/observation.latest.json":
        fail("production observation evidence must use deployments/production/observation.latest.json")
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptors, links = open_directory_chain(path.parent, "observation evidence")
    parent_descriptor = descriptors[-1]
    existing_identity = None
    try:
        existing = os.stat(path.name, dir_fd=parent_descriptor, follow_symlinks=False)
    except FileNotFoundError:
        pass
    except OSError:
        close_descriptors(descriptors)
        fail("existing observation evidence is unreadable")
    else:
        if not stat.S_ISREG(existing.st_mode) or existing.st_nlink != 1 \
                or stat.S_IMODE(existing.st_mode) != 0o600:
            close_descriptors(descriptors)
            fail("existing observation evidence must be a mode-0600 single-link regular file")
        existing_identity = identity(existing)
    temporary_name = f".production-observation.{secrets.token_hex(24)}.tmp"
    descriptor = -1
    temporary_identity = None
    try:
        descriptor = os.open(
            temporary_name,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
            0o600,
            dir_fd=parent_descriptor,
        )
        os.fchmod(descriptor, 0o600)
        temporary_identity = identity(os.fstat(descriptor))
        payload = json.dumps(value, indent=2, sort_keys=True).encode("utf-8") + b"\n"
        offset = 0
        while offset < len(payload):
            offset += os.write(descriptor, payload[offset:])
        os.fsync(descriptor)
        current_temporary = os.stat(
            temporary_name, dir_fd=parent_descriptor, follow_symlinks=False
        )
        if identity(os.fstat(descriptor)) != identity(current_temporary):
            fail("observation evidence temporary file changed")
        current_identity = None
        try:
            current = os.stat(path.name, dir_fd=parent_descriptor, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            current_identity = identity(current)
        if existing_identity is None:
            if current_identity is not None:
                fail("observation evidence appeared concurrently")
        elif current_identity != existing_identity:
            fail("observation evidence changed concurrently")
        os.rename(
            temporary_name,
            path.name,
            src_dir_fd=parent_descriptor,
            dst_dir_fd=parent_descriptor,
        )
        temporary_identity = None
        target = os.stat(path.name, dir_fd=parent_descriptor, follow_symlinks=False)
        if identity(os.fstat(descriptor)) != identity(target) \
                or target.st_nlink != 1 or stat.S_IMODE(target.st_mode) != 0o600:
            fail("observation evidence target changed")
        os.fsync(parent_descriptor)
        verify_directory_chain(descriptors, links, "observation evidence")
    finally:
        if descriptor >= 0:
            try:
                os.close(descriptor)
            except OSError:
                pass
        if temporary_identity is not None:
            try:
                named = os.stat(
                    temporary_name, dir_fd=parent_descriptor, follow_symlinks=False
                )
                if identity(named)[:2] == temporary_identity[:2]:
                    os.unlink(temporary_name, dir_fd=parent_descriptor)
            except OSError:
                pass
        close_descriptors(descriptors)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--approval-state-json", required=True)
    parser.add_argument("--client-config", required=True)
    parser.add_argument("--chain-file", required=True)
    parser.add_argument("--soraswap-rc-state-json", required=True)
    parser.add_argument("--soraswap-source-state-json", required=True)
    parser.add_argument("--iroha-state-json", required=True)
    parser.add_argument("--deploy-file", required=True)
    parser.add_argument("--contracts-file", required=True)
    parser.add_argument("--trader-api-file", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--internal-test-fixture")
    parser.add_argument("--internal-test-token")
    args = parser.parse_args()

    test_mode = args.internal_test_fixture is not None or args.internal_test_token is not None
    if test_mode:
        if args.internal_test_token != TEST_SENTINEL or not args.internal_test_fixture:
            fail("internal test fixture requires the exact non-release test sentinel")
    else:
        leaked = [name for name in FORBIDDEN_OVERRIDE_NAMES if name in os.environ]
        if leaked:
            fail(f"production observation rejects duration/sampling/test overrides: {leaked[0]}")

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
    approval = state(args.approval_state_json, "cutover approval state")
    rc_state = state(args.soraswap_rc_state_json, "SoraSwap RC state")
    source_state = state(args.soraswap_source_state_json, "SoraSwap source state")
    iroha_state = state(args.iroha_state_json, "Iroha state")
    if approval.get("schema") != "soraswap-production-cutover-approval-state/v1":
        fail("cutover approval state schema is invalid")
    if parse_time(approval.get("expires_at"), "cutover approval expiry") <= dt.datetime.now(dt.timezone.utc):
        fail("cutover approval expired before observation")
    observation_policy = approval.get("observation")
    if not isinstance(observation_policy, dict) or any(
        observation_policy.get(key) != expected
        for key, expected in (
            ("duration_seconds", DURATION_SECONDS),
            ("interval_seconds", INTERVAL_SECONDS),
            ("minimum_samples", MINIMUM_SAMPLES),
            ("maximum_monitoring_sample_age_seconds", 30),
            ("maximum_finality_age_ms", 30000),
            ("derivatives_pause_mode", "external_fail_closed"),
        )
    ):
        fail("approval state attempts to weaken the production observation window")

    expected_inputs = {
        "chain": root / "deployments/production/chain.latest.json",
        "deploy": root / "deployments/production/deploy.latest.json",
        "contracts": root / "deployments/production/contracts.latest.json",
        "trader": root / "deployments/production/trader_api_bundle.latest.json",
    }
    provided_inputs = {
        "chain": Path(os.path.abspath(args.chain_file)),
        "deploy": Path(os.path.abspath(args.deploy_file)),
        "contracts": Path(os.path.abspath(args.contracts_file)),
        "trader": Path(os.path.abspath(args.trader_api_file)),
    }
    if provided_inputs != expected_inputs:
        fail("observation inputs must use the canonical production latest evidence paths")
    chain_bytes, _ = read_regular(expected_inputs["chain"], "production chain evidence")
    deploy_bytes, _ = read_regular(expected_inputs["deploy"], "production deploy evidence")
    contracts_bytes, _ = read_regular(expected_inputs["contracts"], "production contracts evidence")
    trader_bytes, _ = read_regular(expected_inputs["trader"], "production trader API evidence")
    chain = json_object(chain_bytes, "production chain evidence")
    deploy = json_object(deploy_bytes, "production deploy evidence")
    contracts = json_object(contracts_bytes, "production contracts evidence")
    trader_api = json_object(trader_bytes, "production trader API evidence")
    fingerprint = chain_fingerprint(chain)
    if fingerprint is None or approval.get("bindings", {}).get("chain_fingerprint") != fingerprint:
        fail("observation chain does not match the signed cutover approval")
    torii_root, basic_authorization = load_client_config(
        Path(os.path.abspath(args.client_config)), fingerprint, root
    )
    for label, artifact in (("deploy", deploy), ("contracts", contracts), ("trader API", trader_api)):
        if chain_fingerprint(artifact) != fingerprint:
            fail(f"production {label} evidence does not match the observation chain")
    source_hash = sha256(canonical_bytes(source_state))
    if approval["bindings"].get("soraswap_git_sha") != rc_state.get("git_sha") \
            or approval["bindings"].get("soraswap_tree_sha") != rc_state.get("tree_sha") \
            or approval["bindings"].get("soraswap_source_sha256") != source_hash:
        fail("observation SoraSwap RC/source does not match the signed approval")
    for key in (
        "iroha_git_sha", "bundle_name", "checksums_sha256", "manifest_sha256",
        "iroha3d_sha256", "iroha_sha256", "kagami_sha256", "archive_sha256",
        "archive_sidecar_sha256",
    ):
        if approval["bindings"].get(key) != iroha_state.get(key):
            fail(f"observation Iroha candidate {key} does not match the signed approval")

    expected_cid = trader_api.get("content_cid")
    expected_routes_hash = routes_sha256(trader_api.get("routes"))
    cid_probe = trader_api.get("cid_probe")
    if not isinstance(expected_cid, str) or len(expected_cid) < 20 \
            or not isinstance(cid_probe, dict):
        fail("production trader API evidence lacks a stable content CID")
    if trader_api.get("app_id") != observation_policy.get("trader_api_app_id") \
            or expected_cid != observation_policy.get("trader_api_content_cid") \
            or expected_routes_hash != observation_policy.get("trader_api_routes_sha256"):
        fail("production trader API evidence differs from the signed app/CID/routes approval")
    if cid_probe.get("status") != "completed" \
            or cid_probe.get("url") != observation_policy.get("trader_api_probe_url") \
            or not isinstance(cid_probe.get("attempt_count"), int) \
            or isinstance(cid_probe.get("attempt_count"), bool) \
            or cid_probe.get("attempt_count") < 1 \
            or cid_probe.get("success_count") != cid_probe.get("attempt_count") \
            or cid_probe.get("manifest_match_count") != cid_probe.get("attempt_count"):
        fail("production trader API evidence lacks an exact successful approved CID probe")
    if not HEX64.fullmatch(str(trader_api.get("manifest_digest_hex") or "")):
        fail("production trader API evidence manifest digest is invalid")
    bindings = {
        "chain_fingerprint": fingerprint,
        "soraswap_git_sha": rc_state.get("git_sha"),
        "soraswap_tree_sha": rc_state.get("tree_sha"),
        "soraswap_source_sha256": source_hash,
        "iroha_git_sha": iroha_state.get("iroha_git_sha"),
        "iroha_state_sha256": sha256(canonical_bytes(iroha_state)),
        "approval_id": approval.get("approval_id"),
        "approval_sha256": approval.get("approval_sha256"),
        "policy_sha256": approval.get("policy_sha256"),
        "deploy_generated_at": deploy.get("generated_at"),
        "deploy_sha256": sha256(deploy_bytes),
        "contracts_generated_at": contracts.get("generated_at"),
        "contracts_sha256": sha256(contracts_bytes),
        "trader_api_generated_at": trader_api.get("generated_at"),
        "trader_api_sha256": sha256(trader_bytes),
        "trader_api_content_cid": expected_cid,
        "trader_api_app_id": trader_api.get("app_id"),
        "trader_api_routes_sha256": expected_routes_hash,
    }
    if not all(
        isinstance(value, str) and value
        for key, value in bindings.items()
        if key != "chain_fingerprint"
    ):
        fail("observation binding inputs are incomplete")

    monitoring_bindings = {
        "chain_fingerprint": fingerprint,
        "soraswap_git_sha": rc_state.get("git_sha"),
        "soraswap_tree_sha": rc_state.get("tree_sha"),
        "soraswap_source_sha256": source_hash,
        "iroha_state_sha256": sha256(canonical_bytes(iroha_state)),
        "approval_id": approval.get("approval_id"),
        "approval_sha256": approval.get("approval_sha256"),
        "deploy_generated_at": deploy.get("generated_at"),
        "deploy_sha256": sha256(deploy_bytes),
        "contracts_generated_at": contracts.get("generated_at"),
        "contracts_sha256": sha256(contracts_bytes),
    }

    if test_mode:
        fixture_bytes, _ = read_regular(
            Path(os.path.abspath(args.internal_test_fixture)), "internal observation fixture"
        )
        fixture = json_object(fixture_bytes, "internal observation fixture")
        if fixture.get("schema") != FIXTURE_SCHEMA:
            fail("internal observation fixture schema is invalid")
        samples = fixture.get("samples")
        wall_elapsed = fixture.get("wall_elapsed_seconds")
        if not isinstance(samples, list) or not isinstance(wall_elapsed, int):
            fail("internal observation fixture is malformed")
    else:
        samples = []
        start_monotonic = time.monotonic()
        for sample_index in range(MINIMUM_SAMPLES):
            target = start_monotonic + sample_index * INTERVAL_SECONDS
            delay = target - time.monotonic()
            if delay > 0:
                time.sleep(delay)
            samples.append(collect_live_sample(
                fingerprint,
                approval,
                trader_api,
                monitoring_bindings,
                torii_root,
                basic_authorization,
            ))
        wall_elapsed = int(time.monotonic() - start_monotonic)

    if wall_elapsed < DURATION_SECONDS:
        fail("observation duration is shorter than the required 1800 seconds")
    if len(samples) != MINIMUM_SAMPLES:
        fail("observation must contain exactly 61 samples")
    sample_times = [parse_time(sample.get("sampled_at"), f"sample {index} sampled_at") for index, sample in enumerate(samples, 1) if isinstance(sample, dict)]
    if len(sample_times) != len(samples):
        fail("observation contains a non-object sample")
    if any(later <= earlier for earlier, later in zip(sample_times, sample_times[1:])):
        fail("observation sample times are not strictly increasing")
    if any(
        not 25 <= (later - earlier).total_seconds() <= 45
        for earlier, later in zip(sample_times, sample_times[1:])
    ):
        fail("observation sample cadence fell outside the approved jitter window")
    if (sample_times[-1] - sample_times[0]).total_seconds() < DURATION_SECONDS:
        fail("observation sample timestamps span less than 1800 seconds")

    try:
        minimum_fee = Decimal(approval["minimum_fee_balance"])
    except (InvalidOperation, KeyError):
        fail("approved minimum fee is invalid")
    maximum_oracle_age = observation_policy.get("maximum_oracle_age_seconds")
    if not isinstance(maximum_oracle_age, int):
        fail("approved oracle freshness maximum is invalid")
    previous_monitoring_time = None
    previous_monitoring_sequence = None
    baseline_watched_balances = None
    for index, sample in enumerate(samples, 1):
        observed_balances = validate_sample(
            sample,
            index,
            maximum_oracle_age,
            minimum_fee,
            approval,
            previous_monitoring_time,
            previous_monitoring_sequence,
        )
        watched_balances = {
            key: amount for key, (kind, amount) in observed_balances.items() if kind == "watched"
        }
        if baseline_watched_balances is None:
            baseline_watched_balances = watched_balances
        elif watched_balances != baseline_watched_balances:
            fail(f"sample {index} watched production balances changed during readonly observation")
        previous_monitoring_time = parse_time(
            sample["monitoring_sampled_at"], f"sample {index} monitoring_sampled_at"
        )
        previous_monitoring_sequence = sample["monitoring_sequence"]
    if samples[-1]["sumeragi"]["last_committed_height"] \
            <= samples[0]["sumeragi"]["last_committed_height"]:
        fail("production finality did not advance during the thirty-minute observation")
    if not test_mode:
        now = dt.datetime.now(dt.timezone.utc)
        if sample_times[-1] > now + dt.timedelta(seconds=5) \
                or (now - sample_times[-1]).total_seconds() > 30:
            fail("final production observation sample is stale or future-dated")
    pause_outcome = "not_required"
    report = {
        "schema": SCHEMA,
        "status": "completed",
        "environment": "production",
        "generated_at": dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
        "test_only": test_mode,
        "required_duration_seconds": DURATION_SECONDS,
        "observed_duration_seconds": wall_elapsed,
        "required_interval_seconds": INTERVAL_SECONDS,
        "required_minimum_samples": MINIMUM_SAMPLES,
        "sample_count": len(samples),
        "started_at": samples[0]["sampled_at"],
        "completed_at": samples[-1]["sampled_at"],
        "bindings": bindings,
        "summary": {
            "sumeragi_v2_finality_agreement": True,
            "transaction_queues_drained": True,
            "sumeragi_v2_liveness_healthy": True,
            "api_failures": 0,
            "oracle_fresh": True,
            "minimum_fee_preserved": True,
            "readonly_routes_stable": True,
            "trader_api_cid_stable": True,
            "shared_derivatives_pause_outcome": pause_outcome,
            "shared_derivatives_pause_boundary": "external_fail_closed",
        },
        "samples": samples,
    }
    atomic_replace(Path(os.path.abspath(args.output)), report, test_mode, root)
    print(json.dumps({
        "status": "completed",
        "output": str(Path(args.output).name),
        "sample_count": len(samples),
        "observed_duration_seconds": wall_elapsed,
        "test_only": test_mode,
    }, sort_keys=True))


if __name__ == "__main__":
    main()
