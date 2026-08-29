import base64
import importlib.util
import io
import json
import os
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_ROOT = REPO_ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS_ROOT))

CONSOLE_MODULE_PATH = SCRIPTS_ROOT / "serve_contract_console.py"
CONSOLE_MODULE_NAME = "serve_contract_console"
console_spec = importlib.util.spec_from_file_location(CONSOLE_MODULE_NAME, CONSOLE_MODULE_PATH)
contract_console = importlib.util.module_from_spec(console_spec)
sys.modules[CONSOLE_MODULE_NAME] = contract_console
assert console_spec.loader is not None
console_spec.loader.exec_module(contract_console)

TRADER_MODULE_PATH = SCRIPTS_ROOT / "serve_trader_ui.py"
TRADER_MODULE_NAME = "soraswap_trader_ui"
trader_spec = importlib.util.spec_from_file_location(TRADER_MODULE_NAME, TRADER_MODULE_PATH)
trader_ui = importlib.util.module_from_spec(trader_spec)
sys.modules[TRADER_MODULE_NAME] = trader_ui
assert trader_spec.loader is not None
trader_spec.loader.exec_module(trader_ui)

TRADER_FIXTURE_SERVER_MODULE_PATH = REPO_ROOT / "tests" / "run_trader_fixture_server.py"
TRADER_FIXTURE_SERVER_MODULE_NAME = "soraswap_trader_fixture_test_support"
trader_fixture_server_spec = importlib.util.spec_from_file_location(
    TRADER_FIXTURE_SERVER_MODULE_NAME,
    TRADER_FIXTURE_SERVER_MODULE_PATH,
)
trader_fixture_server = importlib.util.module_from_spec(trader_fixture_server_spec)
sys.modules[TRADER_FIXTURE_SERVER_MODULE_NAME] = trader_fixture_server
assert trader_fixture_server_spec.loader is not None
trader_fixture_server_spec.loader.exec_module(trader_fixture_server)

TAIRA_NETWORK_ID = "hash:82531CE8EAE8BFF6BEECA4698BFD13A3BC8BEC5F0EE0D23D428C97FC17AB0F3B#3E94"


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
    chain_fingerprint: dict[str, object],
    contract_address: str = "tairac1routerfixture",
    deploy_nonce: int = 12,
) -> dict[str, object]:
    contract_alias = "dlmm_router::dlmm.universal"
    dataspace_alias = "universal"
    dataspace_id = "0"
    code_hash_hex = "3" * 64
    return {
        "contract_key": "dlmm.dlmm_router",
        "generated_at": "20260406T000000Z",
        "environment": "testnet",
        "contract_source": "contracts/dlmm/dlmm_router.ko",
        "contract_alias": contract_alias,
        "dataspace_alias": dataspace_alias,
        "dataspace_id": dataspace_id,
        "contract_address": contract_address,
        "deploy_nonce": deploy_nonce,
        "code_hash_hex": code_hash_hex,
        "abi_hash_hex": "4" * 64,
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
        rows = [("dlmm.dlmm_router", "DLMM router", "ported")]
    path = root / "docs" / "parity" / "migration_register.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "| Module | Scope | Status | Notes |",
        "| --- | --- | --- | --- |",
    ]
    for module, scope, status in rows:
        lines.append(f"| {module} | {scope} | {status} | fixture |")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_public_readiness_evidence(root: Path, environment_name: str, chain: dict[str, object]) -> None:
    environment = root / "deployments" / environment_name
    chain_fingerprint = {
        "torii_url": chain["torii_url"],
        "chain": chain["chain"],
        "block_1_hash": chain["block_1_hash"],
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


class TraderUiFixture:
    def __init__(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        write_migration_register(self.root)
        (self.root / "ui" / "trader").mkdir(parents=True, exist_ok=True)
        (self.root / "ui" / "trader" / "index.html").write_text(
            "<!doctype html><html><body>trader fixture</body></html>",
            encoding="utf-8",
        )
        (self.root / "contracts" / "dlmm").mkdir(parents=True, exist_ok=True)
        (self.root / "contracts" / "dlmm" / "dlmm_router.ko").write_text(
            "// fixture router contract\n",
            encoding="utf-8",
        )
        environment = self.root / "deployments" / "testnet"
        self.chain = {
            "generated_at": "20260406T000000Z",
            "torii_url": "https://taira.sora.org",
            "chain": "test-chain",
            "block_1_hash": "block-1",
            "environment": "testnet",
        }
        self.chain_fingerprint = {
            "torii_url": self.chain["torii_url"],
            "chain": self.chain["chain"],
            "block_1_hash": self.chain["block_1_hash"],
        }
        write_json(environment / "chain.latest.json", self.chain)
        write_public_readiness_evidence(self.root, "testnet", self.chain)
        write_json(
            environment / "contracts.latest.json",
            {
                "generated_at": "20260406T000000Z",
                "status": "completed",
                "environment": "testnet",
                "chain_fingerprint": self.chain_fingerprint,
                "contracts": [current_deployment_record(chain_fingerprint=self.chain_fingerprint)],
            },
        )
        write_json(
            environment / "dlmm.dlmm_router.manifest.json",
            {
                "generated_at": "20260406T000200Z",
                "environment": "testnet",
                "contract_key": "dlmm.dlmm_router",
                "code_hash": canonical_hash_literal("3" * 64),
                "abi_hash": canonical_hash_literal("4" * 64),
                "entrypoints": [
                    {"name": "router_config", "kind": {"kind": "View"}, "params": [], "return_type": "tuple"},
                    {
                        "name": "route_swap",
                        "kind": {"kind": "Kotoage"},
                        "params": [
                            {"name": "amount_in", "type_name": "quantity"},
                            {"name": "input_is_base", "type_name": "int"},
                            {"name": "min_out", "type_name": "quantity"},
                        ],
                        "return_type": "quantity",
                    },
                ]
            },
        )

    def write_completed_deploy_evidence(self, *, include_contract_record: bool = True) -> None:
        environment = self.root / "deployments" / "testnet"
        write_json(
            environment / "deploy.latest.json",
            {
                "generated_at": "20260406T000100Z",
                "status": "completed",
                "environment": "testnet",
                "chain_fingerprint": self.chain_fingerprint,
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
            return
        write_json(
            environment / "dlmm.dlmm_router.deploy.json",
            {
                **current_deployment_record(chain_fingerprint=self.chain_fingerprint),
                "generated_at": "20260406T000200Z",
            },
        )

    def close(self) -> None:
        self.tempdir.cleanup()


DETACHED_TEST_PRIVATE_KEY = "8026209d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
DETACHED_TEST_PUBLIC_KEY = "ed0120d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
DETACHED_TEST_TRANSACTION = b"canonical-trader-prepared-transaction"
DETACHED_TEST_TRANSACTION_B64 = base64.b64encode(DETACHED_TEST_TRANSACTION).decode("ascii")
DETACHED_TEST_SIGNING_MESSAGE_B64 = base64.b64encode(
    contract_console.iroha_transaction_signing_message(DETACHED_TEST_TRANSACTION)
).decode("ascii")


def make_signer(
    *,
    environment: str = "testnet",
    authority: str = "i105fixture",
    torii_url: str = "https://taira.sora.org",
    private_key: str | None = DETACHED_TEST_PRIVATE_KEY,
    public_key: str | None = DETACHED_TEST_PUBLIC_KEY,
) -> contract_console.SignerBinding:
    return contract_console.SignerBinding(
        environment=environment,
        config_path=Path("/tmp/test-trader-signer.toml"),
        authority=authority,
        torii_url=torii_url,
        network_id=TAIRA_NETWORK_ID,
        private_key=private_key,
        public_key=public_key,
        basic_auth=("user", "pass"),
        warnings=[],
        source="explicit",
    )


def contract_call_response(*, submitted: bool, gas_limit: int) -> dict[str, object]:
    fee_payment = contract_console.authority_fee_payment_intent(gas_limit)
    receipt = {
        "operation_kind": "contract_call",
        "status": "submitted" if submitted else "pending_signature",
        "transport": "torii",
        "dataspace": "apps",
        "contract_address": "tairac1routerfixture",
        "code_hash_hex": "45" * 32,
        "abi_hash_hex": "67" * 32,
        "entrypoint": "route_swap",
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
        "contract_address": "tairac1routerfixture",
        "code_hash_hex": "45" * 32,
        "abi_hash_hex": "67" * 32,
        "creation_time_ms": 1_750_000_000_003,
        "tx_hash_hex": "ab" * 32 if submitted else None,
        "entrypoint_hash_hex": "cd" * 32 if submitted else None,
        "transaction_payload_b64": None if submitted else DETACHED_TEST_TRANSACTION_B64,
        "signing_message_b64": None if submitted else DETACHED_TEST_SIGNING_MESSAGE_B64,
        "entrypoint": "route_swap",
        "operation_receipt": receipt,
    }


class RunningTraderServer:
    def __init__(self, state: trader_ui.TraderUiState) -> None:
        self.server = trader_ui.FastThreadingHTTPServer(("127.0.0.1", 0), trader_ui.TraderUiHandler)
        self.server.state = state  # type: ignore[attr-defined]
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


class TraderUiBackendTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = TraderUiFixture()
        self.state = trader_ui.TraderUiState(self.fixture.root, {})

    def tearDown(self) -> None:
        self.fixture.close()

    def test_argument_parser_rejects_invalid_ports(self) -> None:
        parser = trader_ui.build_argument_parser()
        self.assertEqual(parser.parse_args(["--port", "65535"]).port, 65535)

        for value in ("0", "-1", "65536", "not-a-port", "1.5"):
            with self.subTest(value=value):
                with mock.patch("sys.stderr", new=io.StringIO()):
                    with self.assertRaises(SystemExit) as error:
                        parser.parse_args(["--port", value])
                self.assertEqual(error.exception.code, 2)

    def test_fixture_enforces_exact_launchpad_allocation_payloads(self) -> None:
        state = trader_fixture_server.MockToriiState()

        for entrypoint in ("claim_allocation", "refund_allocation"):
            with self.subTest(entrypoint=entrypoint, payload="canonical"):
                response = state.submit_call(
                    {
                        "authority": trader_fixture_server.FIXTURE_AUTHORITY,
                        "contract_address": trader_fixture_server.FIXTURE_LAUNCHPAD_ADDRESS,
                        "entrypoint": entrypoint,
                        "payload": {"allocation": "alloc-alpha"},
                    }
                )
                self.assertNotIn("error", response)
                self.assertEqual(
                    state.contract_events[-1]["payload"],
                    {"allocation": "alloc-alpha"},
                )

            with self.subTest(entrypoint=entrypoint, payload="retired-sale-field"):
                response = state.submit_call(
                    {
                        "authority": trader_fixture_server.FIXTURE_AUTHORITY,
                        "contract_address": trader_fixture_server.FIXTURE_LAUNCHPAD_ADDRESS,
                        "entrypoint": entrypoint,
                        "payload": {"sale": "seed-alpha", "allocation": "alloc-alpha"},
                    }
                )
                self.assertEqual(response, {"error": "invalid_payload_schema"})

            with self.subTest(entrypoint=entrypoint, payload="missing-allocation"):
                response = state.submit_call(
                    {
                        "authority": trader_fixture_server.FIXTURE_AUTHORITY,
                        "contract_address": trader_fixture_server.FIXTURE_LAUNCHPAD_ADDRESS,
                        "entrypoint": entrypoint,
                        "payload": {},
                    }
                )
                self.assertEqual(response, {"error": "invalid_payload_schema"})

    def test_fixture_enforces_exact_perps_payloads_and_current_views(self) -> None:
        state = trader_fixture_server.MockToriiState()
        canonical_payloads = {
            "open_position": {
                "market_id": "1",
                "size": "-520",
                "margin": "120",
                "requested_leverage_bps": "40000",
            },
            "modify_position": {
                "position_id": "7",
                "size_delta": "-40",
                "margin_delta": "-10",
                "requested_leverage_bps": "40000",
            },
            "add_margin": {"position_id": "7", "amount": "24"},
            "remove_margin": {"position_id": "7", "amount": "12"},
            "close_position": {"position_id": "7"},
        }

        for entrypoint, payload in canonical_payloads.items():
            with self.subTest(entrypoint=entrypoint, payload="canonical"):
                response = state.submit_call(
                    {
                        "authority": trader_fixture_server.FIXTURE_AUTHORITY,
                        "contract_address": trader_fixture_server.FIXTURE_PERPS_ADDRESS,
                        "entrypoint": entrypoint,
                        "payload": payload,
                    }
                )
                self.assertNotIn("error", response)
                self.assertEqual(state.contract_events[-1]["payload"], payload)

        retired_open_payload = {
            **canonical_payloads["open_position"],
            "position_id": "8",
        }
        retired_modify_payload = {
            key: value
            for key, value in canonical_payloads["modify_position"].items()
            if key != "requested_leverage_bps"
        }
        retired_modify_payload["market_id"] = "1"
        for entrypoint, payload in (
            ("open_position", retired_open_payload),
            ("modify_position", retired_modify_payload),
        ):
            with self.subTest(entrypoint=entrypoint, payload="retired"):
                response = state.submit_call(
                    {
                        "authority": trader_fixture_server.FIXTURE_AUTHORITY,
                        "contract_address": trader_fixture_server.FIXTURE_PERPS_ADDRESS,
                        "entrypoint": entrypoint,
                        "payload": payload,
                    }
                )
                self.assertEqual(response, {"error": "invalid_payload_schema"})

        self.assertEqual(
            state.view(trader_fixture_server.FIXTURE_PERPS_ADDRESS, "engine_config", {}),
            [
                "usdt#soraswap.universal",
                "perps-custody@universal",
                "perps-oracle@universal",
                0,
                2,
                8,
                201,
                202,
                64,
            ],
        )
        self.assertEqual(
            state.view(trader_fixture_server.FIXTURE_PERPS_ADDRESS, "collateral_pool_state", {}),
            ["perps-custody@universal", 1000, 110, 890],
        )
        self.assertEqual(
            state.view(
                trader_fixture_server.FIXTURE_PERPS_ADDRESS,
                "market_oracle_state",
                {"market_id": 1},
            ),
            [10000, 10000, 25, 100, 174],
        )

    def test_access_log_redacts_sensitive_query_values(self) -> None:
        class FakeHandler:
            def address_string(self) -> str:
                return "127.0.0.1"

        stderr = io.StringIO()
        with mock.patch("sys.stderr", new=stderr):
            trader_ui.TraderUiHandler.log_message(
                FakeHandler(),
                "%s %s %s",
                '"GET /api/pipeline/transactions/status?environment=testnet&hash=pending'
                '&private_key=drop-me&bearer_token=token-secret&password=password-secret'
                '&access_token=access-secret&refreshToken=refresh-secret'
                '&callback=https%3A%2F%2Fuser%3Acallback-secret%40node.example.invalid%2Fpath'
                '&payload=%7B%22password%22%3A%22nested-password%22%2C%22visible%22%3A%22ok%22%7D'
                f'&long={"x" * (contract_console.ACCESS_LOG_QUERY_VALUE_CHARS + 1)}'
                '&visible=ok HTTP/1.1"',
                "200",
                "-",
            )

        log = stderr.getvalue()
        self.assertIn("private_key=[redacted]", log)
        self.assertIn("bearer_token=[redacted]", log)
        self.assertIn("password=[redacted]", log)
        self.assertIn("access_token=[redacted]", log)
        self.assertIn("refreshToken=[redacted]", log)
        self.assertIn("callback=[redacted]", log)
        self.assertIn("payload=[redacted]", log)
        self.assertIn(f"long=[truncated:{contract_console.ACCESS_LOG_QUERY_VALUE_CHARS + 1}]", log)
        self.assertIn("visible=ok", log)
        self.assertNotIn("drop-me", log)
        self.assertNotIn("token-secret", log)
        self.assertNotIn("password-secret", log)
        self.assertNotIn("callback-secret", log)
        self.assertNotIn("access-secret", log)
        self.assertNotIn("refresh-secret", log)
        self.assertNotIn("nested-password", log)
        self.assertNotIn("%22password%22", log)
        self.assertNotIn("x" * (contract_console.ACCESS_LOG_QUERY_VALUE_CHARS + 1), log)

    def test_http_responses_include_browser_security_headers(self) -> None:
        with RunningTraderServer(self.state) as server:
            static_status, static_headers, static_body = request_response(f"{server.base_url}/")
            api_status, api_headers, api_body = request_response(f"{server.base_url}/api/catalog")

        self.assertEqual(static_status, 200)
        self.assertIn(b"trader fixture", static_body)
        assert_browser_security_headers(self, static_headers)
        self.assertEqual(static_headers.get("Cache-Control"), "no-store")

        self.assertEqual(api_status, 200)
        self.assertIn(b"generated_at", api_body)
        assert_browser_security_headers(self, api_headers)
        self.assertEqual(api_headers.get("Cache-Control"), "no-store")

    def test_catalog_prefers_dlmm_router(self) -> None:
        self.fixture.write_completed_deploy_evidence()
        catalog = self.state.load_catalog()
        environment = catalog["environments"][0]

        self.assertEqual(catalog["repo_name"], self.fixture.root.name)
        self.assertEqual(catalog["repo_root"], self.fixture.root.name)
        self.assertNotIn(str(self.fixture.root.parent), json.dumps(catalog))
        self.assertEqual(catalog["preferred_contract_key"], "dlmm.dlmm_router")
        self.assertEqual(environment["preferred_contract"]["contract_key"], "dlmm.dlmm_router")

    def test_trader_proxy_rejects_out_of_range_browser_gas_limits(self) -> None:
        signer = make_signer()
        state = trader_ui.TraderUiState(self.fixture.root, {"testnet": signer})

        with mock.patch.object(contract_console, "proxy_torii_request") as proxy:
            with RunningTraderServer(state) as server:
                batch_status, batch_payload = request_json(
                    f"{server.base_url}/api/view/batch",
                    {
                        "environment": "testnet",
                        "authority": "i105fixture",
                        "items": [{"contract_address": "tairac1routerfixture", "entrypoint": "router_config"}],
                        "gas_limit": 0,
                    },
                )
                call_status, call_payload = request_json(
                    f"{server.base_url}/api/call",
                    {
                        "environment": "testnet",
                        "contract_address": "tairac1routerfixture",
                        "entrypoint": "route_swap",
                        "authority": "i105fixture",
                        "gas_limit": contract_console.MAX_BROWSER_GAS_LIMIT + 1,
                    },
                )

        self.assertEqual(batch_status, 400)
        self.assertFalse(batch_payload["ok"])
        self.assertIn("gas_limit must be between", batch_payload["error"])
        self.assertEqual(call_status, 400)
        self.assertFalse(call_payload["ok"])
        self.assertIn("gas_limit must be between", call_payload["error"])
        proxy.assert_not_called()

    def test_trader_call_uses_exact_two_phase_detached_signing(self) -> None:
        self.fixture.write_completed_deploy_evidence()
        signer = make_signer()
        state = trader_ui.TraderUiState(self.fixture.root, {"testnet": signer})
        captured_payloads: list[dict] = []

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json", canonical_signer=None):
            self.assertEqual(path, "/v1/contracts/call")
            self.assertEqual(method, "POST")
            captured_payloads.append(payload)
            return (
                200,
                json.dumps(contract_call_response(submitted=len(captured_payloads) == 2, gas_limit=123456)),
                "application/json",
            )

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=False):
            with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
                with RunningTraderServer(state) as server:
                    status, payload = request_json(
                        f"{server.base_url}/api/call",
                        {
                            "environment": "testnet",
                            "contract_address": "tairac1routerfixture",
                            "entrypoint": "route_swap",
                            "gas_limit": 123456,
                            "payload": {
                                "amount_in": "10",
                                "input_is_base": "1",
                                "min_out": "9",
                            },
                        },
                    )

        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertEqual(len(captured_payloads), 2)
        self.assertNotIn("gas_limit", captured_payloads[0])
        self.assertNotIn("private_key", json.dumps(captured_payloads))
        self.assertEqual(
            captured_payloads[0]["fee_payment"],
            contract_console.authority_fee_payment_intent(123456),
        )
        self.assertEqual(captured_payloads[1]["fee_payment"], captured_payloads[0]["fee_payment"])
        self.assertEqual(
            captured_payloads[1]["public_key_hex"],
            DETACHED_TEST_PUBLIC_KEY.removeprefix("ed0120"),
        )
        self.assertEqual(captured_payloads[1]["creation_time_ms"], 1_750_000_000_003)

    def test_trader_proxy_rejects_json_number_manifest_numeric_arguments(self) -> None:
        self.fixture.write_completed_deploy_evidence()
        signer = make_signer()
        state = trader_ui.TraderUiState(self.fixture.root, {"testnet": signer})

        with mock.patch.object(contract_console, "proxy_torii_request") as proxy:
            with RunningTraderServer(state) as server:
                status, payload = request_json(
                    f"{server.base_url}/api/call",
                    {
                        "environment": "testnet",
                        "contract_address": "tairac1routerfixture",
                        "entrypoint": "route_swap",
                        "payload": {
                            "amount_in": 10,
                            "input_is_base": "1",
                            "min_out": "9",
                        },
                    },
                )

        self.assertEqual(status, 400)
        self.assertFalse(payload["ok"])
        self.assertIn(
            "payload.amount_in for manifest type quantity must be an exact canonical JSON string",
            payload["error"],
        )
        proxy.assert_not_called()

    def test_read_proxy_caps_large_history_windows(self) -> None:
        query = trader_ui.bounded_read_proxy_query(
            "/v1/contracts/rollups/swaps/fills",
            {
                "environment": ["testnet"],
                "authority": ["i105fixture@universal"],
                "limit": ["999999"],
                "offset": ["-5"],
                "private_key": ["should-not-forward"],
            },
        )

        self.assertEqual(query["authority"], "i105fixture@universal")
        self.assertEqual(query["limit"], "500")
        self.assertEqual(query["offset"], "0")
        self.assertNotIn("environment", query)
        self.assertNotIn("private_key", query)

    def test_read_proxy_caps_module_rollup_windows(self) -> None:
        query = trader_ui.bounded_read_proxy_query(
            "/v1/contracts/rollups/rwa/lots",
            {
                "authority": ["i105fixture@universal"],
                "bucket_secs": ["3600"],
                "limit": ["999999"],
                "offset": ["999999"],
                "unknown": ["drop-me"],
            },
        )

        self.assertEqual(query["limit"], "250")
        self.assertEqual(query["offset"], "10000")
        self.assertNotIn("bucket_secs", query)
        self.assertNotIn("unknown", query)

    def test_read_proxy_caps_bucket_interval_and_text_filters(self) -> None:
        query = trader_ui.bounded_read_proxy_query(
            "/v1/contracts/rollups/swaps/candles",
            {
                "authority": ["i105fixture@universal"],
                "contract_address": ["tairac1" + ("a" * 300)],
                "bucket_secs": ["999999"],
                "limit": ["10"],
                "private_key": ["should-not-forward"],
            },
        )

        self.assertEqual(query["authority"], "i105fixture@universal")
        self.assertEqual(len(query["contract_address"]), trader_ui.DEFAULT_SSE_QUERY_TEXT_CAP)
        self.assertEqual(query["bucket_secs"], "86400")
        self.assertEqual(query["limit"], "10")
        self.assertNotIn("private_key", query)

    def test_read_proxy_sanitizes_account_rollup_query(self) -> None:
        query = trader_ui.bounded_read_proxy_query(
            "/v1/contracts/rollups/trader/account",
            {
                "authority": ["i105fixture@universal"],
                "contract_address": ["tairac1routerfixture"],
                "cursor": ["cursor-1"],
                "module": ["swaps"],
                "bucket_secs": ["999999"],
                "limit": ["999999"],
                "offset": ["999999"],
                "from": ["999999"],
                "private_key": ["should-not-forward"],
                "unknown": ["drop-me"],
            },
        )

        self.assertEqual(query, {"authority": "i105fixture@universal"})

    def test_read_proxy_uses_route_default_for_missing_or_invalid_limit(self) -> None:
        missing_limit_query = trader_ui.bounded_read_proxy_query(
            "/v1/contracts/rollups/swaps/fills",
            {
                "authority": ["i105fixture@universal"],
            },
        )
        invalid_limit_query = trader_ui.bounded_read_proxy_query(
            "/v1/contracts/rollups/trader/activity",
            {
                "authority": ["i105fixture@universal"],
                "limit": ["not-a-number"],
            },
        )

        self.assertEqual(missing_limit_query["limit"], "120")
        self.assertEqual(invalid_limit_query["limit"], "64")

    def test_read_proxy_leaves_uncapped_queries_unchanged(self) -> None:
        query = trader_ui.bounded_read_proxy_query(
            "/v1/pipeline/transactions/status",
            {
                "hash": ["abc123"],
                "limit": ["999999"],
            },
        )

        self.assertEqual(query["hash"], "abc123")
        self.assertEqual(query["limit"], "999999")

    def test_sse_proxy_drops_unknown_query_and_caps_values(self) -> None:
        query = trader_ui.bounded_sse_proxy_query(
            {
                "authority": ["i105fixture@universal"],
                "contract_address": ["tairac1" + ("a" * 300)],
                "cursor": ["cursor-" + ("b" * 300)],
                "module": ["swaps"],
                "limit": ["999999"],
                "from": ["-5"],
                "offset": ["999999"],
                "private_key": ["should-not-forward"],
                "unknown": ["drop-me"],
            },
        )

        self.assertEqual(query["authority"], "i105fixture@universal")
        self.assertEqual(len(query["contract_address"]), trader_ui.DEFAULT_SSE_QUERY_TEXT_CAP)
        self.assertEqual(len(query["cursor"]), trader_ui.DEFAULT_SSE_QUERY_TEXT_CAP)
        self.assertEqual(query["module"], "swaps")
        self.assertEqual(query["limit"], "500")
        self.assertEqual(query["from"], "0")
        self.assertEqual(query["offset"], "10000")
        self.assertNotIn("private_key", query)
        self.assertNotIn("unknown", query)

    def test_get_proxies_reject_unbounded_raw_queries_before_forwarding(self) -> None:
        signer = make_signer()
        state = trader_ui.TraderUiState(self.fixture.root, {"testnet": signer})
        too_many_fields = "&".join(
            ["environment=testnet"]
            + [f"k{index}=v" for index in range(contract_console.MAX_BROWSER_QUERY_FIELDS)]
        )
        long_query = "environment=testnet&payload=" + (
            "x" * contract_console.MAX_BROWSER_QUERY_STRING_CHARS
        )

        with mock.patch.object(contract_console, "proxy_torii_request") as proxy:
            with RunningTraderServer(state) as server:
                too_many_status, too_many_payload = request_json(
                    f"{server.base_url}/api/contracts/rollups/swaps/fills?{too_many_fields}"
                )
                long_status, long_payload = request_json(
                    f"{server.base_url}/api/pipeline/transactions/status?{long_query}"
                )

        self.assertEqual(too_many_status, 400)
        self.assertFalse(too_many_payload["ok"])
        self.assertIn("too many fields", too_many_payload["error"])
        self.assertEqual(long_status, 400)
        self.assertFalse(long_payload["ok"])
        self.assertIn("query string exceeds", long_payload["error"])
        proxy.assert_not_called()

    def test_sse_proxy_rejects_oversized_stream_line(self) -> None:
        self.assertEqual(
            trader_ui.read_bounded_sse_line(io.BytesIO(b"event: ready\n")),
            b"event: ready\n",
        )

        oversized = io.BytesIO(b"x" * (trader_ui.MAX_SSE_LINE_BYTES + 1))
        with self.assertRaisesRegex(OSError, "SSE upstream line exceeds"):
            trader_ui.read_bounded_sse_line(oversized)

    def test_pipeline_status_proxy_requires_and_bounds_hash(self) -> None:
        signer = make_signer()
        state = trader_ui.TraderUiState(self.fixture.root, {"testnet": signer})
        tx_hash = "66" * 32

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json", canonical_signer=None):
            self.assertEqual(path, "/v1/pipeline/transactions/status")
            self.assertEqual(method, "GET")
            self.assertEqual(query, {"hash": tx_hash, "scope": "global"})
            return 200, json.dumps({
                "hash": tx_hash,
                "status": {"kind": "Queued"},
                "scope": "global",
                "resolved_from": "queue",
            }), "application/json"

        with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy) as proxy:
            with RunningTraderServer(state) as server:
                ok_status, ok_payload = request_json(
                    f"{server.base_url}/api/pipeline/transactions/status"
                    f"?environment=testnet&hash={tx_hash}&private_key=drop-me"
                )
                missing_status, missing_payload = request_json(
                    f"{server.base_url}/api/pipeline/transactions/status?environment=testnet"
                )
                long_status, long_payload = request_json(
                    f"{server.base_url}/api/pipeline/transactions/status?environment=testnet&hash={'a' * 129}"
                )
                unsafe_status, unsafe_payload = request_json(
                    f"{server.base_url}/api/pipeline/transactions/status?environment=testnet&hash=bad%20hash"
                )

        self.assertEqual(ok_status, 200)
        self.assertTrue(ok_payload["ok"])
        self.assertEqual(ok_payload["query"], {"hash": tx_hash, "scope": "global"})
        self.assertEqual(ok_payload["status_kind"], "Queued")
        self.assertEqual(ok_payload["status_scope"], "global")
        self.assertEqual(ok_payload["status_resolved_from"], "queue")
        self.assertNotIn("status_summary", ok_payload)
        self.assertNotIn("status_diagnostics", ok_payload)
        self.assertNotIn("rejection_reason", ok_payload)
        self.assertEqual(missing_status, 400)
        self.assertFalse(missing_payload["ok"])
        self.assertIn("hash is required", missing_payload["error"])
        self.assertEqual(long_status, 400)
        self.assertFalse(long_payload["ok"])
        self.assertIn("nonzero lowercase 32-byte", long_payload["error"])
        self.assertEqual(unsafe_status, 400)
        self.assertFalse(unsafe_payload["ok"])
        self.assertIn("nonzero lowercase 32-byte", unsafe_payload["error"])
        self.assertEqual(proxy.call_count, 1)

    def test_pipeline_status_proxy_normalizes_missing_upstream_hash(self) -> None:
        signer = make_signer()
        state = trader_ui.TraderUiState(self.fixture.root, {"testnet": signer})
        tx_hash = "77" * 32

        with mock.patch.object(
            contract_console,
            "proxy_torii_request",
            return_value=(404, json.dumps({"code": "status_missing"}), "application/json"),
        ):
            with RunningTraderServer(state) as server:
                status, payload = request_json(
                    f"{server.base_url}/api/pipeline/transactions/status?environment=testnet&hash={tx_hash}"
                )

        self.assertEqual(status, 200)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["status_kind"], "NotFound")
        self.assertEqual(payload["status_scope"], "global")

    def test_trader_post_rejects_explicit_sensitive_key_in_browser_json(self) -> None:
        signer = make_signer()
        state = trader_ui.TraderUiState(self.fixture.root, {"testnet": signer})

        with mock.patch.object(contract_console, "proxy_torii_request") as proxy:
            with RunningTraderServer(state) as server:
                status, payload = request_json(
                    f"{server.base_url}/api/call",
                    {
                        "environment": "testnet",
                        "authority": "i105fixture",
                        "contract_address": "tairac1routerfixture",
                        "entrypoint": "route_swap",
                        "gas_limit": 100000,
                        "private_key": "should-not-be-here",
                        "payload": {"amount_in": 10},
                    },
                )
                secret_status, secret_payload = request_json(
                    f"{server.base_url}/api/call",
                    {
                        "environment": "testnet",
                        "authority": "i105fixture",
                        "contract_address": "tairac1routerfixture",
                        "entrypoint": "route_swap",
                        "gas_limit": 100000,
                        "secret": "should-not-be-here",
                        "payload": {"amount_in": 10},
                    },
                )
                nested_status, nested_payload = request_json(
                    f"{server.base_url}/api/call",
                    {
                        "environment": "testnet",
                        "authority": "i105fixture",
                        "contract_address": "tairac1routerfixture",
                        "entrypoint": "route_swap",
                        "gas_limit": 100000,
                        "payload": {"amount_in": 10, "secret": "should-not-be-here"},
                    },
                )
                token_status, token_payload = request_json(
                    f"{server.base_url}/api/call",
                    {
                        "environment": "testnet",
                        "authority": "i105fixture",
                        "contract_address": "tairac1routerfixture",
                        "entrypoint": "route_swap",
                        "gas_limit": 100000,
                        "payload": {
                            "amount_in": 10,
                            "apiKey": "should-not-be-here",
                            "access_token": "should-not-be-here",
                            "clientSecret": "should-not-be-here",
                            "authorization": "Bearer should-not-be-here",
                            "password": "should-not-be-here",
                        },
                    },
                )

        self.assertEqual(status, 400)
        self.assertFalse(payload["ok"])
        self.assertIn("browser JSON must not include private keys", payload["error"])
        self.assertIn("tokens", payload["error"])
        self.assertIn("authorization", payload["error"])
        self.assertEqual(secret_status, 400)
        self.assertFalse(secret_payload["ok"])
        self.assertIn("browser JSON must not include private keys", secret_payload["error"])
        self.assertIn("tokens", secret_payload["error"])
        self.assertIn("authorization", secret_payload["error"])
        self.assertEqual(nested_status, 400)
        self.assertFalse(nested_payload["ok"])
        self.assertIn("browser JSON must not include private keys", nested_payload["error"])
        self.assertIn("tokens", nested_payload["error"])
        self.assertIn("authorization", nested_payload["error"])
        self.assertEqual(token_status, 400)
        self.assertFalse(token_payload["ok"])
        self.assertIn("browser JSON must not include private keys", token_payload["error"])
        self.assertIn("passwords", token_payload["error"])
        proxy.assert_not_called()

    def test_readonly_trader_allows_incomplete_public_deploy_evidence(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(
                self.state.contract_console_state
            )

        self.assertEqual(issues, [])

    def test_mutation_enabled_trader_rejects_missing_public_deploy_evidence(self) -> None:
        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(
                self.state.contract_console_state
            )

        self.assertTrue(any("missing deployments/testnet/deploy.latest.json" in issue for issue in issues))

    def test_mutation_enabled_trader_accepts_matching_public_deploy_evidence(self) -> None:
        self.fixture.write_completed_deploy_evidence()
        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(
                self.state.contract_console_state
            )

        self.assertEqual(issues, [])

    def test_mutation_enabled_trader_rejects_invalid_oracle_client_config(self) -> None:
        self.fixture.write_completed_deploy_evidence()
        preflight_path = self.fixture.root / "deployments" / "testnet" / "preflight.latest.json"
        preflight = json.loads(preflight_path.read_text(encoding="utf-8"))
        preflight["environment"]["oracle_client_config_valid"] = False
        write_json(preflight_path, preflight)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(
                self.state.contract_console_state
            )

        self.assertTrue(any("preflight.latest.json is not ready for the current chain" in issue for issue in issues))

    def test_mutation_enabled_trader_rejects_preflight_health_issues(self) -> None:
        self.fixture.write_completed_deploy_evidence()
        preflight_path = self.fixture.root / "deployments" / "testnet" / "preflight.latest.json"
        preflight = json.loads(preflight_path.read_text(encoding="utf-8"))
        preflight["endpoint"]["health_issues"] = [
            "status endpoint did not return JSON private_key=802620TRADERSECRET "
            "Authorization: Bearer trader-token-secret "
            "https://user:trader-url-secret@node.example.invalid/v1?access_token=trader-query-secret "
            "/Users/operator/dev/soraswap/tmp/trader-health.log"
        ]
        write_json(preflight_path, preflight)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(
                self.state.contract_console_state
            )

        self.assertTrue(any("preflight.latest.json is not ready for the current chain" in issue for issue in issues))
        serialized_issues = json.dumps(issues)
        self.assertIn("private_key=[redacted]", serialized_issues)
        self.assertIn("Authorization: Bearer [redacted]", serialized_issues)
        self.assertIn("https://[redacted]@node.example.invalid/v1?access_token=[redacted]", serialized_issues)
        self.assertIn("[local-path]/trader-health.log", serialized_issues)
        self.assertNotIn("802620TRADERSECRET", serialized_issues)
        self.assertNotIn("trader-token-secret", serialized_issues)
        self.assertNotIn("trader-url-secret", serialized_issues)
        self.assertNotIn("trader-query-secret", serialized_issues)
        self.assertNotIn("/Users/operator/dev/soraswap", serialized_issues)

    def test_mutation_enabled_trader_rejects_preflight_missing_health_snapshots(self) -> None:
        self.fixture.write_completed_deploy_evidence()
        preflight_path = self.fixture.root / "deployments" / "testnet" / "preflight.latest.json"
        preflight = json.loads(preflight_path.read_text(encoding="utf-8"))
        preflight["status"] = "ready"
        preflight["blockers"] = []
        preflight["warnings"] = []
        preflight["endpoint"]["health_issues"] = []
        del preflight["endpoint"]["health"]
        write_json(preflight_path, preflight)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(
                self.state.contract_console_state
            )

        self.assertTrue(any("preflight.latest.json is not ready for the current chain" in issue for issue in issues))
        self.assertTrue(
            any("preflight.latest.json status endpoint health snapshot is not JSON-ready" in issue for issue in issues)
        )
        self.assertTrue(
            any("preflight.latest.json sumeragi endpoint health snapshot is not JSON-ready" in issue for issue in issues)
        )

    def test_mutation_enabled_trader_rejects_sensitive_per_contract_evidence(self) -> None:
        self.fixture.write_completed_deploy_evidence()
        environment = self.fixture.root / "deployments" / "testnet"

        deploy_record_path = environment / "dlmm.dlmm_router.deploy.json"
        deploy_record = json.loads(deploy_record_path.read_text(encoding="utf-8"))
        deploy_record["diagnostics"] = "contract deploy retained --client-secret router-secret"
        write_json(deploy_record_path, deploy_record)

        manifest_path = environment / "dlmm.dlmm_router.manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["diagnostics"] = "manifest written at file:///private/tmp/soraswap/router.manifest.json"
        write_json(manifest_path, manifest)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(
                self.state.contract_console_state
            )

        serialized_issues = json.dumps(issues)
        self.assertTrue(
            any(
                "deployments/testnet/dlmm.dlmm_router.deploy.json contains unredacted sensitive diagnostics" in issue
                for issue in issues
            )
        )
        self.assertTrue(
            any(
                "deployments/testnet/dlmm.dlmm_router.manifest.json contains raw local path diagnostics" in issue
                for issue in issues
            )
        )
        self.assertNotIn("router-secret", serialized_issues)
        self.assertNotIn("/private/tmp/soraswap", serialized_issues)

    def test_mutation_enabled_trader_rejects_missing_required_contract_snapshot(self) -> None:
        (self.fixture.root / "contracts" / "n3x").mkdir(parents=True, exist_ok=True)
        (self.fixture.root / "contracts" / "n3x" / "n3x_hub.ko").write_text(
            "// fixture n3x contract\n",
            encoding="utf-8",
        )
        self.fixture.write_completed_deploy_evidence()
        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(
                self.state.contract_console_state
            )

        self.assertTrue(
            any("contracts.latest.json is missing required contract snapshots: n3x.n3x_hub" in issue for issue in issues)
        )

    def test_mutation_enabled_trader_rejects_duplicate_contract_snapshot(self) -> None:
        self.fixture.write_completed_deploy_evidence()
        contracts_path = self.fixture.root / "deployments" / "testnet" / "contracts.latest.json"
        contracts = json.loads(contracts_path.read_text(encoding="utf-8"))
        contracts["contracts"].append(dict(contracts["contracts"][0]))
        write_json(contracts_path, contracts)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(
                self.state.contract_console_state
            )

        self.assertTrue(
            any(
                "contracts.latest.json contains duplicate contract snapshots: dlmm.dlmm_router" in issue
                for issue in issues
            )
        )

    def test_mutation_enabled_trader_rejects_missing_per_contract_deploy_evidence(self) -> None:
        self.fixture.write_completed_deploy_evidence(include_contract_record=False)
        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(
                self.state.contract_console_state
            )

        self.assertTrue(any("missing deployments/testnet/dlmm.dlmm_router.deploy.json" in issue for issue in issues))

    def test_mutation_enabled_trader_rejects_untimestamped_per_contract_deploy_evidence(self) -> None:
        self.fixture.write_completed_deploy_evidence()
        deploy_record_path = self.fixture.root / "deployments" / "testnet" / "dlmm.dlmm_router.deploy.json"
        deploy_record = json.loads(deploy_record_path.read_text(encoding="utf-8"))
        deploy_record.pop("generated_at", None)
        write_json(deploy_record_path, deploy_record)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(
                self.state.contract_console_state
            )

        self.assertTrue(any("dlmm.dlmm_router.deploy.json is missing generated_at" in issue for issue in issues))

    def test_mutation_enabled_trader_rejects_chain_snapshot_missing_torii_url(self) -> None:
        self.fixture.write_completed_deploy_evidence()
        chain_path = self.fixture.root / "deployments" / "testnet" / "chain.latest.json"
        chain = json.loads(chain_path.read_text(encoding="utf-8"))
        chain.pop("torii_url", None)
        write_json(chain_path, chain)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(
                self.state.contract_console_state
            )

        self.assertTrue(any("chain.latest.json must include torii_url" in issue for issue in issues))

    def test_mutation_enabled_trader_rejects_wrong_environment_contract_snapshot(self) -> None:
        self.fixture.write_completed_deploy_evidence()
        contracts_path = self.fixture.root / "deployments" / "testnet" / "contracts.latest.json"
        contracts = json.loads(contracts_path.read_text(encoding="utf-8"))
        contracts["contracts"][0]["environment"] = "production"
        write_json(contracts_path, contracts)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(
                self.state.contract_console_state
            )

        self.assertTrue(
            any(
                "contracts.latest.json contains contract snapshots for the wrong environment: dlmm.dlmm_router"
                in issue
                for issue in issues
            )
        )

    def test_mutation_enabled_trader_rejects_stale_contract_snapshot_key(self) -> None:
        self.fixture.write_completed_deploy_evidence()
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
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(
                self.state.contract_console_state
            )

        self.assertTrue(
            any(
                "contracts.latest.json contains stale or unknown contract snapshots: options.series_manager" in issue
                for issue in issues
            )
        )

    def test_mutation_enabled_trader_rejects_stale_extra_deploy_record(self) -> None:
        self.fixture.write_completed_deploy_evidence()
        write_json(
            self.fixture.root / "deployments" / "testnet" / "options.series_manager.deploy.json",
            {
                "generated_at": "20260406T000300Z",
                "contract_key": "options.series_manager",
                "environment": "testnet",
                "contract_address": "tairac1stale",
                "deploy_nonce": 99,
                "chain_fingerprint": self.fixture.chain,
            },
        )
        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(
                self.state.contract_console_state
            )

        self.assertTrue(
            any("options.series_manager.deploy.json is stale or unknown for current contracts/" in issue for issue in issues)
        )

    def test_mutation_enabled_trader_rejects_stale_extra_manifest(self) -> None:
        self.fixture.write_completed_deploy_evidence()
        write_json(
            self.fixture.root / "deployments" / "testnet" / "options.series_manager.manifest.json",
            {
                "code_hash": canonical_hash_literal("9" * 64),
                "abi_hash": canonical_hash_literal("0" * 64),
                "entrypoints": [],
            },
        )
        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(
                self.state.contract_console_state
            )

        self.assertTrue(
            any("options.series_manager.manifest.json is stale or unknown for current contracts/" in issue for issue in issues)
        )

    def test_mutation_enabled_trader_rejects_missing_deploy_nonce(self) -> None:
        self.fixture.write_completed_deploy_evidence()
        deploy_record_path = self.fixture.root / "deployments" / "testnet" / "dlmm.dlmm_router.deploy.json"
        deploy_record = json.loads(deploy_record_path.read_text(encoding="utf-8"))
        deploy_record.pop("deploy_nonce")
        deploy_record["response"].pop("deploy_nonce")
        write_json(deploy_record_path, deploy_record)
        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(
                self.state.contract_console_state
            )

        self.assertTrue(
            any(
                "dlmm.dlmm_router.deploy.json deploy nonce is missing from contracts.latest.json or the deployment record"
                in issue
                for issue in issues
            )
        )

    def test_mutation_enabled_trader_rejects_deploy_hash_mismatch(self) -> None:
        self.fixture.write_completed_deploy_evidence()
        deploy_record_path = self.fixture.root / "deployments" / "testnet" / "dlmm.dlmm_router.deploy.json"
        deploy_record = json.loads(deploy_record_path.read_text(encoding="utf-8"))
        deploy_record["code_hash_hex"] = "f" * 64
        write_json(deploy_record_path, deploy_record)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(
                self.state.contract_console_state
            )

        self.assertTrue(
            any("dlmm.dlmm_router.deploy.json code or ABI hash does not match contracts.latest.json" in issue for issue in issues)
        )

    def test_mutation_enabled_trader_rejects_manifest_missing_generated_at(self) -> None:
        self.fixture.write_completed_deploy_evidence()
        manifest_path = self.fixture.root / "deployments" / "testnet" / "dlmm.dlmm_router.manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest.pop("generated_at")
        write_json(manifest_path, manifest)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(
                self.state.contract_console_state
            )

        self.assertTrue(
            any("dlmm.dlmm_router.manifest.json is missing generated_at" in issue for issue in issues)
        )

    def test_mutation_enabled_trader_rejects_manifest_contract_key_mismatch(self) -> None:
        self.fixture.write_completed_deploy_evidence()
        manifest_path = self.fixture.root / "deployments" / "testnet" / "dlmm.dlmm_router.manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["contract_key"] = "dlmm.other"
        write_json(manifest_path, manifest)

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=True):
            issues = contract_console.mutation_enabled_public_deployment_evidence_issues(
                self.state.contract_console_state
            )

        self.assertTrue(
            any("dlmm.dlmm_router.manifest.json manifest contract_key does not match filename" in issue for issue in issues)
        )


if __name__ == "__main__":
    unittest.main()
