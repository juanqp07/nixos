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
  if [[ "$INPUTS_CHANGED" == yes ]]; then
    term_info "Inputs del flake: se han detectado cambios en flake.lock"
  elif [[ -n "$LOCK_SNAPSHOT" && -f "$LOCK_SNAPSHOT" ]]; then
    term_info "Inputs del flake: sin cambios"
  fi
  if [[ "$PACKAGE_DIFF_AVAILABLE" == yes ]]; then
    term_info "Paquetes: $PACKAGE_UPDATED modificados · $PACKAGE_ADDED añadidos · $PACKAGE_REMOVED eliminados"
  fi

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

for command in nix git sudo mktemp tail sed date sleep cat env cp diff readlink basename df; do
  need_command "$command"
done

HOST="$(hostname -s)"
[[ -n "$HOST" ]] || die "No se pudo detectar el hostname."

# El spinner se pinta en stderr para no contaminar salidas capturadas.
# Solo se activa en terminales interactivas; CI y logs conservan salida limpia.
SPINNER_ACTIVE=no

clear_spinner() {
  if [[ "$SPINNER_ACTIVE" == yes ]]; then
    # wait_with_spinner deja el cursor al final de la segunda línea.
    # Subimos al estado, limpiamos las dos líneas y dejamos el cursor en la
    # posición inicial para que el siguiente mensaje no herede texto antiguo.
    printf '\033[1A\r\033[2K\033[1B\r\033[2K\033[1A\r' >&2
    SPINNER_ACTIVE=no
  fi
}

NOTIFICATION_ENABLED=no
NOTIFICATION_TASK="Mantenimiento"
EXIT_SUMMARY=""

# Informe de cambios: se conserva la generación anterior y una copia del lock
# solo durante esta ejecución. Nunca se modifica ni se restaura el repositorio.
REPORT_DIR=""
LOCK_SNAPSHOT=""
BUILD_OUT_LINK=""
BASE_SYSTEM=""
PREVIOUS_SELECTED_SYSTEM=""
NEW_SYSTEM=""
INPUTS_CHANGED=no
PACKAGE_DIFF_AVAILABLE=no
PACKAGE_UPDATED=0
PACKAGE_ADDED=0
PACKAGE_REMOVED=0

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

  if [[ -n "$REPORT_DIR" && -d "$REPORT_DIR" ]]; then
    rm -rf -- "$REPORT_DIR"
  fi

  exit "$exit_status"
}

trap finish_with_notification EXIT

wait_with_spinner() {
  local command_pid="$1"
  local log_file="${2:-}"
  local spinner_started
  local now_tenths
  local frame=0
  local status=0
  local elapsed
  local preview_line preview_width terminal_rows terminal_columns
  local command_preview
  local -a command_args=("${@:3}")
  local -a frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

  # Los comandos de captura (nix eval --raw, por ejemplo) pueden no escribir
  # nada hasta finalizar. Mostrar el comando desde el primer frame evita que
  # "En curso" aparezca vacío; cuando haya salida, se sustituye por su última línea.
  if (("${#command_args[@]}" > 0)); then
    printf -v command_preview '%q ' "${command_args[@]}"
    command_preview="${command_preview% }"
  else
    command_preview="proceso PID $command_pid"
  fi

  spinner_started="$(get_clock_tenths)"

  if [[ -t 2 && "${TERM:-dumb}" != "dumb" && -z "${CI:-}" ]]; then
    while kill -0 "$command_pid" 2>/dev/null; do
      now_tenths="$(get_clock_tenths)"
      elapsed="$(format_elapsed "$((now_tenths - spinner_started))")"

      # Leer la última línea del registro y eliminar ANSI/controles para que
      # la vista previa no rompa el panel de dos líneas.
      if [[ -n "$log_file" && -s "$log_file" ]]; then
        preview_line="$(tail -n 1 -- "$log_file" 2>/dev/null | \
          sed -E 's/\x1B\[[0-9;?]*[ -/]*[@-~]//g; s/\r/ /g; s/[[:cntrl:]]//g' || true)"
      else
        preview_line=""
      fi

      if [[ -z "$preview_line" ]]; then
        preview_line="Ejecutando: $command_preview"
      fi

      # Usar el ancho real de la terminal; COLUMNS queda como alternativa.
      if read -r terminal_rows terminal_columns < <(stty size 2>/dev/null); then
        preview_width="$terminal_columns"
      else
        preview_width="${COLUMNS:-100}"
      fi
      [[ "$preview_width" =~ ^[0-9]+$ ]] || preview_width=100
      preview_width=$((preview_width - 8))
      (( preview_width < 20 )) && preview_width=20
      if (( ${#preview_line} > preview_width )); then
        preview_line="${preview_line:0:$((preview_width - 1))}…"
      fi

      # El panel ocupa exactamente dos líneas. En cada refresco subimos una
      # fila con CSI A y volvemos al inicio; así no dependemos de ESC[s/ESC[u
      # (save/restore), que algunas capturas de terminal no reproducen bien.
      if [[ "$SPINNER_ACTIVE" == yes ]]; then
        printf '\033[1A\r' >&2
      fi
      printf '\033[2K%b  %s%b  En curso · %s\n\033[2K%b    ↳ %s%b' \
        "$TERM_STYLE_CYAN$TERM_STYLE_BOLD" \
        "${frames[$frame]}" \
        "$TERM_STYLE_RESET" \
        "$elapsed" \
        "$TERM_STYLE_MUTED" \
        "$preview_line" \
        "$TERM_STYLE_RESET" >&2
      SPINNER_ACTIVE=yes

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

  if wait_with_spinner "$command_pid" "$log_file" "$@"; then
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

  if wait_with_spinner "$command_pid" "$stderr_file" "$@"; then
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


prepare_report_context() {
  REPORT_DIR="$(mktemp -d)" || die "No se pudo crear el directorio temporal del informe."
  LOCK_SNAPSHOT="$REPORT_DIR/flake.lock.before"
  BUILD_OUT_LINK="$REPORT_DIR/system-build"
}

capture_baseline() {
  BASE_SYSTEM=""
  PREVIOUS_SELECTED_SYSTEM=""

  if [[ -e /run/booted-system ]]; then
    BASE_SYSTEM="$(readlink -f /run/booted-system 2>/dev/null || true)"
  fi
  if [[ -e /nix/var/nix/profiles/system ]]; then
    PREVIOUS_SELECTED_SYSTEM="$(readlink -f /nix/var/nix/profiles/system 2>/dev/null || true)"
  fi
  if [[ -z "$BASE_SYSTEM" || ! -d "$BASE_SYSTEM" ]]; then
    BASE_SYSTEM="$PREVIOUS_SELECTED_SYSTEM"
  fi
  [[ -d "$BASE_SYSTEM" ]] || BASE_SYSTEM=""

  term_section "ESTADO INICIAL"
  if [[ -n "$BASE_SYSTEM" ]]; then
    term_info "Generación arrancada: $BASE_SYSTEM"
  else
    term_warning "No se ha podido identificar la generación arrancada."
  fi
  if [[ -n "$PREVIOUS_SELECTED_SYSTEM" ]]; then
    term_info "Generación seleccionada: $PREVIOUS_SELECTED_SYSTEM"
  fi
  term_info "Nix: $(nix --version 2>/dev/null || printf 'versión no disponible')"
}

system_version() {
  local system_path="$1"
  local version=""

  # El toplevel contiene el valor de versión generado para esa generación.
  # Leerlo evita ejecutar un nixos-version que pudiera consultar el sistema activo.
  if [[ -r "$system_path/nixos-version" ]]; then
    version="$(sed -n '1p' "$system_path/nixos-version" || true)"
  fi
  if [[ -n "$version" ]]; then
    printf '%s' "$version"
  else
    basename "$system_path"
  fi
}

system_kernel() {
  local system_path="$1"
  local kernel_path=""

  if [[ -e "$system_path/kernel" ]]; then
    kernel_path="$(readlink -f "$system_path/kernel" 2>/dev/null || true)"
  fi
  if [[ -n "$kernel_path" ]]; then
    basename "$kernel_path"
  else
    printf 'no disponible'
  fi
}

show_generation_metadata() {
  local old_version old_kernel new_version new_kernel

  term_section "GENERACIONES COMPARADAS"
  if [[ -n "$BASE_SYSTEM" ]]; then
    old_version="$(system_version "$BASE_SYSTEM")"
    old_kernel="$(system_kernel "$BASE_SYSTEM")"
    term_info "Anterior: $old_version"
    term_info "Kernel anterior: $old_kernel"
    term_info "Ruta anterior: $BASE_SYSTEM"
  else
    term_warning "No hay una generación anterior legible para comparar."
  fi

  new_version="$(system_version "$NEW_SYSTEM")"
  new_kernel="$(system_kernel "$NEW_SYSTEM")"
  term_info "Nueva: $new_version"
  term_info "Kernel nuevo: $new_kernel"
  term_info "Ruta nueva: $NEW_SYSTEM"

  if [[ -n "$PREVIOUS_SELECTED_SYSTEM" && "$PREVIOUS_SELECTED_SYSTEM" != "$BASE_SYSTEM" ]]; then
    term_info "Aviso: la generación seleccionada antes del mantenimiento no coincidía con la arrancada."
    term_info "Seleccionada antes: $PREVIOUS_SELECTED_SYSTEM"
  fi
}

show_flake_input_changes() {
  local status=0

  term_section "CAMBIOS EN INPUTS / FLAKE.LOCK"
  if [[ ! -f "$LOCK_SNAPSHOT" ]]; then
    term_skip "No se ha actualizado flake.lock en esta operación."
    return 0
  fi

  if diff -u --label "flake.lock (antes)" --label "flake.lock (después)" \
    "$LOCK_SNAPSHOT" "$FLAKE_DIR/flake.lock"; then
    term_success "Los inputs no han cambiado."
  else
    status=$?
    if (( status == 1 )); then
      INPUTS_CHANGED=yes
      term_info "Diff completo: revisiones, hashes y metadatos de los inputs modificados."
    else
      warning "No se pudo generar el diff de flake.lock (código $status)."
    fi
  fi
}

show_closure_changes() {
  local diff_output=""
  local counts=""

  term_section "CAMBIOS REALES EN PAQUETES"
  if [[ -z "$BASE_SYSTEM" || ! -d "$BASE_SYSTEM" ]]; then
    warning "No hay una generación anterior válida; se omite la comparación de paquetes."
    return 0
  fi
  if [[ -z "$NEW_SYSTEM" || ! -d "$NEW_SYSTEM" ]]; then
    warning "No se ha encontrado la nueva generación construida."
    return 0
  fi

  if diff_output="$(run_step_capture \
    "Comparando las clausuras NixOS anterior y nueva" \
    nix store diff-closures "$BASE_SYSTEM" "$NEW_SYSTEM")"; then
    PACKAGE_DIFF_AVAILABLE=yes
    if [[ -z "$diff_output" ]]; then
      PACKAGE_UPDATED=0
      PACKAGE_ADDED=0
      PACKAGE_REMOVED=0
      term_success "No se detectan diferencias de paquetes entre ambas generaciones."
      return 0
    fi

    counts="$(printf '%s\n' "$diff_output" | awk '
      /: ∅ →/ { added++; next }
      /→ ∅/ { removed++; next }
      NF { modified++ }
      END { printf "%d %d %d", modified, added, removed }
    ')"
    read -r PACKAGE_UPDATED PACKAGE_ADDED PACKAGE_REMOVED <<< "$counts"

    term_success "Resultado: $PACKAGE_UPDATED modificados · $PACKAGE_ADDED añadidos · $PACKAGE_REMOVED eliminados"
    term_info "Detalle completo de nix store diff-closures (versiones y cambios de tamaño):"
    printf '%s\n' "$diff_output"
    term_info "Nix omite cambios de tamaño inferiores a 8 KiB cuando no cambia la versión."
  else
    warning "No se pudo calcular el diff de paquetes. La construcción sigue siendo válida; revisa el error anterior."
  fi
}

show_store_usage() {
  local label="$1"

  term_section "ESPACIO EN DISCO · $label"
  if ! df -h /nix/store; then
    warning "No se pudo consultar el espacio disponible en /nix/store."
  fi
}

show_final_system_state() {
  local selected booted

  term_section "ESTADO FINAL DEL SISTEMA"
  selected="$(readlink -f /nix/var/nix/profiles/system 2>/dev/null || true)"
  booted="$(readlink -f /run/booted-system 2>/dev/null || true)"
  [[ -n "$selected" ]] && term_info "Generación seleccionada: $selected"
  [[ -n "$booted" ]] && term_info "Generación arrancada: $booted"

  if [[ -n "$selected" && -n "$booted" && "$selected" != "$booted" ]]; then
    warning "La generación seleccionada y la arrancada son distintas; puede quedar un reinicio pendiente."
  fi

  if command -v nix-env >/dev/null 2>&1; then
    if ! run_step_show "Consultando todas las generaciones del perfil del sistema" \
      sudo nix-env --profile /nix/var/nix/profiles/system --list-generations; then
      warning "No se pudo listar el historial de generaciones."
    fi
  fi
  show_store_usage "DESPUÉS DEL MANTENIMIENTO"
}

if ! run_step "Validando la configuración de $HOST" \
  nix eval --no-write-lock-file --raw ".#nixosConfigurations.$HOST.config.networking.hostName"; then
  die "El host '$HOST' no existe o no se puede evaluar en flake.nix."
fi

get_operation() {
  local operation
  operation="$(run_step_capture \
    "Consultando la estrategia de actualización de $HOST" \
    nix eval --no-write-lock-file --raw ".#nixosConfigurations.$HOST.config.system.autoUpgrade.operation")" ||
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
    local lock_status lock_summary
    lock_status="$(git status --short -- flake.lock || true)"
    lock_summary="$(git diff --stat HEAD -- flake.lock || true)"

    warning "flake.lock contiene cambios locales respecto a HEAD."
    [[ -z "$lock_status" ]] || term_info "Estado: $lock_status"
    [[ -z "$lock_summary" ]] || term_info "$lock_summary"
    note "Inspección: git diff HEAD -- flake.lock"
    note "Para conservarlos, crea un commit o guárdalos con: git stash push -m 'flake.lock pendiente' -- flake.lock"
    die "No se han descartado ni sobrescrito cambios. Revisa flake.lock y vuelve a ejecutar."
  fi
}

get_gc_args() {
  local gc_options
  local -a GC_ARGS

  gc_options="$(run_step_capture \
    "Consultando la política de limpieza de $HOST" \
    nix eval --no-write-lock-file --raw ".#nixosConfigurations.$HOST.config.nix.gc.options")" ||
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

  run_step_show "Limpiando generaciones antiguas" sudo nix-collect-garbage "${GC_ARGS[@]}"
}

build_and_show() {
  [[ -n "$REPORT_DIR" && -d "$REPORT_DIR" ]] ||
    die "No se ha preparado el directorio temporal del informe."
  rm -f -- "$BUILD_OUT_LINK"

  run_step_show "Construyendo la clausura completa de $HOST" \
    sudo nix build --show-trace --print-build-logs --no-write-lock-file \
      --out-link "$BUILD_OUT_LINK" \
      ".#nixosConfigurations.$HOST.config.system.build.toplevel"

  [[ -e "$BUILD_OUT_LINK" ]] ||
    die "Nix terminó la construcción, pero no creó el enlace a la nueva generación."
  NEW_SYSTEM="$(readlink -f "$BUILD_OUT_LINK")"
  [[ "$NEW_SYSTEM" == /nix/store/* && -d "$NEW_SYSTEM" ]] ||
    die "La ruta generada no apunta a una clausura válida de /nix/store."

  show_generation_metadata
  show_closure_changes

  run_step_show "Comprobando la activación sin aplicar cambios" \
    sudo nixos-rebuild dry-activate --no-write-lock-file --flake ".#$HOST"
  note "La generación está construida y validada; todavía no se ha aplicado."
}

apply_generation() {
  section "05" "ACTIVACIÓN" "Desplegando la generación validada"
  case "$OPERATION" in
    switch)
      run_step_show "Aplicando la configuración ahora" sudo nixos-rebuild switch --no-write-lock-file --flake ".#$HOST"
      APPLY_RESULT="Configuración aplicada"
      ;;
    boot)
      run_step_show "Preparando la configuración para el próximo arranque" sudo nixos-rebuild boot --no-write-lock-file --flake ".#$HOST"
      APPLY_RESULT="Preparada para el próximo arranque"
      ;;
  esac

  run_step_show "Verificando el estado de reinicio" \
    env NIX_MAINTENANCE_CONTEXT=yes bash "$SCRIPT_DIR/nix-reboot-check.sh"
  show_final_system_state
}

run_update() {
  section "02" "ACTUALIZACIONES" "Sincronizando las entradas del flake"
  check_lock_clean
  cp -- "$FLAKE_DIR/flake.lock" "$LOCK_SNAPSHOT"
  run_step_show "Actualizando las versiones de los inputs" nix flake update
  show_flake_input_changes
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
  prepare_report_context
  if [[ "$automatic" == "yes" ]]; then
    mode_label="MODO AUTOMÁTICO · confirmaciones omitidas"
  else
    mode_label="MODO INTERACTIVO · tú decides cuándo aplicar"
  fi
  banner "$mode_label"
  capture_baseline
  show_store_usage "ANTES DEL MANTENIMIENTO"

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
    prepare_report_context
    capture_baseline
    show_store_usage "ANTES DE ACTUALIZAR"
    banner "MODO INTERACTIVO · actualizar y revisar antes de aplicar"
    run_update
    run_build_apply no no
    ;;
  apply)
    [[ "$#" -eq 1 ]] || { usage >&2; exit 2; }
    NOTIFICATION_TASK="Construcción y aplicación"
    NOTIFICATION_ENABLED=yes
    prepare_report_context
    capture_baseline
    show_store_usage "ANTES DE CONSTRUIR"
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
