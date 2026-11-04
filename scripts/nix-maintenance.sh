#!/usr/bin/env bash
# Declarative-flake maintenance helpers for the current NixOS host.
# This script never stages, commits, or automatically discards repository changes.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$FLAKE_DIR"

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "No se encuentra el comando requerido: $1"
}

need_command nix
need_command git
need_command sudo
need_command nvd

HOST="$(hostname -s)"
[[ -n "$HOST" ]] || die "No se pudo detectar el hostname."

if ! nix eval --raw ".#nixosConfigurations.$HOST.config.networking.hostName" >/dev/null 2>&1; then
  die "El host '$HOST' no existe o no se puede evaluar en flake.nix."
fi

show_lock_diff() {
  if git diff --quiet HEAD -- flake.lock; then
    printf 'No hay cambios en flake.lock.\n'
  else
    git --no-pager diff -- flake.lock
  fi
}

check_lock_clean() {
  if ! git diff --quiet HEAD -- flake.lock; then
    die "flake.lock ya contiene cambios. Revísalos o guárdalos antes de actualizar para no sobrescribir trabajo previo."
  fi
}

build_and_apply() {
  printf '\n--- Construyendo %s ---\n' "$HOST"
  sudo nixos-rebuild build --flake ".#$HOST" -L

  [[ -e result ]] || die "La construcción terminó sin crear ./result."
  [[ -x result/bin/switch-to-configuration ]] || die "La salida construida no contiene switch-to-configuration."

  printf '\n--- Diferencias respecto al sistema actual ---\n'
  nvd diff /run/current-system result

  printf '\n'
  read -r -p "¿Aplicar esta generación en $HOST? [s/N] " answer
  case "$answer" in
    s|S|si|SI|sí|Sí|sÍ|SÍ)
      printf '\n--- Aplicando generación construida ---\n'
      # Reutiliza exactamente el resultado ya comparado, sin reconstruir.
      sudo ./result/bin/switch-to-configuration switch
      printf '\n--- Comprobación de reinicio ---\n'
      bash "$SCRIPT_DIR/nix-reboot-check.sh"
      ;;
    *)
      printf 'Aplicación cancelada. La generación construida permanece en el almacén.\n'
      ;;
  esac
}

case "${1:-}" in
  update)
    check_lock_clean
    printf '%s\n' '--- Actualizando todos los inputs del flake ---'
    nix flake update
    printf '\n--- Cambios en flake.lock ---\n'
    show_lock_diff
    build_and_apply
    ;;
  apply)
    printf '%s\n' '--- Usando las revisiones existentes en flake.lock ---'
    build_and_apply
    ;;
  clean)
    printf '%s\n' '--- Leyendo política de GC declarada para %s ---' "$HOST"
    gc_options="$(nix eval --raw ".#nixosConfigurations.$HOST.config.nix.gc.options")" ||
      die "No se pudo evaluar nix.gc.options para $HOST."

    # Solo aceptar la política de retención esperada. No ejecutar opciones
    # arbitrarias evaluadas desde una configuración Nix.
    read -r -a gc_args <<< "$gc_options"
    [[ "${#gc_args[@]}" -eq 2 ]] ||
      die "Política GC no reconocida: '$gc_options'. Se esperaba '--delete-older-than Nd'."
    [[ "${gc_args[0]}" == "--delete-older-than" ]] ||
      die "Política GC no reconocida: '$gc_options'."
    [[ "${gc_args[1]}" =~ ^[0-9]+d$ ]] ||
      die "Periodo de retención no válido: '${gc_args[1]}'."

    printf 'Se eliminarán generaciones antiguas según: %s\n' "$gc_options"
    read -r -p "¿Continuar con la limpieza de $HOST? [s/N] " answer
    case "$answer" in
      s|S|si|SI|sí|Sí|sÍ|SÍ)
        sudo nix-collect-garbage "${gc_args[@]}"
        ;;
      *)
        printf 'Limpieza cancelada.\n'
        ;;
    esac
    ;;
  *)
    printf 'Uso: %s {update|apply|clean}\n' "$0" >&2
    exit 2
    ;;
esac
