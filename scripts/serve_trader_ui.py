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
            "repo_root": str(self.repo_root),
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
        sys.stderr.write(f"[trader-ui] {self.address_string()} - {fmt % args}\n")

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
            )
        except OSError as exc:
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
        query_params = urllib.parse.parse_qs(parsed.query, keep_blank_values=False)
        environment = str((query_params.pop("environment", [""])[0]) or "").strip()

        try:
            _, signer, torii_url = self.resolve_proxy_environment(environment)
        except KeyError as exc:
            contract_console.json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": str(exc)})
            return
        except ValueError as exc:
            contract_console.json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return

        request_query = contract_console.query_dict_from_pairs(query_params)
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
        query_params = urllib.parse.parse_qs(parsed.query, keep_blank_values=False)
        environment = str((query_params.pop("environment", [""])[0]) or "").strip()

        try:
            _, signer, torii_url = self.resolve_proxy_environment(environment)
        except KeyError as exc:
            contract_console.json_response(self, HTTPStatus.NOT_FOUND, {"ok": False, "error": str(exc)})
            return
        except ValueError as exc:
            contract_console.json_response(self, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return

        upstream_query = urllib.parse.urlencode(
            [(key, value) for key, values in query_params.items() for value in values],
            doseq=True,
        )
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
            body = exc.read().decode("utf-8", errors="replace")
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
            self.end_headers()

            while True:
                line = upstream.readline()
                if not line:
                    break
                self.wfile.write(line)
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            return
        finally:
            upstream.close()

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
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/catalog":
            contract_console.json_response(self, HTTPStatus.OK, self.state.load_catalog())
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
            self.handle_torii_read_proxy(parsed, "/v1/pipeline/transactions/status")
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

        environment = str(body.get("environment") or "").strip()
        if parsed.path == "/api/view/batch":
            try:
                _, signer, torii_url = self.resolve_proxy_environment(environment)
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

            request_payload: dict[str, Any] = {
                "authority": authority,
                "items": items,
            }
            if "gas_limit" in body and body["gas_limit"] not in (None, ""):
                try:
                    request_payload["gas_limit"] = int(body["gas_limit"])
                except (TypeError, ValueError):
                    contract_console.json_response(
                        self,
                        HTTPStatus.BAD_REQUEST,
                        {"ok": False, "error": "gas_limit must be an integer"},
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

        gas_limit = body.get("gas_limit")
        if gas_limit in (None, ""):
            gas_limit = DEFAULT_GAS_LIMIT
        try:
            gas_limit = int(gas_limit)
        except (TypeError, ValueError):
            contract_console.json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {"ok": False, "error": "gas_limit must be an integer"},
            )
            return

        request_payload: dict[str, Any] = {
            "authority": authority,
            "contract_address": contract_address,
            "entrypoint": entrypoint,
            "gas_limit": gas_limit,
        }
        if "payload" in body and body["payload"] is not None:
            request_payload["payload"] = body["payload"]

        mode = "view"
        path = "/v1/contracts/view"
        if parsed.path == "/api/call":
            try:
                self.require_mutations_allowed(env_record)
            except PermissionError as exc:
                contract_console.json_response(self, HTTPStatus.FORBIDDEN, {"ok": False, "error": str(exc)})
                return
            if not signer.private_key:
                contract_console.json_response(
                    self,
                    HTTPStatus.BAD_REQUEST,
                    {
                        "ok": False,
                        "error": (
                            f"no signer config with private key is bound for environment {environment}; "
                            "start the trader with --signer ENV=/path/to/client.toml"
                        ),
                    },
                )
                return
            request_payload["private_key"] = signer.private_key
            mode = "call"
            path = "/v1/contracts/call"

        try:
            payload = self.execute_upstream_request(
                environment=environment,
                signer=signer,
                torii_url=torii_url,
                mode=mode,
                path=path,
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
    parser.add_argument("--port", type=int, default=4274, help="Bind port. Default: 4274")
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
