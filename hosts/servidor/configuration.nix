{ config, pkgs, lib, inputs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # --- KERNEL, CGROUPS Y RENDIMIENTO ---
  # cgroupv1 eliminado en kernel 6.x: no se fuerzan flags obsoletos.
  # Servidor: gobernador performance fijo + irqbalance (reparte red/docker
  # entre P-cores/E-cores del i5-1250P). Sin scx ni mitigations=off (expuesto).
  boot.kernelPackages = pkgs.linuxPackages;
  hardware.enableRedistributableFirmware = true;
  boot.kernelParams = [
    "intel_pstate=active"
  ];

  # Servidor: intel_pstate+HWP escala solo (powersave + EPP balance_performance
  # por defecto): 400MHz en idle (fresco/silencioso) y turbo bajo carga.
  # Rendimiento bajo demanda sin el ruido/consumo del governor fijo.
  powerManagement.cpuFreqGovernor = "powersave";
  services.irqbalance.enable = true;

  # --- RED ---
  networking.networkmanager.enable = true;
  networking.hostName = "atlas";

  # Prioriza los servicios Docker permanentes frente a compilaciones del sistema.
  nix.settings = {
    max-jobs = 3;
    cores = 2;
  };

  # Docker usa journald como backend; limita el espacio de los registros persistentes.
  services.journald.extraConfig = ''
    SystemMaxUse=1G
    MaxRetentionSec=2week
  '';

  # Red privada con el resto de máquinas (interfaz wt0).
  services.netbird.enable = true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 53 80 443 8384 21115 21116 21117 21118 21119 22000 8621 25565 ];
    allowedUDPPorts = [ 53 21027 21116 22000 8621 ];

    trustedInterfaces = [ "wt0" ];
    checkReversePath = "loose";
    # NOTA: no se usa extraCommands con iptables manual (duplicaba allowed*Ports
    # y docker escribe sus propias reglas de todas formas). Si quieres restringir
    # a LAN, filtra por interfaz con interfaces.wt0.allowed* en vez de global.
  };

  services.fail2ban = {
    enable = true;

    maxretry = 3;
    bantime = "24h";

    bantime-increment = {
      enable = true;
      rndtime = "15m";
      overalljails = true;
      maxtime = "90d";
      multipliers = "1 2 4 8 16 32 64";
    };

    jails = {
      sshd = {
        enabled = true;
        filter = "sshd[mode=aggressive]";

        settings = {
          maxretry = 3;
          findtime = "10m";
        };
      };
    };
  };
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    # Servidor secundario: login con contraseña permitido (igual que pico).
    settings.PasswordAuthentication = true;
  };
  # --- DOCKER Y CONTENEDORES ---
  programs.gnupg.agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-curses;  # o pinentry-gtk2 si tienes GUI
  };
  virtualisation.docker = {
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

  # --- DOCKER: RESTRINGIR PUERTOS PUBLICADOS DE APLICACIONES ---
  # Docker publica puertos fuera de la cadena INPUT de NixOS. DOCKER-USER
  # filtra el tráfico reenviado y compara el puerto original anterior al DNAT.
  # La LAN 192.168.1.0/24, NetBird (wt0) y los bridges Docker (Zoraxy y
  # comunicación interna) conservan el acceso. 80/443, SSH, RustDesk,
  # Syncthing y Minecraft no se incluyen en esta lista.
  systemd.services.docker-published-ports-private = {
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

  # --- ARCANE ---
  virtualisation.oci-containers.backend = "docker";

  virtualisation.oci-containers.containers = {
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
        # La imagen incluye un healthcheck binario; no necesita shell.
        "--health-cmd=./healthcheck"
        "--health-start-period=15s"
        "--health-interval=10s"
        "--health-timeout=5s"
        "--health-retries=15"
      ];
    };

    arcane = {
      image = "ghcr.io/getarcaneapp/manager:latest";
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

      dependsOn = [ "arcane-postgres" "arcane-docker-proxy" ];

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

  # Crear la red Docker privada antes de iniciar Arcane, el proxy y PostgreSQL.
  systemd.services.arcane-network = {
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
  systemd.services.docker-arcane-docker-proxy = {
    requires = [ "arcane-network.service" ];
    after = [ "arcane-network.service" ];
  };

  # Esperar a que el proxy pase su healthcheck antes de arrancar Arcane.
  # dependsOn solo ordena los servicios; esta unidad espera al estado healthy real.
  systemd.services.arcane-proxy-ready = {
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
      attempt=0

      while [ "$attempt" -lt 90 ]; do
        attempt=$((attempt + 1))
        status="$(${config.virtualisation.docker.package}/bin/docker inspect --format '{{.State.Health.Status}}' arcane-docker-proxy 2>/dev/null || true)"

        case "$status" in
          healthy)
            exit 0
            ;;
          unhealthy)
            echo "Arcane no se inicia: el socket proxy está unhealthy." >&2
            ${config.virtualisation.docker.package}/bin/docker logs --tail=100 arcane-docker-proxy >&2 || true
            exit 1
            ;;
        esac

        ${pkgs.coreutils}/bin/sleep 2
      done

      echo "Arcane no se inicia: el socket proxy no alcanzó healthy en 180 segundos." >&2
      ${config.virtualisation.docker.package}/bin/docker logs --tail=100 arcane-docker-proxy >&2 || true
      exit 1
    '';
  };

  systemd.services.docker-arcane = {
    requires = [
      "arcane-network.service"
      "arcane-proxy-ready.service"
    ];
    after = [
      "arcane-network.service"
      "arcane-proxy-ready.service"
    ];
  };

  systemd.services.docker-arcane-postgres = {
    requires = [ "arcane-network.service" ];
    after = [ "arcane-network.service" ];
  };

  systemd.tmpfiles.rules = [
    "d /mnt/datos/AppData/dockge/docker 0755 juan users -"
    "d /mnt/datos/AppData/dockge/data 0755 juan users -"
    "d /mnt/datos/AppData/dockge/stacks 0755 juan users -"
  ];
  # --- ZRAM ---
  zramSwap = {
    enable = true;
    algorithm = "lz4";
    memoryPercent = 75;
    priority = 100;
   };


  # --- GPU / VA-API (Intel iGPU, headless: solo transcodificación) ---
    hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
      intel-compute-runtime
    ];
  };

  environment.variables = {
    LANG = "es_ES.UTF-8";
    LC_ALL = "es_ES.UTF-8";
    LIBVA_DRIVER_NAME = "iHD";
  };

  # --- USUARIOS ---
  users.users.juan = {
    isNormalUser = true;
    extraGroups = [ "docker" "video" "render" "dialout" ];
  };

  # --- ALMACENAMIENTO ---
  fileSystems."/mnt/datos" = {
    device = "/dev/disk/by-uuid/d1908c00-4835-41fd-851b-cb2903898ec7";
    fsType = "ext4";
    options = [ "defaults" "nofail" "noatime" "x-systemd.automount" "x-systemd.device-timeout=5" ];
  };

  # El disco contiene datos persistentes de contenedores. Si no monta, no arranques
  # Docker: evitar que los bind mounts creen directorios vacíos en la raíz del sistema.
  systemd.services.docker.unitConfig.RequiresMountsFor = "/mnt/datos";

  # --- HERRAMIENTAS DE SISTEMA / MONITORIZACIÓN ---
  environment.systemPackages = with pkgs; [
    vim htop ncdu iotop ethtool smartmontools lm_sensors pass gnupg docker-credential-helpers
    intel-gpu-tools # intel_gpu_top: verificar QSV/iGPU en jellyfin/immich
    libva-utils # vainfo: comprobar VA-API antes de probar una transcodificación
    lazydocker # gestión TUI de los ~70 contenedores
  ];

  # --- ACTUALIZACIONES AUTOMÁTICAS ---
  # Usa las revisiones fijadas en flake.lock: la actualización del lock se revisa
  # y despliega de forma controlada, en lugar de resolver una rama distinta cada noche.
  system.autoUpgrade = {
    enable = true;
    flake = "path:/home/juan/nixos#atlas";
    upgrade = false;
    operation = "boot";
    flags = [
      "-L"
      "--no-write-lock-file"
    ];
    # Prepara la generación fuera del horario de uso; se activa en el siguiente reinicio planificado.
    dates = "04:00";
    randomizedDelaySec = "45min";
  };

  services.thermald.enable = true;
  # SMART: aviso temprano de fallo de disco (complementa a beszel).
  services.smartd.enable = true;
  # TRIM semanal para el NVMe (desktops y titan ya lo tienen).
  services.fstrim.enable = true;
  system.stateVersion = "25.11";
}
