#!/usr/bin/env bash
# Verify the deployed Arcane image, application health and PostgreSQL readiness.
set -Eeuo pipefail

expected_image="\${1:?Usage: verify-arcane.sh <expected-image>}"
attempts=36
interval=5
docker="\${DOCKER:-docker}"

command -v "$docker" >/dev/null 2>&1 || {
  echo "Docker CLI is not available." >&2
  exit 1
}

for ((attempt = 1; attempt <= attempts; attempt++)); do
  state="$("$docker" inspect --format '{{.State.Status}}' arcane 2>/dev/null || true)"
  actual_image="$("$docker" inspect --format '{{.Config.Image}}' arcane 2>/dev/null || true)"
  health="$("$docker" inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' arcane 2>/dev/null || true)"

  postgres_running="$("$docker" inspect --format '{{.State.Running}}' arcane-postgres 2>/dev/null || true)"
  postgres_ready=no
  if [[ "$postgres_running" == true ]] && "$docker" exec arcane-postgres pg_isready -q >/dev/null 2>&1; then
    postgres_ready=yes
  fi

  if [[ "$state" == running && "$actual_image" == "$expected_image" && "$health" == healthy && "$postgres_ready" == yes ]]; then
    echo "Arcane is healthy."
    echo "Image: $actual_image"
    echo "PostgreSQL: ready"
    exit 0
  fi

  if [[ "$state" == exited || "$state" == dead ]]; then
    echo "Arcane container stopped while waiting for health." >&2
    break
  fi

  printf 'Waiting for Arcane health (%s/%s): state=%s image=%s health=%s postgres=%s\n' \
    "$attempt" "$attempts" "\${state:-missing}" "\${actual_image:-missing}" \
    "\${health:-unknown}" "$postgres_ready"
  sleep "$interval"
done

echo "Arcane did not become healthy with the expected image: $expected_image" >&2
echo "--- Arcane container logs ---" >&2
"$docker" logs --tail 100 arcane >&2 || true
echo "--- PostgreSQL container logs ---" >&2
"$docker" logs --tail 60 arcane-postgres >&2 || true
echo "The pre-upgrade backup is retained. Do not delete it; follow docs/arcane-maintenance.md to recover." >&2
exit 1
