"""Offline regression tests for the OCI image digest updater."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "update-docker-digests.py"
SPEC = importlib.util.spec_from_file_location("update_docker_digests", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load updater module from {SCRIPT}")

update_docker_digests = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(update_docker_digests)


class ImageReferenceTests(unittest.TestCase):
    def test_parse_docker_hub_reference(self) -> None:
        self.assertEqual(
            update_docker_digests.parse_image_reference("postgres:17-alpine"),
            ("postgres", "17-alpine", None),
        )

    def test_parse_ghcr_reference_with_digest(self) -> None:
        digest = "sha256:" + "a" * 64
        self.assertEqual(
            update_docker_digests.parse_image_reference(
                f"ghcr.io/getarcaneapp/agent:v2.17.3@{digest}"
            ),
            ("ghcr.io/getarcaneapp/agent", "v2.17.3", digest),
        )

    def test_parse_rejects_unpinned_latest_without_tag_separator(self) -> None:
        with self.assertRaises(ValueError):
            update_docker_digests.parse_image_reference("ghcr.io/example/image")

    def test_registry_coordinates_normalize_docker_hub(self) -> None:
        self.assertEqual(
            update_docker_digests.registry_coordinates("postgres"),
            ("registry-1.docker.io", "library/postgres"),
        )
        self.assertEqual(
            update_docker_digests.registry_coordinates("wollomatic/socket-proxy"),
            ("registry-1.docker.io", "wollomatic/socket-proxy"),
        )

    def test_registry_coordinates_preserve_ghcr_repository(self) -> None:
        self.assertEqual(
            update_docker_digests.registry_coordinates("ghcr.io/getarcaneapp/manager"),
            ("ghcr.io", "getarcaneapp/manager"),
        )


class ImageUpdateTests(unittest.TestCase):
    def test_update_image_reference_adds_digest(self) -> None:
        digest = "sha256:" + "b" * 64
        source = '    image = "postgres:17-alpine";\n'

        updated, changes = update_docker_digests.update_image_references(
            source,
            resolver=lambda repository, tag: digest,
        )

        self.assertEqual(
            updated,
            f'    image = "postgres:17-alpine@{digest}";\n',
        )
        self.assertEqual(len(changes), 1)

    def test_update_image_reference_refreshes_changed_digest(self) -> None:
        old_digest = "sha256:" + "a" * 64
        new_digest = "sha256:" + "c" * 64
        source = f'    image = "ghcr.io/example/app:1.2.3@{old_digest}";\n'

        updated, changes = update_docker_digests.update_image_references(
            source,
            resolver=lambda repository, tag: new_digest,
        )

        self.assertIn(new_digest, updated)
        self.assertNotIn(old_digest, updated)
        self.assertEqual(len(changes), 1)

    def test_unchanged_digest_produces_no_change(self) -> None:
        digest = "sha256:" + "d" * 64
        source = f'    image = "postgres:17-alpine@{digest}";\n'

        updated, changes = update_docker_digests.update_image_references(
            source,
            resolver=lambda repository, tag: digest,
        )

        self.assertEqual(updated, source)
        self.assertEqual(changes, [])

    def test_invalid_registry_digest_is_rejected(self) -> None:
        source = '    image = "postgres:17-alpine";\n'

        with self.assertRaises(ValueError):
            update_docker_digests.update_image_references(
                source,
                resolver=lambda repository, tag: "not-a-digest",
            )


if __name__ == "__main__":
    unittest.main()
