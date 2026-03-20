{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "elytra"; # He unificado el hostname que tenías duplicado arriba
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # --- 1. OPTIMIZACIÓN CPU (Intel i5-13450HX) ---
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  
  # Gestión de energía (sigue siendo excelente para CPUs con P-Cores y E-Cores)
services.auto-cpufreq.enable = true;
  # En las versiones nuevas, la estructura debe ser exactamente así:
  services.auto-cpufreq.settings = {
    battery = {
       governor = "powersave";
       turbo = "never";
    };
    charger = {
       governor = "performance";
       turbo = "auto";
    };
  };

  # --- 2. GRÁFICOS E HÍBRIDO (Intel 13th Gen + NVIDIA RTX 5050) ---
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver # Compatible y recomendado para Gen 8+ (tu 13ª Gen)
      vaapiIntel         # Respaldo
      libvdpau-va-gl
    ];
  };

  hardware.nvidia = {
    modesetting.enable = true;
    # IMPORTANTÍSIMO: Para RTX 5050 es mejor usar los módulos abiertos
    open = true; 
    nvidiaSettings = true;
    
    # Al ser una GPU tan nueva, necesitamos los drivers más recientes, no los estables
    package = config.boot.kernelPackages.nvidiaPackages.latest; 
    
    powerManagement.enable = true;
    powerManagement.finegrained = false;

    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      
      # ⚠️ ¡ATENCIÓN! DEBES CAMBIAR ESTO ⚠️
      # Ejecuta en la terminal del Live USB: lspci | grep -E "VGA|3D"
      # Traduce el formato. Ejemplo: si es 00:02.0 -> escribe "PCI:0:2:0"
      intelBusId = "PCI:0:2:0";  # Cambiar por el tuyo
      nvidiaBusId = "PCI:1:0:0"; # Cambiar por el tuyo
    };
  };

  # --- 3. RED Y BLUETOOTH ---
  networking.networkmanager.wifi.backend = "iwd";
  networking.wireless.iwd.enable = true;
  
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  # --- 4. PAQUETES Y HERRAMIENTAS ---
  environment.systemPackages = with pkgs; [
    powertop 
    nvtopPackages.nvidia
    brightnessctl
    vdpauinfo
    libva-utils
  ];

  services.libinput.enable = true;

  system.stateVersion = "25.11"; 
}