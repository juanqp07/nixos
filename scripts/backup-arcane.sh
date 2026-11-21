#!/usr/bin/env bash
# Consistent backup of the Arcane data managed on Atlas.

set -Eeuo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  printf 'Run this script as root (for example: sudo bash scripts/backup-arcane.sh).\n' >&2
  exit 1
fi

for command in docker systemctl sleep tar cp install date du chmod mktemp cut mountpoint; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  }
done

DATA_ROOT="/mnt/datos"
mountpoint -q "$DATA_ROOT" || {
  printf 'Arcane backup refused: %s is not a mounted filesystem.\n' "$DATA_ROOT" >&2
  exit 1
}
ARCANE_ROOT="$DATA_ROOT/AppData/arcane"
ARCANE_SERVICE="docker-arcane.service"
PROJECTS_DIR="$DATA_ROOT/arcane/projects"
BACKUP_ROOT="$ARCANE_ROOT/backups"
MODULE_FILE="$(cd -- "$(dirname -- "$0")/.." && pwd)/modules/atlas-docker.nix"

[[ -d "$ARCANE_ROOT" ]] || {
  printf 'Arcane data directory is not mounted: %s\n' "$ARCANE_ROOT" >&2
  exit 1
}
[[ -d "$PROJECTS_DIR" ]] || {
  printf 'Arcane projects directory is missing: %s\n' "$PROJECTS_DIR" >&2
  exit 1
}
[[ -f "$ARCANE_ROOT/arcane.env" && -f "$ARCANE_ROOT/postgres.env" ]] || {
  printf 'Arcane environment files are missing under %s\n' "$ARCANE_ROOT" >&2
  exit 1
}

systemctl is-active --quiet "$ARCANE_SERVICE" || {
  printf 'Required systemd service is not active: %s\n' "$ARCANE_SERVICE" >&2
  exit 1
}

for container in arcane arcane-postgres; do
  state="$(docker inspect --format '{{.State.Running}}' "$container" 2>/dev/null || true)"
  [[ "$state" == "true" ]] || {
    printf 'Required container is not running: %s\n' "$container" >&2
    exit 1
  }
done

arcane_volume="$(docker volume inspect --format '{{.Mountpoint}}' arcane-data)"
[[ -d "$arcane_volume" ]] || {
  printf 'Arcane Docker volume is unavailable: arcane-data\n' >&2
  exit 1
}

# NixOS owns the container lifecycle. Its oci-containers unit uses Docker's
# --rm behaviour and removes the container when stopped, so docker start cannot
# restore it. Stop and restart the systemd unit to recreate the declared container.
# Keep this trap active for every operation that follows, including failures.
restore_arcane() {
  local status="$?"
  local service_state
  local container_state
  local restore_failed=0
  trap - EXIT

  service_state="$(systemctl is-active "$ARCANE_SERVICE" 2>/dev/null || true)"
  container_state="$(docker inspect --format '{{.State.Running}}' arcane 2>/dev/null || true)"

  if [[ "$service_state" != "active" || "$container_state" != "true" ]]; then
    printf 'Restoring Arcane through %s...\n' "$ARCANE_SERVICE"
    if [[ "$service_state" == "active" ]]; then
      systemctl restart "$ARCANE_SERVICE" || restore_failed=1
    else
      systemctl start "$ARCANE_SERVICE" || restore_failed=1
    fi

    # systemctl start/restart returns when a Type=simple unit's process has
    # been launched, not when Docker has finished creating the container.
    # Wait for both systemd and Docker to report the restored container running.
    if ((restore_failed == 0)); then
      for ((attempt = 1; attempt <= 90; attempt++)); do
        service_state="$(systemctl is-active "$ARCANE_SERVICE" 2>/dev/null || true)"
        container_state="$(docker inspect --format '{{.State.Running}}' arcane 2>/dev/null || true)"
        if [[ "$service_state" == "active" && "$container_state" == "true" ]]; then
          break
        fi
        sleep 1
      done
    fi

    if ((restore_failed != 0)) || [[ "$service_state" != "active" || "$container_state" != "true" ]]; then
      printf 'ERROR: Arcane did not reach a running container state within 90 seconds.\n' >&2
      printf 'Systemd state: %s; container running: %s\n' "${service_state:-unknown}" "${container_state:-no}" >&2
      status=1
    else
      printf 'Arcane systemd service and container are running after backup.\n'
    fi
  fi

  exit "$status"
}
trap restore_arcane EXIT

docker exec arcane-postgres pg_isready -q || {
  printf 'PostgreSQL is not ready; refusing to create a backup.\n' >&2
  exit 1
}
systemctl stop "$ARCANE_SERVICE"

timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
install -d -m 0700 "$BACKUP_ROOT"
backup_dir="$(mktemp -d "$BACKUP_ROOT/$timestamp.XXXXXX")"
chmod 0700 "$backup_dir"
umask 077
incomplete_marker="$backup_dir/INCOMPLETE"
: >"$incomplete_marker"

# Arcane is stopped, so no new application writes can race this database dump.
# PostgreSQL remains online and accepts the local logical backup.
postgres_user="$(docker exec arcane-postgres printenv POSTGRES_USER 2>/dev/null || true)"
[[ -n "$postgres_user" ]] || postgres_user="postgres"
docker exec arcane-postgres pg_dumpall --username="$postgres_user" \
  >"$backup_dir/postgres.sql"
[[ -s "$backup_dir/postgres.sql" ]] || {
  printf 'PostgreSQL produced an empty backup.\n' >&2
  exit 1
}

# Arcane remains stopped until the file-level archives have been created.
# PostgreSQL itself is backed up separately above.
tar --numeric-owner --xattrs --acls -czf "$backup_dir/arcane-data.tar.gz" \
  -C "$arcane_volume" .
tar --numeric-owner --xattrs --acls -czf "$backup_dir/projects.tar.gz" \
  -C "$PROJECTS_DIR" .

cp -a "$ARCANE_ROOT/arcane.env" "$backup_dir/arcane.env"
cp -a "$ARCANE_ROOT/postgres.env" "$backup_dir/postgres.env"
cp -- "$MODULE_FILE" "$backup_dir/atlas-docker.nix"

tar -tzf "$backup_dir/arcane-data.tar.gz" >/dev/null
tar -tzf "$backup_dir/projects.tar.gz" >/dev/null
[[ -s "$backup_dir/postgres.sql" ]]

cat >"$backup_dir/README.txt" <<EOF
Arcane Atlas backup
Created UTC: $timestamp

Contents:
- postgres.sql: logical PostgreSQL dump from arcane-postgres.
- arcane-data.tar.gz: arcane-data Docker volume.
- projects.tar.gz: /mnt/datos/arcane/projects.
- arcane.env and postgres.env: environment files (secrets; keep private).
- atlas-docker.nix: NixOS container declaration used at backup time.

The backup directory is private (0700) and its files are private (0600).
The Manager was stopped and restored through docker-arcane.service. NixOS
recreates its auto-removed container from the declared configuration.
Keep this backup until the updated Arcane Manager and its notifications have
been checked after the next Atlas restart.
EOF

chmod -R go-rwx "$backup_dir"
rm -f "$incomplete_marker"

printf 'Arcane backup created: %s\n' "$backup_dir"
printf 'Backup size: '
du -sh "$backup_dir" | cut -f1
