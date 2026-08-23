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
VALIDATOR_ID = re.compile(r"ed0120[0-9a-f]{64}")
CANONICAL_DECIMAL = re.compile(r"(?:0|[1-9][0-9]*)(?:\.[0-9]*[1-9])?")
WATCH_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:@/#-]{2,127}")
SAMPLE_KEYS = {
    "sampled_at", "monitoring_sampled_at", "monitoring_sequence",
    "status_block_height", "status_queue_size", "status_queue_queued",
    "status_queue_inflight", "status_time_since_last_block_ms",
    "canonical_height", "canonical_phase", "commit_qc_height",
    "highest_qc_height", "proposal_queue_depth", "tx_queue_depth",
    "oldest_queue_age_ms", "validators", "validator_set_sha256",
    "api_failures", "oracles", "balances", "readonly_routes", "trader_api",
    "shared_derivatives_regression", "derivatives_pause_mode",
}
VALIDATOR_KEYS = {
    "id", "status_block_height", "canonical_height", "commit_qc_height",
    "highest_qc_height", "finality_age_ms", "status_queue_size",
    "status_queue_queued", "status_queue_inflight", "proposal_queue_depth",
    "tx_queue_depth", "oldest_queue_age_ms", "lane_backlog", "api_failures",
}
MONITORING_KEYS = {
    "schema", "sampled_at", "sequence", "bindings", "validator_set_sha256",
    "validators", "api_failures", "oracles", "balances", "readonly_routes",
    "shared_derivatives_regression",
}
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
    sumeragi = require_object(responses["sumeragi"], "Sumeragi response")
    monitoring = require_object(responses["monitoring"], "monitoring response")
    canonical = require_object(sumeragi.get("canonical"), "Sumeragi canonical")
    commit_qc = require_object(sumeragi.get("commit_qc"), "Sumeragi commit_qc")
    highest_qc = require_object(sumeragi.get("highest_qc"), "Sumeragi highest_qc")
    proposal_gate = require_object(sumeragi.get("proposal_gate"), "Sumeragi proposal_gate")
    tx_queue = require_object(sumeragi.get("tx_queue"), "Sumeragi tx_queue")
    phase = canonical.get("phase")
    if not isinstance(phase, str) or not phase:
        fail("Sumeragi canonical.phase must be a non-empty string")
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
        "canonical_height": canonical.get("height"),
        "canonical_phase": phase,
        "commit_qc_height": commit_qc.get("height"),
        "highest_qc_height": highest_qc.get("height"),
        "proposal_queue_depth": proposal_gate.get("queue_len"),
        "tx_queue_depth": tx_queue.get("depth"),
        "oldest_queue_age_ms": tx_queue.get("oldest_queued_age_ms"),
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
    positive_fields = (
        "status_block_height", "canonical_height", "commit_qc_height", "highest_qc_height",
    )
    for field in positive_fields:
        require_positive_integer(sample.get(field), f"{prefix} {field}")
    integer_fields = (
        "status_queue_size",
        "status_queue_queued",
        "status_queue_inflight",
        "status_time_since_last_block_ms",
        "proposal_queue_depth",
        "tx_queue_depth",
        "oldest_queue_age_ms",
        "api_failures",
    )
    for field in integer_fields:
        value = sample.get(field)
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            fail(f"{prefix} {field} must be a nonnegative integer")
    if not isinstance(sample.get("canonical_phase"), str) or not sample["canonical_phase"]:
        fail(f"{prefix} canonical phase is missing")
    if any(sample[field] != 0 for field in (
        "status_queue_size", "status_queue_queued", "status_queue_inflight",
        "proposal_queue_depth", "tx_queue_depth", "oldest_queue_age_ms",
    )):
        fail(f"{prefix} queue or lane backlog did not drain to zero")
    if sample["api_failures"] != 0:
        fail(f"{prefix} recorded API failures")
    if sample["status_time_since_last_block_ms"] > approval["observation"]["maximum_finality_age_ms"]:
        fail(f"{prefix} public Torii finality age exceeded the approved maximum")
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
                or VALIDATOR_ID.fullmatch(validator_id) is None \
                or validator_id in validator_ids:
            fail(f"{prefix} validator identities are missing or duplicated")
        validator_ids.append(validator_id)
        for field in ("status_block_height", "canonical_height", "commit_qc_height", "highest_qc_height"):
            require_positive_integer(
                validator.get(field), f"{prefix} validator {validator_id} {field}"
            )
        for field in VALIDATOR_KEYS - {
            "id", "status_block_height", "canonical_height", "commit_qc_height", "highest_qc_height"
        }:
            require_nonnegative_integer(
                validator.get(field), f"{prefix} validator {validator_id} {field}"
            )
        if validator["finality_age_ms"] > approval["observation"]["maximum_finality_age_ms"]:
            fail(f"{prefix} validator {validator_id} exceeded the approved finality age")
        if any(validator[field] != 0 for field in (
            "status_queue_size", "status_queue_queued", "status_queue_inflight",
            "proposal_queue_depth", "tx_queue_depth", "oldest_queue_age_ms",
            "lane_backlog", "api_failures",
        )):
            fail(f"{prefix} validator {validator_id} queue, lane, or API health is nonzero")
    if validator_ids != sorted(validator_ids):
        fail(f"{prefix} validators are not in canonical identity order")
    validator_set_hash = sha256(canonical_bytes(validator_ids))
    if sample.get("validator_set_sha256") != validator_set_hash \
            or validator_set_hash != approval["observation"]["validator_set_sha256"]:
        fail(f"{prefix} validator set does not match the signed approval")
    consensus = {}
    for field in ("canonical_height", "commit_qc_height", "highest_qc_height"):
        values = {validator[field] for validator in validators}
        if len(values) != 1:
            fail(f"{prefix} validators disagree on {field}")
        consensus[field] = values.pop()
    if consensus["commit_qc_height"] != consensus["highest_qc_height"]:
        fail(f"{prefix} commit-QC and highest-QC are not aligned")
    canonical_lead = consensus["canonical_height"] - consensus["commit_qc_height"]
    if canonical_lead < 0 or canonical_lead > approval["observation"]["maximum_canonical_lead"]:
        fail(f"{prefix} canonical lead exceeds the approved bound")
    if any(sample[field] != consensus[field] for field in consensus):
        fail(f"{prefix} public Torii Sumeragi state differs from the validator set")
    if sample["status_block_height"] != consensus["commit_qc_height"] \
            or any(validator["status_block_height"] != consensus["commit_qc_height"] for validator in validators):
        fail(f"{prefix} committed block height is incoherent with commit-QC finality")

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
            ("maximum_canonical_lead", 1),
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
        "irohad_sha256", "iroha_sha256", "kagami_sha256", "archive_sha256",
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
    if samples[-1]["commit_qc_height"] <= samples[0]["commit_qc_height"]:
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
            "validator_qc_finality_agreement": True,
            "queues_drained": True,
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
