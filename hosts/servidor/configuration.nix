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

  # --- ARCANE ---
virtualisation.oci-containers.backend = "docker";

virtualisation.oci-containers.containers = {
  arcane = {
    image = "ghcr.io/getarcaneapp/manager:latest";
    autoStart = true;

    ports = [
      "3552:3552"
    ];

    volumes = [
      "arcane-data:/app/data"
      "/var/run/docker.sock:/var/run/docker.sock"
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
    };

    dependsOn = [ "arcane-postgres" ];

    extraOptions = [
      "--network=arcane-net"
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
    #
    # Si necesitas acceder desde el propio host:
    # ports = [ "127.0.0.1:5334:5432" ];
  };
};

# Crear la red Docker antes de iniciar los contenedores.
systemd.services.arcane-docker-network = {
  description = "Docker network for Arcane";
  wantedBy = [ "multi-user.target" ];
  requires = [ "docker.service" ];
  after = [ "docker.service" ];
  before = [
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

# Asegurar que la red exista también al iniciar manualmente los servicios.
systemd.services.docker-arcane = {
  requires = [ "arcane-docker-network.service" ];
  after = [ "arcane-docker-network.service" ];
};

systemd.services.docker-arcane-postgres = {
  requires = [ "arcane-docker-network.service" ];
  after = [ "arcane-docker-network.service" ];
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
      mesa
      linux-firmware
      vulkan-loader
      vulkan-tools
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
    vim htop ncdu iotop ethtool smartmontools pass gnupg docker-credential-helpers
    intel-gpu-tools # intel_gpu_top: verificar QSV/iGPU en jellyfin/immich
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
