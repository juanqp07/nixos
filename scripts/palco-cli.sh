#!/usr/bin/env bash
# Acciones de administración de Palco, presentadas con el estilo común.
# TERMINAL_STYLE_LIB permite usar la biblioteca desde el paquete NixOS.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STYLE_LIB="${TERMINAL_STYLE_LIB:-$SCRIPT_DIR/terminal-style.sh}"

if [[ ! -r "$STYLE_LIB" ]]; then
  printf 'No se encuentra la biblioteca de estilo: %s\\n' "$STYLE_LIB" >&2
  exit 1
fi
# shellcheck source=scripts/terminal-style.sh
source "$STYLE_LIB"

usage() {
  cat <<'EOF'
Uso: palco-command <acción>

Acciones:
  bolo        Desactiva Wi-Fi y deja Bluetooth visible/emparejable.
  config      Reactiva Wi-Fi para configurar la red.
  estado      Muestra Bluetooth, audio, ALSA y servicios fallidos.
  bt          Muestra el estado y los dispositivos Bluetooth.
  dsp-check   Comprueba el nodo DSP de PipeWire.
  audio-test  Inicia la prueba de altavoces (Ctrl+C para detenerla).
EOF
}

run_step() {
  local description="$1"
  shift

  term_step "$description"
  if "$@"; then
    term_success "$description"
  else
    local status=$?
    term_error "$description (código $status)"
    return "$status"
  fi
}

show_section() {
  local title="$1"
  shift
  term_section "$title"
  "$@"
}

case "${1:-}" in
  bolo)
    [[ "$#" -eq 1 ]] || { usage >&2; exit 2; }
    term_banner "Palco · Modo bolo" "Wi-Fi desactivado · Bluetooth disponible"
    run_step "Bloqueando Wi-Fi" sudo rfkill block wifi
    term_step "Activando Bluetooth y el modo visible/emparejable"
    if printf 'power on\\ndiscoverable on\\npairable on\\n' | bluetoothctl; then
      term_success "Bluetooth listo para emparejar"
    else
      status=$?
      term_error "No se pudo preparar Bluetooth (código $status)"
      exit "$status"
    fi
    ;;
  config)
    [[ "$#" -eq 1 ]] || { usage >&2; exit 2; }
    term_banner "Palco · Modo configuración" "Preparando la conexión de red"
    run_step "Reactivando Wi-Fi" sudo rfkill unblock wifi
    term_info "Abre nmtui para configurar o cambiar la red."
    ;;
  estado)
    [[ "$#" -eq 1 ]] || { usage >&2; exit 2; }
    term_banner "Palco · Estado general" "Bluetooth · PipeWire · ALSA · systemd"
    show_section "Bluetooth · controlador" bluetoothctl show
    show_section "Bluetooth · dispositivos" bluetoothctl devices
    show_section "PipeWire · audio" wpctl status
    show_section "ALSA · tarjetas" aplay -l
    show_section "systemd · servicios fallidos" systemctl --no-pager --failed
    term_rule
    term_success "Diagnóstico completado"
    ;;
  bt)
    [[ "$#" -eq 1 ]] || { usage >&2; exit 2; }
    term_banner "Palco · Bluetooth" "Controlador, dispositivos y radio"
    show_section "Controlador" bluetoothctl show
    show_section "Dispositivos detectados" bluetoothctl devices
    show_section "Dispositivos emparejados" bluetoothctl paired-devices
    show_section "Radio Bluetooth" rfkill list bluetooth
    term_rule
    term_success "Consulta Bluetooth completada"
    ;;
  dsp-check)
    [[ "$#" -eq 1 ]] || { usage >&2; exit 2; }
    term_banner "Palco · Comprobación DSP" "Verificación del nodo de audio en PipeWire"
    term_section "Nodo PipeWire"
    if wpctl status | grep -i 'palco DSP'; then
      :
    else
      term_warning "No aparece un nodo llamado «Palco DSP» en wpctl."
    fi
    term_section "Referencias del DSP"
    if pw-dump 2>/dev/null | grep -o 'palco-dsp[^"]*' | sort -u; then
      :
    else
      term_warning "No se encontraron referencias palco-dsp en pw-dump."
    fi
    ;;
  audio-test)
    [[ "$#" -eq 1 ]] || { usage >&2; exit 2; }
    term_banner "Palco · Prueba de audio" "Señal estéreo de prueba"
    term_info "Pulsa Ctrl+C para detener la reproducción."
    if speaker-test -t wav -c 2; then
      term_success "Prueba de audio finalizada"
    else
      status=$?
      if [[ "$status" -eq 130 || "$status" -eq 143 ]]; then
        term_info "Prueba de audio interrumpida por el usuario."
      else
        term_error "La prueba de audio terminó con código $status."
      fi
      exit "$status"
    fi
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
