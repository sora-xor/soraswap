import importlib.util
import os
import shutil
import stat
import tempfile
import tomllib
import unittest
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parent.parent
MODULE_PATH = REPO_ROOT / "scripts" / "secure_client_config.py"
TAIRA_NETWORK_ID = "hash:82531CE8EAE8BFF6BEECA4698BFD13A3BC8BEC5F0EE0D23D428C97FC17AB0F3B#3E94"
PRODUCTION_NETWORK_ID = "hash:32C903E5B3497E34C2B844EBFE8A39C19E6CF8F95D44C1FFB8BA9DCB42F91149#A2F0"
spec = importlib.util.spec_from_file_location("soraswap_secure_client_config", MODULE_PATH)
secure_config = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(secure_config)


class SecureClientConfigTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.config = self.root / "config" / "production" / "production.client.toml"
        self.config.parent.mkdir(parents=True)
        self.config.write_text(
            """chain = "production-chain"
network_id = "hash:32C903E5B3497E34C2B844EBFE8A39C19E6CF8F95D44C1FFB8BA9DCB42F91149#A2F0"
torii_url = "https://production.sora.org/"

[account]
domain = "universal"
public_key = "ed0120aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
private_key = "802620bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
chain_discriminant = 991

[basic_auth]
web_login = "operator"
password = "fixture-password"
""",
            encoding="utf-8",
        )
        self.config.chmod(0o600)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def load(self):
        return secure_config.load_config(
            str(self.config),
            production=True,
            repo_root=str(self.root),
            taira_chain_id="fc56984b-2be7-431d-840e-21514d1883f0",
            taira_network_id=TAIRA_NETWORK_ID,
            taira_discriminant=369,
        )

    def test_secure_load_returns_coherent_metadata(self) -> None:
        data, opened, metadata = self.load()
        self.assertEqual(data["chain"], "production-chain")
        self.assertEqual(metadata["torii_origin"], "https://production.sora.org")
        self.assertEqual(metadata["network_id"], PRODUCTION_NETWORK_ID)
        self.assertTrue(metadata["basic_auth_configured"])
        self.assertEqual(stat.S_IMODE(opened.st_mode), 0o600)

    def test_secure_load_rejects_ancestor_symlink(self) -> None:
        alias = self.root / "config-alias"
        alias.symlink_to(self.root / "config", target_is_directory=True)
        with self.assertRaisesRegex(secure_config.ConfigError, "opened securely"):
            secure_config.load_config(
                str(alias / "production" / self.config.name),
                production=True,
                repo_root=str(self.root),
                taira_chain_id="taira",
                taira_network_id=TAIRA_NETWORK_ID,
                taira_discriminant=369,
            )

    def test_secure_load_rejects_replacement_between_stat_and_open(self) -> None:
        original_path = self.config.with_name("opened-original.toml")
        real_open = secure_config.os.open
        raced = False

        def replacing_open(path, flags, *args, **kwargs):
            nonlocal raced
            if path == self.config.name and not (flags & getattr(os, "O_DIRECTORY", 0)) and not raced:
                raced = True
                os.replace(self.config, original_path)
                shutil.copyfile(original_path, self.config)
                self.config.chmod(0o600)
            return real_open(path, flags, *args, **kwargs)

        with mock.patch.object(secure_config.os, "open", side_effect=replacing_open):
            with self.assertRaisesRegex(secure_config.ConfigError, "changed while it was being opened"):
                self.load()
        self.assertTrue(raced)

    @unittest.skipUnless(hasattr(os, "mkfifo"), "FIFO support is required")
    def test_secure_load_rejects_fifo_without_blocking(self) -> None:
        fifo = self.config.with_name("production.client.fifo")
        os.mkfifo(fifo, 0o600)
        self.config.unlink()
        fifo.rename(self.config)

        with self.assertRaisesRegex(secure_config.ConfigError, "non-symlink regular file"):
            self.load()

    def test_secure_load_rejects_in_place_change_while_reading(self) -> None:
        real_read = secure_config.os.read
        raced = False

        def changing_read(descriptor, size):
            nonlocal raced
            chunk = real_read(descriptor, size)
            if chunk and not raced:
                raced = True
                with self.config.open("r+b", buffering=0) as handle:
                    handle.seek(0)
                    handle.write(b"Chain")
                    os.fsync(handle.fileno())
            return chunk

        with mock.patch.object(secure_config.os, "read", side_effect=changing_read):
            with self.assertRaisesRegex(secure_config.ConfigError, "changed while it was being read"):
                self.load()
        self.assertTrue(raced)

    def test_secure_load_rejects_mode_and_hardlink_violations(self) -> None:
        self.config.chmod(0o640)
        with self.assertRaisesRegex(secure_config.ConfigError, "mode 0600"):
            self.load()
        self.config.chmod(0o600)
        linked = self.config.with_name("linked.toml")
        os.link(self.config, linked)
        with self.assertRaisesRegex(secure_config.ConfigError, "exactly one hard link"):
            self.load()

    def test_owned_file_cleanup_refuses_replacement(self) -> None:
        path = Path(secure_config.create_owned_file(b"secret\n", family="replacement-test"))
        self.assertTrue(path.is_absolute())
        self.assertEqual(path, path.resolve())
        original = path.with_name("original-secret")
        path.rename(original)
        path.write_bytes(b"replacement")
        path.chmod(0o600)
        with self.assertRaisesRegex(secure_config.ConfigError, "replaced"):
            secure_config.unlink_owned_file(str(path))
        self.assertEqual(path.read_bytes(), b"replacement")
        path.unlink()
        original.unlink()

    def test_owned_file_cleanup_refuses_multiply_linked_file(self) -> None:
        path = Path(secure_config.create_owned_file(b"secret\n", family="hardlink-test"))
        linked = path.with_name("linked-copy")
        os.link(path, linked)
        with self.assertRaisesRegex(secure_config.ConfigError, "multiply-linked"):
            secure_config.unlink_owned_file(str(path))
        linked.unlink()
        secure_config.unlink_owned_file(str(path))
        self.assertFalse(path.exists())

    @unittest.skipUnless(hasattr(os, "mkfifo"), "FIFO support is required")
    def test_owned_file_cleanup_rejects_fifo_replacement_without_blocking(self) -> None:
        path = Path(secure_config.create_owned_file(b"secret\n", family="fifo-cleanup"))
        original = path.with_name("fifo-cleanup-original")
        path.rename(original)
        os.mkfifo(path, 0o600)
        try:
            with self.assertRaisesRegex(secure_config.ConfigError, "replaced"):
                secure_config.unlink_owned_file(str(path))
            self.assertTrue(stat.S_ISFIFO(path.lstat().st_mode))
        finally:
            path.unlink()
            original.unlink()

    def test_owned_file_creation_does_not_delete_raced_replacement(self) -> None:
        real_lstat = secure_config.os.lstat
        published_path: Path | None = None
        displaced_path: Path | None = None
        raced = False

        def replacing_lstat(path, *args, **kwargs):
            nonlocal published_path, displaced_path, raced
            candidate = Path(path)
            if secure_config.OWNED_SUFFIX_RE.search(str(candidate)) and not raced:
                raced = True
                published_path = candidate
                displaced_path = candidate.with_name("displaced-original")
                candidate.rename(displaced_path)
                candidate.write_bytes(b"replacement")
                candidate.chmod(0o600)
            return real_lstat(path, *args, **kwargs)

        with mock.patch.object(secure_config.os, "lstat", side_effect=replacing_lstat):
            with self.assertRaisesRegex(secure_config.ConfigError, "no longer names"):
                secure_config.create_owned_file(b"secret\n", family="publication-race")

        self.assertTrue(raced)
        assert published_path is not None and displaced_path is not None
        self.assertEqual(published_path.read_bytes(), b"replacement")
        published_path.unlink()
        displaced_path.unlink()

    def test_render_rejects_cross_origin_authenticated_override(self) -> None:
        data, _, metadata = self.load()
        with mock.patch.dict(os.environ, {"SORASWAP_TORII_URL": "https://evil.invalid/"}):
            with self.assertRaisesRegex(secure_config.ConfigError, "configured origin"):
                secure_config._render_config(
                    data,
                    metadata,
                    public_env="production",
                    taira_chain_id="taira",
                    taira_network_id=TAIRA_NETWORK_ID,
                    taira_discriminant=369,
                    public_key_override=None,
                    private_key_override=None,
                )

    def test_render_preserves_network_id_and_domainless_alias_scope(self) -> None:
        data, _, metadata = self.load()
        rendered = secure_config._render_config(
            data,
            metadata,
            public_env="production",
            taira_chain_id="taira",
            taira_network_id=TAIRA_NETWORK_ID,
            taira_discriminant=369,
            public_key_override=None,
            private_key_override=None,
        )
        materialized = tomllib.loads(rendered.decode("utf-8"))
        self.assertEqual(materialized["network_id"], PRODUCTION_NETWORK_ID)
        self.assertEqual(materialized["account"]["domain"], "universal")

    def test_render_requires_exact_current_taira_identity(self) -> None:
        data = {
            "account": {
                "domain": "universal",
                "profile": "taira",
                "public_key": "ed0120" + "a" * 64,
                "private_key": "802620" + "b" * 64,
            }
        }
        metadata = {
            "chain": "fc56984b-2be7-431d-840e-21514d1883f0",
            "network_id": TAIRA_NETWORK_ID,
            "torii_url": "https://taira.sora.org/",
            "torii_origin": "https://taira.sora.org",
            "chain_discriminant": None,
        }
        rendered = secure_config._render_config(
            data,
            metadata,
            public_env="testnet",
            taira_chain_id="fc56984b-2be7-431d-840e-21514d1883f0",
            taira_network_id=TAIRA_NETWORK_ID,
            taira_discriminant=369,
            public_key_override=None,
            private_key_override=None,
        )
        materialized = tomllib.loads(rendered.decode("utf-8"))
        self.assertEqual(materialized["chain"], metadata["chain"])
        self.assertEqual(materialized["account"]["chain_discriminant"], 369)

        with mock.patch.dict(
            os.environ,
            {
                "SORASWAP_TESTNET_CHAIN_ID": "retired-chain-override",
                "SORASWAP_TESTNET_CHAIN_DISCRIMINANT": "991",
            },
            clear=False,
        ), self.assertRaisesRegex(secure_config.ConfigError, "unsupported Taira identity override"):
            secure_config._render_config(
                data,
                metadata,
                public_env="testnet",
                taira_chain_id="fc56984b-2be7-431d-840e-21514d1883f0",
                taira_network_id=TAIRA_NETWORK_ID,
                taira_discriminant=369,
                public_key_override=None,
                private_key_override=None,
            )

        for retired_name in (
            "SORASWAP_TESTNET_CHAIN_ID",
            "SORASWAP_TESTNET_CHAIN_DISCRIMINANT",
        ):
            with self.subTest(retired_name=retired_name), mock.patch.dict(
                os.environ,
                {retired_name: ""},
                clear=False,
            ), self.assertRaisesRegex(
                secure_config.ConfigError, "unsupported Taira identity override"
            ):
                secure_config._render_config(
                    data,
                    metadata,
                    public_env="testnet",
                    taira_chain_id="fc56984b-2be7-431d-840e-21514d1883f0",
                    taira_network_id=TAIRA_NETWORK_ID,
                    taira_discriminant=369,
                    public_key_override=None,
                    private_key_override=None,
                )

        for field, value, message in (
            ("chain", "wrong-chain", "canonical Taira chain"),
            ("network_id", PRODUCTION_NETWORK_ID, "canonical Taira network"),
            ("chain_discriminant", 991, "canonical Taira"),
        ):
            invalid = dict(metadata)
            invalid[field] = value
            with self.subTest(field=field), self.assertRaisesRegex(secure_config.ConfigError, message):
                secure_config._render_config(
                    data,
                    invalid,
                    public_env="testnet",
                    taira_chain_id="fc56984b-2be7-431d-840e-21514d1883f0",
                    taira_network_id=TAIRA_NETWORK_ID,
                    taira_discriminant=369,
                    public_key_override=None,
                    private_key_override=None,
                )

    def test_secure_load_requires_canonical_network_id(self) -> None:
        original = self.config.read_text(encoding="utf-8")
        self.config.write_text(original.replace(f'network_id = "{PRODUCTION_NETWORK_ID}"\n', ""), encoding="utf-8")
        with self.assertRaisesRegex(secure_config.ConfigError, "network_id must be a non-empty string"):
            self.load()

        self.config.write_text(
            original.replace(PRODUCTION_NETWORK_ID, PRODUCTION_NETWORK_ID.lower()),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(secure_config.ConfigError, "must be canonical"):
            self.load()

    def test_nonproduction_load_rejects_flat_account_credentials(self) -> None:
        flat_config = self.root / "flat.client.toml"
        flat_config.write_text(
            f'''chain = "local-chain"
network_id = "{PRODUCTION_NETWORK_ID}"
torii_url = "http://127.0.0.1:8080/"
domain = "universal"
public_key = "ed0120aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
private_key = "802620bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
''',
            encoding="utf-8",
        )
        with self.assertRaisesRegex(secure_config.ConfigError, "account must be a table"):
            secure_config.load_config(
                str(flat_config),
                production=False,
                repo_root=str(self.root),
                taira_chain_id="fc56984b-2be7-431d-840e-21514d1883f0",
                taira_network_id=TAIRA_NETWORK_ID,
                taira_discriminant=369,
            )

    def test_production_rejects_taira_network_id(self) -> None:
        original = self.config.read_text(encoding="utf-8")
        self.config.write_text(original.replace(PRODUCTION_NETWORK_ID, TAIRA_NETWORK_ID), encoding="utf-8")
        with self.assertRaisesRegex(secure_config.ConfigError, "canonical Taira network"):
            self.load()

    def test_output_check_rejects_config_and_file_secret_echoes(self) -> None:
        data, _, _ = self.load()
        joined = "operator:fixture-password"
        encoded = secure_config.base64.b64encode(joined.encode("utf-8")).decode("ascii")
        external = Path(secure_config.create_owned_file(b"api-token-value\n", family="api-token"))
        try:
            hostile_outputs = (
                b"fixture-password",
                f"Basic {encoded}".encode("utf-8"),
                data["account"]["private_key"].encode("utf-8"),
                secure_config.base64.b64encode(
                    data["account"]["private_key"].encode("utf-8")
                ),
                b"api-token-value",
            )
            for output in hostile_outputs:
                with self.subTest(output=output[:16]):
                    with self.assertRaisesRegex(secure_config.ConfigError, "credential material"):
                        secure_config.assert_output_has_no_credentials(
                            output,
                            data,
                            secret_files=[str(external)],
                        )
            secure_config.assert_output_has_no_credentials(
                b'{"status":"completed"}',
                data,
                secret_files=[str(external)],
            )
        finally:
            secure_config.unlink_owned_file(str(external))


if __name__ == "__main__":
    unittest.main()
