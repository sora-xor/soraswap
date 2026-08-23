#!/usr/bin/env python3
"""No-clobber, fsync-backed publication for validation-fee JSON journals."""

from __future__ import annotations

import argparse
import json
import os
import stat
import sys
import tempfile
from pathlib import Path
from typing import Any


class PublicationError(RuntimeError):
    """Refuse unsafe or non-durable journal publication."""


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


def strict_json(raw: bytes, label: str) -> Any:
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise PublicationError(f"{label} is not UTF-8") from error

    def object_without_duplicates(
        pairs: list[tuple[str, Any]],
    ) -> dict[str, Any]:
        value: dict[str, Any] = {}
        for key, item in pairs:
            if key in value:
                raise PublicationError(
                    f"{label} contains duplicate object key {key!r}"
                )
            value[key] = item
        return value

    def reject_nonfinite(value: str) -> Any:
        raise PublicationError(f"{label} contains non-finite number {value}")

    try:
        return json.loads(
            text,
            object_pairs_hook=object_without_duplicates,
            parse_constant=reject_nonfinite,
        )
    except json.JSONDecodeError as error:
        raise PublicationError(f"{label} is not valid JSON") from error


def fsync_directory(path: Path) -> None:
    flags = os.O_RDONLY
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    fd = os.open(path, flags)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def verify_existing(output: Path, expected: bytes) -> None:
    if output.is_symlink() or not output.is_file():
        raise PublicationError(
            f"immutable validation-fee evidence is not a regular file: {output}"
        )
    if output.resolve(strict=True) != output:
        raise PublicationError(
            f"immutable validation-fee evidence path is not canonical: {output}"
        )
    mode = stat.S_IMODE(output.stat().st_mode)
    if mode != 0o444:
        raise PublicationError(
            f"immutable validation-fee evidence is not mode 0444: {output}"
        )
    raw = output.read_bytes()
    value = strict_json(raw, str(output))
    if raw != canonical_bytes(value) or raw != expected:
        raise PublicationError(
            f"refusing to replace different immutable validation-fee evidence: {output}"
        )


def ensure_directory(directory: Path) -> None:
    if not directory.is_absolute():
        raise PublicationError("durable directory path must be absolute")
    if directory.resolve(strict=False) != directory:
        raise PublicationError("durable directory path must be canonical and symlink-free")
    missing: list[Path] = []
    cursor = directory
    while not cursor.exists():
        missing.append(cursor)
        cursor = cursor.parent
    if not cursor.is_dir() or cursor.is_symlink() or cursor.resolve(strict=True) != cursor:
        raise PublicationError("durable directory anchor must be a canonical directory")
    for path in reversed(missing):
        os.mkdir(path, 0o700)
        os.chmod(path, 0o700)
        fsync_directory(path)
        fsync_directory(path.parent)
    if directory.is_symlink() or not directory.is_dir():
        raise PublicationError("durable directory target is not a real directory")
    os.chmod(directory, 0o700)
    fsync_directory(directory)
    fsync_directory(directory.parent)


def fsync_file(path: Path) -> None:
    if not path.is_absolute() or path.resolve(strict=True) != path:
        raise PublicationError("durable file path must be canonical")
    if path.is_symlink() or not path.is_file():
        raise PublicationError("durable file target must be a regular file")
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)
    fsync_directory(path.parent)


def publish(raw: bytes, output: Path) -> None:
    if not output.is_absolute():
        raise PublicationError("immutable evidence output path must be absolute")
    parent = output.parent
    if not parent.is_dir() or parent.is_symlink():
        raise PublicationError("immutable evidence parent must be a real directory")
    if parent.resolve(strict=True) != parent:
        raise PublicationError("immutable evidence parent path must be canonical")

    value = strict_json(raw, "immutable evidence input")
    expected = canonical_bytes(value)
    if raw != expected:
        raise PublicationError("immutable evidence input is not canonical JSON")

    if os.path.lexists(output):
        verify_existing(output, expected)
        return

    fd = -1
    staging_name = ""
    published = False
    try:
        fd, staging_name = tempfile.mkstemp(
            prefix=f".{output.name}.immutable.",
            dir=parent,
        )
        with os.fdopen(fd, "wb", closefd=False) as stream:
            stream.write(expected)
            stream.flush()
            os.fsync(fd)
        os.fchmod(fd, 0o444)
        os.fsync(fd)
        os.close(fd)
        fd = -1
        try:
            os.link(staging_name, output)
            published = True
        except FileExistsError:
            verify_existing(output, expected)
            return
        fsync_directory(parent)
        fsync_directory(parent.parent)
        os.unlink(staging_name)
        staging_name = ""
        fsync_directory(parent)
    finally:
        if fd >= 0:
            os.close(fd)
        if staging_name and os.path.lexists(staging_name):
            try:
                if not published:
                    os.chmod(staging_name, 0o600)
                os.unlink(staging_name)
                fsync_directory(parent)
            except OSError:
                raise


def main() -> int:
    parser = argparse.ArgumentParser()
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--output", type=Path)
    target.add_argument("--directory", type=Path)
    target.add_argument("--fsync-file", type=Path)
    target.add_argument("--fsync-directory", type=Path)
    args = parser.parse_args()
    try:
        if args.directory is not None:
            if sys.stdin.buffer.read():
                raise PublicationError("durable directory mode does not accept stdin")
            ensure_directory(args.directory)
            print(args.directory)
            return 0
        if args.fsync_file is not None:
            if sys.stdin.buffer.read():
                raise PublicationError("fsync-file mode does not accept stdin")
            fsync_file(args.fsync_file)
            print(args.fsync_file)
            return 0
        if args.fsync_directory is not None:
            if sys.stdin.buffer.read():
                raise PublicationError("fsync-directory mode does not accept stdin")
            directory = args.fsync_directory
            if (
                not directory.is_absolute()
                or directory.resolve(strict=True) != directory
                or directory.is_symlink()
                or not directory.is_dir()
            ):
                raise PublicationError("fsync directory target must be canonical")
            fsync_directory(directory)
            print(directory)
            return 0
        assert args.output is not None
        publish(sys.stdin.buffer.read(), args.output)
        print(args.output)
        return 0
    except (OSError, PublicationError) as error:
        print(f"immutable validation-fee publication refused: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
