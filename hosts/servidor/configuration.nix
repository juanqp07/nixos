{ config, pkgs, lib, inputs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # --- KERNEL, CGROUPS Y RENDIMIENTO ---
  boot.kernelPackages = pkgs.linuxPackages_latest;
  hardware.enableRedistributableFirmware = true;
  boot.kernelParams = [
    "systemd.unified_cgroup_hierarchy=1"
    "cgroup_no_v1=all"
    "i915.enable_guc=3"
  ];

  # --- RED ---
  networking.networkmanager.enable = true;
  networking.hostName = "atlas";

  networking.firewall = {
    enable = true; 
    allowedTCPPorts = [ 22 53 80 443 8384 21115 21116 21117 21118 21119 22000 8621 ];
    allowedUDPPorts = [ 53 21027 21116 22000 8621 ];
  
    trustedInterfaces = [ "wt0" ];
    extraCommands = ''
      iptables -A INPUT -s 192.168.1.0/24 -p tcp -m multiport --dports 22,53,80,443,21115,21116,21117,21118,21119,22000,8621 -j ACCEPT
      iptables -A INPUT -s 192.168.1.0/24 -p udp -m multiport --dports 53,21027,21116,22000,8621 -j ACCEPT
    '';
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
    settings.PasswordAuthentication = true;
  };
  # --- DOCKER Y CONTENEDORES ---
  programs.gnupg.agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-curses;  # o pinentry-gtk2 si tienes GUI
  };
  virtualisation.docker = {
    enable = true;
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
      "/home/juan/.docker/config.json:/root/.docker/config.json:ro"
      "/var/run/docker.sock:/var/run/docker.sock"
      "/mnt/datos/AppData/dockge/data:/app/data"
      "/mnt/datos/AppData/dockge/stacks:/opt/stacks"
    ];
    environment = {
      DOCKGE_STACKS_DIR = "/opt/stacks";
    };
  };

  systemd.tmpfiles.rules = [
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


  # --- GPU / VA-API (Intel iGPU) ---
  services.xserver.videoDrivers = [ "modesetting" ];
  
    hardware.graphics = {
    enable = true;
    enable32Bit = true;
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
    MESA_LOADER_DRIVER_OVERRIDE = "anv";
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
    options = [ "defaults" "nofail" "noatime" ];
  };

  # --- HERRAMIENTAS DE SISTEMA / MONITORIZACIÓN ---
  environment.systemPackages = with pkgs; [
    vim htop ncdu iotop ethtool smartmontools zram-generator pass gnupg docker-credential-helpers
  ];

  # --- ACTUALIZACIONES AUTOMÁTICAS ---
  system.autoUpgrade = {
    enable = true;
    flake = inputs.self.outPath;
    flags = [
      "-L" # print build logs
    ];
    dates = "04:00";
    randomizedDelaySec = "45min";
  };

  services.thermald.enable = true;
  system.stateVersion = "25.11";
}
