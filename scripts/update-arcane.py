"""Update Atlas' pinned Arcane image without crossing major versions."""

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
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
MODULE_FILE = ROOT / "modules" / "atlas" / "arcane.nix"
BACKUP_SCRIPT = ROOT / "scripts" / "backup-arcane.sh"
MODULE_RELATIVE_PATH = "modules/atlas/arcane.nix"
IMAGE_REPOSITORY = "ghcr.io/getarcaneapp/manager"
RELEASES_URL = "https://api.github.com/repos/getarcaneapp/arcane/releases?per_page=100"
USER_AGENT = "juanqp07-nixos-arcane-updater/1.0"
VERSION_PATTERN = re.compile(r"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
DIGEST_PATTERN = re.compile(r"^sha256:[0-9a-f]{64}$")
IMAGE_PATTERN = re.compile(
    r'^(?P<prefix>[ \t]*image[ \t]*=[ \t]*")'
    r"ghcr\.io/getarcaneapp/manager:(?P<tag>v[0-9]+\.[0-9]+\.[0-9]+)@"
    r"(?P<digest>sha256:[0-9a-f]{64})"
    r'(?P<suffix>"[ \t]*;[ \t]*)$',
    re.MULTILINE,
)


class UpdateError(RuntimeError):
    """Raised when an Arcane update cannot be completed safely."""


def parse_version(tag: str) -> tuple[int, int, int]:
    """Parse a stable vMAJOR.MINOR.PATCH release tag."""
    match = VERSION_PATTERN.fullmatch(tag)
    if match is None:
        raise UpdateError(f"Arcane release tag is not stable SemVer: {tag!r}")
    return tuple(int(part) for part in match.groups())


def update_kind(current: tuple[int, int, int], latest: tuple[int, int, int]) -> str:
    """Classify a release without silently crossing a major-version boundary."""
    if latest <= current:
        return "current"
    if latest[0] != current[0]:
        return "major"
    return "same-major"


def read_arcane_image(content: str) -> tuple[str, str]:
    """Return the one pinned Arcane Manager tag and digest in the Nix module."""
    matches = list(IMAGE_PATTERN.finditer(content))
    if len(matches) != 1:
        raise UpdateError(
            "Expected exactly one pinned ghcr.io/getarcaneapp/manager image "
            f"in {MODULE_RELATIVE_PATH}; found {len(matches)}."
        )
    match = matches[0]
    return match.group("tag"), match.group("digest")


def replace_arcane_image(content: str, tag: str, digest: str) -> str:
    """Replace only the Arcane Manager tag and digest."""
    parse_version(tag)
    if not DIGEST_PATTERN.fullmatch(digest):
        raise UpdateError(f"Invalid GHCR digest for Arcane: {digest!r}")

    matches = list(IMAGE_PATTERN.finditer(content))
    if len(matches) != 1:
        raise UpdateError(
            f"Expected exactly one pinned Arcane Manager image; found {len(matches)}."
        )

    match = matches[0]
    replacement = (
        f"{match.group('prefix')}{IMAGE_REPOSITORY}:{tag}@{digest}"
        f"{match.group('suffix')}"
    )
    return content[: match.start()] + replacement + content[match.end() :]


def select_latest_same_major_release(current_tag: str, releases: list[str]) -> str:
    """Choose the newest stable release that stays on the installed major."""
    current_version = parse_version(current_tag)
    compatible_versions: list[tuple[tuple[int, int, int], str]] = []

    for tag in releases:
        try:
            version = parse_version(tag)
        except UpdateError:
            # Ignore non-SemVer tags rather than guessing their ordering.
            continue
        if version[0] == current_version[0] and version > current_version:
            compatible_versions.append((version, tag))

    if not compatible_versions:
        return current_tag
    return max(compatible_versions, key=lambda item: item[0])[1]


def fetch_stable_releases() -> list[str]:
    """Read stable, published Arcane releases from GitHub."""
    request = Request(
        RELEASES_URL,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": USER_AGENT,
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urlopen(request, timeout=20) as response:
        releases = json.load(response)

    if not isinstance(releases, list):
        raise UpdateError("GitHub returned an invalid Arcane releases response.")

    tags: list[str] = []
    for release in releases:
        if not isinstance(release, dict):
            continue
        if release.get("draft") or release.get("prerelease"):
            continue
        tag = release.get("tag_name")
        if isinstance(tag, str):
            try:
                parse_version(tag)
            except UpdateError:
                continue
            tags.append(tag)

    if not tags:
        raise UpdateError("GitHub did not return any stable Arcane SemVer releases.")
    return tags


def fetch_registry_digest(tag: str) -> str:
    """Reuse the repository's authenticated OCI registry digest resolver."""
    script_path = ROOT / "scripts" / "update-docker-digests.py"
    spec = importlib.util.spec_from_file_location("update_docker_digests", script_path)
    if spec is None or spec.loader is None:
        raise UpdateError("Could not load the shared OCI digest resolver.")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.fetch_digest(IMAGE_REPOSITORY, tag)


def ensure_module_is_clean() -> None:
    """Do not overwrite a user edit or staged change to the Arcane module."""
    result = subprocess.run(
        ["git", "status", "--porcelain=v1", "--", MODULE_RELATIVE_PATH],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    if result.stdout.strip():
        raise UpdateError(
            f"{MODULE_RELATIVE_PATH} has local changes. Commit or stash them "
            "before updating Arcane."
        )


def confirm_update(current_tag: str, latest_tag: str, automatic: bool) -> bool:
    """Require confirmation unless the caller explicitly selected --yes."""
    if automatic:
        print("Automatic mode: accepting this same-major Arcane update.")
        return True

    try:
        answer = (
            input(f"Update Arcane {current_tag} to {latest_tag}? [s/N] ")
            .strip()
            .lower()
        )
    except EOFError:
        answer = ""
    return answer in {"s", "si", "sí", "y", "yes"}


def create_backup() -> None:
    """Back up Arcane's database, app data, projects and environment files."""
    if not BACKUP_SCRIPT.is_file():
        raise UpdateError(f"Backup script not found: {BACKUP_SCRIPT}")
    subprocess.run(
        ["sudo", "bash", str(BACKUP_SCRIPT)],
        cwd=ROOT,
        check=True,
    )


def atomic_write(path: Path, content: str) -> None:
    """Replace the Nix module atomically and preserve its permissions."""
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
            "Check the latest stable Arcane release and update Atlas' pinned "
            "image only when the major version stays the same."
        )
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="accept same-major updates without an interactive prompt",
    )
    arguments = parser.parse_args(argv)

    try:
        ensure_module_is_clean()
        original_content = MODULE_FILE.read_text(encoding="utf-8")
        current_tag, _current_digest = read_arcane_image(original_content)
        releases = fetch_stable_releases()
        current_version = parse_version(current_tag)
        newest_release = max(releases, key=parse_version)
        newest_version = parse_version(newest_release)

        if newest_version[0] > current_version[0]:
            print(
                f"Arcane {newest_release} is a major upgrade from {current_tag}. "
                "It will not be installed automatically."
            )
            print(
                "Major upgrades require the migration checklist in "
                "docs/arcane-updates.md and the official Arcane v3 guide."
            )

        latest_tag = select_latest_same_major_release(current_tag, releases)
        if latest_tag == current_tag:
            print(
                f"No newer stable Arcane release is available within major "
                f"version {current_version[0]}; keeping {current_tag}."
            )
            return 0

        if not confirm_update(current_tag, latest_tag, arguments.yes):
            print("Arcane update skipped; the pinned image was not changed.")
            return 0

        latest_digest = fetch_registry_digest(latest_tag)
        updated_content = replace_arcane_image(
            original_content,
            latest_tag,
            latest_digest,
        )
        if updated_content == original_content:
            print(f"Arcane {latest_tag} is already pinned to the current digest.")
            return 0

        print(f"Creating a verified backup before updating Arcane {current_tag}...")
        create_backup()

        # Recheck both the worktree and source after the backup. Never overwrite
        # changes made by another process while the registry was being queried.
        ensure_module_is_clean()
        current_content = MODULE_FILE.read_text(encoding="utf-8")
        if current_content != original_content:
            raise UpdateError(
                "The Arcane module changed during the update check; no edit was made."
            )

        atomic_write(MODULE_FILE, updated_content)
        print(f"Arcane image updated: {current_tag} -> {latest_tag}.")
        print(
            f"GHCR digest pinned. Review and commit the change in "
            f"{MODULE_RELATIVE_PATH}; nix-maintain does not commit files."
        )
        return 0

    except (OSError, ValueError, UpdateError, subprocess.CalledProcessError) as error:
        print(f"Arcane update skipped: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
