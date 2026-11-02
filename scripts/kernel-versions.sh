#!/usr/bin/env bash
# Show the configured kernel version for every NixOS host in this flake.
# This script is read-only: it evaluates the flake and does not build,
# switch, install, or modify any system.

set -uo pipefail

FLAKE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$FLAKE_DIR"

if ! command -v nix >/dev/null 2>&1; then
  echo "Error: nix is not installed or not in PATH." >&2
  exit 1
fi

if ! hosts="$(nix eval --raw --apply 'attrs: builtins.concatStringsSep "\n" (builtins.attrNames attrs)' .#nixosConfigurations 2>/dev/null)"; then
  echo "Error: could not evaluate nixosConfigurations in $FLAKE_DIR" >&2
  exit 1
fi

if [[ -z "$hosts" ]]; then
  echo "No NixOS hosts found in the flake."
  exit 0
fi

printf '%-20s %s\n' "HOST" "CONFIGURED KERNEL"
printf '%-20s %s\n' "--------------------" "-----------------"

while IFS= read -r host; do
  [[ -n "$host" ]] || continue

  if version="$(nix eval --raw ".#nixosConfigurations.${host}.config.boot.kernelPackages.kernel.version" 2>/dev/null)"; then
    printf '%-20s %s\n' "$host" "$version"
  else
    printf '%-20s %s\n' "$host" "N/A (evaluation failed)" 
  fi
done <<< "$hosts"
