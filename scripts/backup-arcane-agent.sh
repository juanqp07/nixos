#!/usr/bin/env bash
# Consistent backup of the Arcane Agent data managed on Pico.

set -Eeuo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  printf 'Run this script as root (for example: sudo bash scripts/backup-arcane-agent.sh).\n' >&2
  exit 1
fi

for command in docker systemctl tar cp install date du chmod mktemp cut; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  }
done

AGENT_ROOT="/var/lib/arcane-agent"
AGENT_ENV="$AGENT_ROOT/agent.env"
BACKUP_ROOT="$AGENT_ROOT/backups"
AGENT_SERVICE="docker-arcane-agent.service"
MODULE_FILE="$(cd -- "$(dirname -- "$0")/.." && pwd)/hosts/zimablade/configuration.nix"

[[ -d "$AGENT_ROOT" && -f "$AGENT_ENV" ]] || {
  printf 'Arcane Agent data or enrollment environment is missing under %s\n' "$AGENT_ROOT" >&2
  exit 1
}

systemctl is-active --quiet "$AGENT_SERVICE" || {
  printf 'Required systemd service is not active: %s\n' "$AGENT_SERVICE" >&2
  exit 1
}

state="$(docker inspect --format '{{.State.Running}}' arcane-agent 2>/dev/null || true)"
[[ "$state" == "true" ]] || {
  printf 'Required container is not running: arcane-agent\n' >&2
  exit 1
}

agent_volume="$(docker volume inspect --format '{{.Mountpoint}}' arcane-agent-data)"
[[ -d "$agent_volume" ]] || {
  printf 'Arcane Agent Docker volume is unavailable: arcane-agent-data\n' >&2
  exit 1
}

# NixOS owns the Agent container lifecycle. Its oci-containers unit uses
# Docker's --rm behaviour and removes the container when stopped, so docker
# start cannot restore it. Use systemd to recreate the declared container.
# Keep this trap active for every operation that follows, including failures.
restore_agent() {
  local status="$?"
  local service_state
  local container_state
  local restore_failed=0
  trap - EXIT

  service_state="$(systemctl is-active "$AGENT_SERVICE" 2>/dev/null || true)"
  container_state="$(docker inspect --format '{{.State.Running}}' arcane-agent 2>/dev/null || true)"

  if [[ "$service_state" != "active" || "$container_state" != "true" ]]; then
    printf 'Restoring Arcane Agent through %s...\n' "$AGENT_SERVICE"
    if [[ "$service_state" == "active" ]]; then
      systemctl restart "$AGENT_SERVICE" || restore_failed=1
    else
      systemctl start "$AGENT_SERVICE" || restore_failed=1
    fi

    if (( restore_failed == 0 )); then
      service_state="$(systemctl is-active "$AGENT_SERVICE" 2>/dev/null || true)"
      container_state="$(docker inspect --format '{{.State.Running}}' arcane-agent 2>/dev/null || true)"
    fi

    if (( restore_failed != 0 )) || [[ "$service_state" != "active" || "$container_state" != "true" ]]; then
      printf 'ERROR: Arcane Agent could not be restored successfully.\n' >&2
      printf 'Systemd state: %s; container running: %s\n' "${service_state:-unknown}" "${container_state:-no}" >&2
      status=1
    else
      printf 'Arcane Agent systemd service and container are running after backup.\n'
    fi
  fi

  exit "$status"
}
trap restore_agent EXIT

systemctl stop "$AGENT_SERVICE"

timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
install -d -m 0700 "$BACKUP_ROOT"
backup_dir="$(mktemp -d "$BACKUP_ROOT/$timestamp.XXXXXX")"
chmod 0700 "$backup_dir"
umask 077
incomplete_marker="$backup_dir/INCOMPLETE"
: >"$incomplete_marker"

tar --numeric-owner --xattrs --acls -czf "$backup_dir/arcane-agent-data.tar.gz" \
  -C "$agent_volume" .
cp -a "$AGENT_ENV" "$backup_dir/agent.env"
cp -- "$MODULE_FILE" "$backup_dir/zimablade-configuration.nix"
docker inspect --format '{{.Config.Image}}' arcane-agent >"$backup_dir/container-image.txt"

tar -tzf "$backup_dir/arcane-agent-data.tar.gz" >/dev/null
[[ -s "$backup_dir/agent.env" ]]
[[ -s "$backup_dir/container-image.txt" ]]

cat >"$backup_dir/README.txt" <<EOF
Arcane Agent Pico backup
Created UTC: $timestamp

Contents:
- arcane-agent-data.tar.gz: arcane-agent-data Docker volume.
- agent.env: Agent enrollment token and environment (secret; keep private).
- zimablade-configuration.nix: NixOS Agent declaration used at backup time.
- container-image.txt: image reference used by the running container.

The backup directory is private (0700) and its files are private (0600).
The Agent was stopped and restored through docker-arcane-agent.service.
NixOS recreates its auto-removed container from the declared configuration.
The Dockge stack directory is not part of the Agent volume and is not changed.
EOF

chmod -R go-rwx "$backup_dir"
rm -f "$incomplete_marker"

printf 'Arcane Agent backup created: %s\n' "$backup_dir"
printf 'Backup size: '
du -sh "$backup_dir" | cut -f1
