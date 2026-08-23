#!/usr/bin/env python3

from __future__ import annotations

import copy
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import validate_validation_fee_write_gate as write_gate  # noqa: E402


NOW = datetime(2026, 7, 25, 12, 0, 0, tzinfo=timezone.utc)
CHECKPOINT_HEIGHT = 8_192
CHECKPOINT_HASH = "b" * 64
BLOCK_1_HASH = "1" * 64
PLAN_SHA256 = "f" * 64


def prepared_transaction() -> dict[str, str]:
    return {
        "tx_hash": "b" * 64,
        "tx_hash_hex": "b" * 64,
    }


def hajimari_arguments(
    vault_account: str = write_gate.POOL_SUBJECT_ACCOUNT_ID,
) -> dict[str, Any]:
    return {
        "base_asset": write_gate.XOR_ASSET_ID,
        "quote_asset": write_gate.SBD_ASSET_ID,
        "vault_account": vault_account,
        "fee_pips": 3000,
        "bin_step": 1,
        "active_bin": 0,
        "impact_cap_bps": 10000,
        "min_reserve_base": 0,
        "min_reserve_quote": 0,
        "max_bins_per_swap": 8,
        "bin_liquidity_cap": 0,
    }


def rfc3339(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def gate_request(
    *,
    sequence: int = 1,
    previous_observation: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "schema": write_gate.REQUEST_SCHEMA,
        "chain_id": write_gate.CHAIN_ID,
        "chain_discriminant": write_gate.CHAIN_DISCRIMINANT,
        "block_1_hash": BLOCK_1_HASH,
        "plan_sha256": PLAN_SHA256,
        "authority_account_id": write_gate.AUTHORITY_ACCOUNT_ID,
        "sequence": sequence,
        "invocation_id": f"offline-write-{sequence}",
        "operation": {
            "kind": "account_registration",
            "plan_sha256": PLAN_SHA256,
            "account_id": "testofflinefixture",
            "purpose": "pool_contract_subject",
            "payload_sha256": "c" * 64,
            "payload_size_bytes": 1_024,
            "transaction": prepared_transaction(),
        },
        "gate_command_sha256": "a" * 64,
        "previous_observation": previous_observation,
        "direct": [
            {"name": name, "url": url}
            for name, url in write_gate.DIRECT_ENDPOINTS
        ],
        "public": {
            "name": write_gate.PUBLIC_ENDPOINT[0],
            "url": write_gate.PUBLIC_ENDPOINT[1],
        },
        "mcp": {
            "endpoint": write_gate.MCP_ENDPOINT,
            "tools": list(write_gate.MCP_TOOLS),
        },
    }


def checkpoint_observation(
    name: str,
    url: str,
    *,
    height: int,
    block_hash: str,
) -> dict[str, Any]:
    return {
        "name": name,
        "url": url,
        "healthy": True,
        "checks": list(write_gate.CHECKS),
        "chain_id": write_gate.CHAIN_ID,
        "chain_discriminant": write_gate.CHAIN_DISCRIMINANT,
        "block_1_hash": BLOCK_1_HASH,
        "block_height": height,
        "block_hash": block_hash,
    }


def gate_marker(
    request: dict[str, Any],
    *,
    created_at: datetime = NOW - timedelta(seconds=5),
    expires_at: datetime = NOW + timedelta(seconds=30),
    height: int = CHECKPOINT_HEIGHT,
    block_hash: str = CHECKPOINT_HASH,
) -> dict[str, Any]:
    previous = request["previous_observation"]
    return {
        "schema": write_gate.MARKER_SCHEMA,
        "request_sha256": write_gate.sha256(request),
        "chain_id": request["chain_id"],
        "chain_discriminant": request["chain_discriminant"],
        "block_1_hash": request["block_1_hash"],
        "plan_sha256": request["plan_sha256"],
        "authority_account_id": request["authority_account_id"],
        "sequence": request["sequence"],
        "invocation_id": request["invocation_id"],
        "operation": copy.deepcopy(request["operation"]),
        "gate_command_sha256": request["gate_command_sha256"],
        "created_at": rfc3339(created_at),
        "expires_at": rfc3339(expires_at),
        "consensus": {
            "block_height": height,
            "block_hash": block_hash,
        },
        "previous_observation": (
            None
            if previous is None
            else {**copy.deepcopy(previous), "verified_ancestor": True}
        ),
        "direct": [
            checkpoint_observation(
                name,
                url,
                height=height,
                block_hash=block_hash,
            )
            for name, url in write_gate.DIRECT_ENDPOINTS
        ],
        "public": checkpoint_observation(
            write_gate.PUBLIC_ENDPOINT[0],
            write_gate.PUBLIC_ENDPOINT[1],
            height=height,
            block_hash=block_hash,
        ),
        "mcp": {
            "endpoint": write_gate.MCP_ENDPOINT,
            "tools": list(write_gate.MCP_TOOLS),
            "healthy": True,
            "chain_id": write_gate.CHAIN_ID,
            "chain_discriminant": write_gate.CHAIN_DISCRIMINANT,
            "block_1_hash": BLOCK_1_HASH,
            "block_height": height,
            "block_hash": block_hash,
        },
    }


class ValidationFeeWriteGateTests(unittest.TestCase):
    def validate(
        self,
        request: dict[str, Any],
        marker: dict[str, Any],
    ) -> dict[str, Any]:
        checked_request = write_gate.validate_request(
            copy.deepcopy(request),
            PLAN_SHA256,
        )
        return write_gate.validate_marker(
            copy.deepcopy(marker),
            checked_request,
            now=NOW,
            max_age_seconds=60,
        )

    def test_valid_fresh_marker_is_accepted(self) -> None:
        request = gate_request()
        marker = gate_marker(request)

        self.assertEqual(self.validate(request, marker), marker)

    def test_stale_marker_is_rejected(self) -> None:
        request = gate_request()
        marker = gate_marker(
            request,
            created_at=NOW - timedelta(seconds=61),
            expires_at=NOW + timedelta(seconds=30),
        )

        with self.assertRaisesRegex(
            write_gate.Refusal,
            "too old for an immediate write",
        ):
            self.validate(request, marker)

    def test_unhealthy_or_incomplete_direct_check_is_rejected(self) -> None:
        request = gate_request()
        healthy_marker = gate_marker(request)
        altered_markers = []

        unhealthy = copy.deepcopy(healthy_marker)
        unhealthy["direct"][0]["healthy"] = False
        altered_markers.append(unhealthy)

        incomplete_checks = copy.deepcopy(healthy_marker)
        incomplete_checks["direct"][2]["checks"].remove("node.capabilities")
        altered_markers.append(incomplete_checks)

        for marker in altered_markers:
            with self.subTest(marker=marker["direct"]):
                with self.assertRaisesRegex(
                    write_gate.Refusal,
                    "direct gate observation",
                ):
                    self.validate(request, marker)

    def test_mcp_or_consensus_mismatch_is_rejected(self) -> None:
        request = gate_request()
        healthy_marker = gate_marker(request)

        mcp_mismatch = copy.deepcopy(healthy_marker)
        mcp_mismatch["mcp"]["block_height"] += 1
        with self.assertRaisesRegex(
            write_gate.Refusal,
            "MCP observation is not exact",
        ):
            self.validate(request, mcp_mismatch)

        consensus_mismatch = copy.deepcopy(healthy_marker)
        consensus_mismatch["consensus"]["block_hash"] = "c" * 64
        with self.assertRaisesRegex(
            write_gate.Refusal,
            "checkpoint observation",
        ):
            self.validate(request, consensus_mismatch)

    def test_checkpoint_rollback_and_equivocation_are_rejected(self) -> None:
        previous = {
            "sha256": "d" * 64,
            "block_height": CHECKPOINT_HEIGHT,
            "block_hash": CHECKPOINT_HASH,
            "created_at": rfc3339(NOW - timedelta(seconds=20)),
        }
        request = gate_request(sequence=2, previous_observation=previous)

        rollback = gate_marker(
            request,
            height=CHECKPOINT_HEIGHT - 1,
            block_hash="e" * 64,
        )
        with self.assertRaisesRegex(
            write_gate.Refusal,
            "checkpoint rollback detected",
        ):
            self.validate(request, rollback)

        equivocation = gate_marker(
            request,
            height=CHECKPOINT_HEIGHT,
            block_hash="e" * 64,
        )
        with self.assertRaisesRegex(
            write_gate.Refusal,
            "same-height equivocation detected",
        ):
            self.validate(request, equivocation)

    def test_block_1_mismatch_is_rejected_on_every_surface(self) -> None:
        request = gate_request()
        healthy_marker = gate_marker(request)

        for surface in ("direct", "public", "mcp"):
            marker = copy.deepcopy(healthy_marker)
            if surface == "direct":
                marker["direct"][0]["block_1_hash"] = "2" * 64
            else:
                marker[surface]["block_1_hash"] = "2" * 64
            with self.subTest(surface=surface):
                with self.assertRaises(write_gate.Refusal):
                    self.validate(request, marker)

    def test_operation_unknown_fields_and_unsupported_selectors_are_rejected(
        self,
    ) -> None:
        operations = [
            {
                "kind": "account_registration",
                "plan_sha256": PLAN_SHA256,
                "account_id": "testfixture",
                "purpose": "pool_contract_subject",
                "payload_sha256": "c" * 64,
                "payload_size_bytes": 1_024,
                "transaction": prepared_transaction(),
                "extra": True,
            },
            {
                "kind": "permission_grant",
                "plan_sha256": PLAN_SHA256,
                "account_id": "testfixture",
                "permission": {
                    "name": "CanInvokeContractEntrypoint",
                    "payload": {
                        "contract": "tairac1fixture",
                        "entrypoint": "iroha.custom",
                    },
                },
                "payload_sha256": "c" * 64,
                "payload_size_bytes": 1_024,
                "transaction": prepared_transaction(),
            },
            {
                "kind": "split_deploy_transaction",
                "plan_sha256": PLAN_SHA256,
                "contract_key": "pool",
                "contract_alias": "dlmm_pool::dlmm.universal",
                "label": "commit",
                "payload_sha256": "a" * 64,
                "transaction": {
                    "tx_hash": "b" * 64,
                    "tx_hash_hex": "c" * 64,
                },
            },
            {
                "kind": "contract_call",
                "plan_sha256": PLAN_SHA256,
                "contract_address": "tairac1fixture",
                "entrypoint": "seed_bin",
                "arguments": {
                    "position_id": "validation_fee_seed_bin_0",
                    "bin_id": 0,
                    "base_amount": 1000,
                    "quote_amount": 1000,
                    "extra": 1,
                },
            },
        ]
        for operation in operations:
            request = gate_request()
            request["operation"] = operation
            with self.subTest(operation=operation):
                with self.assertRaises(write_gate.Refusal):
                    write_gate.validate_request(request, PLAN_SHA256)

    def test_prepared_ledger_binding_and_plan_mismatch_are_rejected(self) -> None:
        request = gate_request()
        invalid_operations = []

        wrong_plan = copy.deepcopy(request["operation"])
        wrong_plan["plan_sha256"] = "e" * 64
        invalid_operations.append(wrong_plan)

        mismatched_hash = copy.deepcopy(request["operation"])
        mismatched_hash["transaction"]["tx_hash_hex"] = "d" * 64
        invalid_operations.append(mismatched_hash)

        zero_size = copy.deepcopy(request["operation"])
        zero_size["payload_size_bytes"] = 0
        invalid_operations.append(zero_size)

        oversized = copy.deepcopy(request["operation"])
        oversized["payload_size_bytes"] = 16 * 1024 * 1024 + 1
        invalid_operations.append(oversized)

        missing_payload_digest = copy.deepcopy(request["operation"])
        del missing_payload_digest["payload_sha256"]
        invalid_operations.append(missing_payload_digest)

        for operation in invalid_operations:
            candidate = gate_request()
            candidate["operation"] = operation
            with self.subTest(operation=operation):
                with self.assertRaises(write_gate.Refusal):
                    write_gate.validate_request(candidate, PLAN_SHA256)

        top_level_mismatch = gate_request()
        top_level_mismatch["plan_sha256"] = "e" * 64
        with self.assertRaisesRegex(
            write_gate.Refusal,
            "exact reviewed P1 plan",
        ):
            write_gate.validate_request(top_level_mismatch, PLAN_SHA256)

    def test_contract_calls_require_exact_reviewed_pool_selectors(self) -> None:
        exact_operations = [
            {
                "kind": "contract_call",
                "plan_sha256": PLAN_SHA256,
                "contract_address": write_gate.POOL_CONTRACT_ADDRESS,
                "entrypoint": "hajimari",
                "arguments": hajimari_arguments(),
            },
            {
                "kind": "contract_call",
                "plan_sha256": PLAN_SHA256,
                "contract_address": write_gate.POOL_CONTRACT_ADDRESS,
                "entrypoint": "seed_bin",
                "arguments": {
                    "position_id": "validation_fee_seed_bin_0",
                    "bin_id": 0,
                    "base_amount": 1000,
                    "quote_amount": 1000,
                },
            },
            {
                "kind": "contract_call",
                "plan_sha256": PLAN_SHA256,
                "contract_address": write_gate.POOL_CONTRACT_ADDRESS,
                "entrypoint": "renounce_admin",
                "arguments": {},
            },
        ]
        for operation in exact_operations:
            with self.subTest(entrypoint=operation["entrypoint"]):
                self.assertEqual(
                    write_gate.validate_operation(operation, PLAN_SHA256),
                    operation,
                )

        alternate_contract = copy.deepcopy(exact_operations[1])
        alternate_contract["contract_address"] = "tairac1alternatevalidtarget"
        with self.assertRaisesRegex(
            write_gate.Refusal,
            "exact reviewed P1 pool contract",
        ):
            write_gate.validate_operation(alternate_contract, PLAN_SHA256)

        alternate_subject = copy.deepcopy(exact_operations[0])
        alternate_subject["arguments"] = hajimari_arguments(
            "testalternatevalidpoolsubject"
        )
        with self.assertRaisesRegex(
            write_gate.Refusal,
            "exact reviewed P1 pool subject",
        ):
            write_gate.validate_operation(alternate_subject, PLAN_SHA256)

    def test_unresolved_zero_reviewed_plan_digest_is_rejected(self) -> None:
        request = gate_request()
        request["plan_sha256"] = "0" * 64
        request["operation"]["plan_sha256"] = "0" * 64
        with self.assertRaisesRegex(
            write_gate.Refusal,
            "expected reviewed P1 plan SHA-256 is invalid",
        ):
            write_gate.validate_request(request, "0" * 64)

    def test_duplicate_top_level_key_is_rejected(self) -> None:
        with self.assertRaisesRegex(write_gate.Refusal, "duplicate object key"):
            write_gate.strict_json(
                '{"schema":"first","schema":"second"}',
                "fixture",
            )

    def test_duplicate_nested_operation_key_is_rejected(self) -> None:
        with self.assertRaisesRegex(write_gate.Refusal, "duplicate object key"):
            write_gate.strict_json(
                '{"operation":{"kind":"first","kind":"second"}}',
                "fixture",
            )

    def test_duplicate_nested_consensus_key_is_rejected(self) -> None:
        with self.assertRaisesRegex(write_gate.Refusal, "duplicate object key"):
            write_gate.strict_json(
                '{"consensus":{"block_height":1,"block_height":2}}',
                "fixture",
            )

    def test_nonfinite_numbers_are_rejected(self) -> None:
        for value in ("NaN", "Infinity", "-Infinity"):
            with self.subTest(value=value):
                with self.assertRaisesRegex(
                    write_gate.Refusal,
                    "non-finite number",
                ):
                    write_gate.strict_json(
                        f'{{"value":{value}}}',
                        "fixture",
                    )


if __name__ == "__main__":
    unittest.main()
