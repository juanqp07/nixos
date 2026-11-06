#!/usr/bin/env bash
set -Eeuo pipefail

UNIT="rustdesk-privacy-grabber.service"
BACKLIGHT_STATE="/run/rustdesk-privacy-backlight.json"
STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
MODE_FILE="$STATE_DIR/rustdesk-privacy-mode"
SUPPRESS_FILE="$STATE_DIR/rustdesk-privacy-suppress-until-disconnect"
SESSIONS_FILE="$STATE_DIR/rustdesk-privacy-portal-sessions"
LOCK_FILE="$STATE_DIR/rustdesk-privacy.lock"

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

# Serialize manual actions and portal-triggered transitions.
exec 9>"$LOCK_FILE"
flock -x 9

is_active() {
  systemctl is-active --quiet "$UNIT"
}

mode() {
  if [[ -r "$MODE_FILE" ]]; then
    cat "$MODE_FILE"
  else
    printf 'none'
  fi
}

write_mode() {
  local value="$1"
  local temporary
  temporary="$(mktemp "$STATE_DIR/.rustdesk-privacy-mode.XXXXXX")"
  printf '%s\n' "$value" > "$temporary"
  chmod 600 "$temporary"
  mv -f "$temporary" "$MODE_FILE"
}

notify_user() {
  local title="$1"
  local body="$2"

  if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && command -v notify-send >/dev/null 2>&1; then
    notify-send --app-name="RustDesk · Privacidad" --icon="preferences-desktop-screenlocking" "$title" "$body" || true
  fi
}

start_grabber() {
  if is_active; then
    return 0
  fi

  systemctl start --no-ask-password "$UNIT"
}

stop_grabber() {
  if is_active; then
    systemctl stop --no-ask-password "$UNIT"
  fi

  if is_active; then
    printf '  ✗ El servicio sigue activo; revisa systemctl status %s.\n' "$UNIT" >&2
    return 1
  fi

  if [[ -e "$BACKLIGHT_STATE" ]]; then
    printf '  ! Queda una restauración de brillo pendiente en %s.\n' "$BACKLIGHT_STATE" >&2
    printf '    Revisa: sudo journalctl -u %s -n 30\n' "$UNIT" >&2
    return 1
  fi
}

manual_on() {
  printf '  ◌ Activando modo privacidad manual...\n'
  rm -f "$SUPPRESS_FILE"
  write_mode manual

  if ! start_grabber; then
    rm -f "$MODE_FILE"
    printf '  ✗ No se pudo activar. Se ha cancelado el estado manual.\n' >&2
    return 1
  fi

  printf '  ✓ Privacidad ACTIVADA en modo manual.\n'
  printf '  ✓ Se mantendrá activa aunque se desconecte RustDesk.\n'
  notify_user "Privacidad manual activada" "El modo permanecerá activo hasta que lo desactives manualmente."
}

manual_off() {
  # If a remote session is still open, suppress automatic reactivation until
  # its portal session closes. A new connection after that may activate it.
  if [[ -s "$SESSIONS_FILE" ]]; then
    : > "$SUPPRESS_FILE"
    chmod 600 "$SUPPRESS_FILE"
  else
    rm -f "$SUPPRESS_FILE"
  fi

  rm -f "$MODE_FILE"
  printf '  ◌ Desactivando modo privacidad...\n'
  stop_grabber
  printf '  ✓ Privacidad DESACTIVADA.\n'
  notify_user "Privacidad desactivada" "Pantalla y controles físicos restaurados."
}

automatic_on() {
  if [[ "$(mode)" == "manual" ]]; then
    printf '  · Se conserva el modo manual; el evento automático no cambia nada.\n'
    return 0
  fi

  if [[ -e "$SUPPRESS_FILE" ]]; then
    printf '  · Activación automática ignorada: se desactivó manualmente durante esta sesión.\n'
    return 0
  fi

  if is_active; then
    # An active unit with no recorded automatic ownership may have been
    # started manually through systemctl or by an earlier login session.
    # Never claim ownership of it: the watcher must not stop external/manual
    # privacy when the portal session closes.
    if [[ "$(mode)" != "auto" && "$(mode)" != "manual" ]]; then
      write_mode manual
    fi
    return 0
  fi

  printf '  ◌ Sesión remota autenticada: activando privacidad...\n'
  if ! start_grabber; then
    printf '  ✗ No se pudo activar la privacidad automática.\n' >&2
    return 1
  fi

  write_mode auto
  printf '  ✓ Privacidad ACTIVADA automáticamente.\n'
  notify_user "RustDesk conectado" "Pantalla física apagada y controles locales bloqueados."
}

automatic_off() {
  if [[ -s "$SESSIONS_FILE" ]]; then
    printf '  · Aún quedan sesiones RustDesk; se conserva la privacidad.\n'
    return 0
  fi

  rm -f "$SUPPRESS_FILE"

  case "$(mode)" in
    manual)
      printf '  · La privacidad manual permanece activada tras la desconexión.\n'
      return 0
      ;;
    auto)
      printf '  ◌ Última sesión remota cerrada: restaurando el portátil...\n'
      stop_grabber
      rm -f "$MODE_FILE"
      printf '  ✓ Privacidad DESACTIVADA automáticamente.\n'
      notify_user "RustDesk desconectado" "Pantalla y controles físicos restaurados."
      ;;
    *)
      # Never stop a service whose ownership is unknown.
      printf '  · No hay un modo automático que retirar.\n'
      ;;
  esac
}

show_usage() {
  cat <<'EOF'
RustDesk · Privacidad de Elytra

Comandos manuales:
  rustdesk-privacy on       Activa y mantiene la privacidad hasta apagarla manualmente
  rustdesk-privacy off      Desactiva la privacidad manual o automática
  rustdesk-privacy toggle   Alterna el modo manual
  rustdesk-privacy status   Muestra el estado actual

Comandos internos del monitor:
  rustdesk-privacy auto-on  Activa al concederse una sesión de pantalla RustDesk
  rustdesk-privacy auto-off Restaura al cerrarse la última sesión automática
EOF
}

show_status() {
  local current_mode
  current_mode="$(mode)"

  if is_active; then
    case "$current_mode" in
      manual) printf '  ● PRIVACIDAD ACTIVADA · MANUAL\n    Se mantendrá así hasta ejecutar rustdesk-privacy off.\n' ;;
      auto)   printf '  ● PRIVACIDAD ACTIVADA · AUTOMÁTICA\n    Se restaurará al cerrarse la última sesión RustDesk.\n' ;;
      *)      printf '  ● PRIVACIDAD ACTIVADA · ORIGEN EXTERNO\n    El comando no modificará este servicio automáticamente.\n' ;;
    esac
  elif [[ -e "$BACKLIGHT_STATE" ]]; then
    printf '  ! Servicio detenido, pero hay una restauración de brillo pendiente.\n'
    printf '    Consulta: sudo journalctl -u %s -n 30\n' "$UNIT"
    return 1
  else
    printf '  ○ PRIVACIDAD DESACTIVADA\n'
    printf '    Pantalla, teclado y ratón físicos disponibles.\n'
  fi
}

case "${1:-status}" in
  on)
    manual_on
    ;;
  off|emergency-off)
    manual_off
    ;;
  toggle)
    if is_active; then
      manual_off
    else
      manual_on
    fi
    ;;
  auto-on)
    automatic_on
    ;;
  auto-off)
    automatic_off
    ;;
  status)
    show_status
    ;;
  -h|--help|help)
    show_usage
    ;;
  *)
    show_usage >&2
    exit 2
    ;;
esac
