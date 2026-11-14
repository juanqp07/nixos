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

    # Despliegue con deploy-rs. Se exige un checkout limpio y se muestra el
    # commit exacto antes de construir o transferir cualquier generación.
    function __kigo_deploy --argument-names target label peer lan_host transport
      if not pushd "$HOME/nixos" >/dev/null
        __kigo_alias_result 1 "No se pudo acceder a ~/nixos"
        return 1
      end

      if not command git rev-parse --is-inside-work-tree >/dev/null 2>&1
        printf '  Error: ~/nixos no es un repositorio Git.\n' >&2
        popd >/dev/null
        return 1
      end

      set -l dirty (command git status --porcelain --untracked-files=all)
      if test -n "$dirty"
        printf '  Despliegue cancelado: hay cambios locales sin confirmar en ~/nixos.\n' >&2
        printf '  Confirma o guarda los cambios antes de desplegar. Estado actual:\n' >&2
        command git status --short
        popd >/dev/null
        return 1
      end

      set -l branch (command git branch --show-current)
      if test -z "$branch"
        set branch "(HEAD separado)"
      end
      set -l commit (command git rev-parse --short=12 HEAD)
      set -l subject (command git log -1 --format=%s)

      set -l deploy_args --interactive
      set -l destination "juan@$lan_host (LAN)"
      if test "$label" = "Atlas + Pico"
        set destination "Atlas + Pico (LAN)"
      end

      if test "$transport" = "--netbird"
        if not type -q netbird
          printf '  Error: no se encuentra el comando netbird.\n' >&2
          popd >/dev/null
          return 1
        end
        if not type -q jq
          printf '  Error: no se encuentra jq, necesario para leer el estado de NetBird.\n' >&2
          popd >/dev/null
          return 1
        end

        # Solo se acepta un peer conectado y una única IP NetBird. No se hace
        # fallback silencioso a la LAN si el peer no está disponible.
        set -l netbird_ip (command netbird status --filter-by-names "$peer" --json 2>/dev/null | command jq -er '
          [
            .peers.details[]?
            | select((.status // "" | ascii_downcase) == "connected")
            | .netbirdIp // empty
          ]
          | unique
          | if length == 1 then .[0] else error("expected exactly one connected peer") end
        ' 2>/dev/null)
        if test $status -ne 0; or test -z "$netbird_ip"
          printf '  Error: no se encontró un único peer NetBird conectado llamado %s.\n' "$peer" >&2
          printf '  Comprueba el estado de NetBird y vuelve a intentarlo.\n' >&2
          popd >/dev/null
          return 1
        end

        set -a deploy_args --hostname "$netbird_ip"
        set destination "juan@$netbird_ip (NetBird)"
      else if test -n "$transport"
        printf '  Transporte no válido: %s\n' "$transport" >&2
        popd >/dev/null
        return 2
      end

      __kigo_alias_header "Deploy-rs · $label"
      set_color brblack
      printf '  Rama: %s\n' "$branch"
      printf '  Commit: %s\n' "$commit"
      printf '  Mensaje: %s\n' "$subject"
      printf '  Destino: %s · flake %s\n' "$destination" "$target"
      set_color normal

      command nix run .#deploy-rs -- $deploy_args "$target"
      set -l result $status
      popd >/dev/null
      __kigo_alias_result "$result" "Despliegue de $label"
      return $result
    end

    function nix-deploy-atlas --description "Despliega Atlas mediante deploy-rs; acepta --netbird"
      if test (count $argv) -gt 1
        printf 'Uso: nix-deploy-atlas [--netbird]\n' >&2
        return 2
      end
      set -l transport ""
      if test (count $argv) -eq 1
        if test "$argv[1]" != "--netbird"
          printf 'Uso: nix-deploy-atlas [--netbird]\n' >&2
          return 2
        end
        set transport "$argv[1]"
      end
      __kigo_deploy ".#atlas" "Atlas" "atlas" "192.168.1.143" "$transport"
    end

    function nix-deploy-pico --description "Despliega Pico mediante deploy-rs; acepta --netbird"
      if test (count $argv) -gt 1
        printf 'Uso: nix-deploy-pico [--netbird]\n' >&2
        return 2
      end
      set -l transport ""
      if test (count $argv) -eq 1
        if test "$argv[1]" != "--netbird"
          printf 'Uso: nix-deploy-pico [--netbird]\n' >&2
          return 2
        end
        set transport "$argv[1]"
      end
      __kigo_deploy ".#pico" "Pico" "pico" "192.168.1.147" "$transport"
    end

    function nix-deploy-servers --description "Despliega Atlas y Pico mediante deploy-rs"
      if test (count $argv) -ne 0
        printf 'Uso: nix-deploy-servers\n' >&2
        return 2
      end
      __kigo_deploy "." "Atlas + Pico" "" "LAN" ""
    end
  '';

}
