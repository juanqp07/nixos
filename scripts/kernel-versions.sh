#!/usr/bin/env bash
# Muestra el kernel configurado para cada host del flake.
# Solo evalúa la configuración: no construye ni modifica ningún sistema.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$FLAKE_DIR"

# shellcheck source=scripts/terminal-style.sh
source "$SCRIPT_DIR/terminal-style.sh"

if ! command -v nix >/dev/null 2>&1; then
  term_error "Nix no está instalado o no se encuentra en PATH."
  exit 1
fi

if ! hosts="$(nix eval --no-write-lock-file --raw --apply 'attrs: builtins.concatStringsSep "\n" (builtins.attrNames attrs)' .#nixosConfigurations 2>/dev/null)"; then
  term_error "No se pudieron evaluar las configuraciones NixOS de $FLAKE_DIR."
  exit 1
fi

if [[ -z "$hosts" ]]; then
  term_warning "No se han encontrado hosts NixOS en el flake."
  exit 0
fi

term_banner "Versiones del kernel" "Inventario de los equipos definidos en el flake"
printf '\n'
term_table_header "$(printf '%-18s  %s' 'EQUIPO' 'KERNEL CONFIGURADO')"
term_rule

host_count=0
failed_count=0

while IFS= read -r host; do
  [[ -n "$host" ]] || continue
  ((host_count += 1))

  if version="$(nix eval --no-write-lock-file --raw ".#nixosConfigurations.${host}.config.boot.kernelPackages.kernel.version" 2>/dev/null)"; then
    printf '%b%-18s%b  %s\n' "$TERM_STYLE_CYAN" "$host" "$TERM_STYLE_RESET" "$version"
  else
    ((failed_count += 1))
    printf '%b%-18s%b  %bNo disponible (falló la evaluación)%b\n' \
      "$TERM_STYLE_CYAN" "$host" "$TERM_STYLE_RESET" \
      "$TERM_STYLE_WARNING" "$TERM_STYLE_RESET"
  fi
done <<< "$hosts"

term_rule
if (( failed_count == 0 )); then
  term_success "Consulta completada · $host_count equipos"
else
  term_warning "Consulta parcial · $((host_count - failed_count)) correctos, $failed_count con errores"
fi
