"""Pin OCI image references to their current registry manifest digests."""

from __future__ import annotations

import json
import re
import sys
import urllib.parse
import urllib.request
from collections.abc import Callable
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IMAGE_FILES = (
    ROOT / "hosts/servidor/configuration.nix",
    ROOT / "hosts/zimablade/configuration.nix",
)
IMAGE_LINE = re.compile(
    r'^(?P<prefix>[ \t]*image[ \t]*=[ \t]*")(?P<reference>[^"]+)(?P<suffix>";)$',
    re.MULTILINE,
)
DIGEST_PATTERN = re.compile(r"sha256:[0-9a-f]{64}")
ACCEPT_MANIFESTS = (
    "application/vnd.oci.image.index.v1+json, "
    "application/vnd.docker.distribution.manifest.list.v2+json, "
    "application/vnd.oci.image.manifest.v1+json, "
    "application/vnd.docker.distribution.manifest.v2+json"
)
USER_AGENT = "juanqp07-nixos-container-digest-updater/1.0"


def parse_image_reference(reference: str) -> tuple[str, str, str | None]:
    """Split registry/repository:tag[@digest] without losing registry ports."""
    name_and_tag, separator, current_digest = reference.partition("@")
    if separator and not DIGEST_PATTERN.fullmatch(current_digest):
        raise ValueError(f"Invalid digest in image reference: {reference!r}")

    slash = name_and_tag.rfind("/")
    colon = name_and_tag.rfind(":")
    if colon <= slash:
        raise ValueError(f"Image reference must include an explicit tag: {reference!r}")

    repository = name_and_tag[:colon]
    tag = name_and_tag[colon + 1 :]
    if not repository or not tag:
        raise ValueError(f"Invalid image reference: {reference!r}")
    return repository, tag, current_digest if separator else None


def registry_coordinates(repository: str) -> tuple[str, str]:
    """Return registry hostname and normalized repository path."""
    first_component, separator, remainder = repository.partition("/")
    if first_component in ("ghcr.io", "docker.io", "index.docker.io"):
        if not separator or not remainder:
            raise ValueError(f"Missing repository path in {repository!r}")
        registry = "ghcr.io" if first_component == "ghcr.io" else "registry-1.docker.io"
        remote_repository = remainder
    else:
        registry = "registry-1.docker.io"
        remote_repository = repository if separator else f"library/{repository}"

    return registry, remote_repository


def read_json(url: str, headers: dict[str, str] | None = None) -> dict:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, **(headers or {})},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.load(response)
    if not isinstance(payload, dict):
        raise TypeError(f"Registry returned an invalid JSON object for {url}")
    return payload


def fetch_digest(repository: str, tag: str) -> str:
    """Resolve the immutable multi-platform manifest digest from Docker Hub or GHCR."""
    registry, remote_repository = registry_coordinates(repository)
    scope = f"repository:{remote_repository}:pull"

    if registry == "ghcr.io":
        token_query = urllib.parse.urlencode({"scope": scope})
        token_url = f"https://ghcr.io/token?{token_query}"
    else:
        token_query = urllib.parse.urlencode(
            {"service": "registry.docker.io", "scope": scope}
        )
        token_url = f"https://auth.docker.io/token?{token_query}"

    token_payload = read_json(token_url)
    token = token_payload.get("token") or token_payload.get("access_token")
    if not isinstance(token, str) or not token:
        raise ValueError(f"Registry did not issue a pull token for {repository}")

    quoted_repository = urllib.parse.quote(remote_repository, safe="/")
    quoted_tag = urllib.parse.quote(tag, safe="")
    manifest_url = f"https://{registry}/v2/{quoted_repository}/manifests/{quoted_tag}"
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

    if not isinstance(digest, str) or not DIGEST_PATTERN.fullmatch(digest):
        raise ValueError(
            f"Registry returned no valid Docker-Content-Digest for {repository}:{tag}"
        )
    return digest


def update_image_references(
    content: str,
    resolver: Callable[[str, str], str] | None = None,
) -> tuple[str, list[str]]:
    """Pin/update image references in Nix image assignments."""
    resolve = resolver or fetch_digest
    changes: list[str] = []

    def replace(match: re.Match[str]) -> str:
        reference = match.group("reference")
        repository, tag, _ = parse_image_reference(reference)
        new_digest = resolve(repository, tag)
        if not DIGEST_PATTERN.fullmatch(new_digest):
            raise ValueError(
                f"Resolver returned an invalid digest for {repository}:{tag}"
            )

        updated_reference = f"{repository}:{tag}@{new_digest}"
        if updated_reference != reference:
            changes.append(f"{reference} -> {updated_reference}")

        return f"{match.group('prefix')}{updated_reference}{match.group('suffix')}"

    updated = IMAGE_LINE.sub(replace, content)
    return updated, changes


def main() -> None:
    total_changes = 0
    for path in IMAGE_FILES:
        content = path.read_text(encoding="utf-8")
        updated, changes = update_image_references(content)
        if updated != content:
            path.write_text(updated, encoding="utf-8")

        for change in changes:
            print(f"{path.relative_to(ROOT)}: {change}")
        total_changes += len(changes)

    if total_changes == 0:
        print("All declared OCI images already use the current registry digests.")
    else:
        print(f"Updated {total_changes} OCI image digest reference(s).")


if __name__ == "__main__":
    try:
        main()
    # Fail the scheduled job rather than pinning an unknown digest.
    except Exception as error:
        print(f"Container digest update failed: {error}", file=sys.stderr)
        raise
