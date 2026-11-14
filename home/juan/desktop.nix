{ lib, ... }:

{
  # Atajo global de KWin para maximizar la ventana activa.
  # Meta representa la tecla Super. Se libera Meta+Alt+Up de la acción
  # "Switch Window Up" para evitar que ambas acciones compitan por el atajo.
  qt.kde.settings.kglobalshortcutsrc.kwin = {
    "Window Maximize" = "Meta+Alt+Up,Meta+Alt+Up,Maximize Window";
    "Switch Window Up" = "none,none,Switch to Window Above";
  };

  # Fastfetch local y funciones de despliegue remoto para los escritorios.
  # Las sesiones SSH no lanzan fastfetch automáticamente.
  programs.fish.interactiveShellInit = lib.mkAfter ''
    if not set -q SSH_CONNECTION; and not set -q SSH_TTY
      fastfetch
    end

    function nix-up-atlas --description "Despliega la configuración en Atlas"
      if not pushd "$HOME/nixos" >/dev/null
        __kigo_alias_result 1 "No se pudo acceder a ~/nixos"
        return 1
      end

      __kigo_alias_header "Despliegue remoto · Atlas"
      set_color brblack
      printf '  Destino: juan@192.168.1.143 · flake .#atlas\n'
      set_color normal
      command nixos-rebuild build --flake .#atlas
      set -l build_result $status
      if test "$build_result" -ne 0
        popd >/dev/null
        __kigo_alias_result "$build_result" "Build local de Atlas fallido; no se ha desplegado"
        return "$build_result"
      end

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
      command nixos-rebuild build --flake .#pico
      set -l build_result $status
      if test "$build_result" -ne 0
        popd >/dev/null
        __kigo_alias_result "$build_result" "Build local de Pico fallido; no se ha desplegado"
        return "$build_result"
      end

      command nixos-rebuild switch --flake .#pico --target-host juan@192.168.1.147 --sudo --ask-sudo-password
      set -l result $status
      popd >/dev/null
      __kigo_alias_result "$result" "Despliegue de Pico finalizado"
      return $result
    end

    # Despliegue remoto con deploy-rs. La confirmación interactiva evita
    # activar accidentalmente cambios en los servidores.
    function __kigo_deploy --argument-names target label
      if not pushd "$HOME/nixos" >/dev/null
        __kigo_alias_result 1 "No se pudo acceder a ~/nixos"
        return 1
      end

      __kigo_alias_header "Deploy-rs · $label"
      set_color brblack
      printf '  Destino: %s\n' "$target"
      set_color normal
      command nix run .#deploy-rs -- --interactive "$target"
      set -l result $status
      popd >/dev/null
      __kigo_alias_result "$result" "Despliegue de $label"
      return $result
    end

    function nix-deploy-atlas --description "Despliega Atlas mediante deploy-rs"
      __kigo_deploy ".#atlas" "Atlas"
    end

    function nix-deploy-pico --description "Despliega Pico mediante deploy-rs"
      __kigo_deploy ".#pico" "Pico"
    end

    function nix-deploy-servers --description "Despliega Atlas y Pico mediante deploy-rs"
      __kigo_deploy "." "Atlas + Pico"
    end
  '';

}
