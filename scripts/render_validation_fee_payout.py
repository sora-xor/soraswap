#!/usr/bin/env python3
"""Render the immutable CBSI validation-fee payout Kotodama wrapper."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
import unicodedata
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "validation_fee" / "autonomous_payout.ko.template"
DEFAULT_OUTPUT = ROOT / "artifacts" / "rendered" / "validation_fee" / "autonomous_payout.ko"

SBD_ASSET_ID = "7ZepsJTHCVLKsrFFNZGSRGZgvBhv"
XOR_ASSET_ID = "6TEAJqbb8oEPmLncoNiMRbLEK6tw"
EXPECTED_FIELDS = {
    "schema_version",
    "pool_contract_address",
    "pool_vault_account_id",
    "payout_vault_account_id",
    "sbd_asset_definition_id",
    "xor_asset_definition_id",
    "batch_sbd",
    "min_xor_out",
    "max_xor_out",
    "recipient_account_ids",
}
MARKER = re.compile(r"@@[A-Z0-9_]+@@")
BECH32M_CONSTANT = 0x2BC830A3
BECH32_CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
BECH32_GENERATORS = (0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3)
TAIRA_ACCOUNT_PREFIX = "test"


class ConfigError(ValueError):
    """Raised when public binding input is not the exact supported schema."""


def _reject_duplicate_object_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ConfigError(f"duplicate configuration field: {key}")
        result[key] = value
    return result


def parse_config_text(source: str) -> Any:
    return json.loads(source, object_pairs_hook=_reject_duplicate_object_pairs)


def _canonical_json_bytes(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        .encode("utf-8")
    )


def _sha256_hex(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _require_exact_string(config: dict[str, Any], field: str, expected: str) -> None:
    actual = config.get(field)
    if actual != expected:
        raise ConfigError(f"{field} must be exactly {expected!r}")


def _bech32_polymod(values: list[int]) -> int:
    checksum = 1
    for value in values:
        top = checksum >> 25
        checksum = ((checksum & 0x1FFFFFF) << 5) ^ value
        for index, generator in enumerate(BECH32_GENERATORS):
            if (top >> index) & 1:
                checksum ^= generator
    return checksum


def _decode_bech32_payload(values: list[int], field: str) -> bytes:
    output = bytearray()
    accumulator = 0
    bits = 0
    for value in values:
        accumulator = (accumulator << 5) | value
        bits += 5
        while bits >= 8:
            bits -= 8
            output.append((accumulator >> bits) & 0xFF)
        accumulator &= 0 if bits == 0 else (1 << bits) - 1
    if bits >= 5 or (bits > 0 and accumulator != 0):
        raise ConfigError(f"{field} has noncanonical Bech32 padding")
    return bytes(output)


def _validate_taira_contract_address(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value or len(value) > 90:
        raise ConfigError(f"{field} must be a canonical Taira contract address")
    if value != value.lower():
        raise ConfigError(f"{field} must use canonical lowercase Bech32m")
    separator = value.rfind("1")
    if separator <= 0 or separator > 83 or separator + 7 > len(value):
        raise ConfigError(f"{field} is not a canonical contract address")
    human_readable_prefix = value[:separator]
    if human_readable_prefix != "tairac":
        raise ConfigError(f"{field} must belong to the Taira chain")
    if not all(33 <= ord(char) <= 126 for char in human_readable_prefix):
        raise ConfigError(f"{field} has an invalid Bech32 human-readable prefix")
    try:
        values = [BECH32_CHARSET.index(char) for char in value[separator + 1 :]]
    except ValueError as error:
        raise ConfigError(f"{field} contains a non-Bech32 character") from error
    expanded_prefix = [
        *(ord(char) >> 5 for char in human_readable_prefix),
        0,
        *(ord(char) & 0x1F for char in human_readable_prefix),
    ]
    if _bech32_polymod([*expanded_prefix, *values]) != BECH32M_CONSTANT:
        raise ConfigError(f"{field} has an invalid Bech32m checksum")
    payload = _decode_bech32_payload(values[:-6], field)
    if len(payload) != 29 or payload[0] != 1:
        raise ConfigError(f"{field} has an unsupported contract-address payload")
    return value


def _validate_account_id(value: Any, field: str) -> str:
    if not isinstance(value, str):
        raise ConfigError(f"{field} must be a string")
    if value != unicodedata.normalize("NFC", value):
        raise ConfigError(f"{field} must use canonical NFC text")
    if not 20 <= len(value) <= 256 or not value.startswith(TAIRA_ACCOUNT_PREFIX):
        raise ConfigError(f"{field} must be a canonical Taira account literal")
    if any(ord(char) < 0x20 or char.isspace() for char in value):
        raise ConfigError(f"{field} must not contain control characters or whitespace")
    if any(char in value for char in ('"', "\\", "@")):
        raise ConfigError(f"{field} contains a source-unsafe character")
    return value


def validate_config(raw: Any) -> dict[str, Any]:
    if not isinstance(raw, dict):
        raise ConfigError("configuration must be a JSON object")
    unknown = set(raw) - EXPECTED_FIELDS
    missing = EXPECTED_FIELDS - set(raw)
    if unknown:
        raise ConfigError(f"unknown configuration fields: {', '.join(sorted(unknown))}")
    if missing:
        raise ConfigError(f"missing configuration fields: {', '.join(sorted(missing))}")
    if type(raw["schema_version"]) is not int or raw["schema_version"] != 1:
        raise ConfigError("schema_version must be exactly 1")

    contract = _validate_taira_contract_address(
        raw["pool_contract_address"], "pool_contract_address"
    )

    _require_exact_string(raw, "sbd_asset_definition_id", SBD_ASSET_ID)
    _require_exact_string(raw, "xor_asset_definition_id", XOR_ASSET_ID)
    _require_exact_string(raw, "batch_sbd", "10")
    _require_exact_string(raw, "min_xor_out", "4")
    _require_exact_string(raw, "max_xor_out", "100")

    pool_vault = _validate_account_id(raw["pool_vault_account_id"], "pool_vault_account_id")
    payout_vault = _validate_account_id(
        raw["payout_vault_account_id"], "payout_vault_account_id"
    )
    if pool_vault == payout_vault:
        raise ConfigError("pool and payout vault accounts must differ")

    recipients = raw["recipient_account_ids"]
    if not isinstance(recipients, list) or len(recipients) != 4:
        raise ConfigError("recipient_account_ids must contain exactly four accounts")
    checked_recipients = [
        _validate_account_id(value, f"recipient_account_ids[{index}]")
        for index, value in enumerate(recipients)
    ]
    if len(set(checked_recipients)) != 4:
        raise ConfigError("recipient accounts must be unique")
    if pool_vault in checked_recipients or payout_vault in checked_recipients:
        raise ConfigError("recipient accounts must differ from both vault accounts")

    return {
        **raw,
        "pool_contract_address": contract,
        "pool_vault_account_id": pool_vault,
        "payout_vault_account_id": payout_vault,
        "recipient_account_ids": checked_recipients,
    }


def render_source(config: dict[str, Any]) -> str:
    source = TEMPLATE.read_text(encoding="utf-8")
    replacements = {
        "@@POOL_CONTRACT_ADDRESS@@": config["pool_contract_address"],
        "@@POOL_VAULT_ACCOUNT_ID@@": config["pool_vault_account_id"],
        "@@PAYOUT_VAULT_ACCOUNT_ID@@": config["payout_vault_account_id"],
    }
    for index, account_id in enumerate(config["recipient_account_ids"], start=1):
        replacements[f"@@RECIPIENT_ACCOUNT_ID_{index}@@"] = account_id
    for marker, value in replacements.items():
        source = source.replace(marker, value)
    leftovers = sorted(set(MARKER.findall(source)))
    if leftovers:
        raise ConfigError(f"unresolved source markers: {', '.join(leftovers)}")
    if source.count("kotoage fn ") != 1:
        raise ConfigError("rendered payout must expose exactly one mutating entrypoint")
    return source


def _atomic_write(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def _metadata(config: dict[str, Any], source: str) -> dict[str, Any]:
    source_bytes = source.encode("utf-8")
    return {
        "schema_version": 1,
        "contract": "validation_fee.autonomous_payout",
        "source_sha256": _sha256_hex(source_bytes),
        "binding_sha256": _sha256_hex(_canonical_json_bytes(config)),
        "binding": config,
    }


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Render the source-pinned, trigger-only CBSI validation-fee payout contract"
        )
    )
    parser.add_argument("config", type=Path, help="reviewed public binding JSON")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--metadata-output",
        type=Path,
        help="render metadata output (defaults beside the generated source)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify existing outputs byte-for-byte without rewriting them",
    )
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    try:
        raw = parse_config_text(args.config.read_text(encoding="utf-8"))
        config = validate_config(raw)
        source = render_source(config)
        metadata = _metadata(config, source)
        source_bytes = source.encode("utf-8")
        metadata_bytes = (
            json.dumps(metadata, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
        ).encode("utf-8")
        metadata_output = args.metadata_output or args.output.with_suffix(".render.json")

        if args.check:
            if args.output.read_bytes() != source_bytes:
                raise ConfigError(f"rendered source differs: {args.output}")
            if metadata_output.read_bytes() != metadata_bytes:
                raise ConfigError(f"render metadata differs: {metadata_output}")
        else:
            _atomic_write(args.output, source_bytes)
            _atomic_write(metadata_output, metadata_bytes)

        print(
            json.dumps(
                {
                    "source": str(args.output),
                    "metadata": str(metadata_output),
                    "source_sha256": metadata["source_sha256"],
                    "binding_sha256": metadata["binding_sha256"],
                    "checked": args.check,
                },
                sort_keys=True,
            )
        )
        return 0
    except (ConfigError, FileNotFoundError, json.JSONDecodeError) as error:
        print(f"render validation-fee payout: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
