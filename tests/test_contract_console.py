import base64
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parent.parent
MODULE_PATH = REPO_ROOT / "scripts" / "serve_contract_console.py"
MODULE_NAME = "soraswap_contract_console"

spec = importlib.util.spec_from_file_location(MODULE_NAME, MODULE_PATH)
contract_console = importlib.util.module_from_spec(spec)
sys.modules[MODULE_NAME] = contract_console
assert spec.loader is not None
spec.loader.exec_module(contract_console)

TAIRA_NETWORK_ID = "hash:82531CE8EAE8BFF6BEECA4698BFD13A3BC8BEC5F0EE0D23D428C97FC17AB0F3B#3E94"
PRODUCTION_NETWORK_ID = "hash:32C903E5B3497E34C2B844EBFE8A39C19E6CF8F95D44C1FFB8BA9DCB42F91149#A2F0"


def canonical_hash_literal(raw_hash: str) -> str:
    body = raw_hash.upper()
    return f"hash:{body}#{contract_console.iroha_literal_crc16('hash', body):04X}"


def current_deploy_response(
    *,
    contract_address: str,
    contract_alias: str,
    dataspace_id: str,
    deploy_nonce: int,
    code_hash_hex: str,
    chain_id: str,
    torii_url: str,
) -> dict[str, object]:
    commit_hash_hex = "a" * 64
    commit_hash = canonical_hash_literal(commit_hash_hex)
    authority = "0x02000120" + "b" * 64
    deployment_state: dict[str, object] = {
        "authority": authority,
        "contract_alias": contract_alias,
        "deploy_nonce": str(deploy_nonce),
        "dataspace_alias": "universal",
        "dataspace_id": dataspace_id,
        "previous_contract_address": None,
        "observed_block_height": "1",
        "observed_block_hash": "f" * 64,
        "ledger_time_ms": "1000",
        "chain_discriminant": "0",
    }
    fee_quotes: list[object] = []
    operation_receipt = {
        "operation_kind": "contract_deploy",
        "status": "committed",
        "transport": "ivm-contract-deploy-helper",
        "torii_url": torii_url,
        "chain_id": chain_id,
        "authority": authority,
        "chain_discriminant": 0,
        "dataspace": dataspace_id,
        "contract_alias": contract_alias,
        "contract_address": contract_address,
        "contract_subject_account": contract_address,
        "code_hash_hex": code_hash_hex,
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
        "chain_id": chain_id,
        "code_hash_hex": code_hash_hex,
        "commit_deployment_tx_hash": commit_hash,
        "contract_address": contract_address,
        "contract_alias": contract_alias,
        "contract_subject_account": contract_address,
        "dataspace": dataspace_id,
        "deploy_nonce": deploy_nonce,
        "deployment_state": deployment_state,
        "expected_previous_contract_address": None,
        "fee_quotes": fee_quotes,
        "final": {"kind": "Committed", "hash": commit_hash},
        "next_deploy_nonce": deploy_nonce + 1,
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


def current_deployment_record(
    *,
    environment: str,
    contract_address: str,
    deploy_nonce: int,
    chain_fingerprint: dict[str, object],
) -> dict[str, object]:
    contract_alias = "sccp_bridge::bridge.universal"
    dataspace_alias = "universal"
    dataspace_id = "0"
    code_hash_hex = "1" * 64
    return {
        "contract_key": "bridge.sccp_bridge",
        "generated_at": "20260406T000000Z",
        "environment": environment,
        "contract_source": "contracts/bridge/sccp_bridge.ko",
        "contract_alias": contract_alias,
        "dataspace_alias": dataspace_alias,
        "dataspace_id": dataspace_id,
        "contract_address": contract_address,
        "deploy_nonce": deploy_nonce,
        "code_hash_hex": code_hash_hex,
        "abi_hash_hex": "2" * 64,
        "deploy_strategy": "ivm_contract_deploy",
        "chain_fingerprint": chain_fingerprint,
        "response": current_deploy_response(
            contract_address=contract_address,
            contract_alias=contract_alias,
            dataspace_id=dataspace_id,
            deploy_nonce=deploy_nonce,
            code_hash_hex=code_hash_hex,
            chain_id=str(chain_fingerprint["chain"]),
            torii_url=str(chain_fingerprint["torii_url"]),
        ),
    }


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def write_migration_register(root: Path, rows: list[tuple[str, str, str]] | None = None) -> None:
    if rows is None:
        rows = [("bridge.sccp_bridge", "SCCP bridge", "ported")]
    path = root / "docs" / "parity" / "migration_register.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "| Module | Scope | Status | Notes |",
        "| --- | --- | --- | --- |",
    ]
    for module, scope, status in rows:
        lines.append(f"| {module} | {scope} | {status} | fixture |")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_public_readiness_evidence(
    root: Path,
    environment_name: str,
    *,
    torii_url: str,
    chain: str,
    block_1_hash: str,
) -> None:
    environment = root / "deployments" / environment_name
    chain_fingerprint = {
        "torii_url": torii_url,
        "chain": chain,
        "block_1_hash": block_1_hash,
    }
    write_json(
        environment / "nested_call_probe.latest.json",
        {
            "generated_at": "20260406T000040Z",
            "environment": environment_name,
            "chain_fingerprint": chain_fingerprint,
            "supported": True,
            "state_bytes_roundtrip_supported": True,
            "nested_call_supported": True,
            "nested_asset_ops_supported": True,
        },
    )
    write_json(
        environment / "preflight.latest.json",
        {
            "generated_at": "20260406T000050Z",
            "target_environment": environment_name,
            "status": "ready",
            "blockers": [],
            "warnings": [],
            "environment": {
                "mutations_allowed": True,
                "oracle_client_config_present": True,
                "oracle_client_config_valid": True,
                "oracle_account_derivable": True,
                "oracle_account_distinct": True,
                "oracle_client_config_source": "fixture",
            },
            "endpoint": {
                "mcp_http_status": "200",
                "mcp": {
                    "enabled": True,
                    "metadata_valid": True,
                    "protocol_version": "2025-06-18",
                    "server_name": "iroha-torii-mcp",
                    "server_version": "0.0.0-dev",
                    "tool_count": 12,
                    "toolset_version": "fixture-tools-v1",
                },
                "health_issues": [],
                "health": {
                    "status": {"http_status": "200", "json_available": True},
                    "sumeragi": {"http_status": "200", "json_available": True},
                },
            },
            "chain": {
                "fingerprint_available": True,
                "fingerprint": chain_fingerprint,
                "saved_snapshot_exists": True,
                "saved_snapshot_matches": True,
                "saved_snapshot_environment": environment_name,
            },
            "nested_call_probe": {
                "latest_exists": True,
                "matches_current_chain": True,
                "generated_at": "20260406T000040Z",
                "environment": environment_name,
                "chain_fingerprint": chain_fingerprint,
                "supported": True,
            },
            "signer": {
                "authority_derivable": True,
                "account_exists": True,
                "assets_query_available": True,
                "fee_balance": "1",
            },
        },
    )


class ContractConsoleFixture:
    def __init__(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        # macOS spells its real temporary root as /private/var/... while
        # tempfile commonly returns /var/....  Security-sensitive path tests
        # use the canonical spelling so no ancestor symlink is traversed.
        self.root = Path(self.tempdir.name).resolve()
        subprocess.run(["git", "-C", str(self.root), "init", "-q"], check=True)
        (self.root / ".gitignore").write_text(
            "config/production/*.toml\n",
            encoding="utf-8",
        )
        write_migration_register(self.root)
        (self.root / "ui" / "contract_console").mkdir(parents=True, exist_ok=True)
        (self.root / "ui" / "contract_console" / "index.html").write_text(
            "<!doctype html><html><body>fixture</body></html>",
            encoding="utf-8",
        )
        (self.root / "contracts" / "bridge").mkdir(parents=True, exist_ok=True)
        (self.root / "contracts" / "bridge" / "sccp_bridge.ko").write_text(
            "// fixture bridge contract\n",
            encoding="utf-8",
        )
        environment = self.root / "deployments" / "testnet"
        write_json(
            environment / "chain.latest.json",
            {
                "generated_at": "20260406T000000Z",
                "torii_url": "https://taira.sora.org",
                "chain": "test-chain",
                "block_1_hash": "block-1",
                "environment": "testnet",
            },
        )
        write_public_readiness_evidence(
            self.root,
            "testnet",
            torii_url="https://taira.sora.org",
            chain="test-chain",
            block_1_hash="block-1",
        )
        write_json(
            environment / "contracts.latest.json",
            {
                "generated_at": "20260406T000000Z",
                "status": "completed",
                "environment": "testnet",
                "chain_fingerprint": {
                    "torii_url": "https://taira.sora.org",
                    "chain": "test-chain",
                    "block_1_hash": "block-1",
                },
                "contracts": [
                    current_deployment_record(
                        environment="testnet",
                        contract_address="tairac1bridgefixture",
                        deploy_nonce=11,
                        chain_fingerprint={
                            "torii_url": "https://taira.sora.org",
                            "chain": "test-chain",
                            "block_1_hash": "block-1",
                        },
                    )
                ],
            },
        )
        write_json(
            environment / "bridge.sccp_bridge.deploy.json",
            current_deployment_record(
                environment="testnet",
                contract_address="tairac1bridgefixture",
                deploy_nonce=11,
                chain_fingerprint={
                    "torii_url": "https://taira.sora.org",
                    "chain": "test-chain",
                    "block_1_hash": "block-1",
                },
            ),
        )
        write_json(
            environment / "bridge.sccp_bridge.manifest.json",
            {
                "generated_at": "20260406T000200Z",
                "environment": "testnet",
                "contract_key": "bridge.sccp_bridge",
                "code_hash": canonical_hash_literal("1" * 64),
                "abi_hash": canonical_hash_literal("2" * 64),
                "entrypoints": [
                    {"name": "listing_config", "kind": {"kind": "View"}, "params": [], "return_type": "tuple"},
                    {
                        "name": "mirror_asset",
                        "kind": {"kind": "View"},
                        "params": [{"name": "asset_key", "type_name": "Name"}],
                        "return_type": "tuple",
                    },
                    {
                        "name": "asset_config",
                        "kind": {"kind": "View"},
                        "params": [{"name": "asset_key", "type_name": "Name"}],
                        "return_type": "tuple",
                    },
                    {
                        "name": "asset_vault_bound",
                        "kind": {"kind": "View"},
                        "params": [{"name": "asset_key", "type_name": "Name"}],
                        "return_type": "int",
                    },
                    {
                        "name": "asset_vault_account",
                        "kind": {"kind": "View"},
                        "params": [{"name": "asset_key", "type_name": "Name"}],
                        "return_type": "AccountId",
                    },
                    {
                        "name": "mirror_route",
                        "kind": {"kind": "View"},
                        "params": [{"name": "route", "type_name": "Name"}],
                        "return_type": "tuple",
                    },
                    {
                        "name": "route_config",
                        "kind": {"kind": "View"},
                        "params": [{"name": "route", "type_name": "Name"}],
                        "return_type": "tuple",
                    },
                    {
                        "name": "route_provenance",
                        "kind": {"kind": "View"},
                        "params": [{"name": "route", "type_name": "Name"}],
                        "return_type": "tuple",
                    },
                    {
                        "name": "mirror_outbound",
                        "kind": {"kind": "View"},
                        "params": [{"name": "transfer", "type_name": "Name"}],
                        "return_type": "tuple",
                    },
                    {
                        "name": "outbound_config",
                        "kind": {"kind": "View"},
                        "params": [{"name": "transfer", "type_name": "Name"}],
                        "return_type": "tuple",
                    },
                    {
                        "name": "inbound_consumed",
                        "kind": {"kind": "View"},
                        "params": [{"name": "message_id", "type_name": "Name"}],
                        "return_type": "int",
                    },
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
                ]
            },
        )

    def add_environment(
        self,
        environment_name: str,
        *,
        torii_url: str,
        contract_address: str = "tairac1bridgefixture",
    ) -> None:
        environment = self.root / "deployments" / environment_name
        write_json(
            environment / "chain.latest.json",
            {
                "generated_at": "20260406T000000Z",
                "torii_url": torii_url,
                "chain": f"{environment_name}-chain",
                "block_1_hash": f"{environment_name}-block-1",
                "environment": environment_name,
            },
        )
        write_public_readiness_evidence(
            self.root,
            environment_name,
            torii_url=torii_url,
            chain=f"{environment_name}-chain",
            block_1_hash=f"{environment_name}-block-1",
        )
        write_json(
            environment / "contracts.latest.json",
            {
                "generated_at": "20260406T000000Z",
                "status": "completed",
                "environment": environment_name,
                "chain_fingerprint": {
                    "torii_url": torii_url,
                    "chain": f"{environment_name}-chain",
                    "block_1_hash": f"{environment_name}-block-1",
                },
                "contracts": [
                    current_deployment_record(
                        environment=environment_name,
                        contract_address=contract_address,
                        deploy_nonce=11,
                        chain_fingerprint={
                            "torii_url": torii_url,
                            "chain": f"{environment_name}-chain",
                            "block_1_hash": f"{environment_name}-block-1",
                        },
                    )
                ],
            },
        )
        write_json(
            environment / "bridge.sccp_bridge.deploy.json",
            current_deployment_record(
                environment=environment_name,
                contract_address=contract_address,
                deploy_nonce=11,
                chain_fingerprint={
                    "torii_url": torii_url,
                    "chain": f"{environment_name}-chain",
                    "block_1_hash": f"{environment_name}-block-1",
                },
            ),
        )
        write_json(
            environment / "bridge.sccp_bridge.manifest.json",
            {
                "generated_at": "20260406T000200Z",
                "environment": environment_name,
                "contract_key": "bridge.sccp_bridge",
                "code_hash": canonical_hash_literal("1" * 64),
                "abi_hash": canonical_hash_literal("2" * 64),
                "entrypoints": [
                    {"name": "listing_config", "kind": {"kind": "View"}, "params": [], "return_type": "tuple"},
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
                ]
            },
        )

    def write_completed_deploy_evidence(
        self,
        environment_name: str = "testnet",
        *,
        include_contract_record: bool = True,
        contract_address: str = "tairac1bridgefixture",
        deploy_nonce: int = 11,
    ) -> None:
        environment = self.root / "deployments" / environment_name
        chain = {
            "torii_url": "https://taira.sora.org" if environment_name == "testnet" else "https://production.example.invalid",
            "chain": f"{environment_name}-chain" if environment_name != "testnet" else "test-chain",
            "block_1_hash": f"{environment_name}-block-1" if environment_name != "testnet" else "block-1",
        }
        write_json(
            environment / "deploy.latest.json",
            {
                "generated_at": "20260406T000100Z",
                "status": "completed",
                "environment": environment_name,
                "chain_fingerprint": chain,
                "phases": {
                    "preflight": {
                        "status": "completed",
                        "detail": {
                            "signer_ready_check": {
                                "status": "completed",
                            },
                        },
                    },
                    "compile": {"status": "completed"},
                    "nested_call_probe": {"status": "completed"},
                    "deploy": {"status": "completed"},
                    "bootstrap_contract_state": {"status": "completed"},
                    "deployment_records_snapshot": {"status": "completed"},
                },
            },
        )
        if not include_contract_record:
            (environment / "bridge.sccp_bridge.deploy.json").unlink(missing_ok=True)
            return
        write_json(
            environment / "bridge.sccp_bridge.deploy.json",
            {
                **current_deployment_record(
                    environment=environment_name,
                    contract_address=contract_address,
                    deploy_nonce=deploy_nonce,
                    chain_fingerprint=chain,
                ),
                "generated_at": "20260406T000200Z",
            },
        )

    def close(self) -> None:
        self.tempdir.cleanup()

    def write_signer_config(
        self,
        relative_path: str,
        *,
        torii_url: str | None,
        public_key: str,
        private_key: str,
    ) -> Path:
        path = self.root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        lines = [
            f'chain = "fixture-chain"',
            f'network_id = "{PRODUCTION_NETWORK_ID if "/production/" in f"/{relative_path}" else TAIRA_NETWORK_ID}"',
        ]
        if torii_url is not None:
            lines.append(f'torii_url = "{torii_url}"')
        chain_discriminant = 991 if "/production/" in f"/{relative_path}" else 369
        lines.extend(
            [
                "",
                "[account]",
                'domain = "fixture.universal"',
                f'public_key = "{public_key}"',
                f'private_key = "{private_key}"',
                f"chain_discriminant = {chain_discriminant}",
                "",
            ]
        )
        path.write_text(
            "\n".join(lines),
            encoding="utf-8",
        )
        path.chmod(0o600)
        return path


class RunningServer:
    def __init__(self, state) -> None:
        self.server = contract_console.ThreadingHTTPServer(("127.0.0.1", 0), contract_console.ContractConsoleHandler)
        self.server.state = state
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    @property
    def base_url(self) -> str:
        host, port = self.server.server_address
        return f"http://{host}:{port}"

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, exc_type, exc, tb):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)


def request_json(url: str, payload: dict | None = None) -> tuple[int, dict]:
    if payload is None:
        request = urllib.request.Request(url)
    else:
        request = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            method="POST",
            headers={"Content-Type": "application/json"},
        )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        try:
            return exc.code, json.loads(exc.read().decode("utf-8"))
        finally:
            exc.close()


def request_response(url: str) -> tuple[int, object, bytes]:
    with urllib.request.urlopen(urllib.request.Request(url), timeout=5) as response:
        return response.status, response.headers, response.read()


def assert_browser_security_headers(testcase: unittest.TestCase, headers: object) -> None:
    testcase.assertEqual(headers.get("X-Content-Type-Options"), "nosniff")
    testcase.assertEqual(headers.get("X-Frame-Options"), "DENY")
    testcase.assertEqual(headers.get("Referrer-Policy"), "no-referrer")
    testcase.assertEqual(headers.get("Cross-Origin-Opener-Policy"), "same-origin")
    testcase.assertEqual(headers.get("Cross-Origin-Resource-Policy"), "same-origin")
    testcase.assertEqual(
        headers.get("Permissions-Policy"),
        "camera=(), geolocation=(), microphone=(), payment=(), usb=()",
    )
    testcase.assertEqual(
        headers.get("Content-Security-Policy"),
        contract_console.BROWSER_SECURITY_HEADERS["Content-Security-Policy"],
    )


def make_signer(
    *,
    environment: str = "testnet",
    authority: str | None = "i105fixture",
    torii_url: str | None = "https://taira.sora.org",
    private_key: str | None = "8026209d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
    public_key: str | None = None,
    config_path: Path | None = Path("/tmp/test-signer.toml"),
    source: str = "explicit",
    warnings: list[str] | None = None,
    network_id: str | None = TAIRA_NETWORK_ID,
):
    return contract_console.SignerBinding(
        environment=environment,
        config_path=config_path,
        authority=authority,
        torii_url=torii_url,
        network_id=network_id,
        private_key=private_key,
        public_key=public_key or "ed0120d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
        basic_auth=("user", "pass"),
        warnings=warnings or [],
        source=source,
    )


BRIDGE_TEST_PRIVATE_KEY = "8026209d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
BRIDGE_TEST_PUBLIC_KEY = "ed0120d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
BRIDGE_TEST_PROOF_B64 = base64.b64encode(b"closed-proof-fixture").decode("ascii")
BRIDGE_TEST_TRANSACTION = b"canonical-prepared-transaction"
BRIDGE_TEST_TRANSACTION_B64 = base64.b64encode(BRIDGE_TEST_TRANSACTION).decode("ascii")
BRIDGE_TEST_SIGNING_MESSAGE_B64 = base64.b64encode(
    contract_console.iroha_transaction_signing_message(BRIDGE_TEST_TRANSACTION)
).decode("ascii")
BRIDGE_TEST_METADATA = {
    "payload_kind": "transfer",
    "message_id_hex": "12" * 32,
    "backend": "bridge/sccp/groth16-bn254-v1",
    "counterparty_domain": 2,
    "counterparty_chain": "ethereum-sepolia",
    "route_configuration_hash_hex": "34" * 32,
    "range_start_height": 91,
    "range_end_height": 91,
    "creation_time_ms": 1_750_000_000_001,
}


def bridge_preparation_response() -> dict[str, object]:
    return {
        **BRIDGE_TEST_METADATA,
        "submitted": False,
        "tx_hash_hex": None,
        "transaction_payload_b64": BRIDGE_TEST_TRANSACTION_B64,
        "signing_message_b64": BRIDGE_TEST_SIGNING_MESSAGE_B64,
    }


def bridge_submission_response() -> dict[str, object]:
    return {
        **BRIDGE_TEST_METADATA,
        "submitted": True,
        "tx_hash_hex": "ab" * 32,
        "transaction_payload_b64": None,
        "signing_message_b64": None,
    }


def contract_call_response(
    *,
    contract_address: str,
    entrypoint: str,
    submitted: bool,
    gas_limit: int = contract_console.DEFAULT_GAS_LIMIT,
    creation_time_ms: int = 1_750_000_000_002,
) -> dict[str, object]:
    fee_payment = contract_console.authority_fee_payment_intent(gas_limit)
    receipt = {
        "operation_kind": "contract_call",
        "status": "submitted" if submitted else "pending_signature",
        "transport": "torii",
        "dataspace": "apps",
        "contract_address": contract_address,
        "code_hash_hex": "45" * 32,
        "abi_hash_hex": "67" * 32,
        "entrypoint": entrypoint,
        "gas_limit": gas_limit,
        "fee_payment": fee_payment,
        "payload_digest_hex": "89" * 32,
    }
    if submitted:
        receipt["tx_hash_hex"] = "ab" * 32
        receipt["entrypoint_hash_hex"] = "cd" * 32
    return {
        "ok": True,
        "submitted": submitted,
        "dataspace": "apps",
        "contract_address": contract_address,
        "code_hash_hex": "45" * 32,
        "abi_hash_hex": "67" * 32,
        "creation_time_ms": creation_time_ms,
        "tx_hash_hex": "ab" * 32 if submitted else None,
        "entrypoint_hash_hex": "cd" * 32 if submitted else None,
        "transaction_payload_b64": None if submitted else BRIDGE_TEST_TRANSACTION_B64,
        "signing_message_b64": None if submitted else BRIDGE_TEST_SIGNING_MESSAGE_B64,
        "entrypoint": entrypoint,
        "operation_receipt": receipt,
    }


class ContractConsoleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = ContractConsoleFixture()
        self.state = contract_console.ContractConsoleState(self.fixture.root, {})

    def tearDown(self) -> None:
        self.fixture.close()

    def test_argument_parser_rejects_invalid_ports(self) -> None:
        parser = contract_console.build_argument_parser()
        self.assertEqual(parser.parse_args(["--port", "65535"]).port, 65535)

        for value in ("0", "-1", "65536", "not-a-port", "1.5"):
            with self.subTest(value=value):
                with mock.patch("sys.stderr", new=io.StringIO()):
                    with self.assertRaises(SystemExit) as error:
                        parser.parse_args(["--port", value])
                self.assertEqual(error.exception.code, 2)

    def test_browser_gas_limit_normalization_bounds_requests(self) -> None:
        self.assertEqual(contract_console.normalize_browser_gas_limit(None), contract_console.DEFAULT_GAS_LIMIT)
        self.assertEqual(contract_console.normalize_browser_gas_limit(""), contract_console.DEFAULT_GAS_LIMIT)
        self.assertEqual(contract_console.normalize_browser_gas_limit("1"), 1)
        self.assertEqual(
            contract_console.normalize_browser_gas_limit(str(contract_console.MAX_BROWSER_GAS_LIMIT)),
            contract_console.MAX_BROWSER_GAS_LIMIT,
        )

        for value in ("0", "-1", str(contract_console.MAX_BROWSER_GAS_LIMIT + 1)):
            with self.subTest(value=value):
                with self.assertRaisesRegex(ValueError, "gas_limit must be between"):
                    contract_console.normalize_browser_gas_limit(value)

        for value in ("not-a-number", "1.5", 1.5, True):
            with self.subTest(value=value):
                with self.assertRaisesRegex(ValueError, "gas_limit must be an integer"):
                    contract_console.normalize_browser_gas_limit(value)

    def test_fee_payment_validator_accepts_only_current_quoted_charge_limits(self) -> None:
        gas_limit = 123_456
        charge_limits = [
            {
                "kind": {"kind": "nexus", "value": None},
                "asset_definition_id": "62Fk4FPcMuLvW5QjDGNF2a4jAmjM",
                "max_amount": "1.25",
            },
            {
                "kind": {"kind": "pipeline_gas", "value": None},
                "asset_definition_id": "7EAD8EFYUx1aVKZPUU1fyKvr8dF1",
                "max_amount": str((1 << 511) - 1),
            },
        ]
        quoted = {
            "payer": "authority",
            "value": {"charge_limits": charge_limits, "gas_limit": gas_limit},
        }

        self.assertEqual(
            contract_console.validate_authority_fee_payment_intent(
                quoted,
                expected_gas_limit=gas_limit,
                context="quoted fee",
                allow_quoted_charge_limits=True,
            ),
            quoted,
        )
        with self.assertRaisesRegex(ValueError, "must be empty before fee quotation"):
            contract_console.validate_authority_fee_payment_intent(
                quoted,
                expected_gas_limit=gas_limit,
                context="request fee",
            )

        invalid_limits = {
            "unknown field": [{**charge_limits[0], "legacy": True}],
            "untagged kind": [{**charge_limits[0], "kind": "nexus"}],
            "non-null tag": [{**charge_limits[0], "kind": {"kind": "nexus", "value": {}}}],
            "unknown kind": [{**charge_limits[0], "kind": {"kind": "storage", "value": None}}],
            "duplicate kind": [charge_limits[0], dict(charge_limits[0])],
            "wrong order": [charge_limits[1], charge_limits[0]],
            "blank asset": [{**charge_limits[0], "asset_definition_id": " "}],
            "numeric quantity": [{**charge_limits[0], "max_amount": 1}],
            "zero quantity": [{**charge_limits[0], "max_amount": "0"}],
            "leading zero": [{**charge_limits[0], "max_amount": "01"}],
            "trailing fractional zero": [{**charge_limits[0], "max_amount": "1.0"}],
            "excess scale": [{**charge_limits[0], "max_amount": "0." + "0" * 28 + "1"}],
            "signed overflow": [{**charge_limits[0], "max_amount": str(1 << 511)}],
        }
        for label, limits in invalid_limits.items():
            with self.subTest(label=label):
                candidate = {
                    "payer": "authority",
                    "value": {"charge_limits": limits, "gas_limit": gas_limit},
                }
                with self.assertRaises(ValueError):
                    contract_console.validate_authority_fee_payment_intent(
                        candidate,
                        expected_gas_limit=gas_limit,
                        context="quoted fee",
                        allow_quoted_charge_limits=True,
                    )

    def test_contract_call_response_rejects_non_null_gas_used(self) -> None:
        expected_request = {
            "contract_address": "tairac1bridgefixture",
            "entrypoint": "listing_config",
            "fee_payment": contract_console.authority_fee_payment_intent(
                contract_console.DEFAULT_GAS_LIMIT
            ),
        }
        response = contract_call_response(
            contract_address="tairac1bridgefixture",
            entrypoint="listing_config",
            submitted=False,
        )
        response["operation_receipt"]["gas_used"] = 1

        with self.assertRaisesRegex(ValueError, "gas_used must be absent or null"):
            contract_console.validate_contract_call_response(
                response,
                expected_request=expected_request,
                submitted=False,
            )

    def test_contract_proxy_rejects_out_of_range_browser_gas_limit(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        with mock.patch.object(contract_console, "proxy_torii_request") as proxy:
            with RunningServer(state) as server:
                status, payload = request_json(
                    f"{server.base_url}/api/view",
                    {
                        "environment": "testnet",
                        "contract_address": "tairac1bridgefixture",
                        "entrypoint": "listing_config",
                        "authority": "i105fixture",
                        "gas_limit": contract_console.MAX_BROWSER_GAS_LIMIT + 1,
                    },
                )

        self.assertEqual(status, 400)
        self.assertFalse(payload["ok"])
        self.assertIn("gas_limit must be between", payload["error"])
        proxy.assert_not_called()

    def test_contract_view_rejects_explicit_sensitive_key_in_browser_json(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        with mock.patch.object(contract_console, "proxy_torii_request") as proxy:
            with RunningServer(state) as server:
                status, payload = request_json(
                    f"{server.base_url}/api/view",
                    {
                        "environment": "testnet",
                        "contract_address": "tairac1bridgefixture",
                        "entrypoint": "listing_config",
                        "authority": "i105fixture",
                        "payload": {"privateKey": "should-not-be-forwarded"},
                    },
                )

        self.assertEqual(status, 400)
        self.assertFalse(payload["ok"])
        self.assertIn("browser JSON must not include private keys", payload["error"])
        proxy.assert_not_called()

    def test_http_responses_include_browser_security_headers(self) -> None:
        with RunningServer(self.state) as server:
            static_status, static_headers, static_body = request_response(f"{server.base_url}/")
            api_status, api_headers, api_body = request_response(f"{server.base_url}/api/catalog")

        self.assertEqual(static_status, 200)
        self.assertIn(b"fixture", static_body)
        assert_browser_security_headers(self, static_headers)
        self.assertEqual(static_headers.get("Cache-Control"), "no-store")

        self.assertEqual(api_status, 200)
        self.assertIn(b"generated_at", api_body)
        assert_browser_security_headers(self, api_headers)
        self.assertEqual(api_headers.get("Cache-Control"), "no-store")

    def test_redact_request_payload_recursively_hides_sensitive_fields(self) -> None:
        request = {
            "private_key": "top-secret",
            "payload": {
                "privateKey": "camel-secret",
                "public_key": "ed0120fixture",
                "destination_proof_b64": "AQ==",
                "transaction_payload_b64": "Ag==",
                "signature_b64": "Aw==",
                "nested": [
                    {
                        "secret": "nested-secret",
                        "api-token": "api-token-secret",
                        "access_token": "access-token-secret",
                        "refreshToken": "refresh-token-secret",
                        "authorization": "bearer secret",
                        "client_secret": "client-secret-value",
                        "visible": "safe",
                    },
                    {"mnemonic": "seed words"},
                    {"password": "password-secret", "passphrase": "passphrase-secret"},
                ],
            },
        }

        redacted = contract_console.redact_request_payload(request)

        self.assertEqual(redacted["private_key"], "[redacted]")
        self.assertEqual(redacted["payload"]["privateKey"], "[redacted]")
        self.assertEqual(redacted["payload"]["public_key"], "ed0120fixture")
        self.assertEqual(redacted["payload"]["destination_proof_b64"], "[omitted-base64:4]")
        self.assertEqual(redacted["payload"]["transaction_payload_b64"], "[omitted-base64:4]")
        self.assertEqual(redacted["payload"]["signature_b64"], "[omitted-base64:4]")
        self.assertEqual(redacted["payload"]["nested"][0]["secret"], "[redacted]")
        self.assertEqual(redacted["payload"]["nested"][0]["api-token"], "[redacted]")
        self.assertEqual(redacted["payload"]["nested"][0]["access_token"], "[redacted]")
        self.assertEqual(redacted["payload"]["nested"][0]["refreshToken"], "[redacted]")
        self.assertEqual(redacted["payload"]["nested"][0]["authorization"], "[redacted]")
        self.assertEqual(redacted["payload"]["nested"][0]["client_secret"], "[redacted]")
        self.assertEqual(redacted["payload"]["nested"][0]["visible"], "safe")
        self.assertEqual(redacted["payload"]["nested"][1]["mnemonic"], "[redacted]")
        self.assertEqual(redacted["payload"]["nested"][2]["password"], "[redacted]")
        self.assertEqual(redacted["payload"]["nested"][2]["passphrase"], "[redacted]")
        self.assertEqual(request["payload"]["nested"][0]["secret"], "nested-secret")

    def test_explicit_sensitive_key_error_rejects_nested_browser_json(self) -> None:
        payload = {
            "environment": "testnet",
            "payload": {
                "nested": [
                    {"visible": "safe"},
                    {"private-key": "browser-secret"},
                    {"apiKey": "api-key-secret", "bearer_token": "bearer-token-secret"},
                    {"access_token": "access-token-secret", "refresh-token": "refresh-token-secret"},
                    {"clientSecret": "client-secret-value"},
                ],
            },
        }

        error = contract_console.explicit_sensitive_key_error(payload)

        self.assertIsNotNone(error)
        self.assertIn("browser JSON must not include private keys", error)
        self.assertIn("tokens", error)
        self.assertIn("authorization", error)

    def test_sensitive_string_detector_handles_diagnostic_key_forms(self) -> None:
        sensitive_samples = [
            "deployment failed with private_key=fixture-secret",
            "deployment failed with private key: fixture-secret",
            "deployment failed with --private-key fixture-secret",
            "deployment failed with --client-secret=fixture-secret",
            '{"client secret":"fixture-secret"}',
            "callback=https://user:fixture-secret@node.example.invalid/v1",
        ]
        safe_samples = [
            "ordinary contract_address=tairac1fixture",
            "route token count: 3",
            "callback=https://node.example.invalid/v1?visible=ok",
        ]

        for sample in sensitive_samples:
            with self.subTest(sample=sample):
                self.assertTrue(contract_console.string_contains_sensitive_key(sample))
        for sample in safe_samples:
            with self.subTest(sample=sample):
                self.assertFalse(contract_console.string_contains_sensitive_key(sample))

    def test_redact_diagnostic_text_redacts_sensitive_forms_and_paths(self) -> None:
        diagnostic = (
            "health failed private_key=802620SECRET "
            "authorization: Bearer bearer-secret "
            "--client-secret cli-secret "
            "callback=https://user:url-secret@node.example.invalid/v1?access_token=query-secret "
            "/Users/operator/dev/soraswap/tmp/health.log"
        )

        redacted = contract_console.redact_diagnostic_text(diagnostic)

        self.assertIn("private_key=[redacted]", redacted)
        self.assertIn("authorization: Bearer [redacted]", redacted)
        self.assertIn("--client-secret [redacted]", redacted)
        self.assertIn("https://[redacted]@node.example.invalid/v1?access_token=[redacted]", redacted)
        self.assertIn("[local-path]/health.log", redacted)
        self.assertNotIn("802620SECRET", redacted)
        self.assertNotIn("bearer-secret", redacted)
        self.assertNotIn("cli-secret", redacted)
        self.assertNotIn("url-secret", redacted)
        self.assertNotIn("query-secret", redacted)
        self.assertNotIn("/Users/operator/dev/soraswap", redacted)
        self.assertEqual(
            contract_console.redact_diagnostic_text("route token count: 3; public token bucket saturated"),
            "route token count: 3; public token bucket saturated",
        )
        self.assertEqual(
            contract_console.redact_diagnostic_text("secret warning without assignment remains visible"),
            "secret warning without assignment remains visible",
        )
        self.assertEqual(
            contract_console.redact_diagnostic_text("token=fixture-secret password: pass-secret"),
            "token=[redacted] password: [redacted]",
        )

    def test_access_log_redacts_sensitive_query_values(self) -> None:
        class FakeHandler:
            def address_string(self) -> str:
                return "127.0.0.1"

        stderr = io.StringIO()
        with mock.patch("sys.stderr", new=stderr):
            contract_console.ContractConsoleHandler.log_message(
                FakeHandler(),
                "%s %s %s",
                '"GET /api/pipeline/transactions/status?environment=testnet&hash=pending'
                '&private_key=drop-me&apiKey=api-secret&authorization=Bearer+secret'
                '&access_token=access-secret&clientSecret=client-secret'
                '&callback=https%3A%2F%2Fuser%3Acallback-secret%40node.example.invalid%2Fpath'
                '&payload=%7B%22private_key%22%3A%22nested-secret%22%2C%22visible%22%3A%22ok%22%7D'
                f'&long={"x" * (contract_console.ACCESS_LOG_QUERY_VALUE_CHARS + 1)}'
                '&visible=ok HTTP/1.1"',
                "200",
                "-",
            )

        log = stderr.getvalue()
        self.assertIn("private_key=[redacted]", log)
        self.assertIn("apiKey=[redacted]", log)
        self.assertIn("authorization=[redacted]", log)
        self.assertIn("access_token=[redacted]", log)
        self.assertIn("clientSecret=[redacted]", log)
        self.assertIn("callback=[redacted]", log)
        self.assertIn("payload=[redacted]", log)
        self.assertIn(f"long=[truncated:{contract_console.ACCESS_LOG_QUERY_VALUE_CHARS + 1}]", log)
        self.assertIn("visible=ok", log)
        self.assertNotIn("drop-me", log)
        self.assertNotIn("api-secret", log)
        self.assertNotIn("Bearer+secret", log)
        self.assertNotIn("access-secret", log)
        self.assertNotIn("client-secret", log)
        self.assertNotIn("callback-secret", log)
        self.assertNotIn("nested-secret", log)
        self.assertNotIn("%22private_key%22", log)
        self.assertNotIn("x" * (contract_console.ACCESS_LOG_QUERY_VALUE_CHARS + 1), log)
        self.assertEqual(
            contract_console.redact_access_log_message(
                '"GET https://user:proxy-secret@node.example.invalid/v1/status HTTP/1.1"'
            ),
            '"GET https://[redacted]@node.example.invalid/v1/status HTTP/1.1"',
        )

    def test_parse_request_body_rejects_malformed_and_oversized_content_length(self) -> None:
        class FakeHandler:
            def __init__(self, content_length: str, body: bytes = b"{}") -> None:
                self.headers = {
                    "Content-Length": content_length,
                    "Content-Type": "application/json",
                }
                self.rfile = io.BytesIO(body)

        with self.assertRaisesRegex(ValueError, "invalid Content-Length"):
            contract_console.parse_request_body(FakeHandler("not-a-number"))
        with self.assertRaisesRegex(ValueError, "invalid Content-Length"):
            contract_console.parse_request_body(FakeHandler("-1"))
        with self.assertRaisesRegex(ValueError, "request body exceeds"):
            contract_console.parse_request_body(
                FakeHandler(str(contract_console.MAX_REQUEST_BODY_BYTES + 1), b"{}")
            )

    def test_parse_request_body_rejects_invalid_utf8(self) -> None:
        class FakeHandler:
            def __init__(self, body: bytes) -> None:
                self.headers = {
                    "Content-Length": str(len(body)),
                    "Content-Type": "application/json",
                }
                self.rfile = io.BytesIO(body)

        with self.assertRaisesRegex(ValueError, "invalid UTF-8 request body"):
            contract_console.parse_request_body(FakeHandler(b"\xff\xfe"))

    def test_parse_request_body_rejects_overly_nested_json(self) -> None:
        class FakeHandler:
            def __init__(self, body: bytes) -> None:
                self.headers = {
                    "Content-Length": str(len(body)),
                    "Content-Type": "application/json",
                }
                self.rfile = io.BytesIO(body)

        shallow_body = b'{"payload":{"items":[1,2,3]}}'
        deep_body = (
            '{"payload":'
            + ("[" * (contract_console.MAX_BROWSER_JSON_DEPTH + 2))
            + "0"
            + ("]" * (contract_console.MAX_BROWSER_JSON_DEPTH + 2))
            + "}"
        ).encode("utf-8")

        self.assertEqual(
            contract_console.parse_request_body(FakeHandler(shallow_body)),
            {"payload": {"items": [1, 2, 3]}},
        )
        with self.assertRaisesRegex(ValueError, "request body nesting exceeds"):
            contract_console.parse_request_body(FakeHandler(deep_body))

    def test_parse_request_body_requires_json_content_type_for_non_empty_body(self) -> None:
        class FakeHandler:
            def __init__(self, body: bytes, content_type: str | None) -> None:
                self.headers = {"Content-Length": str(len(body))}
                if content_type is not None:
                    self.headers["Content-Type"] = content_type
                self.rfile = io.BytesIO(body)

        body = b'{"payload":true}'
        self.assertEqual(
            contract_console.parse_request_body(
                FakeHandler(body, "application/json; charset=utf-8")
            ),
            {"payload": True},
        )
        self.assertEqual(
            contract_console.parse_request_body(
                FakeHandler(body, "application/vnd.soraswap+json")
            ),
            {"payload": True},
        )
        with self.assertRaisesRegex(ValueError, "Content-Type must be application/json"):
            contract_console.parse_request_body(FakeHandler(body, None))
        with self.assertRaisesRegex(ValueError, "Content-Type must be application/json"):
            contract_console.parse_request_body(FakeHandler(body, "text/plain"))
        self.assertEqual(
            contract_console.parse_request_body(FakeHandler(b"", None)),
            {},
        )

    def test_parse_bounded_query_rejects_oversized_or_too_many_fields(self) -> None:
        self.assertEqual(
            contract_console.parse_bounded_query("environment=testnet&limit=7"),
            {"environment": ["testnet"], "limit": ["7"]},
        )

        long_query = "environment=testnet&payload=" + (
            "x" * contract_console.MAX_BROWSER_QUERY_STRING_CHARS
        )
        with self.assertRaisesRegex(ValueError, "query string exceeds"):
            contract_console.parse_bounded_query(long_query)

        too_many_fields = "&".join(
            f"k{index}=v" for index in range(contract_console.MAX_BROWSER_QUERY_FIELDS + 1)
        )
        with self.assertRaisesRegex(ValueError, "too many fields"):
            contract_console.parse_bounded_query(too_many_fields)

    def test_decode_json_maybe_treats_overly_nested_json_as_text(self) -> None:
        deep_json = ("[" * 2000) + "0" + ("]" * 2000)

        self.assertIsNone(contract_console.decode_json_maybe(deep_json))

    def test_proxy_torii_request_rejects_oversized_upstream_response(self) -> None:
        class FakeHeaders:
            def get(self, name: str) -> str | None:
                return "application/json" if name == "Content-Type" else None

        class FakeResponse:
            status = 200
            headers = FakeHeaders()

            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, tb):
                return False

            def read(self, size: int = -1) -> bytes:
                return b"x" * size

        with mock.patch.object(contract_console, "MAX_UPSTREAM_RESPONSE_BYTES", 8):
            opener = mock.Mock()
            opener.open.return_value = FakeResponse()
            with mock.patch.object(contract_console.urllib.request, "build_opener", return_value=opener):
                with self.assertRaisesRegex(OSError, "upstream response exceeds"):
                    contract_console.proxy_torii_request(
                        "https://taira.sora.org",
                        "/v1/contracts/events",
                        method="GET",
                        payload=None,
                        query=None,
                        basic_auth=None,
                        timeout=1,
                    )

    def test_proxy_torii_request_rejects_incomplete_successful_fanout(self) -> None:
        upstream = mock.MagicMock()
        upstream.__enter__.return_value = upstream
        upstream.status = 200
        upstream.headers = {
            "Content-Type": "application/json",
            "x-iroha-fanout-routes-failed": "1",
        }
        opener = mock.Mock()
        opener.open.return_value = upstream

        with mock.patch.object(contract_console.urllib.request, "build_opener", return_value=opener):
            with self.assertRaisesRegex(OSError, "incomplete Torii routed response"):
                contract_console.proxy_torii_request(
                    "https://taira.sora.org",
                    "/v1/assets/definitions/xor%23universal",
                    method="GET",
                    payload=None,
                    query=None,
                    basic_auth=None,
                    timeout=1,
                )
        upstream.read.assert_not_called()

    def test_complete_fanout_headers_accept_exact_zero_counts(self) -> None:
        contract_console.reject_incomplete_fanout_response(
            200,
            {
                "x-iroha-fanout-routes-failed": "0",
                "x-iroha-fanout-routes-denied": "0",
                "x-iroha-fanout-routes-unavailable": "0",
                "x-iroha-fanout-routes-not-found": "0",
            },
        )

    def test_load_environment_reads_manifest_entrypoints(self) -> None:
        contracts_path = self.fixture.root / "deployments" / "testnet" / "contracts.latest.json"
        contracts_latest = json.loads(contracts_path.read_text(encoding="utf-8"))
        contracts_latest["contracts"][0]["contract_source"] = str(
            self.fixture.root / "contracts" / "bridge" / "sccp_bridge.ko"
        )
        write_json(contracts_path, contracts_latest)

        environment = self.state.load_environment("testnet")
        self.assertEqual(environment["torii_url"], "https://taira.sora.org")
        self.assertEqual(environment["torii_url_source"], "deployment")
        self.assertEqual(environment["mutation_policy"]["name"], "testnet")
        self.assertFalse(environment["mutation_policy"]["allowed"])
        self.assertTrue(environment["mutation_policy"]["requires_flag"])
        self.assertEqual(environment["mutation_policy"]["flag"], "SORASWAP_ALLOW_TESTNET_MUTATIONS")
        self.assertEqual(len(environment["contracts"]), 1)
        contract = environment["contracts"][0]
        self.assertEqual(contract["contract_key"], "bridge.sccp_bridge")
        self.assertEqual(contract["evidence_source"], "deploy_record")
        self.assertEqual(contract["contract_address"], "tairac1bridgefixture")
        self.assertEqual(contract["dataspace_alias"], "universal")
        self.assertEqual(contract["dataspace_id"], "0")
        self.assertNotIn("dataspace", contract)
        self.assertEqual(contract["contract_source"], "contracts/bridge/sccp_bridge.ko")
        self.assertEqual(contract["deployment_path"], "deployments/testnet/bridge.sccp_bridge.deploy.json")
        self.assertEqual(contract["manifest_path"], "deployments/testnet/bridge.sccp_bridge.manifest.json")
        self.assertEqual(contract["entrypoints"][0]["name"], "listing_config")
        self.assertEqual(contract["entrypoints"][-1]["kind"], "Kotoage")
        self.assertIn("commit_deployment_tx_hash", contract)
        self.assertNotIn("verification", contract)
        self.assertNotIn("tx_hash_hex", contract)

    def test_current_deployment_record_shape_rejects_legacy_compatibility_forms(self) -> None:
        chain = {
            "torii_url": "https://taira.sora.org",
            "chain": "test-chain",
            "block_1_hash": "block-1",
        }
        current = current_deployment_record(
            environment="testnet",
            contract_address="tairac1bridgefixture",
            deploy_nonce=11,
            chain_fingerprint=chain,
        )
        self.assertTrue(contract_console.current_deployment_record_shape(current))

        legacy_variants: dict[str, dict[str, object]] = {}
        legacy_variants["instance"] = {**current, "instance": {"contract_id": "tairac1bridgefixture"}}

        ambiguous_dataspace = dict(current)
        ambiguous_dataspace["dataspace"] = ambiguous_dataspace.pop("dataspace_id")
        legacy_variants["ambiguous_top_level_dataspace"] = ambiguous_dataspace

        wrong_dataspace_alias = dict(current)
        wrong_dataspace_alias["dataspace_alias"] = "apps"
        legacy_variants["wrong_dataspace_alias"] = wrong_dataspace_alias

        wrong_dataspace_id = dict(current)
        wrong_dataspace_id["dataspace_id"] = "7"
        legacy_variants["wrong_dataspace_id"] = wrong_dataspace_id

        response_dataspace_mismatch = dict(current)
        response_dataspace_mismatch["response"] = dict(current["response"])
        response_dataspace_mismatch["response"]["dataspace"] = "7"
        legacy_variants["response_dataspace_mismatch"] = response_dataspace_mismatch

        deployment_state_mismatch = dict(current)
        deployment_state_mismatch["response"] = dict(current["response"])
        deployment_state_mismatch["response"]["deployment_state"] = dict(
            current["response"]["deployment_state"]
        )
        deployment_state_mismatch["response"]["deployment_state"]["dataspace_alias"] = "apps"
        legacy_variants["deployment_state_dataspace_mismatch"] = deployment_state_mismatch

        deployment_state_id_mismatch = dict(current)
        deployment_state_id_mismatch["response"] = dict(current["response"])
        deployment_state_id_mismatch["response"]["deployment_state"] = dict(
            current["response"]["deployment_state"]
        )
        deployment_state_id_mismatch["response"]["deployment_state"]["dataspace_id"] = "7"
        legacy_variants["deployment_state_dataspace_id_mismatch"] = deployment_state_id_mismatch

        name_alias = dict(current)
        name_alias["name"] = name_alias.pop("contract_key")
        legacy_variants["name"] = name_alias

        address_alias = dict(current)
        address_alias["contract_id"] = address_alias.pop("contract_address")
        legacy_variants["contract_id"] = address_alias

        code_hash_alias = dict(current)
        code_hash_alias["code_hash"] = code_hash_alias.pop("code_hash_hex")
        legacy_variants["code_hash"] = code_hash_alias

        abi_hash_alias = dict(current)
        abi_hash_alias["abi_hash"] = abi_hash_alias.pop("abi_hash_hex")
        legacy_variants["abi_hash"] = abi_hash_alias

        recovered = dict(current)
        recovered["deploy_strategy"] = "recovered_from_alias_resolve"
        legacy_variants["recovered_strategy"] = recovered

        chain_alias = dict(current)
        chain_alias["chain_fingerprint"] = {**chain, "environment": "testnet"}
        legacy_variants["expanded_chain_fingerprint"] = chain_alias

        response_alias = dict(current)
        response_alias["response"] = dict(current["response"])
        response_alias["response"]["tx_hash_hex"] = response_alias["response"].pop(
            "commit_deployment_tx_hash"
        )
        legacy_variants["response_tx_hash"] = response_alias

        for label, record in legacy_variants.items():
            with self.subTest(label=label):
                self.assertFalse(contract_console.current_deployment_record_shape(record))

    def test_manifest_hash_requires_current_checksummed_hash_literal(self) -> None:
        raw_hash = "1" * 64
        canonical = canonical_hash_literal(raw_hash)
        self.assertEqual(contract_console.manifest_hash({"code_hash": canonical}, "code_hash"), raw_hash)
        for legacy in (raw_hash, f"hash:{raw_hash}", f"0x{raw_hash}", canonical[:-4] + "0000"):
            with self.subTest(legacy=legacy):
                self.assertIsNone(contract_console.manifest_hash({"code_hash": legacy}, "code_hash"))

    def test_catalog_does_not_treat_contracts_snapshot_as_a_deploy_record(self) -> None:
        contracts_path = self.fixture.root / "deployments" / "testnet" / "contracts.latest.json"
        contracts = json.loads(contracts_path.read_text(encoding="utf-8"))
        contracts["legacy"] = True
        write_json(contracts_path, contracts)
        (self.fixture.root / "deployments" / "testnet" / "bridge.sccp_bridge.deploy.json").unlink()

        environment = self.state.load_environment("testnet")

        self.assertEqual(environment["contracts"], [])

    def test_load_environment_uses_current_deploy_record_when_manifest_matches(self) -> None:
        self.fixture.write_completed_deploy_evidence(contract_address="tairac1deploycurrent")

        environment = self.state.load_environment("testnet")

        self.assertEqual(len(environment["contracts"]), 1)
        contract = environment["contracts"][0]
        self.assertEqual(contract["evidence_source"], "deploy_record")
        self.assertEqual(contract["contract_address"], "tairac1deploycurrent")
        self.assertEqual(contract["deployment_path"], "deployments/testnet/bridge.sccp_bridge.deploy.json")
        self.assertEqual(contract["manifest_path"], "deployments/testnet/bridge.sccp_bridge.manifest.json")

    def test_load_environment_ignores_deploy_record_when_hashes_do_not_match_manifest(self) -> None:
        self.fixture.write_completed_deploy_evidence(contract_address="tairac1deploycurrent")
        deploy_path = self.fixture.root / "deployments" / "testnet" / "bridge.sccp_bridge.deploy.json"
        deploy_record = json.loads(deploy_path.read_text(encoding="utf-8"))
        deploy_record["code_hash_hex"] = "9" * 64
        write_json(deploy_path, deploy_record)

        environment = self.state.load_environment("testnet")

        self.assertEqual(environment["contracts"], [])

    def test_load_environment_ignores_deploy_record_when_manifest_hashes_do_not_match(self) -> None:
        manifest_path = self.fixture.root / "deployments" / "testnet" / "bridge.sccp_bridge.manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["code_hash"] = canonical_hash_literal("9" * 64)
        write_json(manifest_path, manifest)

        environment = self.state.load_environment("testnet")

        self.assertEqual(environment["contracts"], [])

    def test_load_environment_ignores_incomplete_contracts_latest_snapshot(self) -> None:
        contracts_path = self.fixture.root / "deployments" / "testnet" / "contracts.latest.json"
        contracts = json.loads(contracts_path.read_text(encoding="utf-8"))
        contracts.pop("status", None)
        write_json(contracts_path, contracts)

        environment = self.state.load_environment("testnet")

        self.assertEqual(len(environment["contracts"]), 1)
        self.assertEqual(environment["contracts"][0]["evidence_source"], "deploy_record")

    def test_load_environment_ignores_duplicate_contracts_latest_snapshot(self) -> None:
        contracts_path = self.fixture.root / "deployments" / "testnet" / "contracts.latest.json"
        contracts = json.loads(contracts_path.read_text(encoding="utf-8"))
        contracts["contracts"].append(dict(contracts["contracts"][0]))
        write_json(contracts_path, contracts)

        environment = self.state.load_environment("testnet")

        self.assertEqual(len(environment["contracts"]), 1)
        self.assertEqual(environment["contracts"][0]["evidence_source"], "deploy_record")

    def test_load_environment_ignores_stale_and_bundle_deploy_records(self) -> None:
        environment_path = self.fixture.root / "deployments" / "testnet"
        write_json(
            environment_path / "bridge.sccp_bridge.deploy.json",
            {
                "generated_at": "20260406T000300Z",
                "contract_key": "bridge.sccp_bridge",
                "environment": "testnet",
                "contract_address": "tairac1stale",
                "deploy_nonce": 99,
                "chain_fingerprint": {
                    "torii_url": "https://taira.sora.org",
                    "chain": "test-chain",
                    "block_1_hash": "stale-block",
                },
            },
        )
        write_json(
            environment_path / "options.series_manager.deploy.json",
            {
                "contract_key": "options.series_manager",
                "environment": "testnet",
                "contract_address": "tairac1stale",
                "deploy_nonce": 99,
            },
        )
        environment = self.state.load_environment("testnet")

        self.assertEqual(environment["contracts"], [])

    def test_load_environment_does_not_recover_chain_from_contracts_snapshot(self) -> None:
        chain_path = self.fixture.root / "deployments" / "testnet" / "chain.latest.json"
        chain_path.unlink()

        environment = self.state.load_environment("testnet")

        self.assertEqual(environment["contracts"], [])

    def test_load_environment_marks_testnet_as_flag_gated(self) -> None:
        state = contract_console.ContractConsoleState(self.fixture.root, {})
        with mock.patch.dict(os.environ, {}, clear=False):
            environment = state.load_environment("testnet")

        self.assertEqual(environment["mutation_policy"]["name"], "testnet")
        self.assertFalse(environment["mutation_policy"]["allowed"])
        self.assertTrue(environment["mutation_policy"]["requires_flag"])
        self.assertEqual(environment["mutation_policy"]["flag"], "SORASWAP_ALLOW_TESTNET_MUTATIONS")

    def test_load_environment_marks_production_as_flag_gated(self) -> None:
        self.fixture.add_environment(
            "production",
            torii_url="https://production.example.invalid",
            contract_address="prodc1bridgefixture",
        )
        state = contract_console.ContractConsoleState(self.fixture.root, {})
        with mock.patch.dict(os.environ, {}, clear=False):
            environment = state.load_environment("production")

        self.assertEqual(environment["mutation_policy"]["name"], "production")
        self.assertFalse(environment["mutation_policy"]["allowed"])
        self.assertTrue(environment["mutation_policy"]["requires_flag"])
        self.assertEqual(environment["mutation_policy"]["flag"], "SORASWAP_ALLOW_PRODUCTION_MUTATIONS")

    def test_mutation_enabled_console_accepts_matching_production_deploy_evidence(self) -> None:
        self.fixture.add_environment(
            "production",
            torii_url="https://production.example.invalid",
            contract_address="prodc1bridgefixture",
        )
        self.fixture.write_completed_deploy_evidence(
            "production",
            contract_address="prodc1bridgefixture",
        )
        state = contract_console.ContractConsoleState(self.fixture.root, {})

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_PRODUCTION_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(state)

        self.assertEqual(issues, [])

    def test_readonly_console_allows_incomplete_public_deploy_evidence(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertEqual(issues, [])

    def test_mutation_enabled_console_rejects_missing_migration_register(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        (self.fixture.root / "docs" / "parity" / "migration_register.md").unlink()

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(any("docs/parity/migration_register.md is missing or empty" in issue for issue in issues))

    def test_mutation_enabled_console_rejects_no_ported_migration_register(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        write_migration_register(
            self.fixture.root,
            rows=[("legacy.reference", "Reference fixture", "reference-only")],
        )

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(any("migration_register.md must contain at least one ported production row" in issue for issue in issues))

    def test_mutation_enabled_console_rejects_non_ported_migration_register_rows(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        write_migration_register(
            self.fixture.root,
            rows=[
                ("bridge.sccp_bridge", "SCCP bridge", "ported"),
                ("launchpad.sale", "Launchpad", "stub"),
            ],
        )

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(any("migration_register.md still contains non-ported production rows" in issue for issue in issues))

    def test_mutation_enabled_console_rejects_blank_migration_register_status(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        write_migration_register(
            self.fixture.root,
            rows=[
                ("bridge.sccp_bridge", "SCCP bridge", "ported"),
                ("launchpad.sale", "Launchpad", ""),
            ],
        )

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(any("migration_register.md still contains non-ported production rows" in issue for issue in issues))
        self.assertTrue(any("Launchpad" in issue for issue in issues))

    def test_mutation_enabled_console_rejects_missing_public_deploy_evidence(self) -> None:
        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(any("missing deployments/testnet/deploy.latest.json" in issue for issue in issues))

    def test_mutation_enabled_console_accepts_matching_public_deploy_evidence(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertEqual(issues, [])

    def test_mutation_enabled_console_rejects_sensitive_core_public_evidence(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        environment = self.fixture.root / "deployments" / "testnet"

        chain_path = environment / "chain.latest.json"
        chain = json.loads(chain_path.read_text(encoding="utf-8"))
        chain["diagnostics"] = "chain sample retained at /Users/operator/dev/soraswap/tmp/chain.log"
        write_json(chain_path, chain)

        preflight_path = environment / "preflight.latest.json"
        preflight = json.loads(preflight_path.read_text(encoding="utf-8"))
        preflight["diagnostics"] = "preflight failed with private_key=802620CORESECRET"
        write_json(preflight_path, preflight)

        deploy_path = environment / "deploy.latest.json"
        deploy = json.loads(deploy_path.read_text(encoding="utf-8"))
        deploy["diagnostics"] = "deploy failed with authorization: Bearer deploy-token-secret"
        write_json(deploy_path, deploy)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        serialized_issues = json.dumps(issues)
        self.assertTrue(
            any("deployments/testnet/chain.latest.json contains raw local path diagnostics" in issue for issue in issues)
        )
        self.assertTrue(
            any(
                "deployments/testnet/preflight.latest.json contains unredacted sensitive diagnostics" in issue
                for issue in issues
            )
        )
        self.assertTrue(
            any(
                "deployments/testnet/deploy.latest.json contains unredacted sensitive diagnostics" in issue
                for issue in issues
            )
        )
        self.assertNotIn("/Users/operator/dev/soraswap", serialized_issues)
        self.assertNotIn("802620CORESECRET", serialized_issues)
        self.assertNotIn("deploy-token-secret", serialized_issues)

    def test_mutation_enabled_console_rejects_missing_public_readiness_evidence(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        environment = self.fixture.root / "deployments" / "testnet"
        (environment / "preflight.latest.json").unlink()
        (environment / "nested_call_probe.latest.json").unlink()

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(any("missing deployments/testnet/preflight.latest.json" in issue for issue in issues))
        self.assertTrue(any("missing deployments/testnet/nested_call_probe.latest.json" in issue for issue in issues))

    def test_mutation_enabled_console_rejects_blocked_public_preflight(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        preflight_path = self.fixture.root / "deployments" / "testnet" / "preflight.latest.json"
        preflight = json.loads(preflight_path.read_text(encoding="utf-8"))
        preflight["status"] = "blocked"
        preflight["blockers"] = ["fixture blocker"]
        write_json(preflight_path, preflight)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(any("preflight.latest.json is not ready for the current chain" in issue for issue in issues))

    def test_mutation_enabled_console_rejects_mcp_http_200_without_enabled_tool_metadata(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        preflight_path = self.fixture.root / "deployments" / "testnet" / "preflight.latest.json"
        preflight = json.loads(preflight_path.read_text(encoding="utf-8"))
        preflight["endpoint"]["mcp"] = {
            "enabled": False,
            "metadata_valid": False,
            "protocol_version": "2025-06-18",
            "server_name": "iroha-torii-mcp",
            "server_version": "0.0.0-dev",
            "tool_count": 0,
            "toolset_version": "",
        }
        write_json(preflight_path, preflight)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(any("preflight.latest.json is not ready for the current chain" in issue for issue in issues))

    def test_mutation_enabled_console_rejects_invalid_oracle_client_config(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        preflight_path = self.fixture.root / "deployments" / "testnet" / "preflight.latest.json"
        preflight = json.loads(preflight_path.read_text(encoding="utf-8"))
        preflight["environment"]["oracle_client_config_valid"] = False
        write_json(preflight_path, preflight)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(any("preflight.latest.json is not ready for the current chain" in issue for issue in issues))

    def test_mutation_enabled_console_rejects_preflight_health_issues(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        preflight_path = self.fixture.root / "deployments" / "testnet" / "preflight.latest.json"
        preflight = json.loads(preflight_path.read_text(encoding="utf-8"))
        preflight["endpoint"]["health_issues"] = [
            "status endpoint did not return JSON private_key=802620UISECRET "
            "Authorization: Bearer ui-token-secret "
            "https://user:url-secret@node.example.invalid/v1?access_token=query-secret "
            "/Users/operator/dev/soraswap/tmp/ui-health.log"
        ]
        write_json(preflight_path, preflight)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(any("preflight.latest.json is not ready for the current chain" in issue for issue in issues))
        serialized_issues = json.dumps(issues)
        self.assertIn("private_key=[redacted]", serialized_issues)
        self.assertIn("Authorization: Bearer [redacted]", serialized_issues)
        self.assertIn("https://[redacted]@node.example.invalid/v1?access_token=[redacted]", serialized_issues)
        self.assertIn("[local-path]/ui-health.log", serialized_issues)
        self.assertNotIn("802620UISECRET", serialized_issues)
        self.assertNotIn("ui-token-secret", serialized_issues)
        self.assertNotIn("url-secret", serialized_issues)
        self.assertNotIn("query-secret", serialized_issues)
        self.assertNotIn("/Users/operator/dev/soraswap", serialized_issues)

    def test_mutation_enabled_console_rejects_preflight_missing_health_snapshots(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        preflight_path = self.fixture.root / "deployments" / "testnet" / "preflight.latest.json"
        preflight = json.loads(preflight_path.read_text(encoding="utf-8"))
        preflight["status"] = "ready"
        preflight["blockers"] = []
        preflight["warnings"] = []
        preflight["endpoint"]["health_issues"] = []
        del preflight["endpoint"]["health"]
        write_json(preflight_path, preflight)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(any("preflight.latest.json is not ready for the current chain" in issue for issue in issues))
        self.assertTrue(
            any("preflight.latest.json status endpoint health snapshot is not JSON-ready" in issue for issue in issues)
        )
        self.assertTrue(
            any("preflight.latest.json sumeragi endpoint health snapshot is not JSON-ready" in issue for issue in issues)
        )

    def test_mutation_enabled_console_rejects_unsupported_nested_call_probe(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        probe_path = self.fixture.root / "deployments" / "testnet" / "nested_call_probe.latest.json"
        probe = json.loads(probe_path.read_text(encoding="utf-8"))
        probe["supported"] = False
        probe["summary"] = "fixture nested-call blocker"
        write_json(probe_path, probe)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(
            any("nested_call_probe.latest.json is not supported: fixture nested-call blocker" in issue for issue in issues)
        )

    def test_mutation_enabled_console_rejects_preflight_without_current_nested_probe(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        preflight_path = self.fixture.root / "deployments" / "testnet" / "preflight.latest.json"
        preflight = json.loads(preflight_path.read_text(encoding="utf-8"))
        preflight["nested_call_probe"]["matches_current_chain"] = False
        write_json(preflight_path, preflight)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(any("preflight.latest.json is not ready for the current chain" in issue for issue in issues))

    def test_mutation_enabled_console_rejects_stale_public_preflight_probe(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        preflight_path = self.fixture.root / "deployments" / "testnet" / "preflight.latest.json"
        preflight = json.loads(preflight_path.read_text(encoding="utf-8"))
        preflight["generated_at"] = "20260406T000030Z"
        write_json(preflight_path, preflight)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(any("preflight.latest.json is older than nested_call_probe.latest.json" in issue for issue in issues))

    def test_mutation_enabled_console_rejects_wrong_environment_public_deploy_evidence(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        environment = self.fixture.root / "deployments" / "testnet"
        for name in (
            "chain.latest.json",
            "contracts.latest.json",
            "deploy.latest.json",
            "bridge.sccp_bridge.deploy.json",
        ):
            path = environment / name
            payload = json.loads(path.read_text(encoding="utf-8"))
            payload["environment"] = "production"
            write_json(path, payload)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(any("chain.latest.json does not identify selected environment testnet" in issue for issue in issues))
        self.assertTrue(any("contracts.latest.json does not identify selected environment testnet" in issue for issue in issues))
        self.assertTrue(any("deploy.latest.json does not identify selected environment testnet" in issue for issue in issues))
        self.assertTrue(
            any("bridge.sccp_bridge.deploy.json does not identify selected environment testnet" in issue for issue in issues)
        )

    def test_mutation_enabled_console_rejects_missing_required_contract_snapshot(self) -> None:
        (self.fixture.root / "contracts" / "n3x").mkdir(parents=True, exist_ok=True)
        (self.fixture.root / "contracts" / "n3x" / "n3x_hub.ko").write_text(
            "// fixture n3x contract\n",
            encoding="utf-8",
        )
        self.fixture.write_completed_deploy_evidence("testnet")

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(
            any("contracts.latest.json is missing required contract snapshots: n3x.n3x_hub" in issue for issue in issues)
        )

    def test_mutation_enabled_console_rejects_duplicate_contract_snapshot(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        contracts_path = self.fixture.root / "deployments" / "testnet" / "contracts.latest.json"
        contracts = json.loads(contracts_path.read_text(encoding="utf-8"))
        contracts["contracts"].append(dict(contracts["contracts"][0]))
        write_json(contracts_path, contracts)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(
            any(
                "contracts.latest.json contains duplicate contract snapshots: bridge.sccp_bridge" in issue
                for issue in issues
            )
        )

    def test_mutation_enabled_console_rejects_missing_per_contract_deploy_evidence(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet", include_contract_record=False)
        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(any("missing deployments/testnet/bridge.sccp_bridge.deploy.json" in issue for issue in issues))

    def test_mutation_enabled_console_rejects_untimestamped_public_deploy_evidence(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        environment = self.fixture.root / "deployments" / "testnet"
        for name in (
            "chain.latest.json",
            "contracts.latest.json",
            "deploy.latest.json",
            "bridge.sccp_bridge.deploy.json",
        ):
            path = environment / name
            payload = json.loads(path.read_text(encoding="utf-8"))
            payload.pop("generated_at", None)
            write_json(path, payload)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(any("chain.latest.json is missing generated_at" in issue for issue in issues))
        self.assertTrue(any("contracts.latest.json is missing generated_at" in issue for issue in issues))
        self.assertTrue(any("deploy.latest.json is missing generated_at" in issue for issue in issues))
        self.assertTrue(
            any("bridge.sccp_bridge.deploy.json is missing generated_at" in issue for issue in issues)
        )

    def test_mutation_enabled_console_rejects_incomplete_contracts_latest(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        contracts_path = self.fixture.root / "deployments" / "testnet" / "contracts.latest.json"
        contracts = json.loads(contracts_path.read_text(encoding="utf-8"))
        contracts["status"] = "partial"
        write_json(contracts_path, contracts)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(any("contracts.latest.json is not completed" in issue for issue in issues))

    def test_mutation_enabled_console_rejects_incomplete_deploy_phase(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        deploy_path = self.fixture.root / "deployments" / "testnet" / "deploy.latest.json"
        deploy = json.loads(deploy_path.read_text(encoding="utf-8"))
        deploy["phases"]["bootstrap_contract_state"]["status"] = "skipped"
        write_json(deploy_path, deploy)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(any("deploy.latest.json has incomplete phases: bootstrap_contract_state" in issue for issue in issues))

    def test_mutation_enabled_console_rejects_deploy_preflight_debug_bypass(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        deploy_path = self.fixture.root / "deployments" / "testnet" / "deploy.latest.json"
        deploy = json.loads(deploy_path.read_text(encoding="utf-8"))
        deploy["phases"]["preflight"]["detail"]["signer_ready_check"]["debug_bypass_env"] = (
            "SORASWAP_SKIP_PUBLIC_SIGNER_READY_CHECK"
        )
        write_json(deploy_path, deploy)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(
            any("deploy.latest.json preflight did not prove signer readiness without debug bypass" in issue for issue in issues)
        )

    def test_mutation_enabled_console_rejects_chain_snapshot_missing_torii_url(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        chain_path = self.fixture.root / "deployments" / "testnet" / "chain.latest.json"
        chain = json.loads(chain_path.read_text(encoding="utf-8"))
        chain.pop("torii_url", None)
        write_json(chain_path, chain)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(any("chain.latest.json must include torii_url" in issue for issue in issues))

    def test_mutation_enabled_console_rejects_wrong_environment_contract_snapshot(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        contracts_path = self.fixture.root / "deployments" / "testnet" / "contracts.latest.json"
        contracts = json.loads(contracts_path.read_text(encoding="utf-8"))
        contracts["contracts"][0]["environment"] = "production"
        write_json(contracts_path, contracts)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(
            any(
                "contracts.latest.json contains contract snapshots for the wrong environment: bridge.sccp_bridge"
                in issue
                for issue in issues
            )
        )

    def test_mutation_enabled_console_rejects_stale_contract_snapshot_key(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        contracts_path = self.fixture.root / "deployments" / "testnet" / "contracts.latest.json"
        contracts = json.loads(contracts_path.read_text(encoding="utf-8"))
        contracts["contracts"].append(
            {
                "contract_key": "options.series_manager",
                "environment": "testnet",
                "contract_address": "tairac1stale",
                "deploy_nonce": 99,
            }
        )
        write_json(contracts_path, contracts)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(
            any(
                "contracts.latest.json contains stale or unknown contract snapshots: options.series_manager" in issue
                for issue in issues
            )
        )

    def test_mutation_enabled_console_rejects_stale_extra_deploy_record(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        write_json(
            self.fixture.root / "deployments" / "testnet" / "options.series_manager.deploy.json",
            {
                "generated_at": "20260406T000300Z",
                "contract_key": "options.series_manager",
                "environment": "testnet",
                "contract_address": "tairac1stale",
                "deploy_nonce": 99,
                "chain_fingerprint": {
                    "torii_url": "https://taira.sora.org",
                    "chain": "test-chain",
                    "block_1_hash": "block-1",
                },
            },
        )

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(
            any("options.series_manager.deploy.json is stale or unknown for current contracts/" in issue for issue in issues)
        )

    def test_mutation_enabled_console_rejects_stale_extra_manifest(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        write_json(
            self.fixture.root / "deployments" / "testnet" / "options.series_manager.manifest.json",
            {
                "code_hash": canonical_hash_literal("9" * 64),
                "abi_hash": canonical_hash_literal("0" * 64),
                "entrypoints": [],
            },
        )

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(
            any("options.series_manager.manifest.json is stale or unknown for current contracts/" in issue for issue in issues)
        )

    def test_mutation_enabled_console_rejects_missing_deploy_nonce(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        deploy_record_path = self.fixture.root / "deployments" / "testnet" / "bridge.sccp_bridge.deploy.json"
        deploy_record = json.loads(deploy_record_path.read_text(encoding="utf-8"))
        deploy_record.pop("deploy_nonce")
        deploy_record["response"].pop("deploy_nonce")
        write_json(deploy_record_path, deploy_record)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(
            any(
                "bridge.sccp_bridge.deploy.json deploy nonce is missing from contracts.latest.json or the deployment record"
                in issue
                for issue in issues
            )
        )

    def test_mutation_enabled_console_rejects_recovered_alias_deploy_strategy(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        deploy_record_path = self.fixture.root / "deployments" / "testnet" / "bridge.sccp_bridge.deploy.json"
        deploy_record = json.loads(deploy_record_path.read_text(encoding="utf-8"))
        deploy_record["deploy_strategy"] = "recovered_from_alias_resolve"
        write_json(deploy_record_path, deploy_record)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(
            any("bridge.sccp_bridge.deploy.json does not use a current deploy strategy" in issue for issue in issues)
        )

    def test_mutation_enabled_console_rejects_manifest_hash_mismatch(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        manifest_path = self.fixture.root / "deployments" / "testnet" / "bridge.sccp_bridge.manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["code_hash"] = canonical_hash_literal("f" * 64)
        write_json(manifest_path, manifest)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(
            any("bridge.sccp_bridge.manifest.json hashes do not match contracts.latest.json" in issue for issue in issues)
        )

    def test_mutation_enabled_console_rejects_manifest_missing_generated_at(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        manifest_path = self.fixture.root / "deployments" / "testnet" / "bridge.sccp_bridge.manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest.pop("generated_at")
        write_json(manifest_path, manifest)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(
            any("bridge.sccp_bridge.manifest.json is missing generated_at" in issue for issue in issues)
        )

    def test_mutation_enabled_console_rejects_manifest_contract_key_mismatch(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        manifest_path = self.fixture.root / "deployments" / "testnet" / "bridge.sccp_bridge.manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["contract_key"] = "bridge.other"
        write_json(manifest_path, manifest)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(
            any("bridge.sccp_bridge.manifest.json manifest contract_key does not match filename" in issue for issue in issues)
        )

    def test_mutation_enabled_console_rejects_failed_deploy_response_evidence(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        deploy_record_path = self.fixture.root / "deployments" / "testnet" / "bridge.sccp_bridge.deploy.json"
        deploy_record = json.loads(deploy_record_path.read_text(encoding="utf-8"))
        deploy_record["response"]["ok"] = False
        write_json(deploy_record_path, deploy_record)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(
            any("bridge.sccp_bridge.deploy.json does not include successful deploy response evidence" in issue for issue in issues)
        )

    def test_mutation_enabled_console_rejects_stale_per_contract_deploy_evidence(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet", contract_address="tairac1oldbridge")
        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(
            any("bridge.sccp_bridge.deploy.json address does not match contracts.latest.json" in issue for issue in issues)
        )

    def test_mutation_enabled_console_rejects_stale_contract_snapshot(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        write_json(
            self.fixture.root / "deployments" / "testnet" / "contracts.latest.json",
            {
                "generated_at": "20260406T000000Z",
                "chain_fingerprint": {
                    "torii_url": "https://old-taira.example.invalid",
                    "chain": "old-test-chain",
                    "block_1_hash": "old-block-1",
                },
                "contracts": [],
            },
        )

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(any("contracts.latest.json does not match chain.latest.json" in issue for issue in issues))

    def test_mutation_enabled_console_rejects_copied_torii_evidence(self) -> None:
        self.fixture.write_completed_deploy_evidence("testnet")
        environment = self.fixture.root / "deployments" / "testnet"
        for name in (
            "contracts.latest.json",
            "deploy.latest.json",
            "bridge.sccp_bridge.deploy.json",
        ):
            path = environment / name
            payload = json.loads(path.read_text(encoding="utf-8"))
            payload["chain_fingerprint"]["torii_url"] = "https://different-taira.example.invalid"
            write_json(path, payload)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(self.state)

        self.assertTrue(any("contracts.latest.json does not match chain.latest.json" in issue for issue in issues))
        self.assertTrue(any("deploy.latest.json does not match chain.latest.json" in issue for issue in issues))
        self.assertTrue(
            any("bridge.sccp_bridge.deploy.json does not match chain.latest.json" in issue for issue in issues)
        )

    def test_bridge_inspect_requires_authority(self) -> None:
        with RunningServer(self.state) as server:
            status, payload = request_json(
                f"{server.base_url}/api/bridge/inspect",
                {"environment": "testnet"},
            )
        self.assertEqual(status, 400)
        self.assertFalse(payload["ok"])
        self.assertIn("no authority available for bridge inspection", payload["error"])

    def test_bridge_inspect_rejects_explicit_sensitive_key_in_browser_json(self) -> None:
        with mock.patch.object(contract_console, "proxy_torii_request") as proxy:
            with RunningServer(self.state) as server:
                status, payload = request_json(
                    f"{server.base_url}/api/bridge/inspect",
                    {
                        "environment": "testnet",
                        "authority": "i105fixture",
                        "asset_key": "xor",
                        "secret": "should-not-be-forwarded",
                    },
                )

        self.assertEqual(status, 400)
        self.assertFalse(payload["ok"])
        self.assertIn("browser JSON must not include private keys", payload["error"])
        proxy.assert_not_called()

    def test_bridge_inspect_aggregates_requested_views(self) -> None:
        calls: list[tuple[str, dict]] = []
        state = contract_console.ContractConsoleState(
            self.fixture.root,
            {"testnet": make_signer()},
        )

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json", canonical_signer=None):
            calls.append((path, payload))
            body = {
                "ok": True,
                "view": payload["entrypoint"],
                "payload": payload.get("payload"),
            }
            return 200, json.dumps(body), "application/json"

        with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
            with RunningServer(state) as server:
                status, payload = request_json(
                    f"{server.base_url}/api/bridge/inspect",
                    {
                        "environment": "testnet",
                        "authority": "i105fixture",
                        "asset_key": "xor",
                        "route": "ton_testnet",
                        "transfer": "xor_ton_1",
                        "message_id": "msg_1",
                    },
                )

        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["contract"]["contract_key"], "bridge.sccp_bridge")
        self.assertEqual(len(payload["views"]), 11)
        self.assertEqual(
            [entry["entrypoint"] for entry in payload["views"]],
            [
                "listing_config",
                "mirror_asset",
                "asset_config",
                "asset_vault_bound",
                "asset_vault_account",
                "mirror_route",
                "route_config",
                "route_provenance",
                "mirror_outbound",
                "outbound_config",
                "inbound_consumed",
            ],
        )
        self.assertEqual(len(calls), 11)
        self.assertTrue(all(path == "/v1/contracts/view" for path, _ in calls))

    def test_build_signer_bindings_auto_discovers_default_testnet_config(self) -> None:
        self.fixture.write_signer_config(
            "config/testnet/taira.client.toml",
            torii_url="https://taira.sora.org/",
            public_key="ed0120fixture",
            private_key="802620fixture",
        )
        with mock.patch.object(
            contract_console,
            "derive_authority_from_public_key",
            return_value=("i105fixture", None),
        ):
            signers = contract_console.build_signer_bindings(
                self.fixture.root,
                {},
                {},
                auto_discover=True,
            )

        self.assertIn("testnet", signers)
        signer = signers["testnet"]
        self.assertEqual(signer.source, "auto")
        self.assertEqual(signer.authority, "i105fixture")
        self.assertTrue(signer.can_call)

    def test_explicit_signer_config_requires_account_credentials(self) -> None:
        config_path = self.fixture.root / "config" / "testnet" / "taira.client.toml"
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text(
            "\n".join(
                [
                    'chain = "fixture-chain"',
                    f'network_id = "{TAIRA_NETWORK_ID}"',
                    'torii_url = "https://taira.sora.org/"',
                    'public_key = "ed0120flat"',
                    'private_key = "802620flat"',
                    "",
                    "[account]",
                    'domain = "fixture.universal"',
                    "",
                ]
            ),
            encoding="utf-8",
        )
        config_path.chmod(0o600)

        with self.assertRaisesRegex(
            ValueError,
            "account .* requires non-empty public_key and private_key",
        ):
            contract_console.build_signer_bindings(
                self.fixture.root,
                {"testnet": str(config_path)},
                {},
                auto_discover=False,
            )

    def test_explicit_signer_config_requires_canonical_network_id(self) -> None:
        config_path = self.fixture.write_signer_config(
            "config/testnet/taira.client.toml",
            torii_url="https://taira.sora.org/",
            public_key=BRIDGE_TEST_PUBLIC_KEY,
            private_key=BRIDGE_TEST_PRIVATE_KEY,
        )
        config_path.write_text(
            config_path.read_text(encoding="utf-8").replace(
                f'network_id = "{TAIRA_NETWORK_ID}"\n',
                "",
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(ValueError, "network_id must be canonical"):
            contract_console.build_signer_bindings(
                self.fixture.root,
                {"testnet": str(config_path)},
                {},
                auto_discover=False,
            )

    def test_authority_override_must_match_key_derived_authority(self) -> None:
        config_path = self.fixture.write_signer_config(
            "config/testnet/taira.client.toml",
            torii_url="https://taira.sora.org/",
            public_key=BRIDGE_TEST_PUBLIC_KEY,
            private_key=BRIDGE_TEST_PRIVATE_KEY,
        )
        with mock.patch.object(
            contract_console,
            "derive_authority_from_public_key",
            return_value=("i105-derived", None),
        ):
            with self.assertRaisesRegex(ValueError, "does not match"):
                contract_console.build_signer_bindings(
                    self.fixture.root,
                    {"testnet": str(config_path)},
                    {"testnet": "i105-override"},
                    auto_discover=False,
                )

    def test_build_signer_bindings_ignores_placeholder_default_config(self) -> None:
        self.fixture.write_signer_config(
            "config/testnet/taira.client.toml",
            torii_url="https://taira.sora.org/",
            public_key="ed0120replaceme",
            private_key="802620fixture",
        )
        with mock.patch.object(contract_console, "derive_authority_from_public_key") as derive_authority:
            signers = contract_console.build_signer_bindings(
                self.fixture.root,
                {},
                {},
                auto_discover=True,
            )

        self.assertEqual(signers, {})
        derive_authority.assert_not_called()

    def test_build_signer_bindings_ignores_default_config_with_placeholder_private_key(self) -> None:
        self.fixture.write_signer_config(
            "config/testnet/taira.client.toml",
            torii_url="https://taira.sora.org/",
            public_key="ed0120fixture",
            private_key="802620changeme",
        )
        with mock.patch.object(contract_console, "derive_authority_from_public_key") as derive_authority:
            signers = contract_console.build_signer_bindings(
                self.fixture.root,
                {},
                {},
                auto_discover=True,
            )

        self.assertEqual(signers, {})
        derive_authority.assert_not_called()

    def test_build_signer_bindings_ignores_public_default_config_with_reserved_endpoint(self) -> None:
        self.fixture.write_signer_config(
            "config/testnet/taira.client.toml",
            torii_url="https://example.invalid/",
            public_key="ed0120fixture",
            private_key="802620fixture",
        )
        with mock.patch.object(contract_console, "derive_authority_from_public_key") as derive_authority:
            signers = contract_console.build_signer_bindings(
                self.fixture.root,
                {},
                {},
                auto_discover=True,
            )

        self.assertEqual(signers, {})

    def test_build_signer_bindings_ignores_public_default_config_without_torii_url(self) -> None:
        self.fixture.write_signer_config(
            "config/testnet/taira.client.toml",
            torii_url=None,
            public_key="ed0120fixture",
            private_key="802620fixture",
        )

        with mock.patch.object(contract_console, "REPO_ROOT", self.fixture.root):
            with mock.patch.object(contract_console, "derive_authority_from_public_key") as derive:
                signers = contract_console.build_signer_bindings(
                    self.fixture.root,
                    {},
                    {},
                    auto_discover=True,
                )

        self.assertEqual(signers, {})
        derive.assert_not_called()

    def test_explicit_placeholder_signer_config_warns_and_cannot_call(self) -> None:
        config_path = self.fixture.write_signer_config(
            "private/sensitive/testnet/taira.client.toml",
            torii_url="https://example.invalid/",
            public_key="ed0120replace_me",
            private_key="802620TODO",
        )
        with mock.patch.object(contract_console, "derive_authority_from_public_key") as derive_authority:
            signers = contract_console.build_signer_bindings(
                self.fixture.root,
                {"testnet": str(config_path)},
                {},
                auto_discover=False,
            )

        derive_authority.assert_not_called()
        signer = signers["testnet"]
        self.assertTrue(signer.configured)
        self.assertFalse(signer.can_call)
        self.assertIsNone(signer.public_key)
        self.assertIsNone(signer.private_key)
        self.assertIsNone(signer.torii_url)
        self.assertTrue(any("public key" in warning for warning in signer.warnings))
        self.assertTrue(any("private key" in warning for warning in signer.warnings))
        self.assertTrue(any("torii_url" in warning for warning in signer.warnings))
        serialized_warnings = json.dumps(signer.warnings)
        self.assertIn("taira.client.toml", serialized_warnings)
        self.assertNotIn(str(config_path.parent), serialized_warnings)
        self.assertNotIn("private/sensitive", serialized_warnings)

    def test_explicit_public_signer_config_warns_and_ignores_reserved_torii_url(self) -> None:
        config_path = self.fixture.write_signer_config(
            "config/testnet/taira.client.toml",
            torii_url="https://example.invalid/",
            public_key="ed0120fixture",
            private_key="802620fixture",
        )
        with mock.patch.object(
            contract_console,
            "derive_authority_from_public_key",
            return_value=("i105fixture", None),
        ):
            signers = contract_console.build_signer_bindings(
                self.fixture.root,
                {"testnet": str(config_path)},
                {},
                auto_discover=False,
            )

        signer = signers["testnet"]
        self.assertTrue(signer.can_call)
        self.assertIsNone(signer.torii_url)
        self.assertTrue(any("torii_url" in warning for warning in signer.warnings))

    def test_explicit_public_signer_config_without_torii_url_uses_deployment_endpoint(self) -> None:
        config_path = self.fixture.write_signer_config(
            "config/testnet/taira.client.toml",
            torii_url=None,
            public_key="ed0120fixture",
            private_key="802620fixture",
        )

        with mock.patch.object(
            contract_console,
            "derive_authority_from_public_key",
            return_value=("i105fixture", None),
        ):
            signers = contract_console.build_signer_bindings(
                self.fixture.root,
                {"testnet": str(config_path)},
                {},
                auto_discover=True,
            )

        signer = signers["testnet"]
        self.assertTrue(signer.can_call)
        self.assertIsNone(signer.torii_url)
        self.assertFalse(any("torii_url" in warning for warning in signer.warnings))

    def test_build_signer_bindings_auto_discovers_default_production_config(self) -> None:
        self.fixture.write_signer_config(
            "config/production/production.client.toml",
            torii_url="https://production.sora.org/",
            public_key="ed0120fixture",
            private_key="802620fixture",
        )
        with mock.patch.object(
            contract_console,
            "derive_authority_from_public_key",
            return_value=("i105production", None),
        ):
            signers = contract_console.build_signer_bindings(
                self.fixture.root,
                {},
                {},
                auto_discover=True,
            )

        self.assertIn("production", signers)
        signer = signers["production"]
        self.assertEqual(signer.source, "auto")
        self.assertEqual(signer.authority, "i105production")
        self.assertTrue(signer.can_call)

    def test_infer_network_prefix_prefers_explicit_testnet_environment(self) -> None:
        with mock.patch.dict(os.environ, {"SORASWAP_ADDRESS_NETWORK_PREFIX": "753"}, clear=False):
            prefix = contract_console.infer_network_prefix("testnet")

        self.assertEqual(prefix, contract_console.TESTNET_NETWORK_PREFIX)

    def test_infer_network_prefix_prefers_explicit_production_environment_over_taira_url(self) -> None:
        with mock.patch.dict(
            os.environ,
            {
                "SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT": "777",
                "SORASWAP_ADDRESS_NETWORK_PREFIX": "753",
            },
            clear=False,
        ):
            prefix = contract_console.infer_network_prefix("production")

        self.assertEqual(prefix, "777")

    def test_infer_network_prefix_without_environment_ignores_taira_url(self) -> None:
        with mock.patch.dict(os.environ, {"SORASWAP_ADDRESS_NETWORK_PREFIX": "753"}, clear=False):
            prefix = contract_console.infer_network_prefix(None)

        self.assertEqual(prefix, "753")

    def test_missing_iroha_cli_warning_uses_relative_path(self) -> None:
        with mock.patch.object(contract_console, "REPO_ROOT", self.fixture.root / "soraswap"):
            authority, warning = contract_console.derive_authority_from_public_key("ed0120fixture", "testnet")

        self.assertIsNone(authority)
        self.assertEqual(warning, "missing iroha CLI at ../iroha/target/debug/iroha")
        self.assertNotIn(str(self.fixture.root), warning or "")

    def test_warning_path_redaction_handles_runtime_and_user_paths(self) -> None:
        warning = contract_console.redact_local_warning_paths(
            "failed using /private/tmp/soraswap-console.XYZ/request.json "
            "and /var/folders/7l/work/T/soraswap-log.ABC123 "
            "with /Users/operator/dev/soraswap/config/testnet/taira.client.toml "
            "but not https://taira.sora.org/tmp/not-local"
        )

        self.assertIn("[runtime-path]/request.json", warning)
        self.assertIn("[runtime-path]/soraswap-log.ABC123", warning)
        self.assertIn("[local-path]/taira.client.toml", warning)
        self.assertIn("https://taira.sora.org/tmp/not-local", warning)
        self.assertNotIn("/private/tmp", warning)
        self.assertNotIn("/var/folders", warning)
        self.assertNotIn("/Users/operator", warning)

    def test_build_signer_bindings_can_disable_auto_discovery(self) -> None:
        self.fixture.write_signer_config(
            "config/testnet/taira.client.toml",
            torii_url="https://taira.sora.org/",
            public_key="ed0120fixture",
            private_key="802620fixture",
        )
        signers = contract_console.build_signer_bindings(
            self.fixture.root,
            {},
            {},
            auto_discover=False,
        )
        self.assertEqual(signers, {})

    def test_environment_rejects_signer_origin_that_differs_from_deployment(self) -> None:
        self.fixture.write_signer_config(
            "config/testnet/taira.client.toml",
            torii_url="https://different.taira.sora.org/",
            public_key="ed0120fixture",
            private_key="802620fixture",
        )
        with mock.patch.object(
            contract_console,
            "derive_authority_from_public_key",
            return_value=("i105fixture", None),
        ):
            signers = contract_console.build_signer_bindings(
                self.fixture.root,
                {},
                {},
                auto_discover=True,
            )
        state = contract_console.ContractConsoleState(self.fixture.root, signers)
        environment = state.load_environment("testnet")
        self.assertIsNone(environment["torii_url"])
        self.assertEqual(environment["torii_url_source"], "deployment")
        self.assertFalse(environment["torii_binding_valid"])
        self.assertEqual(environment["signer"]["torii_url"], "https://different.taira.sora.org")
        self.assertTrue(any("origin differs" in warning for warning in environment["signer"]["warnings"]))

    def test_catalog_exposes_signer_source_and_warnings(self) -> None:
        signer = make_signer(
            source="auto",
            warnings=[
                "example warning",
                "failed with /private/tmp/soraswap-console.XYZ/request.json",
            ],
        )
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        catalog = state.load_catalog()

        self.assertEqual(len(catalog["environments"]), 1)
        environment = catalog["environments"][0]
        self.assertEqual(environment["signer"]["source"], "auto")
        self.assertTrue(environment["signer"]["configured"])
        self.assertIn("example warning", environment["signer"]["warnings"][0])
        serialized = json.dumps(environment["signer"]["warnings"])
        self.assertIn("[runtime-path]/request.json", serialized)
        self.assertNotIn("/private/tmp", serialized)

    def test_catalog_redacts_signer_config_secrets_and_parent_path(self) -> None:
        signer = make_signer(
            config_path=Path("/tmp/soraswap-secret/signers/taira.client.toml"),
            private_key="802620fixture",
            source="cli:/tmp/soraswap-secret/signers/taira.client.toml",
        )
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        catalog = state.load_catalog()
        snapshot = catalog["environments"][0]["signer"]

        self.assertEqual(catalog["repo_name"], self.fixture.root.name)
        self.assertEqual(catalog["repo_root"], self.fixture.root.name)
        self.assertEqual(snapshot["config_path"], "taira.client.toml")
        self.assertEqual(snapshot["source"], "cli:taira.client.toml")
        serialized = json.dumps(catalog)
        self.assertNotIn(str(self.fixture.root.parent), serialized)
        self.assertNotIn("/tmp/soraswap-secret", serialized)
        self.assertNotIn("802620fixture", serialized)
        self.assertNotIn("user", serialized)
        self.assertNotIn("pass", serialized)
        self.assertTrue(snapshot["basic_auth_configured"])

    def test_sccp_proxy_routes_return_capabilities_and_typed_registry(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        calls: list[tuple[str, str, dict | None]] = []

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json", canonical_signer=None):
            self.assertEqual(torii_url, "https://taira.sora.org")
            self.assertEqual(method, "GET")
            self.assertIsNone(payload)
            calls.append((path, torii_url, query))
            if path == "/v1/sccp/capabilities":
                return 200, json.dumps({"version": 1, "registry_path": "/v1/sccp/registry", "proof_submit_path": "/v1/bridge/proofs/submit"}), "application/json"
            if path == "/v1/sccp/registry":
                return 200, json.dumps({"version": 1, "lanes": [{"routes": []}]}), "application/json"
            raise AssertionError(f"unexpected path: {path}")

        with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
            with RunningServer(state) as server:
                capabilities_status, capabilities = request_json(
                    f"{server.base_url}/api/sccp/capabilities?environment=testnet"
                )
                registry_status, registry = request_json(
                    f"{server.base_url}/api/sccp/registry?environment=testnet"
                )

        self.assertEqual(capabilities_status, 200)
        self.assertTrue(capabilities["ok"])
        self.assertEqual(capabilities["response_json"]["registry_path"], "/v1/sccp/registry")
        self.assertEqual(capabilities["response_json"]["proof_submit_path"], "/v1/bridge/proofs/submit")
        self.assertEqual(registry_status, 200)
        self.assertTrue(registry["ok"])
        self.assertEqual(registry["response_json"]["version"], 1)
        self.assertEqual([entry[0] for entry in calls], ["/v1/sccp/capabilities", "/v1/sccp/registry"])

    def test_asset_definition_proxy_reencodes_one_selector_segment(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        def fake_proxy(
            torii_url,
            path,
            *,
            method,
            payload,
            query,
            basic_auth,
            timeout,
            accept="application/json",
            canonical_signer=None,
        ):
            self.assertEqual(path, "/v1/assets/definitions/xor%23universal")
            self.assertEqual(method, "GET")
            self.assertIsNone(payload)
            self.assertEqual(query, {})
            return 200, json.dumps({
                "id": "6TEAJqbb8oEPmLncoNiMRbLEK6tw",
                "alias": "xor#universal",
                "alias_binding": {"alias": "xor#universal", "status": "permanent"},
                "spec": {"scale": 9},
            }), "application/json"

        with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
            with RunningServer(state) as server:
                status, response = request_json(
                    f"{server.base_url}/api/assets/definitions/xor%23universal"
                    "?environment=testnet&private_key=drop"
                )

        self.assertEqual(status, 200)
        self.assertTrue(response["ok"])
        self.assertEqual(response["response_json"]["spec"]["scale"], 9)

    def test_asset_definition_proxy_rejects_path_escape_selector(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        with mock.patch.object(contract_console, "proxy_torii_request") as proxy:
            with RunningServer(state) as server:
                status, response = request_json(
                    f"{server.base_url}/api/assets/definitions/xor%2Funiversal?environment=testnet"
                )

        self.assertEqual(status, 400)
        self.assertFalse(response["ok"])
        self.assertIn("one path segment", response["error"])
        proxy.assert_not_called()

    def test_message_bundle_and_proof_request_proxy_routes_pass_through(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        message_id = "ab" * 32
        observed_paths: list[str] = []

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json", canonical_signer=None):
            self.assertEqual(method, "GET")
            self.assertEqual(query, {})
            observed_paths.append(path)
            return 200, json.dumps({"path": path, "message_id": message_id}), "application/json"

        with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
            with RunningServer(state) as server:
                routes = [
                    ("bundle", f"/api/sccp/proofs/message/{message_id}"),
                    ("proof_request", f"/api/sccp/proof-requests/{message_id}"),
                ]
                payloads = {}
                for label, route in routes:
                    status, payload = request_json(f"{server.base_url}{route}?environment=testnet")
                    self.assertEqual(status, 200)
                    self.assertTrue(payload["ok"])
                    payloads[label] = payload

        self.assertEqual(
            observed_paths,
            [
                f"/v1/sccp/proofs/message/{message_id}",
                f"/v1/sccp/proof-requests/{message_id}",
            ],
        )
        self.assertEqual(payloads["bundle"]["response_json"]["message_id"], message_id)
        self.assertEqual(
            payloads["proof_request"]["response_json"]["path"],
            f"/v1/sccp/proof-requests/{message_id}",
        )

    def test_message_lookup_proxy_rejects_unsafe_message_ids(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        with mock.patch.object(contract_console, "proxy_torii_request") as proxy:
            with RunningServer(state) as server:
                routes = [
                    "/api/sccp/proofs/message/path/segment",
                    "/api/sccp/proof-requests/bad%2Fencoded",
                    f"/api/sccp/proofs/message/{'A' * 64}",
                    f"/api/sccp/proof-requests/{'0' * 64}",
                ]
                responses = [
                    request_json(f"{server.base_url}{route}?environment=testnet")
                    for route in routes
                ]

        for status, payload in responses:
            self.assertEqual(status, 400)
            self.assertFalse(payload["ok"])
            self.assertIn("message_id", payload["error"])
        proxy.assert_not_called()

    def test_recent_message_proxy_route_passes_through_query(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        observed_calls: list[tuple[str, dict[str, str]]] = []

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json", canonical_signer=None):
            self.assertEqual(method, "GET")
            observed_calls.append((path, query))
            return 200, json.dumps({"items": [{"message_id_hex": "aa"}]}), "application/json"

        with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
            with RunningServer(state) as server:
                status, payload = request_json(
                    f"{server.base_url}/api/sccp/messages/recent?environment=testnet&limit=7&from=42"
                )

        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertEqual(
            observed_calls,
            [("/v1/sccp/messages/recent", {"limit": "7", "from": "42"})],
        )
        self.assertEqual(payload["response_json"]["items"][0]["message_id_hex"], "aa")

    def test_recent_message_proxy_caps_large_history_windows(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        observed_queries: list[dict[str, str]] = []

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json", canonical_signer=None):
            self.assertEqual(path, "/v1/sccp/messages/recent")
            self.assertEqual(method, "GET")
            observed_queries.append(query)
            return 200, json.dumps({"items": []}), "application/json"

        with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
            with RunningServer(state) as server:
                status, payload = request_json(
                    f"{server.base_url}/api/sccp/messages/recent"
                    "?environment=testnet&limit=100000&from=999999&cursor=drop&private_key=drop"
                )
                invalid_status, invalid_payload = request_json(
                    f"{server.base_url}/api/sccp/messages/recent?environment=testnet&limit=bad&from=-1"
                )

        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertEqual(invalid_status, 400)
        self.assertFalse(invalid_payload["ok"])
        self.assertIn("from must be a positive block height", invalid_payload["error"])
        self.assertEqual(observed_queries, [{"limit": "50", "from": "999999"}])

    def test_read_proxy_rejects_unbounded_raw_queries_before_forwarding(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        too_many_fields = "&".join(
            ["environment=testnet"]
            + [f"k{index}=v" for index in range(contract_console.MAX_BROWSER_QUERY_FIELDS)]
        )
        long_query = "environment=testnet&payload=" + (
            "x" * contract_console.MAX_BROWSER_QUERY_STRING_CHARS
        )

        with mock.patch.object(contract_console, "proxy_torii_request") as proxy:
            with RunningServer(state) as server:
                too_many_status, too_many_payload = request_json(
                    f"{server.base_url}/api/sccp/messages/recent?{too_many_fields}"
                )
                long_status, long_payload = request_json(
                    f"{server.base_url}/api/transactions/history?{long_query}"
                )

        self.assertEqual(too_many_status, 400)
        self.assertFalse(too_many_payload["ok"])
        self.assertIn("too many fields", too_many_payload["error"])
        self.assertEqual(long_status, 400)
        self.assertFalse(long_payload["ok"])
        self.assertIn("query string exceeds", long_payload["error"])
        proxy.assert_not_called()

    def test_bridge_preparation_accepts_current_solana_testnet_profile(self) -> None:
        response = bridge_preparation_response()
        response["counterparty_domain"] = 3
        response["counterparty_chain"] = "solana-testnet"

        prepared = contract_console.validate_bridge_preparation_response(response)

        self.assertEqual(prepared["metadata"]["counterparty_domain"], 3)
        self.assertEqual(prepared["metadata"]["counterparty_chain"], "solana-testnet")

    def test_bridge_proof_submit_uses_exact_two_phase_detached_signing(self) -> None:
        signer = make_signer(
            private_key=BRIDGE_TEST_PRIVATE_KEY,
            public_key=BRIDGE_TEST_PUBLIC_KEY,
        )
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        captured_payloads: list[dict] = []

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json", canonical_signer=None):
            self.assertEqual(path, "/v1/bridge/proofs/submit")
            self.assertEqual(method, "POST")
            captured_payloads.append(payload)
            response = bridge_preparation_response() if len(captured_payloads) == 1 else bridge_submission_response()
            return 200, json.dumps(response), "application/json"

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=False):
            with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
                with RunningServer(state) as server:
                    status, payload = request_json(
                        f"{server.base_url}/api/bridge/proofs/submit",
                        {
                            "environment": "testnet",
                            "destination_proof_b64": BRIDGE_TEST_PROOF_B64,
                        },
                    )

        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["tx_hash_hex"], "ab" * 32)
        self.assertEqual(
            captured_payloads[0],
            {
                "authority": "i105fixture",
                "fee_payment": contract_console.authority_fee_payment_intent(
                    contract_console.DEFAULT_GAS_LIMIT
                ),
                "destination_proof_b64": BRIDGE_TEST_PROOF_B64,
            },
        )
        self.assertEqual(captured_payloads[1]["transaction_payload_b64"], BRIDGE_TEST_TRANSACTION_B64)
        self.assertEqual(captured_payloads[1]["creation_time_ms"], 1_750_000_000_001)
        self.assertEqual(captured_payloads[1]["fee_payment"], captured_payloads[0]["fee_payment"])
        self.assertEqual(captured_payloads[1]["destination_proof_b64"], BRIDGE_TEST_PROOF_B64)
        self.assertEqual(set(captured_payloads[1]), {
            "authority",
            "fee_payment",
            "destination_proof_b64",
            "transaction_payload_b64",
            "signature_b64",
            "creation_time_ms",
        })
        self.assertNotIn("private_key", json.dumps(captured_payloads))
        self.assertTrue(payload["detached_signing"]["transaction_payload_reused_exactly"])
        self.assertFalse(payload["detached_signing"]["private_key_forwarded"])

    def test_bridge_native_message_uses_native_proof_closed_dto(self) -> None:
        signer = make_signer(
            private_key=BRIDGE_TEST_PRIVATE_KEY,
            public_key=BRIDGE_TEST_PUBLIC_KEY,
        )
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        captured_payloads: list[dict] = []

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json", canonical_signer=None):
            self.assertEqual(path, "/v1/bridge/messages")
            captured_payloads.append(payload)
            response = bridge_preparation_response() if len(captured_payloads) == 1 else bridge_submission_response()
            return 200, json.dumps(response), "application/json"

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=False):
            with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
                with RunningServer(state) as server:
                    status, payload = request_json(
                        f"{server.base_url}/api/bridge/messages",
                        {"environment": "testnet", "native_proof_b64": BRIDGE_TEST_PROOF_B64},
                    )

        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertEqual(captured_payloads[0], {
            "authority": "i105fixture",
            "fee_payment": contract_console.authority_fee_payment_intent(
                contract_console.DEFAULT_GAS_LIMIT
            ),
            "native_proof_b64": BRIDGE_TEST_PROOF_B64,
        })
        self.assertEqual(captured_payloads[1]["native_proof_b64"], BRIDGE_TEST_PROOF_B64)
        self.assertNotIn("destination_proof_b64", captured_payloads[1])

    def test_bridge_submit_rejects_retired_and_caller_signing_fields(self) -> None:
        signer = make_signer(private_key=BRIDGE_TEST_PRIVATE_KEY)
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        retired_fields = [
            "private_key",
            "message_bundle",
            "burn_bundle",
            "governance_bundle",
            "settlement",
            "gas_limit",
            "route",
            "verifier_address_hex",
            "transaction_payload_b64",
            "signature_b64",
            "creation_time_ms",
        ]

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=False):
            with mock.patch.object(contract_console, "proxy_torii_request") as proxy:
                with RunningServer(state) as server:
                    responses = []
                    for field in retired_fields:
                        value = "should-not-be-forwarded"
                        request = {
                            "environment": "testnet",
                            "destination_proof_b64": BRIDGE_TEST_PROOF_B64,
                            field: value,
                        }
                        responses.append(
                            request_json(f"{server.base_url}/api/bridge/proofs/submit", request)
                        )

        for status, payload in responses:
            self.assertEqual(status, 400)
            self.assertFalse(payload["ok"])
        proxy.assert_not_called()

    def test_bridge_submit_rejects_malformed_proof_before_upstream(self) -> None:
        signer = make_signer(private_key=BRIDGE_TEST_PRIVATE_KEY)
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=False):
            with mock.patch.object(contract_console, "proxy_torii_request") as proxy:
                with RunningServer(state) as server:
                    missing = request_json(
                        f"{server.base_url}/api/bridge/proofs/submit",
                        {"environment": "testnet"},
                    )
                    malformed = request_json(
                        f"{server.base_url}/api/bridge/messages",
                        {"environment": "testnet", "native_proof_b64": "not base64"},
                    )

        for status, payload in (missing, malformed):
            self.assertEqual(status, 400)
            self.assertFalse(payload["ok"])
            self.assertIn("canonical padded-base64", payload["error"])
        proxy.assert_not_called()

    def test_bridge_submit_rejects_tampered_preparation_without_second_post(self) -> None:
        signer = make_signer(
            private_key=BRIDGE_TEST_PRIVATE_KEY,
            public_key=BRIDGE_TEST_PUBLIC_KEY,
        )
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        calls = 0

        def fake_proxy(*args, **kwargs):
            nonlocal calls
            calls += 1
            response = bridge_preparation_response()
            response["signing_message_b64"] = base64.b64encode(b"x" * 32).decode("ascii")
            return 200, json.dumps(response), "application/json"

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=False):
            with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
                with RunningServer(state) as server:
                    status, payload = request_json(
                        f"{server.base_url}/api/bridge/proofs/submit",
                        {"environment": "testnet", "destination_proof_b64": BRIDGE_TEST_PROOF_B64},
                    )

        self.assertEqual(status, 502)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["error_code"], "bridge_detached_signing_failed")
        self.assertIn("does not match", payload["error"])
        self.assertEqual(calls, 1)

    def test_bridge_submit_rejects_inconsistent_submitted_response(self) -> None:
        signer = make_signer(
            private_key=BRIDGE_TEST_PRIVATE_KEY,
            public_key=BRIDGE_TEST_PUBLIC_KEY,
        )
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        calls = 0

        def fake_proxy(*args, **kwargs):
            nonlocal calls
            calls += 1
            if calls == 1:
                return 200, json.dumps(bridge_preparation_response()), "application/json"
            invalid = bridge_submission_response()
            invalid["transaction_payload_b64"] = BRIDGE_TEST_TRANSACTION_B64
            return 200, json.dumps(invalid), "application/json"

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=False):
            with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
                with RunningServer(state) as server:
                    status, payload = request_json(
                        f"{server.base_url}/api/bridge/proofs/submit",
                        {"environment": "testnet", "destination_proof_b64": BRIDGE_TEST_PROOF_B64},
                    )

        self.assertEqual(status, 502)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["error_code"], "invalid_bridge_submission_response")
        self.assertEqual(calls, 2)

    def test_bridge_submit_rejects_response_metadata_switch_after_signing(self) -> None:
        signer = make_signer(
            private_key=BRIDGE_TEST_PRIVATE_KEY,
            public_key=BRIDGE_TEST_PUBLIC_KEY,
        )
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        calls = 0

        def fake_proxy(*args, **kwargs):
            nonlocal calls
            calls += 1
            if calls == 1:
                return 200, json.dumps(bridge_preparation_response()), "application/json"
            switched = bridge_submission_response()
            switched["message_id_hex"] = "56" * 32
            return 200, json.dumps(switched), "application/json"

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=False):
            with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
                with RunningServer(state) as server:
                    status, payload = request_json(
                        f"{server.base_url}/api/bridge/proofs/submit",
                        {"environment": "testnet", "destination_proof_b64": BRIDGE_TEST_PROOF_B64},
                    )

        self.assertEqual(status, 502)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["error_code"], "invalid_bridge_submission_response")
        self.assertIn("does not match preparation", payload["error"])
        self.assertEqual(calls, 2)

    def test_pipeline_status_proxy_accepts_only_the_current_status_only_dto(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        queued_hash = "11" * 32
        committed_hash = "22" * 32
        rejected_hash = "33" * 32
        missing_hash = "44" * 32

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json", canonical_signer=None):
            self.assertEqual(path, "/v1/pipeline/transactions/status")
            self.assertEqual(method, "GET")
            self.assertEqual(accept, "application/json")
            self.assertEqual(set(query.keys()), {"hash", "scope"})
            status_by_hash = {
                queued_hash: (200, {
                    "hash": queued_hash,
                    "resolved_from": "queue",
                    "scope": query["scope"],
                    "status": {"kind": "Queued"},
                }),
                committed_hash: (200, {
                    "hash": committed_hash,
                    "resolved_from": "state",
                    "scope": query["scope"],
                    "status": {"kind": "Committed", "block_height": 91},
                }),
                rejected_hash: (200, {
                    "hash": rejected_hash,
                    "resolved_from": "state",
                    "scope": query["scope"],
                    "status": {"kind": "Rejected"},
                }),
                missing_hash: (404, {"code": "status_missing", "message": "status not found"}),
            }
            upstream_status, body = status_by_hash[query["hash"]]
            return upstream_status, json.dumps(body), "application/json"

        with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
            with RunningServer(state) as server:
                queued_status, queued = request_json(
                    f"{server.base_url}/api/pipeline/transactions/status"
                    f"?environment=testnet&hash={queued_hash}&scope=local&private_key=drop-me"
                )
                committed_status, committed = request_json(
                    f"{server.base_url}/api/pipeline/transactions/status?environment=testnet&hash={committed_hash}"
                )
                rejected_status, rejected = request_json(
                    f"{server.base_url}/api/pipeline/transactions/status?environment=testnet&hash={rejected_hash}&scope=global"
                )
                missing_status, missing = request_json(
                    f"{server.base_url}/api/pipeline/transactions/status?environment=testnet&hash={missing_hash}"
                )

        self.assertEqual(queued_status, 200)
        self.assertEqual(queued["status_kind"], "Queued")
        self.assertEqual(queued["status_scope"], "local")
        self.assertEqual(committed_status, 200)
        self.assertEqual(committed["status_kind"], "Committed")
        self.assertEqual(committed["status_scope"], "global")
        self.assertEqual(committed["status_resolved_from"], "state")
        self.assertEqual(committed["status_block_height"], 91)
        self.assertEqual(rejected_status, 200)
        self.assertEqual(rejected["status_kind"], "Rejected")
        self.assertEqual(rejected["status_scope"], "global")
        self.assertNotIn("rejection_reason", rejected)
        self.assertNotIn("status_summary", rejected)
        self.assertNotIn("status_diagnostics", rejected)
        self.assertEqual(missing_status, 200)
        self.assertFalse(missing["ok"])
        self.assertEqual(missing["status_kind"], "NotFound")
        self.assertEqual(missing["status_scope"], "global")

    def test_pipeline_status_proxy_requires_hash(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        with RunningServer(state) as server:
            status, payload = request_json(
                f"{server.base_url}/api/pipeline/transactions/status?environment=testnet"
            )
            upper_status, upper_payload = request_json(
                f"{server.base_url}/api/pipeline/transactions/status?environment=testnet&hash={'A' * 64}"
            )
            unsafe_status, unsafe_payload = request_json(
                f"{server.base_url}/api/pipeline/transactions/status?environment=testnet&hash=bad%2Fhash"
            )
            scope_status, scope_payload = request_json(
                f"{server.base_url}/api/pipeline/transactions/status?environment=testnet&hash={'a' * 64}&scope=state"
            )
            alias_status, alias_payload = request_json(
                f"{server.base_url}/api/pipeline/transactions/status?environment=testnet&hash={'a' * 64}&scope=auto"
            )

        self.assertEqual(status, 400)
        self.assertFalse(payload["ok"])
        self.assertIn("hash is required", payload["error"])
        self.assertEqual(upper_status, 400)
        self.assertFalse(upper_payload["ok"])
        self.assertIn("nonzero lowercase 32-byte", upper_payload["error"])
        self.assertEqual(unsafe_status, 400)
        self.assertFalse(unsafe_payload["ok"])
        self.assertIn("nonzero lowercase 32-byte", unsafe_payload["error"])
        self.assertEqual(scope_status, 400)
        self.assertFalse(scope_payload["ok"])
        self.assertIn("scope must be local or global", scope_payload["error"])
        self.assertEqual(alias_status, 400)
        self.assertFalse(alias_payload["ok"])
        self.assertIn("scope must be local or global", alias_payload["error"])

    def test_pipeline_status_proxy_rejects_unknown_upstream_kind(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        tx_hash = "55" * 32

        def fake_proxy(*args, **kwargs):
            return 200, json.dumps({
                "hash": tx_hash,
                "scope": "global",
                "resolved_from": "cache",
                "status": {"kind": "Pending"},
            }), "application/json"

        with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
            with RunningServer(state) as server:
                status, payload = request_json(
                    f"{server.base_url}/api/pipeline/transactions/status?environment=testnet&hash={tx_hash}"
                )

        self.assertEqual(status, 502)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["error_code"], "invalid_upstream_status_payload")
        self.assertIn("unknown typed status kind", payload["error"])

    def test_pipeline_status_proxy_rejects_retired_public_detail_fields(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        tx_hash = "66" * 32

        for retired_field, retired_value in (
            ("summary", "Rejected"),
            ("diagnostics", []),
        ):
            with self.subTest(field=retired_field):
                def fake_proxy(*args, **kwargs):
                    response = {
                        "hash": tx_hash,
                        "scope": "global",
                        "resolved_from": "state",
                        "status": {"kind": "Rejected"},
                        retired_field: retired_value,
                    }
                    return 200, json.dumps(response), "application/json"

                with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
                    with RunningServer(state) as server:
                        status, payload = request_json(
                            f"{server.base_url}/api/pipeline/transactions/status?environment=testnet&hash={tx_hash}"
                        )
                self.assertEqual(status, 502)
                self.assertFalse(payload["ok"])
                self.assertIn("current status-only DTO", payload["error"])

        def fake_rejection_reason(*args, **kwargs):
            response = {
                "hash": tx_hash,
                "scope": "global",
                "resolved_from": "state",
                "status": {"kind": "Rejected", "rejection_reason": "retired"},
            }
            return 200, json.dumps(response), "application/json"

        with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_rejection_reason):
            with RunningServer(state) as server:
                status, payload = request_json(
                    f"{server.base_url}/api/pipeline/transactions/status?environment=testnet&hash={tx_hash}"
                )
        self.assertEqual(status, 502)
        self.assertFalse(payload["ok"])
        self.assertIn("current status-only DTO", payload["error"])

    def test_testnet_call_requires_mutation_gate(self) -> None:
        signer = make_signer(private_key="802620fixture")
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        with RunningServer(state) as server:
            status, payload = request_json(
                f"{server.base_url}/api/call",
                {
                    "environment": "testnet",
                    "contract_address": "tairac1bridgefixture",
                    "entrypoint": "lock_to_remote",
                    "payload": {"route": "ton_testnet"},
                },
            )

        self.assertEqual(status, 403)
        self.assertFalse(payload["ok"])
        self.assertIn("SORASWAP_ALLOW_TESTNET_MUTATIONS=1", payload["error"])

    def test_contract_console_rejects_json_number_manifest_numeric_arguments(self) -> None:
        signer = make_signer(
            private_key=BRIDGE_TEST_PRIVATE_KEY,
            public_key=BRIDGE_TEST_PUBLIC_KEY,
        )
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        with mock.patch.object(contract_console, "proxy_torii_request") as proxy:
            with RunningServer(state) as server:
                status, payload = request_json(
                    f"{server.base_url}/api/call",
                    {
                        "environment": "testnet",
                        "contract_address": "tairac1bridgefixture",
                        "entrypoint": "lock_to_remote",
                        "payload": {
                            "route": "testnet_lane",
                            "transfer": "transfer-1",
                            "recipient": "recipient-1",
                            "amount": 25,
                        },
                    },
                )

        self.assertEqual(status, 400)
        self.assertFalse(payload["ok"])
        self.assertIn(
            "payload.amount for manifest type quantity must be an exact canonical JSON string",
            payload["error"],
        )
        proxy.assert_not_called()

    def test_testnet_call_is_allowed_when_mutation_gate_is_enabled(self) -> None:
        signer = make_signer(
            private_key=BRIDGE_TEST_PRIVATE_KEY,
            public_key=BRIDGE_TEST_PUBLIC_KEY,
        )
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        captured_payloads: list[dict] = []

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json", canonical_signer=None):
            self.assertEqual(torii_url, "https://taira.sora.org")
            self.assertEqual(path, "/v1/contracts/call")
            self.assertEqual(method, "POST")
            captured_payloads.append(payload)
            response = contract_call_response(
                contract_address="tairac1bridgefixture",
                entrypoint="lock_to_remote",
                submitted=len(captured_payloads) == 2,
            )
            return 200, json.dumps(response), "application/json"

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=False):
            with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
                with RunningServer(state) as server:
                    status, payload = request_json(
                        f"{server.base_url}/api/call",
                        {
                            "environment": "testnet",
                            "contract_address": "tairac1bridgefixture",
                            "entrypoint": "lock_to_remote",
                            "payload": {
                                "route": "testnet_lane",
                                "transfer": "transfer-1",
                                "recipient": "recipient-1",
                                "amount": "1",
                            },
                        },
                    )

        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["tx_hash_hex"], "ab" * 32)
        self.assertEqual(len(captured_payloads), 2)
        self.assertEqual(
            captured_payloads[0]["fee_payment"],
            contract_console.authority_fee_payment_intent(contract_console.DEFAULT_GAS_LIMIT),
        )
        self.assertNotIn("gas_limit", captured_payloads[0])
        self.assertNotIn("private_key", json.dumps(captured_payloads))
        self.assertEqual(captured_payloads[1]["public_key_hex"], BRIDGE_TEST_PUBLIC_KEY.removeprefix("ed0120"))
        self.assertEqual(captured_payloads[1]["creation_time_ms"], 1_750_000_000_002)
        self.assertEqual(captured_payloads[1]["fee_payment"], captured_payloads[0]["fee_payment"])

    def test_production_call_requires_mutation_gate(self) -> None:
        self.fixture.add_environment(
            "production",
            torii_url="https://production.example.invalid",
            contract_address="prodc1bridgefixture",
        )
        signer = make_signer(
            environment="production",
            authority="i105production",
            torii_url="https://production.example.invalid",
            private_key=BRIDGE_TEST_PRIVATE_KEY,
            public_key=BRIDGE_TEST_PUBLIC_KEY,
        )
        state = contract_console.ContractConsoleState(self.fixture.root, {"production": signer})

        with RunningServer(state) as server:
            status, payload = request_json(
                f"{server.base_url}/api/call",
                {
                    "environment": "production",
                    "contract_address": "prodc1bridgefixture",
                    "entrypoint": "lock_to_remote",
                    "payload": {"route": "production_lane"},
                },
            )

        self.assertEqual(status, 403)
        self.assertFalse(payload["ok"])
        self.assertIn("SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1", payload["error"])

    def test_contract_call_rejects_tampered_prepared_signing_message(self) -> None:
        signer = make_signer(
            private_key=BRIDGE_TEST_PRIVATE_KEY,
            public_key=BRIDGE_TEST_PUBLIC_KEY,
        )
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        calls = 0

        def fake_proxy(*args, **kwargs):
            nonlocal calls
            calls += 1
            response = contract_call_response(
                contract_address="tairac1bridgefixture",
                entrypoint="lock_to_remote",
                submitted=False,
            )
            response["signing_message_b64"] = base64.b64encode(b"x" * 32).decode("ascii")
            return 200, json.dumps(response), "application/json"

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=False):
            with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
                with RunningServer(state) as server:
                    status, payload = request_json(
                        f"{server.base_url}/api/call",
                        {
                            "environment": "testnet",
                            "contract_address": "tairac1bridgefixture",
                            "entrypoint": "lock_to_remote",
                        },
                    )

        self.assertEqual(status, 502)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["error_code"], "contract_call_detached_signing_failed")
        self.assertIn("canonical transaction payload", payload["error"])
        self.assertEqual(calls, 1)

    def test_production_call_is_allowed_when_mutation_gate_is_enabled(self) -> None:
        self.fixture.add_environment(
            "production",
            torii_url="https://production.example.invalid",
            contract_address="prodc1bridgefixture",
        )
        signer = make_signer(
            environment="production",
            authority="i105production",
            torii_url="https://production.example.invalid",
            private_key=BRIDGE_TEST_PRIVATE_KEY,
            public_key=BRIDGE_TEST_PUBLIC_KEY,
        )
        state = contract_console.ContractConsoleState(self.fixture.root, {"production": signer})
        captured_payloads: list[dict] = []

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json", canonical_signer=None):
            self.assertEqual(torii_url, "https://production.example.invalid")
            self.assertEqual(path, "/v1/contracts/call")
            self.assertEqual(method, "POST")
            captured_payloads.append(payload)
            response = contract_call_response(
                contract_address="prodc1bridgefixture",
                entrypoint="lock_to_remote",
                submitted=len(captured_payloads) == 2,
            )
            return 200, json.dumps(response), "application/json"

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_PRODUCTION_MUTATIONS": "1"}, clear=False):
            with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
                with RunningServer(state) as server:
                    status, payload = request_json(
                        f"{server.base_url}/api/call",
                        {
                            "environment": "production",
                            "contract_address": "prodc1bridgefixture",
                            "entrypoint": "lock_to_remote",
                            "payload": {
                                "route": "production_lane",
                                "transfer": "transfer-1",
                                "recipient": "recipient-1",
                                "amount": "1",
                            },
                        },
                    )

        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["tx_hash_hex"], "ab" * 32)
        self.assertEqual(len(captured_payloads), 2)

    def test_transaction_history_unavailable_degrades_cleanly(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json", canonical_signer=None):
            self.assertEqual(path, "/v1/transactions/history")
            self.assertEqual(method, "GET")
            self.assertEqual(query, {"limit": "5"})
            return 503, json.dumps({
                "code": "tx_history_auth_unavailable",
                "message": "transaction history bearer auth is not configured",
            }), "application/json"

        with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
            with RunningServer(state) as server:
                status, payload = request_json(
                    f"{server.base_url}/api/transactions/history?environment=testnet&limit=5"
                )

        self.assertEqual(status, 200)
        self.assertFalse(payload["ok"])
        self.assertFalse(payload["available"])
        self.assertFalse(payload["supported"])
        self.assertEqual(payload["unsupported_reason"], "tx_history_auth_unavailable")

    def test_transaction_history_proxy_caps_large_history_windows(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        observed_queries: list[dict[str, str]] = []

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json", canonical_signer=None):
            self.assertEqual(path, "/v1/transactions/history")
            self.assertEqual(method, "GET")
            observed_queries.append(query)
            return 200, json.dumps({"items": []}), "application/json"

        with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
            with RunningServer(state) as server:
                status, payload = request_json(
                    f"{server.base_url}/api/transactions/history"
                    "?environment=testnet&limit=100000&offset=999999&asset_id=xor%23universal"
                    "&count_mode=bounded&from=bad&private_key=drop"
                )
                default_status, default_payload = request_json(
                    f"{server.base_url}/api/transactions/history?environment=testnet"
                )

        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertEqual(default_status, 200)
        self.assertTrue(default_payload["ok"])
        self.assertEqual(observed_queries[0], {
            "limit": "100",
            "offset": "10000",
            "asset_id": "xor#universal",
            "count_mode": "bounded",
        })
        self.assertEqual(observed_queries[1], {"limit": "10"})

    def test_transaction_history_rejects_invalid_allowed_field_values(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        with mock.patch.object(contract_console, "proxy_torii_request") as proxy:
            with RunningServer(state) as server:
                count_status, count_payload = request_json(
                    f"{server.base_url}/api/transactions/history?environment=testnet&count_mode=approximate"
                )
                asset_status, asset_payload = request_json(
                    f"{server.base_url}/api/transactions/history?environment=testnet&asset_id=%0A"
                )

        self.assertEqual(count_status, 400)
        self.assertFalse(count_payload["ok"])
        self.assertIn("count_mode must be bounded or exact", count_payload["error"])
        self.assertEqual(asset_status, 400)
        self.assertFalse(asset_payload["ok"])
        self.assertIn("asset_id must be a non-empty value", asset_payload["error"])
        proxy.assert_not_called()

    def test_authenticated_proxy_returns_redirect_without_following_it(self) -> None:
        opener = mock.Mock()
        opener.open.side_effect = urllib.error.HTTPError(
            "https://taira.sora.org/v1/status",
            302,
            "Found",
            {"Content-Type": "application/json", "Location": "https://evil.invalid/steal"},
            io.BytesIO(b'{"redirect":true}'),
        )
        with mock.patch.object(contract_console.urllib.request, "build_opener", return_value=opener) as build:
            status, body, _ = contract_console.proxy_torii_request(
                "https://taira.sora.org",
                "/v1/status",
                method="GET",
                payload=None,
                query=None,
                basic_auth=("operator", "secret"),
                timeout=1,
            )

        self.assertEqual(status, 302)
        self.assertEqual(json.loads(body), {"redirect": True})
        self.assertEqual(opener.open.call_count, 1)
        self.assertTrue(any(isinstance(arg, contract_console.NoRedirectHandler) for arg in build.call_args.args))

    def test_canonical_request_message_matches_current_iroha_wire_oracle(self) -> None:
        network_id = (
            "hash:7B7B7B7B7B7B7B7B7B7B7B7B7B7B7B7B7B7B7B7B7B7B7B7B7B7B7B7B7B7B7B7B#EB7B"
        )
        raw_query = "b=%FF&a=%E2%82%AC&literal=%GG&space=a+b&&empty"
        message = contract_console.canonical_account_request_message(
            network_id,
            "POST",
            f"https://torii.example/v1/contracts/view?{raw_query}",
            b"wire body",
            1_902_345_678_901,
            "bounded-message-parity",
        )
        expected = b"iroha.app.request.network.v1\0" + bytes([0x7B]) * 32
        expected += (
            b"POST\n/v1/contracts/view\n"
            b"a=%E2%82%AC&b=%EF%BF%BD&empty=&literal=%25GG&space=a+b\n"
            b"6119ee2a454af16109eb044507a4dcaa39ae21297562f996e8d0dea6de66094c\n"
            b"1902345678901\nbounded-message-parity"
        )
        self.assertEqual(message, expected)

    def test_canonical_account_headers_bind_exact_transmitted_request(self) -> None:
        signer = make_signer(
            private_key=BRIDGE_TEST_PRIVATE_KEY,
            public_key=BRIDGE_TEST_PUBLIC_KEY,
        )
        upstream = mock.MagicMock()
        upstream.__enter__.return_value = upstream
        upstream.read.return_value = b"{}"
        upstream.status = 200
        upstream.headers = {"Content-Type": "application/json"}
        opener = mock.Mock()
        opener.open.return_value = upstream
        payload = {"authority": "i105fixture", "payload": {"note": "\u20ac"}}

        with mock.patch.object(contract_console.urllib.request, "build_opener", return_value=opener):
            status, _, _ = contract_console.proxy_torii_request(
                "https://taira.sora.org",
                "/v1/contracts/view",
                method="POST",
                payload=payload,
                query=None,
                basic_auth=signer.basic_auth,
                timeout=1,
                canonical_signer=signer,
            )

        self.assertEqual(status, 200)
        request = opener.open.call_args.args[0]
        self.assertEqual(
            request.data,
            json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8"),
        )
        headers = {key.lower(): value for key, value in request.header_items()}
        self.assertEqual(
            headers["x-iroha-account"],
            "0x02000120" + BRIDGE_TEST_PUBLIC_KEY.removeprefix("ed0120"),
        )
        self.assertEqual(set(contract_console.CANONICAL_ACCOUNT_AUTH_HEADERS), {
            "X-Iroha-Account",
            "X-Iroha-Signature",
            "X-Iroha-Timestamp-Ms",
            "X-Iroha-Nonce",
        })
        message = contract_console.canonical_account_request_message(
            signer.network_id,
            request.method,
            request.full_url,
            request.data,
            int(headers["x-iroha-timestamp-ms"]),
            headers["x-iroha-nonce"],
        )
        self.assertTrue(
            contract_console.verify_ed25519_signature_b64(
                signer.public_key,
                message,
                headers["x-iroha-signature"],
            )
        )
        self.assertNotIn(signer.private_key, json.dumps(headers))

    def test_protected_torii_routes_never_fall_back_to_unsigned_http(self) -> None:
        with mock.patch.object(contract_console.urllib.request, "build_opener") as build_opener:
            for path in sorted(contract_console.CANONICAL_ACCOUNT_AUTH_PATHS):
                with self.subTest(path=path), self.assertRaisesRegex(
                    ValueError,
                    "canonical account request authentication is required",
                ):
                    contract_console.proxy_torii_request(
                        "https://taira.sora.org",
                        path,
                        method="POST",
                        payload={"authority": "i105fixture"},
                        query=None,
                        basic_auth=None,
                        timeout=1,
                    )
        build_opener.assert_not_called()

    def test_canonical_network_id_rejects_checksum_mismatch(self) -> None:
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            contract_console.canonical_network_id_bytes(TAIRA_NETWORK_ID[:-4] + "0000")

    def test_authenticated_proxy_suppresses_basic_auth_response_echoes(self) -> None:
        login = "operator"
        password = "do-not-echo-this-password"
        encoded = base64.b64encode(f"{login}:{password}".encode("utf-8")).decode("ascii")
        upstream = mock.MagicMock()
        upstream.__enter__.return_value = upstream
        upstream.read.return_value = json.dumps({"debug": f"Basic {encoded}"}).encode("utf-8")
        upstream.status = 200
        upstream.headers = {"Content-Type": "application/json"}
        opener = mock.Mock()
        opener.open.return_value = upstream

        with mock.patch.object(contract_console.urllib.request, "build_opener", return_value=opener):
            with self.assertRaisesRegex(OSError, "credential material") as raised:
                contract_console.proxy_torii_request(
                    "https://production.sora.org",
                    "/v1/status",
                    method="GET",
                    payload=None,
                    query=None,
                    basic_auth=(login, password),
                    timeout=1,
                )

        self.assertNotIn(password, str(raised.exception))
        self.assertNotIn(encoded, str(raised.exception))

    def test_authenticated_proxy_suppresses_signer_key_response_echoes(self) -> None:
        private_key = "802620" + "ab" * 32
        upstream = mock.MagicMock()
        upstream.__enter__.return_value = upstream
        upstream.read.return_value = json.dumps({"request_key": private_key}).encode("utf-8")
        upstream.status = 400
        upstream.headers = {"Content-Type": "application/json"}
        opener = mock.Mock()
        opener.open.return_value = upstream

        with mock.patch.object(contract_console.urllib.request, "build_opener", return_value=opener):
            with self.assertRaisesRegex(OSError, "credential material") as raised:
                contract_console.proxy_torii_request(
                    "https://production.sora.org",
                    "/v1/contracts/activity",
                    method="POST",
                    payload={"authority": "i105fixture", "private_key": private_key},
                    query=None,
                    basic_auth=None,
                    timeout=1,
                )

        self.assertNotIn(private_key, str(raised.exception))

    def test_authenticated_proxy_suppresses_http_error_credential_echoes(self) -> None:
        password = "http-error-password-secret"
        opener = mock.Mock()
        opener.open.side_effect = urllib.error.HTTPError(
            "https://production.sora.org/v1/status",
            401,
            "Unauthorized",
            {"Content-Type": "application/json"},
            io.BytesIO(json.dumps({"password_echo": password}).encode("utf-8")),
        )
        with mock.patch.object(contract_console.urllib.request, "build_opener", return_value=opener):
            with self.assertRaisesRegex(OSError, "credential material") as raised:
                contract_console.proxy_torii_request(
                    "https://production.sora.org",
                    "/v1/status",
                    method="GET",
                    payload=None,
                    query=None,
                    basic_auth=("operator", password),
                    timeout=1,
                )

        self.assertNotIn(password, str(raised.exception))

    def test_authenticated_proxy_rejects_origin_escape_paths(self) -> None:
        for path in ("//evil.invalid/steal", "https://evil.invalid/steal", "/v1/status?next=bad"):
            with self.subTest(path=path):
                with self.assertRaisesRegex(ValueError, "root-relative path"):
                    contract_console.proxy_torii_request(
                        "https://taira.sora.org",
                        path,
                        method="GET",
                        payload=None,
                        query=None,
                        basic_auth=("operator", "secret"),
                        timeout=1,
                    )

    def test_production_signer_config_rejects_taira_and_unsafe_files(self) -> None:
        base = self.fixture.write_signer_config(
            "config/production/production.client.toml",
            torii_url="https://production.sora.org/",
            public_key="ed0120fixture",
            private_key="802620fixture",
        )
        original = base.read_text(encoding="utf-8")
        hostile_variants = {
            "taira-chain": original.replace('chain = "fixture-chain"', f'chain = "{contract_console.TAIRA_CHAIN_ID}"'),
            "taira-origin": original.replace("https://production.sora.org/", "https://taira.sora.org/"),
            "taira-discriminant": original.replace("chain_discriminant = 991", "chain_discriminant = 369"),
            "taira-profile": original + '\nprofile = "taira"\n',
            "http-origin": original.replace("https://production.sora.org/", "http://production.sora.org/"),
        }
        for label, content in hostile_variants.items():
            hostile = self.fixture.root / "config" / "production" / f"{label}.toml"
            hostile.write_text(content, encoding="utf-8")
            hostile.chmod(0o600)
            with self.subTest(label=label), self.assertRaises(ValueError):
                contract_console.build_signer_bindings(
                    self.fixture.root,
                    {"production": str(hostile)},
                    {},
                    auto_discover=False,
                )

        base.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "mode 0600"):
            contract_console.build_signer_bindings(
                self.fixture.root, {"production": str(base)}, {}, auto_discover=False
            )
        base.chmod(0o600)
        hardlink = base.with_name("hardlink.toml")
        os.link(base, hardlink)
        with self.assertRaisesRegex(ValueError, "exactly one hard link"):
            contract_console.build_signer_bindings(
                self.fixture.root, {"production": str(base)}, {}, auto_discover=False
            )
        hardlink.unlink()
        symlink = base.with_name("symlink.toml")
        symlink.symlink_to(base)
        with self.assertRaises(ValueError):
            contract_console.build_signer_bindings(
                self.fixture.root, {"production": str(symlink)}, {}, auto_discover=False
            )

        tracked = base.with_name("tracked.toml")
        tracked.write_text(original, encoding="utf-8")
        tracked.chmod(0o600)
        subprocess.run(
            ["git", "-C", str(self.fixture.root), "add", "-f", "config/production/tracked.toml"],
            check=True,
        )
        with self.assertRaisesRegex(ValueError, "untracked"):
            contract_console.build_signer_bindings(
                self.fixture.root, {"production": str(tracked)}, {}, auto_discover=False
            )

        unignored = self.fixture.root / "config" / "operator" / "production.toml"
        unignored.parent.mkdir(parents=True, exist_ok=True)
        unignored.write_text(original, encoding="utf-8")
        unignored.chmod(0o600)
        with self.assertRaisesRegex(ValueError, "ignored"):
            contract_console.build_signer_bindings(
                self.fixture.root, {"production": str(unignored)}, {}, auto_discover=False
            )

    def test_authority_derivation_honors_explicit_candidate_cli(self) -> None:
        candidate_cli = self.fixture.root / "candidate" / "target" / "release" / "iroha"
        candidate_cli.parent.mkdir(parents=True, exist_ok=True)
        candidate_cli.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        candidate_cli.chmod(0o700)
        completed = mock.Mock(returncode=0, stdout="i105candidate\n", stderr="")

        with mock.patch.dict(
            os.environ,
            {"SORASWAP_IROHA_CLI_BIN": str(candidate_cli)},
            clear=False,
        ), mock.patch.object(contract_console.subprocess, "run", return_value=completed) as run:
            authority, warning = contract_console.derive_authority_from_public_key(
                "ed0120fixture", "production", 991
            )

        self.assertEqual(authority, "i105candidate")
        self.assertIsNone(warning)
        self.assertEqual(run.call_args.args[0][0], str(candidate_cli))
        self.assertIn("991", run.call_args.args[0])


if __name__ == "__main__":
    unittest.main()
