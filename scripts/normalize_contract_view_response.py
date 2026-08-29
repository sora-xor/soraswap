#!/usr/bin/env python3
"""Validate and normalize the exact current Torii contract-view result."""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path
from typing import Any


HASH_LITERAL_RE = re.compile(r"^hash:([0-9A-Fa-f]{64})#[0-9A-Fa-f]{4}$")
LOWER_HASH_RE = re.compile(r"^[0-9a-f]{64}$")
INT_RE = re.compile(r"^(?:0|[1-9][0-9]*|-[1-9][0-9]*)$")
UNSIGNED_DECIMAL_RE = re.compile(
    r"^(?:0|[1-9][0-9]*)(?:\.[0-9]*[1-9])?$"
)
SIGNED_DECIMAL_RE = re.compile(
    r"^(?:0|[1-9][0-9]*|-[1-9][0-9]*|0\.[0-9]*[1-9]|-0\.[0-9]*[1-9]|[1-9][0-9]*\.[0-9]*[1-9]|-[1-9][0-9]*\.[0-9]*[1-9])$"
)
BLOB_RE = re.compile(r"^0x(?:[0-9a-f]{2})*$")
MAX_POSITIVE_MANTISSA = (1 << 511) - 1
MAX_NEGATIVE_MAGNITUDE = 1 << 511
NUMERIC_LEAF_KINDS = frozenset({"Int", "Decimal", "Quantity"})
STRING_LEAF_KINDS = frozenset(
    {
        "AccountId",
        "AssetDefinitionId",
        "AssetId",
        "DomainId",
        "Name",
        "NftId",
        "String",
    }
)


class ContractViewNormalizationError(ValueError):
    """The response is not bound to the exact current compiled return schema."""


def _reject_constant(value: str) -> None:
    raise ContractViewNormalizationError(f"non-finite JSON constant is forbidden: {value}")


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ContractViewNormalizationError(f"duplicate JSON key is forbidden: {key}")
        result[key] = value
    return result


def parse_exact_json(raw: str) -> Any:
    try:
        return json.loads(
            raw,
            parse_constant=_reject_constant,
            object_pairs_hook=_reject_duplicate_keys,
        )
    except ContractViewNormalizationError:
        raise
    except (TypeError, json.JSONDecodeError) as error:
        raise ContractViewNormalizationError(f"invalid JSON: {error}") from error


def _hash_literal_hex(value: Any, field: str, manifest_path: Path) -> str:
    if not isinstance(value, str):
        raise ContractViewNormalizationError(
            f"{manifest_path}: {field} must be a canonical hash literal"
        )
    match = HASH_LITERAL_RE.fullmatch(value)
    if match is None:
        raise ContractViewNormalizationError(
            f"{manifest_path}: {field} must be a canonical hash literal"
        )
    return match.group(1).lower()


def _load_bound_manifest(
    repo_root: Path, code_hash_hex: str, abi_hash_hex: str
) -> tuple[Path, dict[str, Any]]:
    manifests_root = repo_root / "artifacts" / "compiled"
    matches: list[tuple[Path, dict[str, Any]]] = []
    for manifest_path in sorted(manifests_root.glob("*/*.manifest.json")):
        try:
            parsed = parse_exact_json(manifest_path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, ContractViewNormalizationError) as error:
            raise ContractViewNormalizationError(
                f"unable to read compiled manifest {manifest_path}: {error}"
            ) from error
        if not isinstance(parsed, dict):
            raise ContractViewNormalizationError(
                f"compiled manifest is not a JSON object: {manifest_path}"
            )
        manifest_code_hash = _hash_literal_hex(
            parsed.get("code_hash"), "code_hash", manifest_path
        )
        manifest_abi_hash = _hash_literal_hex(
            parsed.get("abi_hash"), "abi_hash", manifest_path
        )
        if manifest_code_hash == code_hash_hex and manifest_abi_hash == abi_hash_hex:
            matches.append((manifest_path, parsed))

    if len(matches) != 1:
        raise ContractViewNormalizationError(
            "contract view response must match exactly one current compiled manifest; "
            f"found {len(matches)} for code_hash={code_hash_hex} abi_hash={abi_hash_hex}"
        )
    return matches[0]


def _bound_view_entrypoint(
    manifest_path: Path, manifest: dict[str, Any], entrypoint: str
) -> dict[str, Any]:
    entrypoints = manifest.get("entrypoints")
    if not isinstance(entrypoints, list):
        raise ContractViewNormalizationError(
            f"{manifest_path}: entrypoints must be an array"
        )
    matches = [
        item
        for item in entrypoints
        if isinstance(item, dict) and item.get("name") == entrypoint
    ]
    if len(matches) != 1:
        raise ContractViewNormalizationError(
            f"{manifest_path}: expected exactly one entrypoint named {entrypoint!r}"
        )
    descriptor = matches[0]
    if descriptor.get("kind") != {"kind": "View", "value": None}:
        raise ContractViewNormalizationError(
            f"{manifest_path}: {entrypoint} is not an exact current View entrypoint"
        )
    if not isinstance(descriptor.get("return_schema"), dict):
        raise ContractViewNormalizationError(
            f"{manifest_path}: {entrypoint} has no current return schema"
        )
    return descriptor


def _canonical_numeric_text(value: Any, kind: str, path: str) -> str:
    if not isinstance(value, str):
        raise ContractViewNormalizationError(
            f"{path} for {kind} must be a canonical JSON string, got {type(value).__name__}"
        )

    if kind == "Int":
        if INT_RE.fullmatch(value) is None:
            raise ContractViewNormalizationError(f"{path} is not a canonical int string")
        mantissa = int(value)
    else:
        pattern = UNSIGNED_DECIMAL_RE if kind == "Quantity" else SIGNED_DECIMAL_RE
        if pattern.fullmatch(value) is None:
            raise ContractViewNormalizationError(
                f"{path} is not a canonical {kind.lower()} string"
            )
        integer, separator, fraction = value.partition(".")
        if separator and len(fraction) > 28:
            raise ContractViewNormalizationError(
                f"{path} exceeds the current 28-digit decimal scale"
            )
        digits = f"{integer}{fraction}"
        mantissa = int(digits)

    if mantissa >= 0:
        in_range = mantissa <= MAX_POSITIVE_MANTISSA
    else:
        in_range = -mantissa <= MAX_NEGATIVE_MAGNITUDE
    if not in_range:
        raise ContractViewNormalizationError(
            f"{path} exceeds the current signed 512-bit numeric domain"
        )
    return value


def _native_numeric(value: str, kind: str) -> int | float:
    if kind == "Int" or "." not in value:
        return int(value)
    native = float(value)
    if not math.isfinite(native):
        raise ContractViewNormalizationError(
            f"{kind.lower()} cannot be represented by the internal JSON number schema"
        )
    return native


def _normalize_leaf(value: Any, kind: str, path: str) -> Any:
    if kind in NUMERIC_LEAF_KINDS:
        canonical = _canonical_numeric_text(value, kind, path)
        return _native_numeric(canonical, kind)
    if kind in STRING_LEAF_KINDS:
        if not isinstance(value, str) or not value:
            raise ContractViewNormalizationError(
                f"{path} for {kind} must be a non-empty JSON string"
            )
        return value
    if kind == "Blob":
        if not isinstance(value, str) or BLOB_RE.fullmatch(value) is None:
            raise ContractViewNormalizationError(
                f"{path} for Blob must be canonical lowercase 0x-prefixed bytes"
            )
        return value
    if kind == "Bool":
        if not isinstance(value, bool):
            raise ContractViewNormalizationError(f"{path} for Bool must be a JSON boolean")
        return value
    if kind == "DataSpaceId":
        if type(value) is not int or value < 0 or value > (1 << 64) - 1:
            raise ContractViewNormalizationError(
                f"{path} for DataSpaceId must be a native unsigned 64-bit JSON number"
            )
        return value
    if kind == "Json":
        return value
    raise ContractViewNormalizationError(
        f"{path} uses unsupported current return leaf kind {kind!r}"
    )


def _return_leaf_kinds(return_schema: dict[str, Any], context: str) -> list[str]:
    nodes = return_schema.get("nodes")
    if not isinstance(nodes, list) or not nodes:
        raise ContractViewNormalizationError(f"{context}: return schema nodes are missing")

    if isinstance(nodes[0], dict) and nodes[0].get("kind") == "Leaf":
        if len(nodes) != 1:
            raise ContractViewNormalizationError(
                f"{context}: scalar return schema has trailing nodes"
            )
        leaf_nodes = nodes
    else:
        root = nodes[0]
        if not isinstance(root, dict) or root.get("kind") != "Tuple":
            raise ContractViewNormalizationError(
                f"{context}: unsupported current return schema root"
            )
        count = root.get("value")
        if type(count) is not int or count < 1 or len(nodes) != count + 1:
            raise ContractViewNormalizationError(
                f"{context}: tuple return schema has an invalid arity"
            )
        leaf_nodes = nodes[1:]

    kinds: list[str] = []
    for index, node in enumerate(leaf_nodes):
        if not isinstance(node, dict) or node.get("kind") != "Leaf":
            raise ContractViewNormalizationError(
                f"{context}: return node {index} is not a current scalar leaf"
            )
        value = node.get("value")
        kind = value.get("kind") if isinstance(value, dict) else None
        if not isinstance(kind, str) or value != {"kind": kind, "value": None}:
            raise ContractViewNormalizationError(
                f"{context}: return leaf {index} has an invalid exact shape"
            )
        kinds.append(kind)
    return kinds


def normalize_response(
    repo_root: Path,
    response: Any,
    contract_address: str,
    entrypoint: str,
) -> dict[str, Any]:
    if not isinstance(response, dict):
        raise ContractViewNormalizationError("contract view response must be a JSON object")
    if response.get("contract_address") != contract_address:
        raise ContractViewNormalizationError("contract view response address does not match")
    if response.get("entrypoint") != entrypoint:
        raise ContractViewNormalizationError("contract view response entrypoint does not match")
    code_hash_hex = response.get("code_hash_hex")
    abi_hash_hex = response.get("abi_hash_hex")
    if not isinstance(code_hash_hex, str) or LOWER_HASH_RE.fullmatch(code_hash_hex) is None:
        raise ContractViewNormalizationError("response code_hash_hex is not canonical lowercase hex")
    if not isinstance(abi_hash_hex, str) or LOWER_HASH_RE.fullmatch(abi_hash_hex) is None:
        raise ContractViewNormalizationError("response abi_hash_hex is not canonical lowercase hex")

    manifest_path, manifest = _load_bound_manifest(repo_root, code_hash_hex, abi_hash_hex)
    descriptor = _bound_view_entrypoint(manifest_path, manifest, entrypoint)
    context = f"{manifest_path}:{entrypoint}"
    leaf_kinds = _return_leaf_kinds(descriptor["return_schema"], context)
    raw_result = response.get("result")

    if len(leaf_kinds) == 1 and descriptor["return_schema"]["nodes"][0]["kind"] == "Leaf":
        normalized_result = _normalize_leaf(raw_result, leaf_kinds[0], "result")
    else:
        if not isinstance(raw_result, list) or len(raw_result) != len(leaf_kinds):
            raise ContractViewNormalizationError(
                f"result must be a {len(leaf_kinds)}-element array for {context}"
            )
        normalized_result = [
            _normalize_leaf(value, kind, f"result[{index}]")
            for index, (value, kind) in enumerate(zip(raw_result, leaf_kinds))
        ]

    normalized = dict(response)
    normalized["normalized_result"] = normalized_result
    return normalized


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--contract-address", required=True)
    parser.add_argument("--entrypoint", required=True)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        response = parse_exact_json(sys.stdin.read())
        normalized = normalize_response(
            args.repo_root.resolve(),
            response,
            args.contract_address,
            args.entrypoint,
        )
    except (ContractViewNormalizationError, OSError, UnicodeError) as error:
        print(f"current contract view normalization failed: {error}", file=sys.stderr)
        return 1
    json.dump(normalized, sys.stdout, separators=(",", ":"), ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
