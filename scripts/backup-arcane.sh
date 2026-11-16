#!/usr/bin/env bash
# Non-disruptive backup of the Arcane data managed on Atlas.

set -Eeuo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  printf 'Run this script as root (for example: sudo bash scripts/backup-arcane.sh).\n' >&2
  exit 1
fi

for command in docker tar cp install date du chmod mktemp cut; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  }
done

DATA_ROOT="/mnt/datos"
ARCANE_ROOT="$DATA_ROOT/AppData/arcane"
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

timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
install -d -m 0700 "$BACKUP_ROOT"
backup_dir="$(mktemp -d "$BACKUP_ROOT/$timestamp.XXXXXX")"
chmod 0700 "$backup_dir"
umask 077
incomplete_marker="$backup_dir/INCOMPLETE"
: >"$incomplete_marker"

# pg_dumpall takes a consistent logical backup while PostgreSQL remains online.
postgres_user="$(docker exec arcane-postgres printenv POSTGRES_USER 2>/dev/null || true)"
[[ -n "$postgres_user" ]] || postgres_user="postgres"
docker exec arcane-postgres pg_dumpall --username="$postgres_user" \
  >"$backup_dir/postgres.sql"
[[ -s "$backup_dir/postgres.sql" ]] || {
  printf 'PostgreSQL produced an empty backup.\n' >&2
  exit 1
}

# The application data volume and projects directory are copied without
# stopping Arcane. PostgreSQL itself is backed up separately above.
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
Keep this backup until the updated Arcane Manager and its notifications have
been checked after the next Atlas restart.
EOF

chmod -R go-rwx "$backup_dir"
rm -f "$incomplete_marker"

printf 'Arcane backup created: %s\n' "$backup_dir"
printf 'Backup size: '
du -sh "$backup_dir" | cut -f1
