{ config, pkgs, lib, inputs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # --- KERNEL, CGROUPS Y RENDIMIENTO ---
  # cgroupv1 eliminado en kernel 6.x: no se fuerzan flags obsoletos.
  # Servidor: gobernador performance fijo + irqbalance (reparte red/docker
  # entre P-cores/E-cores del i5-1250P). Sin scx ni mitigations=off (expuesto).
  boot.kernelPackages = pkgs.linuxPackages_latest;
  hardware.enableRedistributableFirmware = true;
  boot.kernelParams = [
    "i915.enable_guc=3"
    "intel_pstate=active"
  ];

  powerManagement.cpuFreqGovernor = "performance";
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
    daemon = {
      settings = {
        # claves con guiones es más seguro escribirlas como strings
        "storage-driver" = "overlay2";
        "log-driver"     = "journald";
      };
    };
  };

  # --- DOCKGE ---
  virtualisation.oci-containers.backend = "docker";
  virtualisation.oci-containers.containers.dockge = {
    image = "cmcooper1980/dockge:latest";
    autoStart = true;
    ports = [ "5001:5001" ];
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock"
      "/mnt/datos/AppData/dockge/docker:/root/.docker:ro"
      "/mnt/datos/AppData/dockge/data:/app/data"
      "/mnt/datos/AppData/dockge/stacks:/opt/stacks"
    ];
    environment = {
      DOCKGE_STACKS_DIR = "/opt/stacks";
    };
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

  # --- HERRAMIENTAS DE SISTEMA / MONITORIZACIÓN ---
  environment.systemPackages = with pkgs; [
    vim htop ncdu iotop ethtool smartmontools zram-generator pass gnupg docker-credential-helpers
    intel-gpu-tools # intel_gpu_top: verificar QSV/iGPU en jellyfin/immich
    lazydocker # gestión TUI de los ~70 contenedores
  ];

  # --- ACTUALIZACIONES AUTOMÁTICAS ---
  # Flake explícito al repo vivo (outPath apuntaba al store congelado del build).
  system.autoUpgrade = {
    enable = true;
    flake = "path:/home/juan/nixos#atlas";
    flags = [
      "-L" # print build logs
    ];
    dates = "04:00";
    randomizedDelaySec = "45min";
  };

  services.thermald.enable = true;
  # TRIM semanal para el NVMe (desktops y titan ya lo tienen).
  services.fstrim.enable = true;
  system.stateVersion = "25.11";
}
