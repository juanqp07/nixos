{ config, pkgs, lib, ... }:

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
  boot.kernel.sysctl = {
    # --- Rendimiento de Red ---
    "net.core.default_qdisc" = "cake";
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.ipv4.tcp_rmem" = "4096 87380 16777216";
    "net.ipv4.tcp_wmem" = "4096 65536 16777216";
    "net.ipv4.tcp_tw_reuse" = 1;

    # --- Seguridad de Red ---
    "net.ipv4.ip_forward" = 0;
    "net.ipv6.conf.all.forwarding" = 0;
    "net.ipv4.icmp_echo_ignore_all" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv6.conf.default.accept_source_route" = 0;

    # --- Memoria y Ficheros ---
    "fs.file-max" = 2097152;
    "fs.nr_open" = 1048576;
    "vm.swappiness" = 10;
    "vm.max_map_count" = 262144;

    # --- Miscelánea de Seguridad ---
    "kernel.sysrq" = 0;
  };

  # --- RED ---
  networking.networkmanager.enable = true;
  networking.hostName = "atlas";

  networking.firewall = {
    enable = true; 
    allowedTCPPorts = [ 22 53 80 443 22000 8621 ];
    allowedUDPPorts = [ 21027 22000 8621 53 ];
    
    trustedInterfaces = [ "wt0" "docker0" ];
    extraCommands = ''
      iptables -A INPUT -s 192.168.1.0/24 -j ACCEPT
    '';
  };

  services.fail2ban.enable = true;
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = true;
  };
  # --- DOCKER Y CONTENEDORES ---
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
    vim htop ncdu iotop ethtool smartmontools zram-generator
  ];

  services.thermald.enable = true;
  system.stateVersion = "25.11";
}
