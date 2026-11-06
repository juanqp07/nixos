#!/usr/bin/env bash
# Mantenimiento NixOS: salida resumida y errores con contexto.
# Nunca añade, confirma ni descarta cambios del repositorio automáticamente.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$FLAKE_DIR"

die() {
  printf '❌ Error: %s\n' "$*" >&2
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "No se encuentra el comando requerido: $1"
}

for command in nix git sudo mktemp tail; do
  need_command "$command"
done

HOST="$(hostname -s)"
[[ -n "$HOST" ]] || die "No se pudo detectar el hostname."

if ! nix eval --raw ".#nixosConfigurations.$HOST.config.networking.hostName" >/dev/null 2>&1; then
  die "El host '$HOST' no existe o no se puede evaluar en flake.nix."
fi

get_operation() {
  local operation
  operation="$(nix eval --raw ".#nixosConfigurations.$HOST.config.system.autoUpgrade.operation" 2>/dev/null)" ||
    die "No se pudo consultar la estrategia de actualización de $HOST."
  case "$operation" in
    switch|boot) printf '%s' "$operation" ;;
    *) die "Estrategia de actualización no reconocida para $HOST." ;;
  esac
}

# NixOS usa switch por defecto si no se declara otra operación.
OPERATION="$(get_operation)"

confirm() {
  local prompt="$1"
  local answer
  if ! read -r -p "❓ $prompt [s/N] " answer; then
    answer=""
  fi
  case "$answer" in
    s|S|si|SI|sí|Sí|sÍ|SÍ) return 0 ;;
    *) return 1 ;;
  esac
}

# Oculta la salida normal de cada comando. Si falla, muestra solo las
# últimas líneas para que el error siga siendo útil sin inundar la terminal.
run_step() {
  local description="$1"
  local log_file status
  shift

  log_file="$(mktemp)" || die "No se pudo crear un archivo temporal para registrar la operación."
  printf '▶ %s...\n' "$description"

  if "$@" >"$log_file" 2>&1; then
    rm -f "$log_file"
    printf '✅ %s completado.\n' "$description"
  else
    status=$?
    printf '❌ %s (código %s).\n' "$description" "$status" >&2
    if [[ -s "$log_file" ]]; then
      printf 'Detalle del error (últimas 20 líneas):\n' >&2
      tail -n 20 "$log_file" >&2 || true
    fi
    rm -f "$log_file"
    return "$status"
  fi
}

check_lock_clean() {
  if ! git diff --quiet HEAD -- flake.lock; then
    die "flake.lock ya contiene cambios. Revísalos o guárdalos antes de actualizar."
  fi
}

get_gc_args() {
  local gc_options
  gc_options="$(nix eval --raw ".#nixosConfigurations.$HOST.config.nix.gc.options" 2>/dev/null)" ||
    die "No se pudo consultar la política de limpieza de $HOST."

  # Solo se acepta la política de retención declarada para este repositorio.
  read -r -a GC_ARGS <<< "$gc_options"
  [[ "${#GC_ARGS[@]}" -eq 2 ]] ||
    die "La política de limpieza configurada no tiene el formato esperado."
  [[ "${GC_ARGS[0]}" == "--delete-older-than" ]] ||
    die "La política de limpieza configurada no está reconocida."
  [[ "${GC_ARGS[1]}" =~ ^[0-9]+d$ ]] ||
    die "El periodo de retención configurado no es válido."

  printf '%s' "$gc_options"
}

clean_generations() {
  local automatic="$1"
  local gc_options
  local -a GC_ARGS

  # En modo boot no se borran generaciones mientras la nueva siga pendiente.
  if [[ "$OPERATION" == "boot" && -e /run/booted-system && -e /nix/var/nix/profiles/system ]]; then
    if [[ "$(readlink -f /run/booted-system)" != "$(readlink -f /nix/var/nix/profiles/system)" ]]; then
      printf '⏭️  Limpieza omitida: hay una generación pendiente de reinicio.\n'
      return 0
    fi
  fi

  gc_options="$(get_gc_args)"
  read -r -a GC_ARGS <<< "$gc_options"

  if [[ "$automatic" != "yes" ]] &&
    ! confirm "¿Limpiar las generaciones antiguas según la política del sistema?"; then
    printf '⏭️  Limpieza omitida.\n'
    return 0
  fi

  run_step "Limpiando generaciones antiguas" sudo nix-collect-garbage "${GC_ARGS[@]}"
}

build_and_show() {
  run_step "Construyendo la configuración de $HOST" sudo nixos-rebuild build --flake ".#$HOST"
  run_step "Comprobando la activación sin aplicar cambios" sudo nixos-rebuild dry-activate --flake ".#$HOST"
  printf 'ℹ️  La configuración está construida; todavía no se ha aplicado.\n'
}

apply_generation() {
  case "$OPERATION" in
    switch)
      run_step "Aplicando la configuración ahora" sudo nixos-rebuild switch --flake ".#$HOST"
      ;;
    boot)
      run_step "Preparando la configuración para el próximo arranque" sudo nixos-rebuild boot --flake ".#$HOST"
      ;;
  esac

  printf '🔎 Comprobando si hace falta reiniciar...\n'
  bash "$SCRIPT_DIR/nix-reboot-check.sh"
}

run_update() {
  check_lock_clean
  run_step "Actualizando las versiones de los inputs" nix flake update
  # Actualiza la estrategia por si ha cambiado con las nuevas revisiones.
  OPERATION="$(get_operation)"
}

run_build_apply() {
  local automatic="$1"
  local include_clean="$2"
  build_and_show

  if [[ "$include_clean" == "yes" ]]; then
    if [[ "$automatic" == "yes" ]]; then
      clean_generations yes
    elif confirm "¿Limpiar las generaciones antiguas ahora?"; then
      clean_generations yes
    else
      printf '⏭️  Limpieza omitida.\n'
    fi
  fi

  if [[ "$automatic" == "yes" ]] || confirm "¿Aplicar la nueva configuración en $HOST?"; then
    apply_generation
  else
    printf '⏭️  Aplicación cancelada. No se ha cambiado el sistema.\n'
  fi
}

run_maintenance() {
  local automatic="$1"
  local reboot_status=0

  printf '\n🛠️  Mantenimiento de NixOS · %s\n' "$HOST"

  printf '🔎 Comprobando el estado del sistema...\n'
  bash "$SCRIPT_DIR/nix-reboot-check.sh" || reboot_status=$?
  case "$reboot_status" in
    0) ;;
    1) die "Falló la comprobación de reinicio." ;;
    2) die "No se pudo verificar el estado de reinicio." ;;
    *) die "La comprobación de reinicio terminó con un error." ;;
  esac

  run_update
  printf '📌 La configuración se aplicará mediante: %s\n' "$OPERATION"
  run_build_apply "$automatic" yes

  printf '\n🎉 Mantenimiento finalizado · %s\n' "$HOST"
}

usage() {
  cat <<'EOF'
Uso:
  nix-maintenance.sh maintain [-y|--yes]
  nix-maintenance.sh update
  nix-maintenance.sh apply
  nix-maintenance.sh clean [-y|--yes]

Comandos:
  maintain  Actualiza, construye, limpia según la política del host y aplica.
  update    Actualiza los inputs, construye y pregunta antes de aplicar.
  apply     Construye con las versiones fijadas y pregunta antes de aplicar.
  clean     Limpia las generaciones antiguas según la política del host.

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
    printf '🔒 Usando las versiones existentes en flake.lock.\n'
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
