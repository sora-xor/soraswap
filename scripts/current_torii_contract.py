#!/usr/bin/env python3
"""Invoke current authenticated Torii contract routes from shell workflows."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

try:
    from serve_contract_console import (
        MAX_REQUEST_BODY_BYTES,
        REPO_ROOT,
        build_proxy_result,
        execute_detached_contract_call,
        load_signer_binding,
        proxy_torii_request,
        url_origin,
    )
except ModuleNotFoundError:
    from scripts.serve_contract_console import (
        MAX_REQUEST_BODY_BYTES,
        REPO_ROOT,
        build_proxy_result,
        execute_detached_contract_call,
        load_signer_binding,
        proxy_torii_request,
        url_origin,
    )


class ContractTransportError(ValueError):
    """Stable user-facing failure for the shell transport."""


LOWER_HASH_RE = re.compile(r"^[0-9a-f]{64}$")


def _closed_json_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ContractTransportError(f"request JSON contains duplicate field: {key}")
        result[key] = value
    return result


def _read_request() -> dict[str, Any]:
    raw = sys.stdin.buffer.read(MAX_REQUEST_BODY_BYTES + 1)
    if len(raw) > MAX_REQUEST_BODY_BYTES:
        raise ContractTransportError("request JSON exceeds the current Torii request limit")
    try:
        decoded = json.loads(raw, object_pairs_hook=_closed_json_object)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ContractTransportError("request body must be one complete UTF-8 JSON object") from exc
    if not isinstance(decoded, dict):
        raise ContractTransportError("request body must be a JSON object")
    return decoded


def _require_exact_fields(
    request: dict[str, Any],
    *,
    required: set[str],
    optional: set[str],
    context: str,
) -> None:
    missing = required - set(request)
    unexpected = set(request) - required - optional
    if missing:
        raise ContractTransportError(
            f"{context} request is missing current field(s): {', '.join(sorted(missing))}"
        )
    if unexpected:
        raise ContractTransportError(
            f"{context} request contains unsupported field(s): {', '.join(sorted(unexpected))}"
        )


def _validate_request(command: str, request: dict[str, Any], authority: str) -> str:
    if request.get("authority") != authority:
        raise ContractTransportError(
            "request authority must exactly match the canonical account signer"
        )
    if command == "call":
        _require_exact_fields(
            request,
            required={"authority", "entrypoint", "fee_payment"},
            optional={
                "contract_address",
                "contract_alias",
                "payload",
                "creation_time_ms",
                "transaction_ttl_ms",
            },
            context="contract call",
        )
        return "/v1/contracts/call"
    if command == "view":
        _require_exact_fields(
            request,
            required={"authority", "entrypoint", "gas_limit"},
            optional={"contract_address", "contract_alias", "payload"},
            context="contract view",
        )
        return "/v1/contracts/view"
    _require_exact_fields(
        request,
        required={"authority", "items"},
        optional={"gas_limit"},
        context="contract batch view",
    )
    return "/v1/contracts/view/batch"


def _require_contract_selector(request: dict[str, Any], *, context: str) -> None:
    selectors = [field for field in ("contract_address", "contract_alias") if field in request]
    if len(selectors) != 1:
        raise ContractTransportError(
            f"{context} request requires exactly one of contract_address or contract_alias"
        )
    selector = request[selectors[0]]
    if not isinstance(selector, str) or not selector or selector.strip() != selector:
        raise ContractTransportError(f"{context} {selectors[0]} must be an exact non-empty string")


def _require_positive_integer(value: Any, *, context: str) -> None:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ContractTransportError(f"{context} must be a positive integer")


def _validate_entrypoint(request: dict[str, Any], *, context: str) -> None:
    entrypoint = request.get("entrypoint")
    if not isinstance(entrypoint, str) or not entrypoint or entrypoint.strip() != entrypoint:
        raise ContractTransportError(f"{context} entrypoint must be an exact non-empty string")


def _validate_call_fee_payment(request: dict[str, Any]) -> None:
    fee_payment = request.get("fee_payment")
    if not isinstance(fee_payment, dict) or set(fee_payment) != {"payer", "value"}:
        raise ContractTransportError("contract call fee_payment must contain only payer and value")
    if fee_payment.get("payer") != "authority":
        raise ContractTransportError("contract call fee_payment.payer must be authority")
    value = fee_payment.get("value")
    if not isinstance(value, dict) or set(value) != {"charge_limits", "gas_limit"}:
        raise ContractTransportError(
            "contract call fee_payment.value must contain only charge_limits and gas_limit"
        )
    if value.get("charge_limits") != []:
        raise ContractTransportError(
            "contract call preparation must leave charge_limits empty for Torii quotation"
        )
    _require_positive_integer(
        value.get("gas_limit"), context="contract call fee_payment.value.gas_limit"
    )


def _validate_shape(command: str, request: dict[str, Any]) -> None:
    if command in {"call", "view"}:
        _require_contract_selector(request, context=f"contract {command}")
        _validate_entrypoint(request, context=f"contract {command}")
        if command == "view":
            _require_positive_integer(
                request.get("gas_limit"), context="contract view gas_limit"
            )
        else:
            _validate_call_fee_payment(request)
            for field in ("creation_time_ms", "transaction_ttl_ms"):
                if field in request:
                    _require_positive_integer(
                        request[field], context=f"contract call {field}"
                    )
        return
    if "gas_limit" in request:
        _require_positive_integer(
            request["gas_limit"], context="contract batch view gas_limit"
        )
    items = request.get("items")
    if not isinstance(items, list) or not items:
        raise ContractTransportError("contract batch view items must be a non-empty array")
    for index, item in enumerate(items):
        if not isinstance(item, dict):
            raise ContractTransportError(f"contract batch view item {index} must be an object")
        _require_exact_fields(
            item,
            required={"entrypoint"},
            optional={"request_id", "contract_address", "contract_alias", "payload", "gas_limit"},
            context=f"contract batch view item {index}",
        )
        _require_contract_selector(item, context=f"contract batch view item {index}")
        _validate_entrypoint(item, context=f"contract batch view item {index}")
        if "request_id" in item and (
            not isinstance(item["request_id"], str)
            or not item["request_id"]
            or item["request_id"].strip() != item["request_id"]
        ):
            raise ContractTransportError(
                f"contract batch view item {index} request_id must be an exact non-empty string"
            )
        if "gas_limit" in item:
            _require_positive_integer(
                item["gas_limit"],
                context=f"contract batch view item {index} gas_limit",
            )


def _execute_once(
    *,
    environment: str,
    signer: Any,
    torii_url: str,
    mode: str,
    path: str,
    request_payload: dict[str, Any],
    timeout: int,
) -> dict[str, Any]:
    status, response_text, content_type = proxy_torii_request(
        torii_url,
        path,
        method="POST",
        payload=request_payload,
        query=None,
        basic_auth=signer.basic_auth,
        timeout=timeout,
        canonical_signer=signer,
    )
    return build_proxy_result(
        environment=environment,
        torii_url=torii_url,
        signer=signer,
        mode=mode,
        path=path,
        query=None,
        request_payload=request_payload,
        upstream_status=status,
        upstream_content_type=content_type,
        response_text=response_text,
    )


def _successful_response(result: dict[str, Any], *, context: str) -> Any:
    if not result.get("ok"):
        status = result.get("upstream_status")
        code = result.get("error_code")
        suffix = f" ({code})" if isinstance(code, str) and code else ""
        raise ContractTransportError(f"{context} failed with Torii HTTP {status}{suffix}")
    response = result.get("response_json")
    if not isinstance(response, (dict, list)):
        raise ContractTransportError(f"{context} returned a non-JSON response")
    return response


def _validate_view_success(
    response: Any,
    request: dict[str, Any],
    *,
    context: str,
) -> dict[str, Any]:
    expected_fields = {
        "ok",
        "dataspace",
        "contract_address",
        "code_hash_hex",
        "abi_hash_hex",
        "entrypoint",
        "result",
    }
    if "request_id" in request:
        expected_fields.add("request_id")
    if not isinstance(response, dict) or set(response) != expected_fields:
        raise ContractTransportError(f"{context} does not match the closed current Torii DTO")
    if response.get("ok") is not True:
        raise ContractTransportError(f"{context} did not succeed")
    if "request_id" in request and response.get("request_id") != request.get("request_id"):
        raise ContractTransportError(f"{context} changed request_id")
    if request.get("contract_address") is not None and response.get(
        "contract_address"
    ) != request.get("contract_address"):
        raise ContractTransportError(f"{context} changed contract_address")
    if not isinstance(response.get("contract_address"), str) or not response[
        "contract_address"
    ]:
        raise ContractTransportError(f"{context} omitted contract_address")
    if response.get("entrypoint") != request.get("entrypoint"):
        raise ContractTransportError(f"{context} changed entrypoint")
    if not isinstance(response.get("dataspace"), str) or not response["dataspace"]:
        raise ContractTransportError(f"{context} omitted dataspace")
    for field in ("code_hash_hex", "abi_hash_hex"):
        value = response.get(field)
        if (
            not isinstance(value, str)
            or LOWER_HASH_RE.fullmatch(value) is None
            or set(value) == {"0"}
        ):
            raise ContractTransportError(f"{context} returned an invalid {field}")
    return response


def _validate_batch_view_response(response: Any, request: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(response, dict) or set(response) != {"items", "ok"}:
        raise ContractTransportError(
            "contract batch view response does not match the closed current Torii DTO"
        )
    items = response.get("items")
    expected_items = request["items"]
    if response.get("ok") is not True or not isinstance(items, list):
        raise ContractTransportError("contract batch view did not complete successfully")
    if len(items) != len(expected_items):
        raise ContractTransportError("contract batch view response item count changed")
    for index, (item, expected) in enumerate(zip(items, expected_items, strict=True)):
        _validate_view_success(
            item,
            expected,
            context=f"contract batch view item {index}",
        )
    return response


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--environment", choices=("local", "testnet", "production"), required=True)
    parser.add_argument("--authority", required=True)
    parser.add_argument("--torii-url", required=True)
    parser.add_argument("--timeout", type=int, default=60)
    parser.add_argument("command", choices=("call", "view", "view-batch"))
    return parser


def main() -> int:
    args = _parser().parse_args()
    if args.timeout <= 0:
        raise ContractTransportError("timeout must be a positive integer")
    request = _read_request()
    path = _validate_request(args.command, request, args.authority)
    _validate_shape(args.command, request)
    signer = load_signer_binding(
        args.environment,
        args.config,
        args.authority,
        source="shell-contract-transport",
        repo_root=Path(REPO_ROOT),
    )
    if not signer.can_call or signer.authority != args.authority:
        raise ContractTransportError("client config cannot authenticate the requested authority")
    require_https = signer.basic_auth is not None or args.environment == "production"
    if signer.torii_url is None or url_origin(
        signer.torii_url,
        require_https=require_https,
        require_root=True,
    ) != url_origin(
        args.torii_url,
        require_https=require_https,
        require_root=True,
    ):
        raise ContractTransportError("Torii URL must exactly keep the signer config origin")

    if args.command == "call":
        result = execute_detached_contract_call(
            _execute_once,
            environment=args.environment,
            signer=signer,
            torii_url=args.torii_url,
            request_payload=request,
            timeout=args.timeout,
        )
        response = _successful_response(result, context="contract call submission")
    else:
        result = _execute_once(
            environment=args.environment,
            signer=signer,
            torii_url=args.torii_url,
            mode=args.command,
            path=path,
            request_payload=request,
            timeout=args.timeout,
        )
        response = _successful_response(result, context=f"contract {args.command}")
        if args.command == "view":
            response = _validate_view_success(
                response,
                request,
                context="contract view response",
            )
        else:
            response = _validate_batch_view_response(response, request)
    print(json.dumps(response, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ContractTransportError, OSError, ValueError) as exc:
        print(f"current Torii contract request failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
