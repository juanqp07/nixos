#!/usr/bin/env bash
set -Eeuo pipefail

UNIT="rustdesk-privacy-grabber.service"
STATE_FILE="/run/rustdesk-privacy-backlight.json"

is_active() {
  systemctl is-active --quiet "$UNIT"
}

notify_user() {
  local title="$1"
  local body="$2"

  if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && command -v notify-send >/dev/null 2>&1; then
    notify-send --app-name="RustDesk · Privacidad" --icon="preferences-desktop-screenlocking" "$title" "$body" || true
  fi
}

show_usage() {
  cat <<'EOF'
RustDesk · Modo privacidad de Elytra

Uso:
  rustdesk-privacy on       Apaga la pantalla física y bloquea la entrada local
  rustdesk-privacy off      Restaura la pantalla, teclado y ratón
  rustdesk-privacy toggle   Alterna el modo privacidad
  rustdesk-privacy status   Muestra el estado actual
EOF
}

activate_privacy() {
  if is_active; then
    printf '  ✓ El modo privacidad ya está activado.\n'
    return 0
  fi

  printf '  ◌ Activando privacidad de RustDesk...\n'
  if ! systemctl start --no-ask-password "$UNIT"; then
    printf '  ✗ No se pudo activar. La entrada física se ha liberado y se ha intentado restaurar el brillo.\n' >&2
    return 1
  fi

  printf '  ✓ Pantalla física apagada; teclado y ratón físicos bloqueados.\n'
  printf '  ✓ La entrada virtual de RustDesk permanece disponible.\n'
  notify_user "Modo privacidad activado" "Pantalla física y controles locales bloqueados."
}

deactivate_privacy() {
  if is_active; then
    printf '  ◌ Desactivando privacidad de RustDesk...\n'
    systemctl stop --no-ask-password "$UNIT"
  fi

  if is_active; then
    printf '  ✗ El servicio sigue activo; revisa systemctl status %s.\n' "$UNIT" >&2
    return 1
  fi

  if [[ -e "$STATE_FILE" ]]; then
    printf '  ! Queda un estado de brillo pendiente en %s.\n' "$STATE_FILE" >&2
    printf '    Revisa: sudo journalctl -u %s -n 30\n' "$UNIT" >&2
    return 1
  fi

  printf '  ✓ Pantalla, teclado y ratón físicos restaurados.\n'
  notify_user "Modo privacidad desactivado" "Pantalla y controles locales restaurados."
}

show_status() {
  if is_active; then
    printf '  ● PRIVACIDAD ACTIVADA\n'
    printf '    Pantalla física apagada; entradas locales aisladas.\n'
    printf '    Parada automática de seguridad: máximo 12 horas.\n'
  elif [[ -e "$STATE_FILE" ]]; then
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
    activate_privacy
    ;;
  off|emergency-off)
    deactivate_privacy
    ;;
  toggle)
    if is_active; then
      deactivate_privacy
    else
      activate_privacy
    fi
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
