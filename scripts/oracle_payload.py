#!/usr/bin/env python3
"""Build signed SoraSwap oracle payload blobs for smoke/bootstrap tooling."""

from __future__ import annotations

import argparse
import json
import os
import stat
import sys
from pathlib import Path

MAX_PRIVATE_KEY_FILE_BYTES = 4096


def _file_identity(metadata: os.stat_result) -> tuple[int, ...]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_uid,
        metadata.st_gid,
        stat.S_IFMT(metadata.st_mode),
        stat.S_IMODE(metadata.st_mode),
        metadata.st_nlink,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _open_regular_file_without_symlink_components(path: str) -> tuple[int, os.stat_result]:
    """Open an absolute canonical path without traversing symlink components."""

    candidate = Path(path).expanduser()
    if not candidate.is_absolute():
        raise SystemExit("private key file path must be absolute and canonical")
    absolute = Path(os.path.abspath(candidate))
    if Path(os.path.realpath(absolute)) != absolute:
        raise SystemExit("private key file path must be absolute and canonical")

    components = absolute.parts[1:]
    if not components or any(component in {"", ".", ".."} for component in components):
        raise SystemExit("private key file path is invalid")

    nofollow = getattr(os, "O_NOFOLLOW", 0)
    cloexec = getattr(os, "O_CLOEXEC", 0)
    directory_flags = os.O_RDONLY | cloexec | nofollow | getattr(os, "O_DIRECTORY", 0)
    read_flags = os.O_RDONLY | cloexec | nofollow
    directory_fd = -1
    descriptor = -1
    try:
        directory_fd = os.open(os.path.sep, directory_flags)
        for component in components[:-1]:
            next_fd = os.open(component, directory_flags, dir_fd=directory_fd)
            os.close(directory_fd)
            directory_fd = next_fd
        before = os.stat(components[-1], dir_fd=directory_fd, follow_symlinks=False)
        descriptor = os.open(components[-1], read_flags, dir_fd=directory_fd)
    except OSError as exc:
        if descriptor >= 0:
            os.close(descriptor)
        raise SystemExit("private key file could not be opened securely") from exc
    finally:
        if directory_fd >= 0:
            os.close(directory_fd)

    if stat.S_ISLNK(before.st_mode) or not stat.S_ISREG(before.st_mode):
        os.close(descriptor)
        raise SystemExit("private key file must be a non-symlink regular file")
    opened = os.fstat(descriptor)
    if not stat.S_ISREG(opened.st_mode) or _file_identity(before) != _file_identity(opened):
        os.close(descriptor)
        raise SystemExit("private key file changed while it was opened")
    return descriptor, opened


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


def read_private_key_file(path: str) -> str:
    descriptor, opened = _open_regular_file_without_symlink_components(path)
    if (
        stat.S_IMODE(opened.st_mode) != 0o600
        or opened.st_nlink != 1
        or opened.st_uid != os.geteuid()
    ):
        os.close(descriptor)
        raise SystemExit(
            "private key file must have mode 0600, exactly one hard link, and be owned by the effective user"
        )
    try:
        chunks: list[bytes] = []
        total = 0
        while True:
            chunk = os.read(descriptor, 4096)
            if not chunk:
                break
            total += len(chunk)
            if total > MAX_PRIVATE_KEY_FILE_BYTES:
                raise SystemExit(
                    f"private key file exceeds {MAX_PRIVATE_KEY_FILE_BYTES} bytes"
                )
            chunks.append(chunk)
        after = os.fstat(descriptor)
        if _file_identity(opened) != _file_identity(after):
            raise SystemExit("private key file changed while it was read")
    finally:
        os.close(descriptor)
    try:
        text = b"".join(chunks).decode("utf-8")
    except UnicodeDecodeError as exc:
        raise SystemExit("private key file must contain UTF-8 text") from exc
    lines = text.splitlines()
    if len(lines) != 1 or not lines[0] or lines[0].strip() != lines[0]:
        raise SystemExit("private key file must contain exactly one non-empty token line")
    return lines[0]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--payload-json", help="Raw JSON payload to compact and sign")
    parser.add_argument("--payload-file", help="File containing raw JSON payload to compact and sign")
    parser.add_argument("--private-key-file")
    parser.add_argument("--normalize-public-key-hex", help="Normalize a raw or Iroha-prefixed public key and exit")
    args = parser.parse_args()

    if args.normalize_public_key_hex:
        print("0x" + normalize_public_key(args.normalize_public_key_hex).hex())
        return 0

    if args.payload_json is None and args.payload_file is None:
        parser.error("--payload-json or --payload-file is required")
    if not args.private_key_file:
        raise SystemExit("--private-key-file is required to sign oracle payloads")
    private_key_hex = read_private_key_file(args.private_key_file)

    if args.payload_file:
        with open(args.payload_file, "r", encoding="utf-8") as handle:
            raw_json = handle.read()
    else:
        raw_json = args.payload_json

    payload = compact_payload(raw_json)
    signature, public_key = sign_payload(payload, private_key_hex)
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
