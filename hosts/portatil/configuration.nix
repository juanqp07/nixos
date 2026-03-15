{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "elytra";
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # --- RED ---
  networking.networkmanager.wifi.backend = "iwd";
  networking.wireless.iwd.enable = true;
  
  # --- BLUETOOTH ---
{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "portatil";

  # --- 1. OPTIMIZACIÓN CPU (Intel i5-9300H) ---
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  
  # Gestión de energía inteligente (mejor que thermald solo)
  services.auto-cpufreq.enable = true;
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

  # --- 2. GRÁFICOS E HÍBRIDO (Intel + NVIDIA 1050 Ti) ---
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver # Para i5-9300H (Coffee Lake)
      vaapiIntel         # VA-API antiguo pero estable
      libvdpau-va-gl
    ];
  };

  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    powerManagement.enable = true;
    powerManagement.finegrained = false;

    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      
      # IMPORTANTE: Asegúrate de que estos ID son correctos. 
      # Ejecuta: lspci | grep -E "VGA|3D"
      # Intel suele ser 00:02.0 -> "PCI:0:2:0"
      # Nvidia suele ser 01:00.0 -> "PCI:1:0:0"
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
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
}
