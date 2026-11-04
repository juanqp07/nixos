#!/usr/bin/env bash
# Declarative-flake maintenance helpers for the current NixOS host.
# Never stages, commits, or discards repository changes automatically.

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

for command in nix git sudo nvd; do
  need_command "$command"
done

HOST="$(hostname -s)"
[[ -n "$HOST" ]] || die "No se pudo detectar el hostname."

if ! nix eval --raw ".#nixosConfigurations.$HOST.config.networking.hostName" >/dev/null 2>&1; then
  die "El host '$HOST' no existe o no se puede evaluar en flake.nix."
fi

get_operation() {
  local operation
  operation="$(nix eval --raw ".#nixosConfigurations.$HOST.config.system.autoUpgrade.operation")" ||
    die "No se pudo evaluar system.autoUpgrade.operation para $HOST."
  case "$operation" in
    switch|boot) printf '%s' "$operation" ;;
    *) die "Operación de despliegue no reconocida para $HOST: '$operation'." ;;
  esac
}

# NixOS defaults system.autoUpgrade.operation to "switch" when not set.
OPERATION="$(get_operation)"

confirm() {
  local prompt="$1"
  local answer
  if ! read -r -p "$prompt [s/N] " answer; then
    answer=""
  fi
  case "$answer" in
    s|S|si|SI|sí|Sí|sÍ|SÍ) return 0 ;;
    *) return 1 ;;
  esac
}

show_lock_diff() {
  if git diff --quiet HEAD -- flake.lock; then
    printf 'No hay cambios en flake.lock.\n'
  else
    git --no-pager diff HEAD -- flake.lock
  fi
}

check_lock_clean() {
  if ! git diff --quiet HEAD -- flake.lock; then
    die "flake.lock ya contiene cambios (preparados o sin preparar). Revísalos o guárdalos antes de actualizar."
  fi
}

get_gc_args() {
  local gc_options
  gc_options="$(nix eval --raw ".#nixosConfigurations.$HOST.config.nix.gc.options")" ||
    die "No se pudo evaluar nix.gc.options para $HOST."

  # Only accept the retention policy expected in this repository.
  read -r -a GC_ARGS <<< "$gc_options"
  [[ "${#GC_ARGS[@]}" -eq 2 ]] ||
    die "Política GC no reconocida: '$gc_options'. Se esperaba '--delete-older-than Nd'."
  [[ "${GC_ARGS[0]}" == "--delete-older-than" ]] ||
    die "Política GC no reconocida: '$gc_options'."
  [[ "${GC_ARGS[1]}" =~ ^[0-9]+d$ ]] ||
    die "Periodo de retención no válido: '${GC_ARGS[1]}'."

  printf '%s' "$gc_options"
}

clean_generations() {
  local automatic="$1"
  local gc_options
  gc_options="$(get_gc_args)"

  printf '\n--- Limpieza de generaciones en %s ---\n' "$HOST"
  printf 'Política declarada: %s\n' "$gc_options"
  printf 'La generación activa se conserva; las generaciones antiguas que cumplan el periodo pueden dejar de servir para rollback.\n'

  if [[ "$automatic" != "yes" ]] && ! confirm "¿Eliminar generaciones antiguas según esta política?"; then
    printf 'Limpieza omitida.\n'
    return 0
  fi

  read -r -a GC_ARGS <<< "$gc_options"
  sudo nix-collect-garbage "${GC_ARGS[@]}"
}

build_and_show() {
  printf '\n--- Construyendo configuración de %s ---\n' "$HOST"
  sudo nixos-rebuild build --flake ".#$HOST" -L

  printf '\n--- Diferencias de paquetes y versiones (NVD) ---\n'
  nvd diff /run/current-system result

  printf '\n--- Simulación de activación (sin aplicar cambios) ---\n'
  sudo nixos-rebuild dry-activate --flake ".#$HOST" -L
}

apply_generation() {
  printf '\n--- Aplicando según la política de %s ---\n' "$HOST"
  case "$OPERATION" in
    switch)
      printf 'Operación: switch (activa ahora la configuración).\n'
      sudo nixos-rebuild switch --flake ".#$HOST" -L
      ;;
    boot)
      printf 'Operación: boot (prepara la generación para el próximo arranque; no reinicia).\n'
      sudo nixos-rebuild boot --flake ".#$HOST" -L
      ;;
  esac

  printf '\n--- Comprobación de reinicio/activación pendiente ---\n'
  bash "$SCRIPT_DIR/nix-reboot-check.sh"
}

run_update() {
  check_lock_clean
  printf '\n--- Actualizando todos los inputs del flake ---\n'
  nix flake update
  printf '\n--- Cambios en flake.lock ---\n'
  show_lock_diff
}

run_build_apply() {
  local automatic="$1"
  local include_clean="$2"
  build_and_show

  if [[ "$include_clean" == "yes" ]]; then
    if [[ "$automatic" == "yes" ]]; then
      clean_generations yes
    elif confirm "¿Aplicar la limpieza de generaciones antiguas ahora?"; then
      clean_generations yes
    else
      printf 'Limpieza omitida.\\n'
    fi
  fi

  if [[ "$automatic" == "yes" ]] || confirm "¿Aplicar la nueva generación en $HOST?"; then
    apply_generation
  else
    printf 'Aplicación cancelada. La configuración construida permanece en /nix/store.\\n'
  fi
}

run_maintenance() {
  local automatic="$1"

  printf '\n========== MANTENIMIENTO NIXOS: %s ==========\n' "$HOST"
  printf 'Estrategia de aplicación declarada: %s\n' "$OPERATION"

  printf '\n--- Estado previo de reinicio ---\n'
  bash "$SCRIPT_DIR/nix-reboot-check.sh" || {
    status=$?
    [[ "$status" -eq 2 ]] && die "No se pudo verificar el estado previo de reinicio."
    [[ "$status" -eq 1 ]] && die "Falló la comprobación previa de reinicio."
  }

  printf '\n--- Generaciones actuales ---\n'
  sudo nixos-rebuild list-generations

  run_update
  run_build_apply "$automatic" yes yes

  printf '\n========== MANTENIMIENTO FINALIZADO: %s ==========\n' "$HOST"
}

usage() {
  cat <<'EOF'
Uso:
  nix-maintenance.sh maintain [-y|--yes]
  nix-maintenance.sh update
  nix-maintenance.sh apply
  nix-maintenance.sh clean [-y|--yes]

Comandos:
  maintain  Actualiza todos los inputs, construye, muestra cambios,
            limpia según la política del host y aplica con switch/boot.
  update    Actualiza todos los inputs, construye y pregunta antes de aplicar.
  apply     Construye con el flake.lock existente y pregunta antes de aplicar.
  clean     Limpia generaciones antiguas según nix.gc.options del host.

Opciones:
  -y, --yes  Omite confirmaciones en maintain y clean.
EOF
}

case "${1:-}" in
  maintain)
    shift
    automatic="no"
    if [[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]]; then
      automatic="yes"
      shift
    fi
    [[ "$#" -eq 0 ]] || { usage >&2; exit 2; }
    run_maintenance "$automatic"
    ;;
  update)
    [[ "$#" -eq 1 ]] || { usage >&2; exit 2; }
    run_update
    run_build_apply no no
    ;;
  apply)
    [[ "$#" -eq 1 ]] || { usage >&2; exit 2; }
    printf '%s\n' '--- Usando las revisiones existentes en flake.lock ---'
    run_build_apply no no
    ;;
  clean)
    shift
    automatic="no"
    if [[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]]; then
      automatic="yes"
      shift
    fi
    [[ "$#" -eq 0 ]] || { usage >&2; exit 2; }
    clean_generations "$automatic"
    ;;
  -h|--help|"")
    usage
    [[ -n "${1:-}" ]] || exit 2
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
