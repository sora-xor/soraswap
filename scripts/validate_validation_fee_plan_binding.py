#!/usr/bin/env python3
"""Validate the immutable Taira P1 deployment-plan evidence and print its digest."""

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
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
MAX_EVIDENCE_BYTES = 2 * 1024 * 1024
PLAN_KEYS = {
    "schema_version",
    "status",
    "network",
    "chain_id",
    "chain_discriminant",
    "genesis_sha256",
    "authority_account_id",
    "dataspace",
    "deployment_spec_sha256",
    "required_starting_deploy_nonce",
    "required_final_deploy_nonce",
    "sequence",
    "contracts",
    "payout_binding",
    "protected_permissions",
    "preconditions",
    "prohibited_actions",
    "toolchain",
}


class Refusal(RuntimeError):
    """Fail-closed plan-evidence refusal."""


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


def read_immutable(path: Path) -> Any:
    if not path.is_absolute() or path.resolve(strict=True) != path:
        raise Refusal("plan evidence path must be absolute, canonical, and symlink-free")
    before = path.stat(follow_symlinks=False)
    if not stat.S_ISREG(before.st_mode) or stat.S_IMODE(before.st_mode) != 0o444:
        raise Refusal("plan evidence must be a mode-0444 regular file")
    if before.st_size <= 0 or before.st_size > MAX_EVIDENCE_BYTES:
        raise Refusal("plan evidence size is outside its reviewed bound")
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
        raise Refusal("plan evidence changed while it was read")
    return strict_json(raw, str(path))


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        allow_nan=False,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def validate(value: Any, expected: str) -> str:
    if not SHA256_RE.fullmatch(expected) or expected == "0" * 64:
        raise Refusal("expected reviewed plan digest must be a resolved lowercase SHA-256")
    evidence = exact_object(
        "plan evidence",
        value,
        {"schema_version", "phase", "plan_sha256", "payload"},
    )
    payload = exact_object(
        "plan evidence payload",
        evidence["payload"],
        {
            "result",
            "write_gate_command_sha256",
            "state_binding_sha256",
            "block_1_hash",
        },
    )
    result = exact_object(
        "plan evidence result",
        payload["result"],
        {"plan", "plan_sha256"},
    )
    plan = exact_object("reviewed plan", result["plan"], PLAN_KEYS)
    digest = hashlib.sha256(canonical_bytes(plan)).hexdigest()
    if (
        evidence["schema_version"] != 1
        or evidence["phase"] != "plan"
        or evidence["plan_sha256"] != expected
        or result["plan_sha256"] != expected
        or digest != expected
    ):
        raise Refusal("plan evidence does not bind the exact canonical reviewed plan")
    if (
        plan["schema_version"] != 1
        or plan["status"] != "undeployed_plan"
        or plan["network"] != "taira"
        or plan["chain_id"] != CHAIN_ID
        or plan["chain_discriminant"] != CHAIN_DISCRIMINANT
        or plan["authority_account_id"] != AUTHORITY_ACCOUNT_ID
        or plan["dataspace"] != "universal"
    ):
        raise Refusal("reviewed plan identity differs from fresh Taira P1")
    prohibited = exact_object(
        "reviewed plan prohibited_actions",
        plan["prohibited_actions"],
        {
            "protected_permission_grants",
            "role_grants",
            "parliament_activation",
            "validation_fee_lifecycle_activation",
        },
    )
    if any(value is not True for value in prohibited.values()):
        raise Refusal("reviewed plan does not retain every prohibited action")
    for label in (
        "genesis_sha256",
        "deployment_spec_sha256",
    ):
        if not isinstance(plan[label], str) or not SHA256_RE.fullmatch(plan[label]):
            raise Refusal(f"reviewed plan {label} must be lowercase SHA-256")
    for label in (
        "write_gate_command_sha256",
        "state_binding_sha256",
        "block_1_hash",
    ):
        value = payload[label]
        if not isinstance(value, str) or not SHA256_RE.fullmatch(value):
            raise Refusal(f"plan evidence {label} must be lowercase SHA-256")
    return digest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan-evidence", type=Path, required=True)
    parser.add_argument("--expected-plan-sha256", required=True)
    args = parser.parse_args()
    try:
        print(validate(read_immutable(args.plan_evidence), args.expected_plan_sha256))
        return 0
    except (OSError, Refusal) as error:
        print(f"validation-fee plan binding refused: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
