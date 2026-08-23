import importlib.util
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "render_validation_fee_payout.py"
VERIFY_TAIRA_SCRIPT = ROOT / "scripts" / "verify_validation_fee_taira_binding.py"
PAYOUT_WORKFLOW = ROOT / "scripts" / "validation_fee_payout.sh"
FIXTURE = ROOT / "tests" / "fixtures" / "validation_fee" / "autonomous-payout.test.json"
TAIRA_PENDING = (
    ROOT / "config" / "validation_fee" / "autonomous-payout.taira.pending.json"
)
TAIRA_PROVENANCE = (
    ROOT
    / "config"
    / "validation_fee"
    / "autonomous-payout.taira.pending.provenance.json"
)
TAIRA_GENESIS_SHA256 = (
    "766910cc2cd4916701c17f00d8f0cad23da0d19774bfad82e3d42442b26178cc"
)

SPEC = importlib.util.spec_from_file_location("render_validation_fee_payout", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
RENDERER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RENDERER)


class RenderValidationFeePayoutTests(unittest.TestCase):
    def fixture(self):
        return json.loads(FIXTURE.read_text(encoding="utf-8"))

    def test_exact_binding_renders_a_trigger_only_source(self):
        config = RENDERER.validate_config(self.fixture())
        source = RENDERER.render_source(config)
        self.assertTrue(config["pool_vault_account_id"].startswith("test"))
        self.assertTrue(config["payout_vault_account_id"].startswith("test"))
        self.assertTrue(
            all(
                account.startswith("test")
                for account in config["recipient_account_ids"]
            )
        )
        self.assertNotIn("@@", source)
        self.assertEqual(source.count("kotoage fn "), 1)
        self.assertIn(f'b"{config["pool_contract_address"]}"', source)
        self.assertIn(
            f'AccountId::parse("{config["pool_vault_account_id"]}")',
            source,
        )
        self.assertGreaterEqual(
            source.count(f'"{config["payout_vault_account_id"]}"'),
            2,
        )
        for recipient in config["recipient_account_ids"]:
            self.assertEqual(source.count(f'"{recipient}"'), 1)
        self.assertIn("autonomous_validation_fee_tick", source)
        self.assertIn('authorize("CanInvokeContractEntrypoint")', source)
        self.assertNotIn('authorize("ValidationFeePayout")', source)
        self.assertIn("on time pre_commit", source)
        self.assertIn("repeats indefinitely", source)
        self.assertIn("swap_exact_in_quote_public", source)
        self.assertIn("let quantity amount = 10", source)
        self.assertIn("let quantity amount = 4", source)
        self.assertIn("let quantity amount = 100", source)
        self.assertIn("context::authority() == vault", source)
        self.assertIn("context::seiyaku_subject() == vault", source)
        self.assertIn("if sbd_before < batch_sbd()", source)
        self.assertIn(
            "if ledger::asset::balance(pool_vault(), xor) < min_xor_out()",
            source,
        )
        self.assertIn("share * 4 == amount_out", source)
        self.assertEqual(source.count("ledger::asset::transfer_batch("), 1)
        for forbidden in (
            "kaizen",
            "set_owner",
            "set_admin",
            "set_router",
            "set_recipient",
            "manual_tick",
            "sponsor",
        ):
            self.assertNotIn(f"kotoage fn {forbidden}", source)

        workflow = PAYOUT_WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("chain_discriminant=369", workflow)
        self.assertEqual(workflow.count('--chain-discriminant "$chain_discriminant"'), 3)

    def test_schema_and_fixed_policy_values_fail_closed(self):
        invalid_cases = []
        boolean_schema = self.fixture()
        boolean_schema["schema_version"] = True
        invalid_cases.append(boolean_schema)
        unknown = self.fixture()
        unknown["legacy_compatibility"] = True
        invalid_cases.append(unknown)
        wrong_sbd = self.fixture()
        wrong_sbd["sbd_asset_definition_id"] = "wrong"
        invalid_cases.append(wrong_sbd)
        wrong_batch = self.fixture()
        wrong_batch["batch_sbd"] = "9"
        invalid_cases.append(wrong_batch)
        wrong_network = self.fixture()
        wrong_network["pool_contract_address"] = (
            "sorac1qyqqqqqqqqqqqqpze5aq5vfxha4qlvu4q80e0ff4yesw50cuwzvx4"
        )
        invalid_cases.append(wrong_network)
        wrong_account_network = self.fixture()
        wrong_account_network["pool_vault_account_id"] = (
            "sorauﾛ1PﾉｳﾇmEｴWｵebHﾑ6ﾔﾙｲヰiwuCWErJ7uｽoPGｱﾔnjﾑKﾋTCW2PV"
        )
        invalid_cases.append(wrong_account_network)
        bad_checksum = self.fixture()
        bad_checksum["pool_contract_address"] = (
            bad_checksum["pool_contract_address"][:-1]
            + ("q" if bad_checksum["pool_contract_address"][-1] != "q" else "p")
        )
        invalid_cases.append(bad_checksum)
        duplicate = self.fixture()
        duplicate["recipient_account_ids"][3] = duplicate["recipient_account_ids"][0]
        invalid_cases.append(duplicate)
        recipient_is_vault = self.fixture()
        recipient_is_vault["recipient_account_ids"][0] = recipient_is_vault[
            "payout_vault_account_id"
        ]
        invalid_cases.append(recipient_is_vault)

        for case in invalid_cases:
            with self.subTest(case=case):
                with self.assertRaises(RENDERER.ConfigError):
                    RENDERER.validate_config(case)

    def test_duplicate_binding_fields_are_rejected(self):
        source = FIXTURE.read_text(encoding="utf-8")
        duplicate = source.replace(
            '"schema_version": 1,',
            '"schema_version": 1,\n  "schema_version": 1,',
            1,
        )
        with self.assertRaises(RENDERER.ConfigError):
            RENDERER.parse_config_text(duplicate)

    def test_taira_pending_binding_pins_genesis_recipients_and_fails_closed(self):
        pending = json.loads(TAIRA_PENDING.read_text(encoding="utf-8"))
        provenance = json.loads(TAIRA_PROVENANCE.read_text(encoding="utf-8"))
        self.assertEqual(provenance["network"], "taira")
        self.assertEqual(provenance["status"], "awaiting_live_deploy")
        self.assertEqual(provenance["genesis"]["sha256"], TAIRA_GENESIS_SHA256)
        self.assertEqual(
            provenance["genesis"]["chain_id"],
            "fc56984b-2be7-431d-840e-21514d1883f0",
        )
        self.assertEqual(provenance["genesis"]["chain_discriminant"], 369)
        self.assertEqual(provenance["genesis"]["consensus_mode"], "Npos")
        self.assertEqual(
            provenance["genesis"]["consensus_fingerprint"],
            "0x21591690e3c4d51fb3b81425aa8b9986eb417cc6a211dcfb8bce51c7600a6a7e",
        )
        self.assertEqual(
            provenance["genesis"]["validator_account_metadata_purpose"],
            "taira_validator_payout_recipient",
        )
        self.assertEqual(provenance["genesis"]["tagged_account_count"], 4)
        self.assertEqual(
            provenance["unresolved_live_fields"],
            [
                "pool_contract_address",
                "pool_vault_account_id",
                "payout_vault_account_id",
            ],
        )
        self.assertEqual(
            provenance["immutable_topology"]["mutating_entrypoints"],
            ["autonomous_validation_fee_tick"],
        )
        self.assertEqual(
            provenance["immutable_topology"]["entrypoint_permission"],
            "CanInvokeContractEntrypoint",
        )
        self.assertEqual(
            provenance["immutable_topology"]["nested_call"]["entrypoint_permission"],
            "CanInvokeContractEntrypoint",
        )
        self.assertEqual(
            provenance["immutable_topology"]["permission_topology"],
            {
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
        )
        self.assertEqual(
            provenance["immutable_topology"]["trigger"],
            {
                "id": "validation_fee_autonomous_payout",
                "filter": "time.pre_commit",
                "repetitions": "indefinite",
                "authority_binding": "payout_vault_account_id",
            },
        )
        self.assertFalse(provenance["immutable_topology"]["mutable_configuration"])
        self.assertFalse(provenance["immutable_topology"]["owner_or_admin"])
        self.assertFalse(provenance["immutable_topology"]["manual_entrypoint"])
        self.assertFalse(provenance["immutable_topology"]["generic_sponsorship"])
        self.assertEqual(len(pending["recipient_account_ids"]), 4)
        self.assertEqual(len(set(pending["recipient_account_ids"])), 4)
        self.assertTrue(
            all(account.startswith("test") for account in pending["recipient_account_ids"])
        )
        for field in provenance["unresolved_live_fields"]:
            self.assertIn("LIVE_TAIRA_", pending[field])
            self.assertIn("_REQUIRED", pending[field])
        with self.assertRaises(RENDERER.ConfigError):
            RENDERER.validate_config(pending)

        resolved = {**pending}
        fixture = self.fixture()
        for field in provenance["unresolved_live_fields"]:
            resolved[field] = fixture[field]
        validated = RENDERER.validate_config(resolved)
        self.assertEqual(
            validated["recipient_account_ids"],
            pending["recipient_account_ids"],
        )

    def test_taira_genesis_verifier_checks_hash_tag_and_recipient_order(self):
        binding = json.loads(TAIRA_PENDING.read_text(encoding="utf-8"))
        provenance = json.loads(TAIRA_PROVENANCE.read_text(encoding="utf-8"))
        genesis = {
            "chain": provenance["genesis"]["chain_id"],
            "chain_discriminant": provenance["genesis"]["chain_discriminant"],
            "consensus_mode": provenance["genesis"]["consensus_mode"],
            "consensus_fingerprint": provenance["genesis"]["consensus_fingerprint"],
            "transactions": [
                {
                    "instructions": [
                        {
                            "Register": {
                                "Account": {
                                    "id": account,
                                    "metadata": {
                                        "purpose": "taira_validator_payout_recipient"
                                    },
                                }
                            }
                        }
                        for account in binding["recipient_account_ids"]
                    ]
                }
            ],
        }
        genesis_bytes = (
            json.dumps(
                genesis,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            )
            + "\n"
        ).encode("utf-8")
        provenance["genesis"]["sha256"] = hashlib.sha256(genesis_bytes).hexdigest()

        with tempfile.TemporaryDirectory() as directory:
            directory_path = Path(directory)
            genesis_path = directory_path / "genesis.json"
            provenance_path = directory_path / "provenance.json"
            genesis_path.write_bytes(genesis_bytes)
            provenance_path.write_text(
                json.dumps(provenance, ensure_ascii=False, sort_keys=True),
                encoding="utf-8",
            )
            verified = subprocess.run(
                [
                    sys.executable,
                    str(VERIFY_TAIRA_SCRIPT),
                    str(genesis_path),
                    "--binding",
                    str(TAIRA_PENDING),
                    "--provenance",
                    str(provenance_path),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                json.loads(verified.stdout)["status"],
                "verified_pending_live_deploy",
            )

            genesis_path.write_bytes(genesis_bytes + b" ")
            rejected = subprocess.run(
                [
                    sys.executable,
                    str(VERIFY_TAIRA_SCRIPT),
                    str(genesis_path),
                    "--binding",
                    str(TAIRA_PENDING),
                    "--provenance",
                    str(provenance_path),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(rejected.returncode, 2)
            self.assertIn("genesis SHA-256 mismatch", rejected.stderr)

    def test_cli_output_is_reproducible_and_checkable(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "autonomous_payout.ko"
            first = subprocess.run(
                [sys.executable, str(SCRIPT), str(FIXTURE), "--output", str(output)],
                check=True,
                capture_output=True,
                text=True,
            )
            first_report = json.loads(first.stdout)
            source_before = output.read_bytes()
            metadata_before = output.with_suffix(".render.json").read_bytes()

            checked = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    str(FIXTURE),
                    "--output",
                    str(output),
                    "--check",
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            checked_report = json.loads(checked.stdout)
            self.assertTrue(checked_report["checked"])
            self.assertEqual(first_report["source_sha256"], checked_report["source_sha256"])
            self.assertEqual(source_before, output.read_bytes())
            self.assertEqual(metadata_before, output.with_suffix(".render.json").read_bytes())


if __name__ == "__main__":
    unittest.main()
