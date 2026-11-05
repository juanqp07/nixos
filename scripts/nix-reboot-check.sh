#!/usr/bin/env bash
# Check reboot requirements against the system profile selected for next boot.
# In "boot" mode, the full generation is pending until the next restart.
# In "switch" mode, only reboot-sensitive components require a restart.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$FLAKE_DIR"

BOOTED="/run/booted-system"
NEXT="/nix/var/nix/profiles/system"

[[ -e "$BOOTED" ]] || {
  echo "❌ Error: no existe $BOOTED; no se puede identificar el sistema arrancado." >&2
  exit 1
}
[[ -e "$NEXT" ]] || {
  echo "❌ Error: no existe $NEXT; no se puede identificar la generación seleccionada." >&2
  exit 1
}

HOST="$(hostname -s)"
OPERATION="$(nix eval --raw ".#nixosConfigurations.$HOST.config.system.autoUpgrade.operation")"

if [[ "$OPERATION" == "boot" ]]; then
  booted_system="$(readlink -f "$BOOTED")"
  next_system="$(readlink -f "$NEXT")"

  if [[ "$booted_system" != "$next_system" ]]; then
    printf '🔁 Reinicio pendiente: hay una nueva generación preparada para el próximo arranque.\n'
    printf '🟢 Arrancada: %s\n📦 Siguiente: %s\n' "$booted_system" "$next_system"
    exit 0
  fi

  echo "✅ No hay una nueva generación pendiente de activar en el próximo arranque."
  exit 0
fi

if [[ "$OPERATION" != "switch" ]]; then
  printf '❌ Error: operación de despliegue no reconocida: %s\n' "$OPERATION" >&2
  exit 2
fi

needs_reboot=0
unverified=0

for component in kernel kernel-modules initrd systemd; do
  booted_component="$BOOTED/$component"
  next_component="$NEXT/$component"

  if [[ ! -e "$booted_component" || ! -e "$next_component" ]]; then
    printf '⚠️  Aviso: no se pudo comparar el componente %s.\n' "$component"
    unverified=1
    continue
  fi

  booted_target="$(readlink -f "$booted_component")"
  next_target="$(readlink -f "$next_component")"

  if [[ "$booted_target" != "$next_target" ]]; then
    printf '🔁 Reinicio necesario: cambio en %s\n' "$component"
    needs_reboot=1
  fi
done

if (( needs_reboot )); then
  exit 0
fi

if (( unverified )); then
  echo "⚠️  No se pudo verificar todos los componentes; revisa los avisos anteriores." >&2
  exit 2
fi

echo "✅ Sin cambios de kernel, módulos, initrd o systemd pendientes de reinicio."
