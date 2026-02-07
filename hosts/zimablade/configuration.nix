{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # --- 1. KERNEL AND PERFORMANCE (Intel N3450 Apollo Lake) ---
  boot.kernelPackages = pkgs.linuxPackages_latest;
  
  boot.kernel.sysctl = {
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
    "vm.swappiness" = 10;
    "fs.file-max" = 100000;
  };

  zramSwap.enable = true;

  # Enable GPU support
  # Apollo Lake supports GuC/HuC.
  boot.kernelParams = [ 
    "i915.enable_guc=2" 
  ];

  boot.loader.systemd-boot.configurationLimit = 10;

  # --- 2. GRAPHICS (Intel QuickSync) ---
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver   # For Gen9+ (Apollo Lake is Gen9)
      intel-compute-runtime # OpenCL
      libvdpau-va-gl
    ];
  };

  environment.variables = { 
    LIBVA_DRIVER_NAME = "iHD"; 
  };


  # --- 3. NETWORK AND SECURITY ---
  networking.hostName = "zimablade";

  networking.firewall = {
    enable = true; 
    allowedTCPPorts = [ 22 53 5001 ]; # Added 5001 for Dockge
    allowedUDPPorts = [ 53 ];
    
    trustedInterfaces = [ "docker0" ];
  };

  services.fail2ban.enable = true;
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = true;
  };

  # --- 4. DOCKER AND DOCKGE ---
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

  # --- 5. SYSTEM MAINTENANCE ---
  services.thermald.enable = true; 
  services.smartd.enable = true;

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

  # --- 6. PACKAGES ---
  environment.systemPackages = with pkgs; [
    intel-gpu-tools 
    lm_sensors
    ncdu
    tmux
    lazydocker
    smartmontools
  ];

  # --- 7. USER ---
  users.users.juan.extraGroups = [ "docker" "video" "render" ];

  system.stateVersion = "24.05"; 
}
