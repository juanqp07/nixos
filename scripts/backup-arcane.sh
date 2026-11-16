#!/usr/bin/env bash
# Create a restorable Arcane snapshot before changing its pinned image.
set -Eeuo pipefail
umask 077

running_image="${1:?Usage: backup-arcane.sh <running-image> <target-image>}"
target_image="${2:?Usage: backup-arcane.sh <running-image> <target-image>}"

backup_root="/mnt/datos/AppData/arcane/backups/nix-maintain"
projects_dir="/mnt/datos/arcane/projects"
arcane_env="/mnt/datos/AppData/arcane/arcane.env"
postgres_env="/mnt/datos/AppData/arcane/postgres.env"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="$backup_root/$timestamp"

fail() {
  printf 'Arcane backup failed: %s\n' "$*" >&2
  printf 'Any partial files were left in: %s\n' "$backup_dir" >&2
  exit 1
}

command -v docker >/dev/null 2>&1 || fail "Docker CLI is not installed."
command -v tar >/dev/null 2>&1 || fail "tar is not installed."
command -v gzip >/dev/null 2>&1 || fail "gzip is not installed."
mountpoint -q /mnt/datos || fail "/mnt/datos is not mounted; refusing to write a backup to the OS disk."

for file in "$arcane_env" "$postgres_env"; do
  [[ -s "$file" ]] || fail "Required environment file is missing or empty: $file"
done
[[ -d "$projects_dir" ]] || fail "Arcane projects directory is missing: $projects_dir"

for container in arcane arcane-postgres; do
  running="$(docker inspect --format '{{.State.Running}}' "$container" 2>/dev/null || true)"
  [[ "$running" == true ]] || fail "Container '$container' is not running."
done

docker exec arcane-postgres pg_isready -q ||
  fail "PostgreSQL is not accepting connections; no upgrade will be attempted."

mkdir -p "$backup_dir"
chmod 0700 "$backup_root" "$backup_dir"

printf 'Running image: %s\nTarget image: %s\nCreated at (UTC): %s\n' \
  "$running_image" "$target_image" "$timestamp" >"$backup_dir/manifest.txt"

# pg_dumpall is a transactionally consistent logical backup of every Arcane
# database and role. The dump is taken while the database is online.
docker exec arcane-postgres sh -ec \
  'pg_dumpall --clean --if-exists --username "${POSTGRES_USER:-postgres}"' \
  >"$backup_dir/postgres.sql" ||
  fail "Could not dump the Arcane PostgreSQL databases."
[[ -s "$backup_dir/postgres.sql" ]] ||
  fail "PostgreSQL produced an empty dump."

# Preserve Arcane's application data volume, external projects and the exact
# environment files required to recreate the current containers.
docker cp arcane:/app/data - | gzip -1 >"$backup_dir/app-data.tar.gz" ||
  fail "Could not archive /app/data from the Arcane container."
[[ -s "$backup_dir/app-data.tar.gz" ]] ||
  fail "The Arcane application data archive is empty."

tar -C "$projects_dir" -czf "$backup_dir/projects.tar.gz" . ||
  fail "Could not archive the Arcane projects directory."
cp -p "$arcane_env" "$backup_dir/arcane.env" ||
  fail "Could not copy arcane.env."
cp -p "$postgres_env" "$backup_dir/postgres.env" ||
  fail "Could not copy postgres.env."

chmod 0600 "$backup_dir"/*
sync

printf 'Arcane backup completed: %s\n' "$backup_dir"
printf 'Contents: PostgreSQL dump, /app/data, projects, environment files and image manifest.\n'
df -h "$backup_dir"
