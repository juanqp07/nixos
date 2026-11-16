#!/usr/bin/env python3
"""Update Atlas's pinned Arcane image within the current major release."""

from __future__ import annotations

import json
import os
import re
import stat
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "modules" / "atlas-docker.nix"
RELEASES_URL = "https://api.github.com/repos/getarcaneapp/arcane/releases?per_page=100"
REGISTRY = "https://ghcr.io"
REPOSITORY = "getarcaneapp/manager"
USER_AGENT = "juanqp07-nixos-arcane-updater/1.0"
ACCEPT_MANIFESTS = (
    "application/vnd.oci.image.index.v1+json, "
    "application/vnd.docker.distribution.manifest.list.v2+json, "
    "application/vnd.oci.image.manifest.v1+json, "
    "application/vnd.docker.distribution.manifest.v2+json"
)
VERSION_RE = re.compile(r"^v(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)$")
DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
IMAGE_RE = re.compile(
    r'^(?P<prefix>[ \t]*image[ \t]*=[ \t]*")'
    r'(?P<repository>ghcr\.io/getarcaneapp/manager:)'
    r'(?P<tag>v\d+\.\d+\.\d+)'
    r'(?P<digest>@sha256:[0-9a-f]{64})'
    r'(?P<suffix>";)$',
    re.MULTILINE,
)


def parse_version(tag: str) -> tuple[int, int, int] | None:
    match = VERSION_RE.fullmatch(tag)
    if match is None:
        return None
    return tuple(int(match.group(part)) for part in ("major", "minor", "patch"))


def latest_stable_release(
    releases: list[dict[str, Any]], major: int | None = None
) -> tuple[str, tuple[int, int, int]] | None:
    candidates: list[tuple[tuple[int, int, int], str]] = []
    for release in releases:
        if release.get("draft") is not False or release.get("prerelease") is not False:
            continue
        tag = release.get("tag_name")
        if not isinstance(tag, str):
            continue
        version = parse_version(tag)
        if version is None or (major is not None and version[0] != major):
            continue
        candidates.append((version, tag))

    if not candidates:
        return None

    version, tag = max(candidates)
    return tag, version


def _next_link(link_header: str | None) -> str | None:
    if not link_header:
        return None
    for entry in link_header.split(","):
        if 'rel="next"' in entry:
            match = re.search(r"<([^>]+)>", entry)
            if match:
                return match.group(1)
    return None


def fetch_releases() -> list[dict[str, Any]]:
    url: str | None = RELEASES_URL
    releases: list[dict[str, Any]] = []
    pages = 0

    while url is not None:
        pages += 1
        if pages > 10:
            raise RuntimeError("GitHub releases pagination exceeded the safety limit")
        request = urllib.request.Request(
            url,
            headers={
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": USER_AGENT,
            },
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.load(response)
            if not isinstance(payload, list):
                raise ValueError("GitHub returned an unexpected releases payload")
            releases.extend(item for item in payload if isinstance(item, dict))
            url = _next_link(response.headers.get("Link"))

    return releases


def _read_json(url: str, headers: dict[str, str] | None = None) -> dict[str, Any]:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, **(headers or {})},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.load(response)
    if not isinstance(payload, dict):
        raise ValueError(f"Registry returned an invalid JSON object for {url}")
    return payload


def fetch_manifest_digest(tag: str) -> str:
    scope = urllib.parse.urlencode({"scope": f"repository:{REPOSITORY}:pull"})
    token_payload = _read_json(f"{REGISTRY}/token?{scope}")
    token = token_payload.get("token") or token_payload.get("access_token")
    if not isinstance(token, str) or not token:
        raise ValueError("GHCR did not issue an anonymous pull token")

    manifest_url = (
        f"{REGISTRY}/v2/{REPOSITORY}/manifests/{urllib.parse.quote(tag, safe='')}"
    )
    request = urllib.request.Request(
        manifest_url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": ACCEPT_MANIFESTS,
            "User-Agent": USER_AGENT,
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        digest = response.headers.get("Docker-Content-Digest")

    if not isinstance(digest, str) or not DIGEST_RE.fullmatch(digest):
        raise ValueError(f"GHCR returned no valid manifest digest for {tag}")
    return digest


def replace_image_reference(content: str, new_tag: str, digest: str) -> tuple[str, str]:
    if parse_version(new_tag) is None:
        raise ValueError(f"Invalid Arcane release tag: {new_tag}")
    if not DIGEST_RE.fullmatch(digest):
        raise ValueError("Refusing to write an invalid image digest")

    matches = list(IMAGE_RE.finditer(content))
    if len(matches) != 1:
        raise ValueError(
            "Expected exactly one pinned Arcane manager image in modules/atlas-docker.nix"
        )

    match = matches[0]
    old_tag = match.group("tag")
    old_reference = match.group("repository") + old_tag + match.group("digest")
    new_reference = match.group("repository") + new_tag + "@" + digest
    updated = content[: match.start()] + match.group("prefix") + new_reference + match.group("suffix") + content[match.end() :]
    return updated, old_reference


def module_has_local_changes() -> bool:
    import subprocess

    result = subprocess.run(
        ["git", "diff", "--quiet", "HEAD", "--", str(MODULE.relative_to(ROOT))],
        cwd=ROOT,
        check=False,
    )
    if result.returncode not in (0, 1):
        raise RuntimeError("Could not inspect the Git state of modules/atlas-docker.nix")
    return result.returncode == 1


def atomic_write(path: Path, content: str) -> None:
    mode = stat.S_IMODE(path.stat().st_mode)
    fd, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def main() -> int:
    try:
        if module_has_local_changes():
            print(
                "Arcane: se omite la actualización porque modules/atlas-docker.nix "
                "ya contiene cambios locales. No se sobrescriben."
            )
            return 0

        content = MODULE.read_text(encoding="utf-8")
        matches = list(IMAGE_RE.finditer(content))
        if len(matches) != 1:
            raise ValueError(
                "Expected exactly one pinned Arcane manager image in modules/atlas-docker.nix"
            )

        current_tag = matches[0].group("tag")
        current_version = parse_version(current_tag)
        if current_version is None:
            raise ValueError(f"Unsupported current Arcane tag: {current_tag}")

        releases = fetch_releases()
        latest_overall = latest_stable_release(releases)
        latest_compatible = latest_stable_release(releases, major=current_version[0])

        if latest_overall and latest_overall[1][0] > current_version[0]:
            print(
                f"Arcane: hay una versión mayor ({latest_overall[0]}), pero no se "
                "actualiza automáticamente. Requiere migración manual."
            )

        if latest_compatible is None or latest_compatible[1] <= current_version:
            print(f"Arcane: {current_tag} ya es la versión estable más reciente de la rama {current_version[0]}.")
            return 0

        new_tag = latest_compatible[0]
        digest = fetch_manifest_digest(new_tag)
        updated, _old_reference = replace_image_reference(content, new_tag, digest)
        if updated == content:
            print(f"Arcane: {current_tag} ya apunta al digest publicado para {new_tag}.")
            return 0

        atomic_write(MODULE, updated)
        print(
            f"Arcane: imagen fijada actualizada de {current_tag} a {new_tag} "
            "con su digest verificado. Se aplicará junto con la generación NixOS."
        )
        return 0

    except (OSError, urllib.error.URLError, json.JSONDecodeError, ValueError, RuntimeError) as error:
        # A registry/API outage must not prevent ordinary NixOS maintenance.
        print(f"Arcane: no se pudo comprobar la actualización; se conserva la versión actual ({error}).", file=sys.stderr)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
