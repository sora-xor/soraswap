#!/usr/bin/env python3
"""Validate one fresh direct/public/MCP gate for a validation-fee write."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


CHAIN_ID = "fc56984b-2be7-431d-840e-21514d1883f0"
CHAIN_DISCRIMINANT = 369
AUTHORITY_ACCOUNT_ID = (
    "testuﾛ1PｵEmｷjMZZﾑﾙeｱﾁﾎﾅﾂﾊmECepdbﾎｳ2uWﾃｸﾊﾘvｵi2ｦP1Y18A"
)
REQUEST_SCHEMA = "soraswap.validation-fee-write-gate-request.v1"
MARKER_SCHEMA = "soraswap.validation-fee-write-gate.v1"
DIRECT_ENDPOINTS = tuple(
    (f"validator-{index + 1}", f"http://127.0.0.1:{39080 + index}")
    for index in range(4)
)
PUBLIC_ENDPOINT = ("public", "https://taira.sora.org")
MCP_ENDPOINT = "https://taira.sora.org/v1/mcp"
CHECKS = (
    "health",
    "status",
    "sumeragi.status",
    "blocks.get",
    "node.capabilities",
)
MCP_TOOLS = (
    "iroha.health",
    "iroha.status",
    "iroha.sumeragi.status",
    "iroha.blocks.get",
)
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
TX_HASH_RE = re.compile(
    r"^(?:hash:[0-9A-F]{64}#[0-9A-F]{4}|(?:0x)?[0-9A-Fa-f]{64})$"
)
ACCOUNT_RE = re.compile(r"^test[^\s#]+$")
CONTRACT_RE = re.compile(r"^tairac1[^\s]+$")
XOR_ASSET_ID = "6TEAJqbb8oEPmLncoNiMRbLEK6tw"
SBD_ASSET_ID = "7ZepsJTHCVLKsrFFNZGSRGZgvBhv"
POOL_CONTRACT_ADDRESS = (
    "tairac1qyqqqqqqqqqqqqymmv4lktrp3r7xyq3jmzk89sy7hyvzdwssatnvg"
)
POOL_SUBJECT_ACCOUNT_ID = (
    "testuﾛ1PcﾀkｼﾉpﾔﾖｸPUCヰrｻjSUzﾕhZGSAｳJﾐｹﾜrﾄﾗﾓｿxS8QRALXF"
)


class Refusal(RuntimeError):
    """Fail-closed marker refusal."""


def canonical_bytes(value: Any) -> bytes:
    return (
        json.dumps(
            value,
            allow_nan=False,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        + "\n"
    ).encode("utf-8")


def sha256(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def exact_object(label: str, value: Any, keys: set[str]) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise Refusal(f"{label} must contain exactly {sorted(keys)}")
    return value


def positive_int(label: str, value: Any) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise Refusal(f"{label} must be a positive integer")
    return value


def parse_time(label: str, value: Any) -> datetime:
    if not isinstance(value, str) or not value.endswith("Z"):
        raise Refusal(f"{label} must be RFC3339 UTC")
    try:
        parsed = datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as error:
        raise Refusal(f"{label} must be RFC3339 UTC") from error
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise Refusal(f"{label} must carry a UTC offset")
    return parsed.astimezone(timezone.utc)


def nonempty_string(label: str, value: Any) -> str:
    if not isinstance(value, str) or not value or value.isspace():
        raise Refusal(f"{label} must be a non-empty string")
    return value


def normalized_transaction_hash(value: Any) -> str:
    transaction = exact_object(
        "split deploy transaction",
        value,
        {"tx_hash", "tx_hash_hex"},
    )
    literal = nonempty_string(
        "split deploy transaction tx_hash",
        transaction["tx_hash"],
    )
    normalized = nonempty_string(
        "split deploy transaction tx_hash_hex",
        transaction["tx_hash_hex"],
    )
    if not TX_HASH_RE.fullmatch(literal) or not SHA256_RE.fullmatch(normalized):
        raise Refusal("split deploy transaction hash is not canonical")
    expected = (
        literal[5:69].lower()
        if literal.startswith("hash:")
        else literal.removeprefix("0x").lower()
    )
    if normalized != expected:
        raise Refusal("split deploy transaction hash forms differ")
    return normalized


def validate_plan_sha256(value: Any, expected_plan_sha256: str) -> str:
    if not isinstance(value, str) or not SHA256_RE.fullmatch(value):
        raise Refusal("operation plan_sha256 must be lowercase SHA-256")
    if value != expected_plan_sha256:
        raise Refusal("operation is not bound to the exact reviewed P1 plan")
    return value


def validate_prepared_payload_binding(value: dict[str, Any]) -> None:
    payload_sha256 = value["payload_sha256"]
    if not isinstance(payload_sha256, str) or not SHA256_RE.fullmatch(
        payload_sha256
    ):
        raise Refusal("prepared ledger payload digest must be lowercase SHA-256")
    payload_size = positive_int(
        "prepared ledger payload size",
        value["payload_size_bytes"],
    )
    if payload_size > 16 * 1024 * 1024:
        raise Refusal("prepared ledger payload exceeds the 16 MiB bound")
    normalized_transaction_hash(value["transaction"])


def validate_permission(value: Any) -> None:
    permission = exact_object(
        "validation-fee permission",
        value,
        {"name", "payload"},
    )
    name = permission["name"]
    if name == "CanInvokeContractEntrypoint":
        payload = exact_object(
            "contract-entrypoint permission payload",
            permission["payload"],
            {"contract", "entrypoint"},
        )
        contract = nonempty_string(
            "contract-entrypoint permission contract",
            payload["contract"],
        )
        if not CONTRACT_RE.fullmatch(contract):
            raise Refusal("contract-entrypoint permission contract is not Taira")
        if payload["entrypoint"] not in {"hajimari", "seed_bin", "renounce_admin"}:
            raise Refusal("contract-entrypoint permission selector is not bootstrap-scoped")
        return
    if name == "CanTransferAsset":
        payload = exact_object(
            "asset-transfer permission payload",
            permission["payload"],
            {"asset"},
        )
        asset = nonempty_string("asset-transfer permission asset", payload["asset"])
        if not any(
            re.fullmatch(
                re.escape(asset_id) + r"#test[^\s#]+#dataspace:0",
                asset,
            )
            for asset_id in (XOR_ASSET_ID, SBD_ASSET_ID)
        ):
            raise Refusal("asset-transfer permission is not exact XOR/SBD bootstrap scope")
        return
    raise Refusal("validation-fee permission kind is unsupported")


def validate_contract_call_arguments(entrypoint: Any, arguments: Any) -> None:
    if entrypoint == "hajimari":
        value = exact_object(
            "hajimari arguments",
            arguments,
            {
                "base_asset",
                "quote_asset",
                "vault_account",
                "fee_pips",
                "bin_step",
                "active_bin",
                "impact_cap_bps",
                "min_reserve_base",
                "min_reserve_quote",
                "max_bins_per_swap",
                "bin_liquidity_cap",
            },
        )
        expected = {
            "base_asset": XOR_ASSET_ID,
            "quote_asset": SBD_ASSET_ID,
            "fee_pips": 3000,
            "bin_step": 1,
            "active_bin": 0,
            "impact_cap_bps": 10000,
            "min_reserve_base": 0,
            "min_reserve_quote": 0,
            "max_bins_per_swap": 8,
            "bin_liquidity_cap": 0,
        }
        if any(
            isinstance(value[key], bool)
            or type(value[key]) is not type(expected_value)
            or value[key] != expected_value
            for key, expected_value in expected.items()
        ):
            raise Refusal("hajimari arguments differ from the exact XOR/SBD pool")
        if value["vault_account"] != POOL_SUBJECT_ACCOUNT_ID:
            raise Refusal(
                "hajimari vault account differs from the exact reviewed P1 pool subject"
            )
        return
    if entrypoint == "seed_bin":
        value = exact_object(
            "seed_bin arguments",
            arguments,
            {"position_id", "bin_id", "base_amount", "quote_amount"},
        )
        if (
            isinstance(value["bin_id"], bool)
            or not isinstance(value["bin_id"], int)
            or value["bin_id"] not in (0, 1, 2)
            or value["position_id"]
            != f"validation_fee_seed_bin_{value['bin_id']}"
            or isinstance(value["base_amount"], bool)
            or not isinstance(value["base_amount"], int)
            or value["base_amount"] != 1000
            or isinstance(value["quote_amount"], bool)
            or not isinstance(value["quote_amount"], int)
            or value["quote_amount"] != 1000
        ):
            raise Refusal("seed_bin arguments differ from the exact reviewed seed")
        return
    if entrypoint == "renounce_admin":
        exact_object("renounce_admin arguments", arguments, set())
        return
    raise Refusal("contract call entrypoint is outside the bootstrap plan")


def validate_operation(
    value: Any,
    expected_plan_sha256: str,
) -> dict[str, Any]:
    if (
        not SHA256_RE.fullmatch(expected_plan_sha256)
        or expected_plan_sha256 == "0" * 64
    ):
        raise Refusal("expected reviewed P1 plan SHA-256 is invalid")
    if not isinstance(value, dict):
        raise Refusal("gate request operation must be an object")
    kind = value.get("kind")
    if kind == "account_registration":
        operation = exact_object(
            "account registration operation",
            value,
            {
                "kind",
                "plan_sha256",
                "account_id",
                "purpose",
                "payload_sha256",
                "payload_size_bytes",
                "transaction",
            },
        )
        validate_plan_sha256(operation["plan_sha256"], expected_plan_sha256)
        if not isinstance(operation["account_id"], str) or not ACCOUNT_RE.fullmatch(
            operation["account_id"]
        ):
            raise Refusal("account registration target is not a Taira account")
        if operation["purpose"] not in {
            "pool_contract_subject",
            "payout_contract_subject",
        }:
            raise Refusal("account registration purpose is not validation-fee scoped")
        validate_prepared_payload_binding(operation)
        return operation
    if kind in {"permission_grant", "permission_revoke"}:
        operation = exact_object(
            "permission mutation operation",
            value,
            {
                "kind",
                "plan_sha256",
                "account_id",
                "permission",
                "payload_sha256",
                "payload_size_bytes",
                "transaction",
            },
        )
        validate_plan_sha256(operation["plan_sha256"], expected_plan_sha256)
        if not isinstance(operation["account_id"], str) or not ACCOUNT_RE.fullmatch(
            operation["account_id"]
        ):
            raise Refusal("permission mutation target is not a Taira account")
        validate_permission(operation["permission"])
        validate_prepared_payload_binding(operation)
        return operation
    if kind == "split_deploy_transaction":
        operation = exact_object(
            "split deploy operation",
            value,
            {
                "kind",
                "plan_sha256",
                "contract_key",
                "contract_alias",
                "label",
                "payload_sha256",
                "transaction",
            },
        )
        validate_plan_sha256(operation["plan_sha256"], expected_plan_sha256)
        aliases = {
            "pool": "dlmm_pool::dlmm.universal",
            "payout": "autonomous_payout::validation_fee.universal",
        }
        if aliases.get(operation["contract_key"]) != operation["contract_alias"]:
            raise Refusal("split deploy contract key/alias is outside P1")
        label = nonempty_string("split deploy label", operation["label"])
        if not re.fullmatch(
            r"(?:register_bytes_stage_[0-9]+|register_bytes_finalize|register_manifest|commit)",
            label,
        ):
            raise Refusal("split deploy label is outside the exact deploy sequence")
        if not isinstance(operation["payload_sha256"], str) or not SHA256_RE.fullmatch(
            operation["payload_sha256"]
        ):
            raise Refusal("split deploy payload digest must be lowercase SHA-256")
        normalized_transaction_hash(operation["transaction"])
        return operation
    if kind == "contract_call":
        operation = exact_object(
            "contract call operation",
            value,
            {
                "kind",
                "plan_sha256",
                "contract_address",
                "entrypoint",
                "arguments",
            },
        )
        validate_plan_sha256(operation["plan_sha256"], expected_plan_sha256)
        if operation["contract_address"] != POOL_CONTRACT_ADDRESS:
            raise Refusal(
                "contract call target differs from the exact reviewed P1 pool contract"
            )
        validate_contract_call_arguments(
            operation["entrypoint"],
            operation["arguments"],
        )
        return operation
    raise Refusal("gate request operation kind is unsupported")


def validate_request(
    request: Any,
    expected_plan_sha256: str,
) -> dict[str, Any]:
    if (
        not SHA256_RE.fullmatch(expected_plan_sha256)
        or expected_plan_sha256 == "0" * 64
    ):
        raise Refusal("expected reviewed P1 plan SHA-256 is invalid")
    value = exact_object(
        "gate request",
        request,
        {
            "schema",
            "chain_id",
            "chain_discriminant",
            "block_1_hash",
            "plan_sha256",
            "authority_account_id",
            "sequence",
            "invocation_id",
            "operation",
            "gate_command_sha256",
            "previous_observation",
            "direct",
            "public",
            "mcp",
        },
    )
    if value["schema"] != REQUEST_SCHEMA:
        raise Refusal(f"gate request schema must be {REQUEST_SCHEMA}")
    if value["chain_id"] != CHAIN_ID:
        raise Refusal("gate request has the wrong chain id")
    if value["chain_discriminant"] != CHAIN_DISCRIMINANT:
        raise Refusal("gate request has the wrong chain discriminant")
    if not isinstance(value["block_1_hash"], str) or not SHA256_RE.fullmatch(
        value["block_1_hash"]
    ):
        raise Refusal("gate request block-1 hash must be lowercase SHA-256")
    if value["plan_sha256"] != expected_plan_sha256:
        raise Refusal("gate request is not bound to the exact reviewed P1 plan")
    if value["authority_account_id"] != AUTHORITY_ACCOUNT_ID:
        raise Refusal("gate request has the wrong authority")
    positive_int("gate request sequence", value["sequence"])
    if not isinstance(value["invocation_id"], str) or not value["invocation_id"]:
        raise Refusal("gate request invocation_id must be non-empty")
    validate_operation(value["operation"], expected_plan_sha256)
    if value["operation"]["plan_sha256"] != value["plan_sha256"]:
        raise Refusal("gate request and imminent operation plan digests differ")
    if (
        not isinstance(value["gate_command_sha256"], str)
        or not SHA256_RE.fullmatch(value["gate_command_sha256"])
    ):
        raise Refusal("gate command digest must be lowercase SHA-256")
    expected_direct = [
        {"name": name, "url": url} for name, url in DIRECT_ENDPOINTS
    ]
    if value["direct"] != expected_direct:
        raise Refusal("gate request direct validators differ from fresh Taira")
    if value["public"] != {
        "name": PUBLIC_ENDPOINT[0],
        "url": PUBLIC_ENDPOINT[1],
    }:
        raise Refusal("gate request public endpoint differs from Taira")
    if value["mcp"] != {"endpoint": MCP_ENDPOINT, "tools": list(MCP_TOOLS)}:
        raise Refusal("gate request MCP contract differs from Taira")
    previous = value["previous_observation"]
    if previous is not None:
        exact_object(
            "gate request previous_observation",
            previous,
            {"sha256", "block_height", "block_hash", "created_at"},
        )
        if not SHA256_RE.fullmatch(str(previous["sha256"])):
            raise Refusal("previous gate digest must be lowercase SHA-256")
        positive_int("previous gate block height", previous["block_height"])
        if not SHA256_RE.fullmatch(str(previous["block_hash"])):
            raise Refusal("previous gate block hash must be lowercase SHA-256")
        parse_time("previous gate created_at", previous["created_at"])
    return value


def observation(
    label: str,
    value: Any,
    expected_name: str,
    expected_url: str,
    height: int,
    block_hash: str,
    block_1_hash: str,
) -> None:
    expected = {
        "name": expected_name,
        "url": expected_url,
        "healthy": True,
        "checks": list(CHECKS),
        "chain_id": CHAIN_ID,
        "chain_discriminant": CHAIN_DISCRIMINANT,
        "block_1_hash": block_1_hash,
        "block_height": height,
        "block_hash": block_hash,
    }
    if value != expected:
        raise Refusal(f"{label} is not the exact healthy checkpoint observation")


def validate_marker(
    marker: Any,
    request: dict[str, Any],
    *,
    now: datetime,
    max_age_seconds: int,
) -> dict[str, Any]:
    value = exact_object(
        "gate marker",
        marker,
        {
            "schema",
            "request_sha256",
            "chain_id",
            "chain_discriminant",
            "block_1_hash",
            "plan_sha256",
            "authority_account_id",
            "sequence",
            "invocation_id",
            "operation",
            "gate_command_sha256",
            "created_at",
            "expires_at",
            "consensus",
            "previous_observation",
            "direct",
            "public",
            "mcp",
        },
    )
    if value["schema"] != MARKER_SCHEMA:
        raise Refusal(f"gate marker schema must be {MARKER_SCHEMA}")
    if value["request_sha256"] != sha256(request):
        raise Refusal("gate marker is not bound to the exact request")
    for field in (
        "chain_id",
        "chain_discriminant",
        "block_1_hash",
        "plan_sha256",
        "authority_account_id",
        "sequence",
        "invocation_id",
        "operation",
        "gate_command_sha256",
    ):
        if value[field] != request[field]:
            raise Refusal(f"gate marker changed request field {field}")
    created_at = parse_time("gate marker created_at", value["created_at"])
    expires_at = parse_time("gate marker expires_at", value["expires_at"])
    if expires_at <= created_at:
        raise Refusal("gate marker expiry must follow creation")
    if (expires_at - created_at).total_seconds() > 120:
        raise Refusal("gate marker validity window exceeds 120 seconds")
    if created_at > now:
        raise Refusal("gate marker creation is in the future")
    if now > expires_at:
        raise Refusal("gate marker has expired")
    if (now - created_at).total_seconds() > max_age_seconds:
        raise Refusal("gate marker is too old for an immediate write")
    consensus = exact_object(
        "gate marker consensus",
        value["consensus"],
        {"block_height", "block_hash"},
    )
    height = positive_int("gate marker block height", consensus["block_height"])
    block_hash = consensus["block_hash"]
    if not isinstance(block_hash, str) or not SHA256_RE.fullmatch(block_hash):
        raise Refusal("gate marker block hash must be lowercase SHA-256")
    previous = request["previous_observation"]
    if previous is None:
        if value["previous_observation"] is not None:
            raise Refusal("first gate marker must not claim a predecessor")
    else:
        expected_previous = {**previous, "verified_ancestor": True}
        if value["previous_observation"] != expected_previous:
            raise Refusal("gate marker did not attest the exact predecessor ancestry")
        previous_time = parse_time("previous gate created_at", previous["created_at"])
        if created_at <= previous_time:
            raise Refusal("gate marker creation time did not advance")
        if height < previous["block_height"]:
            raise Refusal("gate marker checkpoint rollback detected")
        if height == previous["block_height"] and block_hash != previous["block_hash"]:
            raise Refusal("gate marker same-height equivocation detected")
    direct = value["direct"]
    if not isinstance(direct, list) or len(direct) != len(DIRECT_ENDPOINTS):
        raise Refusal("gate marker must contain exactly four direct validators")
    for observed, (name, url) in zip(direct, DIRECT_ENDPOINTS, strict=True):
        observation(
            "direct gate observation",
            observed,
            name,
            url,
            height,
            block_hash,
            request["block_1_hash"],
        )
    observation(
        "public gate observation",
        value["public"],
        PUBLIC_ENDPOINT[0],
        PUBLIC_ENDPOINT[1],
        height,
        block_hash,
        request["block_1_hash"],
    )
    expected_mcp = {
        "endpoint": MCP_ENDPOINT,
        "tools": list(MCP_TOOLS),
        "healthy": True,
        "chain_id": CHAIN_ID,
        "chain_discriminant": CHAIN_DISCRIMINANT,
        "block_1_hash": request["block_1_hash"],
        "block_height": height,
        "block_hash": block_hash,
    }
    if value["mcp"] != expected_mcp:
        raise Refusal("gate marker MCP observation is not exact")
    return value


def strict_json(text: str, label: str) -> Any:
    def object_without_duplicates(
        pairs: list[tuple[str, Any]],
    ) -> dict[str, Any]:
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
            object_pairs_hook=object_without_duplicates,
            parse_constant=reject_nonfinite,
        )
    except json.JSONDecodeError as error:
        raise Refusal(f"{label} is not valid JSON") from error


def load_json(path: Path, *, require_canonical: bool = True) -> Any:
    try:
        raw = path.read_bytes()
        text = raw.decode("utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise Refusal(f"could not read canonical JSON from {path}") from error
    value = strict_json(text, str(path))
    if require_canonical and raw != canonical_bytes(value):
        raise Refusal(f"{path} is not canonical JSON")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", type=Path)
    parser.add_argument("--marker", type=Path)
    parser.add_argument(
        "--operation",
        type=Path,
        help="validate one canonical imminent operation without running a gate",
    )
    parser.add_argument(
        "--revalidate-marker",
        type=Path,
        help="revalidate one published marker at the current time",
    )
    parser.add_argument("--max-age-seconds", type=int, default=60)
    parser.add_argument(
        "--historical",
        action="store_true",
        help="validate an immutable past marker at its recorded creation time",
    )
    parser.add_argument(
        "--expected-plan-sha256",
        required=True,
        help="exact canonical SHA-256 of the immutable reviewed P1 plan",
    )
    args = parser.parse_args()
    try:
        if (
            not SHA256_RE.fullmatch(args.expected_plan_sha256)
            or args.expected_plan_sha256 == "0" * 64
        ):
            raise Refusal("expected reviewed P1 plan SHA-256 is invalid")
        if args.max_age_seconds <= 0 or args.max_age_seconds > 60:
            raise Refusal("max age must be in 1..60 seconds")
        if args.revalidate_marker is not None:
            if (
                args.request is not None
                or args.marker is not None
                or args.operation is not None
                or args.historical
            ):
                raise Refusal("--revalidate-marker cannot be combined with other inputs")
            marker_value = load_json(args.revalidate_marker)
            if not isinstance(marker_value, dict):
                raise Refusal("published gate marker must be an object")
            marker_previous = marker_value.get("previous_observation")
            if marker_previous is not None and not isinstance(marker_previous, dict):
                raise Refusal("published gate predecessor must be an object or null")
            request_value = {
                "schema": REQUEST_SCHEMA,
                "chain_id": marker_value.get("chain_id"),
                "chain_discriminant": marker_value.get("chain_discriminant"),
                "block_1_hash": marker_value.get("block_1_hash"),
                "plan_sha256": marker_value.get("plan_sha256"),
                "authority_account_id": marker_value.get("authority_account_id"),
                "sequence": marker_value.get("sequence"),
                "invocation_id": marker_value.get("invocation_id"),
                "operation": marker_value.get("operation"),
                "gate_command_sha256": marker_value.get("gate_command_sha256"),
                "previous_observation": (
                    None
                    if marker_previous is None
                    else {
                        key: marker_previous.get(key)
                        for key in (
                            "sha256",
                            "block_height",
                            "block_hash",
                            "created_at",
                        )
                    }
                ),
                "direct": [
                    {"name": name, "url": url} for name, url in DIRECT_ENDPOINTS
                ],
                "public": {
                    "name": PUBLIC_ENDPOINT[0],
                    "url": PUBLIC_ENDPOINT[1],
                },
                "mcp": {
                    "endpoint": MCP_ENDPOINT,
                    "tools": list(MCP_TOOLS),
                },
            }
            request = validate_request(
                request_value,
                args.expected_plan_sha256,
            )
            marker = validate_marker(
                marker_value,
                request,
                now=datetime.now(timezone.utc),
                max_age_seconds=args.max_age_seconds,
            )
            sys.stdout.buffer.write(canonical_bytes(marker))
            return 0
        if args.operation is not None:
            if (
                args.request is not None
                or args.marker is not None
                or args.historical
            ):
                raise Refusal("--operation cannot be combined with gate inputs")
            operation = validate_operation(
                load_json(args.operation, require_canonical=False),
                args.expected_plan_sha256,
            )
            sys.stdout.buffer.write(canonical_bytes(operation))
            return 0
        if args.request is None or args.marker is None:
            raise Refusal("--request and --marker are required together")
        request = validate_request(
            load_json(args.request),
            args.expected_plan_sha256,
        )
        marker_value = load_json(args.marker)
        validation_time = (
            parse_time("gate marker created_at", marker_value.get("created_at"))
            if args.historical and isinstance(marker_value, dict)
            else datetime.now(timezone.utc)
        )
        marker = validate_marker(
            marker_value,
            request,
            now=validation_time,
            max_age_seconds=args.max_age_seconds,
        )
        sys.stdout.buffer.write(canonical_bytes(marker))
        return 0
    except Refusal as error:
        print(f"validation-fee write gate refused: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
