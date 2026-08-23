#!/usr/bin/env python3

from __future__ import annotations

import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import prepare_validation_fee_deployment as deployment  # noqa: E402


class ValidationFeeDeploymentSpecTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.spec = json.loads(
            (ROOT / "config/validation_fee/deployment.taira.p1.json").read_text(
                encoding="utf-8"
            )
        )

    def test_reviewed_spec_passes_strict_validation(self) -> None:
        checked = deployment.validate_spec(copy.deepcopy(self.spec))
        self.assertEqual(checked["chain_id"], deployment.EXPECTED_CHAIN_ID)
        self.assertEqual(
            [contract["deploy_nonce"] for contract in checked["contracts"]],
            [0, 1],
        )

    def test_unknown_top_level_field_is_rejected(self) -> None:
        altered = copy.deepcopy(self.spec)
        altered["compatibility"] = True
        with self.assertRaisesRegex(deployment.PlanError, "unknown fields"):
            deployment.validate_spec(altered, enforce_release_digest=False)

    def test_wrong_nonce_or_alias_is_rejected(self) -> None:
        altered = copy.deepcopy(self.spec)
        altered["contracts"][1]["deploy_nonce"] = 2
        with self.assertRaisesRegex(deployment.PlanError, "nonces"):
            deployment.validate_spec(altered, enforce_release_digest=False)

        altered = copy.deepcopy(self.spec)
        altered["contracts"][0]["alias"] = "legacy_pool::dlmm.universal"
        with self.assertRaisesRegex(deployment.PlanError, "aliases"):
            deployment.validate_spec(altered, enforce_release_digest=False)

    def test_protected_selectors_are_exact_and_ordered(self) -> None:
        altered = copy.deepcopy(self.spec)
        altered["protected_permissions"][1]["payload"]["entrypoint"] = (
            "swap_exact_in_quote"
        )
        with self.assertRaisesRegex(deployment.PlanError, "exact ordered P1"):
            deployment.validate_spec(altered, enforce_release_digest=False)

        altered = copy.deepcopy(self.spec)
        altered["protected_permissions"][0], altered["protected_permissions"][1] = (
            altered["protected_permissions"][1],
            altered["protected_permissions"][0],
        )
        with self.assertRaisesRegex(deployment.PlanError, "exact ordered P1"):
            deployment.validate_spec(altered, enforce_release_digest=False)

    def test_chain_and_subject_purposes_are_exact(self) -> None:
        altered = copy.deepcopy(self.spec)
        altered["chain_id"] = "old-chain"
        with self.assertRaisesRegex(deployment.PlanError, "fresh Taira"):
            deployment.validate_spec(altered, enforce_release_digest=False)

        altered = copy.deepcopy(self.spec)
        altered["pre_deploy_accounts"][0]["purpose"] = "generic"
        with self.assertRaisesRegex(deployment.PlanError, "exact P1 purposes"):
            deployment.validate_spec(altered, enforce_release_digest=False)

        altered = copy.deepcopy(self.spec)
        altered["pre_deploy_accounts"].reverse()
        with self.assertRaisesRegex(deployment.PlanError, "unknown fields"):
            deployment.validate_spec(altered, enforce_release_digest=False)

        altered = copy.deepcopy(self.spec)
        altered["pre_deploy_accounts"][1]["required_before_contract_order"] = 3
        with self.assertRaisesRegex(deployment.PlanError, "before contract order 2"):
            deployment.validate_spec(altered, enforce_release_digest=False)

        altered = copy.deepcopy(self.spec)
        altered["pre_deploy_accounts"][0]["compatibility"] = True
        with self.assertRaisesRegex(deployment.PlanError, "unknown fields"):
            deployment.validate_spec(altered, enforce_release_digest=False)

    def test_iroha_binary_must_embed_reviewed_source_commit(self) -> None:
        expected = "a" * 40
        with tempfile.TemporaryDirectory() as temporary:
            binary = Path(temporary) / "iroha"
            binary.write_bytes(b"prefix" + expected.encode("ascii") + b"suffix")
            deployment.validate_iroha_binary_source_binding(binary, expected)

            binary.write_bytes(b"prefix" + b"b" * 40 + b"suffix")
            with self.assertRaisesRegex(
                deployment.PlanError,
                "does not embed the reviewed Iroha source commit",
            ):
                deployment.validate_iroha_binary_source_binding(
                    binary,
                    expected,
                )

            binary.write_bytes(
                b"prefix"
                + expected.encode("ascii")
                + deployment.REJECTED_IROHA_SOURCE_COMMITS[0].encode("ascii")
                + b"suffix"
            )
            with self.assertRaisesRegex(
                deployment.PlanError,
                "embeds rejected stale Iroha source commit",
            ):
                deployment.validate_iroha_binary_source_binding(
                    binary,
                    expected,
                )

            stale = deployment.REJECTED_IROHA_SOURCE_COMMITS[0]
            binary.write_bytes(stale.encode("ascii"))
            with self.assertRaisesRegex(
                deployment.PlanError,
                "embeds rejected stale Iroha source commit",
            ):
                deployment.validate_iroha_binary_source_binding(
                    binary,
                    stale,
                )

    def test_cargo_lock_mismatch_and_mutation_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            cargo_lock = root / "Cargo.lock"
            original = b"# reviewed lock\nversion = 4\n"
            cargo_lock.write_bytes(original)
            expected_hash = deployment.sha256_bytes(original)
            checked = deployment.validate_cargo_lock_binding(
                root,
                expected_hash,
                len(original),
            )
            self.assertEqual(checked["sha256"], expected_hash)
            self.assertEqual(checked["size_bytes"], len(original))

            with self.assertRaisesRegex(
                deployment.PlanError,
                "hash differs from the reviewed release input",
            ):
                deployment.validate_cargo_lock_binding(
                    root,
                    "0" * 64,
                    len(original),
                )

            cargo_lock.write_bytes(original + b"# mutation\n")
            with self.assertRaisesRegex(
                deployment.PlanError,
                "hash differs from the reviewed release input",
            ):
                deployment.validate_cargo_lock_binding(
                    root,
                    expected_hash,
                    len(original),
                )

    def test_additional_ignored_source_input_is_rejected(self) -> None:
        def fake_git(*arguments: str) -> SimpleNamespace:
            if "--ignored" in arguments:
                return SimpleNamespace(stdout="Cargo.lock\0generated/input\0")
            return SimpleNamespace(stdout="")

        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(
                deployment.PlanError,
                "exactly the separately bound Cargo.lock",
            ):
                deployment.audit_cargo_source_inputs(
                    Path(temporary),
                    fake_git,
                )

    def test_source_closure_manifest_is_self_consistent(self) -> None:
        stale = copy.deepcopy(self.spec)
        stale["iroha_source_commit"] = (
            deployment.REJECTED_IROHA_SOURCE_COMMITS[0]
        )
        with self.assertRaisesRegex(
            deployment.PlanError,
            "signed reviewed base",
        ):
            deployment.validate_spec(
                stale,
                enforce_release_digest=False,
            )

        altered = copy.deepcopy(self.spec)
        altered["iroha_source_untracked_path_blob_manifest"][0][
            "blob_sha256"
        ] = "0" * 64
        with self.assertRaisesRegex(
            deployment.PlanError,
            "manifest hash differs",
        ):
            deployment.validate_spec(
                altered,
                enforce_release_digest=False,
            )

        altered = copy.deepcopy(self.spec)
        altered["iroha_source_fingerprint_sha256"] = "0" * 64
        with self.assertRaisesRegex(
            deployment.PlanError,
            "fingerprint differs",
        ):
            deployment.validate_spec(
                altered,
                enforce_release_digest=False,
            )

    def test_tracked_and_untracked_source_closure_is_exact(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            subprocess.run(
                ["git", "-C", str(root), "config", "user.name", "Test"],
                check=True,
            )
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(root),
                    "config",
                    "user.email",
                    "test@example.invalid",
                ],
                check=True,
            )
            tracked = root / "tracked.txt"
            tracked.write_text("base\n", encoding="utf-8")
            subprocess.run(
                ["git", "-C", str(root), "add", "tracked.txt"],
                check=True,
            )
            subprocess.run(
                ["git", "-C", str(root), "commit", "-qm", "base"],
                check=True,
            )
            tracked.write_text("reviewed closure\n", encoding="utf-8")
            untracked = root / "untracked.txt"
            untracked.write_text("first\n", encoding="utf-8")

            first = deployment.capture_iroha_source_closure(root)
            second = deployment.capture_iroha_source_closure(root)
            self.assertEqual(first, second)
            self.assertEqual(first["untracked_file_count"], 1)
            self.assertEqual(
                first["untracked_path_blob_manifest"][0]["path"],
                "untracked.txt",
            )

            matching_spec = {
                "iroha_source_tracked_binary_diff_sha256": first[
                    "tracked_binary_diff_sha256"
                ],
                "iroha_source_untracked_file_count": 1,
                "iroha_source_untracked_path_blob_manifest": first[
                    "untracked_path_blob_manifest"
                ],
                "iroha_source_untracked_path_blob_manifest_sha256": first[
                    "untracked_path_blob_manifest_sha256"
                ],
                "iroha_source_fingerprint_sha256": first[
                    "fingerprint_sha256"
                ],
            }
            deployment.require_iroha_source_closure(first, matching_spec)

            untracked.write_text("changed\n", encoding="utf-8")
            changed = deployment.capture_iroha_source_closure(root)
            self.assertEqual(
                changed["tracked_binary_diff_sha256"],
                first["tracked_binary_diff_sha256"],
            )
            self.assertNotEqual(
                changed["untracked_path_blob_manifest_sha256"],
                first["untracked_path_blob_manifest_sha256"],
            )
            self.assertNotEqual(
                changed["fingerprint_sha256"],
                first["fingerprint_sha256"],
            )
            with self.assertRaisesRegex(
                deployment.PlanError,
                "closure differs",
            ):
                deployment.require_iroha_source_closure(
                    changed,
                    matching_spec,
                )

            tracked.write_text("changed again\n", encoding="utf-8")
            changed_tracked = deployment.capture_iroha_source_closure(root)
            self.assertNotEqual(
                changed_tracked["tracked_binary_diff_sha256"],
                first["tracked_binary_diff_sha256"],
            )

            untracked.unlink()
            untracked.symlink_to(root / "external-target")
            with self.assertRaisesRegex(
                deployment.PlanError,
                "untracked Iroha source symlinks are forbidden",
            ):
                deployment.capture_iroha_source_closure(root)

    def test_head_drift_after_closure_verification_is_rejected(self) -> None:
        expected = deployment.REVIEWED_IROHA_BASE_COMMIT
        heads = iter((expected, "f" * 40))

        def fake_git(*arguments: str) -> SimpleNamespace:
            if arguments[:3] == ("rev-parse", "--verify", "HEAD"):
                return SimpleNamespace(stdout=next(heads) + "\n")
            if arguments == ("verify-commit", expected):
                return SimpleNamespace(stdout="")
            raise AssertionError(f"unexpected Git call: {arguments!r}")

        deployment.require_reviewed_iroha_head(
            fake_git,
            expected,
            "initial source verification",
        )
        with self.assertRaisesRegex(
            deployment.PlanError,
            "during final source verification",
        ):
            deployment.require_reviewed_iroha_head(
                fake_git,
                expected,
                "final source verification",
            )

    def test_inherited_git_and_index_overrides_are_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "repository"
            root.mkdir()
            subprocess.run(
                [str(deployment.PINNED_GIT), "init", "-q", str(root)],
                check=True,
            )
            subprocess.run(
                [
                    str(deployment.PINNED_GIT),
                    "-C",
                    str(root),
                    "config",
                    "user.name",
                    "Test",
                ],
                check=True,
            )
            subprocess.run(
                [
                    str(deployment.PINNED_GIT),
                    "-C",
                    str(root),
                    "config",
                    "user.email",
                    "test@example.invalid",
                ],
                check=True,
            )
            (root / "tracked.txt").write_text("base\n", encoding="utf-8")
            subprocess.run(
                [
                    str(deployment.PINNED_GIT),
                    "-C",
                    str(root),
                    "add",
                    "tracked.txt",
                ],
                check=True,
            )
            subprocess.run(
                [
                    str(deployment.PINNED_GIT),
                    "-C",
                    str(root),
                    "commit",
                    "-qm",
                    "base",
                ],
                check=True,
            )
            (root / "tracked.txt").write_text(
                "reviewed closure\n",
                encoding="utf-8",
            )
            baseline = deployment.capture_iroha_source_closure(root)

            fake_bin = Path(temporary) / "fake-bin"
            fake_bin.mkdir()
            fake_git = fake_bin / "git"
            fake_git.write_text(
                "#!/bin/sh\nexit 97\n",
                encoding="utf-8",
            )
            fake_git.chmod(0o755)
            fake_index = Path(temporary) / "forged-index"
            fake_index.write_bytes(b"forged")
            injected = {
                "GIT_CONFIG_COUNT": "1",
                "GIT_CONFIG_KEY_0": "diff.external",
                "GIT_CONFIG_VALUE_0": "/bin/false",
                "GIT_DIR": str(Path(temporary) / "forged-git-dir"),
                "GIT_INDEX_FILE": str(fake_index),
                "GIT_WORK_TREE": str(Path(temporary) / "forged-worktree"),
                "PATH": str(fake_bin),
            }
            with mock.patch.dict(os.environ, injected, clear=False):
                observed = deployment.capture_iroha_source_closure(root)
            self.assertEqual(observed, baseline)

    def test_inherited_gpg_program_and_cargo_home_are_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            forged_cargo_home = Path(temporary) / "cargo-home"
            forged_cargo_home.mkdir()
            (forged_cargo_home / "config.toml").write_text(
                "[build]\nrustflags = ['--cfg', 'forged']\n",
                encoding="utf-8",
            )
            injected = {
                "CARGO_HOME": str(forged_cargo_home),
                "GIT_CONFIG_COUNT": "1",
                "GIT_CONFIG_KEY_0": "gpg.program",
                "GIT_CONFIG_VALUE_0": "/bin/false",
                "GNUPGHOME": str(Path(temporary) / "forged-gnupg"),
            }
            with mock.patch.dict(os.environ, injected, clear=False):
                deployment._run_iroha_git_bytes(
                    ROOT.parent / "iroha",
                    "verify-commit",
                    deployment.REVIEWED_IROHA_BASE_COMMIT,
                )

                def fake_git(*arguments: str) -> SimpleNamespace:
                    if "--ignored" in arguments:
                        return SimpleNamespace(stdout="Cargo.lock\0")
                    return SimpleNamespace(stdout="")

                audit = deployment.audit_cargo_source_inputs(
                    Path(temporary),
                    fake_git,
                )
            self.assertEqual(audit["ignored_inputs"], ["Cargo.lock"])
            self.assertNotIn(
                str(forged_cargo_home),
                {
                    item["path"]
                    for item in audit["cargo_config_inputs"]
                },
            )


if __name__ == "__main__":
    unittest.main()
