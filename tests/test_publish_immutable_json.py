#!/usr/bin/env python3

from __future__ import annotations

import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import publish_immutable_json as publisher  # noqa: E402


CANONICAL = b'{\n  "phase": "submission",\n  "schema_version": 1\n}\n'


class ImmutableJsonPublisherTests(unittest.TestCase):
    def test_publish_is_no_clobber_and_mode_0444(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory).resolve() / "submission.json"
            publisher.publish(CANONICAL, output)

            self.assertEqual(output.read_bytes(), CANONICAL)
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o444)
            publisher.publish(CANONICAL, output)

            with self.assertRaisesRegex(
                publisher.PublicationError,
                "refusing to replace different",
            ):
                publisher.publish(
                    b'{\n  "phase": "Applied",\n  "schema_version": 1\n}\n',
                    output,
                )
            self.assertEqual(output.read_bytes(), CANONICAL)

    def test_noncanonical_or_duplicate_input_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory).resolve() / "intent.json"
            for raw in (
                b'{"schema_version":1,"phase":"intent"}\n',
                b'{\n  "phase": "intent",\n  "phase": "other"\n}\n',
                b'{\n  "value": NaN\n}\n',
            ):
                with self.subTest(raw=raw):
                    with self.assertRaises(publisher.PublicationError):
                        publisher.publish(raw, output)
                    self.assertFalse(output.exists())

    def test_file_and_directories_are_fsynced(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory).resolve() / "Applied.json"
            with mock.patch.object(
                publisher.os,
                "fsync",
                wraps=publisher.os.fsync,
            ) as fsync:
                publisher.publish(CANONICAL, output)

            self.assertGreaterEqual(fsync.call_count, 5)

    def test_post_link_failure_never_makes_published_inode_mutable(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory).resolve() / "submission.json"
            real_fsync_directory = publisher.fsync_directory
            calls = 0

            def fail_second_directory_fsync(path: Path) -> None:
                nonlocal calls
                calls += 1
                if calls == 2:
                    raise OSError("injected post-link directory fsync failure")
                real_fsync_directory(path)

            with mock.patch.object(
                publisher,
                "fsync_directory",
                side_effect=fail_second_directory_fsync,
            ):
                with self.assertRaisesRegex(
                    OSError,
                    "injected post-link",
                ):
                    publisher.publish(CANONICAL, output)

            self.assertEqual(output.read_bytes(), CANONICAL)
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o444)
            publisher.publish(CANONICAL, output)

    def test_nested_directories_are_created_and_fsynced(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory).resolve() / "one" / "two" / "three"
            with mock.patch.object(
                publisher.os,
                "fsync",
                wraps=publisher.os.fsync,
            ) as fsync:
                publisher.ensure_directory(target)

            self.assertTrue(target.is_dir())
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o700)
            self.assertGreaterEqual(fsync.call_count, 8)


if __name__ == "__main__":
    unittest.main()
