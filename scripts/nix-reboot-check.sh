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
OUTPUT_MODE="human"
case "${1:-}" in
"")
  ;;
--machine-readable)
  OUTPUT_MODE="machine"
  ;;
*)
  echo "Uso: $0 [--machine-readable]" >&2
  exit 2
  ;;
esac

if [[ "$OUTPUT_MODE" == "human" && "${NIX_MAINTENANCE_CONTEXT:-no}" != "yes" ]]; then
  term_banner "Comprobación de reinicio" "$HOST"
fi

BOOTED="${NIX_REBOOT_CHECK_BOOTED_PATH:-/run/booted-system}"
NEXT="${NIX_REBOOT_CHECK_NEXT_PATH:-/nix/var/nix/profiles/system}"

report_required() {
  if [[ "$OUTPUT_MODE" == "machine" ]]; then
    echo required
  else
    term_warning "$1"
  fi
  exit 0
}

report_not_required() {
  if [[ "$OUTPUT_MODE" == "machine" ]]; then
    echo not-required
  else
    term_success "No es necesario reiniciar."
  fi
  exit 0
}

report_unknown() {
  local message="$1"
  local status="${2:-2}"

  if [[ "$OUTPUT_MODE" == "machine" ]]; then
    echo unknown
    exit 0
  fi

  term_error "$message"
  exit "$status"
}

[[ -e "$BOOTED" ]] || report_unknown "No se puede identificar el sistema que está arrancado." 1
[[ -e "$NEXT" ]] || report_unknown "No se puede identificar la generación seleccionada." 1

if ! OPERATION="$(nix eval --no-write-lock-file --raw ".#nixosConfigurations.$HOST.config.system.autoUpgrade.operation" 2>/dev/null)"; then
  report_unknown "No se pudo consultar la estrategia de actualización del host." 2
fi

if [[ "$OPERATION" == "boot" ]]; then
  if [[ "$(readlink -f "$BOOTED")" != "$(readlink -f "$NEXT")" ]]; then
    report_required "Reinicio pendiente: hay una nueva generación preparada."
  else
    report_not_required
  fi
fi

if [[ "$OPERATION" != "switch" ]]; then
  report_unknown "Estrategia de actualización no reconocida: $OPERATION" 2
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

if ((${#changed_components[@]} > 0)); then
  report_required "Reinicio necesario: cambios en ${changed_components[*]}."
fi

if ((unverified)); then
  report_unknown "No se pudo comprobar si hace falta reiniciar." 2
fi

report_not_required
