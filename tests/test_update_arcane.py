"""Offline tests for the Arcane image updater."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "update-arcane.py"
SPEC = importlib.util.spec_from_file_location("update_arcane", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load Arcane updater from {SCRIPT}")

update_arcane = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(update_arcane)


class ArcaneVersionTests(unittest.TestCase):
    def test_parse_stable_semver_tag(self) -> None:
        self.assertEqual(update_arcane.parse_version("v2.17.3"), (2, 17, 3))

    def test_reject_prerelease_and_non_semver_tags(self) -> None:
        self.assertIsNone(update_arcane.parse_version("v3.0.0-rc.1"))
        self.assertIsNone(update_arcane.parse_version("latest"))

    def test_select_latest_stable_release_within_current_major(self) -> None:
        releases = [
            {"tag_name": "v3.0.1", "draft": False, "prerelease": False},
            {"tag_name": "v2.17.2", "draft": False, "prerelease": False},
            {"tag_name": "v2.18.0", "draft": False, "prerelease": False},
            {"tag_name": "v2.19.0-rc.1", "draft": False, "prerelease": True},
            {"tag_name": "v2.20.0", "draft": True, "prerelease": False},
        ]

        self.assertEqual(
            update_arcane.latest_stable_release(releases, major=2),
            ("v2.18.0", (2, 18, 0)),
        )

    def test_latest_stable_release_finds_major_upgrade_without_applying_it(self) -> None:
        releases = [
            {"tag_name": "v3.0.1", "draft": False, "prerelease": False},
            {"tag_name": "v2.17.3", "draft": False, "prerelease": False},
        ]

        self.assertEqual(
            update_arcane.latest_stable_release(releases),
            ("v3.0.1", (3, 0, 1)),
        )
        self.assertEqual(
            update_arcane.latest_stable_release(releases, major=2),
            ("v2.17.3", (2, 17, 3)),
        )


class ArcaneImageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.old_digest = "sha256:" + "a" * 64
        self.new_digest = "sha256:" + "b" * 64
        self.content = (
            "{\n"
            "  containers.arcane = {\n"
            f'    image = "ghcr.io/getarcaneapp/manager:v2.17.3@{self.old_digest}";\n'
            "  };\n"
            "}\n"
        )

    def test_replace_tag_and_digest_together(self) -> None:
        updated, old_reference = update_arcane.replace_image_reference(
            self.content, "v2.18.0", self.new_digest
        )

        self.assertIn(
            f"ghcr.io/getarcaneapp/manager:v2.18.0@{self.new_digest}",
            updated,
        )
        self.assertNotIn(self.old_digest, updated)
        self.assertIn("manager:v2.17.3", old_reference)

    def test_reject_invalid_digest(self) -> None:
        with self.assertRaises(ValueError):
            update_arcane.replace_image_reference(
                self.content, "v2.18.0", "not-a-digest"
            )

    def test_reject_multiple_arcane_image_assignments(self) -> None:
        with self.assertRaises(ValueError):
            update_arcane.replace_image_reference(
                self.content + self.content, "v2.18.0", self.new_digest
            )


if __name__ == "__main__":
    unittest.main()
