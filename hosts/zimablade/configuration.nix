{ config, pkgs, lib, inputs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # --- 1. KERNEL Y RENDIMIENTO (Intel Apollo Lake) ---
  # En NixOS 25.11 el kernel suele ser muy moderno (6.12+),
  # el soporte para Apollo Lake está maduro.
  # NOTA: sin i915.enable_guc (Apollo Lake no tiene GuC/HuC, daba errores en dmesg).
  boot.kernelPackages = pkgs.linuxPackages;

  # Cargar el microcodigo Intel disponible al inicio; esto no garantiza una
  # mitigacion para cada vulnerabilidad. En el Celeron N3450, la revision
  # disponible es 0x48, pero el kernel sigue reportando RFDS sin mitigar:
  # no forzar el estado "Mitigation" sin una correccion confirmada por Intel.
  hardware.cpu.intel.updateMicrocode = true;

  zramSwap = {
    enable = true;
    algorithm = "lz4"; # más ligero que zstd para el Celeron
  };

  # --- 2. GRÁFICOS (Intel QuickSync) ---
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver   # VA-API/media path; verify with vainfo on this GPU
      intel-compute-runtime-legacy1 # OpenCL for Gen8/Gen9/Gen11 (Apollo Lake is Gen9)
      libvdpau-va-gl
    ];
  };

  # NOTA: sin LIBVA_DRIVER_NAME forzado. Apollo Lake (Gen9 LP) elige solo
  # entre i965/iHD según app; forzar iHD rompía algunas rutas VA-API.

  # --- 3. RED Y SEGURIDAD ---
  networking.hostName = "pico";

  # Evita que el Celeron y la memoria limitada compitan con los contenedores.
  nix.settings = {
    max-jobs = 1;
    cores = 1;

  };

  # Límite de registros ajustado al almacenamiento de la ZimaBlade.
  services.journald.extraConfig = ''
    SystemMaxUse=256M
    MaxRetentionSec=1week
  '';

  # Red privada con el resto de máquinas (interfaz wt0).
  services.netbird.enable = true;

  networking.firewall = {
    enable = true;
    # Pico solo expone SSH a nivel del host. Los puertos publicados por
    # Docker se filtran en FORWARD/DOCKER-USER, no mediante estas reglas INPUT.
    allowedTCPPorts = [ 22 ];
    allowedUDPPorts = [ ];
    # Docker no es una interfaz de confianza: los contenedores no deben
    # recibir acceso incondicional a todos los servicios del host.
    trustedInterfaces = [ "wt0" ];
    checkReversePath = "loose";
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
    # Servidor secundario: login con contraseña permitido (igual que atlas).
    settings.PasswordAuthentication = true;
  };

  # --- 4. DOCKER Y ARCANE EDGE AGENT ---
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
    logDriver = "json-file";
    daemon.settings = {
      "log-opts" = {
        "max-size" = "10m";
        "max-file" = "3";
      };
    };
  };

  # Arcane Agent conecta Pico con el único Manager instalado en Atlas.
  # El modo Edge abre una conexión saliente: no publica el puerto 3553.
  # El token se obtiene desde Environments -> Add Environment -> Edge en Arcane
  # y se guarda fuera del repositorio en /var/lib/arcane-agent/agent.env.
  virtualisation.oci-containers.backend = "docker";
  virtualisation.oci-containers.containers.arcane-agent = {
    # Mantener Edge Agent alineado con el Manager estable de Atlas.
    image = "ghcr.io/getarcaneapp/agent:v2.17.3";
    autoStart = true;

    environment = {
      EDGE_AGENT = "true";
      # Mantiene un túnel continuo (gRPC con fallback WebSocket) para evitar
      # latencia de activación al operar sobre el entorno remoto.
      EDGE_TRANSPORT = "auto";
      MANAGER_API_URL = "http://192.168.1.143:3552";
    };

    environmentFiles = [
      "/var/lib/arcane-agent/agent.env"
    ];

    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock"
      "arcane-agent-data:/app/data"
      # Conserva los Compose existentes de Dockge y expone la misma ruta al agente.
      "/var/lib/dockge/stacks:/var/lib/dockge/stacks"
    ];

    extraOptions = [
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
    ];
  };

  # Directorio persistente del agente y conservación de los stacks existentes.
  # No se elimina /var/lib/dockge/stacks durante la migración.
  systemd.tmpfiles.rules = [
    "d /var/lib/arcane-agent 0700 juan users -"
    "d /var/lib/dockge/stacks 0755 juan users -"
  ];

  # --- 5. MANTENIMIENTO DEL SISTEMA ---
  services.thermald.enable = true;
  services.fstrim.enable = true;
  services.smartd.enable = false;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # Este path usa el checkout local y el flake.lock presente en él. El timer NO
  # ejecuta git pull ni sincroniza /home/juan/nixos con GitHub: esa sincronización
  # debe hacerse y revisarse por separado antes de preparar una nueva generación.
  system.autoUpgrade = {
    enable = true;
    flake = "path:/home/juan/nixos#pico";
    upgrade = false;
    operation = "boot";
    flags = [
      "-L"
      "--no-write-lock-file"
    ];
    # Escalonado respecto a atlas (04:00); prepara una generación sin activarla en caliente.
    dates = "05:30";
    randomizedDelaySec = "45min";
  };

  # --- 6. PAQUETES ---
  environment.systemPackages = with pkgs; [
    intel-gpu-tools
    libva-utils # vainfo para comprobar la ruta de vídeo
    lazydocker
    smartmontools
    htop
  ];

  # --- 7. USUARIO ---
  users.users.juan.extraGroups = [ "docker" "video" "render" ];

  system.stateVersion = "25.11";
}

