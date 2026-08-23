#!/usr/bin/env python3
"""Securely inspect and materialize Iroha client configuration.

This helper deliberately owns the complete read/parse/render generation.  Secret
configuration is never passed in argv, and generated files carry their original
device/inode identity in the filename so cleanup can refuse replacements.
"""

from __future__ import annotations

import argparse
import base64
import ctypes
import errno
import json
import os
import re
import stat
import sys
import tempfile
import tomllib
import urllib.parse
from pathlib import Path
from typing import Any, BinaryIO


MAX_CONFIG_BYTES = 1_048_576
MAX_SECRET_BYTES = 1_048_576
MAX_DIAGNOSTIC_BYTES = 10_485_760
OWNED_SUFFIX_RE = re.compile(r"\.d([0-9]+)\.i([0-9]+)$")


class ConfigError(RuntimeError):
    """A client configuration failed a security or schema invariant."""


def identity(metadata: os.stat_result) -> tuple[int, ...]:
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


def _open_regular_nofollow(path: str, *, repo_root: str | None) -> tuple[int, os.stat_result]:
    nofollow = getattr(os, "O_NOFOLLOW", 0)
    cloexec = getattr(os, "O_CLOEXEC", 0)
    # Opening a FIFO for reading can block before we get a chance to reject its
    # file type.  O_NONBLOCK is harmless for regular files and makes both a
    # direct FIFO and a regular-to-FIFO replacement fail closed.
    read_flags = os.O_RDONLY | cloexec | nofollow | getattr(os, "O_NONBLOCK", 0)
    dir_flags = os.O_RDONLY | cloexec | nofollow | getattr(os, "O_DIRECTORY", 0)

    try:
        if repo_root is not None:
            root_input = os.path.abspath(repo_root)
            root = os.path.realpath(root_input)
            absolute = os.path.abspath(path)
            try:
                if os.path.commonpath([root_input, absolute]) == root_input:
                    relative = os.path.relpath(absolute, root_input)
                    contained = True
                elif os.path.commonpath([root, absolute]) == root:
                    relative = os.path.relpath(absolute, root)
                    contained = True
                else:
                    relative = ""
                    contained = False
            except ValueError:
                contained = False
            if not contained:
                raise ConfigError("production client config must be contained by the real repository root")
            components = relative.split(os.sep)
            if not components or any(component in {"", ".", ".."} for component in components):
                raise ConfigError("production client config path is invalid")
            directory_fd = os.open(root, dir_flags)
            try:
                for component in components[:-1]:
                    next_fd = os.open(component, dir_flags, dir_fd=directory_fd)
                    os.close(directory_fd)
                    directory_fd = next_fd
                before = os.stat(components[-1], dir_fd=directory_fd, follow_symlinks=False)
                fd = os.open(components[-1], read_flags, dir_fd=directory_fd)
            finally:
                os.close(directory_fd)
        else:
            before = os.lstat(path)
            fd = os.open(path, read_flags)
    except ConfigError:
        raise
    except OSError as exc:
        raise ConfigError("client config could not be opened securely") from exc

    if stat.S_ISLNK(before.st_mode) or not stat.S_ISREG(before.st_mode):
        os.close(fd)
        raise ConfigError("client config must be a non-symlink regular file")
    opened = os.fstat(fd)
    if not stat.S_ISREG(opened.st_mode) or identity(before) != identity(opened):
        os.close(fd)
        raise ConfigError("client config changed while it was being opened")
    return fd, opened


def _read_complete(fd: int, *, maximum: int) -> bytes:
    chunks: list[bytes] = []
    remaining = maximum + 1
    while remaining > 0:
        chunk = os.read(fd, min(65_536, remaining))
        if not chunk:
            break
        chunks.append(chunk)
        remaining -= len(chunk)
    content = b"".join(chunks)
    if len(content) > maximum:
        raise ConfigError(f"client config exceeds {maximum} bytes")
    return content


def _nonempty_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise ConfigError(f"{label} must be a non-empty string")
    if any(ord(char) < 0x20 or ord(char) == 0x7F for char in value):
        raise ConfigError(f"{label} must not contain control characters")
    return value


def _canonical_origin(parsed: urllib.parse.SplitResult) -> str:
    assert parsed.hostname is not None
    host = parsed.hostname.lower().rstrip(".")
    host_literal = f"[{host}]" if ":" in host else host
    default_port = 443 if parsed.scheme.lower() == "https" else 80
    origin = f"{parsed.scheme.lower()}://{host_literal}"
    if parsed.port is not None and parsed.port != default_port:
        origin += f":{parsed.port}"
    return origin


def _parse_http_url(value: Any, label: str) -> tuple[str, urllib.parse.SplitResult, str]:
    url = _nonempty_string(value, label)
    if any(char.isspace() for char in url) or "\\" in url:
        raise ConfigError(f"{label} is invalid")
    try:
        parsed = urllib.parse.urlsplit(url)
        _ = parsed.port
    except ValueError as exc:
        raise ConfigError(f"{label} is invalid") from exc
    if parsed.scheme.lower() not in {"http", "https"} or not parsed.hostname:
        raise ConfigError(f"{label} must be an absolute HTTP(S) URL")
    if parsed.username is not None or parsed.password is not None:
        raise ConfigError(f"{label} must not contain userinfo")
    if parsed.query or parsed.fragment:
        raise ConfigError(f"{label} must not contain a query or fragment")
    return url, parsed, _canonical_origin(parsed)


def _canonical_decimal_override(raw: str, label: str) -> int:
    if not re.fullmatch(r"0|[1-9][0-9]*", raw):
        raise ConfigError(f"{label} must be canonical unsigned decimal")
    value = int(raw)
    if value > 65_535:
        raise ConfigError(f"{label} must fit u16")
    return value


def _validate_auth(data: dict[str, Any], *, scheme: str) -> dict[str, str] | None:
    auth = data.get("basic_auth")
    if auth is None:
        return None
    if not isinstance(auth, dict):
        raise ConfigError("client config basic_auth must be a table")
    if set(auth) != {"web_login", "password"}:
        raise ConfigError("client config basic_auth requires only web_login and password")
    login = _nonempty_string(auth.get("web_login"), "client config basic_auth.web_login")
    password = _nonempty_string(auth.get("password"), "client config basic_auth.password")
    if ":" in login:
        raise ConfigError("client config basic_auth.web_login must not contain ':'")
    if scheme != "https":
        raise ConfigError("client config basic_auth requires an HTTPS Torii URL")
    return {"web_login": login, "password": password}


def _validate_production_identity(
    *,
    chain: str,
    parsed: urllib.parse.SplitResult,
    account: dict[str, Any],
    discriminant: int,
    taira_chain_id: str,
    taira_discriminant: int,
) -> None:
    host = (parsed.hostname or "").lower().rstrip(".")
    profile = str(account.get("profile") or "").strip().lower()
    if chain == taira_chain_id:
        raise ConfigError("production client config must not select the canonical Taira chain")
    if host == "taira.sora.org" or host.endswith(".taira.sora.org"):
        raise ConfigError("production client config must not use a Taira Torii origin")
    if profile == "taira":
        raise ConfigError("production client config must not use the Taira account profile")
    if discriminant == taira_discriminant:
        raise ConfigError("production client config must not use the Taira chain discriminant")


def load_config(
    path: str,
    *,
    production: bool,
    repo_root: str,
    taira_chain_id: str,
    taira_discriminant: int,
) -> tuple[dict[str, Any], os.stat_result, dict[str, Any]]:
    fd, opened = _open_regular_nofollow(path, repo_root=repo_root if production else None)
    try:
        if production and (
            stat.S_IMODE(opened.st_mode) != 0o600
            or opened.st_nlink != 1
            or opened.st_uid != os.geteuid()
        ):
            raise ConfigError(
                "production client config must have mode 0600, exactly one hard link, and be owned by the effective user"
            )
        raw = _read_complete(fd, maximum=MAX_CONFIG_BYTES)
        after = os.fstat(fd)
        if identity(opened) != identity(after):
            raise ConfigError("client config changed while it was being read")
    finally:
        os.close(fd)
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ConfigError("client config must be UTF-8") from exc
    try:
        data = tomllib.loads(text)
    except tomllib.TOMLDecodeError as exc:
        raise ConfigError("client config is not valid TOML") from exc
    if not isinstance(data, dict):
        raise ConfigError("client config root must be a TOML table")

    torii_url, parsed, origin = _parse_http_url(data.get("torii_url"), "client config torii_url")
    auth = _validate_auth(data, scheme=parsed.scheme.lower())
    chain = _nonempty_string(data.get("chain"), "client config chain")
    account = data.get("account")
    if not isinstance(account, dict):
        if production:
            raise ConfigError("client config account must be a table")
        account = data
    discriminant = account.get("chain_discriminant")
    if discriminant is not None and (
        isinstance(discriminant, bool)
        or not isinstance(discriminant, int)
        or discriminant < 0
        or discriminant > 65_535
    ):
        raise ConfigError("account.chain_discriminant must be a TOML u16 integer")
    if production:
        if parsed.scheme.lower() != "https":
            raise ConfigError("production client config torii_url must use https")
        if parsed.path not in {"", "/"}:
            raise ConfigError("production client config torii_url must be a Torii root URL")
        if discriminant is None:
            raise ConfigError("production account.chain_discriminant is required")
        for key in ("domain", "public_key", "private_key"):
            _nonempty_string(account.get(key), f"production client config account.{key}")
        _validate_production_identity(
            chain=chain,
            parsed=parsed,
            account=account,
            discriminant=discriminant,
            taira_chain_id=taira_chain_id,
            taira_discriminant=taira_discriminant,
        )

    metadata = {
        "torii_url": torii_url,
        "torii_origin": origin,
        "chain": chain,
        "chain_discriminant": discriminant,
        "account_domain": account.get("domain"),
        "account_public_key": account.get("public_key"),
        "account_profile": account.get("profile"),
        "basic_auth_configured": auth is not None,
        "mode": stat.S_IMODE(opened.st_mode),
        "nlink": opened.st_nlink,
        "identity": {
            "device": after.st_dev,
            "inode": after.st_ino,
            "type": stat.S_IFMT(after.st_mode),
            "mode": stat.S_IMODE(after.st_mode),
            "nlink": after.st_nlink,
            "size": after.st_size,
            "mtime_ns": after.st_mtime_ns,
            "ctime_ns": after.st_ctime_ns,
        },
    }
    return data, opened, metadata


def _toml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def _render_config(
    data: dict[str, Any],
    metadata: dict[str, Any],
    *,
    public_env: str,
    taira_chain_id: str,
    taira_discriminant: int,
    public_key_override: str | None,
    private_key_override: str | None,
) -> bytes:
    nested_account = data.get("account")
    account = nested_account if isinstance(nested_account, dict) else data
    chain = metadata["chain"]
    torii_url = metadata["torii_url"]
    configured_origin = metadata["torii_origin"]
    auth = data.get("basic_auth")

    torii_override = os.environ.get("SORASWAP_TORII_URL", "")
    if torii_override:
        torii_url, override_parts, override_origin = _parse_http_url(torii_override, "Torii override")
        if auth is not None and override_origin != configured_origin:
            raise ConfigError("authenticated Torii override must use the configured origin")
        if public_env == "production":
            if override_parts.scheme.lower() != "https" or override_parts.path not in {"", "/"}:
                raise ConfigError("production Torii override must be an HTTPS root")
            if override_origin != configured_origin:
                raise ConfigError("production Torii override must use the configured origin")

    configured_discriminant = metadata["chain_discriminant"]
    if public_env == "testnet":
        chain = os.environ.get("SORASWAP_TESTNET_CHAIN_ID") or chain
        raw_discriminant = os.environ.get("SORASWAP_TESTNET_CHAIN_DISCRIMINANT", "")
        if raw_discriminant:
            discriminant = _canonical_decimal_override(raw_discriminant, "SORASWAP_TESTNET_CHAIN_DISCRIMINANT")
        elif configured_discriminant is not None:
            discriminant = configured_discriminant
        else:
            discriminant = taira_discriminant
    elif public_env == "production":
        chain = os.environ.get("SORASWAP_PRODUCTION_CHAIN_ID") or chain
        raw_discriminant = os.environ.get("SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT", "")
        discriminant = (
            _canonical_decimal_override(raw_discriminant, "SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT")
            if raw_discriminant
            else configured_discriminant
        )
        if chain == taira_chain_id:
            raise ConfigError("production chain override must not select canonical Taira")
        if discriminant == taira_discriminant:
            raise ConfigError("production chain override must not use the Taira discriminant")
    else:
        chain = os.environ.get("CHAIN") or chain
        raw_discriminant = (
            os.environ.get("SORASWAP_ADDRESS_NETWORK_PREFIX")
            or os.environ.get("SORASWAP_CHAIN_DISCRIMINANT")
            or "753"
        )
        discriminant = _canonical_decimal_override(raw_discriminant, "local account chain discriminant")

    if not isinstance(discriminant, int) or isinstance(discriminant, bool) or not 0 <= discriminant <= 65_535:
        raise ConfigError("account chain discriminant must fit u16")
    chain = _nonempty_string(chain, "rendered client config chain")
    domain = _nonempty_string(account.get("domain"), "client config account.domain")
    if "." not in domain:
        domain += ".universal"
    public_key = public_key_override or account.get("public_key")
    private_key = private_key_override or account.get("private_key")
    public_key = _nonempty_string(public_key, "client config account.public_key")
    private_key = _nonempty_string(private_key, "client config account.private_key")

    transaction = data.get("transaction") or {}
    if not isinstance(transaction, dict):
        raise ConfigError("client config transaction must be a table")
    ttl_ms = transaction.get("time_to_live_ms", 120_000)
    status_timeout_ms = transaction.get("status_timeout_ms", 120_000)
    nonce = transaction.get("nonce", False)
    request_timeout_ms = data.get("torii_request_timeout_ms")
    raw_request_timeout_override = os.environ.get(
        "SORASWAP_MATERIALIZE_TORII_REQUEST_TIMEOUT_MS", ""
    )
    if raw_request_timeout_override:
        if not re.fullmatch(r"0|[1-9][0-9]*", raw_request_timeout_override):
            raise ConfigError(
                "SORASWAP_MATERIALIZE_TORII_REQUEST_TIMEOUT_MS must be canonical unsigned decimal"
            )
        request_timeout_ms = int(raw_request_timeout_override)
    for label, value in (("time_to_live_ms", ttl_ms), ("status_timeout_ms", status_timeout_ms)):
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            raise ConfigError(f"transaction.{label} must be a non-negative TOML integer")
    if not isinstance(nonce, bool):
        raise ConfigError("transaction.nonce must be a TOML boolean")
    if request_timeout_ms is not None and (
        isinstance(request_timeout_ms, bool)
        or not isinstance(request_timeout_ms, int)
        or request_timeout_ms < 0
    ):
        raise ConfigError("torii_request_timeout_ms must be a non-negative TOML integer")

    lines = [f"chain = {_toml_string(chain)}", f"torii_url = {_toml_string(torii_url)}"]
    if request_timeout_ms is not None:
        lines.append(f"torii_request_timeout_ms = {request_timeout_ms}")
    lines += [
        "",
        "[account]",
        f"domain = {_toml_string(domain)}",
        f"public_key = {_toml_string(public_key)}",
        f"private_key = {_toml_string(private_key)}",
        f"chain_discriminant = {discriminant}",
        "",
        "[transaction]",
        f"time_to_live_ms = {ttl_ms}",
        f"status_timeout_ms = {status_timeout_ms}",
        "nonce = " + ("true" if nonce else "false"),
    ]
    if auth is not None:
        lines += [
            "",
            "[basic_auth]",
            f"web_login = {_toml_string(auth['web_login'])}",
            f"password = {_toml_string(auth['password'])}",
        ]
    return ("\n".join(lines) + "\n").encode("utf-8")


def _owned_path_for(path: str, metadata: os.stat_result) -> str:
    return f"{path}.d{metadata.st_dev}.i{metadata.st_ino}"


def _rename_directory_noreplace(source: str, destination: str) -> None:
    """Atomically rename a private directory without replacing another path."""

    libc = ctypes.CDLL(None, use_errno=True)
    source_raw = os.fsencode(source)
    destination_raw = os.fsencode(destination)
    if sys.platform == "darwin":
        try:
            renamex_np = libc.renamex_np
        except AttributeError as exc:
            raise ConfigError("atomic no-replace directory rename is unavailable") from exc
        renamex_np.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
        renamex_np.restype = ctypes.c_int
        result = renamex_np(source_raw, destination_raw, 0x00000004)  # RENAME_EXCL
    elif sys.platform.startswith("linux"):
        try:
            renameat2 = libc.renameat2
        except AttributeError as exc:
            raise ConfigError("atomic no-replace directory rename is unavailable") from exc
        renameat2.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        renameat2.restype = ctypes.c_int
        result = renameat2(-100, source_raw, -100, destination_raw, 1)  # AT_FDCWD, RENAME_NOREPLACE
    else:
        raise ConfigError("atomic no-replace directory rename is unsupported on this platform")
    if result != 0:
        error_number = ctypes.get_errno()
        if error_number in {errno.EEXIST, errno.ENOTEMPTY}:
            raise ConfigError("generated secret directory destination already exists")
        raise ConfigError("generated secret directory could not be renamed atomically")


def create_owned_file(content: bytes, *, family: str, directory: str | None = None) -> str:
    safe_family = re.sub(r"[^A-Za-z0-9_.-]", "-", family) or "secret"
    target_dir = os.path.realpath(
        os.path.abspath(directory or os.environ.get("TMPDIR") or tempfile.gettempdir())
    )
    fd = -1
    initial_path = ""
    owned_path = ""
    try:
        fd, initial_path = tempfile.mkstemp(prefix=f"soraswap-{safe_family}.", dir=target_dir)
        os.fchmod(fd, 0o600)
        opened = os.fstat(fd)
        if not stat.S_ISREG(opened.st_mode) or opened.st_nlink != 1:
            raise ConfigError("generated secret file is not a single-link regular file")
        owned_path = _owned_path_for(initial_path, opened)
        # Link-then-unlink provides no-replace semantics. A plain rename could
        # silently replace a path raced into existence after the inode suffix
        # was chosen.
        os.link(initial_path, owned_path, follow_symlinks=False)
        os.unlink(initial_path)
        initial_path = ""
        view = memoryview(content)
        while view:
            written = os.write(fd, view)
            if written <= 0:
                raise ConfigError("could not write generated secret file")
            view = view[written:]
        os.fsync(fd)
        final = os.fstat(fd)
        if (
            final.st_dev != opened.st_dev
            or final.st_ino != opened.st_ino
            or not stat.S_ISREG(final.st_mode)
            or stat.S_IMODE(final.st_mode) != 0o600
            or final.st_nlink != 1
            or final.st_uid != os.geteuid()
        ):
            raise ConfigError("generated secret file identity changed")
        path_stat = os.lstat(owned_path)
        if identity(final) != identity(path_stat):
            raise ConfigError("generated secret path no longer names its opened file")
        return owned_path
    except (OSError, ConfigError):
        # Cleanup is identity-bound too.  Never unlink a path merely because
        # it has the random name we selected: it may have been replaced after
        # publication.  Removing the initial link first also reduces a
        # successfully published inode back to one link before the standard
        # owned-file verifier handles it.
        if initial_path and fd >= 0:
            try:
                current = os.lstat(initial_path)
                opened_now = os.fstat(fd)
                if (current.st_dev, current.st_ino) == (opened_now.st_dev, opened_now.st_ino):
                    os.unlink(initial_path)
            except OSError:
                pass
        if owned_path:
            try:
                unlink_owned_file(owned_path)
            except (OSError, ConfigError):
                pass
        raise
    finally:
        if fd >= 0:
            os.close(fd)


def unlink_owned_file(path: str) -> None:
    match = OWNED_SUFFIX_RE.search(path)
    if not match:
        raise ConfigError("refusing to unlink a file without an owned identity suffix")
    expected = (int(match.group(1)), int(match.group(2)))
    nofollow = getattr(os, "O_NOFOLLOW", 0)
    try:
        before = os.lstat(path)
        fd = os.open(
            path,
            os.O_RDONLY
            | nofollow
            | getattr(os, "O_CLOEXEC", 0)
            | getattr(os, "O_NONBLOCK", 0),
        )
    except FileNotFoundError:
        return
    except OSError as exc:
        raise ConfigError("owned file could not be opened for cleanup") from exc
    try:
        opened = os.fstat(fd)
        if (
            (opened.st_dev, opened.st_ino) != expected
            or not stat.S_ISREG(opened.st_mode)
            or stat.S_IMODE(opened.st_mode) != 0o600
            or opened.st_nlink != 1
            or identity(before) != identity(opened)
        ):
            raise ConfigError("refusing to unlink a replaced or multiply-linked owned file")
        after = os.lstat(path)
        if identity(opened) != identity(after):
            raise ConfigError("refusing to unlink an owned file whose path identity changed")
        os.unlink(path)
    finally:
        os.close(fd)


def create_owned_directory(*, family: str) -> str:
    safe_family = re.sub(r"[^A-Za-z0-9_.-]", "-", family) or "secrets"
    target_dir = os.path.realpath(
        os.path.abspath(os.environ.get("TMPDIR") or tempfile.gettempdir())
    )
    initial_path = tempfile.mkdtemp(prefix=f"soraswap-{safe_family}.", dir=target_dir)
    owned_path = ""
    opened: os.stat_result | None = None
    try:
        os.chmod(initial_path, 0o700)
        opened = os.lstat(initial_path)
        if (
            not stat.S_ISDIR(opened.st_mode)
            or stat.S_IMODE(opened.st_mode) != 0o700
            or opened.st_uid != os.geteuid()
        ):
            raise ConfigError("generated secret directory is not private")
        owned_path = _owned_path_for(initial_path, opened)
        _rename_directory_noreplace(initial_path, owned_path)
        initial_path = ""
        final = os.lstat(owned_path)
        if (
            final.st_dev != opened.st_dev
            or final.st_ino != opened.st_ino
            or not stat.S_ISDIR(final.st_mode)
            or stat.S_IMODE(final.st_mode) != 0o700
            or final.st_uid != os.geteuid()
        ):
            raise ConfigError("generated secret directory identity changed")
        return owned_path
    except (OSError, ConfigError):
        if initial_path and opened is not None:
            try:
                current = os.lstat(initial_path)
                if (current.st_dev, current.st_ino) == (opened.st_dev, opened.st_ino):
                    os.rmdir(initial_path)
            except OSError:
                pass
        if owned_path:
            try:
                cleanup_owned_directory(owned_path)
            except (OSError, ConfigError):
                pass
        raise


def cleanup_owned_directory(path: str) -> None:
    match = OWNED_SUFFIX_RE.search(path)
    if not match:
        raise ConfigError("refusing to clean a directory without an owned identity suffix")
    expected = (int(match.group(1)), int(match.group(2)))
    nofollow = getattr(os, "O_NOFOLLOW", 0)
    dir_flags = os.O_RDONLY | nofollow | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_DIRECTORY", 0)
    try:
        before = os.lstat(path)
        directory_fd = os.open(path, dir_flags)
    except FileNotFoundError:
        return
    except OSError as exc:
        raise ConfigError("owned secret directory could not be opened for cleanup") from exc
    try:
        opened = os.fstat(directory_fd)
        if (
            (opened.st_dev, opened.st_ino) != expected
            or not stat.S_ISDIR(opened.st_mode)
            or stat.S_IMODE(opened.st_mode) != 0o700
            or identity(before) != identity(opened)
        ):
            raise ConfigError("refusing to clean a replaced owned secret directory")
        entries = os.listdir(directory_fd)
        validated: list[str] = []
        for entry in entries:
            entry_match = OWNED_SUFFIX_RE.search(entry)
            if not entry_match:
                raise ConfigError("owned secret directory contains an unowned entry")
            entry_expected = (int(entry_match.group(1)), int(entry_match.group(2)))
            entry_before = os.stat(entry, dir_fd=directory_fd, follow_symlinks=False)
            entry_fd = os.open(
                entry,
                os.O_RDONLY
                | nofollow
                | getattr(os, "O_CLOEXEC", 0)
                | getattr(os, "O_NONBLOCK", 0),
                dir_fd=directory_fd,
            )
            try:
                entry_opened = os.fstat(entry_fd)
                if (
                    (entry_opened.st_dev, entry_opened.st_ino) != entry_expected
                    or not stat.S_ISREG(entry_opened.st_mode)
                    or stat.S_IMODE(entry_opened.st_mode) != 0o600
                    or entry_opened.st_nlink != 1
                    or identity(entry_before) != identity(entry_opened)
                ):
                    raise ConfigError("owned secret directory contains a replaced entry")
            finally:
                os.close(entry_fd)
            validated.append(entry)
        for entry in validated:
            current = os.stat(entry, dir_fd=directory_fd, follow_symlinks=False)
            entry_match = OWNED_SUFFIX_RE.search(entry)
            assert entry_match is not None
            if (current.st_dev, current.st_ino) != (
                int(entry_match.group(1)),
                int(entry_match.group(2)),
            ) or (
                not stat.S_ISREG(current.st_mode)
                or stat.S_IMODE(current.st_mode) != 0o600
                or current.st_nlink != 1
                or current.st_uid != os.geteuid()
            ):
                raise ConfigError("owned secret entry changed before cleanup")
            os.unlink(entry, dir_fd=directory_fd)
        after = os.lstat(path)
        if (
            (
                opened.st_dev,
                opened.st_ino,
                opened.st_uid,
                opened.st_gid,
                stat.S_IFMT(opened.st_mode),
                stat.S_IMODE(opened.st_mode),
            )
            != (
                after.st_dev,
                after.st_ino,
                after.st_uid,
                after.st_gid,
                stat.S_IFMT(after.st_mode),
                stat.S_IMODE(after.st_mode),
            )
        ):
            raise ConfigError("owned secret directory changed before removal")
    finally:
        os.close(directory_fd)
    os.rmdir(path)


def parse_secret_overrides() -> tuple[str | None, str | None]:
    raw = sys.stdin.buffer.read(MAX_SECRET_BYTES + 1)
    if len(raw) > MAX_SECRET_BYTES:
        raise ConfigError("secret override payload is too large")
    if not raw:
        return None, None
    try:
        value = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ConfigError("secret override payload is invalid JSON") from exc
    if not isinstance(value, dict) or set(value) - {"public_key", "private_key"}:
        raise ConfigError("secret override payload has unexpected fields")
    public_key = value.get("public_key")
    private_key = value.get("private_key")
    if public_key is not None:
        public_key = _nonempty_string(public_key, "public key override")
    if private_key is not None:
        private_key = _nonempty_string(private_key, "private key override")
    return public_key, private_key


def read_secret_token_file(path: str) -> str:
    fd, opened = _open_regular_nofollow(path, repo_root=None)
    try:
        if (
            stat.S_IMODE(opened.st_mode) != 0o600
            or opened.st_nlink != 1
            or opened.st_uid != os.geteuid()
        ):
            raise ConfigError(
                "secret file must have mode 0600, exactly one hard link, and be owned by the effective user"
            )
        raw = _read_complete(fd, maximum=65_536)
        after = os.fstat(fd)
        if identity(opened) != identity(after):
            raise ConfigError("secret file changed while it was being read")
    finally:
        os.close(fd)
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ConfigError("secret file must be UTF-8") from exc
    lines = text.splitlines()
    if len(lines) != 1 or not lines[0] or lines[0].strip() != lines[0]:
        raise ConfigError("secret file must contain exactly one non-empty token line")
    return lines[0]


def assert_output_has_no_credentials(
    raw: bytes,
    data: dict[str, Any],
    *,
    secret_files: list[str],
) -> None:
    tokens: set[str] = set()
    account = data.get("account")
    if not isinstance(account, dict):
        account = data
    private_key = account.get("private_key")
    if isinstance(private_key, str) and private_key:
        tokens.add(private_key)
    auth = data.get("basic_auth")
    if isinstance(auth, dict):
        login = auth.get("web_login")
        password = auth.get("password")
        if isinstance(login, str) and isinstance(password, str):
            joined = f"{login}:{password}"
            encoded = base64.b64encode(joined.encode("utf-8")).decode("ascii")
            tokens.update({password, joined, encoded, f"Basic {encoded}"})
    for path in secret_files:
        tokens.add(read_secret_token_file(path))

    expanded = set(tokens)
    for token in tokens:
        expanded.add(json.dumps(token, ensure_ascii=True)[1:-1])
        expanded.add(urllib.parse.quote(token, safe=""))
        expanded.add(base64.b64encode(token.encode("utf-8")).decode("ascii"))
    for token in expanded:
        if token and token.encode("utf-8") in raw:
            raise ConfigError("command output contained credential material and was suppressed")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--public-env", default="")
    parser.add_argument("--taira-chain-id", required=True)
    parser.add_argument("--taira-discriminant", type=int, required=True)
    subparsers = parser.add_subparsers(dest="command", required=True)

    inspect = subparsers.add_parser("inspect")
    inspect.add_argument("--config", required=True)
    inspect.add_argument("--production", action="store_true")
    inspect.add_argument("--format", choices=("metadata", "curl", "auth-toml"), default="metadata")

    materialize = subparsers.add_parser("materialize")
    materialize.add_argument("--config", required=True)
    materialize.add_argument("--production", action="store_true")
    materialize.add_argument("--family", default="cli-config")

    private_key = subparsers.add_parser("private-key-file")
    private_key.add_argument("--config", required=True)
    private_key.add_argument("--production", action="store_true")
    private_key.add_argument("--family", default="private-key")

    write_secret = subparsers.add_parser("write-secret")
    write_secret.add_argument("--family", default="secret")

    output_check = subparsers.add_parser("assert-output-clean")
    output_check.add_argument("--config", required=True)
    output_check.add_argument("--production", action="store_true")
    output_check.add_argument("--secret-file", action="append", default=[])

    unlink = subparsers.add_parser("unlink-owned")
    unlink.add_argument("--path", required=True)
    create_dir = subparsers.add_parser("create-owned-dir")
    create_dir.add_argument("--family", default="secrets")
    cleanup_dir = subparsers.add_parser("cleanup-owned-dir")
    cleanup_dir.add_argument("--path", required=True)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.command == "unlink-owned":
        unlink_owned_file(args.path)
        return 0
    if args.command == "create-owned-dir":
        print(create_owned_directory(family=args.family))
        return 0
    if args.command == "cleanup-owned-dir":
        cleanup_owned_directory(args.path)
        return 0
    if args.command == "write-secret":
        raw = sys.stdin.buffer.read(MAX_SECRET_BYTES + 1)
        if len(raw) > MAX_SECRET_BYTES:
            raise ConfigError("secret payload is too large")
        print(create_owned_file(raw, family=args.family))
        return 0

    data, _, metadata = load_config(
        args.config,
        production=args.production,
        repo_root=args.repo_root,
        taira_chain_id=args.taira_chain_id,
        taira_discriminant=args.taira_discriminant,
    )
    if args.command == "assert-output-clean":
        raw = sys.stdin.buffer.read(MAX_DIAGNOSTIC_BYTES + 1)
        if len(raw) > MAX_DIAGNOSTIC_BYTES:
            raise ConfigError(f"command output exceeds {MAX_DIAGNOSTIC_BYTES} bytes")
        assert_output_has_no_credentials(raw, data, secret_files=args.secret_file)
        return 0
    if args.command == "inspect":
        if args.format == "metadata":
            print(json.dumps(metadata, separators=(",", ":"), ensure_ascii=False))
        elif args.format == "auth-toml":
            auth = data.get("basic_auth")
            if auth is not None:
                print("[basic_auth]")
                print(f"web_login = {_toml_string(auth['web_login'])}")
                print(f"password = {_toml_string(auth['password'])}")
        else:
            print(metadata["torii_origin"])
            auth = data.get("basic_auth")
            if auth is None:
                # Command substitution strips trailing newlines. Emit an
                # explicit non-secret sentinel so an anonymous config cannot
                # be misparsed as its own Authorization header.
                print("-")
            else:
                encoded = base64.b64encode(
                    f"{auth['web_login']}:{auth['password']}".encode("utf-8")
                ).decode("ascii")
                print(f'header = "Authorization: Basic {encoded}"')
        return 0
    if args.command == "private-key-file":
        account = data.get("account")
        if not isinstance(account, dict):
            account = data
        private_key = account.get("private_key")
        private_key = _nonempty_string(private_key, "client config account.private_key")
        print(create_owned_file((private_key + "\n").encode("utf-8"), family=args.family))
        return 0
    if args.command == "materialize":
        public_key_override, private_key_override = parse_secret_overrides()
        rendered = _render_config(
            data,
            metadata,
            public_env=args.public_env,
            taira_chain_id=args.taira_chain_id,
            taira_discriminant=args.taira_discriminant,
            public_key_override=public_key_override,
            private_key_override=private_key_override,
        )
        print(create_owned_file(rendered, family=args.family))
        return 0
    raise AssertionError(args.command)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ConfigError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
