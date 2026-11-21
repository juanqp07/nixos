"""Keep Pico's pinned Arcane Agent aligned with the running Atlas Manager."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
AGENT_FILE = ROOT / "hosts" / "zimablade" / "configuration.nix"
BACKUP_SCRIPT = ROOT / "scripts" / "backup-arcane-agent.sh"
AGENT_RELATIVE_PATH = "hosts/zimablade/configuration.nix"
AGENT_IMAGE_REPOSITORY = "ghcr.io/getarcaneapp/agent"
VERSION_PATTERN = re.compile(r"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
DIGEST_PATTERN = re.compile(r"^sha256:[0-9a-f]{64}$")
MANAGER_API_URL_PATTERN = re.compile(
    r'^[ \t]*ARCANE_MANAGER_API_URL[ \t]*=[ \t]*'
    r'"(?P<url>https?://[^"]+)"[ \t]*;[ \t]*
MANAGER_API_TIMEOUT = 10


class UpdateError(RuntimeError):
    """Raised when an Arcane Agent update cannot be completed safely."""


def parse_version(tag: str) -> tuple[int, int, int]:
    """Parse a stable vMAJOR.MINOR.PATCH release tag."""
    match = VERSION_PATTERN.fullmatch(tag)
    if match is None:
        raise UpdateError(f"Arcane version is not stable SemVer: {tag!r}")
    return tuple(int(part) for part in match.groups())


def read_manager_api_url(content: str) -> str:
    """Read the configured Atlas Manager URL from Pico's Agent declaration."""
    matches = list(MANAGER_API_URL_PATTERN.finditer(content))
    if len(matches) != 1:
        raise UpdateError(
            "Expected exactly one ARCANE_MANAGER_API_URL in "
            f"{AGENT_RELATIVE_PATH}; found {len(matches)}."
        )

    url = matches[0].group("url")
    parsed = urlsplit(url)
    try:
        parsed.port
    except ValueError as error:
        raise UpdateError("ARCANE_MANAGER_API_URL contains an invalid port.") from error

    if (
        parsed.scheme not in {"http", "https"}
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
    ):
        raise UpdateError(
            "ARCANE_MANAGER_API_URL must be an HTTP(S) base URL without "
            "credentials, query parameters or fragments."
        )
    return url.rstrip("/")


def fetch_manager_version(manager_api_url: str) -> str:
    """Read the running Manager version from Arcane's public app-version endpoint."""
    endpoint = f"{manager_api_url}/api/app/version"
    request = Request(
        endpoint,
        headers={
            "Accept": "application/json",
            "User-Agent": "juanqp07-nixos-arcane-agent-updater/1.0",
        },
    )
    try:
        with urlopen(request, timeout=MANAGER_API_TIMEOUT) as response:
            payload = json.load(response)
    except (OSError, TimeoutError, ValueError) as error:
        raise UpdateError(
            f"Could not query the running Arcane Manager at {endpoint}: {error}"
        ) from error

    if not isinstance(payload, dict):
        raise UpdateError("Arcane Manager returned an invalid version response.")
    manager_tag = payload.get("currentVersion")
    if not isinstance(manager_tag, str):
        raise UpdateError(
            "Arcane Manager response does not contain a string currentVersion."
        )

    parse_version(manager_tag)
    return manager_tag


def read_agent_image(content: str) -> tuple[str, str]:
    """Return the pinned Arcane Agent tag and digest."""
    matches = list(AGENT_IMAGE_PATTERN.finditer(content))
    if len(matches) != 1:
        raise UpdateError(
            "Expected exactly one pinned Arcane Agent image in "
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
    """Replace only the pinned Arcane Agent tag and registry digest."""
    parse_version(tag)
    if not DIGEST_PATTERN.fullmatch(digest):
        raise UpdateError(f"Invalid registry digest for Arcane Agent: {digest!r}")

    matches = list(AGENT_IMAGE_PATTERN.finditer(content))
    if len(matches) != 1:
        raise UpdateError(
            f"Expected exactly one pinned Arcane Agent image; found {len(matches)}."
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


def ensure_agent_config_is_clean() -> None:
    """Never overwrite local edits to the Agent declaration."""
    result = subprocess.run(
        [
            "git",
            "status",
            "--porcelain=v1",
            "--",
            AGENT_RELATIVE_PATH,
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    if result.stdout.strip():
        raise UpdateError(
            "The Arcane Agent declaration has local changes. "
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
                f"Update Pico's Arcane Agent {agent_tag} to match "
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
            "Synchronize Pico's pinned Arcane Agent with the running Atlas "
            "Manager version, without crossing major versions."
        )
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="accept same-major Agent updates without an interactive prompt",
    )
    arguments = parser.parse_args(argv)

    try:
        ensure_agent_config_is_clean()
        agent_content = AGENT_FILE.read_text(encoding="utf-8")
        manager_api_url = read_manager_api_url(agent_content)
        manager_tag = fetch_manager_version(manager_api_url)
        agent_tag, _agent_digest = read_agent_image(agent_content)
        print(f"Running Atlas Arcane Manager version: {manager_tag}.")
        status = agent_sync_status(manager_tag, agent_tag)

        if status == "current":
            print(
                f"Arcane Agent {agent_tag} already matches the running "
                "Atlas Manager; no Agent update is needed."
            )
            return 0

        if status == "major":
            print(
                f"Running Arcane Manager {manager_tag} and Arcane Agent {agent_tag} "
                "belong to different major versions."
            )
            print(
                "Automatic synchronization is disabled for major migrations. "
                "Follow docs/arcane-updates.md and the official Arcane migration guide."
            )
            return 0

        if status == "agent-ahead":
            print(
                f"Arcane Agent {agent_tag} is newer than the running "
                f"Atlas Manager {manager_tag}; refusing to downgrade it."
            )
            return 0

        if not confirm_update(manager_tag, agent_tag, arguments.yes):
            print("Arcane Agent update skipped; the pinned image was not changed.")
            return 0

        latest_digest = fetch_registry_digest(manager_tag)
        updated_content = replace_agent_image(agent_content, manager_tag, latest_digest)
        if updated_content == agent_content:
            print(f"Arcane Agent {manager_tag} is already pinned to this digest.")
            return 0

        print(f"Creating a backup before updating Pico's Arcane Agent {agent_tag}...")
        create_backup()

        # Recheck the Agent declaration after the backup; never overwrite edits
        # made while the registry was being queried or the backup was running.
        ensure_agent_config_is_clean()
        current_agent = AGENT_FILE.read_text(encoding="utf-8")
        if current_agent != agent_content:
            raise UpdateError(
                "The Arcane Agent declaration changed during the update; "
                "no edit was made."
            )
        current_manager_tag = fetch_manager_version(manager_api_url)
        if current_manager_tag != manager_tag:
            raise UpdateError(
                "Atlas Manager version changed during the Agent update "
                f"({manager_tag} -> {current_manager_tag}); retry the maintenance."
            )

        atomic_write(AGENT_FILE, updated_content)
        print(f"Arcane Agent image updated: {agent_tag} -> {manager_tag}.")
        print(
            f"Image registry digest pinned. Review and commit the change in "
            f"{AGENT_RELATIVE_PATH}; nix-maintain does not commit files."
        )
        return 0

    except (OSError, ValueError, UpdateError, subprocess.CalledProcessError) as error:
        print(f"Arcane Agent update skipped: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
,
    re.MULTILINE,
)
MANAGER_API_TIMEOUT = 10


class UpdateError(RuntimeError):
    """Raised when an Arcane Agent update cannot be completed safely."""


def parse_version(tag: str) -> tuple[int, int, int]:
    """Parse a stable vMAJOR.MINOR.PATCH release tag."""
    match = VERSION_PATTERN.fullmatch(tag)
    if match is None:
        raise UpdateError(f"Arcane version is not stable SemVer: {tag!r}")
    return tuple(int(part) for part in match.groups())


def read_manager_api_url(content: str) -> str:
    """Read the configured Atlas Manager URL from Pico's Agent declaration."""
    matches = list(MANAGER_API_URL_PATTERN.finditer(content))
    if len(matches) != 1:
        raise UpdateError(
            "Expected exactly one ARCANE_MANAGER_API_URL in "
            f"{AGENT_RELATIVE_PATH}; found {len(matches)}."
        )

    url = matches[0].group("url")
    parsed = urlsplit(url)
    try:
        _port = parsed.port
    except ValueError as error:
        raise UpdateError("ARCANE_MANAGER_API_URL contains an invalid port.") from error

    if (
        parsed.scheme not in {"http", "https"}
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
    ):
        raise UpdateError(
            "ARCANE_MANAGER_API_URL must be an HTTP(S) base URL without "
            "credentials, query parameters or fragments."
        )
    return url.rstrip("/")


def fetch_manager_version(manager_api_url: str) -> str:
    """Read the running Manager version from Arcane's public app-version endpoint."""
    endpoint = f"{manager_api_url}/api/app/version"
    request = Request(
        endpoint,
        headers={
            "Accept": "application/json",
            "User-Agent": "juanqp07-nixos-arcane-agent-updater/1.0",
        },
    )
    try:
        with urlopen(request, timeout=MANAGER_API_TIMEOUT) as response:
            payload = json.load(response)
    except (OSError, TimeoutError, ValueError) as error:
        raise UpdateError(
            f"Could not query the running Arcane Manager at {endpoint}: {error}"
        ) from error

    if not isinstance(payload, dict):
        raise UpdateError("Arcane Manager returned an invalid version response.")
    manager_tag = payload.get("currentVersion")
    if not isinstance(manager_tag, str):
        raise UpdateError(
            "Arcane Manager response does not contain a string currentVersion."
        )

    parse_version(manager_tag)
    return manager_tag


def read_agent_image(content: str) -> tuple[str, str]:
    """Return the pinned Arcane Agent tag and digest."""
    matches = list(AGENT_IMAGE_PATTERN.finditer(content))
    if len(matches) != 1:
        raise UpdateError(
            "Expected exactly one pinned Arcane Agent image in "
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
    """Replace only the pinned Arcane Agent tag and registry digest."""
    parse_version(tag)
    if not DIGEST_PATTERN.fullmatch(digest):
        raise UpdateError(f"Invalid registry digest for Arcane Agent: {digest!r}")

    matches = list(AGENT_IMAGE_PATTERN.finditer(content))
    if len(matches) != 1:
        raise UpdateError(
            f"Expected exactly one pinned Arcane Agent image; found {len(matches)}."
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


def ensure_agent_config_is_clean() -> None:
    """Never overwrite local edits to the Agent declaration."""
    result = subprocess.run(
        [
            "git",
            "status",
            "--porcelain=v1",
            "--",
            AGENT_RELATIVE_PATH,
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    if result.stdout.strip():
        raise UpdateError(
            "The Arcane Agent declaration has local changes. "
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
                f"Update Pico's Arcane Agent {agent_tag} to match "
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
            "Synchronize Pico's pinned Arcane Agent with the running Atlas "
            "Manager version, without crossing major versions."
        )
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="accept same-major Agent updates without an interactive prompt",
    )
    arguments = parser.parse_args(argv)

    try:
        ensure_agent_config_is_clean()
        agent_content = AGENT_FILE.read_text(encoding="utf-8")
        manager_api_url = read_manager_api_url(agent_content)
        manager_tag = fetch_manager_version(manager_api_url)
        agent_tag, _agent_digest = read_agent_image(agent_content)
        print(f"Running Atlas Arcane Manager version: {manager_tag}.")
        status = agent_sync_status(manager_tag, agent_tag)

        if status == "current":
            print(
                f"Arcane Agent {agent_tag} already matches the running "
                "Atlas Manager; no Agent update is needed."
            )
            return 0

        if status == "major":
            print(
                f"Running Arcane Manager {manager_tag} and Arcane Agent {agent_tag} "
                "belong to different major versions."
            )
            print(
                "Automatic synchronization is disabled for major migrations. "
                "Follow docs/arcane-updates.md and the official Arcane migration guide."
            )
            return 0

        if status == "agent-ahead":
            print(
                f"Arcane Agent {agent_tag} is newer than the running "
                f"Atlas Manager {manager_tag}; refusing to downgrade it."
            )
            return 0

        if not confirm_update(manager_tag, agent_tag, arguments.yes):
            print("Arcane Agent update skipped; the pinned image was not changed.")
            return 0

        latest_digest = fetch_registry_digest(manager_tag)
        updated_content = replace_agent_image(agent_content, manager_tag, latest_digest)
        if updated_content == agent_content:
            print(f"Arcane Agent {manager_tag} is already pinned to this digest.")
            return 0

        print(f"Creating a backup before updating Pico's Arcane Agent {agent_tag}...")
        create_backup()

        # Recheck the Agent declaration after the backup; never overwrite edits
        # made while the registry was being queried or the backup was running.
        ensure_agent_config_is_clean()
        current_agent = AGENT_FILE.read_text(encoding="utf-8")
        if current_agent != agent_content:
            raise UpdateError(
                "The Arcane Agent declaration changed during the update; "
                "no edit was made."
            )

        atomic_write(AGENT_FILE, updated_content)
        print(f"Arcane Agent image updated: {agent_tag} -> {manager_tag}.")
        print(
            f"Image registry digest pinned. Review and commit the change in "
            f"{AGENT_RELATIVE_PATH}; nix-maintain does not commit files."
        )
        return 0

    except (OSError, ValueError, UpdateError, subprocess.CalledProcessError) as error:
        print(f"Arcane Agent update skipped: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
