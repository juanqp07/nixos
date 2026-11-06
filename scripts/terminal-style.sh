#!/usr/bin/env bash
# Identidad visual compartida para las herramientas propias del repositorio.
# Compatible con SSH, Fish, Bash, KDE Konsole y terminales sin color.

TERM_STYLE_RESET=''
TERM_STYLE_BOLD=''
TERM_STYLE_MUTED=''
TERM_STYLE_ACCENT=''
TERM_STYLE_CYAN=''
TERM_STYLE_VIOLET=''
TERM_STYLE_SUCCESS=''
TERM_STYLE_WARNING=''
TERM_STYLE_ERROR=''

if [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-dumb} != "dumb" ]]; then
  TERM_STYLE_RESET=$'\033[0m'
  TERM_STYLE_BOLD=$'\033[1m'
  TERM_STYLE_MUTED=$'\033[38;5;245m'
  TERM_STYLE_ACCENT=$'\033[38;5;75m'   # Azul Plasma
  TERM_STYLE_CYAN=$'\033[38;5;81m'
  TERM_STYLE_VIOLET=$'\033[38;5;141m'
  TERM_STYLE_SUCCESS=$'\033[38;5;78m'
  TERM_STYLE_WARNING=$'\033[38;5;221m'
  TERM_STYLE_ERROR=$'\033[38;5;203m'
fi

term_banner() {
  local title="$1"
  local subtitle="${2:-}"

  printf '\n%b╭─ NIXOS / %s%b\n' "$TERM_STYLE_ACCENT$TERM_STYLE_BOLD" "$title" "$TERM_STYLE_RESET"
  if [[ -n "$subtitle" ]]; then
    printf '%b│%b  %s\n' "$TERM_STYLE_ACCENT" "$TERM_STYLE_RESET" "$subtitle"
  fi
  printf '%b╰────────────────────────────────────────────────────%b\n' "$TERM_STYLE_MUTED" "$TERM_STYLE_RESET"
}

term_section() {
  printf '\n%b◆ %s%b\n' "$TERM_STYLE_VIOLET$TERM_STYLE_BOLD" "$*" "$TERM_STYLE_RESET"
}

term_step() {
  printf '%b  ›%b  %s\n' "$TERM_STYLE_CYAN$TERM_STYLE_BOLD" "$TERM_STYLE_RESET" "$*"
}

term_success() {
  printf '%b  ✓%b  %s\n' "$TERM_STYLE_SUCCESS$TERM_STYLE_BOLD" "$TERM_STYLE_RESET" "$*"
}

term_info() {
  printf '%b  ·%b  %s\n' "$TERM_STYLE_ACCENT" "$TERM_STYLE_RESET" "$*"
}

term_warning() {
  printf '%b  !%b  %s\n' "$TERM_STYLE_WARNING$TERM_STYLE_BOLD" "$TERM_STYLE_RESET" "$*"
}

term_error() {
  printf '%b  ✕%b  %s\n' "$TERM_STYLE_ERROR$TERM_STYLE_BOLD" "$TERM_STYLE_RESET" "$*" >&2
}

term_skip() {
  printf '%b  ↷%b  %s\n' "$TERM_STYLE_MUTED" "$TERM_STYLE_RESET" "$*"
}

term_rule() {
  printf '%b────────────────────────────────────────────────────%b\n' "$TERM_STYLE_MUTED" "$TERM_STYLE_RESET"
}

term_table_header() {
  printf '%b%s%b\n' "$TERM_STYLE_ACCENT$TERM_STYLE_BOLD" "$*" "$TERM_STYLE_RESET"
}
