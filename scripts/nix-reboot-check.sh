#!/usr/bin/env bash
# Comprueba si la generación seleccionada requiere reiniciar el equipo.

set -Eeuo pipefail

BOOTED="/run/booted-system"
NEXT="/nix/var/nix/profiles/system"

[[ -e "$BOOTED" ]] || {
  echo "❌ Error: no se puede identificar el sistema que está arrancado." >&2
  exit 1
}
[[ -e "$NEXT" ]] || {
  echo "❌ Error: no se puede identificar la generación seleccionada." >&2
  exit 1
}

HOST="$(hostname -s)"
if ! OPERATION="$(nix eval --raw ".#nixosConfigurations.$HOST.config.system.autoUpgrade.operation" 2>/dev/null)"; then
  echo "❌ Error: no se pudo consultar la estrategia de actualización del host." >&2
  exit 2
fi

if [[ "$OPERATION" == "boot" ]]; then
  if [[ "$(readlink -f "$BOOTED")" != "$(readlink -f "$NEXT")" ]]; then
    echo "🔁 Reinicio pendiente: hay una nueva generación preparada."
  else
    echo "✅ No hay ningún reinicio pendiente."
  fi
  exit 0
fi

if [[ "$OPERATION" != "switch" ]]; then
  printf '❌ Error: estrategia de actualización no reconocida: %s\n' "$OPERATION" >&2
  exit 2
fi

changed_components=()
unverified=0

for component in kernel kernel-modules initrd systemd; do
  booted_component="$BOOTED/$component"
  next_component="$NEXT/$component"

  if [[ ! -e "$booted_component" || ! -e "$next_component" ]]; then
    unverified=1
    continue
  fi

  if [[ "$(readlink -f "$booted_component")" != "$(readlink -f "$next_component")" ]]; then
    changed_components+=("$component")
  fi
done

if (( ${#changed_components[@]} > 0 )); then
  printf '🔁 Reinicio necesario: cambios en %s.\n' "${changed_components[*]}"
  exit 0
fi

if (( unverified )); then
  echo "⚠️  No se pudo comprobar si hace falta reiniciar." >&2
  exit 2
fi

echo "✅ No es necesario reiniciar."
