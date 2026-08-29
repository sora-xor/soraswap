#!/usr/bin/env python3
"""Iroha V1 canonical account-request authentication primitives."""

from __future__ import annotations

import base64
import hashlib
import os
import re
import secrets
import shutil
import subprocess
import tempfile
import time
import urllib.parse
from typing import Any


ED25519_PRIVATE_MULTIHASH_RE = re.compile(r"^802620([0-9A-Fa-f]{64})$")
ED25519_PUBLIC_MULTIHASH_RE = re.compile(r"^ed0120([0-9A-Fa-f]{64})$", re.IGNORECASE)
CANONICAL_NETWORK_ID_RE = re.compile(r"^hash:([0-9A-F]{64})#([0-9A-F]{4})$")
CANONICAL_ACCOUNT_AUTH_HEADERS = (
    "X-Iroha-Account",
    "X-Iroha-Signature",
    "X-Iroha-Timestamp-Ms",
    "X-Iroha-Nonce",
)


def _anonymous_regular_file(payload: bytes) -> int:
    fd, path = tempfile.mkstemp(prefix="soraswap-ed25519-sign-")
    try:
        os.fchmod(fd, 0o600)
        view = memoryview(payload)
        offset = 0
        while offset < len(view):
            written = os.write(fd, view[offset:])
            if written <= 0:
                raise OSError("short write while preparing Ed25519 signing input")
            offset += written
        os.lseek(fd, 0, os.SEEK_SET)
        os.unlink(path)
        return fd
    except Exception:
        os.close(fd)
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
        raise


def _run_openssl_pkeyutl(
    arguments: list[str], inputs: list[bytes]
) -> subprocess.CompletedProcess[bytes]:
    openssl = shutil.which("openssl")
    if not openssl:
        raise ValueError("local Ed25519 signing requires the openssl executable")
    descriptors: list[int] = []
    try:
        descriptors = [_anonymous_regular_file(value) for value in inputs]
        command = [openssl, "pkeyutl", *arguments]
        command = [
            part.format(**{f"fd{index}": fd for index, fd in enumerate(descriptors)})
            for part in command
        ]
        try:
            return subprocess.run(
                command,
                capture_output=True,
                check=False,
                close_fds=True,
                pass_fds=tuple(descriptors),
                timeout=10,
            )
        except (OSError, subprocess.SubprocessError) as exc:
            raise ValueError("local Ed25519 signing failed to execute") from exc
    finally:
        for fd in descriptors:
            os.close(fd)


def raw_ed25519_public_key_hex(public_key: str | None) -> str:
    public_match = ED25519_PUBLIC_MULTIHASH_RE.fullmatch(public_key or "")
    if public_match is None:
        raise ValueError("Ed25519 signing requires a canonical public key")
    return public_match.group(1).lower()


def verify_ed25519_signature_b64(
    public_key: str | None,
    message: bytes,
    signature_b64: str,
) -> bool:
    try:
        signature = base64.b64decode(signature_b64, validate=True)
    except (ValueError, TypeError):
        return False
    if len(signature) != 64 or base64.b64encode(signature).decode("ascii") != signature_b64:
        return False
    public_der = bytes.fromhex("302a300506032b6570032100") + bytes.fromhex(
        raw_ed25519_public_key_hex(public_key)
    )
    verified = _run_openssl_pkeyutl(
        [
            "-verify",
            "-rawin",
            "-pubin",
            "-inkey",
            "/dev/fd/{fd0}",
            "-keyform",
            "DER",
            "-in",
            "/dev/fd/{fd1}",
            "-sigfile",
            "/dev/fd/{fd2}",
        ],
        [public_der, message, signature],
    )
    return verified.returncode == 0


def sign_ed25519_message(
    private_key: str,
    public_key: str | None,
    message: bytes,
    *,
    context: str,
) -> str:
    private_match = ED25519_PRIVATE_MULTIHASH_RE.fullmatch(private_key)
    if private_match is None:
        raise ValueError(f"{context} requires a canonical Ed25519 private key")
    private_der = bytes.fromhex("302e020100300506032b657004220420") + bytes.fromhex(
        private_match.group(1)
    )
    signed = _run_openssl_pkeyutl(
        ["-sign", "-rawin", "-inkey", "/dev/fd/{fd0}", "-keyform", "DER", "-in", "/dev/fd/{fd1}"],
        [private_der, message],
    )
    if signed.returncode != 0 or len(signed.stdout) != 64:
        raise ValueError(f"local {context} failed")
    signature_b64 = base64.b64encode(signed.stdout).decode("ascii")
    if not verify_ed25519_signature_b64(public_key, message, signature_b64):
        raise ValueError("configured Ed25519 public and private keys do not form a signing pair")
    return signature_b64


def _iroha_literal_crc16(tag: str, body: str) -> int:
    crc = 0xFFFF
    for byte in f"{tag}:{body}".encode("ascii"):
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def canonical_network_id_bytes(network_id: Any) -> bytes:
    match = CANONICAL_NETWORK_ID_RE.fullmatch(network_id if isinstance(network_id, str) else "")
    if match is None:
        raise ValueError("network_id must be canonical hash:<64 uppercase hex>#<4 uppercase hex>")
    body, checksum = match.groups()
    expected_checksum = f"{_iroha_literal_crc16('hash', body):04X}"
    if checksum != expected_checksum:
        raise ValueError(f"network_id checksum mismatch (expected {expected_checksum})")
    return bytes.fromhex(body)


def canonical_ed25519_account_header(public_key: str | None) -> str:
    # AccountAddress V1: header(version=0, single-key, norm=1), controller tag,
    # Ed25519 curve id, one-byte key length, then the raw controller key.
    return "0x02000120" + raw_ed25519_public_key_hex(public_key)


def _canonical_form_decode(raw: str) -> str:
    encoded = raw.encode("utf-8")
    decoded = bytearray()
    index = 0
    while index < len(encoded):
        byte = encoded[index]
        if byte == ord("+"):
            decoded.append(ord(" "))
            index += 1
            continue
        if byte == ord("%") and index + 2 < len(encoded):
            pair = encoded[index + 1 : index + 3]
            if all(
                ord("0") <= nibble <= ord("9")
                or ord("a") <= nibble <= ord("f")
                or ord("A") <= nibble <= ord("F")
                for nibble in pair
            ):
                decoded.append(int(pair.decode("ascii"), 16))
                index += 3
                continue
        decoded.append(byte)
        index += 1
    return decoded.decode("utf-8", errors="replace")


def _canonical_form_encode(value: str) -> str:
    output: list[str] = []
    for byte in value.encode("utf-8"):
        if (
            ord("A") <= byte <= ord("Z")
            or ord("a") <= byte <= ord("z")
            or ord("0") <= byte <= ord("9")
            or byte in b"*-._"
        ):
            output.append(chr(byte))
        elif byte == ord(" "):
            output.append("+")
        else:
            output.append(f"%{byte:02X}")
    return "".join(output)


def canonical_request_query(raw_query: str) -> str:
    if len(raw_query.encode("utf-8")) > 64 * 1024:
        raise ValueError("canonical request query exceeds the V1 raw-byte limit")
    pairs: list[tuple[str, str]] = []
    for sequence in raw_query.split("&"):
        if not sequence:
            continue
        raw_key, separator, raw_value = sequence.partition("=")
        pairs.append(
            (
                _canonical_form_decode(raw_key),
                _canonical_form_decode(raw_value if separator else ""),
            )
        )
        if len(pairs) > 64:
            raise ValueError("canonical request query exceeds the V1 pair limit")
    pairs.sort()
    return "&".join(
        f"{_canonical_form_encode(key)}={_canonical_form_encode(value)}" for key, value in pairs
    )


def canonical_account_request_message(
    network_id: str,
    method: str,
    request_url: str,
    body: bytes,
    timestamp_ms: int,
    nonce: str,
) -> bytes:
    if (
        isinstance(timestamp_ms, bool)
        or not isinstance(timestamp_ms, int)
        or not 0 <= timestamp_ms <= 2**64 - 1
    ):
        raise ValueError("canonical request timestamp must fit u64")
    if (
        not nonce
        or len(nonce) > 256
        or not nonce.isascii()
        or any(ord(char) < 0x21 or ord(char) > 0x7E for char in nonce)
    ):
        raise ValueError("canonical request nonce must be 1-256 printable ASCII bytes")
    normalized_method = method.upper()
    if not normalized_method or len(normalized_method) > 32 or not normalized_method.isascii():
        raise ValueError("canonical request method is invalid")
    parsed = urllib.parse.urlsplit(request_url)
    if not parsed.path.startswith("/") or len(parsed.path.encode("utf-8")) > 64 * 1024:
        raise ValueError("canonical request path is invalid")
    query = canonical_request_query(parsed.query)
    body_digest = hashlib.sha256(body).hexdigest()
    target = (
        normalized_method.encode("ascii")
        + b"\n"
        + parsed.path.encode("ascii")
        + b"\n"
        + query.encode("ascii")
        + b"\n"
        + body_digest.encode("ascii")
        + b"\n"
        + str(timestamp_ms).encode("ascii")
        + b"\n"
        + nonce.encode("ascii")
    )
    return b"iroha.app.request.network.v1\0" + canonical_network_id_bytes(network_id) + target


def build_account_request_headers(
    *,
    network_id: str,
    private_key: str,
    public_key: str,
    method: str,
    request_url: str,
    body: bytes,
    timestamp_ms: int | None = None,
    nonce: str | None = None,
) -> dict[str, str]:
    if timestamp_ms is None:
        timestamp_ms = time.time_ns() // 1_000_000
    if nonce is None:
        nonce = secrets.token_urlsafe(12)
    message = canonical_account_request_message(
        network_id,
        method,
        request_url,
        body,
        timestamp_ms,
        nonce,
    )
    signature = sign_ed25519_message(
        private_key,
        public_key,
        message,
        context="canonical account request signing",
    )
    return {
        "X-Iroha-Account": canonical_ed25519_account_header(public_key),
        "X-Iroha-Signature": signature,
        "X-Iroha-Timestamp-Ms": str(timestamp_ms),
        "X-Iroha-Nonce": nonce,
    }
