from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts import normalize_contract_view_response as normalizer


CODE_HASH = "a" * 64
ABI_HASH = "b" * 64
CONTRACT_ADDRESS = "tairac1fixture"
ENTRYPOINT = "mirror_fixture"


class ContractViewResponseNormalizationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.repo_root = Path(self.temp_dir.name)
        self.manifest_dir = self.repo_root / "artifacts" / "compiled" / "fixture"
        self.manifest_dir.mkdir(parents=True)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def write_manifest(self, leaf_kinds: list[str]) -> None:
        if len(leaf_kinds) == 1:
            nodes = [
                {"kind": "Leaf", "value": {"kind": leaf_kinds[0], "value": None}}
            ]
        else:
            nodes = [{"kind": "Tuple", "value": len(leaf_kinds)}]
            nodes.extend(
                {"kind": "Leaf", "value": {"kind": kind, "value": None}}
                for kind in leaf_kinds
            )
        manifest = {
            "code_hash": f"hash:{CODE_HASH.upper()}#0000",
            "abi_hash": f"hash:{ABI_HASH.upper()}#0000",
            "entrypoints": [
                {
                    "name": ENTRYPOINT,
                    "kind": {"kind": "View", "value": None},
                    "return_type": "fixture",
                    "return_schema": {"nodes": nodes},
                }
            ],
        }
        (self.manifest_dir / "fixture.manifest.json").write_text(
            json.dumps(manifest), encoding="utf-8"
        )

    def response(self, result: object) -> dict[str, object]:
        return {
            "ok": True,
            "dataspace": "universal",
            "contract_address": CONTRACT_ADDRESS,
            "code_hash_hex": CODE_HASH,
            "abi_hash_hex": ABI_HASH,
            "entrypoint": ENTRYPOINT,
            "result": result,
        }

    def normalize(self, result: object) -> dict[str, object]:
        return normalizer.normalize_response(
            self.repo_root,
            self.response(result),
            CONTRACT_ADDRESS,
            ENTRYPOINT,
        )

    def test_numeric_strings_are_schema_validated_and_normalized(self) -> None:
        self.write_manifest(["Int", "Decimal", "Quantity", "Name"])
        normalized = self.normalize(["-2", "1.25", "3.5", "007"])

        self.assertEqual(normalized["result"], ["-2", "1.25", "3.5", "007"])
        self.assertEqual(normalized["normalized_result"], [-2, 1.25, 3.5, "007"])

    def test_numeric_json_tokens_are_not_accepted_as_current_results(self) -> None:
        self.write_manifest(["Int"])
        with self.assertRaisesRegex(
            normalizer.ContractViewNormalizationError,
            "must be a canonical JSON string",
        ):
            self.normalize(7)

    def test_protocol_numeric_leaf_remains_native(self) -> None:
        self.write_manifest(["DataSpaceId"])
        normalized = self.normalize(7)
        self.assertEqual(normalized["result"], 7)
        self.assertEqual(normalized["normalized_result"], 7)

    def test_noncanonical_numeric_strings_fail_closed(self) -> None:
        for kind, value in [
            ("Int", "01"),
            ("Int", "-0"),
            ("Decimal", "1.0"),
            ("Decimal", "+1"),
            ("Quantity", "-1"),
            ("Quantity", "0.0"),
        ]:
            with self.subTest(kind=kind, value=value):
                self.write_manifest([kind])
                with self.assertRaises(normalizer.ContractViewNormalizationError):
                    self.normalize(value)

    def test_result_must_match_exact_tuple_arity(self) -> None:
        self.write_manifest(["Int", "Quantity"])
        with self.assertRaisesRegex(
            normalizer.ContractViewNormalizationError, "2-element array"
        ):
            self.normalize(["1"])

    def test_response_must_bind_to_one_current_manifest(self) -> None:
        self.write_manifest(["Int"])
        response = self.response("1")
        response["abi_hash_hex"] = "c" * 64
        with self.assertRaisesRegex(
            normalizer.ContractViewNormalizationError,
            "match exactly one current compiled manifest",
        ):
            normalizer.normalize_response(
                self.repo_root, response, CONTRACT_ADDRESS, ENTRYPOINT
            )


if __name__ == "__main__":
    unittest.main()
