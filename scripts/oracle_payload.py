#!/usr/bin/env python3
"""Build signed SoraSwap oracle payload blobs for smoke/bootstrap tooling."""

from __future__ import annotations

import argparse
import json
import os
import sys


def _strip_hex_prefix(raw: str) -> str:
    value = raw.strip()
    if value.startswith(("ed25519:", "ED25519:")):
        value = value.split(":", 1)[1]
    if value.startswith(("0x", "0X")):
        value = value[2:]
    return value.strip()


def _decode_hex(raw: str, label: str) -> bytes:
    value = _strip_hex_prefix(raw)
    try:
        return bytes.fromhex(value)
    except ValueError as exc:
        raise SystemExit(f"{label} must be hexadecimal") from exc


def normalize_public_key(raw: str) -> bytes:
    data = _decode_hex(raw, "public key")
    if len(data) == 35 and data[:3] == bytes.fromhex("ed0120"):
        data = data[3:]
    if len(data) != 32:
        raise SystemExit("public key must be a raw 32-byte Ed25519 key or ed0120-prefixed Iroha key")
    return data


def normalize_private_seed(raw: str) -> bytes:
    data = _decode_hex(raw, "private key")
    if len(data) == 35 and data[:3] == bytes.fromhex("802620"):
        data = data[3:]
    if len(data) == 64:
        data = data[:32]
    if len(data) != 32:
        raise SystemExit("private key must be a raw 32-byte seed, 64-byte seed+public key, or 802620-prefixed Iroha key")
    return data


def compact_payload(raw_json: str) -> bytes:
    try:
        value = json.loads(raw_json)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"payload JSON is invalid: {exc}") from exc
    return json.dumps(value, separators=(",", ":"), ensure_ascii=True).encode("utf-8")


def sign_payload(payload: bytes, private_key_hex: str) -> tuple[bytes, bytes]:
    try:
        from nacl.signing import SigningKey
    except ImportError as exc:
        raise SystemExit("PyNaCl is required for oracle signing; install the nacl Python package") from exc

    signing_key = SigningKey(normalize_private_seed(private_key_hex))
    signature = signing_key.sign(payload).signature
    public_key = bytes(signing_key.verify_key)
    return signature, public_key


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--payload-json", help="Raw JSON payload to compact and sign")
    parser.add_argument("--payload-file", help="File containing raw JSON payload to compact and sign")
    parser.add_argument("--private-key-hex", default=os.environ.get("SORASWAP_ORACLE_PRIVATE_KEY_HEX", ""))
    parser.add_argument("--normalize-public-key-hex", help="Normalize a raw or Iroha-prefixed public key and exit")
    args = parser.parse_args()

    if args.normalize_public_key_hex:
        print("0x" + normalize_public_key(args.normalize_public_key_hex).hex())
        return 0

    if args.payload_json is None and args.payload_file is None:
        parser.error("--payload-json or --payload-file is required")
    if not args.private_key_hex:
        raise SystemExit("SORASWAP_ORACLE_PRIVATE_KEY_HEX is required to sign oracle payloads")

    if args.payload_file:
        with open(args.payload_file, "r", encoding="utf-8") as handle:
            raw_json = handle.read()
    else:
        raw_json = args.payload_json

    payload = compact_payload(raw_json)
    signature, public_key = sign_payload(payload, args.private_key_hex)
    print(
        json.dumps(
            {
                "oracle_payload": "0x" + payload.hex(),
                "oracle_signature": "0x" + signature.hex(),
                "oracle_public_key": "0x" + public_key.hex(),
                "oracle_payload_bytes": list(payload),
                "oracle_signature_bytes": list(signature),
                "oracle_public_key_bytes": list(public_key),
                "payload_json": payload.decode("utf-8"),
            },
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
