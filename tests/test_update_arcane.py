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

OLD_DIGEST = "sha256:" + "a" * 64
NEW_DIGEST = "sha256:" + "b" * 64
SAMPLE = (
    "    arcane = {\n"
    f'      image = "ghcr.io/getarcaneapp/manager:v2.17.3@{OLD_DIGEST}";\n'
    "      autoStart = true;\n"
    "    };\n"
)


class ArcaneVersionTests(unittest.TestCase):
    def test_parse_stable_semver(self) -> None:
        self.assertEqual(update_arcane.parse_version("v2.17.3"), (2, 17, 3))

    def test_parse_rejects_prerelease_or_missing_prefix(self) -> None:
        for tag in ("v3.0.1-rc.1", "3.0.1", "latest", "v3.0"):
            with self.subTest(tag=tag), self.assertRaises(update_arcane.UpdateError):
                update_arcane.parse_version(tag)

    def test_same_major_release_can_be_updated(self) -> None:
        self.assertEqual(
            update_arcane.update_kind((2, 17, 3), (2, 18, 0)),
            "same-major",
        )

    def test_major_release_requires_manual_migration(self) -> None:
        self.assertEqual(
            update_arcane.update_kind((2, 17, 3), (3, 0, 1)),
            "major",
        )

    def test_older_or_equal_release_is_not_an_update(self) -> None:
        self.assertEqual(
            update_arcane.update_kind((2, 17, 3), (2, 17, 3)),
            "current",
        )
        self.assertEqual(
            update_arcane.update_kind((2, 17, 3), (2, 16, 9)),
            "current",
        )


class ArcaneImageTests(unittest.TestCase):
    def test_reads_single_pinned_manager_image(self) -> None:
        self.assertEqual(
            update_arcane.read_arcane_image(SAMPLE),
            ("v2.17.3", OLD_DIGEST),
        )

    def test_updates_only_manager_tag_and_digest(self) -> None:
        updated = update_arcane.replace_arcane_image(
            SAMPLE,
            "v2.18.0",
            NEW_DIGEST,
        )
        self.assertIn(
            f'ghcr.io/getarcaneapp/manager:v2.18.0@{NEW_DIGEST}',
            updated,
        )
        self.assertIn("autoStart = true;", updated)
        self.assertNotIn(OLD_DIGEST, updated)

    def test_rejects_invalid_digest(self) -> None:
        with self.assertRaises(update_arcane.UpdateError):
            update_arcane.replace_arcane_image(
                SAMPLE,
                "v2.18.0",
                "not-a-digest",
            )

    def test_rejects_missing_or_duplicate_manager_images(self) -> None:
        with self.assertRaises(update_arcane.UpdateError):
            update_arcane.read_arcane_image("services.arcane.enable = true;\n")

        with self.assertRaises(update_arcane.UpdateError):
            update_arcane.read_arcane_image(SAMPLE + SAMPLE)


if __name__ == "__main__":
    unittest.main()
