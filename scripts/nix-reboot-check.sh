#!/usr/bin/env bash
# Comprueba si la generación seleccionada requiere reiniciar el equipo.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$FLAKE_DIR"

# Estilo común de la suite de administración.
# shellcheck source=scripts/terminal-style.sh
source "$SCRIPT_DIR/terminal-style.sh"

HOST="$(hostname -s)"

BOOTED="/run/booted-system"
NEXT="/nix/var/nix/profiles/system"

[[ -e "$BOOTED" ]] || {
  term_error "No se puede identificar el sistema que está arrancado."
  exit 1
}
[[ -e "$NEXT" ]] || {
  term_error "No se puede identificar la generación seleccionada."
  exit 1
}

if ! OPERATION="$(nix eval --raw ".#nixosConfigurations.$HOST.config.system.autoUpgrade.operation" 2>/dev/null)"; then
  term_error "No se pudo consultar la estrategia de actualización del host."
  exit 2
fi

if [[ "$OPERATION" == "boot" ]]; then
  if [[ "$(readlink -f "$BOOTED")" != "$(readlink -f "$NEXT")" ]]; then
    term_warning "Reinicio pendiente: hay una nueva generación preparada."
  else
    term_success "No hay ningún reinicio pendiente."
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
  term_warning "No se pudo comprobar si hace falta reiniciar."
  exit 2
fi

term_success "No es necesario reiniciar."
