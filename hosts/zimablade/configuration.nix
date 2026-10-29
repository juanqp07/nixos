{ config, pkgs, lib, inputs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # --- 1. KERNEL Y RENDIMIENTO (Intel Apollo Lake) ---
  # En NixOS 25.11 el kernel suele ser muy moderno (6.12+),
  # el soporte para Apollo Lake está maduro.
  # NOTA: sin i915.enable_guc (Apollo Lake no tiene GuC/HuC, daba errores en dmesg).
  boot.kernelPackages = pkgs.linuxPackages;

  zramSwap = {
    enable = true;
    algorithm = "lz4"; # más ligero que zstd para el Celeron
  };

  boot.loader.systemd-boot.configurationLimit = 10;

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

  # Evita que las compilaciones compitan con Docker en el Celeron y su RAM limitada.
  nix.settings = {
    max-jobs = 1;
    cores = 1;
  };

  # Red privada con el resto de máquinas (interfaz wt0).
  services.netbird.enable = true;

  networking.firewall = {
    enable = true; 
    # Solo puertos esenciales. 53 eliminado (a menos que sea servidor DNS).
    allowedTCPPorts = [ 22 5001 53 ]; 
    allowedUDPPorts = [ 53 ]; 
    trustedInterfaces = [ "wt0" "docker0" ];
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

  # --- 4. DOCKER Y DOCKGE ---
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

  # Dockge container
  virtualisation.oci-containers.backend = "docker";
  virtualisation.oci-containers.containers.dockge = {
    # Fork de louislam/dockge mantenido por cmcooper1980 (no es la imagen oficial)
    image = "cmcooper1980/dockge:latest";
    autoStart = true;
    ports = [ "5001:5001" ];
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock"
      "/var/lib/dockge/data:/app/data"
      "/var/lib/dockge/stacks:/opt/stacks"
    ];
    environment = {
      DOCKGE_STACKS_DIR = "/opt/stacks";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/dockge/data 0755 juan users -"
    "d /var/lib/dockge/stacks 0755 juan users -"
  ];

  # --- 5. MANTENIMIENTO DEL SISTEMA ---
  services.thermald.enable = true; 
  services.smartd.enable = false;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = lib.mkForce "--delete-older-than 7d"; 
  };

  # Usa las revisiones fijadas en flake.lock. El lock se actualiza y revisa de forma controlada.
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
    lm_sensors
    ncdu
    tmux
    lazydocker
    smartmontools
    git
    htop
  ];

  # --- 7. USUARIO ---
  users.users.juan.extraGroups = [ "docker" "video" "render" ];

  system.stateVersion = "25.11"; 
}
