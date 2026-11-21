"""Offline tests for the Arcane Agent updater."""

from __future__ import annotations

import importlib.util
import io
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.request import Request

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "update-arcane-agent.py"
SPEC = importlib.util.spec_from_file_location("update_arcane_agent", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load Arcane Agent updater from {SCRIPT}")

update_agent = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(update_agent)

OLD_DIGEST = "sha256:" + "a" * 64
NEW_DIGEST = "sha256:" + "b" * 64
MANAGER_URL = "http://192.168.1.143:3552"
AGENT = (
    "      containers.arcane-agent = {\n"
    f'        image = "ghcr.io/getarcaneapp/agent:v3.0.1@{OLD_DIGEST}";\n'
    "        autoStart = true;\n"
    "        environment = {\n"
    f'          ARCANE_MANAGER_API_URL = "{MANAGER_URL}";\n'
    "        };\n"
    "      };\n"
)


class ArcaneAgentVersionTests(unittest.TestCase):
    def test_parse_stable_semver(self) -> None:
        self.assertEqual(update_agent.parse_version("v3.1.1"), (3, 1, 1))

    def test_parse_rejects_unstable_or_invalid_versions(self) -> None:
        for tag in ("v3.1.1-rc.1", "3.1.1", "latest", "v3.1"):
            with self.subTest(tag=tag), self.assertRaises(update_agent.UpdateError):
                update_agent.parse_version(tag)

    def test_reads_manager_api_url_from_agent_config(self) -> None:
        self.assertEqual(update_agent.read_manager_api_url(AGENT), MANAGER_URL)

    def test_rejects_missing_or_duplicate_manager_api_url(self) -> None:
        with self.assertRaises(update_agent.UpdateError):
            update_agent.read_manager_api_url("services.arcane.enable = true;\n")
        with self.assertRaises(update_agent.UpdateError):
            update_agent.read_manager_api_url(AGENT + AGENT)

    def test_rejects_unsafe_manager_api_url(self) -> None:
        invalid_config = AGENT.replace(MANAGER_URL, "ftp://atlas:3552")
        with self.assertRaises(update_agent.UpdateError):
            update_agent.read_manager_api_url(invalid_config)

    def test_fetches_running_manager_version_from_public_endpoint(self) -> None:
        response = io.BytesIO(b'{"currentVersion":"v3.1.1"}')
        with patch.object(update_agent, "urlopen", return_value=response) as mocked:
            self.assertEqual(update_agent.fetch_manager_version(MANAGER_URL), "v3.1.1")
        request = mocked.call_args.args[0]
        self.assertIsInstance(request, Request)
        self.assertEqual(request.full_url, f"{MANAGER_URL}/api/app/version")
        self.assertEqual(mocked.call_args.kwargs["timeout"], 10)

    def test_rejects_manager_response_without_current_version(self) -> None:
        response = io.BytesIO(b'{"displayVersion":"3.1.1"}')
        with patch.object(update_agent, "urlopen", return_value=response):
            with self.assertRaises(update_agent.UpdateError):
                update_agent.fetch_manager_version(MANAGER_URL)

    def test_rejects_invalid_manager_version(self) -> None:
        response = io.BytesIO(b'{"currentVersion":"next"}')
        with patch.object(update_agent, "urlopen", return_value=response):
            with self.assertRaises(update_agent.UpdateError):
                update_agent.fetch_manager_version(MANAGER_URL)

    def test_manager_unreachable_fails_closed(self) -> None:
        with patch.object(
            update_agent,
            "urlopen",
            side_effect=OSError("connection refused"),
        ):
            with self.assertRaisesRegex(update_agent.UpdateError, "Could not query"):
                update_agent.fetch_manager_version(MANAGER_URL)

    def test_agent_behind_running_manager_on_same_major_is_updated(self) -> None:
        self.assertEqual(update_agent.agent_sync_status("v3.1.1", "v3.0.1"), "update")

    def test_major_mismatch_requires_manual_migration(self) -> None:
        self.assertEqual(update_agent.agent_sync_status("v3.1.1", "v2.17.3"), "major")

    def test_agent_ahead_of_manager_is_never_downgraded(self) -> None:
        self.assertEqual(
            update_agent.agent_sync_status("v3.0.1", "v3.1.1"),
            "agent-ahead",
        )

    def test_matching_versions_need_no_update(self) -> None:
        self.assertEqual(update_agent.agent_sync_status("v3.1.1", "v3.1.1"), "current")

    def test_reads_agent_tag_and_digest(self) -> None:
        self.assertEqual(update_agent.read_agent_image(AGENT), ("v3.0.1", OLD_DIGEST))

    def test_updates_only_agent_tag_and_digest(self) -> None:
        updated = update_agent.replace_agent_image(AGENT, "v3.1.1", NEW_DIGEST)
        self.assertIn(f"ghcr.io/getarcaneapp/agent:v3.1.1@{NEW_DIGEST}", updated)
        self.assertIn("autoStart = true;", updated)
        self.assertIn(f'ARCANE_MANAGER_API_URL = "{MANAGER_URL}";', updated)
        self.assertNotIn(OLD_DIGEST, updated)

    def test_rejects_invalid_digest(self) -> None:
        with self.assertRaises(update_agent.UpdateError):
            update_agent.replace_agent_image(AGENT, "v3.1.1", "not-a-digest")

    def test_rejects_missing_or_duplicate_agent_image(self) -> None:
        with self.assertRaises(update_agent.UpdateError):
            update_agent.read_agent_image("services.arcane.enable = true;\n")
        with self.assertRaises(update_agent.UpdateError):
            update_agent.read_agent_image(AGENT + AGENT)


if __name__ == "__main__":
    unittest.main()
