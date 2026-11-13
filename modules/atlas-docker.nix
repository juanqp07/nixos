{ config, pkgs, ... }:

{
  # Atlas: motor Docker, política de puertos publicados y stack privado de Arcane.
  # Este módulo es específico del servidor y solo debe importarse en Atlas.

  virtualisation = {
    docker = {
      enable = true;
      # Poda semanal: con ~70 contenedores + watchtower, las imágenes viejas
      # se acumulan en /. Mismo patrón que pico.
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
      daemon.settings = {
        "log-driver" = "journald";

        features = {
          "containerd-snapshotter" = true;
        };
      };
    };

    # --- ARCANE ---
    oci-containers = {
      backend = "docker";

      containers = {
        # Proxy limitado: Arcane nunca recibe el socket Docker directamente.
        arcane-docker-proxy = {
          image = "wollomatic/socket-proxy:1.13.2";
          autoStart = true;
          user = "0:0";

          cmd = [
            "-listenip=0.0.0.0"
            # Arcane y su helper temporal de actualizaciones. No usar rangos CIDR.
            "-allowfrom=arcane,arcane-upgrader"
            "-allowhealthcheck"

            # Lectura: estado, eventos, contenedores, imágenes y recursos.
            "-allowGET=(/v[0-9.]+)?/_ping"
            "-allowGET=(/v[0-9.]+)?/events(/.*)?"
            "-allowGET=(/v[0-9.]+)?/version"
            "-allowGET=(/v[0-9.]+)?/info(/.*)?"
            "-allowGET=(/v[0-9.]+)?/system/df"
            "-allowGET=(/v[0-9.]+)?/containers(/.*)?"
            "-allowGET=(/v[0-9.]+)?/exec(/.*)?"
            "-allowGET=(/v[0-9.]+)?/images(/.*)?"
            "-allowGET=(/v[0-9.]+)?/networks(/.*)?"
            "-allowGET=(/v[0-9.]+)?/volumes(/.*)?"
            "-allowGET=(/v[0-9.]+)?/distribution(/.*)?"
            "-allowGET=(/v[0-9.]+)?/swarm(/.*)?"
            "-allowGET=(/v[0-9.]+)?/nodes(/.*)?"
            "-allowGET=(/v[0-9.]+)?/services(/.*)?"
            "-allowGET=(/v[0-9.]+)?/tasks(/.*)?"
            "-allowGET=(/v[0-9.]+)?/secrets(/.*)?"
            "-allowGET=(/v[0-9.]+)?/configs(/.*)?"

            # HEAD: comprobaciones de versión y disponibilidad.
            "-allowHEAD=(/v[0-9.]+)?/_ping"
            "-allowHEAD=(/v[0-9.]+)?/version"

            # POST: operaciones de gestión, builds, registros y Swarm.
            "-allowPOST=(/v[0-9.]+)?/containers(/.*)?"
            "-allowPOST=(/v[0-9.]+)?/exec(/.*)?"
            "-allowPOST=(/v[0-9.]+)?/images(/.*)?"
            "-allowPOST=(/v[0-9.]+)?/networks(/.*)?"
            "-allowPOST=(/v[0-9.]+)?/volumes(/.*)?"
            "-allowPOST=(/v[0-9.]+)?/commit"
            "-allowPOST=(/v[0-9.]+)?/build(/.*)?"
            "-allowPOST=(/v[0-9.]+)?/session"
            "-allowPOST=(/v[0-9.]+)?/grpc"
            "-allowPOST=(/v[0-9.]+)?/auth"
            "-allowPOST=(/v[0-9.]+)?/swarm(/.*)?"
            "-allowPOST=(/v[0-9.]+)?/nodes(/.*)?"
            "-allowPOST=(/v[0-9.]+)?/services(/.*)?"
            "-allowPOST=(/v[0-9.]+)?/secrets(/.*)?"
            "-allowPOST=(/v[0-9.]+)?/configs(/.*)?"

            # PUT: transferencia de archivos de contenedores.
            "-allowPUT=(/v[0-9.]+)?/containers(/.*)?"

            # DELETE: eliminación de recursos Docker.
            "-allowDELETE=(/v[0-9.]+)?/containers(/.*)?"
            "-allowDELETE=(/v[0-9.]+)?/images(/.*)?"
            "-allowDELETE=(/v[0-9.]+)?/networks(/.*)?"
            "-allowDELETE=(/v[0-9.]+)?/volumes(/.*)?"
            "-allowDELETE=(/v[0-9.]+)?/nodes(/.*)?"
            "-allowDELETE=(/v[0-9.]+)?/services(/.*)?"
            "-allowDELETE=(/v[0-9.]+)?/secrets(/.*)?"
            "-allowDELETE=(/v[0-9.]+)?/configs(/.*)?"
          ];

          volumes = [
            "/var/run/docker.sock:/var/run/docker.sock:ro"
          ];

          extraOptions = [
            "--network=arcane-net"
            "--read-only"
            "--cap-drop=ALL"
            "--security-opt=no-new-privileges:true"
            "--memory=64m"
            "--pids-limit=64"
            # No configurar --health-cmd: Docker CLI lo convierte en CMD-SHELL y esta imagen no tiene shell.
          ];
        };

        arcane = {
          # Fijar la versión evita que :latest adelante el Manager a la rama v3-next.
          image = "ghcr.io/getarcaneapp/manager:v2.17.3";
          autoStart = true;

          # NixOS gestiona el ciclo de vida; desactivar el updater interno evita
          # que compita con virtualisation.oci-containers.
          labels = {
            "com.getarcaneapp.arcane.updater" = "false";
          };

          ports = [
            "3552:3552"
          ];

          volumes = [
            "arcane-data:/app/data"
            "/mnt/datos/arcane/projects:/app/data/projects"
          ];

          environmentFiles = [
            "/mnt/datos/AppData/arcane/arcane.env"
          ];

          environment = {
            APP_URL = "http://192.168.1.143:3552";
            PUID = "1000";
            PGID = "1000";
            LOG_LEVEL = "info";
            LOG_JSON = "false";
            OIDC_ENABLED = "false";
            PROJECTS_DIRECTORY = "/app/data/projects";
            DOCKER_HOST = "tcp://arcane-docker-proxy:2375";
          };

          dependsOn = [
            "arcane-postgres"
            "arcane-docker-proxy"
          ];

          extraOptions = [
            "--network=arcane-net"
            "--health-cmd=./arcane health --timeout 2s"
            "--health-start-period=15s"
            "--health-interval=10s"
            "--health-timeout=5s"
            "--health-retries=5"
          ];
        };

        arcane-postgres = {
          image = "postgres:17-alpine";
          autoStart = true;

          volumes = [
            "postgres-data:/var/lib/postgresql/data"
          ];

          environmentFiles = [
            "/mnt/datos/AppData/arcane/postgres.env"
          ];

          extraOptions = [
            "--network=arcane-net"
            "--network-alias=postgres"
          ];

          # PostgreSQL no necesita publicar el puerto 5432:
          # Arcane accede a él por la red privada arcane-net.
        };
      };
    };

  };

  systemd = {
    services = {
      docker-published-ports-private = {
        description = "Restrict direct access to Atlas Docker application ports";
        wantedBy = [ "multi-user.target" ];
        requires = [ "docker.service" ];
        after = [ "docker.service" ];
        partOf = [ "docker.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          set -eu

          IPTABLES=${pkgs.iptables}/bin/iptables
          CHAIN="ATLAS-DOCKER-PRIVATE"
          CONTROL_PORTS="5553 8001 8019"
          PRIVATE_PORTS="53 1080 1231 1800 2283 2322 2450 3000 3004 3067 3131 3160 3232 3421 3422 3455 3456 3535 3552 3590 4533 4534 5000 7575 7644 8000 8090 8288 8555 8665 8888 9180 9191 9192 9920 9999"

          $IPTABLES -w -N "$CHAIN" 2>/dev/null || true
          $IPTABLES -w -F "$CHAIN"

          # Docker-to-Docker traffic is required by Zoraxy and internal services.
          $IPTABLES -w -A "$CHAIN" -i br+ -j RETURN
          $IPTABLES -w -A "$CHAIN" -i docker0 -j RETURN

          # Never expose privileged control APIs on the host, even to the LAN.
          for port in $CONTROL_PORTS; do
            for protocol in tcp udp; do
              $IPTABLES -w -A "$CHAIN" -p "$protocol" -m conntrack --ctorigdstport "$port" -j DROP
            done
          done

          # Keep user-facing panels and app ports available only to trusted clients.
          $IPTABLES -w -A "$CHAIN" -i wt0 -j RETURN
          $IPTABLES -w -A "$CHAIN" -s 192.168.1.0/24 -j RETURN

          # Block direct WAN access to app UIs and proxy ports; Zoraxy's bridge
          # traffic was allowed above and public 80/443 are not in this list.
          for port in $PRIVATE_PORTS; do
            for protocol in tcp udp; do
              $IPTABLES -w -A "$CHAIN" -p "$protocol" -m conntrack --ctorigdstport "$port" -j DROP
            done
          done

          $IPTABLES -w -A "$CHAIN" -j RETURN
          $IPTABLES -w -C DOCKER-USER -j "$CHAIN" 2>/dev/null || \
            $IPTABLES -w -I DOCKER-USER 1 -j "$CHAIN"

          # Protect IPv6-published containers too, when Docker created its
          # DOCKER-USER chain. Global IPv6 clients are not on the trusted allowlist.
          IP6TABLES=${pkgs.iptables}/bin/ip6tables
          if $IP6TABLES -w -S DOCKER-USER >/dev/null 2>&1; then
            $IP6TABLES -w -N "$CHAIN" 2>/dev/null || true
            $IP6TABLES -w -F "$CHAIN"
            $IP6TABLES -w -A "$CHAIN" -i br+ -j RETURN
            $IP6TABLES -w -A "$CHAIN" -i docker0 -j RETURN
            for port in $CONTROL_PORTS; do
              for protocol in tcp udp; do
                $IP6TABLES -w -A "$CHAIN" -p "$protocol" -m conntrack --ctorigdstport "$port" -j DROP
              done
            done
            $IP6TABLES -w -A "$CHAIN" -i wt0 -j RETURN
            $IP6TABLES -w -A "$CHAIN" -s fc00::/7 -j RETURN
            for port in $PRIVATE_PORTS; do
              for protocol in tcp udp; do
                $IP6TABLES -w -A "$CHAIN" -p "$protocol" -m conntrack --ctorigdstport "$port" -j DROP
              done
            done
            $IP6TABLES -w -A "$CHAIN" -j RETURN
            $IP6TABLES -w -C DOCKER-USER -j "$CHAIN" 2>/dev/null || \
              $IP6TABLES -w -I DOCKER-USER 1 -j "$CHAIN"
          fi
        '';
      };

      # Crear la red Docker privada antes de iniciar Arcane, el proxy y PostgreSQL.
      arcane-network = {
        description = "Docker network for Arcane";
        wantedBy = [ "multi-user.target" ];
        requires = [ "docker.service" ];
        after = [ "docker.service" ];
        before = [
          "docker-arcane-docker-proxy.service"
          "docker-arcane.service"
          "docker-arcane-postgres.service"
        ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          ${config.virtualisation.docker.package}/bin/docker \
            network inspect arcane-net >/dev/null 2>&1 || \
          ${config.virtualisation.docker.package}/bin/docker \
            network create arcane-net
        '';
      };

      # Orden explícito: la red existe antes de los tres contenedores.
      docker-arcane-docker-proxy = {
        requires = [ "arcane-network.service" ];
        after = [ "arcane-network.service" ];
      };

      # Esperar a que el proxy pase su healthcheck antes de arrancar Arcane.
      # dependsOn solo ordena los servicios; esta unidad espera al estado healthy real.
      arcane-proxy-ready = {
        description = "Wait for Arcane Docker socket proxy health";
        requires = [ "docker-arcane-docker-proxy.service" ];
        after = [ "docker-arcane-docker-proxy.service" ];
        before = [ "docker-arcane.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "190s";
        };

        script = ''
          docker="${config.virtualisation.docker.package}/bin/docker"
          attempt=0

          while [ "$attempt" -lt 90 ]; do
            attempt=$((attempt + 1))

            # Ejecuta el binario healthcheck en formato exec (sin /bin/sh).
            if "$docker" exec arcane-docker-proxy ./healthcheck >/dev/null 2>&1; then
              echo "Arcane Docker socket proxy está saludable."
              exit 0
            fi

            state="$("$docker" inspect --format '{{.State.Status}}' arcane-docker-proxy 2>/dev/null || true)"
            case "$state" in
              exited|dead)
                echo "Arcane no se inicia: el socket proxy está en estado $state." >&2
                "$docker" logs --tail=100 arcane-docker-proxy >&2 || true
                exit 1
                ;;
            esac

            ${pkgs.coreutils}/bin/sleep 2
          done

          echo "Arcane no se inicia: el healthcheck exec del socket proxy falló durante 180 segundos." >&2
          "$docker" inspect --format 'Estado: {{.State.Status}}' arcane-docker-proxy >&2 || true
          "$docker" logs --tail=100 arcane-docker-proxy >&2 || true
          exit 1
        '';
      };

      docker-arcane = {
        requires = [
          "arcane-network.service"
          "arcane-proxy-ready.service"
        ];
        after = [
          "arcane-network.service"
          "arcane-proxy-ready.service"
        ];
      };

      docker-arcane-postgres = {
        requires = [ "arcane-network.service" ];
        after = [ "arcane-network.service" ];
      };
    };
  };
}
