{ config, pkgs, ... }:

{
  virtualisation = {
    oci-containers = {
      backend = "docker";

      containers = {
        # Proxy limitado: Arcane nunca recibe el socket Docker directamente.
        arcane-docker-proxy = {
          image = "wollomatic/socket-proxy:1.13.2@sha256:ff95d6ff6c27853005ef85eb8f4ab5923dc3d2f1e055f98fb6aeeaceec3fe848";
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
          image = "ghcr.io/getarcaneapp/manager:v3.1.1@sha256:f12cfe86238b892956d945681613e9056676ca0cda0d980abacad033ebb72bee";
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
            ARCANE_APP_URL = "http://192.168.1.143:3552";
            PUID = "1000";
            PGID = "1000";
            ARCANE_LOG_LEVEL = "info";
            ARCANE_LOG_JSON = "false";
            ARCANE_OIDC_ENABLED = "false";
            ARCANE_PROJECTS_DIRECTORY = "/app/data/projects";
            DOCKER_HOST = "tcp://arcane-docker-proxy:2375";
          };

          dependsOn = [
            "arcane-postgres"
            "arcane-docker-proxy"
          ];

          extraOptions = [
            "--network=arcane-net"
            # Docker CLI --health-cmd siempre genera CMD-SHELL; esta imagen no incluye /bin/sh.
            # La comprobación directa se ejecuta desde systemd (arcane-healthcheck.timer).
            "--no-healthcheck"
          ];
        };

        arcane-postgres = {
          image = "postgres:17-alpine@sha256:f9cf3e1f0066f0eb0c48707d864f0ac5941e9ff454a072077d97a4d278d07d73";
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

      # El Manager es una imagen mínima sin /bin/sh. Docker CLI --health-cmd
      # usa CMD-SHELL, así que se comprueba el binario directamente desde el host.
      arcane-healthcheck = {
        description = "Check Arcane Manager health without a container shell";
        after = [
          "docker.service"
          "docker-arcane.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${config.virtualisation.docker.package}/bin/docker exec arcane ./arcane health --timeout 2s";
        };
      };
    };

    timers.arcane-healthcheck = {
      description = "Periodic health check for Arcane Manager";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "1min";
        AccuracySec = "15s";
      };
    };
  };
}
