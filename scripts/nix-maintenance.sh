#!/usr/bin/env bash
# Mantenimiento NixOS: salida resumida y errores con contexto.
# Nunca añade, confirma ni descarta cambios del repositorio automáticamente.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$FLAKE_DIR"

# Estilo común para KDE Plasma, Konsole y sesiones SSH.
# shellcheck source=scripts/terminal-style.sh
source "$SCRIPT_DIR/terminal-style.sh"

# Adaptadores del antiguo vocabulario visual al API compartido term_*.
# Se mantienen locales a este script para no ampliar innecesariamente la
# interfaz de terminal-style.sh.
banner() {
  term_banner "Mantenimiento NixOS" "$1"
}

section() {
  local number="$1"
  local title="$2"
  local description="${3:-}"

  term_section "${number} · ${title}"
  if [[ -n "$description" ]]; then
    term_info "$description"
  fi
}

note() {
  term_info "$*"
}

warning() {
  term_warning "$*"
}

format_duration() {
  local total_seconds="${1:-0}"
  local hours minutes seconds

  [[ "$total_seconds" =~ ^[0-9]+$ ]] || total_seconds=0
  hours=$((total_seconds / 3600))
  minutes=$(((total_seconds % 3600) / 60))
  seconds=$((total_seconds % 60))

  if (( hours > 0 )); then
    printf '%dh %02dm %02ds' "$hours" "$minutes" "$seconds"
  elif (( minutes > 0 )); then
    printf '%dm %02ds' "$minutes" "$seconds"
  else
    printf '%ds' "$seconds"
  fi
}

print_summary() {
  local duration="$1"
  local result="$2"

  term_rule
  term_section "RESUMEN DEL MANTENIMIENTO"
  term_info "Equipo: $HOST"
  term_info "Duración: $(format_duration "$duration")"

  case "$result" in
    "Configuración aplicada"|"Preparada para el próximo arranque")
      term_success "$result"
      ;;
    "Aplicación cancelada")
      term_warning "$result"
      ;;
    *)
      term_info "$result"
      ;;
  esac
}

die() {
  term_error "$*"
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "No se encuentra el comando requerido: $1"
}

for command in nix git sudo mktemp tail date; do
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
  printf '%b  ?%b  %s [s/N] ' "$TERM_STYLE_WARNING$TERM_STYLE_BOLD" "$TERM_STYLE_RESET" "$prompt"
  if ! read -r answer; then
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
  local log_file status started_at finished_at elapsed
  shift

  log_file="$(mktemp)" || die "No se pudo crear un archivo temporal para registrar la operación."
  started_at="$(date +%s)"
  term_step "$description"

  if "$@" >"$log_file" 2>&1; then
    finished_at="$(date +%s)"
    elapsed="$((finished_at - started_at))"
    rm -f "$log_file"
    term_success "Completado · $(format_duration "$elapsed")"
  else
    status=$?
    term_error "$description (código $status)"
    if [[ -s "$log_file" ]]; then
      term_info "Detalle del error (últimas 20 líneas):"
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
      warning "Limpieza omitida: hay una generación pendiente de reinicio."
      return 0
    fi
  fi

  gc_options="$(get_gc_args)"
  read -r -a GC_ARGS <<< "$gc_options"

  if [[ "$automatic" != "yes" ]] &&
    ! confirm "¿Limpiar las generaciones antiguas según la política del sistema?"; then
    note "Limpieza omitida."
    return 0
  fi

  run_step "Limpiando generaciones antiguas" sudo nix-collect-garbage "${GC_ARGS[@]}"
}

build_and_show() {
  run_step "Construyendo la configuración de $HOST" sudo nixos-rebuild build --flake ".#$HOST"
  run_step "Comprobando la activación sin aplicar cambios" sudo nixos-rebuild dry-activate --flake ".#$HOST"
  note "La generación está construida y validada; todavía no se ha aplicado."
}

apply_generation() {
  section "05" "ACTIVACIÓN" "Desplegando la generación validada"
  case "$OPERATION" in
    switch)
      run_step "Aplicando la configuración ahora" sudo nixos-rebuild switch --flake ".#$HOST"
      APPLY_RESULT="Configuración aplicada"
      ;;
    boot)
      run_step "Preparando la configuración para el próximo arranque" sudo nixos-rebuild boot --flake ".#$HOST"
      APPLY_RESULT="Preparada para el próximo arranque"
      ;;
  esac

  term_step "Verificando el estado de reinicio"
  NIX_MAINTENANCE_CONTEXT=yes bash "$SCRIPT_DIR/nix-reboot-check.sh"
}

run_update() {
  section "02" "ACTUALIZACIONES" "Sincronizando las entradas del flake"
  check_lock_clean
  run_step "Actualizando las versiones de los inputs" nix flake update
  # Actualiza la estrategia por si ha cambiado con las nuevas revisiones.
  OPERATION="$(get_operation)"
}

run_build_apply() {
  local automatic="$1"
  local include_clean="$2"
  section "03" "CONSTRUIR Y VALIDAR" "Comprobar que la nueva generación puede activarse"
  build_and_show

  if [[ "$include_clean" == "yes" ]]; then
    section "04" "LIMPIEZA" "Aplicando la política de retención de generaciones"
    if [[ "$automatic" == "yes" ]]; then
      clean_generations yes
    elif confirm "¿Limpiar las generaciones antiguas ahora?"; then
      clean_generations yes
    else
      note "Limpieza omitida."
    fi
  fi

  if [[ "$automatic" == "yes" ]] || confirm "¿Aplicar la nueva configuración en $HOST?"; then
    apply_generation
  else
    APPLY_RESULT="Aplicación cancelada"
    warning "Aplicación cancelada. El sistema sigue usando la generación anterior."
  fi
}

run_maintenance() {
  local automatic="$1"
  local reboot_status=0
  local started_at finished_at mode_label

  started_at="$(date +%s)"
  if [[ "$automatic" == "yes" ]]; then
    mode_label="MODO AUTOMÁTICO · confirmaciones omitidas"
  else
    mode_label="MODO INTERACTIVO · tú decides cuándo aplicar"
  fi
  banner "$mode_label"

  section "01" "COMPROBACIONES" "Revisando el estado de arranque"
  term_step "Comprobando si hay un reinicio pendiente"
  NIX_MAINTENANCE_CONTEXT=yes bash "$SCRIPT_DIR/nix-reboot-check.sh" || reboot_status=$?
  case "$reboot_status" in
    0) ;;
    1) die "Falló la comprobación de reinicio." ;;
    2) die "No se pudo verificar el estado de reinicio." ;;
    *) die "La comprobación de reinicio terminó con un error." ;;
  esac

  run_update
  case "$OPERATION" in
    switch) note "Estrategia: aplicar inmediatamente (switch)." ;;
    boot) note "Estrategia: preparar para el próximo arranque (boot)." ;;
  esac
  APPLY_RESULT="Sin aplicar"
  run_build_apply "$automatic" yes

  finished_at="$(date +%s)"
  print_summary "$((finished_at - started_at))" "$APPLY_RESULT"
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
    banner "MODO INTERACTIVO · actualizar y revisar antes de aplicar"
    run_update
    run_build_apply no no
    ;;
  apply)
    [[ "$#" -eq 1 ]] || { usage >&2; exit 2; }
    banner "MODO INTERACTIVO · versiones fijadas en flake.lock"
    note "No se actualizarán los inputs."
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
    banner "MODO LIMPIEZA · política declarada por el host"
    section "01" "LIMPIEZA" "Revisando generaciones antiguas"
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
