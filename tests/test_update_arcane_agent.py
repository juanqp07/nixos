"""Offline tests for the Arcane Agent updater."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "update-arcane-agent.py"
SPEC = importlib.util.spec_from_file_location("update_arcane_agent", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load Arcane Agent updater from {SCRIPT}")

update_agent = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(update_agent)

OLD_DIGEST = "sha256:" + "a" * 64
NEW_DIGEST = "sha256:" + "b" * 64
MANAGER = (
    "    arcane = {\n"
    f'      image = "ghcr.io/getarcaneapp/manager:v2.17.3@{OLD_DIGEST}";\n'
    "    };\n"
)
AGENT = (
    "      containers.arcane-agent = {\n"
    f'        image = "ghcr.io/getarcaneapp/agent:v2.17.2@{OLD_DIGEST}";\n'
    "        autoStart = true;\n"
    "      };\n"
)


class ArcaneAgentVersionTests(unittest.TestCase):
    def test_parse_stable_semver(self) -> None:
        self.assertEqual(update_agent.parse_version("v2.17.3"), (2, 17, 3))

    def test_parse_rejects_unstable_or_invalid_versions(self) -> None:
        for tag in ("v3.0.1-rc.1", "3.0.1", "latest", "v3.0"):
            with self.subTest(tag=tag), self.assertRaises(update_agent.UpdateError):
                update_agent.parse_version(tag)

    def test_agent_behind_manager_on_same_major_is_updated(self) -> None:
        self.assertEqual(
            update_agent.agent_sync_status("v2.17.3", "v2.17.2"),
            "update",
        )

    def test_major_mismatch_requires_manual_migration(self) -> None:
        self.assertEqual(
            update_agent.agent_sync_status("v3.0.1", "v2.17.3"),
            "major",
        )

    def test_agent_ahead_of_manager_is_never_downgraded(self) -> None:
        self.assertEqual(
            update_agent.agent_sync_status("v2.17.2", "v2.17.3"),
            "agent-ahead",
        )

    def test_matching_versions_need_no_update(self) -> None:
        self.assertEqual(
            update_agent.agent_sync_status("v2.17.3", "v2.17.3"),
            "current",
        )

    def test_reads_manager_image_version(self) -> None:
        self.assertEqual(update_agent.read_manager_version(MANAGER), "v2.17.3")

    def test_reads_agent_tag_and_digest(self) -> None:
        self.assertEqual(
            update_agent.read_agent_image(AGENT),
            ("v2.17.2", OLD_DIGEST),
        )

    def test_updates_only_agent_tag_and_digest(self) -> None:
        updated = update_agent.replace_agent_image(
            AGENT,
            "v2.17.3",
            NEW_DIGEST,
        )
        self.assertIn(
            f"ghcr.io/getarcaneapp/agent:v2.17.3@{NEW_DIGEST}",
            updated,
        )
        self.assertIn("autoStart = true;", updated)
        self.assertNotIn(OLD_DIGEST, updated)

    def test_rejects_invalid_digest(self) -> None:
        with self.assertRaises(update_agent.UpdateError):
            update_agent.replace_agent_image(AGENT, "v2.17.3", "not-a-digest")

    def test_rejects_missing_or_duplicate_agent_image(self) -> None:
        with self.assertRaises(update_agent.UpdateError):
            update_agent.read_agent_image("services.arcane.enable = true;\n")
        with self.assertRaises(update_agent.UpdateError):
            update_agent.read_agent_image(AGENT + AGENT)

    def test_rejects_missing_or_duplicate_manager_image(self) -> None:
        with self.assertRaises(update_agent.UpdateError):
            update_agent.read_manager_version("services.arcane.enable = true;\n")
        with self.assertRaises(update_agent.UpdateError):
            update_agent.read_manager_version(MANAGER + MANAGER)


if __name__ == "__main__":
    unittest.main()
