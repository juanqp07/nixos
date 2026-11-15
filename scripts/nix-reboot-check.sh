#!/usr/bin/env bash
# Comprueba si la generación seleccionada requiere reiniciar el equipo.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$FLAKE_DIR"

# Estilo común de la suite de administración.
# shellcheck source=scripts/terminal-style.sh
source "$SCRIPT_DIR/terminal-style.sh"

MODE="human"
case "${1:-}" in
"")
  ;;
--status)
  MODE="status"
  ;;
-h | --help)
  printf 'Uso: nix-reboot-check.sh [--status]\n'
  printf '  --status  Emite estado|motivo para consumo por otros scripts.\n'
  exit 0
  ;;
*)
  printf 'Uso: nix-reboot-check.sh [--status]\n' >&2
  exit 2
  ;;
esac
[[ "$#" -le 1 ]] || {
  printf 'Uso: nix-reboot-check.sh [--status]\n' >&2
  exit 2
}

HOST="$(hostname -s)"
if [[ "$MODE" == human && "${NIX_MAINTENANCE_CONTEXT:-no}" != "yes" ]]; then
  term_banner "Comprobación de reinicio" "$HOST"
fi

BOOTED="${NIX_REBOOT_CHECK_BOOTED_PATH:-/run/booted-system}"
NEXT="${NIX_REBOOT_CHECK_NEXT_PATH:-/nix/var/nix/profiles/system}"

report_status() {
  local status="$1"
  local reason="$2"

  if [[ "$MODE" == status ]]; then
    printf '%s|%s\n' "$status" "$reason"
    return 0
  fi

  case "$status" in
  required)
    term_warning "Reinicio necesario: $reason."
    ;;
  not-required)
    term_success "No es necesario reiniciar."
    ;;
  unknown)
    term_warning "No se pudo comprobar si hace falta reiniciar: $reason."
    ;;
  esac
}

[[ -e "$BOOTED" ]] || {
  report_status unknown "no se puede identificar el sistema arrancado"
  exit 1
}
[[ -e "$NEXT" ]] || {
  report_status unknown "no se puede identificar la generación seleccionada"
  exit 1
}
if ! OPERATION="$(nix eval --no-write-lock-file --raw ".#nixosConfigurations.$HOST.config.system.autoUpgrade.operation" 2>/dev/null)"; then
  report_status unknown "no se pudo consultar la estrategia de actualización del host"
  exit 2
fi

if [[ "$OPERATION" == "boot" ]]; then
  if [[ "$(readlink -f "$BOOTED")" != "$(readlink -f "$NEXT")" ]]; then
    report_status required "hay una nueva generación preparada para el próximo arranque"
  else
    report_status not-required ""
  fi
  exit 0
fi

if [[ "$OPERATION" != "switch" ]]; then
  report_status unknown "estrategia de actualización no reconocida: $OPERATION"
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

if ((${#changed_components[@]} > 0)); then
  report_status required "cambios en ${changed_components[*]}"
  exit 0
fi

if ((unverified)); then
  report_status unknown "faltan componentes necesarios para comparar las generaciones"
  exit 2
fi

report_status not-required ""
