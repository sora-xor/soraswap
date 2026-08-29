#!/usr/bin/env python3
"""Serve a lightweight browser console for deployed SoraSwap contracts."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import mimetypes
import os
import re
import stat
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:  # Python < 3.11
    import tomli as tomllib

SCRIPT_ROOT = Path(__file__).resolve().parent
if str(SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPT_ROOT))

from iroha_canonical_request_auth import (
    CANONICAL_ACCOUNT_AUTH_HEADERS,
    build_account_request_headers,
    canonical_account_request_message,
    canonical_ed25519_account_header,
    canonical_network_id_bytes,
    canonical_request_query,
    raw_ed25519_public_key_hex,
    sign_ed25519_message,
    verify_ed25519_signature_b64,
)


REPO_ROOT = Path(__file__).resolve().parent.parent
DEPLOYMENTS_ROOT = REPO_ROOT / "deployments"
UI_ROOT = REPO_ROOT / "ui" / "contract_console"
DEFAULT_GAS_LIMIT = 100000
MAX_BROWSER_GAS_LIMIT = 50_000_000
DEFAULT_NETWORK_PREFIX = "753"
TESTNET_NETWORK_PREFIX = "369"
TAIRA_CHAIN_ID = "fc56984b-2be7-431d-840e-21514d1883f0"
TAIRA_NETWORK_ID = "hash:82531CE8EAE8BFF6BEECA4698BFD13A3BC8BEC5F0EE0D23D428C97FC17AB0F3B#3E94"
TAIRA_NETWORK_PREFIX = 369
BRIDGE_CONTRACT_KEY = "bridge.sccp_bridge"
PUBLIC_MUTATION_ENVIRONMENTS = {"testnet", "production"}
MAX_REQUEST_BODY_BYTES = 1_048_576
MAX_UPSTREAM_RESPONSE_BYTES = 10_485_760
MAX_BROWSER_JSON_DEPTH = 64
MAX_BROWSER_QUERY_STRING_CHARS = 4096
MAX_BROWSER_QUERY_FIELDS = 32
HASH_HEX_CHARS = 64
MAX_HISTORY_ASSET_ID_CHARS = 512
MAX_ASSET_DEFINITION_SELECTOR_CHARS = 512
DEFAULT_UPSTREAM_TIMEOUT_SECONDS = 60
ACCESS_LOG_QUERY_VALUE_CHARS = 256
READ_PROXY_OFFSET_CAP = 10000
READ_PROXY_LIMITS = {
    "/v1/sccp/messages/recent": {"default": 25, "cap": 50},
    "/v1/transactions/history": {"default": 10, "cap": 100},
}
READ_PROXY_ALLOWED_QUERY_KEYS = {
    "/v1/sccp/capabilities": set(),
    "/v1/sccp/registry": set(),
    "/v1/sccp/messages/recent": {"limit", "from"},
    "/v1/transactions/history": {"limit", "offset", "asset_id", "count_mode"},
}
BRIDGE_PROOF_SUBMIT_BROWSER_KEYS = {
    "authority",
    "destination_proof_b64",
}
BRIDGE_MESSAGE_BROWSER_KEYS = {
    "authority",
    "native_proof_b64",
}
BRIDGE_PROOF_FIELD_BY_PATH = {
    "/v1/bridge/proofs/submit": "destination_proof_b64",
    "/v1/bridge/messages": "native_proof_b64",
}
PIPELINE_STATUS_KINDS = {"Queued", "Approved", "Committed", "Applied", "Rejected", "Expired"}
PIPELINE_STATUS_SCOPES = {"local", "global"}
PIPELINE_STATUS_SOURCES = {"cache", "queue", "state"}
SCCP_EXTERNAL_PROFILES = {
    "ethereum-mainnet",
    "ethereum-sepolia",
    "bsc-mainnet",
    "bsc-testnet",
    "solana-testnet",
    "tron-mainnet",
    "tron-nile",
    "tron-shasta",
}
BRIDGE_RESPONSE_FIELDS = {
    "submitted",
    "payload_kind",
    "message_id_hex",
    "backend",
    "counterparty_domain",
    "counterparty_chain",
    "route_configuration_hash_hex",
    "range_start_height",
    "range_end_height",
    "creation_time_ms",
    "tx_hash_hex",
    "transaction_payload_b64",
    "signing_message_b64",
}
CONTRACT_CALL_RESPONSE_FIELDS = {
    "ok",
    "submitted",
    "dataspace",
    "contract_address",
    "code_hash_hex",
    "abi_hash_hex",
    "creation_time_ms",
    "transaction_ttl_ms",
    "tx_hash_hex",
    "pipeline_status",
    "entrypoint_hash_hex",
    "transaction_payload_b64",
    "signing_message_b64",
    "entrypoint",
    "operation_receipt",
}
CONTRACT_CALL_REQUIRED_RESPONSE_FIELDS = CONTRACT_CALL_RESPONSE_FIELDS - {
    "transaction_ttl_ms",
    "pipeline_status",
}
CONTRACT_CALL_RECEIPT_FIELDS = {
    "operation_kind",
    "status",
    "transport",
    "dataspace",
    "contract_alias",
    "contract_address",
    "code_hash_hex",
    "abi_hash_hex",
    "tx_hash_hex",
    "entrypoint",
    "entrypoint_hash_hex",
    "gas_limit",
    "gas_used",
    "fee_payment",
    "payload_digest_hex",
}
CONTRACT_CALL_REQUIRED_RECEIPT_FIELDS = {
    "operation_kind",
    "status",
    "transport",
    "dataspace",
    "contract_address",
    "code_hash_hex",
    "abi_hash_hex",
    "entrypoint",
    "gas_limit",
    "fee_payment",
    "payload_digest_hex",
}
CURRENT_DEPLOY_STRATEGY = "ivm_contract_deploy"
DEPLOYMENT_DATASPACE_ALIAS = "universal"
DEPLOYMENT_DATASPACE_ID = "0"
CHAIN_FINGERPRINT_FIELDS = frozenset({"torii_url", "chain", "block_1_hash"})
DEPLOYMENT_RECORD_FIELDS = frozenset(
    {
        "contract_key",
        "generated_at",
        "environment",
        "contract_source",
        "contract_alias",
        "dataspace_alias",
        "dataspace_id",
        "contract_address",
        "deploy_nonce",
        "code_hash_hex",
        "abi_hash_hex",
        "deploy_strategy",
        "chain_fingerprint",
        "response",
    }
)
CONTRACTS_SNAPSHOT_FIELDS = frozenset(
    {"generated_at", "environment", "status", "chain_fingerprint", "contracts"}
)
CONTRACT_DEPLOY_RESPONSE_FIELDS = frozenset(
    {
        "authority",
        "chain_discriminant",
        "chain_id",
        "code_hash_hex",
        "commit_deployment_tx_hash",
        "contract_address",
        "contract_alias",
        "contract_subject_account",
        "dataspace",
        "deploy_nonce",
        "deployment_state",
        "expected_previous_contract_address",
        "fee_quotes",
        "final",
        "next_deploy_nonce",
        "ok",
        "operation_receipt",
        "register_bytes_chunk_count",
        "register_bytes_chunk_size",
        "register_bytes_stage_tx_hashes",
        "register_bytes_tx_hash",
        "register_bytes_tx_strategy",
        "register_manifest_tx_hash",
        "submitted",
        "terminal_kind",
        "torii_url",
    }
)
CONTRACT_DEPLOY_RECEIPT_FIELDS = frozenset(
    {
        "operation_kind",
        "status",
        "transport",
        "torii_url",
        "chain_id",
        "authority",
        "chain_discriminant",
        "dataspace",
        "contract_alias",
        "contract_address",
        "contract_subject_account",
        "code_hash_hex",
        "abi_hash_hex",
        "tx_hash_hex",
        "entrypoint",
        "entrypoint_hash_hex",
        "gas_limit",
        "gas_used",
        "fee_payment",
        "fee_quotes",
        "payload_digest_hex",
        "deployment_state",
    }
)
CANONICAL_BASE64_RE = re.compile(r"^[A-Za-z0-9+/]+={0,2}$")
LOWER_NONZERO_HASH_RE = re.compile(r"^[0-9a-f]{64}$")
CANONICAL_HASH_LITERAL_RE = re.compile(r"^hash:([0-9A-F]{64})#([0-9A-F]{4})$")
CANONICAL_DECIMAL_STRING_RE = re.compile(r"^(0|[1-9][0-9]*)$")
CANONICAL_QUANTITY_RE = re.compile(r"^(0|[1-9][0-9]*)(?:\.([0-9]*[1-9]))?$")
CANONICAL_INT_ARGUMENT_RE = re.compile(r"^(?:0|-?[1-9][0-9]*)$")
CANONICAL_DECIMAL_ARGUMENT_RE = re.compile(
    r"^-?(?:0|[1-9][0-9]*)(?:\.([0-9]*[1-9]))?$"
)
MANIFEST_NUMERIC_TYPES = frozenset({"int", "quantity", "decimal"})
FEE_CHARGE_KIND_ORDER = {"nexus": 0, "pipeline_gas": 1}
CANONICAL_ACCOUNT_AUTH_PATHS = frozenset(
    {
        "/v1/contracts/view",
        "/v1/contracts/view/batch",
        "/v1/contracts/call",
        "/v1/bridge/proofs/submit",
        "/v1/bridge/messages",
    }
)
PLACEHOLDER_EXACT_VALUES = {"none", "null", "n/a", "na", "example"}
PLACEHOLDER_TOKEN_RE = re.compile(
    r"change[_ -]?me|changeme|replace[_ -]?me|replaceme|todo|tbd|placeholder", re.IGNORECASE
)
RESERVED_PUBLIC_HOST_SUFFIXES = (".example", ".invalid", ".test", ".localhost")
RESERVED_PUBLIC_HOSTS = {"127.0.0.1", "::1", "localhost", "example.com", "example.org", "example.net"}
RESERVED_PUBLIC_HOST_TRAILING_SUFFIXES = (".example.com", ".example.org", ".example.net")
SIMPLE_PROXY_IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]*$")
LOCAL_RUNTIME_PATH_RE = re.compile(
    r"(?<![A-Za-z0-9:/])(?P<path>(?:/private)?/var/folders/[^\s\",}\]]+|(?:/private)?/tmp/[^\s\",}\]]+)"
)
LOCAL_USER_PATH_RE = re.compile(r"(?<![A-Za-z0-9:/])(?P<path>/Users/[^\s\",}\]]+)")
LOCAL_DIAGNOSTIC_PATH_RE = re.compile(
    r"(?:file://(?:localhost)?/(?:Users/|private/var/folders/|var/folders/|private/tmp/|tmp/))"
    r"|(?:file:/(?:Users/|private/var/folders/|var/folders/|private/tmp/|tmp/))"
    r"|(?:(?<![A-Za-z0-9:/])(?:/Users/|/private/var/folders/|/var/folders/|/private/tmp/|/tmp/))"
)
BROWSER_SECURITY_HEADERS = {
    "Content-Security-Policy": (
        "default-src 'self'; "
        "base-uri 'none'; "
        "object-src 'none'; "
        "frame-ancestors 'none'; "
        "form-action 'self'; "
        "connect-src 'self'; "
        "img-src 'self' data:; "
        "script-src 'self'; "
        "style-src 'self'"
    ),
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Resource-Policy": "same-origin",
    "Permissions-Policy": "camera=(), geolocation=(), microphone=(), payment=(), usb=()",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
}


def utc_timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def json_response(handler: BaseHTTPRequestHandler, status: int, payload: dict[str, Any]) -> None:
    encoded = json.dumps(payload, indent=2, sort_keys=False).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(encoded)))
    handler.send_header("Cache-Control", "no-store")
    send_browser_security_headers(handler)
    handler.end_headers()
    handler.wfile.write(encoded)


def send_browser_security_headers(handler: BaseHTTPRequestHandler) -> None:
    for header, value in BROWSER_SECURITY_HEADERS.items():
        handler.send_header(header, value)


def normalize_torii_url(value: str | None) -> str | None:
    if not value:
        return None
    return value.rstrip("/")


def url_origin(value: str, *, require_https: bool = False, require_root: bool = False) -> str:
    if not value or any(char.isspace() for char in value) or "\\" in value:
        raise ValueError("Torii URL is invalid")
    try:
        parsed = urllib.parse.urlsplit(value)
        port = parsed.port
    except ValueError as exc:
        raise ValueError("Torii URL is invalid") from exc
    if parsed.scheme.lower() not in {"http", "https"} or not parsed.hostname:
        raise ValueError("Torii URL must be an absolute HTTP(S) URL")
    if require_https and parsed.scheme.lower() != "https":
        raise ValueError("Torii URL must use HTTPS")
    if parsed.username is not None or parsed.password is not None:
        raise ValueError("Torii URL must not contain userinfo")
    if parsed.query or parsed.fragment:
        raise ValueError("Torii URL must not contain a query or fragment")
    if require_root and parsed.path not in {"", "/"}:
        raise ValueError("Torii URL must identify the Torii root")
    host = parsed.hostname.lower().rstrip(".")
    host_literal = f"[{host}]" if ":" in host else host
    default_port = 443 if parsed.scheme.lower() == "https" else 80
    origin = f"{parsed.scheme.lower()}://{host_literal}"
    if port is not None and port != default_port:
        origin += f":{port}"
    return origin


def _file_identity(metadata: os.stat_result) -> tuple[int, ...]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_uid,
        metadata.st_gid,
        stat.S_IFMT(metadata.st_mode),
        stat.S_IMODE(metadata.st_mode),
        metadata.st_nlink,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def read_signer_config_secure(path: Path, environment: str, repo_root: Path) -> dict[str, Any]:
    production = environment == "production"
    nofollow = getattr(os, "O_NOFOLLOW", 0)
    cloexec = getattr(os, "O_CLOEXEC", 0)
    read_flags = os.O_RDONLY | cloexec | nofollow
    dir_flags = os.O_RDONLY | cloexec | nofollow | getattr(os, "O_DIRECTORY", 0)
    resolved_path = path.expanduser()
    if not resolved_path.is_absolute():
        resolved_path = Path.cwd() / resolved_path

    try:
        if production:
            root_input = repo_root.absolute()
            root = repo_root.resolve()
            absolute = resolved_path.absolute()
            try:
                if os.path.commonpath([str(root_input), str(absolute)]) == str(root_input):
                    relative = os.path.relpath(absolute, root_input)
                elif os.path.commonpath([str(root), str(absolute)]) == str(root):
                    relative = os.path.relpath(absolute, root)
                else:
                    raise ValueError
            except ValueError as exc:
                raise ValueError("production signer config must be inside the repository") from exc
            components = Path(relative).parts
            if not components or any(component in {"", ".", ".."} for component in components):
                raise ValueError("production signer config path is invalid")
            relative_label = os.path.join(*components)
            repository_check = subprocess.run(
                ["git", "-C", str(root), "rev-parse", "--is-inside-work-tree"],
                capture_output=True,
                check=False,
                timeout=10,
            )
            if repository_check.returncode != 0:
                raise ValueError("production signer config requires a Git worktree")
            tracked_check = subprocess.run(
                ["git", "-C", str(root), "ls-files", "--error-unmatch", "--", relative_label],
                capture_output=True,
                check=False,
                timeout=10,
            )
            if tracked_check.returncode == 0:
                raise ValueError("production signer config must be untracked")
            ignored_check = subprocess.run(
                ["git", "-C", str(root), "check-ignore", "-q", "--", relative_label],
                capture_output=True,
                check=False,
                timeout=10,
            )
            if ignored_check.returncode != 0:
                raise ValueError("production signer config must be ignored by Git")
            directory_fd = os.open(root, dir_flags)
            try:
                for component in components[:-1]:
                    next_fd = os.open(component, dir_flags, dir_fd=directory_fd)
                    os.close(directory_fd)
                    directory_fd = next_fd
                before = os.stat(components[-1], dir_fd=directory_fd, follow_symlinks=False)
                fd = os.open(components[-1], read_flags, dir_fd=directory_fd)
            finally:
                os.close(directory_fd)
        else:
            before = os.lstat(resolved_path)
            fd = os.open(resolved_path, read_flags)
    except ValueError:
        raise
    except OSError as exc:
        raise ValueError("signer config could not be opened securely") from exc

    if stat.S_ISLNK(before.st_mode) or not stat.S_ISREG(before.st_mode):
        os.close(fd)
        raise ValueError("signer config must be a non-symlink regular file")
    try:
        opened = os.fstat(fd)
        if _file_identity(before) != _file_identity(opened):
            raise ValueError("signer config changed while it was opened")
        if production and (
            stat.S_IMODE(opened.st_mode) != 0o600
            or opened.st_nlink != 1
            or opened.st_uid != os.geteuid()
        ):
            raise ValueError(
                "production signer config must have mode 0600, exactly one hard link, and be owned by the effective user"
            )
        with os.fdopen(fd, "rb", closefd=False) as handle:
            raw = handle.read(1_048_577)
        if len(raw) > 1_048_576:
            raise ValueError("signer config exceeds 1048576 bytes")
        after = os.fstat(fd)
        if _file_identity(opened) != _file_identity(after):
            raise ValueError("signer config changed while it was read")
    finally:
        os.close(fd)
    try:
        config = tomllib.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, tomllib.TOMLDecodeError) as exc:
        raise ValueError("signer config is not valid UTF-8 TOML") from exc
    if not isinstance(config, dict):
        raise ValueError("signer config root must be a TOML table")
    return config


def decode_canonical_base64(value: Any, field_name: str, *, maximum: int) -> bytes:
    if not isinstance(value, str) or not value or len(value) > 4 * ((maximum + 2) // 3):
        raise ValueError(f"{field_name} must be a non-empty canonical padded-base64 string")
    if not CANONICAL_BASE64_RE.fullmatch(value) or any(char.isspace() for char in value):
        raise ValueError(f"{field_name} must be a non-empty canonical padded-base64 string")
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, base64.binascii.Error) as exc:
        raise ValueError(f"{field_name} must be a non-empty canonical padded-base64 string") from exc
    if not decoded or len(decoded) > maximum or base64.b64encode(decoded).decode("ascii") != value:
        raise ValueError(f"{field_name} must be a non-empty canonical padded-base64 string")
    return decoded


def iroha_transaction_signing_message(transaction_payload: bytes) -> bytes:
    digest = bytearray(hashlib.blake2b(transaction_payload, digest_size=32).digest())
    digest[-1] |= 1
    return bytes(digest)


def authority_fee_payment_intent(gas_limit: int) -> dict[str, Any]:
    """Return the sole first-release fee intent used by browser-backed mutations."""

    return {
        "payer": "authority",
        "value": {
            "charge_limits": [],
            "gas_limit": gas_limit,
        },
    }


def validate_authority_fee_payment_intent(
    value: Any,
    *,
    expected_gas_limit: int,
    context: str,
    allow_quoted_charge_limits: bool = False,
) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != {"payer", "value"}:
        raise ValueError(f"{context} must contain only payer and value")
    if value.get("payer") != "authority":
        raise ValueError(f"{context}.payer must be authority")
    payment = value.get("value")
    if not isinstance(payment, dict) or set(payment) != {"charge_limits", "gas_limit"}:
        raise ValueError(f"{context}.value must contain only charge_limits and gas_limit")
    charge_limits = payment.get("charge_limits")
    if not isinstance(charge_limits, list) or len(charge_limits) > 2:
        raise ValueError(f"{context}.value.charge_limits must be a bounded array")
    if charge_limits and not allow_quoted_charge_limits:
        raise ValueError(f"{context}.value.charge_limits must be empty before fee quotation")
    previous_kind_order = -1
    for index, limit in enumerate(charge_limits):
        limit_context = f"{context}.value.charge_limits[{index}]"
        if not isinstance(limit, dict) or set(limit) != {
            "kind",
            "asset_definition_id",
            "max_amount",
        }:
            raise ValueError(
                f"{limit_context} must contain only kind, asset_definition_id, and max_amount"
            )
        tagged_kind = limit.get("kind")
        if not isinstance(tagged_kind, dict) or set(tagged_kind) != {"kind", "value"}:
            raise ValueError(f"{limit_context}.kind must be an exact tagged fee kind")
        kind = tagged_kind.get("kind")
        if kind not in FEE_CHARGE_KIND_ORDER or tagged_kind.get("value") is not None:
            raise ValueError(f"{limit_context}.kind must be nexus or pipeline_gas with null value")
        kind_order = FEE_CHARGE_KIND_ORDER[kind]
        if kind_order <= previous_kind_order:
            raise ValueError(
                f"{context}.value.charge_limits must be unique and ordered nexus before pipeline_gas"
            )
        previous_kind_order = kind_order
        asset_definition_id = limit.get("asset_definition_id")
        if (
            not isinstance(asset_definition_id, str)
            or not asset_definition_id
            or asset_definition_id != asset_definition_id.strip()
            or any(char.isspace() or ord(char) < 0x20 or ord(char) == 0x7F for char in asset_definition_id)
        ):
            raise ValueError(f"{limit_context}.asset_definition_id must be an exact non-empty ID")
        max_amount = limit.get("max_amount")
        quantity_match = CANONICAL_QUANTITY_RE.fullmatch(
            max_amount if isinstance(max_amount, str) else ""
        )
        if quantity_match is None:
            raise ValueError(f"{limit_context}.max_amount must be a positive canonical Quantity")
        integer, fraction = quantity_match.groups()
        fraction = fraction or ""
        digits = integer + fraction
        if (
            len(fraction) > 28
            or len(digits) > 154
            or int(digits) == 0
            or int(digits) > (1 << 511) - 1
        ):
            raise ValueError(f"{limit_context}.max_amount must be a positive canonical Quantity")
    gas_limit = payment.get("gas_limit")
    if (
        isinstance(gas_limit, bool)
        or not isinstance(gas_limit, int)
        or gas_limit != expected_gas_limit
    ):
        raise ValueError(f"{context}.value.gas_limit does not match the requested gas limit")
    return value


def sign_transaction_message_ed25519(private_key: str, public_key: str | None, message: bytes) -> str:
    if len(message) != 32:
        raise ValueError("signing message must be the exact 32-byte prepared transaction hash")
    return sign_ed25519_message(
        private_key,
        public_key,
        message,
        context="detached transaction signing",
    )


def validate_prepared_transaction(response_json: dict[str, Any], *, context: str) -> dict[str, Any]:
    transaction_payload_b64 = response_json.get("transaction_payload_b64")
    signing_message_b64 = response_json.get("signing_message_b64")
    transaction_payload = decode_canonical_base64(
        transaction_payload_b64,
        "transaction_payload_b64",
        maximum=16 * 1024 * 1024,
    )
    signing_message = decode_canonical_base64(
        signing_message_b64,
        "signing_message_b64",
        maximum=32,
    )
    if len(signing_message) != 32 or signing_message != iroha_transaction_signing_message(
        transaction_payload
    ):
        raise ValueError(
            f"{context} signing message does not match the exact canonical transaction payload"
        )
    return {
        "transaction_payload_b64": transaction_payload_b64,
        "signing_message": signing_message,
        "signing_message_b64": signing_message_b64,
    }


def _required_lower_hash(value: Any, field_name: str) -> str:
    if (
        not isinstance(value, str)
        or LOWER_NONZERO_HASH_RE.fullmatch(value) is None
        or set(value) == {"0"}
    ):
        raise ValueError(f"{field_name} must be a nonzero lowercase 32-byte hash")
    return value


def validate_contract_call_response(
    response_json: Any,
    *,
    expected_request: dict[str, Any],
    submitted: bool,
    expected_preparation: dict[str, Any] | None = None,
) -> dict[str, Any]:
    context = "contract call submission" if submitted else "contract call preparation"
    if not isinstance(response_json, dict):
        raise ValueError(f"{context} response must be a JSON object")
    unknown = set(response_json) - CONTRACT_CALL_RESPONSE_FIELDS
    missing = CONTRACT_CALL_REQUIRED_RESPONSE_FIELDS - set(response_json)
    if unknown or missing:
        raise ValueError(f"{context} response does not match the closed first-release DTO")
    if response_json.get("ok") is not True or response_json.get("submitted") is not submitted:
        raise ValueError(f"{context} response has an invalid ok/submitted state")

    creation_time_ms = response_json.get("creation_time_ms")
    if (
        isinstance(creation_time_ms, bool)
        or not isinstance(creation_time_ms, int)
        or creation_time_ms <= 0
    ):
        raise ValueError(f"{context} response requires a positive creation_time_ms")
    if submitted and creation_time_ms != expected_request.get("creation_time_ms"):
        raise ValueError("contract call submission changed the prepared creation_time_ms")
    if response_json.get("contract_address") != expected_request.get("contract_address"):
        raise ValueError(f"{context} response changed the requested contract address")
    if response_json.get("entrypoint") != expected_request.get("entrypoint"):
        raise ValueError(f"{context} response changed the requested entrypoint")
    dataspace = response_json.get("dataspace")
    if not isinstance(dataspace, str) or not dataspace:
        raise ValueError(f"{context} response requires a dataspace")
    code_hash_hex = _required_lower_hash(response_json.get("code_hash_hex"), "code_hash_hex")
    abi_hash_hex = _required_lower_hash(response_json.get("abi_hash_hex"), "abi_hash_hex")

    receipt = response_json.get("operation_receipt")
    if not isinstance(receipt, dict):
        raise ValueError(f"{context} operation_receipt must be an object")
    if set(receipt) - CONTRACT_CALL_RECEIPT_FIELDS or (
        CONTRACT_CALL_REQUIRED_RECEIPT_FIELDS - set(receipt)
    ):
        raise ValueError(f"{context} operation_receipt does not match the closed first-release DTO")
    expected_status = "submitted" if submitted else "pending_signature"
    if (
        receipt.get("operation_kind") != "contract_call"
        or receipt.get("status") != expected_status
        or receipt.get("transport") != "torii"
        or receipt.get("dataspace") != dataspace
        or receipt.get("contract_address") != expected_request.get("contract_address")
        or receipt.get("code_hash_hex") != code_hash_hex
        or receipt.get("abi_hash_hex") != abi_hash_hex
        or receipt.get("entrypoint") != expected_request.get("entrypoint")
    ):
        raise ValueError(f"{context} operation_receipt is not bound to the requested call")
    gas_limit = expected_request["fee_payment"]["value"]["gas_limit"]
    if receipt.get("gas_limit") != gas_limit:
        raise ValueError(f"{context} operation_receipt changed the requested gas limit")
    fee_payment = validate_authority_fee_payment_intent(
        receipt.get("fee_payment"),
        expected_gas_limit=gas_limit,
        context=f"{context} operation_receipt.fee_payment",
        allow_quoted_charge_limits=True,
    )
    if receipt.get("gas_used") is not None:
        raise ValueError(f"{context} operation_receipt.gas_used must be absent or null")
    payload_digest_hex = _required_lower_hash(
        receipt.get("payload_digest_hex"), "payload_digest_hex"
    )

    stable = {
        "dataspace": dataspace,
        "contract_address": response_json["contract_address"],
        "code_hash_hex": code_hash_hex,
        "abi_hash_hex": abi_hash_hex,
        "creation_time_ms": creation_time_ms,
        "transaction_ttl_ms": response_json.get("transaction_ttl_ms"),
        "entrypoint": response_json["entrypoint"],
        "contract_alias": receipt.get("contract_alias"),
        "gas_limit": gas_limit,
        "fee_payment": fee_payment,
        "payload_digest_hex": payload_digest_hex,
    }
    if expected_preparation is not None and stable != expected_preparation["stable"]:
        raise ValueError("contract call submission metadata does not match preparation")

    if not submitted:
        if any(
            response_json.get(field) is not None
            for field in ("tx_hash_hex", "entrypoint_hash_hex", "pipeline_status")
        ):
            raise ValueError("contract call preparation must not include submission state")
        draft = validate_prepared_transaction(response_json, context=context)
        return {**draft, "creation_time_ms": creation_time_ms, "stable": stable}

    tx_hash_hex = _required_lower_hash(response_json.get("tx_hash_hex"), "tx_hash_hex")
    entrypoint_hash_hex = _required_lower_hash(
        response_json.get("entrypoint_hash_hex"), "entrypoint_hash_hex"
    )
    if response_json.get("transaction_payload_b64") is not None or response_json.get(
        "signing_message_b64"
    ) is not None:
        raise ValueError("contract call submission must not return preparation material")
    if receipt.get("tx_hash_hex") != tx_hash_hex or receipt.get("entrypoint_hash_hex") != entrypoint_hash_hex:
        raise ValueError("contract call submission receipt hashes do not match the response")
    return {"tx_hash_hex": tx_hash_hex, "entrypoint_hash_hex": entrypoint_hash_hex, "stable": stable}


def execute_detached_contract_call(
    execute_upstream_request: Any,
    *,
    environment: str,
    signer: "SignerBinding",
    torii_url: str,
    request_payload: dict[str, Any],
    timeout: int,
) -> dict[str, Any]:
    """Prepare, verify, sign locally, and submit one current Torii contract call."""

    preparation_payload = execute_upstream_request(
        environment=environment,
        signer=signer,
        torii_url=torii_url,
        mode="call-prepare",
        path="/v1/contracts/call",
        request_payload=request_payload,
        timeout=timeout,
    )
    if not preparation_payload.get("ok"):
        return preparation_payload
    try:
        prepared = validate_contract_call_response(
            preparation_payload.get("response_json"),
            expected_request=request_payload,
            submitted=False,
        )
        signature_b64 = sign_transaction_message_ed25519(
            str(signer.private_key or ""),
            signer.public_key,
            prepared["signing_message"],
        )
        public_key_hex = raw_ed25519_public_key_hex(signer.public_key)
    except ValueError as exc:
        return {
            "ok": False,
            "error_code": "contract_call_detached_signing_failed",
            "error": str(exc),
            "preparation": preparation_payload,
        }

    submission_request = {
        **request_payload,
        "public_key_hex": public_key_hex,
        "signature_b64": signature_b64,
        "creation_time_ms": prepared["creation_time_ms"],
    }
    submission_payload = execute_upstream_request(
        environment=environment,
        signer=signer,
        torii_url=torii_url,
        mode="call-submit",
        path="/v1/contracts/call",
        request_payload=submission_request,
        timeout=timeout,
    )
    if not submission_payload.get("ok"):
        submission_payload["preparation"] = preparation_payload
        return submission_payload
    try:
        submitted = validate_contract_call_response(
            submission_payload.get("response_json"),
            expected_request=submission_request,
            submitted=True,
            expected_preparation=prepared,
        )
    except ValueError as exc:
        submission_payload["ok"] = False
        submission_payload["error_code"] = "invalid_contract_call_submission_response"
        submission_payload["error"] = str(exc)
        submission_payload["preparation"] = preparation_payload
        return submission_payload

    submission_payload["tx_hash_hex"] = submitted["tx_hash_hex"]
    submission_payload["detached_signing"] = {
        "prepared": True,
        "locally_signed": True,
        "submitted": True,
        "creation_time_ms": prepared["creation_time_ms"],
        "public_key_encoding": "raw_ed25519_hex",
        "private_key_forwarded": False,
    }
    return submission_payload


def validate_bridge_response_metadata(response_json: dict[str, Any]) -> dict[str, Any]:
    if set(response_json) != BRIDGE_RESPONSE_FIELDS:
        raise ValueError("bridge response does not match the closed first-release DTO")
    if response_json.get("payload_kind") != "transfer":
        raise ValueError("bridge response payload_kind must be transfer")
    message_id_hex = response_json.get("message_id_hex")
    if (
        not isinstance(message_id_hex, str)
        or LOWER_NONZERO_HASH_RE.fullmatch(message_id_hex) is None
        or set(message_id_hex) == {"0"}
    ):
        raise ValueError("bridge response requires a nonzero lowercase 32-byte message_id_hex")
    backend = response_json.get("backend")
    if not isinstance(backend, str) or not backend or re.fullmatch(r"[a-z0-9/_-]+", backend) is None:
        raise ValueError("bridge response requires a canonical backend label")
    counterparty_domain = response_json.get("counterparty_domain")
    if (
        isinstance(counterparty_domain, bool)
        or not isinstance(counterparty_domain, int)
        or counterparty_domain <= 0
    ):
        raise ValueError("bridge response requires a positive counterparty_domain")
    counterparty_chain = response_json.get("counterparty_chain")
    if counterparty_chain not in SCCP_EXTERNAL_PROFILES:
        raise ValueError("bridge response names an unsupported exact counterparty_chain")
    route_hash = response_json.get("route_configuration_hash_hex")
    if (
        not isinstance(route_hash, str)
        or LOWER_NONZERO_HASH_RE.fullmatch(route_hash) is None
        or set(route_hash) == {"0"}
    ):
        raise ValueError(
            "bridge response requires a nonzero lowercase 32-byte route_configuration_hash_hex"
        )
    range_start = response_json.get("range_start_height")
    range_end = response_json.get("range_end_height")
    if (
        isinstance(range_start, bool)
        or not isinstance(range_start, int)
        or range_start <= 0
        or isinstance(range_end, bool)
        or not isinstance(range_end, int)
        or range_end < range_start
    ):
        raise ValueError("bridge response requires a positive ordered proof-height range")
    creation_time_ms = response_json.get("creation_time_ms")
    if isinstance(creation_time_ms, bool) or not isinstance(creation_time_ms, int) or creation_time_ms <= 0:
        raise ValueError("bridge response requires a positive creation_time_ms")
    return {
        "payload_kind": response_json["payload_kind"],
        "message_id_hex": message_id_hex,
        "backend": backend,
        "counterparty_domain": counterparty_domain,
        "counterparty_chain": counterparty_chain,
        "route_configuration_hash_hex": route_hash,
        "range_start_height": range_start,
        "range_end_height": range_end,
        "creation_time_ms": creation_time_ms,
    }


def validate_bridge_preparation_response(response_json: Any) -> dict[str, Any]:
    if not isinstance(response_json, dict) or response_json.get("submitted") is not False:
        raise ValueError("bridge preparation response must record submitted=false")
    metadata = validate_bridge_response_metadata(response_json)
    if response_json.get("tx_hash_hex") is not None:
        raise ValueError("bridge preparation response must not include a transaction hash")
    draft = validate_prepared_transaction(response_json, context="bridge preparation")
    return {
        **draft,
        "creation_time_ms": metadata["creation_time_ms"],
        "metadata": metadata,
    }


def validate_bridge_submission_response(
    response_json: Any,
    *,
    expected_metadata: dict[str, Any],
) -> str:
    if not isinstance(response_json, dict) or response_json.get("submitted") is not True:
        raise ValueError("bridge submission response must record submitted=true")
    metadata = validate_bridge_response_metadata(response_json)
    if metadata != expected_metadata:
        raise ValueError("submitted bridge response metadata does not match preparation")
    for preparation_field in ("transaction_payload_b64", "signing_message_b64"):
        if response_json.get(preparation_field) is not None:
            raise ValueError("submitted bridge response must null preparation fields")
    tx_hash_hex = response_json.get("tx_hash_hex")
    if (
        not isinstance(tx_hash_hex, str)
        or LOWER_NONZERO_HASH_RE.fullmatch(tx_hash_hex) is None
        or set(tx_hash_hex) == {"0"}
    ):
        raise ValueError("submitted bridge response requires a nonzero lowercase 32-byte tx_hash_hex")
    return tx_hash_hex


def parse_assignment(values: list[str] | None, label: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for raw in values or []:
        if "=" not in raw:
            raise ValueError(f"{label} values must use ENV=VALUE form: {raw}")
        environment, value = raw.split("=", 1)
        environment = environment.strip()
        value = value.strip()
        if not environment or not value:
            raise ValueError(f"{label} values must use ENV=VALUE form: {raw}")
        result[environment] = value
    return result


def parse_tcp_port_arg(value: str) -> int:
    if not re.fullmatch(r"[1-9][0-9]*", value):
        raise argparse.ArgumentTypeError("must be a positive integer no greater than 65535")
    port = int(value)
    if port > 65535:
        raise argparse.ArgumentTypeError("must be a positive integer no greater than 65535")
    return port


def safe_read_json(path: Path) -> dict[str, Any] | list[Any] | None:
    if not path.exists():
        return None
    with path.open("rb") as handle:
        return json.load(handle)


def chain_identity(value: dict[str, Any] | None) -> tuple[str | None, str | None]:
    if not isinstance(value, dict):
        return None, None
    chain = value.get("chain")
    block_1_hash = value.get("block_1_hash")
    return (
        str(chain).strip() if isinstance(chain, str) and chain.strip() else None,
        str(block_1_hash).strip() if isinstance(block_1_hash, str) and block_1_hash.strip() else None,
    )


def chain_fingerprint_matches_chain(record: dict[str, Any], chain: dict[str, Any]) -> bool:
    record_chain, record_block_1_hash = chain_identity(record)
    chain_id, chain_block_1_hash = chain_identity(chain)
    record_torii_url = nonempty_string(record.get("torii_url"))
    chain_torii_url = nonempty_string(chain.get("torii_url"))
    return bool(
        record_torii_url
        and record_chain
        and record_block_1_hash
        and chain_torii_url
        and chain_id
        and chain_block_1_hash
        and record_torii_url == chain_torii_url
        and record_chain == chain_id
        and record_block_1_hash == chain_block_1_hash
    )


def nonempty_string(value: Any) -> str | None:
    return str(value).strip() if isinstance(value, str) and value.strip() else None


def has_generated_at(record: dict[str, Any]) -> bool:
    return bool(nonempty_string(record.get("generated_at")))


def generated_at_value(record: dict[str, Any]) -> str | None:
    return nonempty_string(record.get("generated_at"))


def positive_decimalish(value: Any) -> bool:
    if isinstance(value, bool):
        return False
    try:
        parsed = Decimal(str(value).strip())
    except (InvalidOperation, ValueError):
        return False
    return parsed.is_finite() and parsed > 0


def contract_address_from_evidence(record: dict[str, Any]) -> str | None:
    return nonempty_string(record.get("contract_address"))


def deploy_nonce_from_evidence(record: dict[str, Any]) -> Any:
    return record.get("deploy_nonce") if "deploy_nonce" in record else None


def iroha_literal_crc16(tag: str, body: str) -> int:
    crc = 0xFFFF
    for byte in f"{tag}:{body}".encode("ascii"):
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def canonical_hash_literal_hex(value: Any) -> str | None:
    match = CANONICAL_HASH_LITERAL_RE.fullmatch(value if isinstance(value, str) else "")
    if match is None:
        return None
    body, checksum = match.groups()
    if checksum != f"{iroha_literal_crc16('hash', body):04X}" or set(body) == {"0"}:
        return None
    return body.lower()


def hash_from_evidence(record: dict[str, Any], field: str) -> str | None:
    value = record.get(field)
    if (
        not isinstance(value, str)
        or LOWER_NONZERO_HASH_RE.fullmatch(value) is None
        or set(value) == {"0"}
    ):
        return None
    return value


def manifest_hash(manifest: dict[str, Any], field: str) -> str | None:
    return canonical_hash_literal_hex(manifest.get(field))


def current_contract_deploy_response_matches_record(
    response: Any,
    record: dict[str, Any],
) -> bool:
    if not isinstance(response, dict) or set(response) != CONTRACT_DEPLOY_RESPONSE_FIELDS:
        return False
    deploy_nonce = deploy_nonce_from_evidence(record)
    final = response.get("final")
    commit_hash = response.get("commit_deployment_tx_hash")
    commit_hash_hex = canonical_hash_literal_hex(commit_hash)
    register_manifest_hash = canonical_hash_literal_hex(response.get("register_manifest_tx_hash"))
    register_bytes_hash = response.get("register_bytes_tx_hash")
    stage_hashes = response.get("register_bytes_stage_tx_hashes")
    deployment_state = response.get("deployment_state")
    deployment_state_matches = bool(
        isinstance(deployment_state, dict)
        and set(deployment_state)
        == {
            "authority",
            "chain_discriminant",
            "contract_alias",
            "dataspace_alias",
            "dataspace_id",
            "deploy_nonce",
            "ledger_time_ms",
            "observed_block_hash",
            "observed_block_height",
            "previous_contract_address",
        }
        and deployment_state.get("authority") == response.get("authority")
        and deployment_state.get("contract_alias") == response.get("contract_alias")
        and deployment_state.get("deploy_nonce") == str(deploy_nonce)
        and deployment_state.get("dataspace_alias") == record.get("dataspace_alias")
        and deployment_state.get("dataspace_id") == record.get("dataspace_id")
        and deployment_state.get("previous_contract_address")
        == response.get("expected_previous_contract_address")
        and isinstance(deployment_state.get("observed_block_height"), str)
        and CANONICAL_DECIMAL_STRING_RE.fullmatch(
            deployment_state["observed_block_height"]
        )
        is not None
        and int(deployment_state["observed_block_height"]) > 0
        and hash_from_evidence(deployment_state, "observed_block_hash")
        and isinstance(deployment_state.get("ledger_time_ms"), str)
        and CANONICAL_DECIMAL_STRING_RE.fullmatch(deployment_state["ledger_time_ms"])
        is not None
        and deployment_state.get("chain_discriminant")
        == str(response.get("chain_discriminant"))
    )
    receipt = response.get("operation_receipt")
    receipt_matches = bool(
        isinstance(receipt, dict)
        and set(receipt) == CONTRACT_DEPLOY_RECEIPT_FIELDS
        and receipt.get("operation_kind") == "contract_deploy"
        and receipt.get("status") == "committed"
        and receipt.get("transport") == "ivm-contract-deploy-helper"
        and receipt.get("torii_url") == response.get("torii_url")
        and receipt.get("chain_id") == response.get("chain_id")
        and receipt.get("authority") == response.get("authority")
        and receipt.get("chain_discriminant") == response.get("chain_discriminant")
        and receipt.get("dataspace") == response.get("dataspace")
        and receipt.get("contract_alias") == response.get("contract_alias")
        and receipt.get("contract_address") == response.get("contract_address")
        and receipt.get("contract_subject_account") == response.get("contract_subject_account")
        and receipt.get("code_hash_hex") == response.get("code_hash_hex")
        and receipt.get("abi_hash_hex") is None
        and receipt.get("tx_hash_hex") == commit_hash_hex
        and receipt.get("entrypoint") is None
        and receipt.get("entrypoint_hash_hex") is None
        and receipt.get("gas_used") is None
        and isinstance(receipt.get("fee_payment"), dict)
        and receipt.get("fee_quotes") == response.get("fee_quotes")
        and hash_from_evidence(receipt, "payload_digest_hex")
        and receipt.get("deployment_state") == response.get("deployment_state")
    )
    return bool(
        response.get("ok") is True
        and response.get("submitted") is True
        and response.get("terminal_kind") == "Committed"
        and isinstance(final, dict)
        and set(final) == {"kind", "hash"}
        and final.get("kind") == "Committed"
        and commit_hash_hex
        and final.get("hash") == commit_hash
        and response.get("contract_address") == contract_address_from_evidence(record)
        and response.get("contract_alias") == nonempty_string(record.get("contract_alias"))
        and response.get("dataspace") == record.get("dataspace_id")
        and response.get("deploy_nonce") == deploy_nonce
        and isinstance(deploy_nonce, int)
        and not isinstance(deploy_nonce, bool)
        and deploy_nonce >= 0
        and response.get("next_deploy_nonce") == deploy_nonce + 1
        and response.get("code_hash_hex") == hash_from_evidence(record, "code_hash_hex")
        and receipt_matches
        and deployment_state_matches
        and isinstance(response.get("fee_quotes"), list)
        and isinstance(stage_hashes, list)
        and all(hash_from_evidence({"value": item}, "value") for item in stage_hashes)
        and hash_from_evidence({"value": register_bytes_hash}, "value")
        and register_manifest_hash
        and response.get("register_bytes_tx_strategy") == "native_chunks"
        and response.get("register_bytes_chunk_size") == 65_536
        and isinstance(response.get("register_bytes_chunk_count"), int)
        and not isinstance(response.get("register_bytes_chunk_count"), bool)
        and response.get("register_bytes_chunk_count") > 0
        and nonempty_string(response.get("authority"))
        and nonempty_string(response.get("chain_id"))
        and nonempty_string(response.get("contract_subject_account"))
        and nonempty_string(response.get("torii_url"))
    )


def current_deployment_record_shape(record: Any) -> bool:
    if not isinstance(record, dict) or set(record) != DEPLOYMENT_RECORD_FIELDS:
        return False
    return bool(
        has_generated_at(record)
        and nonempty_string(record.get("contract_key"))
        and nonempty_string(record.get("environment"))
        and nonempty_string(record.get("contract_source"))
        and nonempty_string(record.get("contract_alias"))
        and record.get("contract_alias").endswith(
            (
                f".{DEPLOYMENT_DATASPACE_ALIAS}",
                f"::{DEPLOYMENT_DATASPACE_ALIAS}",
            )
        )
        and record.get("dataspace_alias") == DEPLOYMENT_DATASPACE_ALIAS
        and record.get("dataspace_id") == DEPLOYMENT_DATASPACE_ID
        and contract_address_from_evidence(record)
        and hash_from_evidence(record, "code_hash_hex")
        and hash_from_evidence(record, "abi_hash_hex")
        and record.get("deploy_strategy") == CURRENT_DEPLOY_STRATEGY
        and current_chain_fingerprint_shape(record.get("chain_fingerprint"))
        and current_contract_deploy_response_matches_record(record.get("response"), record)
    )


def current_chain_fingerprint_shape(value: Any) -> bool:
    return bool(
        isinstance(value, dict)
        and set(value) == CHAIN_FINGERPRINT_FIELDS
        and all(nonempty_string(value.get(field)) for field in CHAIN_FINGERPRINT_FIELDS)
    )


def contains_local_diagnostic_path(value: Any) -> bool:
    if isinstance(value, str):
        return LOCAL_DIAGNOSTIC_PATH_RE.search(value) is not None
    if isinstance(value, dict):
        for key, nested in value.items():
            if contains_local_diagnostic_path(key) or contains_local_diagnostic_path(nested):
                return True
        return False
    if isinstance(value, list):
        return any(contains_local_diagnostic_path(item) for item in value)
    return False


def contract_evidence_records(contracts_latest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    records: dict[str, dict[str, Any]] = {}
    items = contracts_latest.get("contracts")
    if not isinstance(items, list):
        return records
    for item in items:
        if not isinstance(item, dict):
            continue
        contract_key = nonempty_string(item.get("contract_key"))
        if contract_key:
            records[contract_key] = item
    return records


def contract_evidence_duplicate_keys(contracts_latest: dict[str, Any] | list[Any] | None) -> list[str]:
    if not isinstance(contracts_latest, dict):
        return []
    items = contracts_latest.get("contracts")
    if not isinstance(items, list):
        return []

    seen: set[str] = set()
    duplicates: set[str] = set()
    for item in items:
        if not isinstance(item, dict):
            continue
        contract_key = nonempty_string(item.get("contract_key"))
        if not contract_key:
            continue
        if contract_key in seen:
            duplicates.add(contract_key)
        seen.add(contract_key)
    return sorted(duplicates)


def deployment_manifest_matches_environment(
    manifest: dict[str, Any] | list[Any] | None,
    environment: str,
    contract_key: str,
) -> bool:
    return bool(
        isinstance(manifest, dict)
        and has_generated_at(manifest)
        and manifest.get("environment") == environment
        and nonempty_string(manifest.get("contract_key")) == contract_key
        and manifest_hash(manifest, "code_hash")
        and manifest_hash(manifest, "abi_hash")
    )


def deployment_manifest_hashes_match_evidence(
    manifest: dict[str, Any] | list[Any] | None,
    record: dict[str, Any],
) -> bool:
    if not isinstance(manifest, dict):
        return False
    expected_code_hash = hash_from_evidence(record, "code_hash_hex")
    expected_abi_hash = hash_from_evidence(record, "abi_hash_hex")
    return bool(
        expected_code_hash
        and expected_abi_hash
        and manifest_hash(manifest, "code_hash") == expected_code_hash
        and manifest_hash(manifest, "abi_hash") == expected_abi_hash
    )


def record_matches_catalog_chain(record: dict[str, Any], chain_fingerprint: dict[str, Any] | None) -> bool:
    record_chain = record.get("chain_fingerprint")
    return bool(
        chain_fingerprint is not None
        and isinstance(record_chain, dict)
        and chain_fingerprint_matches_chain(record_chain, chain_fingerprint)
    )


def deployment_record_matches_catalog_evidence(
    record: dict[str, Any],
    manifest: dict[str, Any] | list[Any] | None,
    environment: str,
    contract_key: str,
    chain_fingerprint: dict[str, Any] | None,
) -> bool:
    return bool(
        current_deployment_record_shape(record)
        and record.get("environment") == environment
        and nonempty_string(record.get("contract_key")) == contract_key
        and record.get("deploy_strategy") == CURRENT_DEPLOY_STRATEGY
        and record_matches_catalog_chain(record, chain_fingerprint)
        and deployment_manifest_matches_environment(manifest, environment, contract_key)
        and deployment_manifest_hashes_match_evidence(manifest, record)
    )


def required_contract_keys_from_repo(repo_root: Path) -> list[str]:
    contracts_root = repo_root / "contracts"
    if not contracts_root.is_dir():
        return []

    keys: list[str] = []
    for source in sorted(contracts_root.rglob("*.ko")):
        relative = source.relative_to(contracts_root).with_suffix("")
        keys.append(".".join(relative.parts))
    return keys


def catalog_display_path(path: Path | None, repo_root: Path) -> str | None:
    if path is None or not path.exists():
        return None
    try:
        return path.relative_to(repo_root).as_posix()
    except ValueError:
        return path.name


def catalog_display_record_path(value: Any, repo_root: Path) -> Any:
    if not isinstance(value, str) or not value:
        return value
    path = Path(value).expanduser()
    if not path.is_absolute():
        return value
    try:
        return path.relative_to(repo_root).as_posix()
    except ValueError:
        return path.name


def safe_read_toml(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    with path.open("rb") as handle:
        return tomllib.load(handle)


def account_config_string(config: dict[str, Any], key: str) -> str | None:
    account = config.get("account")
    if not isinstance(account, dict):
        return None
    return nonempty_string(account.get(key))


def looks_like_placeholder(value: str | None) -> bool:
    if value is None:
        return True
    normalized = value.strip().lower()
    if not normalized:
        return True
    if normalized in PLACEHOLDER_EXACT_VALUES:
        return True
    if normalized.startswith("<") and normalized.endswith(">"):
        return True
    return bool(PLACEHOLDER_TOKEN_RE.search(normalized))


def looks_like_reserved_public_endpoint(value: str | None) -> bool:
    normalized = normalize_torii_url(value)
    if not normalized:
        return True
    if looks_like_placeholder(normalized):
        return True
    parsed = urllib.parse.urlparse(normalized)
    host = (parsed.hostname or "").strip().lower().rstrip(".")
    if not host:
        return True
    if host in RESERVED_PUBLIC_HOSTS:
        return True
    if host.endswith(RESERVED_PUBLIC_HOST_SUFFIXES):
        return True
    return host.endswith(RESERVED_PUBLIC_HOST_TRAILING_SUFFIXES)


def candidate_default_signer_configs(repo_root: Path) -> dict[str, Path]:
    configured_localnet_dir = Path(
        os.environ.get("SORASWAP_LOCALNET_DIR", str(repo_root / "tmp" / "iroha-localnet"))
    ).expanduser()
    if not configured_localnet_dir.is_absolute():
        configured_localnet_dir = (Path.cwd() / configured_localnet_dir).resolve()
    return {
        "local": configured_localnet_dir / "client.toml",
        "testnet": repo_root / "config" / "testnet" / "taira.client.toml",
        "production": repo_root / "config" / "production" / "production.client.toml",
    }


def config_supports_autodiscovery(path: Path, environment: str, repo_root: Path) -> bool:
    try:
        parsed = read_signer_config_secure(path, environment, repo_root)
        canonical_network_id_bytes(parsed.get("network_id"))
    except (OSError, ValueError):
        return False
    if environment in PUBLIC_MUTATION_ENVIRONMENTS and looks_like_reserved_public_endpoint(parsed.get("torii_url")):
        return False
    public_key = account_config_string(parsed, "public_key")
    private_key = account_config_string(parsed, "private_key")
    return bool(
        isinstance(public_key, str)
        and not looks_like_placeholder(public_key)
        and isinstance(private_key, str)
        and not looks_like_placeholder(private_key)
    )


def entrypoint_kind(entrypoint: dict[str, Any]) -> str:
    return str(((entrypoint.get("kind") or {}).get("kind")) or "Unknown")


def sanitize_manifest_entrypoints(manifest: dict[str, Any] | None) -> list[dict[str, Any]]:
    if not manifest:
        return []

    sanitized: list[dict[str, Any]] = []
    for entrypoint in manifest.get("entrypoints") or []:
        params: list[dict[str, Any]] = []
        for param in entrypoint.get("params") or []:
            params.append(
                {
                    "name": param.get("name"),
                    "type_name": param.get("type_name"),
                }
            )

        sanitized.append(
            {
                "name": entrypoint.get("name"),
                "kind": entrypoint_kind(entrypoint),
                "return_type": entrypoint.get("return_type"),
                "permission": entrypoint.get("permission"),
                "params": params,
            }
        )
    return sanitized


def validate_manifest_numeric_arguments(
    environment_record: dict[str, Any],
    *,
    contract_address: str,
    entrypoint_name: str,
    payload: Any,
    context: str = "payload",
) -> None:
    if payload is None:
        return
    if not isinstance(payload, dict):
        raise ValueError(f"{context} must be a JSON object")

    contract = next(
        (
            item
            for item in environment_record.get("contracts") or []
            if item.get("contract_address") == contract_address
        ),
        None,
    )
    if not isinstance(contract, dict):
        return
    entrypoint = next(
        (
            item
            for item in contract.get("entrypoints") or []
            if item.get("name") == entrypoint_name
        ),
        None,
    )
    if not isinstance(entrypoint, dict):
        return

    for parameter in entrypoint.get("params") or []:
        name = parameter.get("name")
        type_name = parameter.get("type_name")
        if not isinstance(name, str) or type_name not in MANIFEST_NUMERIC_TYPES or name not in payload:
            continue
        value = payload[name]
        valid = False
        if isinstance(value, str):
            if type_name == "int":
                valid = CANONICAL_INT_ARGUMENT_RE.fullmatch(value) is not None
            elif type_name == "quantity":
                valid = CANONICAL_QUANTITY_RE.fullmatch(value) is not None
            else:
                valid = (
                    value != "-0"
                    and CANONICAL_DECIMAL_ARGUMENT_RE.fullmatch(value) is not None
                )
        if not valid:
            raise ValueError(
                f"{context}.{name} for manifest type {type_name} must be an exact canonical JSON string"
            )


def infer_network_prefix(environment: str | None, configured_discriminant: int | None = None) -> str:
    normalized_environment = (environment or "").strip().lower()
    if configured_discriminant is not None:
        if isinstance(configured_discriminant, bool) or not 0 <= configured_discriminant <= 65_535:
            raise ValueError("configured chain discriminant must fit u16")
        if normalized_environment == "production" and configured_discriminant == TAIRA_NETWORK_PREFIX:
            raise ValueError("production must not use the Taira chain discriminant")
        return str(configured_discriminant)
    if normalized_environment == "testnet":
        return TESTNET_NETWORK_PREFIX
    if normalized_environment == "production":
        raw = os.environ.get("SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT", "")
        if not re.fullmatch(r"0|[1-9][0-9]*", raw):
            raise ValueError("production chain discriminant is required and must be canonical decimal")
        value = int(raw)
        if value > 65_535 or value == TAIRA_NETWORK_PREFIX:
            raise ValueError("production chain discriminant must fit u16 and must not be Taira")
        return raw
    return os.environ.get("SORASWAP_ADDRESS_NETWORK_PREFIX", DEFAULT_NETWORK_PREFIX)


def redact_local_warning_paths(message: str) -> str:
    redacted = message
    replacements = [
        (REPO_ROOT.parent / "iroha", "../iroha"),
        (REPO_ROOT, REPO_ROOT.name),
        (REPO_ROOT.parent, ".."),
    ]
    for path, replacement in replacements:
        redacted = redacted.replace(str(path), replacement)
    redacted = LOCAL_RUNTIME_PATH_RE.sub(
        lambda match: f"[runtime-path]/{Path(match.group('path')).name}",
        redacted,
    )
    redacted = LOCAL_USER_PATH_RE.sub(
        lambda match: f"[local-path]/{Path(match.group('path')).name}",
        redacted,
    )
    return redacted


def derive_authority_from_public_key(
    public_key: str, environment: str | None, configured_discriminant: int | None = None
) -> tuple[str | None, str | None]:
    explicit_cli = os.environ.get("SORASWAP_IROHA_CLI_BIN", "").strip()
    configured_root = os.environ.get("SORASWAP_IROHA_ROOT", "").strip()
    if explicit_cli:
        iroha_cli = Path(explicit_cli).expanduser().absolute()
    elif configured_root:
        iroha_root = Path(configured_root).expanduser().absolute()
        debug_cli = iroha_root / "target" / "debug" / "iroha"
        release_cli = iroha_root / "target" / "release" / "iroha"
        iroha_cli = debug_cli if debug_cli.exists() else release_cli
    else:
        iroha_cli = REPO_ROOT.parent / "iroha" / "target" / "debug" / "iroha"
    if not iroha_cli.is_file() or not os.access(iroha_cli, os.X_OK):
        if not explicit_cli and not configured_root:
            return None, "missing iroha CLI at ../iroha/target/debug/iroha"
        return None, f"missing executable iroha CLI: {redact_local_warning_paths(str(iroha_cli))}"

    try:
        network_prefix = infer_network_prefix(environment, configured_discriminant)
    except ValueError as exc:
        return None, str(exc)
    command = [
        str(iroha_cli),
        "--output-format",
        "text",
        "tools",
        "address",
        "convert",
        "--network-prefix",
        network_prefix,
        public_key,
    ]
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
            timeout=20,
        )
    except Exception as exc:  # pragma: no cover - defensive path
        detail = redact_local_warning_paths(str(exc)) or exc.__class__.__name__
        return None, f"failed to derive authority with sibling iroha CLI: {detail}"

    if completed.returncode != 0:
        stderr = completed.stderr.strip() or completed.stdout.strip() or "unknown error"
        return None, f"failed to derive authority with sibling iroha CLI: {redact_local_warning_paths(stderr)}"

    lines = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    if not lines:
        return None, "failed to derive authority: empty iroha CLI output"
    return lines[-1], None


@dataclass
class SignerBinding:
    environment: str
    config_path: Path | None
    authority: str | None
    torii_url: str | None
    network_id: str | None
    private_key: str | None
    public_key: str | None
    basic_auth: tuple[str, str] | None
    warnings: list[str]
    source: str = "none"
    chain_discriminant: int | None = None

    @property
    def configured(self) -> bool:
        return self.config_path is not None

    @property
    def can_call(self) -> bool:
        return (
            self.configured
            and bool(self.private_key)
            and bool(self.public_key)
            and bool(self.authority)
            and bool(self.network_id)
        )

    @property
    def can_authenticate_requests(self) -> bool:
        return bool(self.private_key and self.public_key and self.network_id)


def require_bound_request_signer(
    signer: SignerBinding,
    *,
    authority: str,
    environment: str,
) -> None:
    if not signer.can_call:
        raise ValueError(
            f"no signer config with network_id, authority, and an Ed25519 keypair is bound for "
            f"environment {environment}; start the service with --signer ENV=/path/to/client.toml"
        )
    if authority != signer.authority:
        raise ValueError("request authority does not match the bound canonical request signer")


def canonical_account_request_headers(
    signer: SignerBinding,
    *,
    method: str,
    request_url: str,
    body: bytes,
    timestamp_ms: int | None = None,
    nonce: str | None = None,
) -> dict[str, str]:
    if not signer.can_authenticate_requests:
        raise ValueError(
            "canonical account request authentication requires signer network_id and an Ed25519 keypair"
        )
    assert signer.network_id is not None
    assert signer.private_key is not None
    assert signer.public_key is not None
    return build_account_request_headers(
        network_id=signer.network_id,
        private_key=signer.private_key,
        public_key=signer.public_key,
        method=method,
        request_url=request_url,
        body=body,
        timestamp_ms=timestamp_ms,
        nonce=nonce,
    )


def load_signer_binding(
    environment: str,
    config_path: str | None,
    authority_override: str | None,
    *,
    source: str,
    repo_root: Path,
) -> SignerBinding:
    warnings: list[str] = []
    if config_path is None:
        return SignerBinding(
            environment=environment,
            config_path=None,
            authority=authority_override,
            torii_url=None,
            network_id=None,
            private_key=None,
            public_key=None,
            basic_auth=None,
            warnings=warnings,
            source=source,
        )

    resolved_path = Path(config_path).expanduser()
    if not resolved_path.is_absolute():
        resolved_path = Path.cwd() / resolved_path
    resolved_path = resolved_path.absolute()
    config_label = resolved_path.name

    config = read_signer_config_secure(resolved_path, environment, repo_root)

    network_id = config.get("network_id")
    canonical_network_id_bytes(network_id)

    account = config.get("account")
    if not isinstance(account, dict):
        raise ValueError(f"account in {config_label} must be a table")
    public_key = nonempty_string(account.get("public_key"))
    private_key = nonempty_string(account.get("private_key"))
    if not public_key or not private_key:
        raise ValueError(
            f"account in {config_label} requires non-empty public_key and private_key"
        )
    if environment == "production":
        domain = nonempty_string(account.get("domain"))
        if not domain:
            raise ValueError(
                f"account in {config_label} requires non-empty domain, public_key, and private_key"
            )
    raw_torii_url = config.get("torii_url")
    if raw_torii_url is None and environment != "production" and config.get("basic_auth") is None:
        torii_url = None
    else:
        if not isinstance(raw_torii_url, str):
            raise ValueError(f"torii_url in {config_label} must be a string")
        require_https = environment == "production" or config.get("basic_auth") is not None
        url_origin(raw_torii_url, require_https=require_https, require_root=environment == "production")
        torii_url = normalize_torii_url(raw_torii_url)
    basic_auth_cfg = config.get("basic_auth")
    basic_auth: tuple[str, str] | None = None
    if basic_auth_cfg is not None:
        if not isinstance(basic_auth_cfg, dict) or set(basic_auth_cfg) != {"web_login", "password"}:
            raise ValueError(f"basic_auth in {config_label} requires only web_login and password")
        login = basic_auth_cfg.get("web_login")
        password = basic_auth_cfg.get("password")
        if not isinstance(login, str) or not login or not isinstance(password, str) or not password:
            raise ValueError(f"basic_auth in {config_label} requires non-empty string values")
        if ":" in login or any(ord(char) < 0x20 or ord(char) == 0x7F for char in login + password):
            raise ValueError(f"basic_auth in {config_label} contains an invalid value")
        basic_auth = (login, password)

    chain_discriminant = account.get("chain_discriminant")
    if chain_discriminant is not None and (
        isinstance(chain_discriminant, bool)
        or not isinstance(chain_discriminant, int)
        or not 0 <= chain_discriminant <= 65_535
    ):
        raise ValueError(f"account.chain_discriminant in {config_label} must be a TOML u16 integer")
    if environment == "production":
        chain = config.get("chain")
        assert isinstance(raw_torii_url, str)
        host = (urllib.parse.urlsplit(raw_torii_url).hostname or "").lower().rstrip(".")
        if not isinstance(chain, str) or not chain:
            raise ValueError(f"chain in {config_label} must be a non-empty string")
        if chain == TAIRA_CHAIN_ID:
            raise ValueError("production signer config must not select the canonical Taira chain")
        if network_id == TAIRA_NETWORK_ID:
            raise ValueError("production signer config must not select the canonical Taira network")
        if host == "taira.sora.org" or host.endswith(".taira.sora.org"):
            raise ValueError("production signer config must not use a Taira Torii origin")
        if str(account.get("profile") or "").strip().lower() == "taira":
            raise ValueError("production signer config must not use the Taira account profile")
        if chain_discriminant is None:
            raise ValueError("production signer config requires account.chain_discriminant")
        if chain_discriminant == TAIRA_NETWORK_PREFIX:
            raise ValueError("production signer config must not use the Taira chain discriminant")

    if isinstance(public_key, str) and looks_like_placeholder(public_key):
        warnings.append(f"public key in {config_label} still uses placeholder content")
        public_key = None
    if isinstance(private_key, str) and looks_like_placeholder(private_key):
        warnings.append(f"private key in {config_label} still uses placeholder content")
        private_key = None
    if environment in PUBLIC_MUTATION_ENVIRONMENTS and torii_url and looks_like_reserved_public_endpoint(torii_url):
        warnings.append(f"torii_url in {config_label} still uses placeholder or local endpoint content")
        torii_url = None

    authority = authority_override
    if public_key:
        if chain_discriminant is None:
            derived_authority, warning = derive_authority_from_public_key(
                str(public_key), environment
            )
        else:
            derived_authority, warning = derive_authority_from_public_key(
                str(public_key), environment, chain_discriminant
            )
        if warning:
            warnings.append(warning)
        if authority_override is not None:
            if derived_authority is None:
                raise ValueError(
                    "authority override cannot be verified against the configured signer public key"
                )
            if authority_override != derived_authority:
                raise ValueError("authority override does not match the configured signer public key")
        authority = derived_authority

    if authority is None:
        warnings.append(
            "no authority configured; provide --authority ENV=I105... or use a signer config that can be derived"
        )

    return SignerBinding(
        environment=environment,
        config_path=resolved_path,
        authority=authority,
        torii_url=torii_url,
        network_id=str(network_id),
        private_key=str(private_key) if private_key else None,
        public_key=str(public_key) if public_key else None,
        basic_auth=basic_auth,
        warnings=warnings,
        source=source,
        chain_discriminant=chain_discriminant,
    )


def build_signer_bindings(
    repo_root: Path,
    signer_assignments: dict[str, str],
    authority_assignments: dict[str, str],
    *,
    auto_discover: bool,
) -> dict[str, SignerBinding]:
    discovered_configs: dict[str, Path] = {}
    if auto_discover:
        for environment, candidate in candidate_default_signer_configs(repo_root).items():
            if environment in signer_assignments:
                continue
            if config_supports_autodiscovery(candidate, environment, repo_root):
                discovered_configs[environment] = candidate

    environments = set(discovered_configs) | set(signer_assignments) | set(authority_assignments)
    signers: dict[str, SignerBinding] = {}
    for environment in sorted(environments):
        explicit_path = signer_assignments.get(environment)
        config_path = explicit_path or (
            str(discovered_configs[environment]) if environment in discovered_configs else None
        )
        if explicit_path:
            source = "explicit"
        elif config_path is not None:
            source = "auto"
        else:
            source = "authority"
        signers[environment] = load_signer_binding(
            environment=environment,
            config_path=config_path,
            authority_override=authority_assignments.get(environment),
            source=source,
            repo_root=repo_root,
        )
    return signers


class ContractConsoleState:
    def __init__(self, repo_root: Path, signers: dict[str, SignerBinding]) -> None:
        self.repo_root = repo_root
        self.deployments_root = repo_root / "deployments"
        self.ui_root = repo_root / "ui" / "contract_console"
        self.signers = signers

    def list_environments(self) -> list[str]:
        if not self.deployments_root.exists():
            return []
        return sorted(
            entry.name
            for entry in self.deployments_root.iterdir()
            if entry.is_dir() and not entry.name.startswith(".")
        )

    def load_environment(self, environment: str) -> dict[str, Any]:
        env_root = self.deployments_root / environment
        if not env_root.is_dir():
            raise KeyError(f"unknown deployment environment: {environment}")

        chain_latest = safe_read_json(env_root / "chain.latest.json")
        chain_fingerprint: dict[str, Any] | None = None
        if isinstance(chain_latest, dict):
            chain_fingerprint = dict(chain_latest)

        record_map: dict[str, dict[str, Any]] = {}
        record_sources: dict[str, dict[str, Any]] = {}
        required_contract_keys = set(required_contract_keys_from_repo(self.repo_root))
        for path in sorted(env_root.glob("*.deploy.json")):
            parsed = safe_read_json(path)
            if not isinstance(parsed, dict):
                continue
            record_key = nonempty_string(parsed.get("contract_key"))
            if not record_key:
                continue
            if path.name != f"{record_key}.deploy.json":
                continue
            if required_contract_keys and record_key not in required_contract_keys:
                continue
            manifest_path = env_root / f"{record_key}.manifest.json"
            manifest = safe_read_json(manifest_path)
            if not deployment_record_matches_catalog_evidence(
                parsed,
                manifest,
                environment,
                record_key,
                chain_fingerprint,
            ):
                continue
            record_map[record_key] = parsed
            record_sources[record_key] = {"source": "deploy_record", "deployment_path": path}

        records = sorted(
            record_map.values(),
            key=lambda item: item["contract_key"],
        )

        contracts: list[dict[str, Any]] = []
        for record in records:
            contract_key = record["contract_key"]
            manifest_path = env_root / f"{contract_key}.manifest.json"
            source = record_sources.get(contract_key) or {}
            deployment_path = source.get("deployment_path")
            manifest = safe_read_json(manifest_path) if manifest_path else None
            entrypoints = sanitize_manifest_entrypoints(manifest if isinstance(manifest, dict) else None)
            contracts.append(
                {
                    "contract_key": contract_key,
                    "evidence_source": source.get("source"),
                    "contract_source": catalog_display_record_path(record.get("contract_source"), self.repo_root),
                    "contract_alias": record["contract_alias"],
                    "contract_address": record["contract_address"],
                    "dataspace_alias": record["dataspace_alias"],
                    "dataspace_id": record["dataspace_id"],
                    "deploy_nonce": record.get("deploy_nonce"),
                    "deploy_strategy": record.get("deploy_strategy"),
                    "code_hash_hex": record["code_hash_hex"],
                    "abi_hash_hex": record["abi_hash_hex"],
                    "commit_deployment_tx_hash": record["response"]["commit_deployment_tx_hash"],
                    "deployment_path": catalog_display_path(
                        deployment_path if isinstance(deployment_path, Path) else None,
                        self.repo_root,
                    ),
                    "manifest_path": catalog_display_path(manifest_path, self.repo_root),
                    "entrypoints": entrypoints,
                }
            )

        signer = self.signers.get(environment) or SignerBinding(
            environment=environment,
            config_path=None,
            authority=None,
            torii_url=None,
            network_id=None,
            private_key=None,
            public_key=None,
            basic_auth=None,
            warnings=[],
            source="none",
        )
        deployment_torii_url = normalize_torii_url(chain_fingerprint.get("torii_url") if chain_fingerprint else None)
        effective_torii_url = deployment_torii_url or signer.torii_url
        torii_url_source = "deployment" if deployment_torii_url else ("signer" if signer.torii_url else "none")
        mutation_policy = mutation_policy_for_environment(environment)
        warnings = [redact_local_warning_paths(warning) for warning in signer.warnings]
        torii_binding_valid = True
        if deployment_torii_url:
            try:
                if environment == "production" and isinstance(chain_fingerprint, dict) \
                    and chain_fingerprint.get("chain") == TAIRA_CHAIN_ID:
                    raise ValueError("production deployment evidence identifies the canonical Taira chain")
                deployment_origin = url_origin(
                    deployment_torii_url,
                    require_https=environment == "production",
                    require_root=environment == "production",
                )
                deployment_host = (
                    urllib.parse.urlsplit(deployment_torii_url).hostname or ""
                ).lower().rstrip(".")
                if environment == "production" and (
                    deployment_host == "taira.sora.org"
                    or deployment_host.endswith(".taira.sora.org")
                ):
                    raise ValueError("production deployment evidence identifies Taira")
            except ValueError as exc:
                torii_binding_valid = False
                effective_torii_url = None
                warnings.append(f"deployment Torii URL is unsafe: {exc}")
                deployment_origin = ""
        else:
            deployment_origin = ""
        if deployment_torii_url and signer.torii_url:
            try:
                signer_origin = url_origin(
                    signer.torii_url,
                    require_https=environment == "production" or signer.basic_auth is not None,
                    require_root=environment == "production",
                )
            except ValueError as exc:
                signer_origin = ""
                torii_binding_valid = False
                effective_torii_url = None
                warnings.append(f"signer Torii URL is unsafe: {exc}")
            if deployment_origin != signer_origin:
                torii_binding_valid = False
                effective_torii_url = None
                warnings.append("signer config Torii origin differs from deployment; refusing proxy requests")

        return {
            "name": environment,
            "torii_url": effective_torii_url,
            "torii_url_source": torii_url_source,
            "torii_binding_valid": torii_binding_valid,
            "mutation_policy": mutation_policy,
            "chain_fingerprint": chain_fingerprint,
            "contracts": contracts,
            "signer": {
                **signer_snapshot(signer),
                "warnings": warnings,
            },
        }

    def load_catalog(self) -> dict[str, Any]:
        environments = [self.load_environment(name) for name in self.list_environments()]
        return {
            "generated_at": utc_timestamp(),
            "repo_name": self.repo_root.name,
            "repo_root": self.repo_root.name,
            "environments": environments,
        }

    def resolve_environment(self, environment: str) -> tuple[dict[str, Any], SignerBinding]:
        loaded = self.load_environment(environment)
        signer = self.signers.get(environment) or SignerBinding(
            environment=environment,
            config_path=None,
            authority=None,
            torii_url=None,
            network_id=None,
            private_key=None,
            public_key=None,
            basic_auth=None,
            warnings=[],
            source="none",
        )
        return loaded, signer

    def resolve_contract(self, environment: str, contract_key: str) -> tuple[dict[str, Any], dict[str, Any], SignerBinding]:
        env_record, signer = self.resolve_environment(environment)
        for contract in env_record.get("contracts") or []:
            if contract.get("contract_key") == contract_key:
                return env_record, contract, signer
        raise KeyError(f"contract {contract_key} is not deployed in environment {environment}")


def parse_request_body(handler: BaseHTTPRequestHandler) -> dict[str, Any]:
    content_length_header = handler.headers.get("Content-Length") or "0"
    try:
        content_length = int(content_length_header)
    except ValueError as exc:
        raise ValueError("invalid Content-Length header") from exc
    if content_length < 0:
        raise ValueError("invalid Content-Length header")
    if content_length > MAX_REQUEST_BODY_BYTES:
        raise ValueError(f"request body exceeds {MAX_REQUEST_BODY_BYTES} byte limit")
    if content_length and not json_request_content_type_allowed(handler.headers.get("Content-Type")):
        raise ValueError("Content-Type must be application/json or application/*+json")
    raw = handler.rfile.read(content_length) if content_length else b"{}"
    try:
        decoded = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError(f"invalid UTF-8 request body: {exc}") from exc
    try:
        parsed = json.loads(decoded)
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid JSON body: {exc}") from exc
    except RecursionError as exc:
        raise ValueError("invalid JSON body: nesting is too deep") from exc
    if not isinstance(parsed, dict):
        raise ValueError("request body must be a JSON object")
    if json_depth_exceeds(parsed, MAX_BROWSER_JSON_DEPTH):
        raise ValueError(f"request body nesting exceeds {MAX_BROWSER_JSON_DEPTH} levels")
    return parsed


def json_request_content_type_allowed(content_type: str | None) -> bool:
    if not content_type:
        return False
    media_type = content_type.split(";", 1)[0].strip().lower()
    return media_type == "application/json" or (
        media_type.startswith("application/") and media_type.endswith("+json")
    )


def json_depth_exceeds(value: Any, max_depth: int) -> bool:
    stack: list[tuple[Any, int]] = [(value, 1)]
    while stack:
        current, depth = stack.pop()
        if depth > max_depth:
            return True
        if isinstance(current, dict):
            stack.extend((entry, depth + 1) for entry in current.values())
        elif isinstance(current, list):
            stack.extend((entry, depth + 1) for entry in current)
    return False


def read_limited_text(response: Any, max_bytes: int = MAX_UPSTREAM_RESPONSE_BYTES) -> str:
    body = response.read(max_bytes + 1)
    if len(body) > max_bytes:
        raise OSError(f"upstream response exceeds {max_bytes} byte limit")
    return body.decode("utf-8", errors="replace")


def _response_credential_tokens(
    basic_auth: tuple[str, str] | None,
    request_payload: dict[str, Any] | None,
    canonical_headers: dict[str, str] | None = None,
) -> set[str]:
    """Return exact secret encodings that an upstream response must never echo."""

    tokens: set[str] = set()
    if basic_auth is not None:
        login, password = basic_auth
        joined = f"{login}:{password}"
        encoded = base64.b64encode(joined.encode("utf-8")).decode("ascii")
        tokens.update({password, joined, encoded, f"Basic {encoded}"})
    if canonical_headers is not None:
        for header in ("X-Iroha-Signature", "X-Iroha-Nonce"):
            value = canonical_headers.get(header)
            if value:
                tokens.add(value)

    def visit(value: Any, *, sensitive: bool = False) -> None:
        if isinstance(value, dict):
            for key, entry in value.items():
                visit(entry, sensitive=sensitive or sensitive_request_key(str(key)))
        elif isinstance(value, list):
            for entry in value:
                visit(entry, sensitive=sensitive)
        elif sensitive and isinstance(value, str) and value:
            tokens.add(value)

    visit(request_payload)
    encoded_tokens = set(tokens)
    for token in tokens:
        encoded_tokens.add(json.dumps(token, ensure_ascii=True)[1:-1])
        encoded_tokens.add(urllib.parse.quote(token, safe=""))
        encoded_tokens.add(base64.b64encode(token.encode("utf-8")).decode("ascii"))
    return {token for token in encoded_tokens if token}


def reject_upstream_credential_echo(
    response_text: str,
    *,
    basic_auth: tuple[str, str] | None,
    request_payload: dict[str, Any] | None,
    canonical_headers: dict[str, str] | None = None,
) -> None:
    for token in _response_credential_tokens(basic_auth, request_payload, canonical_headers):
        if token in response_text:
            raise OSError("upstream response contained credential material and was suppressed")


class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Return upstream redirects to the console without issuing a second request."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[no-untyped-def]
        return None


INCOMPLETE_FANOUT_HEADERS = (
    "x-iroha-fanout-routes-failed",
    "x-iroha-fanout-routes-denied",
    "x-iroha-fanout-routes-unavailable",
    "x-iroha-fanout-routes-not-found",
)


def reject_incomplete_fanout_response(status: int, headers: object) -> None:
    """Reject a successful Torii response whose routed read is incomplete."""

    if not 200 <= status < 300:
        return
    get_all = getattr(headers, "get_all", None)
    get_one = getattr(headers, "get", None)
    incomplete: list[str] = []
    for name in INCOMPLETE_FANOUT_HEADERS:
        if callable(get_all):
            values = get_all(name) or []
        elif callable(get_one):
            value = get_one(name)
            values = [] if value is None else [value]
        else:
            values = []
        for raw_value in values:
            value = str(raw_value).strip()
            if re.fullmatch(r"0|[1-9][0-9]*", value) is None:
                incomplete.append(f"{name}=invalid")
            elif int(value) != 0:
                incomplete.append(f"{name}={value}")
    if incomplete:
        raise OSError("incomplete Torii routed response: " + ", ".join(incomplete))


def proxy_torii_request(
    torii_url: str,
    path: str,
    *,
    method: str,
    payload: dict[str, Any] | None,
    query: dict[str, Any] | None,
    basic_auth: tuple[str, str] | None,
    timeout: int,
    accept: str = "application/json",
    canonical_signer: SignerBinding | None = None,
) -> tuple[int, str, str | None]:
    configured_origin = url_origin(
        torii_url,
        require_https=basic_auth is not None,
        require_root=True,
    )
    parsed_path = urllib.parse.urlsplit(path)
    if (
        not path.startswith("/")
        or path.startswith("//")
        or parsed_path.scheme
        or parsed_path.netloc
        or parsed_path.query
        or parsed_path.fragment
        or "\\" in path
    ):
        raise ValueError("upstream Torii path must be a root-relative path without query or fragment")
    request_url = f"{torii_url.rstrip('/')}{path}"
    if url_origin(request_url, require_https=basic_auth is not None) != configured_origin:
        raise ValueError("upstream request escaped the configured Torii origin")
    query_string = encoded_query(query)
    if query_string:
        request_url = f"{request_url}?{query_string}"

    encoded_payload = (
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        if payload is not None
        else None
    )
    headers = {
        "Accept": accept,
    }
    if payload is not None:
        headers["Content-Type"] = "application/json"
    canonical_headers: dict[str, str] = {}
    if path in CANONICAL_ACCOUNT_AUTH_PATHS:
        if method.upper() != "POST" or encoded_payload is None:
            raise ValueError("canonical account-authenticated Torii routes require a JSON POST body")
        if query_string:
            raise ValueError("canonical account-authenticated Torii routes do not accept query parameters")
        if canonical_signer is None:
            raise ValueError(
                f"canonical account request authentication is required for upstream route {path}"
            )
        canonical_headers = canonical_account_request_headers(
            canonical_signer,
            method=method,
            request_url=request_url,
            body=encoded_payload,
        )
        headers.update(canonical_headers)
    request = urllib.request.Request(
        url=request_url,
        data=encoded_payload,
        method=method,
        headers=headers,
    )
    if basic_auth:
        token = base64.b64encode(f"{basic_auth[0]}:{basic_auth[1]}".encode("utf-8")).decode("ascii")
        request.add_header("Authorization", f"Basic {token}")

    opener = urllib.request.build_opener(NoRedirectHandler())
    try:
        with opener.open(request, timeout=timeout) as response:
            reject_incomplete_fanout_response(response.status, response.headers)
            body = read_limited_text(response)
            reject_upstream_credential_echo(
                body,
                basic_auth=basic_auth,
                request_payload=payload,
                canonical_headers=canonical_headers,
            )
            return response.status, body, response.headers.get("Content-Type")
    except urllib.error.HTTPError as exc:
        try:
            body = read_limited_text(exc)
            reject_upstream_credential_echo(
                body,
                basic_auth=basic_auth,
                request_payload=payload,
                canonical_headers=canonical_headers,
            )
            return exc.code, body, exc.headers.get("Content-Type")
        finally:
            exc.close()


def decode_json_maybe(response_text: str) -> Any:
    if not response_text:
        return None
    try:
        parsed = json.loads(response_text)
    except (json.JSONDecodeError, RecursionError):
        return None
    if json_depth_exceeds(parsed, MAX_BROWSER_JSON_DEPTH):
        return None
    return parsed


def query_dict_from_pairs(pairs: dict[str, list[str]]) -> dict[str, str | list[str]]:
    normalized: dict[str, str | list[str]] = {}
    for key, values in pairs.items():
        filtered = [value for value in values if value != ""]
        if not filtered:
            continue
        normalized[key] = filtered if len(filtered) > 1 else filtered[0]
    return normalized


def parse_bounded_query(raw_query: str) -> dict[str, list[str]]:
    if len(raw_query) > MAX_BROWSER_QUERY_STRING_CHARS:
        raise ValueError(f"query string exceeds {MAX_BROWSER_QUERY_STRING_CHARS} character limit")
    try:
        return urllib.parse.parse_qs(
            raw_query,
            keep_blank_values=False,
            max_num_fields=MAX_BROWSER_QUERY_FIELDS,
        )
    except ValueError as exc:
        raise ValueError(f"query string has too many fields (max {MAX_BROWSER_QUERY_FIELDS})") from exc


def first_query_value(values: list[str] | None) -> str | None:
    if not values:
        return None
    for value in values:
        if value != "":
            return value
    return None


def bounded_int_query_value(
    pairs: dict[str, list[str]],
    key: str,
    *,
    default: int,
    cap: int,
    minimum: int,
) -> str:
    raw_value = first_query_value(pairs.get(key))
    try:
        value = int(str(raw_value).strip()) if raw_value is not None else default
    except ValueError:
        value = default
    if value < minimum:
        value = default
    return str(min(value, cap))


def normalize_browser_gas_limit(value: Any) -> int:
    if value in (None, ""):
        return DEFAULT_GAS_LIMIT
    if isinstance(value, bool):
        raise ValueError("gas_limit must be an integer")
    if isinstance(value, int):
        gas_limit = value
    elif isinstance(value, str):
        normalized = value.strip()
        if not re.fullmatch(r"[+-]?\d+", normalized):
            raise ValueError("gas_limit must be an integer")
        gas_limit = int(normalized)
    else:
        raise ValueError("gas_limit must be an integer")
    if gas_limit < 1 or gas_limit > MAX_BROWSER_GAS_LIMIT:
        raise ValueError(f"gas_limit must be between 1 and {MAX_BROWSER_GAS_LIMIT}")
    return gas_limit


def bounded_read_proxy_query(
    upstream_path: str,
    pairs: dict[str, list[str]],
) -> dict[str, str | list[str]]:
    allowed_keys = READ_PROXY_ALLOWED_QUERY_KEYS.get(upstream_path)
    if allowed_keys is None and (
        upstream_path.startswith("/v1/sccp/proofs/message/")
        or upstream_path.startswith("/v1/sccp/proof-requests/")
        or upstream_path.startswith("/v1/assets/definitions/")
    ):
        allowed_keys = set()
    query_pairs = {
        key: list(values)
        for key, values in pairs.items()
        if allowed_keys is None or key in allowed_keys
    }
    limit_config = READ_PROXY_LIMITS.get(upstream_path)
    if limit_config is None:
        return query_dict_from_pairs(query_pairs)

    query_pairs["limit"] = [
        bounded_int_query_value(
            query_pairs,
            "limit",
            default=int(limit_config["default"]),
            cap=int(limit_config["cap"]),
            minimum=1,
        )
    ]
    for offset_key in ("from", "offset"):
        if offset_key in query_pairs:
            if upstream_path == "/v1/sccp/messages/recent" and offset_key == "from":
                raw_from = str(first_query_value(query_pairs.get("from")) or "").strip()
                if not re.fullmatch(r"[1-9][0-9]*", raw_from):
                    raise ValueError("from must be a positive block height")
                query_pairs["from"] = [raw_from]
                continue
            query_pairs[offset_key] = [
                bounded_int_query_value(
                    query_pairs,
                    offset_key,
                    default=0,
                    cap=READ_PROXY_OFFSET_CAP,
                    minimum=0,
                )
            ]
    if upstream_path == "/v1/transactions/history":
        asset_id = first_query_value(query_pairs.get("asset_id"))
        if asset_id is not None:
            asset_id = asset_id.strip()
            if (
                not asset_id
                or len(asset_id) > MAX_HISTORY_ASSET_ID_CHARS
                or any(ord(char) < 0x20 or ord(char) == 0x7F for char in asset_id)
            ):
                raise ValueError(
                    f"asset_id must be a non-empty value of at most {MAX_HISTORY_ASSET_ID_CHARS} characters"
                )
            query_pairs["asset_id"] = [asset_id]
        count_mode = first_query_value(query_pairs.get("count_mode"))
        if count_mode is not None:
            count_mode = count_mode.strip().lower()
            if count_mode not in {"bounded", "exact"}:
                raise ValueError("count_mode must be bounded or exact")
            query_pairs["count_mode"] = [count_mode]
    return query_dict_from_pairs(query_pairs)


def bounded_status_proxy_query(pairs: dict[str, list[str]]) -> tuple[dict[str, str], str | None]:
    tx_hash_hex = urllib.parse.unquote(str(first_query_value(pairs.get("hash")) or "").strip())
    if not tx_hash_hex:
        return {}, "hash is required"
    if LOWER_NONZERO_HASH_RE.fullmatch(tx_hash_hex) is None or set(tx_hash_hex) == {"0"}:
        return {}, "hash must be a nonzero lowercase 32-byte hexadecimal transaction hash"
    scope = urllib.parse.unquote(str(first_query_value(pairs.get("scope")) or "global").strip())
    if scope not in PIPELINE_STATUS_SCOPES:
        return {}, "scope must be local or global"
    return {"hash": tx_hash_hex, "scope": scope}, None


def normalize_sccp_message_id(raw_message_id: str) -> tuple[str | None, str | None]:
    message_id = urllib.parse.unquote(str(raw_message_id or "").strip())
    if not message_id:
        return None, "message_id is required"
    if LOWER_NONZERO_HASH_RE.fullmatch(message_id) is None or set(message_id) == {"0"}:
        return None, "message_id must be a nonzero lowercase 32-byte hexadecimal SCCP message id"
    return message_id, None


def normalize_asset_definition_selector(raw_selector: str) -> tuple[str | None, str | None]:
    try:
        selector = urllib.parse.unquote(str(raw_selector or ""), errors="strict")
    except UnicodeDecodeError:
        return None, "asset definition selector must be valid UTF-8"
    if not selector or selector != selector.strip():
        return None, "asset definition selector is required"
    if len(selector) > MAX_ASSET_DEFINITION_SELECTOR_CHARS:
        return None, (
            "asset definition selector must be at most "
            f"{MAX_ASSET_DEFINITION_SELECTOR_CHARS} characters"
        )
    if any(ord(char) < 0x20 or ord(char) == 0x7F for char in selector):
        return None, "asset definition selector must not contain control characters"
    if "/" in selector or "\\" in selector:
        return None, "asset definition selector must be one path segment"
    return selector, None


def encoded_query(query: dict[str, Any] | None) -> str:
    if not query:
        return ""
    items: list[tuple[str, str]] = []
    for key, raw_value in query.items():
        values = raw_value if isinstance(raw_value, (list, tuple)) else [raw_value]
        for value in values:
            if value in (None, ""):
                continue
            items.append((key, str(value)))
    return urllib.parse.urlencode(items, doseq=True)


def signer_snapshot(signer: SignerBinding) -> dict[str, Any]:
    return {
        "configured": signer.configured,
        "config_path": signer.config_path.name if signer.config_path else None,
        "authority": signer.authority,
        "torii_url": signer.torii_url,
        "network_id": signer.network_id,
        "chain_discriminant": signer.chain_discriminant,
        "call_enabled": signer.can_call,
        "basic_auth_configured": signer.basic_auth is not None,
        "source": signer_source_label(signer.source),
        "warnings": [redact_local_warning_paths(warning) for warning in signer.warnings],
    }


def signer_source_label(source: str) -> str:
    value = str(source or "none")
    if ":" not in value:
        return catalog_display_record_path(value, REPO_ROOT)
    prefix, detail = value.split(":", 1)
    if not detail:
        return prefix
    return f"{prefix}:{catalog_display_record_path(detail, REPO_ROOT)}"


def mutation_policy_for_environment(environment: str) -> dict[str, Any]:
    normalized_environment = environment.strip().lower()

    if normalized_environment == "local":
        return {
            "name": "local",
            "allowed": True,
            "requires_flag": False,
            "flag": None,
            "reason": "local environments permit signed mutations by default",
        }

    if normalized_environment in {"testnet", "production"}:
        flag = (
            "SORASWAP_ALLOW_PRODUCTION_MUTATIONS"
            if normalized_environment == "production"
            else "SORASWAP_ALLOW_TESTNET_MUTATIONS"
        )
        enabled = os.environ.get(flag) == "1"
        return {
            "name": normalized_environment or "testnet",
            "allowed": enabled,
            "requires_flag": True,
            "flag": flag,
            "reason": (
                "signed public-environment mutations are disabled until "
                f"{flag}=1 is exported before starting the console"
            ),
        }

    return {
        "name": "custom",
        "allowed": True,
        "requires_flag": False,
        "flag": None,
        "reason": "custom non-public environments may permit signed mutations",
    }


def migration_register_issues(repo_root: Path) -> list[str]:
    register_path = repo_root / "docs" / "parity" / "migration_register.md"
    rel_path = "docs/parity/migration_register.md"
    if not register_path.is_file() or register_path.stat().st_size == 0:
        return [f"{rel_path} is missing or empty"]

    ported_count = 0
    non_ported_rows: list[str] = []
    for line_number, line in enumerate(register_path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.startswith("|"):
            continue
        if "| Status |" in line or "| --- |" in line:
            continue

        columns = [column.strip() for column in line.split("|")]
        row_status = columns[3] if len(columns) > 3 else ""
        if row_status == "ported":
            ported_count += 1
        elif row_status == "reference-only":
            continue
        else:
            non_ported_rows.append(f"line {line_number}: {line}")

    issues: list[str] = []
    if non_ported_rows:
        issues.append(
            f"{rel_path} still contains non-ported production rows: "
            + "; ".join(non_ported_rows)
        )
    if ported_count == 0:
        issues.append(f"{rel_path} must contain at least one ported production row")
    return issues


PUBLIC_DEPLOY_REQUIRED_PHASES = (
    "preflight",
    "compile",
    "nested_call_probe",
    "deploy",
    "bootstrap_contract_state",
    "deployment_records_snapshot",
)


def deploy_latest_phase_issues(deploy_latest: dict[str, Any]) -> list[str]:
    phases = deploy_latest.get("phases")
    missing_or_incomplete: list[str] = []
    for phase in PUBLIC_DEPLOY_REQUIRED_PHASES:
        phase_record = phases.get(phase) if isinstance(phases, dict) else None
        if not isinstance(phase_record, dict) or phase_record.get("status") != "completed":
            missing_or_incomplete.append(phase)

    issues: list[str] = []
    if missing_or_incomplete:
        issues.append(
            "deploy.latest.json has incomplete phases: "
            + ", ".join(missing_or_incomplete)
        )

    preflight = phases.get("preflight") if isinstance(phases, dict) else None
    preflight_detail = preflight.get("detail") if isinstance(preflight, dict) else None
    signer_ready_check = (
        preflight_detail.get("signer_ready_check") if isinstance(preflight_detail, dict) else None
    )
    if (
        not isinstance(signer_ready_check, dict)
        or signer_ready_check.get("status") != "completed"
        or signer_ready_check.get("debug_bypass_env") is not None
    ):
        issues.append("deploy.latest.json preflight did not prove signer readiness without debug bypass")
    return issues


def artifact_diagnostic_issues(label: str, evidence: Any) -> list[str]:
    issues: list[str] = []
    if contains_local_diagnostic_path(evidence):
        issues.append(f"{label} contains raw local path diagnostics")
    if contains_sensitive_diagnostic_value(evidence):
        issues.append(f"{label} contains unredacted sensitive diagnostics")
    return issues


def public_preflight_health_diagnostic_issues(preflight_endpoint: Any) -> list[str]:
    issues: list[str] = []

    if not isinstance(preflight_endpoint, dict):
        issues.append("preflight.latest.json status endpoint health snapshot is not JSON-ready")
        issues.append("preflight.latest.json sumeragi endpoint health snapshot is not JSON-ready")
        return issues

    health_issues = preflight_endpoint.get("health_issues")
    if isinstance(health_issues, list):
        for health_issue in health_issues:
            if health_issue in (None, ""):
                continue
            issues.append(
                "preflight.latest.json health issue: "
                + redact_diagnostic_text(str(health_issue))
            )
    elif health_issues is not None:
        issues.append("preflight.latest.json health_issues must be an array")

    health = preflight_endpoint.get("health")
    if not isinstance(health, dict):
        issues.append("preflight.latest.json status endpoint health snapshot is not JSON-ready")
        issues.append("preflight.latest.json sumeragi endpoint health snapshot is not JSON-ready")
        return issues

    status_health = health.get("status")
    if not (
        isinstance(status_health, dict)
        and str(status_health.get("http_status")) == "200"
        and status_health.get("json_available") is True
    ):
        issues.append("preflight.latest.json status endpoint health snapshot is not JSON-ready")

    sumeragi_health = health.get("sumeragi")
    if not (
        isinstance(sumeragi_health, dict)
        and str(sumeragi_health.get("http_status")) == "200"
        and sumeragi_health.get("json_available") is True
    ):
        issues.append("preflight.latest.json sumeragi endpoint health snapshot is not JSON-ready")

    return issues


def public_preflight_mcp_ready(endpoint: Any) -> bool:
    if not isinstance(endpoint, dict) or str(endpoint.get("mcp_http_status")) != "200":
        return False
    mcp = endpoint.get("mcp")
    if not isinstance(mcp, dict):
        return False
    tool_count = mcp.get("tool_count")
    return bool(
        mcp.get("enabled") is True
        and mcp.get("metadata_valid") is True
        and nonempty_string(mcp.get("protocol_version"))
        and nonempty_string(mcp.get("server_name"))
        and nonempty_string(mcp.get("server_version"))
        and isinstance(tool_count, int)
        and not isinstance(tool_count, bool)
        and tool_count > 0
        and nonempty_string(mcp.get("toolset_version"))
    )


def public_preflight_and_probe_issues(
    env_root: Path,
    environment: str,
    chain_latest: dict[str, Any],
) -> list[str]:
    issues: list[str] = []
    repo_root = env_root.parent.parent
    preflight = safe_read_json(env_root / "preflight.latest.json")
    probe = safe_read_json(env_root / "nested_call_probe.latest.json")

    if not isinstance(preflight, dict):
        issues.append(f"{environment}: missing deployments/{environment}/preflight.latest.json")
    else:
        preflight_label = str((env_root / "preflight.latest.json").relative_to(repo_root))
        for issue in artifact_diagnostic_issues(preflight_label, preflight):
            issues.append(f"{environment}: {issue}")
        if not has_generated_at(preflight):
            issues.append(f"{environment}: preflight.latest.json is missing generated_at")
        if preflight.get("target_environment") != environment:
            issues.append(
                f"{environment}: preflight.latest.json must record target_environment {environment}"
            )
        preflight_chain = preflight.get("chain")
        preflight_fingerprint = (
            preflight_chain.get("fingerprint") if isinstance(preflight_chain, dict) else None
        )
        preflight_probe = preflight.get("nested_call_probe")
        signer = preflight.get("signer")
        preflight_environment = preflight.get("environment")
        preflight_endpoint = preflight.get("endpoint")
        readiness_ok = bool(
            preflight.get("status") == "ready"
            and preflight.get("blockers") == []
            and preflight.get("warnings") == []
            and isinstance(preflight_environment, dict)
            and preflight_environment.get("mutations_allowed") is True
            and preflight_environment.get("oracle_client_config_present") is True
            and preflight_environment.get("oracle_client_config_valid") is True
            and preflight_environment.get("oracle_account_derivable") is True
            and preflight_environment.get("oracle_account_distinct") is True
            and nonempty_string(preflight_environment.get("oracle_client_config_source"))
            and isinstance(preflight_endpoint, dict)
            and public_preflight_mcp_ready(preflight_endpoint)
            and preflight_endpoint.get("health_issues") == []
            and isinstance(preflight_endpoint.get("health"), dict)
            and isinstance(preflight_endpoint["health"].get("status"), dict)
            and str(preflight_endpoint["health"]["status"].get("http_status")) == "200"
            and preflight_endpoint["health"]["status"].get("json_available") is True
            and isinstance(preflight_endpoint["health"].get("sumeragi"), dict)
            and str(preflight_endpoint["health"]["sumeragi"].get("http_status")) == "200"
            and preflight_endpoint["health"]["sumeragi"].get("json_available") is True
            and isinstance(preflight_chain, dict)
            and preflight_chain.get("fingerprint_available") is True
            and preflight_chain.get("saved_snapshot_exists") is True
            and preflight_chain.get("saved_snapshot_matches") is True
            and preflight_chain.get("saved_snapshot_environment") == environment
            and isinstance(preflight_fingerprint, dict)
            and chain_fingerprint_matches_chain(preflight_fingerprint, chain_latest)
            and isinstance(preflight_probe, dict)
            and preflight_probe.get("latest_exists") is True
            and preflight_probe.get("matches_current_chain") is True
            and preflight_probe.get("supported") is True
            and isinstance(signer, dict)
            and signer.get("authority_derivable") is True
            and signer.get("account_exists") is True
            and signer.get("assets_query_available") is True
            and positive_decimalish(signer.get("fee_balance"))
        )
        if not readiness_ok:
            issues.append(f"{environment}: preflight.latest.json is not ready for the current chain")
        if preflight.get("status") == "ready" or isinstance(preflight_endpoint, dict):
            for health_issue in public_preflight_health_diagnostic_issues(preflight_endpoint):
                issues.append(f"{environment}: {health_issue}")

    if not isinstance(probe, dict):
        issues.append(f"{environment}: missing deployments/{environment}/nested_call_probe.latest.json")
    else:
        probe_label = str((env_root / "nested_call_probe.latest.json").relative_to(repo_root))
        for issue in artifact_diagnostic_issues(probe_label, probe):
            issues.append(f"{environment}: {issue}")
        if not has_generated_at(probe):
            issues.append(f"{environment}: nested_call_probe.latest.json is missing generated_at")
        if probe.get("environment") != environment:
            issues.append(
                f"{environment}: nested_call_probe.latest.json does not identify selected environment {environment}"
            )
        probe_chain = probe.get("chain_fingerprint")
        if not isinstance(probe_chain, dict) or not chain_fingerprint_matches_chain(probe_chain, chain_latest):
            issues.append(f"{environment}: nested_call_probe.latest.json does not match chain.latest.json")
        if probe.get("supported") is not True:
            summary = nonempty_string(probe.get("summary"))
            suffix = f": {summary}" if summary else ""
            issues.append(f"{environment}: nested_call_probe.latest.json is not supported{suffix}")

    if isinstance(preflight, dict) and isinstance(probe, dict):
        preflight_generated_at = generated_at_value(preflight)
        probe_generated_at = generated_at_value(probe)
        if preflight_generated_at and probe_generated_at and preflight_generated_at < probe_generated_at:
            issues.append(
                f"{environment}: preflight.latest.json is older than nested_call_probe.latest.json"
            )

    return issues


def public_deployment_evidence_issues(repo_root: Path, environment: str) -> list[str]:
    env_root = repo_root / "deployments" / environment
    issues: list[str] = []
    issues.extend(migration_register_issues(repo_root))
    required_contract_keys = required_contract_keys_from_repo(repo_root)
    if not required_contract_keys:
        issues.append(f"{environment}: no Kotodama contracts found under contracts/")

    chain_latest = safe_read_json(env_root / "chain.latest.json")
    if not isinstance(chain_latest, dict):
        issues.append(f"{environment}: missing deployments/{environment}/chain.latest.json")
        return issues
    for issue in artifact_diagnostic_issues(
        str((env_root / "chain.latest.json").relative_to(repo_root)),
        chain_latest,
    ):
        issues.append(f"{environment}: {issue}")

    chain_id, block_1_hash = chain_identity(chain_latest)
    missing_chain_fields = []
    if not nonempty_string(chain_latest.get("torii_url")):
        missing_chain_fields.append("torii_url")
    if not chain_id:
        missing_chain_fields.append("chain")
    if not block_1_hash:
        missing_chain_fields.append("block_1_hash")
    if missing_chain_fields:
        issues.append(
            f"{environment}: chain.latest.json must include {', '.join(missing_chain_fields)}"
        )
    if chain_latest.get("environment") != environment:
        issues.append(f"{environment}: chain.latest.json does not identify selected environment {environment}")
    if not has_generated_at(chain_latest):
        issues.append(f"{environment}: chain.latest.json is missing generated_at")
    issues.extend(public_preflight_and_probe_issues(env_root, environment, chain_latest))

    contracts_latest = safe_read_json(env_root / "contracts.latest.json")
    checked_deploy_record_paths: set[Path] = set()
    checked_manifest_paths: set[Path] = set()
    if not isinstance(contracts_latest, dict):
        issues.append(f"{environment}: missing deployments/{environment}/contracts.latest.json")
    else:
        if set(contracts_latest) != CONTRACTS_SNAPSHOT_FIELDS:
            issues.append(f"{environment}: contracts.latest.json does not match the current snapshot schema")
        if not current_chain_fingerprint_shape(contracts_latest.get("chain_fingerprint")):
            issues.append(
                f"{environment}: contracts.latest.json chain_fingerprint does not match the current schema"
            )
        for issue in artifact_diagnostic_issues(
            str((env_root / "contracts.latest.json").relative_to(repo_root)),
            contracts_latest,
        ):
            issues.append(f"{environment}: {issue}")
        if not has_generated_at(contracts_latest):
            issues.append(f"{environment}: contracts.latest.json is missing generated_at")
        if contracts_latest.get("status") != "completed":
            issues.append(f"{environment}: contracts.latest.json is not completed")
        if contracts_latest.get("environment") != environment:
            issues.append(f"{environment}: contracts.latest.json does not identify selected environment {environment}")
        contracts_chain = contracts_latest.get("chain_fingerprint")
        if not isinstance(contracts_chain, dict) or not chain_fingerprint_matches_chain(contracts_chain, chain_latest):
            issues.append(f"{environment}: contracts.latest.json does not match chain.latest.json")
        duplicate_contract_keys = contract_evidence_duplicate_keys(contracts_latest)
        if duplicate_contract_keys:
            issues.append(
                f"{environment}: contracts.latest.json contains duplicate contract snapshots: "
                f"{', '.join(duplicate_contract_keys)}"
            )
        contract_records = contract_evidence_records(contracts_latest)
        malformed_contract_keys = sorted(
            nonempty_string(item.get("contract_key")) or "<missing-contract-key>"
            for item in contracts_latest.get("contracts", [])
            if not current_deployment_record_shape(item)
        ) if isinstance(contracts_latest.get("contracts"), list) else ["<invalid-contracts-array>"]
        if malformed_contract_keys:
            issues.append(
                f"{environment}: contracts.latest.json contains records outside the current deployment schema: "
                f"{', '.join(malformed_contract_keys)}"
            )
        wrong_environment_contract_keys = sorted(
            key for key, record in contract_records.items() if record.get("environment") != environment
        )
        if wrong_environment_contract_keys:
            issues.append(
                f"{environment}: contracts.latest.json contains contract snapshots for the wrong environment: "
                f"{', '.join(wrong_environment_contract_keys)}"
            )
        missing_contract_keys = sorted(key for key in required_contract_keys if key not in contract_records)
        if missing_contract_keys:
            issues.append(
                f"{environment}: contracts.latest.json is missing required contract snapshots: "
                f"{', '.join(missing_contract_keys)}"
            )
        stale_contract_keys = sorted(key for key in contract_records if key not in required_contract_keys)
        if stale_contract_keys:
            issues.append(
                f"{environment}: contracts.latest.json contains stale or unknown contract snapshots: "
                f"{', '.join(stale_contract_keys)}"
            )
        for contract_key, expected_record in sorted(contract_records.items()):
            deploy_record_path = env_root / f"{contract_key}.deploy.json"
            manifest_path = env_root / f"{contract_key}.manifest.json"
            checked_deploy_record_paths.add(deploy_record_path)
            checked_manifest_paths.add(manifest_path)
            rel_path = deploy_record_path.relative_to(repo_root)
            manifest_rel_path = manifest_path.relative_to(repo_root)
            parsed = safe_read_json(deploy_record_path)
            if not isinstance(parsed, dict):
                issues.append(f"{environment}: missing {rel_path}")
                continue
            manifest = safe_read_json(manifest_path)
            if not isinstance(manifest, dict):
                issues.append(f"{environment}: missing {manifest_rel_path}")
                continue
            for issue in artifact_diagnostic_issues(str(rel_path), parsed):
                issues.append(f"{environment}: {issue}")
            for issue in artifact_diagnostic_issues(str(manifest_rel_path), manifest):
                issues.append(f"{environment}: {issue}")

            if not has_generated_at(manifest):
                issues.append(f"{environment}: {manifest_rel_path} is missing generated_at")

            if manifest.get("environment") != environment:
                issues.append(
                    f"{environment}: {manifest_rel_path} does not identify selected environment {environment}"
                )

            if nonempty_string(manifest.get("contract_key")) != contract_key:
                issues.append(f"{environment}: {manifest_rel_path} manifest contract_key does not match filename")

            if not has_generated_at(parsed):
                issues.append(f"{environment}: {rel_path} is missing generated_at")

            if not current_deployment_record_shape(parsed):
                issues.append(f"{environment}: {rel_path} does not match the current deployment record schema")

            if parsed.get("environment") != environment:
                issues.append(f"{environment}: {rel_path} does not identify selected environment {environment}")

            record_chain = parsed.get("chain_fingerprint")
            if not isinstance(record_chain, dict) or not chain_fingerprint_matches_chain(record_chain, chain_latest):
                issues.append(f"{environment}: {rel_path} does not match chain.latest.json")

            actual_key = nonempty_string(parsed.get("contract_key"))
            if actual_key != contract_key:
                issues.append(f"{environment}: {rel_path} does not identify contract_key {contract_key}")

            expected_address = contract_address_from_evidence(expected_record)
            actual_address = contract_address_from_evidence(parsed)
            if not expected_address or not actual_address:
                issues.append(
                    f"{environment}: {rel_path} contract address is missing from contracts.latest.json "
                    "or the deployment record"
                )
            elif expected_address != actual_address:
                issues.append(f"{environment}: {rel_path} address does not match contracts.latest.json")

            expected_nonce = deploy_nonce_from_evidence(expected_record)
            actual_nonce = deploy_nonce_from_evidence(parsed)
            if expected_nonce is None or actual_nonce is None:
                issues.append(
                    f"{environment}: {rel_path} deploy nonce is missing from contracts.latest.json "
                    "or the deployment record"
                )
            elif str(expected_nonce) != str(actual_nonce):
                issues.append(f"{environment}: {rel_path} deploy nonce does not match contracts.latest.json")

            expected_code_hash = hash_from_evidence(expected_record, "code_hash_hex")
            expected_abi_hash = hash_from_evidence(expected_record, "abi_hash_hex")
            if not expected_code_hash or not expected_abi_hash:
                issues.append(
                    f"{environment}: contracts.latest.json is missing code_hash_hex or abi_hash_hex for {contract_key}"
                )
            else:
                if manifest_hash(manifest, "code_hash") != expected_code_hash or manifest_hash(manifest, "abi_hash") != expected_abi_hash:
                    issues.append(f"{environment}: {manifest_rel_path} hashes do not match contracts.latest.json")
                actual_code_hash = hash_from_evidence(parsed, "code_hash_hex")
                actual_abi_hash = hash_from_evidence(parsed, "abi_hash_hex")
                if actual_code_hash != expected_code_hash or actual_abi_hash != expected_abi_hash:
                    issues.append(f"{environment}: {rel_path} code or ABI hash does not match contracts.latest.json")

                response = parsed.get("response")
                if (
                    not current_contract_deploy_response_matches_record(response, parsed)
                    or response.get("contract_address") != expected_address
                    or response.get("deploy_nonce") != expected_nonce
                    or response.get("code_hash_hex") != expected_code_hash
                ):
                    issues.append(f"{environment}: {rel_path} does not include successful deploy response evidence")

                if parsed.get("deploy_strategy") != CURRENT_DEPLOY_STRATEGY:
                    issues.append(f"{environment}: {rel_path} does not use a current deploy strategy")

    deploy_latest = safe_read_json(env_root / "deploy.latest.json")
    if not isinstance(deploy_latest, dict):
        issues.append(f"{environment}: missing deployments/{environment}/deploy.latest.json")
    else:
        for issue in artifact_diagnostic_issues(
            str((env_root / "deploy.latest.json").relative_to(repo_root)),
            deploy_latest,
        ):
            issues.append(f"{environment}: {issue}")
        if not has_generated_at(deploy_latest):
            issues.append(f"{environment}: deploy.latest.json is missing generated_at")
        if deploy_latest.get("environment") != environment:
            issues.append(f"{environment}: deploy.latest.json does not identify selected environment {environment}")
        if deploy_latest.get("status") != "completed":
            issues.append(f"{environment}: deploy.latest.json is not completed")
        for issue in deploy_latest_phase_issues(deploy_latest):
            issues.append(f"{environment}: {issue}")
        deploy_chain = deploy_latest.get("chain_fingerprint")
        if not isinstance(deploy_chain, dict) or not chain_fingerprint_matches_chain(deploy_chain, chain_latest):
            issues.append(f"{environment}: deploy.latest.json does not match chain.latest.json")

    for deploy_record_path in sorted(env_root.glob("*.deploy.json")):
        if deploy_record_path in checked_deploy_record_paths:
            continue
        parsed = safe_read_json(deploy_record_path)
        rel_path = deploy_record_path.relative_to(repo_root)
        if not isinstance(parsed, dict):
            issues.append(f"{environment}: {rel_path} is not valid JSON object evidence")
            continue
        for issue in artifact_diagnostic_issues(str(rel_path), parsed):
            issues.append(f"{environment}: {issue}")
        if not has_generated_at(parsed):
            issues.append(f"{environment}: {rel_path} is missing generated_at")
            continue
        if parsed.get("environment") != environment:
            issues.append(f"{environment}: {rel_path} does not identify selected environment {environment}")
            continue
        actual_key = nonempty_string(parsed.get("contract_key"))
        if not actual_key:
            issues.append(f"{environment}: {rel_path} does not identify a current contract_key")
            continue
        if deploy_record_path.name != f"{actual_key}.deploy.json":
            issues.append(f"{environment}: {rel_path} contract_key does not match filename")
            continue
        if actual_key not in required_contract_keys:
            issues.append(f"{environment}: {rel_path} is stale or unknown for current contracts/")
            continue
        if isinstance(contracts_latest, dict) and actual_key not in contract_evidence_records(contracts_latest):
            issues.append(f"{environment}: {rel_path} is not referenced by contracts.latest.json")
            continue
        record_chain = parsed.get("chain_fingerprint")
        if not isinstance(record_chain, dict) or not chain_fingerprint_matches_chain(record_chain, chain_latest):
            issues.append(f"{environment}: {rel_path} does not match chain.latest.json")

    for manifest_path in sorted(env_root.glob("*.manifest.json")):
        if manifest_path in checked_manifest_paths:
            continue
        rel_path = manifest_path.relative_to(repo_root)
        manifest_key = manifest_path.name.removesuffix(".manifest.json")
        if not manifest_key:
            issues.append(f"{environment}: {rel_path} does not identify a current contract_key")
            continue
        if manifest_key not in required_contract_keys:
            issues.append(f"{environment}: {rel_path} is stale or unknown for current contracts/")
            continue
        if isinstance(contracts_latest, dict) and manifest_key not in contract_evidence_records(contracts_latest):
            issues.append(f"{environment}: {rel_path} is not referenced by contracts.latest.json")
            continue
        parsed = safe_read_json(manifest_path)
        if not isinstance(parsed, dict):
            issues.append(f"{environment}: {rel_path} is not valid JSON object evidence")
            continue
        for issue in artifact_diagnostic_issues(str(rel_path), parsed):
            issues.append(f"{environment}: {issue}")
        if not has_generated_at(parsed):
            issues.append(f"{environment}: {rel_path} is missing generated_at")
            continue
        if parsed.get("environment") != environment:
            issues.append(f"{environment}: {rel_path} does not identify selected environment {environment}")
            continue
        if nonempty_string(parsed.get("contract_key")) != manifest_key:
            issues.append(f"{environment}: {rel_path} manifest contract_key does not match filename")

    return issues


def mutation_enabled_public_deployment_evidence_issues(state: ContractConsoleState) -> list[str]:
    issues: list[str] = []
    for environment in state.list_environments():
        if environment not in PUBLIC_MUTATION_ENVIRONMENTS:
            continue
        policy = mutation_policy_for_environment(environment)
        if not bool(policy.get("allowed")):
            continue
        issues.extend(public_deployment_evidence_issues(state.repo_root, environment))
    return issues


SENSITIVE_REQUEST_KEYS = {
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
LARGE_SIGNING_REQUEST_KEYS = {
    "destinationproofb64",
    "nativeproofb64",
    "transactionpayloadb64",
    "signatureb64",
}
EXPLICIT_SENSITIVE_KEY_ERROR = (
    "browser JSON must not include private keys, secrets, mnemonics, tokens, authorization, "
    "passwords, or passphrases; "
    "bind a signer config instead"
)
SENSITIVE_KEY_ASSIGNMENT_RE = re.compile(
    (
        r"""(?<![?&#A-Za-z0-9_-])"""
        r"""(?:"([^"]{1,64})"|'([^']{1,64})'|([A-Za-z][A-Za-z0-9_-]{0,64}))\s*[:=]"""
    ),
    re.IGNORECASE,
)
SENSITIVE_FREEFORM_KEY_RE = re.compile(
    (
        r"""(?<![?&#A-Za-z0-9_-])"""
        r"""(private\s+key|api\s+token|access\s+token|refresh\s+token|api\s+key|bearer\s+token|client\s+secret)\s*[:=]"""
    ),
    re.IGNORECASE,
)
SENSITIVE_CLI_FLAG_RE = re.compile(r"""(?<![A-Za-z0-9_-])--?([A-Za-z][A-Za-z0-9_-]{0,64})(?:=|\s+)""")
SENSITIVE_DIAGNOSTIC_ASSIGNMENT_RE = re.compile(
    (
        r"""(?<![A-Za-z0-9_-])"""
        r"""(?P<key>private[_ -]?key|secret|mnemonic|api[_ -]?token|access[_ -]?token|"""
        r"""refresh[_ -]?token|api[_ -]?key|authorization|bearer[_ -]?token|client[_ -]?secret|"""
        r"""token|password|passphrase)"""
        r"""(?P<sep>\s*[:=]\s*|\s+)"""
        r"""(?P<value>"[^"]*"|'[^']*'|[^\s,;)}\]]+)"""
    ),
    re.IGNORECASE,
)
SENSITIVE_DIAGNOSTIC_CLI_FLAG_VALUE_RE = re.compile(
    r"""(?<![A-Za-z0-9_-])(?P<flag>--?[A-Za-z][A-Za-z0-9_-]{0,64})(?P<sep>=|\s+)(?P<value>[^\s,;)}\]]+)""",
    re.IGNORECASE,
)
SENSITIVE_DIAGNOSTIC_QUERY_VALUE_RE = re.compile(
    (
        r"""(?P<prefix>[?&#](?:access_token|refresh_token|client_secret|api_key|api-token|"""
        r"""authorization|bearer_token|bearer-token|token|password)=)"""
        r"""(?P<value>[^&#\s]+)"""
    ),
    re.IGNORECASE,
)
SENSITIVE_DIAGNOSTIC_BEARER_VALUE_RE = re.compile(
    r"""(?P<prefix>\b(?:authorization\s*[:=]?\s*)?Bearer\s+)(?P<value>[^\s,;)}\]]+)""",
    re.IGNORECASE,
)


def sensitive_request_key(key: object) -> bool:
    normalized = "".join(char for char in str(key).lower() if char.isalnum())
    return normalized in SENSITIVE_REQUEST_KEYS


def string_contains_sensitive_key(raw_value: str) -> bool:
    decoded = urllib.parse.unquote_plus(raw_value)
    if not decoded:
        return False
    if url_value_contains_credentials(decoded):
        return True
    for match in SENSITIVE_KEY_ASSIGNMENT_RE.finditer(decoded):
        key = next((group for group in match.groups() if group is not None), "")
        if sensitive_request_key(key):
            return True
    for match in SENSITIVE_FREEFORM_KEY_RE.finditer(decoded):
        if sensitive_request_key(match.group(1)):
            return True
    for match in SENSITIVE_CLI_FLAG_RE.finditer(decoded):
        if sensitive_request_key(match.group(1)):
            return True
    return False


def query_value_contains_sensitive_key(raw_value: str) -> bool:
    return string_contains_sensitive_key(raw_value)


def url_value_contains_credentials(raw_value: str) -> bool:
    for match in re.finditer(r"\b[a-z][a-z0-9+.-]*://[^\s\"']+", raw_value, re.IGNORECASE):
        try:
            parsed = urllib.parse.urlsplit(match.group(0))
        except ValueError:
            continue
        if parsed.username or parsed.password:
            return True
    return False


def contains_sensitive_diagnostic_value(value: Any) -> bool:
    if isinstance(value, str):
        return string_contains_sensitive_key(value)
    if isinstance(value, dict):
        for key, entry in value.items():
            if sensitive_request_key(key) and entry not in (None, ""):
                return True
            if isinstance(key, str) and query_value_contains_sensitive_key(key):
                return True
            if contains_sensitive_diagnostic_value(entry):
                return True
    if isinstance(value, list):
        return any(contains_sensitive_diagnostic_value(entry) for entry in value)
    return False


def redact_diagnostic_text(message: str) -> str:
    redacted = redact_local_warning_paths(str(message))
    redacted = re.sub(
        r"\b([a-z][a-z0-9+.-]*://)[^/\s:@?#]+(?::[^/\s@?#]*)?@",
        r"\1[redacted]@",
        redacted,
        flags=re.IGNORECASE,
    )
    redacted = SENSITIVE_DIAGNOSTIC_BEARER_VALUE_RE.sub(
        lambda match: f"{match.group('prefix')}[redacted]",
        redacted,
    )

    def replace_assignment(match: re.Match[str]) -> str:
        key = match.group("key")
        separator = match.group("sep")
        value = match.group("value").strip("\"'")
        normalized_key = "".join(char for char in str(key).lower() if char.isalnum())
        separator_is_assignment = ":" in separator or "=" in separator
        if normalized_key == "authorization":
            if value.lower() == "bearer":
                return match.group(0)
        if normalized_key in {"secret", "mnemonic", "token", "password", "passphrase", "authorization"}:
            if not separator_is_assignment:
                return match.group(0)
        if sensitive_request_key(key):
            return f"{key}{separator}[redacted]"
        return match.group(0)

    redacted = SENSITIVE_DIAGNOSTIC_ASSIGNMENT_RE.sub(replace_assignment, redacted)

    def replace_cli_flag(match: re.Match[str]) -> str:
        flag = match.group("flag")
        flag_key = flag.lstrip("-")
        if sensitive_request_key(flag_key):
            return f"{flag}{match.group('sep')}[redacted]"
        return match.group(0)

    redacted = SENSITIVE_DIAGNOSTIC_CLI_FLAG_VALUE_RE.sub(replace_cli_flag, redacted)
    redacted = SENSITIVE_DIAGNOSTIC_QUERY_VALUE_RE.sub(
        lambda match: f"{match.group('prefix')}[redacted]",
        redacted,
    )
    return redacted


def redact_access_log_message(message: str) -> str:
    message = re.sub(
        r"\b([a-z][a-z0-9+.-]*://)[^/\s:@?#]+(?::[^/\s@?#]*)?@",
        r"\1[redacted]@",
        message,
        flags=re.IGNORECASE,
    )

    def replace_query_value(match: re.Match[str]) -> str:
        separator, raw_key, raw_value = match.groups()
        decoded_key = urllib.parse.unquote_plus(raw_key)
        if sensitive_request_key(decoded_key) or query_value_contains_sensitive_key(raw_value):
            return f"{separator}{raw_key}=[redacted]"
        if len(raw_value) > ACCESS_LOG_QUERY_VALUE_CHARS:
            return f"{separator}{raw_key}=[truncated:{len(raw_value)}]"
        return match.group(0)

    return re.sub(r"([?&])([^=&\s\"]+)=([^&\s\"]*)", replace_query_value, message)


def contains_sensitive_request_value(value: Any) -> bool:
    if isinstance(value, dict):
        for key, entry in value.items():
            if sensitive_request_key(key) and entry not in (None, ""):
                return True
            if contains_sensitive_request_value(entry):
                return True
    if isinstance(value, list):
        return any(contains_sensitive_request_value(entry) for entry in value)
    return False


def explicit_sensitive_key_error(body: dict[str, Any]) -> str | None:
    if contains_sensitive_request_value(body):
        return EXPLICIT_SENSITIVE_KEY_ERROR
    return None


def redact_sensitive_request_value(value: Any) -> Any:
    if isinstance(value, dict):
        redacted: dict[str, Any] = {}
        for key, entry in value.items():
            normalized = "".join(char for char in str(key).lower() if char.isalnum())
            if sensitive_request_key(key):
                redacted[key] = "[redacted]"
            elif normalized in LARGE_SIGNING_REQUEST_KEYS and isinstance(entry, str):
                redacted[key] = f"[omitted-base64:{len(entry)}]"
            else:
                redacted[key] = redact_sensitive_request_value(entry)
        return redacted
    if isinstance(value, list):
        return [redact_sensitive_request_value(entry) for entry in value]
    return value


def redact_request_payload(payload: dict[str, Any] | None) -> dict[str, Any] | None:
    if payload is None:
        return None
    redacted = redact_sensitive_request_value(payload)
    return redacted if isinstance(redacted, dict) else None


def extract_error_code(response_json: Any, response_text: str) -> str | None:
    if isinstance(response_json, dict):
        for key in ("code", "error_code"):
            value = response_json.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
        error_value = response_json.get("error")
        if isinstance(error_value, dict):
            for key in ("code", "error_code"):
                value = error_value.get(key)
                if isinstance(value, str) and value.strip():
                    return value.strip()

    match = re.search(r"\b[a-z0-9]+(?:_[a-z0-9]+)+\b", response_text)
    if match:
        return match.group(0)
    return None


def extract_tx_hash_hex(response_json: Any) -> str | None:
    if not isinstance(response_json, dict):
        return None
    tx_hash_hex = response_json.get("tx_hash_hex")
    if isinstance(tx_hash_hex, str) and tx_hash_hex.strip():
        return tx_hash_hex.strip()
    return None


def extract_submitted_flag(response_json: Any) -> bool | None:
    if not isinstance(response_json, dict):
        return None
    submitted = response_json.get("submitted")
    if isinstance(submitted, bool):
        return submitted
    return None


def extract_status_kind(response_json: Any) -> str | None:
    if not isinstance(response_json, dict):
        return None
    status = response_json.get("status")
    if isinstance(status, dict):
        kind = status.get("kind")
        if isinstance(kind, str) and kind.strip():
            return kind.strip()
    return None


def validate_pipeline_status_response(
    response_json: Any,
    *,
    expected_hash: str,
    expected_scope: str,
) -> dict[str, Any]:
    if not isinstance(response_json, dict):
        raise ValueError("pipeline transaction status response must be a JSON object")
    if set(response_json) != {"hash", "status", "scope", "resolved_from"}:
        raise ValueError("pipeline transaction status response fields do not match the current status-only DTO")
    if response_json.get("hash") != expected_hash:
        raise ValueError("pipeline transaction status response hash does not match the request")
    scope = response_json.get("scope")
    if scope not in PIPELINE_STATUS_SCOPES or scope != expected_scope:
        raise ValueError("pipeline transaction status response scope does not match the request")
    if response_json.get("resolved_from") not in PIPELINE_STATUS_SOURCES:
        raise ValueError("pipeline transaction status response has an invalid resolved_from value")
    status = response_json.get("status")
    if not isinstance(status, dict) or status.get("kind") not in PIPELINE_STATUS_KINDS:
        raise ValueError("pipeline transaction status response has an unknown typed status kind")
    if set(status) not in ({"kind"}, {"kind", "block_height"}):
        raise ValueError("pipeline transaction status fields do not match the current status-only DTO")
    kind = str(status["kind"])
    block_height = status.get("block_height")
    if block_height is not None and (
        isinstance(block_height, bool) or not isinstance(block_height, int) or block_height <= 0
    ):
        raise ValueError("pipeline transaction status block_height must be a positive integer")
    return {
        "kind": kind,
        "scope": scope,
        "resolved_from": response_json["resolved_from"],
        "block_height": block_height,
    }


def build_proxy_result(
    *,
    environment: str,
    torii_url: str,
    signer: SignerBinding,
    mode: str,
    path: str,
    query: dict[str, Any] | None,
    request_payload: dict[str, Any] | None,
    upstream_status: int,
    upstream_content_type: str | None,
    response_text: str,
) -> dict[str, Any]:
    response_json = decode_json_maybe(response_text)
    result: dict[str, Any] = {
        "ok": 200 <= upstream_status < 300,
        "environment": environment,
        "torii_url": torii_url,
        "mode": mode,
        "path": path,
        "query": query,
        "request": redact_request_payload(request_payload),
        "upstream_status": upstream_status,
        "upstream_content_type": upstream_content_type,
        "response_json": response_json,
        "response_text": response_text,
        "signer": signer_snapshot(signer),
    }
    error_code = extract_error_code(response_json, response_text)
    if error_code:
        result["error_code"] = error_code
    tx_hash_hex = extract_tx_hash_hex(response_json)
    if tx_hash_hex:
        result["tx_hash_hex"] = tx_hash_hex
    submitted = extract_submitted_flag(response_json)
    if submitted is not None:
        result["submitted"] = submitted
    status_kind = extract_status_kind(response_json)
    if status_kind:
        result["status_kind"] = status_kind
    return result


class ContractConsoleHandler(BaseHTTPRequestHandler):
    server_version = "SoraSwapContractConsole/0.1"

    @property
    def state(self) -> ContractConsoleState:
        return self.server.state  # type: ignore[attr-defined]

    def resolve_proxy_environment(self, environment: str) -> tuple[dict[str, Any], SignerBinding, str]:
        if not environment:
            raise ValueError("environment is required")
        env_record, signer = self.state.resolve_environment(environment)
        torii_url = normalize_torii_url(env_record.get("torii_url"))
        if not torii_url:
            raise ValueError(f"no Torii URL is known for environment {environment}")
        return env_record, signer, torii_url

    def require_mutations_allowed(self, env_record: dict[str, Any]) -> None:
        policy = env_record.get("mutation_policy") or {}
        if bool(policy.get("allowed")):
            return

        reason = str(policy.get("reason") or "").strip()
        if not reason:
            reason = f"signed mutations are disabled for environment {env_record.get('name') or 'unknown'}"
        raise PermissionError(reason)

    def reject_explicit_sensitive_key(self, body: dict[str, Any]) -> str | None:
        return explicit_sensitive_key_error(body)

    def execute_upstream_request(
        self,
        *,
        environment: str,
        signer: SignerBinding,
        torii_url: str,
        mode: str,
        path: str,
        query: dict[str, Any] | None = None,
        request_payload: dict[str, Any] | None = None,
        timeout: int = DEFAULT_UPSTREAM_TIMEOUT_SECONDS,
    ) -> dict[str, Any]:
        try:
            upstream_status, response_text, upstream_content_type = proxy_torii_request(
                torii_url=torii_url,
                path=path,
                method="GET" if request_payload is None else "POST",
                payload=request_payload,
                query=query,
                basic_auth=signer.basic_auth,
                timeout=timeout,
                canonical_signer=signer,
            )
        except (OSError, ValueError) as exc:
            raise ConnectionError(f"failed to reach {torii_url}{path}: {exc}") from exc

        return build_proxy_result(
            environment=environment,
            torii_url=torii_url,
            signer=signer,
            mode=mode,
            path=path,
            query=query,
            request_payload=request_payload,
            upstream_status=upstream_status,
            upstream_content_type=upstream_content_type,
            response_text=response_text,
        )

    def handle_torii_read_proxy(self, parsed: urllib.parse.ParseResult, upstream_path: str) -> None:
        try:
            query_params = parse_bounded_query(parsed.query)
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return
        environment = str((query_params.pop("environment", [""])[0]) or "").strip()

        try:
            _, signer, torii_url = self.resolve_proxy_environment(environment)
        except KeyError as exc:
            json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": str(exc)})
            return
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return

        try:
            request_query = bounded_read_proxy_query(upstream_path, query_params)
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return
        try:
            payload = self.execute_upstream_request(
                environment=environment,
                signer=signer,
                torii_url=torii_url,
                mode="read",
                path=upstream_path,
                query=request_query,
                request_payload=None,
            )
        except ConnectionError as exc:
            json_response(self, HTTPStatus.BAD_GATEWAY, {"ok": False, "error": str(exc)})
            return

        json_response(self, HTTPStatus.OK, payload)

    def handle_pipeline_transaction_status(self, parsed: urllib.parse.ParseResult) -> None:
        try:
            query_params = parse_bounded_query(parsed.query)
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return
        environment = str((query_params.pop("environment", [""])[0]) or "").strip()
        request_query, query_error = bounded_status_proxy_query(query_params)
        if query_error:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": query_error})
            return

        try:
            _, signer, torii_url = self.resolve_proxy_environment(environment)
        except KeyError as exc:
            json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": str(exc)})
            return
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return

        try:
            payload = self.execute_upstream_request(
                environment=environment,
                signer=signer,
                torii_url=torii_url,
                mode="status",
                path="/v1/pipeline/transactions/status",
                query=request_query,
                request_payload=None,
            )
        except ConnectionError as exc:
            json_response(self, HTTPStatus.BAD_GATEWAY, {"ok": False, "error": str(exc)})
            return

        if payload["upstream_status"] == 404 and "status_kind" not in payload:
            payload["status_kind"] = "NotFound"
            payload["status_scope"] = request_query["scope"]
        elif payload["upstream_status"] == 200:
            try:
                typed_status = validate_pipeline_status_response(
                    payload.get("response_json"),
                    expected_hash=request_query["hash"],
                    expected_scope=request_query["scope"],
                )
            except ValueError as exc:
                payload["ok"] = False
                payload["error_code"] = "invalid_upstream_status_payload"
                payload["error"] = str(exc)
                json_response(self, HTTPStatus.BAD_GATEWAY, payload)
                return
            payload["status_kind"] = typed_status["kind"]
            payload["status_scope"] = typed_status["scope"]
            payload["status_resolved_from"] = typed_status["resolved_from"]
            if typed_status["block_height"] is not None:
                payload["status_block_height"] = typed_status["block_height"]
        json_response(self, HTTPStatus.OK, payload)

    def handle_transactions_history(self, parsed: urllib.parse.ParseResult) -> None:
        try:
            query_params = parse_bounded_query(parsed.query)
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return
        environment = str((query_params.pop("environment", [""])[0]) or "").strip()

        try:
            _, signer, torii_url = self.resolve_proxy_environment(environment)
        except KeyError as exc:
            json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": str(exc)})
            return
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return

        try:
            request_query = bounded_read_proxy_query("/v1/transactions/history", query_params)
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return
        try:
            payload = self.execute_upstream_request(
                environment=environment,
                signer=signer,
                torii_url=torii_url,
                mode="history",
                path="/v1/transactions/history",
                query=request_query,
                request_payload=None,
            )
        except ConnectionError as exc:
            json_response(self, HTTPStatus.BAD_GATEWAY, {"ok": False, "error": str(exc)})
            return

        available = bool(payload["ok"])
        payload["available"] = available
        payload["supported"] = available
        if not available:
            payload["unsupported_reason"] = payload.get("error_code") or "upstream_unavailable"
        json_response(self, HTTPStatus.OK, payload)

    def handle_bridge_submit_proxy(self, upstream_path: str) -> None:
        try:
            body = parse_request_body(self)
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return

        environment = str(body.pop("environment", "") or "").strip()
        if not environment:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": "environment is required"})
            return

        try:
            env_record, signer, torii_url = self.resolve_proxy_environment(environment)
        except KeyError as exc:
            json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": str(exc)})
            return
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return

        sensitive_key_error = self.reject_explicit_sensitive_key(body)
        if sensitive_key_error:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": sensitive_key_error})
            return

        try:
            self.require_mutations_allowed(env_record)
        except PermissionError as exc:
            json_response(self, HTTPStatus.FORBIDDEN, {"ok": False, "error": str(exc)})
            return

        authority = str(body.get("authority") or signer.authority or "").strip()
        if not authority:
            json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {
                    "ok": False,
                    "error": (
                        "no authority available for this request; pass one in the UI or start the console with "
                        "--authority ENV=I105..."
                    ),
                },
            )
            return
        try:
            require_bound_request_signer(
                signer,
                authority=authority,
                environment=environment,
            )
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return
        body["authority"] = authority

        allowed_browser_keys = (
            BRIDGE_PROOF_SUBMIT_BROWSER_KEYS
            if upstream_path == "/v1/bridge/proofs/submit"
            else BRIDGE_MESSAGE_BROWSER_KEYS
        )
        unsupported_keys = sorted(set(body) - allowed_browser_keys)
        if unsupported_keys:
            json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {
                    "ok": False,
                    "error": f"unsupported bridge submit fields: {', '.join(unsupported_keys)}",
                },
            )
            return

        proof_field = BRIDGE_PROOF_FIELD_BY_PATH[upstream_path]
        try:
            decode_canonical_base64(body.get(proof_field), proof_field, maximum=MAX_REQUEST_BODY_BYTES)
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return

        fee_payment = authority_fee_payment_intent(DEFAULT_GAS_LIMIT)
        preparation_request = {
            "authority": authority,
            "fee_payment": fee_payment,
            proof_field: body[proof_field],
        }

        try:
            preparation_payload = self.execute_upstream_request(
                environment=environment,
                signer=signer,
                torii_url=torii_url,
                mode="bridge-prepare",
                path=upstream_path,
                request_payload=preparation_request,
                timeout=45,
            )
        except ConnectionError as exc:
            json_response(self, HTTPStatus.BAD_GATEWAY, {"ok": False, "error": str(exc)})
            return
        if not preparation_payload.get("ok"):
            json_response(self, HTTPStatus.BAD_GATEWAY, preparation_payload)
            return
        try:
            prepared = validate_bridge_preparation_response(preparation_payload.get("response_json"))
            signature_b64 = sign_transaction_message_ed25519(
                signer.private_key,
                signer.public_key,
                prepared["signing_message"],
            )
        except ValueError as exc:
            json_response(
                self,
                HTTPStatus.BAD_GATEWAY,
                {
                    "ok": False,
                    "error_code": "bridge_detached_signing_failed",
                    "error": str(exc),
                    "preparation": preparation_payload,
                },
            )
            return

        submission_request = {
            "authority": authority,
            "fee_payment": fee_payment,
            proof_field: body[proof_field],
            "transaction_payload_b64": prepared["transaction_payload_b64"],
            "signature_b64": signature_b64,
            "creation_time_ms": prepared["creation_time_ms"],
        }
        try:
            submission_payload = self.execute_upstream_request(
                environment=environment,
                signer=signer,
                torii_url=torii_url,
                mode="bridge-submit",
                path=upstream_path,
                request_payload=submission_request,
                timeout=45,
            )
        except ConnectionError as exc:
            json_response(self, HTTPStatus.BAD_GATEWAY, {"ok": False, "error": str(exc)})
            return
        if not submission_payload.get("ok"):
            submission_payload["preparation"] = preparation_payload
            json_response(self, HTTPStatus.BAD_GATEWAY, submission_payload)
            return
        try:
            tx_hash_hex = validate_bridge_submission_response(
                submission_payload.get("response_json"),
                expected_metadata=prepared["metadata"],
            )
        except ValueError as exc:
            submission_payload["ok"] = False
            submission_payload["error_code"] = "invalid_bridge_submission_response"
            submission_payload["error"] = str(exc)
            submission_payload["preparation"] = preparation_payload
            json_response(self, HTTPStatus.BAD_GATEWAY, submission_payload)
            return

        submission_payload["tx_hash_hex"] = tx_hash_hex
        submission_payload["detached_signing"] = {
            "prepared": True,
            "locally_signed": True,
            "submitted": True,
            "proof_field": proof_field,
            "creation_time_ms": prepared["creation_time_ms"],
            "transaction_payload_reused_exactly": True,
            "private_key_forwarded": False,
        }
        json_response(self, HTTPStatus.OK, submission_payload)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/catalog":
            json_response(self, HTTPStatus.OK, self.state.load_catalog())
            return
        if parsed.path == "/api/sccp/capabilities":
            self.handle_torii_read_proxy(parsed, "/v1/sccp/capabilities")
            return
        if parsed.path == "/api/sccp/registry":
            self.handle_torii_read_proxy(parsed, "/v1/sccp/registry")
            return
        if parsed.path == "/api/sccp/messages/recent":
            self.handle_torii_read_proxy(parsed, "/v1/sccp/messages/recent")
            return
        if parsed.path.startswith("/api/assets/definitions/"):
            selector, selector_error = normalize_asset_definition_selector(
                parsed.path.removeprefix("/api/assets/definitions/")
            )
            if selector_error:
                json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": selector_error})
                return
            encoded_selector = urllib.parse.quote(selector or "", safe="")
            self.handle_torii_read_proxy(
                parsed,
                f"/v1/assets/definitions/{encoded_selector}",
            )
            return
        if parsed.path.startswith("/api/sccp/proofs/message/"):
            message_id, message_id_error = normalize_sccp_message_id(
                parsed.path.removeprefix("/api/sccp/proofs/message/")
            )
            if message_id_error:
                json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": message_id_error})
                return
            self.handle_torii_read_proxy(parsed, f"/v1/sccp/proofs/message/{message_id}")
            return
        if parsed.path.startswith("/api/sccp/proof-requests/"):
            message_id, message_id_error = normalize_sccp_message_id(
                parsed.path.removeprefix("/api/sccp/proof-requests/")
            )
            if message_id_error:
                json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": message_id_error})
                return
            self.handle_torii_read_proxy(parsed, f"/v1/sccp/proof-requests/{message_id}")
            return
        if parsed.path == "/api/pipeline/transactions/status":
            self.handle_pipeline_transaction_status(parsed)
            return
        if parsed.path == "/api/transactions/history":
            self.handle_transactions_history(parsed)
            return

        self.serve_static(parsed.path)

    def do_POST(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/bridge/inspect":
            self.handle_bridge_inspect()
            return
        if parsed.path == "/api/bridge/proofs/submit":
            self.handle_bridge_submit_proxy("/v1/bridge/proofs/submit")
            return
        if parsed.path == "/api/bridge/messages":
            self.handle_bridge_submit_proxy("/v1/bridge/messages")
            return

        if parsed.path not in {"/api/view", "/api/call"}:
            json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": "unknown API path"})
            return

        try:
            body = parse_request_body(self)
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return

        sensitive_key_error = self.reject_explicit_sensitive_key(body)
        if sensitive_key_error:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": sensitive_key_error})
            return

        environment = str(body.get("environment") or "").strip()
        contract_address = str(body.get("contract_address") or "").strip()
        entrypoint = str(body.get("entrypoint") or "").strip()
        if not environment or not contract_address or not entrypoint:
            json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {
                    "ok": False,
                    "error": "environment, contract_address, and entrypoint are required",
                },
            )
            return

        try:
            env_record, signer = self.state.resolve_environment(environment)
        except KeyError as exc:
            json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": str(exc)})
            return

        torii_url = normalize_torii_url(env_record.get("torii_url"))
        if not torii_url:
            json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {"ok": False, "error": f"no Torii URL is known for environment {environment}"},
            )
            return

        authority = str(body.get("authority") or signer.authority or "").strip()
        if not authority:
            json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {
                    "ok": False,
                    "error": (
                        "no authority available for this request; pass one in the UI or start the console with "
                        "--authority ENV=I105..."
                    ),
                },
            )
            return
        try:
            require_bound_request_signer(
                signer,
                authority=authority,
                environment=environment,
            )
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return

        try:
            gas_limit = normalize_browser_gas_limit(body.get("gas_limit"))
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return

        try:
            validate_manifest_numeric_arguments(
                env_record,
                contract_address=contract_address,
                entrypoint_name=entrypoint,
                payload=body.get("payload"),
            )
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return

        upstream_request: dict[str, Any] = {
            "authority": authority,
            "contract_address": contract_address,
            "entrypoint": entrypoint,
        }
        if "payload" in body and body["payload"] is not None:
            upstream_request["payload"] = body["payload"]

        timeout = DEFAULT_UPSTREAM_TIMEOUT_SECONDS
        if parsed.path == "/api/call":
            try:
                self.require_mutations_allowed(env_record)
            except PermissionError as exc:
                json_response(self, HTTPStatus.FORBIDDEN, {"ok": False, "error": str(exc)})
                return
            upstream_request["fee_payment"] = authority_fee_payment_intent(gas_limit)
            try:
                payload = execute_detached_contract_call(
                    self.execute_upstream_request,
                    environment=environment,
                    signer=signer,
                    torii_url=torii_url,
                    request_payload=upstream_request,
                    timeout=timeout,
                )
            except ConnectionError as exc:
                json_response(self, HTTPStatus.BAD_GATEWAY, {"ok": False, "error": str(exc)})
                return
            json_response(self, HTTPStatus.OK if payload.get("ok") else HTTPStatus.BAD_GATEWAY, payload)
            return

        upstream_request["gas_limit"] = gas_limit

        try:
            payload = self.execute_upstream_request(
                environment=environment,
                signer=signer,
                torii_url=torii_url,
                mode="view",
                path="/v1/contracts/view",
                request_payload=upstream_request,
                timeout=timeout,
            )
        except ConnectionError as exc:
            json_response(
                self,
                HTTPStatus.BAD_GATEWAY,
                {
                    "ok": False,
                    "error": str(exc),
                },
            )
            return
        json_response(self, HTTPStatus.OK, payload)

    def handle_bridge_inspect(self) -> None:
        try:
            body = parse_request_body(self)
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return

        sensitive_key_error = self.reject_explicit_sensitive_key(body)
        if sensitive_key_error:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": sensitive_key_error})
            return

        environment = str(body.get("environment") or "").strip()
        if not environment:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": "environment is required"})
            return

        try:
            env_record, bridge_contract, signer = self.state.resolve_contract(environment, BRIDGE_CONTRACT_KEY)
        except KeyError as exc:
            json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": str(exc)})
            return

        torii_url = normalize_torii_url(env_record.get("torii_url"))
        if not torii_url:
            json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {"ok": False, "error": f"no Torii URL is known for environment {environment}"},
            )
            return

        authority = str(body.get("authority") or signer.authority or "").strip()
        if not authority:
            json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {
                    "ok": False,
                    "error": (
                        "no authority available for bridge inspection; pass one in the UI or start the console with "
                        "--authority ENV=I105..."
                    ),
                },
            )
            return
        try:
            require_bound_request_signer(
                signer,
                authority=authority,
                environment=environment,
            )
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return

        try:
            gas_limit = normalize_browser_gas_limit(body.get("gas_limit"))
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return

        contract_address = str(bridge_contract.get("contract_address") or "").strip()
        if not contract_address:
            json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {"ok": False, "error": f"bridge contract has no contract_address in environment {environment}"},
            )
            return

        requested_keys = {
            "asset_key": str(body.get("asset_key") or "").strip(),
            "route": str(body.get("route") or "").strip(),
            "transfer": str(body.get("transfer") or "").strip(),
            "message_id": str(body.get("message_id") or "").strip(),
        }

        inspections: list[tuple[str, dict[str, Any] | None]] = [("listing_config", None)]
        if requested_keys["asset_key"]:
            inspections.extend(
                [
                    ("mirror_asset", {"asset_key": requested_keys["asset_key"]}),
                    ("asset_config", {"asset_key": requested_keys["asset_key"]}),
                    ("asset_vault_bound", {"asset_key": requested_keys["asset_key"]}),
                    ("asset_vault_account", {"asset_key": requested_keys["asset_key"]}),
                ]
            )
        if requested_keys["route"]:
            inspections.extend(
                [
                    ("mirror_route", {"route": requested_keys["route"]}),
                    ("route_config", {"route": requested_keys["route"]}),
                    ("route_provenance", {"route": requested_keys["route"]}),
                ]
            )
        if requested_keys["transfer"]:
            inspections.extend(
                [
                    ("mirror_outbound", {"transfer": requested_keys["transfer"]}),
                    ("outbound_config", {"transfer": requested_keys["transfer"]}),
                ]
            )
        if requested_keys["message_id"]:
            inspections.append(("inbound_consumed", {"message_id": requested_keys["message_id"]}))

        responses: list[dict[str, Any]] = []
        overall_ok = True
        for entrypoint, payload in inspections:
            upstream_request: dict[str, Any] = {
                "authority": authority,
                "contract_address": contract_address,
                "entrypoint": entrypoint,
                "gas_limit": gas_limit,
            }
            if payload is not None:
                upstream_request["payload"] = payload

            try:
                result = self.execute_upstream_request(
                    environment=environment,
                    signer=signer,
                    torii_url=torii_url,
                    mode="bridge-inspect",
                    path="/v1/contracts/view",
                    request_payload=upstream_request,
                )
            except ConnectionError as exc:
                json_response(
                    self,
                    HTTPStatus.BAD_GATEWAY,
                    {
                        "ok": False,
                        "error": str(exc),
                    },
                )
                return

            entry_ok = bool(result["ok"])
            overall_ok = overall_ok and entry_ok
            responses.append(
                {
                    "entrypoint": entrypoint,
                    "payload": payload,
                    "ok": entry_ok,
                    "upstream_status": result["upstream_status"],
                    "upstream_content_type": result["upstream_content_type"],
                    "response_json": result["response_json"],
                    "response_text": result["response_text"],
                }
            )

        json_response(
            self,
            HTTPStatus.OK,
            {
                "ok": overall_ok,
                "environment": environment,
                "torii_url": torii_url,
                "authority": authority,
                "gas_limit": gas_limit,
                "contract": {
                    "contract_key": bridge_contract.get("contract_key"),
                    "contract_address": contract_address,
                    "contract_source": bridge_contract.get("contract_source"),
                    "deploy_nonce": bridge_contract.get("deploy_nonce"),
                    "verification": bridge_contract.get("verification"),
                },
                "requested_keys": requested_keys,
                "views": responses,
                "signer": signer_snapshot(signer),
            },
        )

    def serve_static(self, request_path: str) -> None:
        candidate = request_path or "/"
        if candidate == "/":
            candidate = "/index.html"

        relative_path = candidate.lstrip("/")
        resolved = (self.state.ui_root / relative_path).resolve()
        try:
            resolved.relative_to(self.state.ui_root.resolve())
        except ValueError:
            json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": "file not found"})
            return

        if not resolved.exists() or not resolved.is_file():
            json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": "file not found"})
            return

        content = resolved.read_bytes()
        content_type, _ = mimetypes.guess_type(str(resolved))
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", f"{content_type or 'application/octet-stream'}")
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-store")
        send_browser_security_headers(self)
        self.end_headers()
        self.wfile.write(content)

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write(f"[contract-console] {self.address_string()} - {redact_access_log_message(fmt % args)}\n")


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Serve a browser console for deployed SoraSwap contracts.",
    )
    parser.add_argument("--host", default="127.0.0.1", help="Bind host. Default: 127.0.0.1")
    parser.add_argument("--port", type=parse_tcp_port_arg, default=4173, help="Bind port. Default: 4173")
    parser.add_argument(
        "--signer",
        action="append",
        default=[],
        metavar="ENV=PATH",
        help="Bind a signer config to an environment for signed contract calls.",
    )
    parser.add_argument(
        "--authority",
        action="append",
        default=[],
        metavar="ENV=I105...",
        help="Set a default authority for an environment. Useful for view-only sessions.",
    )
    parser.add_argument(
        "--no-auto-signers",
        action="store_true",
        help="Disable automatic discovery of standard local/testnet/production signer configs.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_argument_parser()
    args = parser.parse_args(argv)

    try:
        signer_assignments = parse_assignment(args.signer, "--signer")
        authority_assignments = parse_assignment(args.authority, "--authority")
    except ValueError as exc:
        parser.error(str(exc))
        return 2

    signers = build_signer_bindings(
        REPO_ROOT,
        signer_assignments,
        authority_assignments,
        auto_discover=not args.no_auto_signers,
    )

    state = ContractConsoleState(REPO_ROOT, signers)
    evidence_issues = mutation_enabled_public_deployment_evidence_issues(state)
    if evidence_issues:
        print(
            "refusing to start mutation-enabled public contract console with stale deployment evidence:",
            file=sys.stderr,
        )
        for issue in evidence_issues:
            print(f"  - {issue}", file=sys.stderr)
        print(
            "Unset the public mutation consent flag for read-only use, or refresh the public evidence.",
            file=sys.stderr,
        )
        return 1

    server = ThreadingHTTPServer((args.host, args.port), ContractConsoleHandler)
    server.state = state  # type: ignore[attr-defined]

    print(f"SoraSwap contract console listening on http://{args.host}:{args.port}")
    for environment in state.list_environments():
        env_record = state.load_environment(environment)
        signer = env_record["signer"]
        print(
            f"  - {environment}: {len(env_record['contracts'])} contract(s), "
            f"torii={env_record.get('torii_url') or 'unconfigured'}, "
            f"signer={'yes' if signer.get('configured') else 'no'}"
            f" ({signer.get('source', 'none')}), "
            f"call-enabled={'yes' if signer.get('call_enabled') else 'no'}"
        )
        for warning in signer.get("warnings") or []:
            print(f"      warning: {warning}")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopping contract console")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
