{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # --- 1. KERNEL Y RENDIMIENTO (Intel 12th Gen Headless) ---
  boot.kernelPackages = pkgs.linuxPackages_latest;
  
  boot.kernel.sysctl = {
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
    "vm.swappiness" = 10;
    "fs.file-max" = 100000;
    "net.core.rmem_max" = 4194304;
    "net.core.wmem_max" = 4194304;
  };

  zramSwap.enable = true;

  # Habilitar soporte para la iGPU (QuickSync)
  hardware.enableRedistributableFirmware = true;
  boot.kernelParams = [ "i915.force_probe=46a6" ];

  boot.loader.systemd-boot.configurationLimit = 10;

  # --- 2. GRÁFICOS Y TRANSCODIFICACIÓN (Optimizado para Alder Lake) ---
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
      intel-compute-runtime
      mesa
      linux-firmware
    ];
  };

environment.variables = { 
    LIBVA_DRIVER_NAME = "iHD"; 
    MESA_LOADER_DRIVER_OVERRIDE = "anv";
  };


  # --- 3. RED Y SEGURIDAD ---
  networking.hostName = "servidor";

  networking.firewall = {
    enable = true; 
    allowedTCPPorts = [ 22 53 8008 8443 22000 8621 ];
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

  # --- 4. DOCKER Y DOCKGE (Declarativo) ---
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
    logDriver = "json-file";
    extraOptions = "--log-opt max-size=50m --log-opt max-file=3";
  };

  # Este bloque sustituye tu "docker-compose up" manual para Dockge
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

  # --- 5. MANTENIMIENTO Y MONITORIZACIÓN ---
  services.thermald.enable = true; # Vital para Alder Lake Headless
  services.smartd.enable = true;   # Vigilancia de discos

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = lib.mkForce "--delete-older-than 14d";
  };

  system.autoUpgrade = {
    enable = true;
    dates = "04:00";
    flake = "/home/juan/nixos"; # Asegúrate de que esta es la ruta a tu repo
    flags = [ "--update-input" "nixpkgs" "--commit-lock-file" ];
    allowReboot = true;
  };

  # --- 6. PAQUETES DE GESTIÓN (Headless) ---
  environment.systemPackages = with pkgs; [
    intel-gpu-tools 
    nvtopPackages.intel 
    ctop 
    lm_sensors
    ncdu
    tmux
    lazydocker
    smartmontools
    ollama
  ];

  # --- 7. USUARIO Y ALMACENAMIENTO ---
  users.users.juan.extraGroups = [ "docker" "video" "render" "dialout" ];

  fileSystems."/mnt/datos" = {
    device = "/dev/disk/by-uuid/d1908c00-4835-41fd-851b-cb2903898ec7";
    fsType = "ext4";
    options = [ "defaults" "nofail" "noatime" ];
  };

  # --- 8. Ollama ---
  services.ollama = {
    enable = true;
    package = pkgs.ollama-vulkan;
  };
  
  systemd.services.ollama.environment = { 
    # Desactiva la optimización que rompe los cálculos en Intel Xe
    "OLLAMA_FLASH_ATTENTION" = "0"; 
  };
  system.stateVersion = "25.11"; 
}
