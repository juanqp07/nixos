{ ... }:

{
  programs.fish = {
    enable = true;

    # Saludo propio: limpio y compatible con Konsole/KDE y sesiones SSH.
    # Fish gestiona automáticamente los colores según las capacidades del terminal.
    interactiveShellInit = ''
      set -g fish_greeting

      function __kigo_alias_header --description "Cabecera visual de los alias personales"
        set_color --bold brblue
        printf '\n╭─ NIXOS / %s\n' "$argv[1]"
        set_color normal
        set_color brblack
        printf '╰────────────────────────────────────────────────────\n'
        set_color normal
      end

      function __kigo_alias_result --description "Resultado visual de un alias"
        set -l result "$argv[1]"
        set -l message "$argv[2]"
        if test "$result" -eq 0
          set_color --bold brgreen
          printf '  ✓ '
          set_color normal
          printf '%s completado\n' "$message"
        else
          set_color --bold brred
          printf '  ✕ '
          set_color normal
          printf '%s (código %s)\n' "$message" "$result"
        end
      endd

      function __kigo_alias_run --description "Ejecuta un comando con cabecera y resultado"
        set -l title "$argv[1]"
        set -l message "$argv[2]"
        set -e argv[1..2]

        __kigo_alias_header "$title"
        command $argv
        set -l result $status
        __kigo_alias_result "$result" "$message"
        return $result
      end
    '';

    # Los comandos de mantenimiento comparten el estilo Bash de scripts/terminal-style.sh.
    shellAliases = {
      kernels = "bash ~/nixos/scripts/kernel-versions.sh";
      nix-reboot-check = "bash ~/nixos/scripts/nix-reboot-check.sh";
      nix-maintain = "bash ~/nixos/scripts/nix-maintenance.sh maintain";
      nix-update = "bash ~/nixos/scripts/nix-maintenance.sh update";
      nix-apply-locked = "bash ~/nixos/scripts/nix-maintenance.sh apply";
      nix-clean = "bash ~/nixos/scripts/nix-maintenance.sh clean";
    };

    functions = {
      nix-generations = {
        description = "Muestra el historial de generaciones de NixOS";
        body = ''
          __kigo_alias_run "Historial de generaciones" "Consulta de generaciones" sudo nix-env --profile /nix/var/nix/profiles/system --list-generations
        '';
      };

      nix-optimise = {
        description = "Deduplica el almacén Nix";
        body = ''
          __kigo_alias_run "Optimización del almacén Nix" "Optimización del almacén" sudo nix-store --optimise
        '';
      };
    };
  };
}
