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

# Bash 5 proporciona EPOCHREALTIME con microsegundos. Convertimos el reloj
# a décimas para que el spinner no repita "0s", "1s", etc. cuatro veces por
# segundo al refrescarse cada 250 ms.
get_clock_tenths() {
  local timestamp="${EPOCHREALTIME:-}"
  local whole_seconds fractional

  if [[ "$timestamp" =~ ^([0-9]+)\.([0-9]{1,6})$ ]]; then
    whole_seconds="${BASH_REMATCH[1]}"
    fractional="${BASH_REMATCH[2]}000000"
    printf '%s%s' "$whole_seconds" "${fractional:0:1}"
  else
    # Compatibilidad con Bash sin EPOCHREALTIME (resolución de un segundo).
    printf '%s0' "$SECONDS"
  fi
}

format_elapsed() {
  local tenths="${1:-0}"
  local total_seconds=$((tenths / 10))
  local tenth_digit=$((tenths % 10))

  if (( total_seconds >= 3600 )); then
    printf '%dh %02dm %02d.%ds' \
      "$((total_seconds / 3600))" \
      "$(((total_seconds % 3600) / 60))" \
      "$((total_seconds % 60))" \
      "$tenth_digit"
  elif (( total_seconds >= 60 )); then
    printf '%dm %02d.%ds' \
      "$((total_seconds / 60))" \
      "$((total_seconds % 60))" \
      "$tenth_digit"
  else
    printf '%d.%ds' "$total_seconds" "$tenth_digit"
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
  EXIT_SUMMARY="$*"
  term_error "$*"
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "No se encuentra el comando requerido: $1"
}

for command in nix git sudo mktemp tail sed date sleep cat env; do
  need_command "$command"
done

HOST="$(hostname -s)"
[[ -n "$HOST" ]] || die "No se pudo detectar el hostname."

# El spinner se pinta en stderr para no contaminar salidas capturadas.
# Solo se activa en terminales interactivas; CI y logs conservan salida limpia.
SPINNER_ACTIVE=no

clear_spinner() {
  if [[ "$SPINNER_ACTIVE" == yes ]]; then
    # El spinner solo ocupa una línea; borrarla deja el cursor listo
    # para que el siguiente mensaje se escriba normalmente.
    printf '\r\033[K' >&2
    SPINNER_ACTIVE=no
  fi
}

NOTIFICATION_ENABLED=no
NOTIFICATION_TASK="Mantenimiento"
EXIT_SUMMARY=""

notify_desktop() {
  local urgency="$1"
  local title="$2"
  local body="$3"
  local bus_address="${DBUS_SESSION_BUS_ADDRESS:-}"

  # Las notificaciones son opcionales: sin libnotify o sin una sesión D-Bus,
  # el mantenimiento sigue funcionando y la terminal conserva los detalles.
  command -v notify-send >/dev/null 2>&1 || return 0

  if [[ -z "$bus_address" && -n "${XDG_RUNTIME_DIR:-}" && -S "${XDG_RUNTIME_DIR}/bus" ]]; then
    bus_address="unix:path=${XDG_RUNTIME_DIR}/bus"
  fi
  [[ -n "$bus_address" ]] || return 0

  DBUS_SESSION_BUS_ADDRESS="$bus_address" notify-send \
    --app-name="Mantenimiento NixOS" \
    --urgency="$urgency" \
    --expire-time=10000 \
    "$title" "$body" >/dev/null 2>&1 || true
}

finish_with_notification() {
  local exit_status="$?"
  local details

  trap - EXIT
  clear_spinner

  if [[ "$NOTIFICATION_ENABLED" == yes ]]; then
    if (( exit_status == 0 )); then
      details="${APPLY_RESULT:-Operación completada correctamente}"
      notify_desktop normal "NixOS · ${HOST:-equipo}" \
        "${NOTIFICATION_TASK}: terminado" "$details"
    else
      details="${EXIT_SUMMARY:-Consulta la terminal para ver los detalles del error.}"
      notify_desktop critical "NixOS · ${HOST:-equipo}" \
        "${NOTIFICATION_TASK}: error (código ${exit_status})" "$details"
    fi
  fi

  exit "$exit_status"
}

trap finish_with_notification EXIT

wait_with_spinner() {
  local command_pid="$1"
  local spinner_started
  local now_tenths
  local frame=0
  local status=0
  local elapsed
  local -a frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

  spinner_started="$(get_clock_tenths)"

  if [[ -t 2 && "${TERM:-dumb}" != "dumb" && -z "${CI:-}" ]]; then
    SPINNER_ACTIVE=yes

    while kill -0 "$command_pid" 2>/dev/null; do
      now_tenths="$(get_clock_tenths)"
      elapsed="$(format_elapsed "$((now_tenths - spinner_started))")"

      # \r vuelve al principio y \033[K limpia el resto de la misma línea.
      # No se imprime ningún salto de línea hasta que termina la operación.
      printf '\r\033[K%b  %s%b  En curso · %s' \
        "$TERM_STYLE_CYAN$TERM_STYLE_BOLD" \
        "${frames[$frame]}" \
        "$TERM_STYLE_RESET" \
        "$elapsed" >&2

      sleep 0.25 || true
      frame=$(((frame + 1) % ${#frames[@]}))
    done

    clear_spinner
  fi

  wait "$command_pid" || status=$?
  return "$status"
}

# Ejecuta cualquier operación mostrando actividad sin inundar la terminal.
# La salida normal se conserva en un temporal y solo se enseña si se solicita
# expresamente o si el comando falla.
run_step_internal() {
  local show_output="$1"
  local description="$2"
  shift 2

  local log_file status started_at finished_at elapsed command_pid

  log_file="$(mktemp)" || die "No se pudo crear un archivo temporal para registrar la operación."
  started_at="$(date +%s)"
  term_step "$description"

  # Autenticar antes de lanzar sudo en segundo plano evita que el spinner
  # sobrescriba una petición interactiva de contraseña.
  if [[ "${1:-}" == sudo ]]; then
    if sudo -v; then
      :
    else
      status=$?
      rm -f "$log_file"
      EXIT_SUMMARY="$description (autenticación sudo cancelada o fallida)"
      term_error "$description (autenticación sudo cancelada o fallida)"
      return "$status"
    fi
  fi

  "$@" >"$log_file" 2>&1 &
  command_pid=$!

  if wait_with_spinner "$command_pid" "$log_file"; then
    finished_at="$(date +%s)"
    elapsed="$((finished_at - started_at))"

    if [[ "$show_output" == yes && -s "$log_file" ]]; then
      cat "$log_file"
    fi

    rm -f "$log_file"
    term_success "Completado · $(format_duration "$elapsed")"
  else
    status=$?
    EXIT_SUMMARY="$description (código $status)"
    term_error "$description (código $status)"
    if [[ -s "$log_file" ]]; then
      term_info "Detalle del error (últimas 20 líneas):"
      tail -n 20 "$log_file" >&2 || true
    fi
    rm -f "$log_file"
    return "$status"
  fi
}

run_step() {
  run_step_internal no "$@"
}

# Variante para comprobaciones que producen un resumen útil en caso de éxito.
run_step_show() {
  run_step_internal yes "$@"
}

# Variante para comandos cuyo stdout se usa como valor de retorno. El progreso
# y los diagnósticos se envían por stderr para que command substitution siga
# recibiendo exclusivamente el resultado del comando.
run_step_capture() {
  local description="$1"
  shift

  local stdout_file stderr_file status started_at finished_at elapsed command_pid

  stdout_file="$(mktemp)" || die "No se pudo crear un temporal para la salida del comando."
  stderr_file="$(mktemp)" || {
    rm -f "$stdout_file"
    die "No se pudo crear un temporal para los errores del comando."
  }

  started_at="$(date +%s)"
  term_step "$description" >&2
  "$@" >"$stdout_file" 2>"$stderr_file" &
  command_pid=$!

  if wait_with_spinner "$command_pid" "$stderr_file"; then
    finished_at="$(date +%s)"
    elapsed="$((finished_at - started_at))"

    if [[ -s "$stderr_file" ]]; then
      cat "$stderr_file" >&2
    fi
    term_success "Completado · $(format_duration "$elapsed")" >&2
    cat "$stdout_file"
  else
    status=$?
    EXIT_SUMMARY="$description (código $status)"
    term_error "$description (código $status)" >&2
    if [[ -s "$stderr_file" ]]; then
      term_info "Detalle del error (últimas 20 líneas):" >&2
      tail -n 20 "$stderr_file" >&2 || true
    fi
    if [[ -s "$stdout_file" ]]; then
      term_info "Salida del comando (últimas 20 líneas):" >&2
      tail -n 20 "$stdout_file" >&2 || true
    fi
    rm -f "$stdout_file" "$stderr_file"
    return "$status"
  fi

  rm -f "$stdout_file" "$stderr_file"
}

if ! run_step "Validando la configuración de $HOST" \
  nix eval --raw ".#nixosConfigurations.$HOST.config.networking.hostName"; then
  die "El host '$HOST' no existe o no se puede evaluar en flake.nix."
fi

get_operation() {
  local operation
  operation="$(run_step_capture \
    "Consultando la estrategia de actualización de $HOST" \
    nix eval --raw ".#nixosConfigurations.$HOST.config.system.autoUpgrade.operation")" ||
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

check_lock_clean() {
  if ! git diff --quiet HEAD -- flake.lock; then
    die "flake.lock ya contiene cambios. Revísalos o guárdalos antes de actualizar."
  fi
}

get_gc_args() {
  local gc_options
  local -a GC_ARGS

  gc_options="$(run_step_capture \
    "Consultando la política de limpieza de $HOST" \
    nix eval --raw ".#nixosConfigurations.$HOST.config.nix.gc.options")" ||
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

  run_step_show "Verificando el estado de reinicio" \
    env NIX_MAINTENANCE_CONTEXT=yes bash "$SCRIPT_DIR/nix-reboot-check.sh"
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
  if run_step_show "Comprobando si hay un reinicio pendiente" \
    env NIX_MAINTENANCE_CONTEXT=yes bash "$SCRIPT_DIR/nix-reboot-check.sh"; then
    reboot_status=0
  else
    reboot_status=$?
  fi
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
    NOTIFICATION_TASK="Mantenimiento"
    NOTIFICATION_ENABLED=yes
    run_maintenance "$automatic"
    ;;
  update)
    [[ "$#" -eq 1 ]] || { usage >&2; exit 2; }
    NOTIFICATION_TASK="Actualización"
    NOTIFICATION_ENABLED=yes
    banner "MODO INTERACTIVO · actualizar y revisar antes de aplicar"
    run_update
    run_build_apply no no
    ;;
  apply)
    [[ "$#" -eq 1 ]] || { usage >&2; exit 2; }
    NOTIFICATION_TASK="Construcción y aplicación"
    NOTIFICATION_ENABLED=yes
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
    NOTIFICATION_TASK="Limpieza de generaciones"
    NOTIFICATION_ENABLED=yes
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
