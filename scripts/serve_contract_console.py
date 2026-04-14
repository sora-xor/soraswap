#!/usr/bin/env python3
"""Serve a lightweight browser console for deployed SoraSwap contracts."""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import re
import subprocess
import sys
import tomllib
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import UTC, datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent.parent
DEPLOYMENTS_ROOT = REPO_ROOT / "deployments"
UI_ROOT = REPO_ROOT / "ui" / "contract_console"
DEFAULT_GAS_LIMIT = 100000
DEFAULT_NETWORK_PREFIX = "753"
TESTNET_NETWORK_PREFIX = "369"
BRIDGE_CONTRACT_KEY = "bridge.sccp_bridge"


def utc_timestamp() -> str:
    return datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")


def json_response(handler: BaseHTTPRequestHandler, status: int, payload: dict[str, Any]) -> None:
    encoded = json.dumps(payload, indent=2, sort_keys=False).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(encoded)))
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(encoded)


def normalize_torii_url(value: str | None) -> str | None:
    if not value:
        return None
    return value.rstrip("/")


def is_proof_managed_bridge_entrypoint(entrypoint: str | None) -> bool:
    return (entrypoint or "finalize_inbound").strip() in {
        "finalize_inbound",
        "activate_route_governed",
    }


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


def safe_read_json(path: Path) -> dict[str, Any] | list[Any] | None:
    if not path.exists():
        return None
    with path.open("rb") as handle:
        return json.load(handle)


def safe_read_toml(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    with path.open("rb") as handle:
        return tomllib.load(handle)


def looks_like_placeholder(value: str | None) -> bool:
    if value is None:
        return True
    normalized = value.strip().lower()
    if not normalized:
        return True
    return "change_me" in normalized or "change-me" in normalized


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


def config_supports_autodiscovery(path: Path) -> bool:
    parsed = safe_read_toml(path)
    if not isinstance(parsed, dict):
        return False
    account = parsed.get("account") or {}
    public_key = account.get("public_key")
    return isinstance(public_key, str) and not looks_like_placeholder(public_key)


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


def infer_network_prefix(environment: str | None) -> str:
    normalized_environment = (environment or "").strip().lower()
    if normalized_environment == "testnet":
        return TESTNET_NETWORK_PREFIX
    if normalized_environment == "production":
        return (
            os.environ.get("SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT")
            or os.environ.get("SORASWAP_CHAIN_DISCRIMINANT")
            or os.environ.get("SORASWAP_ADDRESS_NETWORK_PREFIX")
            or DEFAULT_NETWORK_PREFIX
        )
    return os.environ.get("SORASWAP_ADDRESS_NETWORK_PREFIX", DEFAULT_NETWORK_PREFIX)


def derive_authority_from_public_key(
    public_key: str, environment: str | None
) -> tuple[str | None, str | None]:
    iroha_cli = REPO_ROOT.parent / "iroha" / "target" / "debug" / "iroha"
    if not iroha_cli.exists():
        return None, f"missing iroha CLI at {iroha_cli}"

    command = [
        str(iroha_cli),
        "--output-format",
        "text",
        "tools",
        "address",
        "convert",
        "--network-prefix",
        infer_network_prefix(environment),
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
        return None, f"failed to derive authority: {exc}"

    if completed.returncode != 0:
        stderr = completed.stderr.strip() or completed.stdout.strip() or "unknown error"
        return None, f"failed to derive authority: {stderr}"

    lines = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    if not lines:
        return None, "failed to derive authority: empty iroha CLI output"
    return lines[-1], None


@dataclass(slots=True)
class SignerBinding:
    environment: str
    config_path: Path | None
    authority: str | None
    torii_url: str | None
    private_key: str | None
    public_key: str | None
    basic_auth: tuple[str, str] | None
    warnings: list[str]
    source: str = "none"

    @property
    def configured(self) -> bool:
        return self.config_path is not None

    @property
    def can_call(self) -> bool:
        return self.configured and bool(self.private_key) and bool(self.authority)


def load_signer_binding(
    environment: str,
    config_path: str | None,
    authority_override: str | None,
    *,
    source: str,
) -> SignerBinding:
    warnings: list[str] = []
    if config_path is None:
        return SignerBinding(
            environment=environment,
            config_path=None,
            authority=authority_override,
            torii_url=None,
            private_key=None,
            public_key=None,
            basic_auth=None,
            warnings=warnings,
            source=source,
        )

    resolved_path = Path(config_path).expanduser()
    if not resolved_path.is_absolute():
        resolved_path = (Path.cwd() / resolved_path).resolve()

    with resolved_path.open("rb") as handle:
        config = tomllib.load(handle)

    account = config.get("account") or {}
    public_key = account.get("public_key")
    private_key = account.get("private_key")
    torii_url = normalize_torii_url(config.get("torii_url"))
    basic_auth_cfg = config.get("basic_auth") or {}
    basic_auth: tuple[str, str] | None = None
    if basic_auth_cfg.get("web_login") and basic_auth_cfg.get("password"):
        basic_auth = (str(basic_auth_cfg["web_login"]), str(basic_auth_cfg["password"]))

    if isinstance(public_key, str) and looks_like_placeholder(public_key):
        warnings.append(f"public key in {resolved_path} still uses placeholder content")
        public_key = None
    if isinstance(private_key, str) and looks_like_placeholder(private_key):
        warnings.append(f"private key in {resolved_path} still uses placeholder content")
        private_key = None

    authority = authority_override
    if authority is None and public_key:
        authority, warning = derive_authority_from_public_key(str(public_key), environment)
        if warning:
            warnings.append(warning)

    if authority is None:
        warnings.append(
            "no authority configured; provide --authority ENV=I105... or use a signer config that can be derived"
        )

    return SignerBinding(
        environment=environment,
        config_path=resolved_path,
        authority=authority,
        torii_url=torii_url,
        private_key=str(private_key) if private_key else None,
        public_key=str(public_key) if public_key else None,
        basic_auth=basic_auth,
        warnings=warnings,
        source=source,
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
            if config_supports_autodiscovery(candidate):
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
        contracts_latest = safe_read_json(env_root / "contracts.latest.json")

        chain_fingerprint: dict[str, Any] | None = None
        if isinstance(chain_latest, dict):
            chain_fingerprint = dict(chain_latest)
        elif isinstance(contracts_latest, dict) and isinstance(contracts_latest.get("chain_fingerprint"), dict):
            chain_fingerprint = dict(contracts_latest["chain_fingerprint"])

        record_map: dict[str, dict[str, Any]] = {}
        for path in sorted(env_root.glob("*.deploy.json")):
            parsed = safe_read_json(path)
            if not isinstance(parsed, dict):
                continue
            record_key = str(parsed.get("contract_key") or parsed.get("contract_address") or path.stem)
            record_map[record_key] = parsed
        if not record_map and isinstance(contracts_latest, dict):
            for index, record in enumerate(contracts_latest.get("contracts") or []):
                if not isinstance(record, dict):
                    continue
                record_key = str(record.get("contract_key") or record.get("contract_address") or f"record-{index}")
                record_map[record_key] = record
        records = sorted(
            record_map.values(),
            key=lambda item: str(item.get("contract_key") or item.get("contract_address") or ""),
        )

        contracts: list[dict[str, Any]] = []
        for record in records:
            contract_key = str(record.get("contract_key") or "")
            manifest_path = env_root / f"{contract_key}.manifest.json" if contract_key else None
            deployment_path = env_root / f"{contract_key}.deploy.json" if contract_key else None
            manifest = safe_read_json(manifest_path) if manifest_path else None
            entrypoints = sanitize_manifest_entrypoints(manifest if isinstance(manifest, dict) else None)
            contracts.append(
                {
                    "contract_key": contract_key,
                    "contract_source": record.get("contract_source"),
                    "contract_address": record.get("contract_address")
                    or ((record.get("instance") or {}).get("contract_address")),
                    "dataspace": record.get("dataspace"),
                    "deploy_nonce": record.get("deploy_nonce"),
                    "deploy_strategy": record.get("deploy_strategy"),
                    "code_hash_hex": record.get("code_hash_hex")
                    or ((record.get("instance") or {}).get("code_hash_hex")),
                    "abi_hash_hex": record.get("abi_hash_hex")
                    or ((record.get("instance") or {}).get("abi_hash_hex")),
                    "verification": ((record.get("instance") or {}).get("verification")),
                    "tx_hash_hex": ((record.get("instance") or {}).get("tx_hash_hex"))
                    or ((record.get("response") or {}).get("tx_hash_hex")),
                    "deployment_path": str(deployment_path) if deployment_path and deployment_path.exists() else None,
                    "manifest_path": str(manifest_path) if manifest_path and manifest_path.exists() else None,
                    "entrypoints": entrypoints,
                }
            )

        signer = self.signers.get(environment) or SignerBinding(
            environment=environment,
            config_path=None,
            authority=None,
            torii_url=None,
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
        warnings = list(signer.warnings)

        return {
            "name": environment,
            "torii_url": effective_torii_url,
            "torii_url_source": torii_url_source,
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
            "repo_root": str(self.repo_root),
            "environments": environments,
        }

    def resolve_environment(self, environment: str) -> tuple[dict[str, Any], SignerBinding]:
        loaded = self.load_environment(environment)
        signer = self.signers.get(environment) or SignerBinding(
            environment=environment,
            config_path=None,
            authority=None,
            torii_url=None,
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
    content_length = int(handler.headers.get("Content-Length") or "0")
    raw = handler.rfile.read(content_length) if content_length else b"{}"
    try:
        parsed = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid JSON body: {exc}") from exc
    if not isinstance(parsed, dict):
        raise ValueError("request body must be a JSON object")
    return parsed


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
) -> tuple[int, str, str | None]:
    request_url = f"{torii_url}{path}"
    query_string = encoded_query(query)
    if query_string:
        request_url = f"{request_url}?{query_string}"

    encoded_payload = json.dumps(payload).encode("utf-8") if payload is not None else None
    headers = {
        "Accept": accept,
    }
    if payload is not None:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        url=request_url,
        data=encoded_payload,
        method=method,
        headers=headers,
    )
    if basic_auth:
        token = base64.b64encode(f"{basic_auth[0]}:{basic_auth[1]}".encode("utf-8")).decode("ascii")
        request.add_header("Authorization", f"Basic {token}")

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read().decode("utf-8", errors="replace")
            return response.status, body, response.headers.get("Content-Type")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        return exc.code, body, exc.headers.get("Content-Type")


def decode_json_maybe(response_text: str) -> Any:
    if not response_text:
        return None
    try:
        return json.loads(response_text)
    except json.JSONDecodeError:
        return None


def query_dict_from_pairs(pairs: dict[str, list[str]]) -> dict[str, str | list[str]]:
    normalized: dict[str, str | list[str]] = {}
    for key, values in pairs.items():
        filtered = [value for value in values if value != ""]
        if not filtered:
            continue
        normalized[key] = filtered if len(filtered) > 1 else filtered[0]
    return normalized


def encoded_query(query: dict[str, Any] | None) -> str:
    if not query:
        return ""
    items: list[tuple[str, str]] = []
    for key, raw_value in query.items():
        values = raw_value if isinstance(raw_value, list | tuple) else [raw_value]
        for value in values:
            if value in (None, ""):
                continue
            items.append((key, str(value)))
    return urllib.parse.urlencode(items, doseq=True)


def signer_snapshot(signer: SignerBinding) -> dict[str, Any]:
    return {
        "configured": signer.configured,
        "config_path": str(signer.config_path) if signer.config_path else None,
        "authority": signer.authority,
        "torii_url": signer.torii_url,
        "call_enabled": signer.can_call,
        "basic_auth_configured": signer.basic_auth is not None,
        "source": signer.source,
        "warnings": list(signer.warnings),
    }


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
        flag = "SORASWAP_ALLOW_TESTNET_MUTATIONS"
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


def redact_request_payload(payload: dict[str, Any] | None) -> dict[str, Any] | None:
    if payload is None:
        return None
    redacted = dict(payload)
    if "private_key" in redacted:
        redacted["private_key"] = "[redacted]"
    return redacted


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

    def pick_kind(value: Any) -> str | None:
        if isinstance(value, str) and value.strip():
            return value.strip()
        if isinstance(value, dict):
            kind = value.get("kind")
            if isinstance(kind, str) and kind.strip():
                return kind.strip()
        return None

    direct = pick_kind(response_json.get("status"))
    if direct:
        return direct
    content = response_json.get("content")
    if isinstance(content, dict):
        nested = pick_kind(content.get("status"))
        if nested:
            return nested
    return None


def extract_rejection_reason(response_json: Any) -> str | None:
    if not isinstance(response_json, dict):
        return None

    direct_status = response_json.get("status")
    if isinstance(direct_status, dict):
        for key in ("rejection_reason", "rejectionReason", "reason", "reject_code", "rejectCode"):
            value = direct_status.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
        if (
            str(direct_status.get("kind") or "").strip().lower() == "rejected"
            and isinstance(direct_status.get("content"), str)
            and str(direct_status["content"]).strip()
        ):
            return str(direct_status["content"]).strip()

    for key in ("rejection_reason", "rejectionReason", "reason", "reject_code", "rejectCode"):
        value = response_json.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()

    content = response_json.get("content")
    if isinstance(content, dict):
        for key in ("rejection_reason", "rejectionReason", "reason", "reject_code", "rejectCode"):
            value = content.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
        status = content.get("status")
        if isinstance(status, dict):
            for key in ("rejection_reason", "rejectionReason", "reason", "reject_code", "rejectCode"):
                value = status.get(key)
                if isinstance(value, str) and value.strip():
                    return value.strip()
            if (
                str(status.get("kind") or "").strip().lower() == "rejected"
                and isinstance(status.get("content"), str)
                and str(status["content"]).strip()
            ):
                return str(status["content"]).strip()
    return None


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
    rejection_reason = extract_rejection_reason(response_json)
    if rejection_reason:
        result["rejection_reason"] = rejection_reason
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

    def reject_explicit_private_key(self, body: dict[str, Any]) -> str | None:
        if body.get("private_key") not in (None, ""):
            return "private_key must not be supplied in browser JSON; bind a signer config instead"
        return None

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
        timeout: int = 30,
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
            )
        except OSError as exc:
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
        query_params = urllib.parse.parse_qs(parsed.query, keep_blank_values=False)
        environment = str((query_params.pop("environment", [""])[0]) or "").strip()

        try:
            _, signer, torii_url = self.resolve_proxy_environment(environment)
        except KeyError as exc:
            json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": str(exc)})
            return
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return

        request_query = query_dict_from_pairs(query_params)
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
        query_params = urllib.parse.parse_qs(parsed.query, keep_blank_values=False)
        environment = str((query_params.pop("environment", [""])[0]) or "").strip()
        tx_hash_hex = str((query_params.get("hash", [""])[0]) or "").strip()
        if not tx_hash_hex:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": "hash is required"})
            return

        try:
            _, signer, torii_url = self.resolve_proxy_environment(environment)
        except KeyError as exc:
            json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": str(exc)})
            return
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return

        request_query = query_dict_from_pairs(query_params)
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
        json_response(self, HTTPStatus.OK, payload)

    def handle_transactions_history(self, parsed: urllib.parse.ParseResult) -> None:
        query_params = urllib.parse.parse_qs(parsed.query, keep_blank_values=False)
        environment = str((query_params.pop("environment", [""])[0]) or "").strip()

        try:
            _, signer, torii_url = self.resolve_proxy_environment(environment)
        except KeyError as exc:
            json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": str(exc)})
            return
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return

        request_query = query_dict_from_pairs(query_params)
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

    def handle_bridge_submit_proxy(self, upstream_path: str, *, message_bundle_required: bool) -> None:
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

        private_key_error = self.reject_explicit_private_key(body)
        if private_key_error:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": private_key_error})
            return

        try:
            self.require_mutations_allowed(env_record)
        except PermissionError as exc:
            json_response(self, HTTPStatus.FORBIDDEN, {"ok": False, "error": str(exc)})
            return

        if not signer.private_key:
            json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {
                    "ok": False,
                    "error": (
                        f"no signer config with private key is bound for environment {environment}; "
                        "start the console with --signer ENV=/path/to/client.toml"
                    ),
                },
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
        body["authority"] = authority

        body["private_key"] = signer.private_key

        if upstream_path == "/v1/bridge/proofs/submit":
            bundle_keys = ("burn_bundle", "governance_bundle", "message_bundle")
            bundle_count = sum(
                1
                for key in bundle_keys
                if key in body and body[key] is not None
            )
            if bundle_count != 1:
                json_response(
                    self,
                    HTTPStatus.BAD_REQUEST,
                    {
                        "ok": False,
                        "error": "provide exactly one of burn_bundle, governance_bundle, or message_bundle",
                    },
                )
                return
        if message_bundle_required and not isinstance(body.get("message_bundle"), dict):
            json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {"ok": False, "error": "message_bundle is required and must be a JSON object"},
            )
            return
        if "message_bundle" in body and body["message_bundle"] is not None and not isinstance(body["message_bundle"], dict):
            json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {"ok": False, "error": "message_bundle must be a JSON object"},
            )
            return
        for key in ("burn_bundle", "governance_bundle"):
            if key in body and body[key] is not None and not isinstance(body[key], dict):
                json_response(
                    self,
                    HTTPStatus.BAD_REQUEST,
                    {"ok": False, "error": f"{key} must be a JSON object"},
                )
                return
        if "settlement" in body and body["settlement"] is not None and not isinstance(body["settlement"], dict):
            json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {"ok": False, "error": "settlement must be a JSON object"},
            )
            return
        settlement_entrypoint = None
        if isinstance(body.get("settlement"), dict):
            settlement_entrypoint = str(body["settlement"].get("entrypoint") or "finalize_inbound").strip()
        if (
            message_bundle_required
            and isinstance(body.get("settlement"), dict)
            and body["settlement"].get("payload") is not None
            and is_proof_managed_bridge_entrypoint(settlement_entrypoint)
        ):
            json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {
                    "ok": False,
                    "error": (
                        "bridge message submissions for proof-managed bridge entrypoints must not "
                        "supply settlement.payload; use the proof-driven route fields only"
                    ),
                },
            )
            return

        try:
            payload = self.execute_upstream_request(
                environment=environment,
                signer=signer,
                torii_url=torii_url,
                mode="submit",
                path=upstream_path,
                request_payload=body,
                timeout=45,
            )
        except ConnectionError as exc:
            json_response(self, HTTPStatus.BAD_GATEWAY, {"ok": False, "error": str(exc)})
            return

        json_response(self, HTTPStatus.OK, payload)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/catalog":
            json_response(self, HTTPStatus.OK, self.state.load_catalog())
            return
        if parsed.path == "/api/sccp/capabilities":
            self.handle_torii_read_proxy(parsed, "/v1/sccp/capabilities")
            return
        if parsed.path == "/api/sccp/manifests":
            self.handle_torii_read_proxy(parsed, "/v1/sccp/manifests")
            return
        if parsed.path == "/api/sccp/messages/recent":
            self.handle_torii_read_proxy(parsed, "/v1/sccp/messages/recent")
            return
        if parsed.path.startswith("/api/sccp/proofs/message/"):
            message_id = parsed.path.removeprefix("/api/sccp/proofs/message/").strip()
            if not message_id:
                json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": "message_id is required"})
                return
            self.handle_torii_read_proxy(parsed, f"/v1/sccp/proofs/message/{message_id}")
            return
        if parsed.path.startswith("/api/sccp/artifacts/message/"):
            message_id = parsed.path.removeprefix("/api/sccp/artifacts/message/").strip()
            if not message_id:
                json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": "message_id is required"})
                return
            self.handle_torii_read_proxy(parsed, f"/v1/sccp/artifacts/message/{message_id}")
            return
        if parsed.path.startswith("/api/sccp/jobs/message/"):
            message_id = parsed.path.removeprefix("/api/sccp/jobs/message/").strip()
            if not message_id:
                json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": "message_id is required"})
                return
            self.handle_torii_read_proxy(parsed, f"/v1/sccp/jobs/message/{message_id}")
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
            self.handle_bridge_submit_proxy("/v1/bridge/proofs/submit", message_bundle_required=False)
            return
        if parsed.path == "/api/bridge/messages":
            self.handle_bridge_submit_proxy("/v1/bridge/messages", message_bundle_required=True)
            return

        if parsed.path not in {"/api/view", "/api/call"}:
            json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": "unknown API path"})
            return

        try:
            body = parse_request_body(self)
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
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

        gas_limit = body.get("gas_limit")
        if gas_limit in (None, ""):
            gas_limit = DEFAULT_GAS_LIMIT
        try:
            gas_limit = int(gas_limit)
        except (TypeError, ValueError):
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": "gas_limit must be an integer"})
            return

        upstream_request: dict[str, Any] = {
            "authority": authority,
            "contract_address": contract_address,
            "entrypoint": entrypoint,
            "gas_limit": gas_limit,
        }
        if "payload" in body and body["payload"] is not None:
            upstream_request["payload"] = body["payload"]

        timeout = 30
        path = "/v1/contracts/view"
        if parsed.path == "/api/call":
            private_key_error = self.reject_explicit_private_key(body)
            if private_key_error:
                json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": private_key_error})
                return
            try:
                self.require_mutations_allowed(env_record)
            except PermissionError as exc:
                json_response(self, HTTPStatus.FORBIDDEN, {"ok": False, "error": str(exc)})
                return
            path = "/v1/contracts/call"
            if not signer.private_key:
                json_response(
                    self,
                    HTTPStatus.BAD_REQUEST,
                    {
                        "ok": False,
                        "error": (
                            f"no signer config with private key is bound for environment {environment}; "
                            "start the console with --signer ENV=/path/to/client.toml"
                        ),
                    },
                )
                return
            upstream_request["private_key"] = signer.private_key

        try:
            payload = self.execute_upstream_request(
                environment=environment,
                signer=signer,
                torii_url=torii_url,
                mode="call" if parsed.path == "/api/call" else "view",
                path=path,
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

        gas_limit = body.get("gas_limit")
        if gas_limit in (None, ""):
            gas_limit = DEFAULT_GAS_LIMIT
        try:
            gas_limit = int(gas_limit)
        except (TypeError, ValueError):
            json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": "gas_limit must be an integer"})
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
        self.end_headers()
        self.wfile.write(content)

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write(f"[contract-console] {self.address_string()} - {fmt % args}\n")


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Serve a browser console for deployed SoraSwap contracts.",
    )
    parser.add_argument("--host", default="127.0.0.1", help="Bind host. Default: 127.0.0.1")
    parser.add_argument("--port", type=int, default=4173, help="Bind port. Default: 4173")
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
