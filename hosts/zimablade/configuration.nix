{ config, pkgs, lib, inputs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # --- 1. KERNEL Y RENDIMIENTO (Intel Apollo Lake) ---
  # En NixOS 25.11 el kernel suele ser muy moderno (6.12+),
  # el soporte para Apollo Lake está maduro.
  # NOTA: sin i915.enable_guc (Apollo Lake no tiene GuC/HuC, daba errores en dmesg).
  boot.kernelPackages = pkgs.linuxPackages_latest;

  zramSwap.enable = true;

  boot.loader.systemd-boot.configurationLimit = 10;

  # --- 2. GRÁFICOS (Intel QuickSync) ---
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver   # Gen9+ (Apollo Lake)
      intel-compute-runtime # OpenCL
      libvdpau-va-gl
    ];
  };

  # NOTA: sin LIBVA_DRIVER_NAME forzado. Apollo Lake (Gen9 LP) elige solo
  # entre i965/iHD según app; forzar iHD rompía algunas rutas VA-API.

  # --- 3. RED Y SEGURIDAD ---
  networking.hostName = "pico";

  # Red privada con el resto de máquinas (interfaz wt0).
  services.netbird.enable = true;

  networking.firewall = {
    enable = true; 
    # Solo puertos esenciales. 53 eliminado (a menos que sea servidor DNS).
    allowedTCPPorts = [ 22 5001 ]; 
    allowedUDPPorts = [ ]; 
    trustedInterfaces = [ "wt0" "docker0" ];
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
    # Usamos la imagen oficial
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

  # Flake explícito al repo vivo (outPath apuntaba al store congelado del build).
  system.autoUpgrade = {
    enable = true;
    flake = "path:/home/juan/nixos#pico";
    flags = [
      "-L" # print build logs
    ];
    dates = "04:00";
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
