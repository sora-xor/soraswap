import importlib.util
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
MODULE_PATH = REPO_ROOT / "scripts" / "serve_contract_console.py"
MODULE_NAME = "soraswap_contract_console"

spec = importlib.util.spec_from_file_location(MODULE_NAME, MODULE_PATH)
contract_console = importlib.util.module_from_spec(spec)
sys.modules[MODULE_NAME] = contract_console
assert spec.loader is not None
spec.loader.exec_module(contract_console)


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


class ContractConsoleFixture:
    def __init__(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        (self.root / "ui" / "contract_console").mkdir(parents=True, exist_ok=True)
        (self.root / "ui" / "contract_console" / "index.html").write_text(
            "<!doctype html><html><body>fixture</body></html>",
            encoding="utf-8",
        )
        environment = self.root / "deployments" / "testnet"
        write_json(
            environment / "chain.latest.json",
            {
                "torii_url": "https://taira.sora.org",
                "chain": "test-chain",
                "block_1_hash": "block-1",
            },
        )
        write_json(
            environment / "contracts.latest.json",
            {
                "generated_at": "20260406T000000Z",
                "chain_fingerprint": {
                    "torii_url": "https://taira.sora.org",
                    "chain": "test-chain",
                    "block_1_hash": "block-1",
                },
                "contracts": [
                    {
                        "contract_key": "bridge.sccp_bridge",
                        "contract_source": "contracts/bridge/sccp_bridge.ko",
                        "dataspace": "universal",
                        "contract_address": "tairac1bridgefixture",
                        "deploy_nonce": 11,
                        "instance": {
                            "verification": "transaction_and_manifest",
                            "tx_hash_hex": "deadbeef",
                        },
                    }
                ],
            },
        )
        write_json(
            environment / "bridge.sccp_bridge.manifest.json",
            {
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
                        "kind": {"kind": "Public"},
                        "params": [
                            {"name": "route", "type_name": "Name"},
                            {"name": "transfer", "type_name": "Name"},
                            {"name": "sender", "type_name": "AccountId"},
                            {"name": "recipient", "type_name": "Name"},
                            {"name": "amount", "type_name": "int"},
                        ],
                        "return_type": "int",
                        "permission": "Admin",
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
                "torii_url": torii_url,
                "chain": f"{environment_name}-chain",
                "block_1_hash": f"{environment_name}-block-1",
            },
        )
        write_json(
            environment / "contracts.latest.json",
            {
                "generated_at": "20260406T000000Z",
                "chain_fingerprint": {
                    "torii_url": torii_url,
                    "chain": f"{environment_name}-chain",
                    "block_1_hash": f"{environment_name}-block-1",
                },
                "contracts": [
                    {
                        "contract_key": "bridge.sccp_bridge",
                        "contract_source": "contracts/bridge/sccp_bridge.ko",
                        "dataspace": "universal",
                        "contract_address": contract_address,
                        "deploy_nonce": 11,
                        "instance": {
                            "verification": "transaction_and_manifest",
                            "tx_hash_hex": "deadbeef",
                        },
                    }
                ],
            },
        )
        write_json(
            environment / "bridge.sccp_bridge.manifest.json",
            {
                "entrypoints": [
                    {"name": "listing_config", "kind": {"kind": "View"}, "params": [], "return_type": "tuple"},
                    {
                        "name": "lock_to_remote",
                        "kind": {"kind": "Public"},
                        "params": [
                            {"name": "route", "type_name": "Name"},
                            {"name": "transfer", "type_name": "Name"},
                            {"name": "sender", "type_name": "AccountId"},
                            {"name": "recipient", "type_name": "Name"},
                            {"name": "amount", "type_name": "int"},
                        ],
                        "return_type": "int",
                        "permission": "Admin",
                    },
                ]
            },
        )

    def close(self) -> None:
        self.tempdir.cleanup()

    def write_signer_config(
        self,
        relative_path: str,
        *,
        torii_url: str,
        public_key: str,
        private_key: str,
    ) -> Path:
        path = self.root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "\n".join(
                [
                    f'chain = "fixture-chain"',
                    f'torii_url = "{torii_url}"',
                    "",
                    "[account]",
                    'domain = "fixture.universal"',
                    f'public_key = "{public_key}"',
                    f'private_key = "{private_key}"',
                    "",
                ]
            ),
            encoding="utf-8",
        )
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


def make_signer(
    *,
    environment: str = "testnet",
    authority: str | None = "i105fixture",
    torii_url: str | None = "https://signer.example.invalid",
    private_key: str | None = None,
    source: str = "explicit",
    warnings: list[str] | None = None,
):
    return contract_console.SignerBinding(
        environment=environment,
        config_path=Path("/tmp/test-signer.toml"),
        authority=authority,
        torii_url=torii_url,
        private_key=private_key,
        public_key="ed0120fixture",
        basic_auth=("user", "pass"),
        warnings=warnings or [],
        source=source,
    )


class ContractConsoleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = ContractConsoleFixture()
        self.state = contract_console.ContractConsoleState(self.fixture.root, {})

    def tearDown(self) -> None:
        self.fixture.close()

    def test_load_environment_reads_manifest_entrypoints(self) -> None:
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
        self.assertEqual(contract["contract_address"], "tairac1bridgefixture")
        self.assertEqual(contract["entrypoints"][0]["name"], "listing_config")
        self.assertEqual(contract["entrypoints"][-1]["kind"], "Public")

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
        self.assertEqual(environment["mutation_policy"]["flag"], "SORASWAP_ALLOW_TESTNET_MUTATIONS")

    def test_bridge_inspect_requires_authority(self) -> None:
        with RunningServer(self.state) as server:
            status, payload = request_json(
                f"{server.base_url}/api/bridge/inspect",
                {"environment": "testnet"},
            )
        self.assertEqual(status, 400)
        self.assertFalse(payload["ok"])
        self.assertIn("no authority available for bridge inspection", payload["error"])

    def test_bridge_inspect_aggregates_requested_views(self) -> None:
        calls: list[tuple[str, dict]] = []

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json"):
            calls.append((path, payload))
            body = {
                "ok": True,
                "view": payload["entrypoint"],
                "payload": payload.get("payload"),
            }
            return 200, json.dumps(body), "application/json"

        with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
            with RunningServer(self.state) as server:
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

    def test_build_signer_bindings_auto_discovers_default_production_config(self) -> None:
        self.fixture.write_signer_config(
            "config/production/production.client.toml",
            torii_url="https://production.example.invalid/",
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

    def test_environment_prefers_deployment_torii_over_signer_config(self) -> None:
        self.fixture.write_signer_config(
            "config/testnet/taira.client.toml",
            torii_url="https://different.example.invalid/",
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
        self.assertEqual(environment["torii_url"], "https://taira.sora.org")
        self.assertEqual(environment["torii_url_source"], "deployment")
        self.assertEqual(environment["signer"]["torii_url"], "https://different.example.invalid")

    def test_catalog_exposes_signer_source_and_warnings(self) -> None:
        signer = make_signer(
            source="auto",
            warnings=["example warning"],
        )
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        catalog = state.load_catalog()

        self.assertEqual(len(catalog["environments"]), 1)
        environment = catalog["environments"][0]
        self.assertEqual(environment["signer"]["source"], "auto")
        self.assertTrue(environment["signer"]["configured"])
        self.assertIn("example warning", environment["signer"]["warnings"][0])

    def test_sccp_proxy_routes_return_parsed_data(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        calls: list[tuple[str, str, dict | None]] = []

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json"):
            self.assertEqual(torii_url, "https://taira.sora.org")
            self.assertEqual(method, "GET")
            self.assertIsNone(payload)
            calls.append((path, torii_url, query))
            if path == "/v1/sccp/capabilities":
                return 200, json.dumps({"local_chain": "sora", "proof_submit_path": "/v1/bridge/proofs/submit"}), "application/json"
            if path == "/v1/sccp/manifests":
                return 200, json.dumps({"manifests": [{"chain": "ton"}]}), "application/json"
            raise AssertionError(f"unexpected path: {path}")

        with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
            with RunningServer(state) as server:
                capabilities_status, capabilities = request_json(
                    f"{server.base_url}/api/sccp/capabilities?environment=testnet"
                )
                manifests_status, manifests = request_json(
                    f"{server.base_url}/api/sccp/manifests?environment=testnet"
                )

        self.assertEqual(capabilities_status, 200)
        self.assertTrue(capabilities["ok"])
        self.assertEqual(capabilities["response_json"]["local_chain"], "sora")
        self.assertEqual(capabilities["response_json"]["proof_submit_path"], "/v1/bridge/proofs/submit")
        self.assertEqual(manifests_status, 200)
        self.assertTrue(manifests["ok"])
        self.assertEqual(manifests["response_json"]["manifests"][0]["chain"], "ton")
        self.assertEqual([entry[0] for entry in calls], ["/v1/sccp/capabilities", "/v1/sccp/manifests"])

    def test_message_bundle_artifact_and_job_proxy_routes_pass_through(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        message_id = "deadbeef"
        observed_paths: list[str] = []

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json"):
            self.assertEqual(method, "GET")
            self.assertEqual(query, {})
            observed_paths.append(path)
            return 200, json.dumps({"path": path, "message_id": message_id}), "application/json"

        with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
            with RunningServer(state) as server:
                routes = [
                    ("bundle", f"/api/sccp/proofs/message/{message_id}"),
                    ("artifact", f"/api/sccp/artifacts/message/{message_id}"),
                    ("job", f"/api/sccp/jobs/message/{message_id}"),
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
                f"/v1/sccp/artifacts/message/{message_id}",
                f"/v1/sccp/jobs/message/{message_id}",
            ],
        )
        self.assertEqual(payloads["bundle"]["response_json"]["message_id"], message_id)
        self.assertEqual(payloads["artifact"]["response_json"]["path"], f"/v1/sccp/artifacts/message/{message_id}")
        self.assertEqual(payloads["job"]["response_json"]["path"], f"/v1/sccp/jobs/message/{message_id}")

    def test_recent_message_proxy_route_passes_through_query(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        observed_calls: list[tuple[str, dict[str, str]]] = []

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json"):
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

    def test_bridge_proof_submit_rejects_malformed_body_and_shapes_valid_request(self) -> None:
        signer = make_signer(private_key="802620fixture")
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        captured_payloads: list[dict] = []

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json"):
            self.assertEqual(path, "/v1/bridge/proofs/submit")
            self.assertEqual(method, "POST")
            self.assertEqual(torii_url, "https://taira.sora.org")
            captured_payloads.append(payload)
            return 200, json.dumps({"ok": True, "submitted": True, "tx_hash_hex": "beadfeed"}), "application/json"

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=False):
            with RunningServer(state) as server:
                invalid_status, invalid_payload = request_json(
                    f"{server.base_url}/api/bridge/proofs/submit",
                    {"environment": "testnet"},
                )
        self.assertEqual(invalid_status, 400)
        self.assertFalse(invalid_payload["ok"])
        self.assertIn("exactly one", invalid_payload["error"])

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=False):
            with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
                with RunningServer(state) as server:
                    status, payload = request_json(
                        f"{server.base_url}/api/bridge/proofs/submit",
                        {
                            "environment": "testnet",
                            "message_bundle": {"version": 1},
                        },
                    )

        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["tx_hash_hex"], "beadfeed")
        self.assertEqual(payload["request"]["private_key"], "[redacted]")
        self.assertEqual(captured_payloads[0]["authority"], "i105fixture")
        self.assertEqual(captured_payloads[0]["private_key"], "802620fixture")
        self.assertNotIn("environment", captured_payloads[0])

    def test_bridge_submit_rejects_explicit_private_key_in_browser_json(self) -> None:
        signer = make_signer(private_key="802620fixture")
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=False):
            with RunningServer(state) as server:
                status, payload = request_json(
                    f"{server.base_url}/api/bridge/proofs/submit",
                    {
                        "environment": "testnet",
                        "private_key": "should-not-be-here",
                        "message_bundle": {"version": 1},
                    },
                )

        self.assertEqual(status, 400)
        self.assertFalse(payload["ok"])
        self.assertIn("private_key must not be supplied", payload["error"])

    def test_bridge_message_submit_rejects_malformed_body_and_shapes_valid_request(self) -> None:
        signer = make_signer(private_key="802620fixture")
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})
        captured_payloads: list[dict] = []

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json"):
            self.assertEqual(path, "/v1/bridge/messages")
            self.assertEqual(method, "POST")
            captured_payloads.append(payload)
            return 200, json.dumps({"ok": True, "submitted": True, "tx_hash_hex": "feedbead"}), "application/json"

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=False):
            with RunningServer(state) as server:
                invalid_status, invalid_payload = request_json(
                    f"{server.base_url}/api/bridge/messages",
                    {
                        "environment": "testnet",
                        "message_bundle": "not-an-object",
                    },
                )
        self.assertEqual(invalid_status, 400)
        self.assertFalse(invalid_payload["ok"])
        self.assertIn("message_bundle", invalid_payload["error"])

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=False):
            with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
                with RunningServer(state) as server:
                    status, payload = request_json(
                        f"{server.base_url}/api/bridge/messages",
                        {
                            "environment": "testnet",
                            "message_bundle": {"version": 1},
                            "settlement": {"route": "ton_testnet"},
                        },
                    )

        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["tx_hash_hex"], "feedbead")
        self.assertEqual(payload["request"]["private_key"], "[redacted]")
        self.assertEqual(captured_payloads[0]["authority"], "i105fixture")
        self.assertEqual(captured_payloads[0]["settlement"]["route"], "ton_testnet")

    def test_bridge_message_submit_rejects_non_object_settlement(self) -> None:
        signer = make_signer(private_key="802620fixture")
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=False):
            with RunningServer(state) as server:
                status, payload = request_json(
                    f"{server.base_url}/api/bridge/messages",
                    {
                        "environment": "testnet",
                        "message_bundle": {"version": 1},
                        "settlement": "finalize-me",
                    },
                )

        self.assertEqual(status, 400)
        self.assertFalse(payload["ok"])
        self.assertIn("settlement must be a JSON object", payload["error"])

    def test_bridge_message_submit_rejects_proof_managed_settlement_payload(self) -> None:
        signer = make_signer(private_key="802620fixture")
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=False):
            with RunningServer(state) as server:
                status, payload = request_json(
                    f"{server.base_url}/api/bridge/messages",
                    {
                        "environment": "testnet",
                        "message_bundle": {"version": 1},
                        "settlement": {
                            "route": "ton_testnet",
                            "payload": {"manual": True},
                        },
                    },
                )

        self.assertEqual(status, 400)
        self.assertFalse(payload["ok"])
        self.assertIn("must not supply settlement.payload", payload["error"])

    def test_bridge_message_submit_rejects_governed_route_activation_payload(self) -> None:
        signer = make_signer(private_key="802620fixture")
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=False):
            with RunningServer(state) as server:
                status, payload = request_json(
                    f"{server.base_url}/api/bridge/messages",
                    {
                        "environment": "testnet",
                        "message_bundle": {"version": 1},
                        "settlement": {
                            "entrypoint": "activate_route_governed",
                            "payload": {"manual": True},
                        },
                    },
                )

        self.assertEqual(status, 400)
        self.assertFalse(payload["ok"])
        self.assertIn("proof-managed bridge entrypoints", payload["error"])

    def test_pipeline_status_proxy_handles_pending_committed_rejected_and_not_found(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json"):
            self.assertEqual(path, "/v1/pipeline/transactions/status")
            self.assertEqual(method, "GET")
            status_by_hash = {
                "pending": (202, {"hash": "pending", "resolved_from": "queue", "scope": "auto", "status": "Pending"}),
                "committed": (200, {"hash": "committed", "resolved_from": "state", "scope": "auto", "status": "Committed"}),
                "rejected": (200, {"hash": "rejected", "resolved_from": "state", "scope": "auto", "status": {"kind": "Rejected", "content": "invalid payload"}}),
                "missing": (404, {"code": "status_missing", "message": "status not found"}),
            }
            upstream_status, body = status_by_hash[query["hash"]]
            return upstream_status, json.dumps(body), "application/json"

        with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
            with RunningServer(state) as server:
                pending_status, pending = request_json(
                    f"{server.base_url}/api/pipeline/transactions/status?environment=testnet&hash=pending"
                )
                committed_status, committed = request_json(
                    f"{server.base_url}/api/pipeline/transactions/status?environment=testnet&hash=committed"
                )
                rejected_status, rejected = request_json(
                    f"{server.base_url}/api/pipeline/transactions/status?environment=testnet&hash=rejected"
                )
                missing_status, missing = request_json(
                    f"{server.base_url}/api/pipeline/transactions/status?environment=testnet&hash=missing"
                )

        self.assertEqual(pending_status, 200)
        self.assertEqual(pending["status_kind"], "Pending")
        self.assertEqual(committed_status, 200)
        self.assertEqual(committed["status_kind"], "Committed")
        self.assertEqual(rejected_status, 200)
        self.assertEqual(rejected["status_kind"], "Rejected")
        self.assertEqual(rejected["rejection_reason"], "invalid payload")
        self.assertEqual(missing_status, 200)
        self.assertFalse(missing["ok"])
        self.assertEqual(missing["status_kind"], "NotFound")

    def test_pipeline_status_proxy_requires_hash(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        with RunningServer(state) as server:
            status, payload = request_json(
                f"{server.base_url}/api/pipeline/transactions/status?environment=testnet"
            )

        self.assertEqual(status, 400)
        self.assertFalse(payload["ok"])
        self.assertIn("hash is required", payload["error"])

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

    def test_testnet_call_is_allowed_when_mutation_gate_is_enabled(self) -> None:
        signer = make_signer(private_key="802620fixture")
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json"):
            self.assertEqual(torii_url, "https://taira.sora.org")
            self.assertEqual(path, "/v1/contracts/call")
            self.assertEqual(method, "POST")
            return 200, json.dumps({"submitted": True, "tx_hash_hex": "facefeed"}), "application/json"

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=False):
            with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
                with RunningServer(state) as server:
                    status, payload = request_json(
                        f"{server.base_url}/api/call",
                        {
                            "environment": "testnet",
                            "contract_address": "tairac1bridgefixture",
                            "entrypoint": "lock_to_remote",
                            "payload": {"route": "testnet_lane"},
                        },
                    )

        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["tx_hash_hex"], "facefeed")

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
            private_key="802620fixture",
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
        self.assertIn("SORASWAP_ALLOW_TESTNET_MUTATIONS=1", payload["error"])

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
            private_key="802620fixture",
        )
        state = contract_console.ContractConsoleState(self.fixture.root, {"production": signer})

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json"):
            self.assertEqual(torii_url, "https://production.example.invalid")
            self.assertEqual(path, "/v1/contracts/call")
            self.assertEqual(method, "POST")
            return 200, json.dumps({"submitted": True, "tx_hash_hex": "prodfeed"}), "application/json"

        with mock.patch.dict(os.environ, {"SORASWAP_ALLOW_TESTNET_MUTATIONS": "1"}, clear=False):
            with mock.patch.object(contract_console, "proxy_torii_request", side_effect=fake_proxy):
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

        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["tx_hash_hex"], "prodfeed")

    def test_transaction_history_unavailable_degrades_cleanly(self) -> None:
        signer = make_signer()
        state = contract_console.ContractConsoleState(self.fixture.root, {"testnet": signer})

        def fake_proxy(torii_url, path, *, method, payload, query, basic_auth, timeout, accept="application/json"):
            self.assertEqual(path, "/v1/transactions/history")
            self.assertEqual(method, "GET")
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


if __name__ == "__main__":
    unittest.main()
