#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import validate_validation_fee_plan_binding as plan_binding  # noqa: E402
import validate_validation_fee_prepared_ledger as prepared  # noqa: E402


def canonical(value: Any) -> bytes:
    return json.dumps(
        value,
        allow_nan=False,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode()


def fixture_plan() -> dict[str, Any]:
    return {
        "schema_version": 1,
        "status": "undeployed_plan",
        "network": "taira",
        "chain_id": plan_binding.CHAIN_ID,
        "chain_discriminant": plan_binding.CHAIN_DISCRIMINANT,
        "genesis_sha256": "1" * 64,
        "authority_account_id": plan_binding.AUTHORITY_ACCOUNT_ID,
        "dataspace": "universal",
        "deployment_spec_sha256": "2" * 64,
        "required_starting_deploy_nonce": 0,
        "required_final_deploy_nonce": 2,
        "sequence": [],
        "contracts": [],
        "payout_binding": {},
        "protected_permissions": [],
        "preconditions": {},
        "prohibited_actions": {
            "protected_permission_grants": True,
            "role_grants": True,
            "parliament_activation": True,
            "validation_fee_lifecycle_activation": True,
        },
        "toolchain": {},
    }


class PlanBindingTests(unittest.TestCase):
    def test_exact_canonical_plan_digest_is_required(self) -> None:
        plan = fixture_plan()
        digest = hashlib.sha256(canonical(plan)).hexdigest()
        evidence = {
            "schema_version": 1,
            "phase": "plan",
            "plan_sha256": digest,
            "payload": {
                "result": {"plan": plan, "plan_sha256": digest},
                "write_gate_command_sha256": "3" * 64,
                "state_binding_sha256": "4" * 64,
                "block_1_hash": "5" * 64,
            },
        }
        self.assertEqual(plan_binding.validate(evidence, digest), digest)
        evidence["payload"]["result"]["plan"]["network"] = "minamoto"
        with self.assertRaises(plan_binding.Refusal):
            plan_binding.validate(evidence, digest)

    def test_duplicate_json_is_rejected(self) -> None:
        with self.assertRaises(plan_binding.Refusal):
            plan_binding.strict_json(b'{"phase":"plan","phase":"legacy"}', "fixture")


class PreparedLedgerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.prepared_dir = self.root / "prepared"
        self.prepared_dir.mkdir()
        self.operation = {
            "kind": "account_registration",
            "plan_sha256": "a" * 64,
            "account_id": "testfixture",
            "purpose": "pool_contract_subject",
        }
        self.operation_path = self.root / "operation.json"
        self.operation_path.write_bytes(canonical(self.operation) + b"\n")
        self.operation_path.chmod(0o600)
        payload = b"typed-norito-fixture"
        (self.prepared_dir / "transaction.norito").write_bytes(payload)
        (self.prepared_dir / "transaction.norito").chmod(0o444)
        operation_sha = hashlib.sha256(canonical(self.operation)).hexdigest()
        self.wrapper = {
            "schema_version": 1,
            "phase": "prepared_validation_fee_ledger_transaction",
            "plan_sha256": "a" * 64,
            "adapter_binary_sha256": "b" * 64,
            "manifest": {
                "schema": prepared.MANIFEST_SCHEMA,
                "plan_sha256": "a" * 64,
                "operation_sha256": operation_sha,
                "operation": self.operation,
                "chain_id": prepared.CHAIN_ID,
                "chain_discriminant": prepared.CHAIN_DISCRIMINANT,
                "authority_account_id": prepared.AUTHORITY_ACCOUNT_ID,
                "iroha_source": {
                    "commit": prepared.IROHA_COMMIT,
                    "source_fingerprint_sha256":
                        prepared.IROHA_SOURCE_FINGERPRINT_SHA256,
                    "tracked_diff_sha256": prepared.IROHA_TRACKED_DIFF_SHA256,
                },
                "adapter_source_sha256": "c" * 64,
                "payload": {
                    "file": "transaction.norito",
                    "size_bytes": len(payload),
                    "sha256": hashlib.sha256(payload).hexdigest(),
                },
                "transaction": {
                    "tx_hash": "d" * 64,
                    "tx_hash_hex": "d" * 64,
                },
            },
        }
        (self.prepared_dir / "plan.json").write_bytes(
            canonical(self.wrapper) + b"\n"
        )
        (self.prepared_dir / "plan.json").chmod(0o444)
        self.prepared_dir.chmod(0o555)

    def tearDown(self) -> None:
        self.prepared_dir.chmod(0o755)
        for path in self.prepared_dir.iterdir():
            path.chmod(0o600)
        self.temporary.cleanup()

    def test_structurally_exact_frozen_package_is_accepted(self) -> None:
        self.assertEqual(
            prepared.validate(
                self.prepared_dir,
                self.operation_path,
                "a" * 64,
                "b" * 64,
                "c" * 64,
            ),
            self.wrapper,
        )

    def test_unknown_manifest_field_is_rejected(self) -> None:
        self.prepared_dir.chmod(0o755)
        plan_path = self.prepared_dir / "plan.json"
        plan_path.chmod(0o600)
        self.wrapper["manifest"]["legacy"] = True
        plan_path.write_bytes(canonical(self.wrapper) + b"\n")
        plan_path.chmod(0o444)
        self.prepared_dir.chmod(0o555)
        with self.assertRaises(prepared.Refusal):
            prepared.validate(
                self.prepared_dir,
                self.operation_path,
                "a" * 64,
                "b" * 64,
                "c" * 64,
            )

    def test_payload_size_or_digest_drift_is_rejected(self) -> None:
        self.prepared_dir.chmod(0o755)
        payload_path = self.prepared_dir / "transaction.norito"
        payload_path.chmod(0o600)
        payload_path.write_bytes(b"changed")
        payload_path.chmod(0o444)
        self.prepared_dir.chmod(0o555)
        with self.assertRaises(prepared.Refusal):
            prepared.validate(
                self.prepared_dir,
                self.operation_path,
                "a" * 64,
                "b" * 64,
                "c" * 64,
            )

    def test_adapter_source_digest_must_match_reviewed_build(self) -> None:
        with self.assertRaises(prepared.Refusal):
            prepared.validate(
                self.prepared_dir,
                self.operation_path,
                "a" * 64,
                "b" * 64,
                "e" * 64,
            )


if __name__ == "__main__":
    unittest.main()
