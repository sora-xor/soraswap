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
FIXTURE_NETWORK_ID = "hash:82531CE8EAE8BFF6BEECA4698BFD13A3BC8BEC5F0EE0D23D428C97FC17AB0F3B#3E94"
XOR_ASSET_DEFINITION_ID = "6TEAJqbb8oEPmLncoNiMRbLEK6tw"


def canonical_hash_literal(raw_hash: str) -> str:
    body = raw_hash.upper()
    return f"hash:{body}#{contract_console.iroha_literal_crc16('hash', body):04X}"


def current_deploy_response(torii_url: str) -> dict[str, Any]:
    commit_hash_hex = "a" * 64
    commit_hash = canonical_hash_literal(commit_hash_hex)
    authority = "0x02000120" + "b" * 64
    contract_alias = "sccp_bridge::bridge.universal"
    deployment_state: dict[str, Any] = {
        "authority": authority,
        "contract_alias": contract_alias,
        "deploy_nonce": str(BRIDGE_DEPLOY_NONCE),
        "dataspace_alias": "universal",
        "dataspace_id": "0",
        "previous_contract_address": None,
        "observed_block_height": "1",
        "observed_block_hash": "f" * 64,
        "ledger_time_ms": "1000",
        "chain_discriminant": "0",
    }
    fee_quotes: list[Any] = []
    operation_receipt = {
        "operation_kind": "contract_deploy",
        "status": "committed",
        "transport": "ivm-contract-deploy-helper",
        "torii_url": torii_url,
        "chain_id": "fixture-chain",
        "authority": authority,
        "chain_discriminant": 0,
        "dataspace": "0",
        "contract_alias": contract_alias,
        "contract_address": BRIDGE_ADDRESS,
        "contract_subject_account": BRIDGE_ADDRESS,
        "code_hash_hex": BRIDGE_CODE_HASH,
        "abi_hash_hex": None,
        "tx_hash_hex": commit_hash_hex,
        "entrypoint": None,
        "entrypoint_hash_hex": None,
        "gas_limit": None,
        "gas_used": None,
        "fee_payment": {},
        "fee_quotes": fee_quotes,
        "payload_digest_hex": "e" * 64,
        "deployment_state": deployment_state,
    }
    return {
        "authority": authority,
        "chain_discriminant": 0,
        "chain_id": "fixture-chain",
        "code_hash_hex": BRIDGE_CODE_HASH,
        "commit_deployment_tx_hash": commit_hash,
        "contract_address": BRIDGE_ADDRESS,
        "contract_alias": contract_alias,
        "contract_subject_account": BRIDGE_ADDRESS,
        "dataspace": "0",
        "deploy_nonce": BRIDGE_DEPLOY_NONCE,
        "deployment_state": deployment_state,
        "expected_previous_contract_address": None,
        "fee_quotes": fee_quotes,
        "final": {"kind": "Committed", "hash": commit_hash},
        "next_deploy_nonce": BRIDGE_DEPLOY_NONCE + 1,
        "ok": True,
        "operation_receipt": operation_receipt,
        "register_bytes_chunk_count": 1,
        "register_bytes_chunk_size": 65_536,
        "register_bytes_stage_tx_hashes": [],
        "register_bytes_tx_hash": "c" * 64,
        "register_bytes_tx_strategy": "native_chunks",
        "register_manifest_tx_hash": canonical_hash_literal("d" * 64),
        "submitted": True,
        "terminal_kind": "Committed",
        "torii_url": torii_url,
    }


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
        "torii_url": torii_url,
        "chain": "fixture-chain",
        "block_1_hash": "fixture-block-1",
    }
    chain_latest = {
        "generated_at": FIXTURE_GENERATED_AT,
        "environment": "fixture",
        **chain_fingerprint,
    }
    write_json(
        environment_root / "chain.latest.json",
        chain_latest,
    )
    deployment_record = {
        "contract_key": "bridge.sccp_bridge",
        "generated_at": FIXTURE_GENERATED_AT,
        "environment": "fixture",
        "contract_source": "contracts/bridge/sccp_bridge.ko",
        "contract_alias": "sccp_bridge::bridge.universal",
        "dataspace_alias": "universal",
        "dataspace_id": "0",
        "contract_address": BRIDGE_ADDRESS,
        "deploy_nonce": BRIDGE_DEPLOY_NONCE,
        "code_hash_hex": BRIDGE_CODE_HASH,
        "abi_hash_hex": BRIDGE_ABI_HASH,
        "deploy_strategy": "ivm_contract_deploy",
        "chain_fingerprint": chain_fingerprint,
        "response": current_deploy_response(torii_url),
    }
    write_json(environment_root / "bridge.sccp_bridge.deploy.json", deployment_record)
    write_json(
        environment_root / "contracts.latest.json",
        {
            "generated_at": FIXTURE_GENERATED_AT,
            "status": "completed",
            "environment": "fixture",
            "chain_fingerprint": chain_fingerprint,
            "contracts": [deployment_record],
        },
    )
    write_json(
        environment_root / "bridge.sccp_bridge.manifest.json",
        {
            "generated_at": FIXTURE_GENERATED_AT,
            "environment": "fixture",
            "contract_key": "bridge.sccp_bridge",
            "code_hash": canonical_hash_literal(BRIDGE_CODE_HASH),
            "abi_hash": canonical_hash_literal(BRIDGE_ABI_HASH),
            "entrypoints": [
                {"name": "listing_config", "kind": {"kind": "View"}, "params": [], "return_type": "tuple"},
                {"name": "mirror_asset", "kind": {"kind": "View"}, "params": [{"name": "asset_key", "type_name": "Name"}], "return_type": "tuple"},
                {"name": "asset_config", "kind": {"kind": "View"}, "params": [{"name": "asset_key", "type_name": "Name"}], "return_type": "tuple"},
                {"name": "mirror_route", "kind": {"kind": "View"}, "params": [{"name": "route", "type_name": "Name"}], "return_type": "tuple"},
                {"name": "route_config", "kind": {"kind": "View"}, "params": [{"name": "route", "type_name": "Name"}], "return_type": "tuple"},
                {"name": "mirror_outbound", "kind": {"kind": "View"}, "params": [{"name": "transfer", "type_name": "Name"}], "return_type": "tuple"},
                {"name": "outbound_config", "kind": {"kind": "View"}, "params": [{"name": "transfer", "type_name": "Name"}], "return_type": "tuple"},
                {"name": "inbound_consumed", "kind": {"kind": "View"}, "params": [{"name": "message_id", "type_name": "Name"}], "return_type": "int"},
                {
                    "name": "lock_to_remote",
                    "kind": {"kind": "Kotoage"},
                    "params": [
                        {"name": "route", "type_name": "Name"},
                        {"name": "transfer", "type_name": "Name"},
                        {"name": "recipient", "type_name": "Name"},
                        {"name": "amount", "type_name": "quantity"},
                    ],
                    "return_type": "int",
                    "permission": "AssetOps",
                },
                {
                    "name": "finalize_inbound",
                    "kind": {"kind": "Kotoage"},
                    "params": [
                        {"name": "route", "type_name": "Name"},
                        {"name": "message_id", "type_name": "Name"},
                        {"name": "recipient", "type_name": "AccountId"},
                        {"name": "amount", "type_name": "quantity"},
                    ],
                    "return_type": "int",
                    "permission": "AssetOps",
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
            "aa" * 32: {"status": {"kind": "Committed"}},
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
                    "status": {"kind": "Committed"},
                }
            else:
                self.status_by_hash[tx_hash_hex] = {
                    "status": {"kind": "Queued"},
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
        self.raw_request_body = raw
        return json.loads(raw.decode("utf-8") or "{}")

    def has_valid_canonical_account_auth(self) -> bool:
        values: dict[str, str] = {}
        for header in contract_console.CANONICAL_ACCOUNT_AUTH_HEADERS:
            entries = self.headers.get_all(header) or []
            if len(entries) != 1:
                return False
            values[header] = entries[0]
        if values["X-Iroha-Account"] != contract_console.canonical_ed25519_account_header(
            BRIDGE_TEST_PUBLIC_KEY
        ):
            return False
        timestamp_raw = values["X-Iroha-Timestamp-Ms"]
        try:
            timestamp_ms = int(timestamp_raw)
        except ValueError:
            return False
        if str(timestamp_ms) != timestamp_raw:
            return False
        try:
            message = contract_console.canonical_account_request_message(
                FIXTURE_NETWORK_ID,
                self.command,
                f"http://fixture{self.path}",
                self.raw_request_body,
                timestamp_ms,
                values["X-Iroha-Nonce"],
            )
            return contract_console.verify_ed25519_signature_b64(
                BRIDGE_TEST_PUBLIC_KEY,
                message,
                values["X-Iroha-Signature"],
            )
        except ValueError:
            return False

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(parsed.query, keep_blank_values=False)
        if parsed.path.startswith("/v1/assets/definitions/"):
            selector = urllib.parse.unquote(parsed.path.removeprefix("/v1/assets/definitions/"))
            if selector == "xor#universal":
                json_response(
                    self,
                    HTTPStatus.OK,
                    {
                        "id": XOR_ASSET_DEFINITION_ID,
                        "alias": selector,
                        "spec": {"scale": 9},
                        "alias_binding": {
                            "alias": selector,
                            "status": "permanent",
                            "bound_at_ms": 1,
                        },
                    },
                )
                return
            json_response(self, HTTPStatus.NOT_FOUND, {"code": "not_found"})
            return
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
            scope = str((query.get("scope") or ["global"])[0])
            payload = dict(self.state.status_by_hash.get(
                tx_hash_hex,
                {"status": {"kind": "Committed"}},
            ))
            resolved_from = "queue" if payload["status"]["kind"] == "Queued" else "state"
            payload.update({"hash": tx_hash_hex, "scope": scope, "resolved_from": resolved_from})
            json_response(self, HTTPStatus.OK, payload)
            return
        if parsed.path == "/v1/transactions/history":
            json_response(self, HTTPStatus.OK, {"items": list(self.state.history_items)})
            return

        json_response(self, HTTPStatus.NOT_FOUND, {"code": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        request = self.parse_json_body()
        if parsed.path in contract_console.CANONICAL_ACCOUNT_AUTH_PATHS and not self.has_valid_canonical_account_auth():
            json_response(self, HTTPStatus.UNAUTHORIZED, {"code": "canonical_authentication_required"})
            return
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
            preparation_keys = {
                "authority",
                "contract_address",
                "entrypoint",
                "fee_payment",
            }
            if "payload" in request:
                preparation_keys.add("payload")
            submission_keys = preparation_keys | {
                "public_key_hex",
                "signature_b64",
                "creation_time_ms",
            }
            request_keys = frozenset(request)
            if request_keys not in {
                frozenset(preparation_keys),
                frozenset(submission_keys),
            }:
                json_response(self, HTTPStatus.BAD_REQUEST, {"code": "closed_dto_violation"})
                return

            creation_time_ms = 1_750_000_000_002
            prepared_request = {key: request[key] for key in preparation_keys}
            transaction = json.dumps(
                {
                    "creation_time_ms": creation_time_ms,
                    "request": prepared_request,
                },
                separators=(",", ":"),
                sort_keys=True,
            ).encode("utf-8")
            transaction_payload_b64 = base64.b64encode(transaction).decode("ascii")
            signing_message = contract_console.iroha_transaction_signing_message(transaction)
            signing_message_b64 = base64.b64encode(signing_message).decode("ascii")
            fee_payment = request.get("fee_payment")
            try:
                gas_limit = fee_payment["value"]["gas_limit"]
            except (KeyError, TypeError):
                json_response(self, HTTPStatus.BAD_REQUEST, {"code": "invalid_fee_payment"})
                return

            submitted = request_keys == frozenset(submission_keys)
            tx_hash_hex: str | None = None
            entrypoint_hash_hex: str | None = None
            if submitted:
                if (
                    request.get("creation_time_ms") != creation_time_ms
                    or request.get("public_key_hex")
                    != contract_console.raw_ed25519_public_key_hex(BRIDGE_TEST_PUBLIC_KEY)
                    or not contract_console.verify_ed25519_signature_b64(
                        BRIDGE_TEST_PUBLIC_KEY,
                        signing_message,
                        request.get("signature_b64"),
                    )
                ):
                    json_response(self, HTTPStatus.BAD_REQUEST, {"code": "detached_payload_mismatch"})
                    return
                payload = request.get("payload") if isinstance(request, dict) else {}
                terminal = not (
                    isinstance(payload, dict) and payload.get("route") == "timeout_route"
                )
                tx_hash_hex = self.state.register_submission(
                    "contract_call",
                    request,
                    terminal=terminal,
                )
                entrypoint_hash_hex = "cd" * 32

            operation_receipt = {
                "operation_kind": "contract_call",
                "status": "submitted" if submitted else "pending_signature",
                "transport": "torii",
                "dataspace": "0",
                "contract_alias": "sccp_bridge::bridge.universal",
                "contract_address": request["contract_address"],
                "code_hash_hex": BRIDGE_CODE_HASH,
                "abi_hash_hex": BRIDGE_ABI_HASH,
                "tx_hash_hex": tx_hash_hex,
                "entrypoint": request["entrypoint"],
                "entrypoint_hash_hex": entrypoint_hash_hex,
                "gas_limit": gas_limit,
                "gas_used": None,
                "fee_payment": fee_payment,
                "payload_digest_hex": "89" * 32,
            }
            json_response(
                self,
                HTTPStatus.OK,
                {
                    "ok": True,
                    "submitted": submitted,
                    "dataspace": "0",
                    "contract_address": request["contract_address"],
                    "code_hash_hex": BRIDGE_CODE_HASH,
                    "abi_hash_hex": BRIDGE_ABI_HASH,
                    "creation_time_ms": creation_time_ms,
                    "tx_hash_hex": tx_hash_hex,
                    "entrypoint_hash_hex": entrypoint_hash_hex,
                    "transaction_payload_b64": None if submitted else transaction_payload_b64,
                    "signing_message_b64": None if submitted else signing_message_b64,
                    "entrypoint": request["entrypoint"],
                    "operation_receipt": operation_receipt,
                },
            )
            return
        if parsed.path in {"/v1/bridge/proofs/submit", "/v1/bridge/messages"}:
            proof_field = (
                "destination_proof_b64"
                if parsed.path == "/v1/bridge/proofs/submit"
                else "native_proof_b64"
            )
            preparation_keys = {"authority", "fee_payment", proof_field}
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
        network_id=FIXTURE_NETWORK_ID,
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
