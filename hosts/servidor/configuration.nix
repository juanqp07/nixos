{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # --- 1. KERNEL Y RENDIMIENTO (Optimizado para i5 12th Gen) ---
  # Usamos el kernel más reciente para mejor soporte de iGPU y E-cores/P-cores
  boot.kernelPackages = pkgs.linuxPackages_latest;
  
  boot.kernel.sysctl = {
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
    # Reducimos uso de swap en disco drásticamente
    "vm.swappiness" = 10;
    # Aumentamos límite de archivos abiertos (necesario para muchos contenedores/Plex/Navidrome)
    "fs.file-max" = 100000;
  };

  # Habilitar Swap en RAM (ZRAM). Muy recomendado para servidores con mucha carga.
  zramSwap.enable = true;

  # Parámetros para Intel QuickSync (Guc/Huc)
  boot.kernelParams = [ 
    "i915.enable_guc=3" 
    # Opcional: Ayuda si tienes tearing o problemas de energía
    "i915.enable_psr=0" 
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Limita las entradas de boot guardadas para no llenar la partición EFI
  boot.loader.systemd-boot.configurationLimit = 10;

  # --- 2. GRÁFICOS E INTEL QUICK SYNC (QSV) ---
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
      intel-compute-runtime 
      # Drivers para transcodificación VAAPI (legacy pero útiles)
      intel-vaapi-driver
    ];
  };

  # --- 3. RED Y SEGURIDAD ---
  networking.hostName = "servidor-nix";
  networking.networkmanager.enable = true;

  # ¡IMPORTANTE! Reactivamos el Firewall por seguridad
  networking.firewall = {
    enable = true; 
    # Puertos del Host (Zoraxy maneja 80/443, SSH es 22)
    allowedTCPPorts = [ 22 8008 8443 ];
    # Puertos UDP si usas Wireguard/Gluetun o mDNS
    allowedUDPPorts = [ ]; 
    
    trustedInterfaces = [ "wt0" "docker0" ]; # Confiar en Netbird y Docker interno
    
    # Tu regla personalizada para permitir toda la LAN (más limpio así)
    extraCommands = ''
      iptables -A INPUT -s 192.168.1.0/24 -j ACCEPT
    '';
  };

  # Fail2Ban: Esencial si tienes el puerto 22 abierto, aunque sea solo en LAN
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
  };

  services.openssh = {
    enable = true;
    settings = {
      # RECOMENDACIÓN: Cambia a "no" y usa llaves SSH en cuanto puedas
      PasswordAuthentication = true; 
      PermitRootLogin = "no";
    };
  };

  # Si AdGuard Home necesita el puerto 53 del host, descomenta esto:
  # services.resolved.enable = false;

  # --- 4. DOCKER ---
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
    # Configuración global del demonio para rotación de logs (evita discos llenos)
    logDriver = "json-file";
    extraOptions = "--log-opt max-size=50m --log-opt max-file=3";
  };

  # --- 5. USUARIO ---
  users.users.juan = {
    isNormalUser = true;
    # Añadido "dialout" por si usas dispositivos Zigbee/USB en el futuro
    extraGroups = [ "wheel" "docker" "video" "render" "dialout" ];
  };

  # --- 6. PAQUETES DE DIAGNÓSTICO ---
  environment.systemPackages = with pkgs; [
    vim git htop btop
    intel-gpu-tools 
    pciutils
    nvtopPackages.intel # Visor visual de uso de GPU (alternativa a intel_gpu_top)
    ctop # Como htop pero para contenedores Docker
    lm_sensors # Para ver temperaturas de la CPU
  ];

  # --- 7. MANTENIMIENTO ---
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.settings.auto-optimise-store = true;
 
  # --- 8. ALMACENAMIENTO ---
  fileSystems."/mnt/datos" = {
    device = "/dev/disk/by-uuid/d1908c00-4835-41fd-851b-cb2903898ec7";
    fsType = "ext4";
    options = [ "defaults" "nofail" "noatime" ]; # "noatime" mejora rendimiento en discos mecánicos/SSDs
  };

  system.stateVersion = "25.11"; 
}