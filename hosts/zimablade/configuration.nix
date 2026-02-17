{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # --- 1. KERNEL Y RENDIMIENTO (Intel Apollo Lake) ---
  # En NixOS 25.11 el kernel suele ser muy moderno (6.12+), 
  # el soporte para Apollo Lake está maduro.
  boot.kernelPackages = pkgs.linuxPackages_latest;
  
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

  zramSwap.enable = true;

  # Habilitar soporte GPU (GuC/HuC firmware)
  # Necesario para transcodificación eficiente en Jellyfin/Plex/Tdarr
  boot.kernelParams = [ 
    "i915.enable_guc=2" 
  ];

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

  environment.variables = { 
    LIBVA_DRIVER_NAME = "iHD"; 
  };

  # --- 3. RED Y SEGURIDAD ---
  networking.hostName = "pico";

  networking.firewall = {
    enable = true; 
    # Solo puertos esenciales. 53 eliminado (a menos que sea servidor DNS).
    allowedTCPPorts = [ 22 5001 ]; 
    allowedUDPPorts = [ ]; 
    trustedInterfaces = [ "wt0" "docker0" ];
  };

  services.fail2ban.enable = true;
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
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
      "/var/lib/dockge//data:/app/data"
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
    options = lib.mkForce "--delete-older-than 14d"; 
  };

  system.autoUpgrade = {
    enable = true;
    dates = "04:00";
    flake = "/home/juan/nixos"; 
    flags = [ "--update-input" "nixpkgs" "--commit-lock-file" ];
    allowReboot = true;
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
