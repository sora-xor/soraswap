#!/usr/bin/env python3
"""Serve the SoraSwap trader cockpit."""

from __future__ import annotations

import argparse
import base64
import mimetypes
import socketserver
import sys
import urllib.parse
import urllib.request
import urllib.error
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

import serve_contract_console as contract_console


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_GAS_LIMIT = 100000
DEFAULT_ROUTER_CONTRACT_KEY = "dlmm.dlmm_router"
DEFAULT_READ_PROXY_LIMIT_CAP = 500
DEFAULT_READ_PROXY_OFFSET_CAP = 10000
DEFAULT_SSE_QUERY_TEXT_CAP = 256
MAX_SSE_LINE_BYTES = 1_048_576
READ_PROXY_TEXT_QUERY_KEYS = {"authority", "contract_address", "cursor", "module"}
SSE_TEXT_QUERY_KEYS = {"authority", "contract_address", "cursor", "module"}
READ_PROXY_LIMITS = {
    "/v1/contracts/activity": {"default": 200, "cap": DEFAULT_READ_PROXY_LIMIT_CAP},
    "/v1/contracts/events": {"default": 200, "cap": DEFAULT_READ_PROXY_LIMIT_CAP},
    "/v1/contracts/rollups/swaps/fills": {"default": 120, "cap": DEFAULT_READ_PROXY_LIMIT_CAP},
    "/v1/contracts/rollups/swaps/candles": {"default": 120, "cap": DEFAULT_READ_PROXY_LIMIT_CAP},
    "/v1/contracts/rollups/trader/activity": {"default": 64, "cap": DEFAULT_READ_PROXY_LIMIT_CAP},
    "/v1/contracts/rollups/intents": {"default": 64, "cap": 250},
    "/v1/contracts/rollups/vaults/positions": {"default": 64, "cap": 250},
    "/v1/contracts/rollups/operators/status": {"default": 64, "cap": 250},
    "/v1/contracts/rollups/margin/health": {"default": 64, "cap": 250},
    "/v1/contracts/rollups/rwa/lots": {"default": 64, "cap": 250},
    "/v1/contracts/rollups/dlmm/hooks": {"default": 64, "cap": 250},
}
READ_PROXY_ALLOWLIST_PATHS = set(READ_PROXY_LIMITS) | {
    "/v1/contracts/rollups/trader/account",
}
READ_PROXY_TEXT_QUERY_KEYS_BY_PATH = {
    "/v1/contracts/rollups/trader/account": {"authority"},
}
READ_PROXY_INT_QUERY_LIMITS_BY_PATH = {
    "/v1/contracts/rollups/swaps/candles": {
        "bucket_secs": {"default": 3600, "minimum": 1, "maximum": 86400},
    },
}


def _first_query_value(value: str | list[str] | tuple[str, ...] | None) -> str | None:
    if value is None:
        return None
    if isinstance(value, list | tuple):
        return str(value[0]) if value else None
    return str(value)


def _bounded_int_query_value(
    value: str | list[str] | tuple[str, ...] | None,
    *,
    default: int,
    minimum: int,
    maximum: int,
) -> str:
    raw = _first_query_value(value)
    try:
        parsed = int(raw) if raw not in (None, "") else default
    except (TypeError, ValueError):
        parsed = default
    parsed = max(minimum, min(maximum, parsed))
    return str(parsed)


def bounded_read_proxy_query(
    upstream_path: str,
    query_params: dict[str, list[str]],
) -> dict[str, str | list[str]]:
    if upstream_path.startswith("/v1/assets/definitions/"):
        return {}
    if upstream_path not in READ_PROXY_ALLOWLIST_PATHS:
        return contract_console.query_dict_from_pairs(query_params)

    query: dict[str, str | list[str]] = {}
    text_query_keys = READ_PROXY_TEXT_QUERY_KEYS_BY_PATH.get(upstream_path, READ_PROXY_TEXT_QUERY_KEYS)
    for key in sorted(text_query_keys):
        value = _bounded_text_query_value(
            query_params.get(key),
            maximum_length=DEFAULT_SSE_QUERY_TEXT_CAP,
        )
        if value:
            query[key] = value

    int_query_limits = READ_PROXY_INT_QUERY_LIMITS_BY_PATH.get(upstream_path, {})
    for key, config in int_query_limits.items():
        if key in query_params:
            query[key] = _bounded_int_query_value(
                query_params.get(key),
                default=config["default"],
                minimum=config["minimum"],
                maximum=config["maximum"],
            )

    limit_config = READ_PROXY_LIMITS.get(upstream_path)
    if limit_config is None:
        return query

    query["limit"] = _bounded_int_query_value(
        query_params.get("limit"),
        default=limit_config["default"],
        minimum=1,
        maximum=limit_config["cap"],
    )
    for offset_key in ("from", "offset"):
        if offset_key in query_params:
            query[offset_key] = _bounded_int_query_value(
                query_params.get(offset_key),
                default=0,
                minimum=0,
                maximum=DEFAULT_READ_PROXY_OFFSET_CAP,
            )
    return query


def _bounded_text_query_value(
    value: str | list[str] | tuple[str, ...] | None,
    *,
    maximum_length: int,
) -> str | None:
    raw = _first_query_value(value)
    if raw in (None, ""):
        return None
    return str(raw)[:maximum_length]


def bounded_sse_proxy_query(query_params: dict[str, list[str]]) -> dict[str, str]:
    query: dict[str, str] = {}
    for key in sorted(SSE_TEXT_QUERY_KEYS):
        value = _bounded_text_query_value(
            query_params.get(key),
            maximum_length=DEFAULT_SSE_QUERY_TEXT_CAP,
        )
        if value:
            query[key] = value

    if "limit" in query_params:
        query["limit"] = _bounded_int_query_value(
            query_params.get("limit"),
            default=DEFAULT_READ_PROXY_LIMIT_CAP,
            minimum=1,
            maximum=DEFAULT_READ_PROXY_LIMIT_CAP,
        )
    if "from" in query_params:
        query["from"] = _bounded_int_query_value(
            query_params.get("from"),
            default=0,
            minimum=0,
            maximum=DEFAULT_READ_PROXY_OFFSET_CAP,
        )
    if "offset" in query_params:
        query["offset"] = _bounded_int_query_value(
            query_params.get("offset"),
            default=0,
            minimum=0,
            maximum=DEFAULT_READ_PROXY_OFFSET_CAP,
        )
    return query


def read_bounded_sse_line(upstream: Any) -> bytes:
    line = upstream.readline(MAX_SSE_LINE_BYTES + 1)
    if len(line) > MAX_SSE_LINE_BYTES:
        raise OSError(f"SSE upstream line exceeds {MAX_SSE_LINE_BYTES} byte limit")
    return line


class FastThreadingHTTPServer(ThreadingHTTPServer):
    def server_bind(self) -> None:
        socketserver.TCPServer.server_bind(self)
        host, port = self.server_address[:2]
        self.server_name = str(host)
        self.server_port = port


class TraderUiState:
    def __init__(self, repo_root: Path, signers: dict[str, contract_console.SignerBinding]) -> None:
        self.repo_root = repo_root
        self.ui_root = repo_root / "ui" / "trader"
        self.contract_console_state = contract_console.ContractConsoleState(repo_root, signers)

    def list_environments(self) -> list[str]:
        return self.contract_console_state.list_environments()

    def load_environment(self, environment: str) -> dict[str, Any]:
        loaded = self.contract_console_state.load_environment(environment)
        preferred_contract = next(
            (
                contract
                for contract in loaded.get("contracts") or []
                if contract.get("contract_key") == DEFAULT_ROUTER_CONTRACT_KEY
            ),
            None,
        )
        loaded["preferred_contract_key"] = DEFAULT_ROUTER_CONTRACT_KEY
        loaded["preferred_contract"] = preferred_contract
        return loaded

    def load_catalog(self) -> dict[str, Any]:
        return {
            "generated_at": contract_console.utc_timestamp(),
            "repo_name": self.repo_root.name,
            "repo_root": self.repo_root.name,
            "preferred_contract_key": DEFAULT_ROUTER_CONTRACT_KEY,
            "environments": [self.load_environment(name) for name in self.list_environments()],
        }

    def resolve_environment(
        self, environment: str
    ) -> tuple[dict[str, Any], contract_console.SignerBinding]:
        loaded = self.load_environment(environment)
        signer = self.contract_console_state.signers.get(environment) or contract_console.SignerBinding(
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


class TraderUiHandler(BaseHTTPRequestHandler):
    server_version = "SoraSwapTraderUi/0.1"

    @property
    def state(self) -> TraderUiState:
        return self.server.state  # type: ignore[attr-defined]

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write(f"[trader-ui] {self.address_string()} - {contract_console.redact_access_log_message(fmt % args)}\n")

    def resolve_proxy_environment(
        self, environment: str
    ) -> tuple[dict[str, Any], contract_console.SignerBinding, str]:
        if not environment:
            raise ValueError("environment is required")
        env_record, signer = self.state.resolve_environment(environment)
        torii_url = contract_console.normalize_torii_url(env_record.get("torii_url"))
        if not torii_url:
            raise ValueError(f"no Torii URL is known for environment {environment}")
        return env_record, signer, torii_url

    def require_mutations_allowed(self, env_record: dict[str, Any]) -> None:
        policy = env_record.get("mutation_policy") or {}
        if bool(policy.get("allowed")):
            return
        reason = str(policy.get("reason") or "").strip()
        if not reason:
            reason = (
                f"signed mutations are disabled for environment {env_record.get('name') or 'unknown'}"
            )
        raise PermissionError(reason)

    def execute_upstream_request(
        self,
        *,
        environment: str,
        signer: contract_console.SignerBinding,
        torii_url: str,
        mode: str,
        path: str,
        query: dict[str, Any] | None = None,
        request_payload: dict[str, Any] | None = None,
        timeout: int = 30,
    ) -> dict[str, Any]:
        try:
            upstream_status, response_text, upstream_content_type = contract_console.proxy_torii_request(
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

        return contract_console.build_proxy_result(
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
            query_params = contract_console.parse_bounded_query(parsed.query)
        except ValueError as exc:
            contract_console.json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return
        environment = str((query_params.pop("environment", [""])[0]) or "").strip()

        try:
            _, signer, torii_url = self.resolve_proxy_environment(environment)
        except KeyError as exc:
            contract_console.json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": str(exc)})
            return
        except ValueError as exc:
            contract_console.json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return

        request_query = bounded_read_proxy_query(upstream_path, query_params)
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
            contract_console.json_response(self, HTTPStatus.BAD_GATEWAY, {"ok": False, "error": str(exc)})
            return

        contract_console.json_response(self, HTTPStatus.OK, payload)

    def handle_torii_events_sse(
        self, parsed: urllib.parse.ParseResult, upstream_path: str = "/v1/events/sse"
    ) -> None:
        try:
            query_params = contract_console.parse_bounded_query(parsed.query)
        except ValueError as exc:
            contract_console.json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return
        environment = str((query_params.pop("environment", [""])[0]) or "").strip()

        try:
            _, signer, torii_url = self.resolve_proxy_environment(environment)
        except KeyError as exc:
            contract_console.json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": str(exc)})
            return
        except ValueError as exc:
            contract_console.json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return

        request_query = bounded_sse_proxy_query(query_params)
        upstream_query = urllib.parse.urlencode(request_query, doseq=True)
        upstream_url = f"{torii_url}{upstream_path}"
        if upstream_query:
            upstream_url = f"{upstream_url}?{upstream_query}"

        headers = {"Accept": "text/event-stream"}
        if signer.basic_auth:
            token = base64.b64encode(
                f"{signer.basic_auth[0]}:{signer.basic_auth[1]}".encode("utf-8")
            ).decode("ascii")
            headers["Authorization"] = f"Basic {token}"

        request = urllib.request.Request(upstream_url, headers=headers, method="GET")
        try:
            upstream = urllib.request.urlopen(request, timeout=300)
        except urllib.error.HTTPError as exc:
            try:
                body = contract_console.read_limited_text(exc)
            except OSError as read_error:
                body = str(read_error)
            contract_console.json_response(
                self,
                HTTPStatus.BAD_GATEWAY,
                {"ok": False, "error": f"SSE upstream rejected request: {body or exc.reason}"},
            )
            return
        except OSError as exc:
            contract_console.json_response(
                self,
                HTTPStatus.BAD_GATEWAY,
                {"ok": False, "error": f"failed to open SSE stream from {upstream_url}: {exc}"},
            )
            return

        try:
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Connection", "keep-alive")
            contract_console.send_browser_security_headers(self)
            self.end_headers()

            while True:
                line = read_bounded_sse_line(upstream)
                if not line:
                    break
                self.wfile.write(line)
                self.wfile.flush()
        except OSError:
            return
        except (BrokenPipeError, ConnectionResetError):
            return
        finally:
            upstream.close()

    def handle_pipeline_transaction_status(self, parsed: urllib.parse.ParseResult) -> None:
        try:
            query_params = contract_console.parse_bounded_query(parsed.query)
        except ValueError as exc:
            contract_console.json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return
        environment = str((query_params.pop("environment", [""])[0]) or "").strip()
        request_query, query_error = contract_console.bounded_status_proxy_query(query_params)
        if query_error:
            contract_console.json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": query_error})
            return

        try:
            _, signer, torii_url = self.resolve_proxy_environment(environment)
        except KeyError as exc:
            contract_console.json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": str(exc)})
            return
        except ValueError as exc:
            contract_console.json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
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
            contract_console.json_response(self, HTTPStatus.BAD_GATEWAY, {"ok": False, "error": str(exc)})
            return

        if payload["upstream_status"] == 404 and "status_kind" not in payload:
            payload["status_kind"] = "NotFound"
            payload["status_scope"] = request_query["scope"]
        elif payload["upstream_status"] == 200:
            try:
                typed_status = contract_console.validate_pipeline_status_response(
                    payload.get("response_json"),
                    expected_hash=request_query["hash"],
                    expected_scope=request_query["scope"],
                )
            except ValueError as exc:
                payload["ok"] = False
                payload["error_code"] = "invalid_upstream_status_payload"
                payload["error"] = str(exc)
                contract_console.json_response(self, HTTPStatus.BAD_GATEWAY, payload)
                return
            payload["status_kind"] = typed_status["kind"]
            payload["status_scope"] = typed_status["scope"]
            payload["status_resolved_from"] = typed_status["resolved_from"]
            if typed_status["block_height"] is not None:
                payload["status_block_height"] = typed_status["block_height"]
        contract_console.json_response(self, HTTPStatus.OK, payload)

    def serve_static(self, request_path: str) -> None:
        candidate = request_path or "/"
        if candidate == "/":
            candidate = "/index.html"

        relative_path = candidate.lstrip("/")
        resolved = (self.state.ui_root / relative_path).resolve()
        try:
            resolved.relative_to(self.state.ui_root.resolve())
        except ValueError:
            contract_console.json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": "file not found"})
            return

        if not resolved.exists() or not resolved.is_file():
            contract_console.json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": "file not found"})
            return

        content = resolved.read_bytes()
        content_type, _ = mimetypes.guess_type(str(resolved))
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", f"{content_type or 'application/octet-stream'}")
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-store")
        contract_console.send_browser_security_headers(self)
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/catalog":
            contract_console.json_response(self, HTTPStatus.OK, self.state.load_catalog())
            return
        if parsed.path.startswith("/api/assets/definitions/"):
            selector, selector_error = contract_console.normalize_asset_definition_selector(
                parsed.path.removeprefix("/api/assets/definitions/")
            )
            if selector_error:
                contract_console.json_response(
                    self,
                    HTTPStatus.BAD_REQUEST,
                    {"ok": False, "error": selector_error},
                )
                return
            encoded_selector = urllib.parse.quote(selector or "", safe="")
            self.handle_torii_read_proxy(
                parsed,
                f"/v1/assets/definitions/{encoded_selector}",
            )
            return
        if parsed.path == "/api/contracts/activity":
            self.handle_torii_read_proxy(parsed, "/v1/contracts/activity")
            return
        if parsed.path == "/api/contracts/events":
            self.handle_torii_read_proxy(parsed, "/v1/contracts/events")
            return
        if parsed.path == "/api/contracts/rollups/swaps/fills":
            self.handle_torii_read_proxy(parsed, "/v1/contracts/rollups/swaps/fills")
            return
        if parsed.path == "/api/contracts/rollups/swaps/candles":
            self.handle_torii_read_proxy(parsed, "/v1/contracts/rollups/swaps/candles")
            return
        if parsed.path == "/api/contracts/rollups/trader/activity":
            self.handle_torii_read_proxy(parsed, "/v1/contracts/rollups/trader/activity")
            return
        if parsed.path == "/api/contracts/rollups/trader/account":
            self.handle_torii_read_proxy(parsed, "/v1/contracts/rollups/trader/account")
            return
        if parsed.path == "/api/contracts/rollups/intents":
            self.handle_torii_read_proxy(parsed, "/v1/contracts/rollups/intents")
            return
        if parsed.path == "/api/contracts/rollups/vaults/positions":
            self.handle_torii_read_proxy(parsed, "/v1/contracts/rollups/vaults/positions")
            return
        if parsed.path == "/api/contracts/rollups/operators/status":
            self.handle_torii_read_proxy(parsed, "/v1/contracts/rollups/operators/status")
            return
        if parsed.path == "/api/contracts/rollups/margin/health":
            self.handle_torii_read_proxy(parsed, "/v1/contracts/rollups/margin/health")
            return
        if parsed.path == "/api/contracts/rollups/rwa/lots":
            self.handle_torii_read_proxy(parsed, "/v1/contracts/rollups/rwa/lots")
            return
        if parsed.path == "/api/contracts/rollups/dlmm/hooks":
            self.handle_torii_read_proxy(parsed, "/v1/contracts/rollups/dlmm/hooks")
            return
        if parsed.path == "/api/events/sse":
            self.handle_torii_events_sse(parsed)
            return
        if parsed.path == "/api/contracts/events/sse":
            self.handle_torii_events_sse(parsed, "/v1/contracts/events/sse")
            return
        if parsed.path == "/api/pipeline/transactions/status":
            self.handle_pipeline_transaction_status(parsed)
            return
        self.serve_static(parsed.path)

    def do_POST(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path not in {"/api/view", "/api/view/batch", "/api/call"}:
            contract_console.json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": "unknown API path"})
            return

        try:
            body = contract_console.parse_request_body(self)
        except ValueError as exc:
            contract_console.json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return
        sensitive_key_error = contract_console.explicit_sensitive_key_error(body)
        if sensitive_key_error:
            contract_console.json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": sensitive_key_error})
            return

        environment = str(body.get("environment") or "").strip()
        if parsed.path == "/api/view/batch":
            try:
                env_record, signer, torii_url = self.resolve_proxy_environment(environment)
            except KeyError as exc:
                contract_console.json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": str(exc)})
                return
            except ValueError as exc:
                contract_console.json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
                return

            authority = str(body.get("authority") or signer.authority or "").strip()
            items = body.get("items")
            if not environment or not authority or not isinstance(items, list) or not items:
                contract_console.json_response(
                    self,
                    HTTPStatus.BAD_REQUEST,
                    {
                        "ok": False,
                        "error": "environment, authority, and a non-empty items list are required",
                    },
                )
                return
            try:
                contract_console.require_bound_request_signer(
                    signer,
                    authority=authority,
                    environment=environment,
                )
            except ValueError as exc:
                contract_console.json_response(
                    self,
                    HTTPStatus.BAD_REQUEST,
                    {"ok": False, "error": str(exc)},
                )
                return

            try:
                for index, item in enumerate(items):
                    if not isinstance(item, dict):
                        raise ValueError(f"items[{index}] must be a JSON object")
                    contract_console.validate_manifest_numeric_arguments(
                        env_record,
                        contract_address=str(item.get("contract_address") or "").strip(),
                        entrypoint_name=str(item.get("entrypoint") or "").strip(),
                        payload=item.get("payload"),
                        context=f"items[{index}].payload",
                    )
            except ValueError as exc:
                contract_console.json_response(
                    self,
                    HTTPStatus.BAD_REQUEST,
                    {"ok": False, "error": str(exc)},
                )
                return

            request_payload: dict[str, Any] = {
                "authority": authority,
                "items": items,
            }
            if "gas_limit" in body and body["gas_limit"] not in (None, ""):
                try:
                    request_payload["gas_limit"] = contract_console.normalize_browser_gas_limit(
                        body["gas_limit"]
                    )
                except ValueError as exc:
                    contract_console.json_response(
                        self,
                        HTTPStatus.BAD_REQUEST,
                        {"ok": False, "error": str(exc)},
                    )
                    return

            try:
                payload = self.execute_upstream_request(
                    environment=environment,
                    signer=signer,
                    torii_url=torii_url,
                    mode="view_batch",
                    path="/v1/contracts/view/batch",
                    request_payload=request_payload,
                )
            except ConnectionError as exc:
                contract_console.json_response(self, HTTPStatus.BAD_GATEWAY, {"ok": False, "error": str(exc)})
                return

            contract_console.json_response(self, HTTPStatus.OK, payload)
            return

        contract_address = str(body.get("contract_address") or "").strip()
        entrypoint = str(body.get("entrypoint") or "").strip()
        if not environment or not contract_address or not entrypoint:
            contract_console.json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {"ok": False, "error": "environment, contract_address, and entrypoint are required"},
            )
            return

        try:
            env_record, signer, torii_url = self.resolve_proxy_environment(environment)
        except KeyError as exc:
            contract_console.json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": str(exc)})
            return
        except ValueError as exc:
            contract_console.json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return

        authority = str(body.get("authority") or signer.authority or "").strip()
        if not authority:
            contract_console.json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {
                    "ok": False,
                    "error": (
                        "no authority available for this request; pass one in the UI or start the trader with "
                        "--authority ENV=I105..."
                    ),
                },
            )
            return
        try:
            contract_console.require_bound_request_signer(
                signer,
                authority=authority,
                environment=environment,
            )
        except ValueError as exc:
            contract_console.json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {"ok": False, "error": str(exc)},
            )
            return

        try:
            gas_limit = contract_console.normalize_browser_gas_limit(body.get("gas_limit"))
        except ValueError as exc:
            contract_console.json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {"ok": False, "error": str(exc)},
            )
            return

        try:
            contract_console.validate_manifest_numeric_arguments(
                env_record,
                contract_address=contract_address,
                entrypoint_name=entrypoint,
                payload=body.get("payload"),
            )
        except ValueError as exc:
            contract_console.json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {"ok": False, "error": str(exc)},
            )
            return

        request_payload: dict[str, Any] = {
            "authority": authority,
            "contract_address": contract_address,
            "entrypoint": entrypoint,
        }
        if "payload" in body and body["payload"] is not None:
            request_payload["payload"] = body["payload"]

        mode = "view"
        if parsed.path == "/api/call":
            try:
                self.require_mutations_allowed(env_record)
            except PermissionError as exc:
                contract_console.json_response(self, HTTPStatus.FORBIDDEN, {"ok": False, "error": str(exc)})
                return
            request_payload["fee_payment"] = contract_console.authority_fee_payment_intent(gas_limit)
            try:
                payload = contract_console.execute_detached_contract_call(
                    self.execute_upstream_request,
                    environment=environment,
                    signer=signer,
                    torii_url=torii_url,
                    request_payload=request_payload,
                    timeout=45,
                )
            except ConnectionError as exc:
                contract_console.json_response(
                    self, HTTPStatus.BAD_GATEWAY, {"ok": False, "error": str(exc)}
                )
                return
            contract_console.json_response(
                self,
                HTTPStatus.OK if payload.get("ok") else HTTPStatus.BAD_GATEWAY,
                payload,
            )
            return

        request_payload["gas_limit"] = gas_limit

        try:
            payload = self.execute_upstream_request(
                environment=environment,
                signer=signer,
                torii_url=torii_url,
                mode=mode,
                path="/v1/contracts/view",
                request_payload=request_payload,
                timeout=45 if mode == "call" else 30,
            )
        except ConnectionError as exc:
            contract_console.json_response(self, HTTPStatus.BAD_GATEWAY, {"ok": False, "error": str(exc)})
            return

        contract_console.json_response(self, HTTPStatus.OK, payload)


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Serve the SoraSwap trader cockpit.")
    parser.add_argument("--host", default="127.0.0.1", help="Bind host. Default: 127.0.0.1")
    parser.add_argument("--port", type=contract_console.parse_tcp_port_arg, default=4274, help="Bind port. Default: 4274")
    parser.add_argument(
        "--signer",
        action="append",
        default=[],
        metavar="ENV=PATH",
        help="Bind a signer config to an environment for signed router swaps.",
    )
    parser.add_argument(
        "--authority",
        action="append",
        default=[],
        metavar="ENV=I105...",
        help="Set a default authority for an environment.",
    )
    parser.add_argument(
        "--no-auto-signers",
        action="store_true",
        help="Disable auto-discovery of default signer configs.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_argument_parser()
    args = parser.parse_args(argv)

    try:
        signer_assignments = contract_console.parse_assignment(args.signer, "--signer")
        authority_assignments = contract_console.parse_assignment(args.authority, "--authority")
    except ValueError as exc:
        parser.error(str(exc))
        return 2

    signers = contract_console.build_signer_bindings(
        REPO_ROOT,
        signer_assignments,
        authority_assignments,
        auto_discover=not args.no_auto_signers,
    )
    state = TraderUiState(REPO_ROOT, signers)
    evidence_issues = contract_console.mutation_enabled_public_deployment_evidence_issues(
        state.contract_console_state
    )
    if evidence_issues:
        print(
            "refusing to start mutation-enabled public trader cockpit with stale deployment evidence:",
            file=sys.stderr,
        )
        for issue in evidence_issues:
            print(f"  - {issue}", file=sys.stderr)
        print(
            "Unset the public mutation consent flag for read-only use, or refresh the public evidence.",
            file=sys.stderr,
        )
        return 1

    server = FastThreadingHTTPServer((args.host, args.port), TraderUiHandler)
    server.state = state  # type: ignore[attr-defined]

    print(f"SoraSwap trader cockpit listening on http://{args.host}:{args.port}")
    for environment in state.list_environments():
        env_record = state.load_environment(environment)
        signer = env_record["signer"]
        preferred_contract = env_record.get("preferred_contract")
        print(
            f"  - {environment}: router={'yes' if preferred_contract else 'no'}, "
            f"torii={env_record.get('torii_url') or 'unconfigured'}, "
            f"signer={'yes' if signer.get('configured') else 'no'} "
            f"({signer.get('source', 'none')}), "
            f"call-enabled={'yes' if signer.get('call_enabled') else 'no'}"
        )
        for warning in signer.get("warnings") or []:
            print(f"      warning: {warning}")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopping trader cockpit")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
