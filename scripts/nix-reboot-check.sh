#!/usr/bin/env bash
# Compare reboot-sensitive components of the booted system with the
# system profile selected for the next boot (including operation = "boot").

set -Eeuo pipefail

BOOTED="/run/booted-system"
NEXT="/nix/var/nix/profiles/system"

[[ -e "$BOOTED" ]] || {
  echo "Error: no existe $BOOTED; no se puede identificar el sistema arrancado." >&2
  exit 1
}
[[ -e "$NEXT" ]] || {
  echo "Error: no existe $NEXT; no se puede identificar la generación seleccionada." >&2
  exit 1
}

needs_reboot=0

for component in kernel kernel-modules initrd systemd; do
  booted_component="$BOOTED/$component"
  next_component="$NEXT/$component"

  if [[ ! -e "$booted_component" || ! -e "$next_component" ]]; then
    printf 'Aviso: no se pudo comparar el componente %s.\n' "$component"
    continue
  fi

  booted_target="$(readlink -f "$booted_component")"
  next_target="$(readlink -f "$next_component")"

  if [[ "$booted_target" != "$next_target" ]]; then
    printf 'Reinicio necesario: cambio en %s\n' "$component"
    needs_reboot=1
  fi
done

if (( needs_reboot )); then
  exit 0
fi

echo "Sin cambios de kernel, módulos, initrd o systemd pendientes de reinicio."
