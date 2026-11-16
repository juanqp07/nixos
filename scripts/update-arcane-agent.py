"""Keep Pico's pinned Arcane Direct Agent aligned with Atlas' Manager."""

from __future__ import annotations

import argparse
import importlib.util
import os
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANAGER_FILE = ROOT / "modules" / "atlas-docker.nix"
AGENT_FILE = ROOT / "hosts" / "zimablade" / "configuration.nix"
BACKUP_SCRIPT = ROOT / "scripts" / "backup-arcane-agent.sh"
MANAGER_RELATIVE_PATH = "modules/atlas-docker.nix"
AGENT_RELATIVE_PATH = "hosts/zimablade/configuration.nix"
AGENT_IMAGE_REPOSITORY = "ghcr.io/getarcaneapp/agent"
VERSION_PATTERN = re.compile(r"^v(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")
DIGEST_PATTERN = re.compile(r"^sha256:[0-9a-f]{64}$")
MANAGER_IMAGE_PATTERN = re.compile(
    r'^[ \\t]*image[ \\t]*=[ \\t]*"ghcr\\.io/getarcaneapp/manager:'
    r"(?P<tag>v[0-9]+\\.[0-9]+\\.[0-9]+)@"
    r"(?P<digest>sha256:[0-9a-f]{64})"
    r'"[ \\t]*;[ \\t]*$',
    re.MULTILINE,
)
AGENT_IMAGE_PATTERN = re.compile(
    r'^(?P<prefix>[ \\t]*image[ \\t]*=[ \\t]*")'
    r"ghcr\\.io/getarcaneapp/agent:(?P<tag>v[0-9]+\\.[0-9]+\\.[0-9]+)@"
    r"(?P<digest>sha256:[0-9a-f]{64})"
    r'(?P<suffix>"[ \\t]*;[ \\t]*)$',
    re.MULTILINE,
)


class UpdateError(RuntimeError):
    """Raised when an Arcane Agent update cannot be completed safely."""


def parse_version(tag: str) -> tuple[int, int, int]:
    """Parse a stable vMAJOR.MINOR.PATCH release tag."""
    match = VERSION_PATTERN.fullmatch(tag)
    if match is None:
        raise UpdateError(f"Arcane version is not stable SemVer: {tag!r}")
    return tuple(int(part) for part in match.groups())


def read_manager_version(content: str) -> str:
    """Read the single pinned Arcane Manager version used as the source of truth."""
    matches = list(MANAGER_IMAGE_PATTERN.finditer(content))
    if len(matches) != 1:
        raise UpdateError(
            "Expected exactly one pinned Arcane Manager image in "
            f"{MANAGER_RELATIVE_PATH}; found {len(matches)}."
        )
    return matches[0].group("tag")


def read_agent_image(content: str) -> tuple[str, str]:
    """Return the pinned Direct Agent tag and digest."""
    matches = list(AGENT_IMAGE_PATTERN.finditer(content))
    if len(matches) != 1:
        raise UpdateError(
            "Expected exactly one pinned Arcane Direct Agent image in "
            f"{AGENT_RELATIVE_PATH}; found {len(matches)}."
        )
    match = matches[0]
    return match.group("tag"), match.group("digest")


def agent_sync_status(manager_tag: str, agent_tag: str) -> str:
    """Classify the agent relative to the Manager without downgrades or major jumps."""
    manager_version = parse_version(manager_tag)
    agent_version = parse_version(agent_tag)

    if manager_version[0] != agent_version[0]:
        return "major"
    if manager_version > agent_version:
        return "update"
    if manager_version < agent_version:
        return "agent-ahead"
    return "current"


def replace_agent_image(content: str, tag: str, digest: str) -> str:
    """Replace only the pinned Direct Agent tag and registry digest."""
    parse_version(tag)
    if not DIGEST_PATTERN.fullmatch(digest):
        raise UpdateError(f"Invalid GHCR digest for Arcane Agent: {digest!r}")

    matches = list(AGENT_IMAGE_PATTERN.finditer(content))
    if len(matches) != 1:
        raise UpdateError(
            f"Expected exactly one pinned Arcane Direct Agent image; found {len(matches)}."
        )

    match = matches[0]
    replacement = (
        f"{match.group('prefix')}{AGENT_IMAGE_REPOSITORY}:{tag}@{digest}"
        f"{match.group('suffix')}"
    )
    return content[: match.start()] + replacement + content[match.end() :]


def fetch_registry_digest(tag: str) -> str:
    """Reuse the repository's shared OCI registry digest resolver."""
    script_path = ROOT / "scripts" / "update-docker-digests.py"
    spec = importlib.util.spec_from_file_location("update_docker_digests", script_path)
    if spec is None or spec.loader is None:
        raise UpdateError("Could not load the shared OCI digest resolver.")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.fetch_digest(AGENT_IMAGE_REPOSITORY, tag)


def ensure_modules_are_clean() -> None:
    """Never overwrite edits to either the Agent pin or its Manager source of truth."""
    result = subprocess.run(
        [
            "git",
            "status",
            "--porcelain=v1",
            "--",
            MANAGER_RELATIVE_PATH,
            AGENT_RELATIVE_PATH,
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    if result.stdout.strip():
        raise UpdateError(
            "The Arcane Manager or Direct Agent declaration has local changes. "
            "Commit or stash them before synchronizing the Agent."
        )


def confirm_update(manager_tag: str, agent_tag: str, automatic: bool) -> bool:
    """Require confirmation unless the caller explicitly selected --yes."""
    if automatic:
        print("Automatic mode: accepting this same-major Arcane Agent update.")
        return True

    try:
        answer = (
            input(
                f"Update Pico's Arcane Direct Agent {agent_tag} to match "
                f"Atlas Manager {manager_tag}? [s/N] "
            )
            .strip()
            .lower()
        )
    except EOFError:
        answer = ""
    return answer in {"s", "si", "sí", "y", "yes"}


def create_backup() -> None:
    """Back up the Agent volume, enrollment environment and Nix declaration."""
    if not BACKUP_SCRIPT.is_file():
        raise UpdateError(f"Backup script not found: {BACKUP_SCRIPT}")
    subprocess.run(
        ["sudo", "bash", str(BACKUP_SCRIPT)],
        cwd=ROOT,
        check=True,
    )


def atomic_write(path: Path, content: str) -> None:
    """Replace the Nix configuration atomically and preserve its permissions."""
    mode = stat.S_IMODE(path.stat().st_mode)
    temporary_path: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as temporary_file:
            temporary_file.write(content)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
            temporary_path = temporary_file.name
        os.chmod(temporary_path, mode)
        os.replace(temporary_path, path)
    finally:
        if temporary_path and os.path.exists(temporary_path):
            os.unlink(temporary_path)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Synchronize Pico's pinned Arcane Direct Agent with the Manager "
            "version declared for Atlas, without crossing major versions."
        )
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="accept same-major Agent updates without an interactive prompt",
    )
    arguments = parser.parse_args(argv)

    try:
        ensure_modules_are_clean()
        manager_content = MANAGER_FILE.read_text(encoding="utf-8")
        agent_content = AGENT_FILE.read_text(encoding="utf-8")
        manager_tag = read_manager_version(manager_content)
        agent_tag, _agent_digest = read_agent_image(agent_content)
        status = agent_sync_status(manager_tag, agent_tag)

        if status == "current":
            print(
                f"Arcane Direct Agent {agent_tag} already matches the "
                f"Atlas Manager pin; no Agent update is needed."
            )
            return 0

        if status == "major":
            print(
                f"Arcane Manager {manager_tag} and Direct Agent {agent_tag} "
                "belong to different major versions."
            )
            print(
                "Automatic synchronization is disabled for major migrations. "
                "Follow docs/arcane-updates.md and the official Arcane migration guide."
            )
            return 0

        if status == "agent-ahead":
            print(
                f"Arcane Direct Agent {agent_tag} is newer than the pinned "
                f"Atlas Manager {manager_tag}; refusing to downgrade it."
            )
            return 0

        if not confirm_update(manager_tag, agent_tag, arguments.yes):
            print("Arcane Direct Agent update skipped; the pinned image was not changed.")
            return 0

        latest_digest = fetch_registry_digest(manager_tag)
        updated_content = replace_agent_image(agent_content, manager_tag, latest_digest)
        if updated_content == agent_content:
            print(f"Arcane Direct Agent {manager_tag} is already pinned to this digest.")
            return 0

        print(f"Creating a backup before updating Pico's Arcane Agent {agent_tag}...")
        create_backup()

        # Recheck the worktree and source after the backup. Never overwrite edits
        # made while the registry was being queried or the backup was running.
        ensure_modules_are_clean()
        current_manager = MANAGER_FILE.read_text(encoding="utf-8")
        current_agent = AGENT_FILE.read_text(encoding="utf-8")
        if current_manager != manager_content or current_agent != agent_content:
            raise UpdateError(
                "The Manager or Direct Agent declaration changed during the update; "
                "no edit was made."
            )

        atomic_write(AGENT_FILE, updated_content)
        print(f"Arcane Direct Agent image updated: {agent_tag} -> {manager_tag}.")
        print(
            f"GHCR digest pinned. Review and commit the change in "
            f"{AGENT_RELATIVE_PATH}; nix-maintain does not commit files."
        )
        return 0

    except (OSError, ValueError, UpdateError, subprocess.CalledProcessError) as error:
        print(f"Arcane Direct Agent update skipped: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
