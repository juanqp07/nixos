{ lib, ... }:

{
  # Fastfetch solo en terminales locales; no interrumpir sesiones SSH.
  programs.fish.interactiveShellInit = lib.mkAfter ''
    if not set -q SSH_CONNECTION; and not set -q SSH_TTY
      fastfetch
    end
  '';

  # Despliegue remoto de servidores desde Elytra o Titan.
  # La compilación se realiza localmente y la activación por SSH en el destino.
  programs.fish.shellAliases = {
    nix-up-atlas =
      "pushd ~/nixos > /dev/null && "
      + "echo '--- 🚀 Desplegando Atlas desde este equipo ---' && "
      + "nixos-rebuild switch --flake .#atlas --target-host juan@192.168.1.143 --sudo --ask-sudo-password && "
      + "popd > /dev/null";

    nix-up-pico =
      "pushd ~/nixos > /dev/null && "
      + "echo '--- 🚀 Desplegando Pico desde este equipo ---' && "
      + "nixos-rebuild switch --flake .#pico --target-host juan@192.168.1.147 --sudo --ask-sudo-password && "
      + "popd > /dev/null";
  };
}
