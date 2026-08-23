#!/usr/bin/env python3
"""Adversarial tests for the signed production cutover and readonly observer."""

from __future__ import annotations

import base64
import copy
import datetime as dt
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
APPROVAL_SCRIPT = REPO / "scripts/verify_production_cutover_approval.py"
OBSERVER_SCRIPT = REPO / "scripts/observe_production_cutover.py"
EVIDENCE_SCRIPT = REPO / "scripts/verify_production_cutover_evidence.py"
NAMESPACE = "soraswap-production-cutover-v1"
TEST_TOKEN = "soraswap-internal-observation-fixture-v1"


def load_module(name: str, path: Path):
    specification = importlib.util.spec_from_file_location(name, path)
    assert specification is not None and specification.loader is not None
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


APPROVAL_MODULE = load_module("cutover_approval_test_module", APPROVAL_SCRIPT)
OBSERVER_MODULE = load_module("cutover_observer_test_module", OBSERVER_SCRIPT)


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def run(*args: str, cwd: Path | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(item) for item in args], cwd=cwd, check=check, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )


def write_json(path: Path, value: object, mode: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if mode is not None:
        path.chmod(mode)


def public_key(path: Path) -> str:
    return " ".join(path.with_suffix(".pub").read_text(encoding="utf-8").split()[:2])


class CutoverFixture:
    def __init__(self, base: Path):
        self.root = base / "repo"
        self.root.mkdir()
        self.keys = base / "keys"
        self.keys.mkdir()
        self.security_key = self.keys / "security"
        self.operations_key = self.keys / "operations"
        self.git_key = self.keys / "git"
        for key in (self.security_key, self.operations_key, self.git_key):
            run("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key))

        (self.root / "config/production").mkdir(parents=True)
        (self.root / "deployments/production").mkdir(parents=True)
        (self.root / ".gitignore").write_text(
            "/deployments/\n/config/production/cutover-approval.json\n"
            "/config/production/production.client.toml\n",
            encoding="utf-8",
        )
        self.policy = {
            "schema": "soraswap-production-cutover-trust-policy/v1",
            "environment": "production",
            "policy_id": "production-policy-2026-01",
            "signature_namespace": NAMESPACE,
            "required_signature_count": 2,
            "required_roles": ["security", "operations"],
            "trusted_approvers": [
                {
                    "id": "security.approver",
                    "role": "security",
                    "public_key": public_key(self.security_key),
                    "independent": True,
                },
                {
                    "id": "operations.approver",
                    "role": "operations",
                    "public_key": public_key(self.operations_key),
                    "independent": True,
                },
            ],
            "allowed_monitoring_origins": ["https://monitor.production.sora.org"],
            "approval_max_age_seconds": 7200,
            "observation": {
                "duration_seconds": 1800,
                "interval_seconds": 30,
                "minimum_samples": 61,
                "maximum_monitoring_sample_age_seconds": 30,
                "minimum_validator_count": 4,
                "maximum_canonical_lead": 1,
                "maximum_finality_age_ms": 30000,
                "derivatives_pause_mode": "external_fail_closed",
            },
        }
        self.policy_path = self.root / "config/production/cutover-trust-policy.json"
        write_json(self.policy_path, self.policy)
        self._init_git()

        self.chain = {
            "schema": "soraswap-public-chain-fingerprint/v1",
            "generated_at": "20260711T000000Z",
            "environment": "production",
            "torii_url": "https://torii.production.sora.org",
            "chain": "production-chain-2026-01",
            "block_1_hash": "1" * 64,
        }
        self.chain_path = self.root / "deployments/production/chain.latest.json"
        write_json(self.chain_path, self.chain)
        self.rc_state = {"git_sha": self.sha, "tree_sha": self.tree}
        self.source_state = {
            "git_head": self.sha,
            "tracked_non_status_doc_count": 3,
            "tracked_non_status_doc_sha256": "2" * 64,
            "tracked_status_doc_count": 2,
            "tracked_status_doc_identity_sha256": "3" * 64,
        }
        self.iroha_state = {
            "iroha_root": "/opt/iroha-candidate",
            "bundle_dir": "/opt/taira-rollout-fixture-release",
            "iroha_git_sha": "4" * 40,
            "bundle_name": "taira-rollout-fixture-release",
            "checksums_sha256": "5" * 64,
            "manifest_sha256": "6" * 64,
            "irohad_sha256": "7" * 64,
            "iroha_sha256": "8" * 64,
            "kagami_sha256": "9" * 64,
            "archive_sha256": "a" * 64,
            "archive_sidecar_sha256": "b" * 64,
        }
        self.routes = [
            {"method": "POST", "path": "/v1/contracts/view/batch", "adapter": "contract.view_batch.v1"},
            {"method": "GET", "path": "/v1/contracts/rollups/swaps/fills", "adapter": "contract.rollups.swaps_fills.v1"},
        ]
        self.routes_hash = digest(canonical(self.routes))
        self.cid = "b" + "a" * 52
        self.validator_ids = [f"ed0120{index:064x}" for index in range(1, 5)]
        self.validator_hash = digest(canonical(self.validator_ids))
        self.oracle_ids = ["oracle.options", "oracle.perps"]
        self.oracle_hash = digest(canonical([{"id": value} for value in self.oracle_ids]))
        self.balance_identities = [
            {"id": "balance.signer-fee", "kind": "signer_fee"},
            {"id": "balance.trader-usdt", "kind": "watched"},
            {"id": "balance.trader-xor", "kind": "watched"},
        ]
        self.balance_hash = digest(canonical(self.balance_identities))
        self.readonly_hash = "c" * 64
        self.authorities = {
            "signer": "i105-production-signer",
            "oracle": "ed0120" + "d" * 64,
            "admin": "i105-production-admin",
            "treasury": "i105-production-treasury",
            "bridge": "i105-production-bridge",
        }
        self.approval_path = self.root / "config/production/cutover-approval.json"
        self.approval_evidence = self.root / "deployments/production/cutover_approval.latest.json"
        self.approval = self.make_approval()

    def _init_git(self) -> None:
        run("git", "init", "-q", cwd=self.root)
        run("git", "config", "user.name", "Cutover Test", cwd=self.root)
        run("git", "config", "user.email", "cutover@test.sora.org", cwd=self.root)
        allowed = self.keys / "git.allowed"
        allowed.write_text(f"cutover@test.sora.org {public_key(self.git_key)}\n", encoding="utf-8")
        run("git", "config", "gpg.format", "ssh", cwd=self.root)
        run("git", "config", "user.signingkey", str(self.git_key), cwd=self.root)
        run("git", "config", "gpg.ssh.allowedSignersFile", str(allowed), cwd=self.root)
        run("git", "add", ".", cwd=self.root)
        run("git", "commit", "-S", "-q", "-m", "signed policy", cwd=self.root)
        self.sha = run("git", "rev-parse", "HEAD", cwd=self.root).stdout.strip()
        self.tree = run("git", "rev-parse", "HEAD^{tree}", cwd=self.root).stdout.strip()
        run("git", "verify-commit", self.sha, cwd=self.root)

    def make_approval(self) -> dict:
        now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
        policy_bytes = self.policy_path.read_bytes()
        approval = {
            "schema": "soraswap-production-cutover-approval/v1",
            "environment": "production",
            "approval_id": "cutover-approval-2026-0001",
            "policy_sha256": digest(policy_bytes),
            "issued_at": (now - dt.timedelta(seconds=30)).isoformat().replace("+00:00", "Z"),
            "expires_at": (now + dt.timedelta(hours=1)).isoformat().replace("+00:00", "Z"),
            "review": {
                "identity": "security.approver",
                "reviewed_at": (now - dt.timedelta(seconds=30)).isoformat().replace("+00:00", "Z"),
                "independent": True,
            },
            "findings": {"unresolved_critical": 0, "unresolved_high": 0, "unresolved": []},
            "bindings": {
                "chain_fingerprint": {
                    "torii_url": self.chain["torii_url"],
                    "chain": self.chain["chain"],
                    "block_1_hash": self.chain["block_1_hash"],
                },
                "soraswap_git_sha": self.sha,
                "soraswap_tree_sha": self.tree,
                "soraswap_source_sha256": digest(canonical(self.source_state)),
                "iroha_git_sha": self.iroha_state["iroha_git_sha"],
                "bundle_name": self.iroha_state["bundle_name"],
                "checksums_sha256": self.iroha_state["checksums_sha256"],
                "manifest_sha256": self.iroha_state["manifest_sha256"],
                "irohad_sha256": self.iroha_state["irohad_sha256"],
                "iroha_sha256": self.iroha_state["iroha_sha256"],
                "kagami_sha256": self.iroha_state["kagami_sha256"],
                "archive_sha256": self.iroha_state["archive_sha256"],
                "archive_sidecar_sha256": self.iroha_state["archive_sidecar_sha256"],
                "irohad_features": ["embedded-soracloud-runtime", "sccp-test-fixtures"],
            },
            "authorities": dict(self.authorities),
            "minimum_fee_balance": "10",
            "controls": {
                "custody": "ticket://custody/approved-001",
                "rotation": "ticket://rotation/approved-001",
                "admin": "ticket://admin/approved-001",
                "pause": "ticket://pause/approved-001",
                "rollback": "ticket://rollback/approved-001",
                "monitoring": "ticket://monitoring/approved-001",
                "incident_response": "ticket://incident/approved-001",
            },
            "observation": {
                "monitoring_snapshot_url": "https://monitor.production.sora.org/cutover-snapshot",
                "maximum_monitoring_sample_age_seconds": 30,
                "validator_count": 4,
                "validator_set_sha256": self.validator_hash,
                "maximum_canonical_lead": 1,
                "maximum_finality_age_ms": 30000,
                "maximum_oracle_age_seconds": 60,
                "oracle_watch_sha256": self.oracle_hash,
                "minimum_fee_balance": "10",
                "balance_watch_sha256": self.balance_hash,
                "readonly_route_set_sha256": self.readonly_hash,
                "trader_api_probe_url": f"{self.chain['torii_url']}/v1/app-api/cid/{self.cid}",
                "trader_api_content_cid": self.cid,
                "trader_api_app_id": "soraswap.trader",
                "trader_api_routes_sha256": self.routes_hash,
                "derivatives_pause_mode": "external_fail_closed",
            },
            "signatures": [],
        }
        return approval

    def sign_approval(self, approval: dict | None = None) -> dict:
        approval = copy.deepcopy(approval or self.approval)
        payload = dict(approval)
        payload.pop("signatures", None)
        message = self.keys / "approval.message"
        message.write_bytes(canonical(payload))
        signatures = []
        for approver_id, key in (
            ("security.approver", self.security_key),
            ("operations.approver", self.operations_key),
        ):
            signature = message.with_suffix(".message.sig")
            signature.unlink(missing_ok=True)
            run("ssh-keygen", "-Y", "sign", "-f", str(key), "-n", NAMESPACE, str(message))
            signatures.append({
                "approver_id": approver_id,
                "signature_base64": base64.b64encode(signature.read_bytes()).decode("ascii"),
            })
        approval["signatures"] = signatures
        return approval

    def approval_args(self, evidence_mode: str = "--write-evidence") -> list[str]:
        return [
            "python3", str(APPROVAL_SCRIPT), "--root", str(self.root),
            "--policy", str(self.policy_path), "--approval", str(self.approval_path),
            "--expected-soraswap-sha", self.sha,
            "--soraswap-rc-state-json", json.dumps(self.rc_state),
            "--soraswap-source-state-json", json.dumps(self.source_state),
            "--iroha-state-json", json.dumps(self.iroha_state),
            "--chain-file", str(self.chain_path),
            "--signer-authority", self.authorities["signer"],
            "--oracle-authority", self.authorities["oracle"],
            "--admin-authority", self.authorities["admin"],
            "--treasury-authority", self.authorities["treasury"],
            "--bridge-authority", self.authorities["bridge"],
            "--minimum-fee-balance", "10", evidence_mode, str(self.approval_evidence),
        ]

    def verify_approval(self, approval: dict | None = None, evidence_mode: str = "--write-evidence") -> subprocess.CompletedProcess[str]:
        write_json(self.approval_path, self.sign_approval(approval), 0o600)
        return run(*self.approval_args(evidence_mode), check=False)

    def make_observation_inputs(self, approval_state: dict) -> tuple[Path, dict]:
        config = self.root / "config/production/production.client.toml"
        config.write_text(
            f'chain = "{self.chain["chain"]}"\n'
            f'torii_url = "{self.chain["torii_url"]}/"\n'
            '[account]\npublic_key = "ed0120' + "e" * 64 + '"\n'
            'private_key = "802620' + "f" * 64 + '"\nchain_discriminant = 753\n',
            encoding="utf-8",
        )
        config.chmod(0o600)
        fingerprint = approval_state["bindings"]["chain_fingerprint"]
        deploy = {"generated_at": "20260711T010000Z", "environment": "production", "status": "completed", "chain_fingerprint": fingerprint}
        contracts = {"generated_at": "20260711T010100Z", "environment": "production", "status": "completed", "chain_fingerprint": fingerprint}
        trader = {
            "generated_at": "20260711T010200Z", "environment": "production", "status": "completed",
            "chain_fingerprint": fingerprint, "app_id": "soraswap.trader", "content_cid": self.cid,
            "manifest_digest_hex": "d" * 64, "routes": self.routes,
            "cid_probe": {
                "status": "completed", "url": approval_state["observation"]["trader_api_probe_url"],
                "attempt_count": 2, "success_count": 2, "manifest_match_count": 2,
            },
        }
        write_json(self.root / "deployments/production/deploy.latest.json", deploy)
        write_json(self.root / "deployments/production/contracts.latest.json", contracts)
        write_json(self.root / "deployments/production/trader_api_bundle.latest.json", trader)
        return config, trader

    def samples(self, trader: dict) -> list[dict]:
        manifest = {
            "schema_version": 1, "app_id": trader["app_id"], "content_cid": trader["content_cid"],
            "manifest_digest_hex": trader["manifest_digest_hex"], "routes": trader["routes"],
        }
        trader_proof = {
            "app_id": trader["app_id"], "content_cid": trader["content_cid"],
            "routes_sha256": self.routes_hash, "manifest_sha256": digest(canonical(manifest)),
        }
        start = dt.datetime.now(dt.timezone.utc).replace(microsecond=0) - dt.timedelta(seconds=1800)
        result = []
        for index in range(61):
            sampled = start + dt.timedelta(seconds=index * 30)
            height = 1000 + index
            validators = []
            for validator_id in self.validator_ids:
                validators.append({
                    "id": validator_id, "status_block_height": height,
                    "canonical_height": height + 1, "commit_qc_height": height,
                    "highest_qc_height": height, "finality_age_ms": 1000,
                    "status_queue_size": 0, "status_queue_queued": 0,
                    "status_queue_inflight": 0, "proposal_queue_depth": 0,
                    "tx_queue_depth": 0, "oldest_queue_age_ms": 0,
                    "lane_backlog": 0, "api_failures": 0,
                })
            result.append({
                "sampled_at": sampled.isoformat().replace("+00:00", "Z"),
                "monitoring_sampled_at": sampled.isoformat().replace("+00:00", "Z"),
                "monitoring_sequence": index + 1,
                "status_block_height": height, "status_queue_size": 0,
                "status_queue_queued": 0, "status_queue_inflight": 0,
                "status_time_since_last_block_ms": 1000,
                "canonical_height": height + 1, "canonical_phase": "prepare",
                "commit_qc_height": height, "highest_qc_height": height,
                "proposal_queue_depth": 0, "tx_queue_depth": 0,
                "oldest_queue_age_ms": 0, "validators": validators,
                "validator_set_sha256": self.validator_hash, "api_failures": 0,
                "oracles": {
                    "watch_sha256": self.oracle_hash,
                    "feeds": [{"id": value, "age_seconds": 5} for value in self.oracle_ids],
                },
                "balances": {
                    "watch_sha256": self.balance_hash,
                    "entries": [
                        {"id": "balance.signer-fee", "kind": "signer_fee", "amount": "100"},
                        {"id": "balance.trader-usdt", "kind": "watched", "amount": "200"},
                        {"id": "balance.trader-xor", "kind": "watched", "amount": "300"},
                    ],
                },
                "readonly_routes": {"set_sha256": self.readonly_hash, "ok": True, "failure_count": 0},
                "trader_api": trader_proof, "shared_derivatives_regression": False,
                "derivatives_pause_mode": "external_fail_closed",
            })
        return result


class ProductionCutoverTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="soraswap-cutover-test.")
        self.base = Path(self.temporary.name).resolve()
        self.fixture = CutoverFixture(self.base)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def assert_failed(self, process: subprocess.CompletedProcess[str], text: str) -> None:
        self.assertNotEqual(process.returncode, 0, process.stdout)
        self.assertIn(text, process.stderr + process.stdout)

    def valid_state(self) -> dict:
        process = self.fixture.verify_approval()
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(os.stat(self.fixture.approval_evidence).st_mode & 0o777, 0o600)
        return json.loads(process.stdout)

    def test_signed_approval_and_evidence_revalidation(self) -> None:
        state = self.valid_state()
        self.assertEqual(state["schema"], "soraswap-production-cutover-approval-state/v1")
        second = self.fixture.verify_approval(evidence_mode="--verify-evidence")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(json.loads(second.stdout), state)

    def test_policy_requires_distinct_comment_free_ed25519_trust_anchors(self) -> None:
        duplicate = copy.deepcopy(self.fixture.policy)
        duplicate["trusted_approvers"][1]["public_key"] = duplicate["trusted_approvers"][0]["public_key"]
        with self.assertRaisesRegex(SystemExit, "distinct signing keys"):
            APPROVAL_MODULE.validate_policy(duplicate)

        commented = copy.deepcopy(self.fixture.policy)
        commented["trusted_approvers"][0]["public_key"] += " injected-comment"
        with self.assertRaisesRegex(SystemExit, "comment-free SSH Ed25519"):
            APPROVAL_MODULE.validate_policy(commented)

        weak = copy.deepcopy(self.fixture.policy)
        weak["required_signature_count"] = 1
        with self.assertRaisesRegex(SystemExit, "at least two independent signatures"):
            APPROVAL_MODULE.validate_policy(weak)

    def test_approval_rejects_schema_time_authority_and_origin_attacks(self) -> None:
        cases = []
        extra = copy.deepcopy(self.fixture.approval)
        extra["ignored"] = True
        cases.append((extra, "approval fields do not match"))
        expired = copy.deepcopy(self.fixture.approval)
        expired["expires_at"] = "2000-01-01T00:00:00Z"
        cases.append((expired, "approval expiry is stale"))
        cross_origin = copy.deepcopy(self.fixture.approval)
        cross_origin["observation"]["trader_api_probe_url"] = f"https://evil.production.sora.org/v1/app-api/cid/{self.fixture.cid}"
        cases.append((cross_origin, "probe URL/CID binding is invalid"))
        for approval, expected in cases[:3]:
            with self.subTest(expected=expected):
                process = self.fixture.verify_approval(approval)
                self.assert_failed(process, expected)

        duplicate_args = self.fixture.approval_args()
        duplicate_args[duplicate_args.index("--admin-authority") + 1] = self.fixture.authorities["signer"]
        duplicate = copy.deepcopy(self.fixture.approval)
        duplicate["authorities"]["admin"] = self.fixture.authorities["signer"]
        write_json(self.fixture.approval_path, self.fixture.sign_approval(duplicate), 0o600)
        process = run(*duplicate_args, check=False)
        self.assert_failed(process, "authorities must be distinct")

    def test_approval_rejects_link_mode_and_signature_attacks(self) -> None:
        write_json(self.fixture.approval_path, self.fixture.sign_approval(), 0o644)
        process = run(*self.fixture.approval_args(), check=False)
        self.assert_failed(process, "must have mode 0600")

        self.fixture.approval_path.unlink()
        target = self.base / "approval-target.json"
        write_json(target, self.fixture.sign_approval(), 0o600)
        self.fixture.approval_path.symlink_to(target)
        process = run(*self.fixture.approval_args(), check=False)
        self.assert_failed(process, "missing")

        self.fixture.approval_path.unlink()
        os.link(target, self.fixture.approval_path)
        process = run(*self.fixture.approval_args(), check=False)
        self.assert_failed(process, "exactly one hard link")

        self.fixture.approval_path.unlink()
        target.unlink()
        tampered = self.fixture.sign_approval()
        tampered["controls"]["pause"] = "ticket://pause/tampered-999"
        write_json(self.fixture.approval_path, tampered, 0o600)
        process = run(*self.fixture.approval_args(), check=False)
        self.assert_failed(process, "signature verification failed")

    def observer_process(self, state: dict, samples: list[dict], output: Path | None = None) -> subprocess.CompletedProcess[str]:
        config, trader = self.fixture.make_observation_inputs(state)
        fixture_path = self.base / "observation-fixture.json"
        write_json(fixture_path, {
            "schema": "soraswap-production-observation-fixture/v1",
            "wall_elapsed_seconds": 1800,
            "samples": samples,
        })
        output = output or self.base / "observation.json"
        args = [
            "python3", str(OBSERVER_SCRIPT), "--root", str(self.fixture.root),
            "--approval-state-json", json.dumps(state), "--client-config", str(config),
            "--chain-file", str(self.fixture.chain_path),
            "--soraswap-rc-state-json", json.dumps(self.fixture.rc_state),
            "--soraswap-source-state-json", json.dumps(self.fixture.source_state),
            "--iroha-state-json", json.dumps(self.fixture.iroha_state),
            "--deploy-file", str(self.fixture.root / "deployments/production/deploy.latest.json"),
            "--contracts-file", str(self.fixture.root / "deployments/production/contracts.latest.json"),
            "--trader-api-file", str(self.fixture.root / "deployments/production/trader_api_bundle.latest.json"),
            "--output", str(output), "--internal-test-fixture", str(fixture_path),
            "--internal-test-token", TEST_TOKEN,
        ]
        return run(*args, check=False)

    def test_observer_accepts_exact_61_sample_fixture_but_marks_it_test_only(self) -> None:
        state = self.valid_state()
        _, trader = self.fixture.make_observation_inputs(state)
        output = self.base / "observation.json"
        process = self.observer_process(state, self.fixture.samples(trader), output)
        self.assertEqual(process.returncode, 0, process.stderr)
        report = json.loads(output.read_text())
        self.assertTrue(report["test_only"])
        self.assertEqual(report["sample_count"], 61)
        self.assertEqual(report["summary"]["shared_derivatives_pause_outcome"], "not_required")

        shutil.copy2(output, self.fixture.root / "deployments/production/observation.latest.json")
        (self.fixture.root / "deployments/production/observation.latest.json").chmod(0o600)
        evidence_args = [
            "python3", str(EVIDENCE_SCRIPT), "--root", str(self.fixture.root),
            "--approval-state-json", json.dumps(state),
            "--soraswap-rc-state-json", json.dumps(self.fixture.rc_state),
            "--soraswap-source-state-json", json.dumps(self.fixture.source_state),
            "--iroha-state-json", json.dumps(self.fixture.iroha_state),
            "--chain-file", str(self.fixture.chain_path),
            "--deploy-file", str(self.fixture.root / "deployments/production/deploy.latest.json"),
            "--contracts-file", str(self.fixture.root / "deployments/production/contracts.latest.json"),
            "--trader-api-file", str(self.fixture.root / "deployments/production/trader_api_bundle.latest.json"),
            "--approval-evidence", str(self.fixture.approval_evidence),
            "--observation-evidence", str(self.fixture.root / "deployments/production/observation.latest.json"),
        ]
        rejected = run(*evidence_args, check=False)
        self.assert_failed(rejected, "not completed non-test production evidence")

    def test_observer_rejects_health_finality_and_pause_attacks(self) -> None:
        state = self.valid_state()
        _, trader = self.fixture.make_observation_inputs(state)
        baseline = self.fixture.samples(trader)
        mutations = [
            (lambda values: values[10].__setitem__("tx_queue_depth", 1), "queue or lane backlog"),
            (lambda values: values[10]["validators"][0].__setitem__("commit_qc_height", 999), "validators disagree"),
            (lambda values: values[10].__setitem__("status_block_height", 999), "committed block height is incoherent"),
            (lambda values: values[10].__setitem__("validator_set_sha256", "0" * 64), "validator set does not match"),
            (lambda values: values[10].__setitem__("api_failures", 1), "recorded API failures"),
            (lambda values: values[10]["oracles"]["feeds"][0].__setitem__("age_seconds", 61), "oracle freshness exceeded"),
            (lambda values: values[10]["balances"]["entries"][0].__setitem__("amount", "9"), "fee balance fell below"),
            (lambda values: values[10]["readonly_routes"].__setitem__("ok", False), "readonly routes regressed"),
            (lambda values: values[10].__setitem__("shared_derivatives_regression", True), "stopped without claiming that a pause was executed"),
            (lambda values: values[10]["trader_api"].__setitem__("content_cid", "b" + "z" * 52), "manifest/CID proof changed"),
            (lambda values: values[10]["balances"]["entries"][1].__setitem__("amount", "201"), "watched production balances changed"),
        ]
        for mutate, expected in mutations:
            with self.subTest(expected=expected):
                samples = copy.deepcopy(baseline)
                mutate(samples)
                process = self.observer_process(state, samples)
                self.assert_failed(process, expected)

    def test_live_collector_requires_exact_same_origin_torii_shapes_and_fresh_monitor_binding(self) -> None:
        state = self.valid_state()
        _, trader = self.fixture.make_observation_inputs(state)
        deploy_path = self.fixture.root / "deployments/production/deploy.latest.json"
        contracts_path = self.fixture.root / "deployments/production/contracts.latest.json"
        source_hash = digest(canonical(self.fixture.source_state))
        monitoring_bindings = {
            "chain_fingerprint": state["bindings"]["chain_fingerprint"],
            "soraswap_git_sha": self.fixture.sha,
            "soraswap_tree_sha": self.fixture.tree,
            "soraswap_source_sha256": source_hash,
            "iroha_state_sha256": digest(canonical(self.fixture.iroha_state)),
            "approval_id": state["approval_id"],
            "approval_sha256": state["approval_sha256"],
            "deploy_generated_at": json.loads(deploy_path.read_text())["generated_at"],
            "deploy_sha256": digest(deploy_path.read_bytes()),
            "contracts_generated_at": json.loads(contracts_path.read_text())["generated_at"],
            "contracts_sha256": digest(contracts_path.read_bytes()),
        }
        sample_template = self.fixture.samples(trader)[0]
        responses = {
            "/status/blocks": sample_template["status_block_height"],
            "/status": {
                "blocks": sample_template["status_block_height"],
                "queue_size": 0, "queue_queued": 0, "queue_inflight": 0,
                "time_since_last_block_ms": 1000,
            },
            "/v1/sumeragi/status": {
                "canonical": {"height": sample_template["canonical_height"], "phase": "prepare"},
                "commit_qc": {"height": sample_template["commit_qc_height"]},
                "highest_qc": {"height": sample_template["highest_qc_height"]},
                "proposal_gate": {"queue_len": 0},
                "tx_queue": {"depth": 0, "oldest_queued_age_ms": 0},
            },
            "/cutover-snapshot": {
                "schema": "soraswap-production-monitoring-snapshot/v1",
                "sampled_at": sample_template["sampled_at"], "sequence": 1,
                "bindings": monitoring_bindings,
                "validator_set_sha256": sample_template["validator_set_sha256"],
                "validators": sample_template["validators"], "api_failures": 0,
                "oracles": sample_template["oracles"], "balances": sample_template["balances"],
                "readonly_routes": sample_template["readonly_routes"],
                "shared_derivatives_regression": False,
            },
            f"/v1/app-api/cid/{self.fixture.cid}": {
                "schema_version": 1, "app_id": trader["app_id"],
                "content_cid": trader["content_cid"],
                "manifest_digest_hex": trader["manifest_digest_hex"], "routes": trader["routes"],
            },
        }
        calls = []

        def fetch(url, torii_origin, authorization, allow_auth):
            parsed = __import__("urllib.parse", fromlist=["urlsplit"]).urlsplit(url)
            calls.append((parsed.netloc, parsed.path, authorization, allow_auth))
            return responses[parsed.path]

        original = OBSERVER_MODULE.fetch_json_value
        OBSERVER_MODULE.fetch_json_value = fetch
        try:
            sample = OBSERVER_MODULE.collect_live_sample(
                state["bindings"]["chain_fingerprint"], state, trader,
                monitoring_bindings, self.fixture.chain["torii_url"], "Basic fixture-secret",
            )
        finally:
            OBSERVER_MODULE.fetch_json_value = original
        self.assertEqual(sample["status_block_height"], sample["commit_qc_height"])
        torii_calls = [item for item in calls if item[0] == "torii.production.sora.org"]
        self.assertTrue(torii_calls)
        self.assertTrue(all(item[2] == "Basic fixture-secret" and item[3] for item in torii_calls))
        monitoring_calls = [item for item in calls if item[0] == "monitor.production.sora.org"]
        self.assertEqual(monitoring_calls, [("monitor.production.sora.org", "/cutover-snapshot", "Basic fixture-secret", False)])

        responses["/status"]["blocks"] += 1
        OBSERVER_MODULE.fetch_json_value = fetch
        try:
            with self.assertRaisesRegex(SystemExit, "disagree on committed height"):
                OBSERVER_MODULE.collect_live_sample(
                    state["bindings"]["chain_fingerprint"], state, trader,
                    monitoring_bindings, self.fixture.chain["torii_url"], None,
                )
        finally:
            OBSERVER_MODULE.fetch_json_value = original

    def test_observer_rejects_cadence_sequence_and_input_link_attacks(self) -> None:
        state = self.valid_state()
        config, trader = self.fixture.make_observation_inputs(state)
        baseline = self.fixture.samples(trader)

        cadence = copy.deepcopy(baseline)
        cadence[10]["sampled_at"] = cadence[9]["sampled_at"]
        process = self.observer_process(state, cadence)
        self.assert_failed(process, "sample times are not strictly increasing")

        sequence = copy.deepcopy(baseline)
        sequence[10]["monitoring_sequence"] = sequence[9]["monitoring_sequence"]
        process = self.observer_process(state, sequence)
        self.assert_failed(process, "monitoring sequence was repeated")

        stale = copy.deepcopy(baseline)
        old = dt.datetime.fromisoformat(stale[10]["monitoring_sampled_at"].replace("Z", "+00:00")) - dt.timedelta(seconds=31)
        stale[10]["monitoring_sampled_at"] = old.isoformat().replace("+00:00", "Z")
        process = self.observer_process(state, stale)
        self.assert_failed(process, "monitoring snapshot is stale")

        original_chain = self.fixture.chain_path
        linked = self.base / "chain-hardlink.json"
        process = self.observer_process(state, baseline)
        self.assertEqual(process.returncode, 0, process.stderr)
        os.link(original_chain, linked)
        process = self.observer_process(state, baseline)
        self.assert_failed(process, "exactly one hard link")

    def test_release_runner_has_no_observation_bypass_and_preserves_twelve_phases(self) -> None:
        release = (REPO / "scripts/release_production.sh").read_text(encoding="utf-8")
        self.assertNotIn("--internal-test-fixture", release)
        self.assertNotIn("--internal-test-token", release)
        self.assertIn("release_phase_total=12", release)
        self.assertIn('if [[ "$target" == "release-production-checklist" ]]; then\n      run_production_cutover_observation', release)
        self.assertIn(
            'run_target release-production-checklist \\\n'
            '  "$production_dir/observation.latest.json"',
            release,
        )
        configure_call = release.rfind("\nconfigure_production_cutover_inputs\n")
        journal_call = release.rfind("\nphase_journal_token=")
        first_phase = release.rfind("\nSORASWAP_PREFLIGHT_SKIP_EXISTING_NESTED_PROBE_CHECK=1 run_target")
        self.assertGreater(configure_call, 0)
        self.assertLess(configure_call, journal_call)
        self.assertLess(journal_call, first_phase)
        for setting in (
            "SORASWAP_PRODUCTION_OBSERVATION_DURATION_SECS",
            "SORASWAP_PRODUCTION_OBSERVATION_FIXTURE",
            "SORASWAP_PRODUCTION_OBSERVATION_SAMPLE_COMMAND",
        ):
            self.assertIn(setting, release)


if __name__ == "__main__":
    unittest.main(verbosity=2)
