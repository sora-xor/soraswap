#!/usr/bin/env python3
"""Verify the pending Taira payout binding against one rendered genesis."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

import render_validation_fee_payout as renderer


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_BINDING = (
    ROOT / "config" / "validation_fee" / "autonomous-payout.taira.pending.json"
)
DEFAULT_PROVENANCE = DEFAULT_BINDING.with_name(
    "autonomous-payout.taira.pending.provenance.json"
)
TAG = "taira_validator_payout_recipient"
LIVE_PLACEHOLDERS = {
    "pool_contract_address": "<LIVE_TAIRA_DLMM_CONTRACT_ADDRESS_REQUIRED>",
    "pool_vault_account_id": "<LIVE_TAIRA_DLMM_POOL_VAULT_ACCOUNT_ID_REQUIRED>",
    "payout_vault_account_id": (
        "<LIVE_TAIRA_PAYOUT_CONTRACT_SUBJECT_ACCOUNT_ID_REQUIRED>"
    ),
}


class VerificationError(ValueError):
    """Raised when genesis and pending binding provenance diverge."""


def _read_json(path: Path) -> Any:
    return renderer.parse_config_text(path.read_text(encoding="utf-8"))


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def _tagged_accounts(genesis: dict[str, Any]) -> list[str]:
    accounts: list[str] = []
    transactions = genesis.get("transactions")
    _require(isinstance(transactions, list), "genesis transactions must be a list")
    for transaction in transactions:
        if not isinstance(transaction, dict):
            continue
        instructions = transaction.get("instructions", [])
        if not isinstance(instructions, list):
            continue
        for instruction in instructions:
            if not isinstance(instruction, dict):
                continue
            register = instruction.get("Register")
            if not isinstance(register, dict):
                continue
            account = register.get("Account")
            if not isinstance(account, dict):
                continue
            metadata = account.get("metadata")
            if not isinstance(metadata, dict) or metadata.get("purpose") != TAG:
                continue
            account_id = account.get("id")
            _require(isinstance(account_id, str), "tagged account id must be a string")
            accounts.append(account_id)
    _require(len(accounts) == 4, "genesis must contain exactly four tagged payout accounts")
    _require(len(set(accounts)) == 4, "tagged payout accounts must be unique")
    return accounts


def verify(genesis_path: Path, binding_path: Path, provenance_path: Path) -> dict[str, Any]:
    genesis_bytes = genesis_path.read_bytes()
    genesis = renderer.parse_config_text(genesis_bytes.decode("utf-8"))
    binding = _read_json(binding_path)
    provenance = _read_json(provenance_path)
    _require(isinstance(genesis, dict), "genesis must be a JSON object")
    _require(isinstance(binding, dict), "binding must be a JSON object")
    _require(isinstance(provenance, dict), "provenance must be a JSON object")
    _require(set(binding) == renderer.EXPECTED_FIELDS, "binding fields are not exact")
    _require(
        type(binding.get("schema_version")) is int
        and binding["schema_version"] == 1,
        "binding schema_version must be exactly 1",
    )
    _require(
        set(provenance)
        == {
            "schema_version",
            "network",
            "status",
            "binding_file",
            "genesis",
            "unresolved_live_fields",
            "fixed_policy",
            "immutable_topology",
        },
        "provenance fields are not exact",
    )
    _require(
        type(provenance.get("schema_version")) is int
        and provenance["schema_version"] == 1,
        "unsupported provenance schema",
    )
    _require(provenance.get("network") == "taira", "provenance network must be Taira")
    _require(
        provenance.get("status") == "awaiting_live_deploy",
        "provenance status must remain pending",
    )
    _require(
        provenance.get("binding_file") == binding_path.name,
        "provenance binding filename mismatch",
    )

    genesis_provenance = provenance.get("genesis")
    _require(isinstance(genesis_provenance, dict), "provenance genesis must be an object")
    digest = hashlib.sha256(genesis_bytes).hexdigest()
    _require(digest == genesis_provenance.get("sha256"), "genesis SHA-256 mismatch")
    for genesis_field, provenance_field in (
        ("chain", "chain_id"),
        ("chain_discriminant", "chain_discriminant"),
        ("consensus_mode", "consensus_mode"),
        ("consensus_fingerprint", "consensus_fingerprint"),
    ):
        _require(
            genesis.get(genesis_field) == genesis_provenance.get(provenance_field),
            f"genesis {genesis_field} does not match provenance",
        )
    _require(
        genesis_provenance.get("validator_account_metadata_purpose") == TAG,
        "unexpected validator account metadata purpose",
    )

    recipients = _tagged_accounts(genesis)
    _require(
        recipients == binding.get("recipient_account_ids"),
        "pending recipients differ from tagged genesis accounts",
    )
    _require(
        genesis_provenance.get("tagged_account_count") == len(recipients),
        "tagged account count differs from provenance",
    )
    _require(
        provenance.get("unresolved_live_fields") == list(LIVE_PLACEHOLDERS),
        "unresolved live-field list is not exact",
    )
    for field, placeholder in LIVE_PLACEHOLDERS.items():
        _require(binding.get(field) == placeholder, f"{field} is not the required live marker")

    fixed_policy = provenance.get("fixed_policy")
    _require(isinstance(fixed_policy, dict), "fixed policy must be an object")
    expected_policy = {
        "base_asset_definition_id": binding.get("xor_asset_definition_id"),
        "quote_asset_definition_id": binding.get("sbd_asset_definition_id"),
        "exact_quote_input": binding.get("batch_sbd"),
        "minimum_base_output": binding.get("min_xor_out"),
        "maximum_base_output": binding.get("max_xor_out"),
        "recipient_count": len(recipients),
        "distribution": "four_equal_shares",
    }
    _require(fixed_policy == expected_policy, "fixed policy differs from pending binding")
    expected_topology = {
        "contract": "validation_fee.autonomous_payout",
        "mutating_entrypoints": ["autonomous_validation_fee_tick"],
        "entrypoint_permission": "CanInvokeContractEntrypoint",
        "trigger": {
            "id": "validation_fee_autonomous_payout",
            "filter": "time.pre_commit",
            "repetitions": "indefinite",
            "authority_binding": "payout_vault_account_id",
        },
        "nested_call": {
            "contract_binding": "pool_contract_address",
            "entrypoint": "swap_exact_in_quote_public",
            "entrypoint_permission": "CanInvokeContractEntrypoint",
            "return_type": "quantity",
            "caller_funded": True,
            "full_fill": True,
        },
        "permission_topology": {
            "direct_only": True,
            "role_holders": False,
            "wrapper_subject_binding": "payout_vault_account_id",
            "pool_subject_binding": "pool_vault_account_id",
            "pool_sbd_transfer": {
                "permission": "CanTransferAsset",
                "asset_definition_binding": "quote_asset_definition_id",
                "asset_account_binding": "payout_vault_account_id",
                "holder_binding": "pool_vault_account_id",
                "scope": "dataspace:0",
                "provisioned_by": "protected_core_validation_fee_lifecycle",
                "external_bootstrap_grant": False,
            },
        },
        "mutable_configuration": False,
        "owner_or_admin": False,
        "manual_entrypoint": False,
        "generic_sponsorship": False,
    }
    _require(
        provenance.get("immutable_topology") == expected_topology,
        "immutable topology differs from the supported wrapper",
    )

    return {
        "binding": str(binding_path),
        "genesis_sha256": digest,
        "provenance": str(provenance_path),
        "recipient_account_ids": recipients,
        "status": "verified_pending_live_deploy",
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify the pending payout binding against rendered Taira genesis"
    )
    parser.add_argument("genesis", type=Path)
    parser.add_argument("--binding", type=Path, default=DEFAULT_BINDING)
    parser.add_argument("--provenance", type=Path, default=DEFAULT_PROVENANCE)
    args = parser.parse_args()
    try:
        report = verify(args.genesis, args.binding, args.provenance)
    except (
        FileNotFoundError,
        UnicodeDecodeError,
        json.JSONDecodeError,
        renderer.ConfigError,
        VerificationError,
    ) as error:
        print(f"verify validation-fee Taira binding: {error}", file=sys.stderr)
        return 2
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
