"""Offline regression tests for the Nori release updater."""

from __future__ import annotations

import base64
import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "update-nori.py"
SPEC = importlib.util.spec_from_file_location("update_nori", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load updater module from {SCRIPT}")

update_nori = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(update_nori)


class VersionTests(unittest.TestCase):
    def test_version_tuple_parses_stable_semver(self) -> None:
        self.assertEqual(update_nori.version_tuple("0.9.0"), (0, 9, 0))

    def test_version_tuple_rejects_prerelease(self) -> None:
        with self.assertRaises(ValueError):
            update_nori.version_tuple("0.9.0-rc1")


class ReleaseAssetTests(unittest.TestCase):
    def test_asset_sri_converts_github_sha256_digest(self) -> None:
        digest = "0" * 64
        actual = update_nori.asset_sri({"digest": f"sha256:{digest}"})
        expected = "sha256-" + base64.b64encode(bytes.fromhex(digest)).decode("ascii")
        self.assertEqual(actual, expected)

    def test_asset_sri_rejects_untrusted_fallback_url(self) -> None:
        with self.assertRaises(ValueError):
            update_nori.asset_sri({"browser_download_url": "https://example.invalid/file"})


class PackageUpdateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.package = Path("package.nix")
        self.source = '''version = "0.8.0";

sources = {
  "x86_64-linux" = {
    arch = "x86_64";
    hash = "sha256-old-x86";
  };
  "aarch64-linux" = {
    arch = "aarch64";
    hash = "sha256-old-arm";
  };
};
'''

    def test_update_package_changes_version_and_both_architecture_hashes(self) -> None:
        updated = update_nori.update_package(
            self.package,
            "0.8.0",
            "0.9.0",
            {
                "x86_64-linux": "sha256-new-x86",
                "aarch64-linux": "sha256-new-arm",
            },
        )

        self.assertIn('version = "0.9.0";', updated)
        self.assertIn('hash = "sha256-new-x86";', updated)
        self.assertIn('hash = "sha256-new-arm";', updated)
        self.assertNotIn("sha256-old", updated)

    def test_update_package_rejects_unexpected_current_version(self) -> None:
        with self.assertRaises(ValueError):
            update_nori.update_package(
                self.package,
                "0.7.0",
                "0.9.0",
                {
                    "x86_64-linux": "sha256-new-x86",
                    "aarch64-linux": "sha256-new-arm",
                },
            )


if __name__ == "__main__":
    unittest.main()
