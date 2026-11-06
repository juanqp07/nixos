{ ... }:

{
  programs.fish = {
    enable = true;

    # Ocultar el saludo predeterminado en sesiones interactivas del usuario.
    interactiveShellInit = ''
      set -g fish_greeting
    '';

    shellAliases = {
      # Consulta las versiones de kernel configuradas en todos los hosts.
      kernels = "bash ~/nixos/scripts/kernel-versions.sh";

      # Comprueba reinicios según la estrategia switch/boot del host.
      nix-reboot-check = "bash ~/nixos/scripts/nix-reboot-check.sh";

      # Mantenimiento completo: interactivo o automático con -y.
      nix-maintain = "bash ~/nixos/scripts/nix-maintenance.sh maintain";

      # Actualiza todos los inputs, construye y pregunta antes de aplicar.
      nix-update = "bash ~/nixos/scripts/nix-maintenance.sh update";

      # Construye y aplica usando el flake.lock existente, sin actualizar inputs.
      nix-apply-locked = "bash ~/nixos/scripts/nix-maintenance.sh apply";

      # Limpia generaciones según la política declarada para el host actual.
      nix-clean = "bash ~/nixos/scripts/nix-maintenance.sh clean";

      # Muestra solo el número, fecha y generación actual.
      nix-generations = "sudo nix-env --profile /nix/var/nix/profiles/system --list-generations";

      # Deduplicación completa manual; auto-optimise-store sigue cubriendo nuevas rutas.
      nix-optimise = "sudo nix-store --optimise";
    };
  };
}
