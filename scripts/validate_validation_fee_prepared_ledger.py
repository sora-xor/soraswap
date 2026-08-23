#!/usr/bin/env python3
"""Validate one frozen ledger package's filesystem and manifest structure.

The runner must additionally invoke the pinned native adapter's offline
verification mode against the same open payload descriptor before submission.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import stat
import sys
from pathlib import Path
from typing import Any


CHAIN_ID = "fc56984b-2be7-431d-840e-21514d1883f0"
CHAIN_DISCRIMINANT = 369
AUTHORITY_ACCOUNT_ID = (
    "testuﾛ1PｵEmｷjMZZﾑﾙeｱﾁﾎﾅﾂﾊmECepdbﾎｳ2uWﾃｸﾊﾘvｵi2ｦP1Y18A"
)
MANIFEST_SCHEMA = "soraswap.validation-fee-ledger-prepared.v1"
IROHA_COMMIT = "3d7a3bc788a791a426f914f15b2ba1f04b86ea0d"
IROHA_SOURCE_FINGERPRINT_SHA256 = (
    "de2b317a75803a33358e9a04fc3f82c9c285aa362e063a51a842e9ee6cdd8c5c"
)
IROHA_TRACKED_DIFF_SHA256 = (
    "9f8326bfa913039e2bdc0b9e96a37cab8010aaca9d5a27292d15d7258667f870"
)
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
TX_HASH_RE = re.compile(
    r"^(?:hash:[0-9A-F]{64}#[0-9A-F]{4}|(?:0x)?[0-9A-Fa-f]{64})$"
)
MAX_JSON_BYTES = 2 * 1024 * 1024
MAX_PAYLOAD_BYTES = 16 * 1024 * 1024


class Refusal(RuntimeError):
    """Fail-closed prepared-package refusal."""


def exact_object(label: str, value: Any, keys: set[str]) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise Refusal(f"{label} must contain exactly {sorted(keys)}")
    return value


def strict_json(raw: bytes, label: str) -> Any:
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise Refusal(f"{label} must be UTF-8 JSON") from error

    def no_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        value: dict[str, Any] = {}
        for key, item in pairs:
            if key in value:
                raise Refusal(f"{label} contains duplicate object key {key!r}")
            value[key] = item
        return value

    def reject_nonfinite(value: str) -> Any:
        raise Refusal(f"{label} contains non-finite number {value}")

    try:
        return json.loads(
            text,
            object_pairs_hook=no_duplicates,
            parse_constant=reject_nonfinite,
        )
    except json.JSONDecodeError as error:
        raise Refusal(f"{label} is not valid JSON") from error


def read_stable(path: Path, label: str, max_bytes: int, mode: int) -> bytes:
    before = path.stat(follow_symlinks=False)
    if not stat.S_ISREG(before.st_mode) or stat.S_IMODE(before.st_mode) != mode:
        raise Refusal(f"{label} must be a mode-{mode:04o} regular file")
    if before.st_size <= 0 or before.st_size > max_bytes:
        raise Refusal(f"{label} size is outside its reviewed bound")
    raw = path.read_bytes()
    after = path.stat(follow_symlinks=False)
    stable_fields = (
        "st_dev",
        "st_ino",
        "st_mode",
        "st_size",
        "st_mtime_ns",
        "st_ctime_ns",
    )
    if len(raw) != before.st_size or any(
        getattr(before, field) != getattr(after, field) for field in stable_fields
    ):
        raise Refusal(f"{label} changed while it was read")
    return raw


def load_json(path: Path, label: str, mode: int = 0o444) -> Any:
    return strict_json(read_stable(path, label, MAX_JSON_BYTES, mode), label)


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        allow_nan=False,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def normalized_hash(value: Any) -> str:
    transaction = exact_object(
        "prepared transaction",
        value,
        {"tx_hash", "tx_hash_hex"},
    )
    literal = transaction["tx_hash"]
    normalized = transaction["tx_hash_hex"]
    if (
        not isinstance(literal, str)
        or not TX_HASH_RE.fullmatch(literal)
        or not isinstance(normalized, str)
        or not SHA256_RE.fullmatch(normalized)
    ):
        raise Refusal("prepared transaction hash is not canonical")
    expected = (
        literal[5:69].lower()
        if literal.startswith("hash:")
        else literal.removeprefix("0x").lower()
    )
    if normalized != expected:
        raise Refusal("prepared transaction hash literal and digest differ")
    return normalized


def validate(
    prepared_dir: Path,
    operation_path: Path,
    expected_plan_sha256: str,
    expected_adapter_sha256: str,
    expected_adapter_source_sha256: str,
) -> dict[str, Any]:
    for label, value in (
        ("reviewed plan", expected_plan_sha256),
        ("adapter binary", expected_adapter_sha256),
        ("adapter source", expected_adapter_source_sha256),
    ):
        if not SHA256_RE.fullmatch(value) or value == "0" * 64:
            raise Refusal(f"expected {label} digest is unresolved or invalid")
    if (
        not prepared_dir.is_absolute()
        or prepared_dir.resolve(strict=True) != prepared_dir
        or not prepared_dir.is_dir()
        or stat.S_IMODE(prepared_dir.stat(follow_symlinks=False).st_mode) != 0o555
    ):
        raise Refusal("prepared directory must be canonical, symlink-free, and mode 0555")
    if {entry.name for entry in prepared_dir.iterdir()} != {
        "plan.json",
        "transaction.norito",
    }:
        raise Refusal("prepared directory must contain exactly plan.json and transaction.norito")

    wrapper = exact_object(
        "prepared wrapper",
        load_json(prepared_dir / "plan.json", "prepared wrapper"),
        {
            "schema_version",
            "phase",
            "plan_sha256",
            "adapter_binary_sha256",
            "manifest",
        },
    )
    operation = load_json(operation_path, "semantic ledger operation", mode=0o600)
    manifest = exact_object(
        "adapter manifest",
        wrapper["manifest"],
        {
            "schema",
            "plan_sha256",
            "operation_sha256",
            "operation",
            "chain_id",
            "chain_discriminant",
            "authority_account_id",
            "iroha_source",
            "adapter_source_sha256",
            "payload",
            "transaction",
        },
    )
    if (
        wrapper["schema_version"] != 1
        or wrapper["phase"] != "prepared_validation_fee_ledger_transaction"
        or wrapper["plan_sha256"] != expected_plan_sha256
        or wrapper["adapter_binary_sha256"] != expected_adapter_sha256
        or manifest["schema"] != MANIFEST_SCHEMA
        or manifest["plan_sha256"] != expected_plan_sha256
        or manifest["chain_id"] != CHAIN_ID
        or manifest["chain_discriminant"] != CHAIN_DISCRIMINANT
        or manifest["authority_account_id"] != AUTHORITY_ACCOUNT_ID
        or manifest["operation"] != operation
    ):
        raise Refusal("prepared wrapper or manifest changed its exact reviewed binding")
    operation_digest = hashlib.sha256(canonical_bytes(operation)).hexdigest()
    if manifest["operation_sha256"] != operation_digest:
        raise Refusal("prepared manifest semantic-operation digest differs")
    source = exact_object(
        "adapter Iroha source",
        manifest["iroha_source"],
        {"commit", "source_fingerprint_sha256", "tracked_diff_sha256"},
    )
    if source != {
        "commit": IROHA_COMMIT,
        "source_fingerprint_sha256": IROHA_SOURCE_FINGERPRINT_SHA256,
        "tracked_diff_sha256": IROHA_TRACKED_DIFF_SHA256,
    }:
        raise Refusal("adapter manifest differs from the exact reviewed Iroha closure")
    if manifest["adapter_source_sha256"] != expected_adapter_source_sha256:
        raise Refusal("adapter source digest differs from the exact reviewed build")

    payload = exact_object(
        "prepared payload",
        manifest["payload"],
        {"file", "size_bytes", "sha256"},
    )
    if payload["file"] != "transaction.norito":
        raise Refusal("prepared payload file name differs")
    if (
        isinstance(payload["size_bytes"], bool)
        or not isinstance(payload["size_bytes"], int)
        or payload["size_bytes"] <= 0
        or payload["size_bytes"] > MAX_PAYLOAD_BYTES
        or not isinstance(payload["sha256"], str)
        or not SHA256_RE.fullmatch(payload["sha256"])
    ):
        raise Refusal("prepared payload metadata is invalid")
    payload_bytes = read_stable(
        prepared_dir / "transaction.norito",
        "prepared Norito payload",
        MAX_PAYLOAD_BYTES,
        0o444,
    )
    if (
        len(payload_bytes) != payload["size_bytes"]
        or hashlib.sha256(payload_bytes).hexdigest() != payload["sha256"]
    ):
        raise Refusal("prepared Norito payload differs from its frozen manifest")
    normalized_hash(manifest["transaction"])
    return wrapper


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prepared-dir", type=Path, required=True)
    parser.add_argument("--operation", type=Path, required=True)
    parser.add_argument("--expected-plan-sha256", required=True)
    parser.add_argument("--expected-adapter-sha256", required=True)
    parser.add_argument("--expected-adapter-source-sha256", required=True)
    args = parser.parse_args()
    try:
        wrapper = validate(
            args.prepared_dir,
            args.operation,
            args.expected_plan_sha256,
            args.expected_adapter_sha256,
            args.expected_adapter_source_sha256,
        )
        sys.stdout.write(
            json.dumps(
                wrapper,
                allow_nan=False,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            )
            + "\n"
        )
        return 0
    except (OSError, Refusal) as error:
        print(f"validation-fee prepared ledger refused: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
