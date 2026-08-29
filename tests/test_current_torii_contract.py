from __future__ import annotations

import contextlib
import io
import sys
import unittest
from types import SimpleNamespace
from unittest import mock

from scripts import current_torii_contract as transport


AUTHORITY = "test-authority"


class CurrentToriiContractTests(unittest.TestCase):
    def test_call_rejects_retired_private_key_body_field(self) -> None:
        request = {
            "authority": AUTHORITY,
            "contract_address": "contract",
            "entrypoint": "main",
            "fee_payment": {
                "payer": "authority",
                "value": {"charge_limits": [], "gas_limit": 5000},
            },
            "private_key": "retired",
        }
        with self.assertRaisesRegex(
            transport.ContractTransportError, "unsupported field.*private_key"
        ):
            transport._validate_request("call", request, AUTHORITY)

    def test_batch_view_requires_closed_current_item_shape(self) -> None:
        request = {
            "authority": AUTHORITY,
            "items": [
                {
                    "contract_address": "contract",
                    "entrypoint": "main",
                    "legacy_name": "retired",
                }
            ],
        }
        self.assertEqual(
            transport._validate_request("view-batch", request, AUTHORITY),
            "/v1/contracts/view/batch",
        )
        with self.assertRaisesRegex(
            transport.ContractTransportError, "unsupported field.*legacy_name"
        ):
            transport._validate_shape("view-batch", request)

    def test_call_emits_only_the_submitted_torii_response(self) -> None:
        request = {
            "authority": AUTHORITY,
            "contract_address": "contract",
            "entrypoint": "main",
            "fee_payment": {
                "payer": "authority",
                "value": {"charge_limits": [], "gas_limit": 5000},
            },
        }
        signer = SimpleNamespace(
            can_call=True,
            authority=AUTHORITY,
            basic_auth=None,
            torii_url="http://127.0.0.1:8080",
        )
        submitted = {"ok": True, "submitted": True, "tx_hash_hex": "ab" * 32}
        output = io.StringIO()
        argv = [
            "current_torii_contract.py",
            "--config",
            "/tmp/client.toml",
            "--environment",
            "local",
            "--authority",
            AUTHORITY,
            "--torii-url",
            "http://127.0.0.1:8080",
            "call",
        ]
        with mock.patch.object(sys, "argv", argv), mock.patch.object(
            transport, "_read_request", return_value=request
        ), mock.patch.object(
            transport, "load_signer_binding", return_value=signer
        ), mock.patch.object(
            transport,
            "execute_detached_contract_call",
            return_value={"ok": True, "response_json": submitted},
        ) as execute, contextlib.redirect_stdout(output):
            self.assertEqual(transport.main(), 0)

        self.assertEqual(output.getvalue(), f'{transport.json.dumps(submitted, separators=(",", ":"))}\n')
        self.assertEqual(execute.call_args.kwargs["request_payload"], request)

    def test_batch_view_rejects_http_success_with_failed_item(self) -> None:
        request = {
            "authority": AUTHORITY,
            "items": [{"contract_address": "contract", "entrypoint": "main"}],
        }
        response = {
            "ok": False,
            "items": [
                {
                    "ok": False,
                    "dataspace": "0",
                    "contract_address": "contract",
                    "code_hash_hex": "ab" * 32,
                    "abi_hash_hex": "cd" * 32,
                    "entrypoint": "main",
                    "error": "trap",
                }
            ],
        }
        with self.assertRaisesRegex(
            transport.ContractTransportError, "did not complete successfully"
        ):
            transport._validate_batch_view_response(response, request)

    def test_call_shape_requires_the_current_unquoted_fee_intent(self) -> None:
        request = {
            "authority": AUTHORITY,
            "contract_address": "contract",
            "entrypoint": "main",
            "fee_payment": {
                "payer": "authority",
                "value": {
                    "charge_limits": [
                        {
                            "kind": "nexus",
                            "asset_definition_id": "xor#universal",
                            "max_amount": "1",
                        }
                    ],
                    "gas_limit": 5000,
                },
            },
        }
        with self.assertRaisesRegex(
            transport.ContractTransportError, "leave charge_limits empty"
        ):
            transport._validate_shape("call", request)


if __name__ == "__main__":
    unittest.main()
