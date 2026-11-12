#!/usr/bin/env python3
"""Update the Nori desktop and CLI Nix packages from the latest stable release."""

from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RELEASE_API = "https://api.github.com/repos/norifm/nori/releases/latest"
PACKAGE_FILES = {
    "desktop": ROOT / "nixpkgs/pkgs/by-name/no/nori/package.nix",
    "cli": ROOT / "nixpkgs/pkgs/by-name/no/nori-cli/package.nix",
}
ASSETS = {
    ("desktop", "x86_64-linux"): "nori-desktop-{version}-linux-x86_64.AppImage",
    ("desktop", "aarch64-linux"): "nori-desktop-{version}-linux-aarch64.AppImage",
    ("cli", "x86_64-linux"): "nori-cli-{version}-linux-x86_64.tar.gz",
    ("cli", "aarch64-linux"): "nori-cli-{version}-linux-aarch64.tar.gz",
}
ARCHES = {
    "x86_64-linux": "x86_64",
    "aarch64-linux": "aarch64",
}


def github_json(url: str) -> dict:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "nixos-nori-package-updater",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def version_tuple(version: str) -> tuple[int, int, int]:
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", version)
    if not match:
        raise ValueError(f"Unsupported Nori version: {version!r}")
    return tuple(map(int, match.groups()))


def package_version(content: str, path: Path) -> str:
    match = re.search(r'(?m)^\s*version\s*=\s*"([^"]+)"\s*;', content)
    if not match:
        raise ValueError(f"Could not find a version declaration in {path}")
    return match.group(1)


def asset_sri(asset: dict) -> str:
    """Use GitHub's SHA-256 digest, falling back to hashing the official release asset."""
    digest = asset.get("digest") or ""
    match = re.fullmatch(r"sha256:([0-9a-fA-F]{64})", digest)
    if match:
        raw_hash = bytes.fromhex(match.group(1))
    else:
        url = asset.get("browser_download_url") or ""
        prefix = "https://github.com/norifm/nori/releases/download/"
        if not url.startswith(prefix):
            raise ValueError(f"Unexpected release asset URL: {url!r}")
        request = urllib.request.Request(
            url, headers={"User-Agent": "nixos-nori-package-updater"}
        )
        hasher = hashlib.sha256()
        with urllib.request.urlopen(request, timeout=120) as response:
            while chunk := response.read(1024 * 1024):
                hasher.update(chunk)
        raw_hash = hasher.digest()

    if len(raw_hash) != 32:
        raise ValueError(f"Invalid SHA-256 digest for asset {asset.get('name')!r}")
    return "sha256-" + base64.b64encode(raw_hash).decode("ascii")


def update_package(path: Path, current: str, version: str, hashes: dict[str, str]) -> str:
    content = path.read_text(encoding="utf-8")
    if package_version(content, path) != current:
        raise ValueError(f"Unexpected version change while updating {path}")

    version_pattern = re.compile(r'(?m)^(\s*version\s*=\s*")[^"]+("\s*;)$')
    content, count = version_pattern.subn(
        lambda match: f"{match.group(1)}{version}{match.group(2)}",
        content,
        count=1,
    )
    if count != 1:
        raise ValueError(f"Expected one version declaration in {path}, found {count}")

    for system, arch in ARCHES.items():
        pattern = re.compile(
            rf'("{re.escape(system)}"\s*=\s*\{{\s*arch\s*=\s*"{arch}";'
            rf'\s*hash\s*=\s*")[^"]+(";)'
        )
        content, count = pattern.subn(
            lambda match: f"{match.group(1)}{hashes[system]}{match.group(2)}",
            content,
            count=1,
        )
        if count != 1:
            raise ValueError(f"Expected one {system} hash block in {path}, found {count}")

    return content


def write_output(changed: bool, version: str) -> None:
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as file:
            file.write(f"changed={'true' if changed else 'false'}\n")
            file.write(f"version={version}\n")


def main() -> None:
    release = github_json(RELEASE_API)
    if release.get("draft") or release.get("prerelease"):
        raise ValueError("The latest Nori release is not a stable published release")

    tag = release.get("tag_name", "")
    match = re.fullmatch(r"v(\d+\.\d+\.\d+)", tag)
    if not match:
        raise ValueError(f"Unexpected Nori release tag: {tag!r}")
    version = match.group(1)

    contents = {name: path.read_text(encoding="utf-8") for name, path in PACKAGE_FILES.items()}
    versions = {
        name: package_version(content, PACKAGE_FILES[name])
        for name, content in contents.items()
    }
    if len(set(versions.values())) != 1:
        raise ValueError(f"Nori desktop and CLI versions differ: {versions}")
    current = next(iter(versions.values()))

    if version_tuple(version) <= version_tuple(current):
        print(f"Nori packages are already at {current}; latest stable release is {version}.")
        write_output(False, version)
        return

    release_assets = {asset.get("name"): asset for asset in release.get("assets", [])}
    hashes: dict[str, dict[str, str]] = {"desktop": {}, "cli": {}}
    for (package, system), name_template in ASSETS.items():
        asset_name = name_template.format(version=version)
        asset = release_assets.get(asset_name)
        if not asset:
            raise ValueError(f"Release {tag} is missing required asset {asset_name}")
        hashes[package][system] = asset_sri(asset)

    updated = {
        name: update_package(PACKAGE_FILES[name], current, version, hashes[name])
        for name in PACKAGE_FILES
    }
    for name, content in updated.items():
        PACKAGE_FILES[name].write_text(content, encoding="utf-8")

    print(f"Updated Nori desktop and CLI packages: {current} -> {version}")
    write_output(True, version)


if __name__ == "__main__":
    main()
