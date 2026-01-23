{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # --- 1. KERNEL Y RENDIMIENTO ---
  boot.kernelPackages = pkgs.linuxPackages;
  
  boot.kernel.sysctl = {
    # BBR sigue siendo el rey para el streaming de video
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
    "vm.swappiness" = 10;
  };

  # Mantén estos parámetros para que la iGPU (Intel 12ª Gen) rinda al máximo
  boot.kernelParams = [ "i915.enable_guc=3" ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # --- 2. GRÁFICOS E INTEL QUICK SYNC (QSV) ---
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
      intel-compute-runtime 
    ];
  };

  # --- 3. RED Y SEGURIDAD ---
  networking.hostName = "servidor-nix";
  # IMPORTANTE: En 25.11, si usas VPNs a través de NetworkManager, 
  # ahora debes declarar los plugins explícitamente.
  networking.networkmanager.enable = true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 80 443 ];
    trustedInterfaces = [ "wt0" ];

    # Usamos -I (Insert) en lugar de -A (Append)
    # Esto coloca la regla al principio de la lista, saltándose cualquier bloqueo posterior
    extraCommands = ''
      iptables -I INPUT -s 192.168.1.0/24 -j ACCEPT
    '';
  };

  # Protección contra ataques al SSH (muy recomendado si abres puertos)
  services.fail2ban.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # --- 4. DOCKER Y VIRTUALIZACIÓN ---
  virtualisation.docker = {
    enable = true;
    # Limpieza semanal de imágenes y contenedores parados (Mantenimiento 25.11)
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  # --- 5. USUARIO Y HERRAMIENTAS ---
  users.users.juan = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" "video" "render" ];
  };

  environment.systemPackages = with pkgs; [
    vim git htop btop
    intel-gpu-tools # Úsalo para ver si el proxy usa la GPU ('intel_gpu_top')
    pciutils
  ];

  # --- 6. MANTENIMIENTO DEL SISTEMA ---
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.settings.auto-optimise-store = true;
 
  # --- 7. MONTAJE DE DISCOS ADICIONALES ---
  fileSystems."/mnt/datos" = {
    device = "/dev/disk/by-uuid/TU-UUID-AQUÍ"; # <--- Pega aquí tu UUID
    fsType = "ext4";
    options = [ "defaults" "nofail" ]; # "nofail" evita que el PC no arranque si el disco está desconectado
  };

  system.stateVersion = "25.11"; 
}