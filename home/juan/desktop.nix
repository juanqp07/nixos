{ lib, ... }:

{
  # Fastfetch solo en terminales locales; no interrumpir sesiones SSH.
  programs.fish.interactiveShellInit = lib.mkAfter ''
    if not set -q SSH_CONNECTION; and not set -q SSH_TTY
      fastfetch
    end
  '';

  # Despliegue remoto con el mismo lenguaje visual que el resto de Fish.
  # La compilación sigue siendo local y la activación se realiza por SSH.
  programs.fish.interactiveShellInit = lib.mkAfter ''
    function nix-up-atlas --description "Despliega la configuración en Atlas"
      if not pushd "$HOME/nixos" >/dev/null
        __kigo_alias_result 1 "No se pudo acceder a ~/nixos"
        return 1
      end

      __kigo_alias_header "Despliegue remoto · Atlas"
      set_color brblack
      printf '  Destino: juan@192.168.1.143 · flake .#atlas\n'
      set_color normal
      command nixos-rebuild switch --flake .#atlas --target-host juan@192.168.1.143 --sudo --ask-sudo-password
      set -l result $status
      popd >/dev/null
      __kigo_alias_result "$result" "Despliegue de Atlas finalizado"
      return $result
    end

    function nix-up-pico --description "Despliega la configuración en Pico"
      if not pushd "$HOME/nixos" >/dev/null
        __kigo_alias_result 1 "No se pudo acceder a ~/nixos"
        return 1
      end

      __kigo_alias_header "Despliegue remoto · Pico"
      set_color brblack
      printf '  Destino: juan@192.168.1.147 · flake .#pico\n'
      set_color normal
      command nixos-rebuild switch --flake .#pico --target-host juan@192.168.1.147 --sudo --ask-sudo-password
      set -l result $status
      popd >/dev/null
      __kigo_alias_result "$result" "Despliegue de Pico finalizado"
      return $result
    end
  '';

}
