#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import base64
import json
import os
import signal
import sys
import tempfile
import threading
import urllib.parse
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent.parent
MODULE_PATH = REPO_ROOT / "scripts" / "serve_contract_console.py"
MODULE_NAME = "soraswap_contract_console_fixture_server"

spec = importlib.util.spec_from_file_location(MODULE_NAME, MODULE_PATH)
contract_console = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[MODULE_NAME] = contract_console
spec.loader.exec_module(contract_console)


BRIDGE_ADDRESS = "tairac1fixturebridge00000000000000000000000000000000000"
FIXTURE_GENERATED_AT = "20260407T000000Z"
BRIDGE_CODE_HASH = "1" * 64
BRIDGE_ABI_HASH = "2" * 64
BRIDGE_DEPLOY_NONCE = 1
BRIDGE_TEST_PRIVATE_KEY = "8026209d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
BRIDGE_TEST_PUBLIC_KEY = "ed0120d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"


def json_response(handler: BaseHTTPRequestHandler, status: int, payload: dict[str, Any]) -> None:
    body = json.dumps(payload).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def build_fixture_repo(root: Path, torii_url: str) -> None:
    (root / "ui").mkdir(parents=True, exist_ok=True)
    os.symlink(REPO_ROOT / "ui" / "contract_console", root / "ui" / "contract_console", target_is_directory=True)

    bridge_source = root / "contracts" / "bridge" / "sccp_bridge.ko"
    bridge_source.parent.mkdir(parents=True, exist_ok=True)
    bridge_source.write_text("// fixture bridge contract\n", encoding="utf-8")

    environment_root = root / "deployments" / "fixture"
    chain_fingerprint = {
        "generated_at": FIXTURE_GENERATED_AT,
        "environment": "fixture",
        "torii_url": torii_url,
        "chain": "fixture-chain",
        "block_1_hash": "fixture-block-1",
    }
    write_json(
        environment_root / "chain.latest.json",
        chain_fingerprint,
    )
    write_json(
        environment_root / "contracts.latest.json",
        {
            "generated_at": FIXTURE_GENERATED_AT,
            "status": "completed",
            "environment": "fixture",
            "chain_fingerprint": chain_fingerprint,
            "contracts": [
                {
                    "contract_key": "bridge.sccp_bridge",
                    "environment": "fixture",
                    "contract_source": "contracts/bridge/sccp_bridge.ko",
                    "dataspace": "universal",
                    "contract_address": BRIDGE_ADDRESS,
                    "deploy_nonce": BRIDGE_DEPLOY_NONCE,
                    "code_hash_hex": BRIDGE_CODE_HASH,
                    "abi_hash_hex": BRIDGE_ABI_HASH,
                    "instance": {
                        "verification": "transaction_and_manifest",
                        "tx_hash_hex": "11" * 32,
                        "contract_address": BRIDGE_ADDRESS,
                        "deploy_nonce": BRIDGE_DEPLOY_NONCE,
                        "code_hash_hex": BRIDGE_CODE_HASH,
                        "abi_hash_hex": BRIDGE_ABI_HASH,
                    },
                }
            ],
        },
    )
    write_json(
        environment_root / "bridge.sccp_bridge.manifest.json",
        {
            "generated_at": FIXTURE_GENERATED_AT,
            "environment": "fixture",
            "contract_key": "bridge.sccp_bridge",
            "code_hash": "hash:" + BRIDGE_CODE_HASH,
            "abi_hash": "hash:" + BRIDGE_ABI_HASH,
            "entrypoints": [
                {"name": "listing_config", "kind": {"kind": "View"}, "params": [], "return_type": "tuple"},
                {"name": "mirror_asset", "kind": {"kind": "View"}, "params": [{"name": "asset_key", "type_name": "String"}], "return_type": "tuple"},
                {"name": "asset_config", "kind": {"kind": "View"}, "params": [{"name": "asset_key", "type_name": "String"}], "return_type": "tuple"},
                {"name": "mirror_route", "kind": {"kind": "View"}, "params": [{"name": "route", "type_name": "String"}], "return_type": "tuple"},
                {"name": "route_config", "kind": {"kind": "View"}, "params": [{"name": "route", "type_name": "String"}], "return_type": "tuple"},
                {"name": "mirror_outbound", "kind": {"kind": "View"}, "params": [{"name": "transfer", "type_name": "String"}], "return_type": "tuple"},
                {"name": "outbound_config", "kind": {"kind": "View"}, "params": [{"name": "transfer", "type_name": "String"}], "return_type": "tuple"},
                {"name": "inbound_consumed", "kind": {"kind": "View"}, "params": [{"name": "message_id", "type_name": "String"}], "return_type": "int"},
                {
                    "name": "lock_to_remote",
                    "kind": {"kind": "Public"},
                    "params": [
                        {"name": "route", "type_name": "String"},
                        {"name": "transfer", "type_name": "String"},
                        {"name": "sender", "type_name": "AccountId"},
                        {"name": "recipient", "type_name": "String"},
                        {"name": "amount", "type_name": "u64"},
                    ],
                    "return_type": "int",
                    "permission": "Operator",
                },
                {
                    "name": "finalize_inbound",
                    "kind": {"kind": "Public"},
                    "params": [
                        {"name": "route", "type_name": "String"},
                        {"name": "message_id", "type_name": "String"},
                        {"name": "recipient", "type_name": "String"},
                        {"name": "amount", "type_name": "u64"},
                    ],
                    "return_type": "int",
                    "permission": "Operator",
                },
            ]
        },
    )


class MockToriiState:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.submission_counter = 0
        self.history_items: list[dict[str, Any]] = [
            {"hash": "aa" * 32, "status": "Committed", "kind": "seeded"},
        ]
        self.status_by_hash: dict[str, dict[str, Any]] = {
            "aa" * 32: {"status": {"kind": "Committed"}, "summary": "Committed", "diagnostics": []},
        }

    def register_submission(self, kind: str, request: dict[str, Any], *, terminal: bool = True) -> str:
        with self.lock:
            self.submission_counter += 1
            tx_hash_hex = f"{self.submission_counter:064x}"
            self.history_items.insert(0, {
                "hash": tx_hash_hex,
                "status": "Committed" if terminal else "Queued",
                "kind": kind,
                "entrypoint": request.get("entrypoint"),
            })
            self.history_items = self.history_items[:10]
            if terminal:
                self.status_by_hash[tx_hash_hex] = {
                    "status": {
                        "kind": "Committed",
                    },
                    "summary": "Committed",
                    "diagnostics": [],
                }
            else:
                self.status_by_hash[tx_hash_hex] = {
                    "status": {
                        "kind": "Queued",
                    },
                    "summary": "Queued",
                    "diagnostics": [],
                }
            return tx_hash_hex


class MockToriiHandler(BaseHTTPRequestHandler):
    server_version = "MockTorii/0.1"

    @property
    def state(self) -> MockToriiState:
        return self.server.state  # type: ignore[attr-defined]

    def log_message(self, format: str, *args: object) -> None:
        return

    def parse_json_body(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length > 0 else b"{}"
        return json.loads(raw.decode("utf-8") or "{}")

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(parsed.query, keep_blank_values=False)
        if parsed.path == "/v1/sccp/capabilities":
            json_response(
                self,
                HTTPStatus.OK,
                {
                    "version": 1,
                    "registry_revision": "0x" + ("11" * 32),
                    "registry_path": "/v1/sccp/registry",
                    "message_bundle_path": "/v1/sccp/proofs/message/{message_id}",
                    "proof_request_path": "/v1/sccp/proof-requests/{message_id}",
                    "recent_messages_path": "/v1/sccp/messages/recent",
                    "registry_limits": {
                        "max_governed_lanes": 16,
                        "max_live_governed_routes": 64,
                        "max_live_routes_per_lane": 8,
                        "max_retained_routes_per_lane": 64,
                        "max_retained_native_trust_anchors_per_lane": 4096,
                    },
                    "resource_limits": {
                        "max_proofs_per_transaction": 1,
                        "max_proofs_per_block": 4,
                    },
                    "proof_submit_path": "/v1/bridge/proofs/submit",
                    "native_message_submit_path": "/v1/bridge/messages",
                },
            )
            return
        if parsed.path == "/v1/sccp/registry":
            json_response(
                self,
                HTTPStatus.OK,
                {
                    "version": 1,
                    "lanes": [
                        {
                            "lane_id": {"source": "ethereum_sepolia", "target": "sora_taira"},
                            "native_trust_anchors": [],
                            "current_native_trust_anchor_hash": None,
                            "routes": [{
                                "lane_id": {"source": "ethereum_sepolia", "target": "sora_taira"},
                                "route_id": "fixture_lane",
                                "asset_key": "xor",
                                "revision": 1,
                                "activation": "bidirectional",
                            }],
                        }
                    ]
                },
            )
            return
        if parsed.path == "/v1/sccp/messages/recent":
            message_id = "67" * 32
            json_response(
                self,
                HTTPStatus.OK,
                {
                    "items": [{
                        "height": 42,
                        "message_id_hex": message_id,
                        "kind": "transfer",
                        "source_profile": "sora-taira",
                        "target_profile": "ethereum-sepolia",
                        "destination_binding_hash": "0x" + ("56" * 32),
                        "route_configuration_hash": "0x" + ("34" * 32),
                        "target_domain": 2,
                        "asset_id": "xor",
                        "route_id": "fixture_lane",
                        "amount": "10",
                        "payload_projection": {"Transfer": {
                            "version": 1,
                            "source_domain": 0,
                            "dest_domain": 2,
                            "nonce": 7,
                            "route_revision": 1,
                            "asset_home_domain": 0,
                            "asset_id": {"CanonicalText": {"value": "xor"}},
                            "amount": 10,
                            "sender": {"CanonicalText": {"value": "fixture"}},
                            "recipient": {"EvmAddress20": {"bytes": [17] * 20}},
                            "route_id": {"CanonicalText": {"value": "fixture_lane"}},
                        }},
                        "links": {
                            "bundle_path": f"/v1/sccp/proofs/message/{message_id}",
                            "proof_request_path": f"/v1/sccp/proof-requests/{message_id}",
                        },
                    }]
                },
            )
            return
        if parsed.path.startswith("/v1/sccp/proofs/message/"):
            message_id = parsed.path.removeprefix("/v1/sccp/proofs/message/")
            json_response(
                self,
                HTTPStatus.OK,
                {
                    "version": 1,
                    "commitment_root": "01" * 32,
                    "commitment": {
                        "version": 1,
                        "kind": "Transfer",
                        "target_domain": 1,
                        "message_id": message_id,
                        "payload_hash": "02" * 32,
                        "parliament_certificate_hash": None,
                    },
                    "merkle_proof": {"steps": []},
                    "payload": {
                        "Transfer": {
                            "version": 1,
                            "source_domain": 0,
                            "dest_domain": 1,
                            "nonce": 7,
                            "asset_home_domain": 0,
                            "asset_id_codec": 1,
                            "asset_id": "xor#universal",
                            "amount": 10,
                            "sender_codec": 1,
                            "sender": "nexus:soraswap",
                            "recipient_codec": 2,
                            "recipient": "0x1111111111111111111111111111111111111111",
                            "route_id_codec": 1,
                            "route_id": "fixture_lane",
                        }
                    },
                    "finality_proof": "0xfeed",
                },
            )
            return
        if parsed.path.startswith("/v1/sccp/proof-requests/"):
            json_response(
                self,
                HTTPStatus.OK,
                {
                    "version": 1,
                    "backend": "ethereum_groth16_bn254",
                    "source_network": "sora_taira",
                    "target_network": "ethereum_sepolia",
                    "verifier_key_hash": "03" * 32,
                    "statement_hash": "04" * 32,
                    "request_hash": "05" * 32,
                },
            )
            return
        if parsed.path == "/v1/pipeline/transactions/status":
            tx_hash_hex = str((query.get("hash") or [""])[0])
            requested_scope = str((query.get("scope") or ["auto"])[0])
            scope = "global" if requested_scope == "auto" else requested_scope
            payload = dict(self.state.status_by_hash.get(
                tx_hash_hex,
                {"status": {"kind": "Committed"}, "summary": "Committed", "diagnostics": []},
            ))
            payload.update({"hash": tx_hash_hex, "scope": scope, "resolved_from": "state"})
            json_response(self, HTTPStatus.OK, payload)
            return
        if parsed.path == "/v1/transactions/history":
            json_response(self, HTTPStatus.OK, {"items": list(self.state.history_items)})
            return

        json_response(self, HTTPStatus.NOT_FOUND, {"code": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        request = self.parse_json_body()
        if parsed.path == "/v1/contracts/view":
            entrypoint = request.get("entrypoint")
            payload = request.get("payload") or {}
            response_map = {
                "listing_config": {"listing_mode": "fixture"},
                "mirror_asset": {"asset_key": payload.get("asset_key"), "home_domain": 0},
                "asset_config": {"registered": True},
                "mirror_route": [payload.get("route"), 1000],
                "route_config": {"route": payload.get("route"), "enabled": True},
                "mirror_outbound": {"transfer": payload.get("transfer"), "status": "prepared"},
                "outbound_config": {"transfer": payload.get("transfer"), "finality_model": "safe_block_depth"},
                "inbound_consumed": 0,
            }
            json_response(self, HTTPStatus.OK, response_map.get(str(entrypoint), {"entrypoint": entrypoint}))
            return
        if parsed.path == "/v1/contracts/call":
            payload = request.get("payload") if isinstance(request, dict) else {}
            terminal = not (isinstance(payload, dict) and payload.get("route") == "timeout_route")
            tx_hash_hex = self.state.register_submission("contract_call", request, terminal=terminal)
            json_response(self, HTTPStatus.OK, {"submitted": True, "tx_hash_hex": tx_hash_hex})
            return
        if parsed.path in {"/v1/bridge/proofs/submit", "/v1/bridge/messages"}:
            proof_field = (
                "destination_proof_b64"
                if parsed.path == "/v1/bridge/proofs/submit"
                else "native_proof_b64"
            )
            preparation_keys = {"authority", proof_field}
            submission_keys = preparation_keys | {
                "transaction_payload_b64",
                "signature_b64",
                "creation_time_ms",
            }
            request_keys = frozenset(request)
            if request_keys not in {frozenset(preparation_keys), frozenset(submission_keys)}:
                json_response(self, HTTPStatus.BAD_REQUEST, {"code": "closed_dto_violation"})
                return
            transaction = json.dumps(
                {
                    "path": parsed.path,
                    "authority": request["authority"],
                    proof_field: request[proof_field],
                },
                separators=(",", ":"),
                sort_keys=True,
            ).encode("utf-8")
            transaction_payload_b64 = base64.b64encode(transaction).decode("ascii")
            signing_message_b64 = base64.b64encode(
                contract_console.iroha_transaction_signing_message(transaction)
            ).decode("ascii")
            creation_time_ms = 1_750_000_000_001
            response_metadata = {
                "payload_kind": "transfer",
                "message_id_hex": "12" * 32,
                "backend": (
                    "bridge/sccp/groth16-bn254-v1"
                    if proof_field == "destination_proof_b64"
                    else "bridge/sccp/native/ethereum-pos-v1"
                ),
                "counterparty_domain": 2,
                "counterparty_chain": "ethereum-sepolia",
                "route_configuration_hash_hex": "34" * 32,
                "range_start_height": 91,
                "range_end_height": 91,
                "creation_time_ms": creation_time_ms,
            }
            if request_keys == frozenset(preparation_keys):
                json_response(
                    self,
                    HTTPStatus.OK,
                    {
                        **response_metadata,
                        "submitted": False,
                        "tx_hash_hex": None,
                        "transaction_payload_b64": transaction_payload_b64,
                        "signing_message_b64": signing_message_b64,
                    },
                )
                return
            try:
                signature = contract_console.decode_canonical_base64(
                    request["signature_b64"],
                    "signature_b64",
                    maximum=64,
                )
            except ValueError:
                json_response(self, HTTPStatus.BAD_REQUEST, {"code": "invalid_signature"})
                return
            if (
                request["transaction_payload_b64"] != transaction_payload_b64
                or request["creation_time_ms"] != creation_time_ms
                or len(signature) != 64
            ):
                json_response(self, HTTPStatus.BAD_REQUEST, {"code": "detached_payload_mismatch"})
                return
            kind = "bridge_proof_submit" if proof_field == "destination_proof_b64" else "bridge_message_submit"
            tx_hash_hex = self.state.register_submission(kind, request)
            json_response(
                self,
                HTTPStatus.OK,
                {
                    **response_metadata,
                    "submitted": True,
                    "tx_hash_hex": tx_hash_hex,
                    "transaction_payload_b64": None,
                    "signing_message_b64": None,
                },
            )
            return

        json_response(self, HTTPStatus.NOT_FOUND, {"code": "not_found"})


def start_server(server: ThreadingHTTPServer) -> threading.Thread:
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return thread


def main() -> int:
    tempdir = tempfile.TemporaryDirectory(prefix="soraswap-console-fixture-")
    fixture_root = Path(tempdir.name)

    upstream_state = MockToriiState()
    upstream_server = ThreadingHTTPServer(("127.0.0.1", 0), MockToriiHandler)
    upstream_server.state = upstream_state  # type: ignore[attr-defined]
    upstream_thread = start_server(upstream_server)
    upstream_host, upstream_port = upstream_server.server_address
    upstream_url = f"http://{upstream_host}:{upstream_port}"

    build_fixture_repo(fixture_root, upstream_url)

    signer = contract_console.SignerBinding(
        environment="fixture",
        config_path=fixture_root / "config" / "fixture.client.toml",
        authority="i105fixtureoperator@universal",
        torii_url=upstream_url,
        private_key=BRIDGE_TEST_PRIVATE_KEY,
        public_key=BRIDGE_TEST_PUBLIC_KEY,
        basic_auth=None,
        warnings=[],
        source="explicit",
    )
    state = contract_console.ContractConsoleState(fixture_root, {"fixture": signer})
    app_server = ThreadingHTTPServer(("127.0.0.1", 0), contract_console.ContractConsoleHandler)
    app_server.state = state  # type: ignore[attr-defined]
    app_thread = start_server(app_server)
    app_host, app_port = app_server.server_address
    app_url = f"http://{app_host}:{app_port}"

    stop_event = threading.Event()

    def handle_signal(signum, frame) -> None:  # noqa: ARG001
        stop_event.set()

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    print(json.dumps({"url": app_url, "upstream_url": upstream_url}), flush=True)

    try:
        while not stop_event.wait(0.25):
            pass
    finally:
        app_server.shutdown()
        upstream_server.shutdown()
        app_server.server_close()
        upstream_server.server_close()
        app_thread.join(timeout=5)
        upstream_thread.join(timeout=5)
        tempdir.cleanup()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
