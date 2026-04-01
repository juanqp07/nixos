{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "elytra";
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # --- 1. OPTIMIZACIÓN CPU (Intel i5-13450HX) ---
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # --- 2. GRÁFICOS E HÍBRIDO (Intel 13th Gen + NVIDIA RTX 5050) ---
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
      libvdpau-va-gl
    ];
  };

  hardware.nvidia = {
    modesetting.enable = true;
    open = true; 
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.latest; 
    
    powerManagement.enable = true;
    powerManagement.finegrained = false;

    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      # Verifica estos IDs con 'lspci | grep -E "VGA|3D"'
      intelBusId = "PCI:0:2:0";  
      nvidiaBusId = "PCI:1:0:0"; 
    };
  };

  # --- 3. RED Y BLUETOOTH (Optimizado para Gaming) ---
  
  # Usamos el backend por defecto (wpa_supplicant) que es más estable para jugar que iwd
  networking.networkmanager.enable = true;
  
  # Desactivamos el ahorro de energía que mata el ping
  networking.networkmanager.wifi.powersave = false;
  networking.networkmanager.wifi.macAddress = "preserve";

  # PARCHE PARA REALTEK RTL8852BE:
  # Desactivamos ASPM y Power Save a nivel de driver (módulo rtw89)
  boot.extraModprobeConfig = ''
    options rtw89_pci disable_aspm_l1=1 disable_aspm_l1ss=1
    options rtw89_core disable_ps_mode=1
  '';

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings.General = {
      # For newer Bluetooth capabilities.
      Experimental = true;
      # For quicker device reconnection.
      FastConnectable = true;
    };
    settings.Policy = {
      # Power up all controllers.
      AutoEnable = true;
    };
  };

  # --- 4. PAQUETES Y HERRAMIENTAS ---
  environment.systemPackages = with pkgs; [
    powertop 
    nvtopPackages.nvidia
    brightnessctl
    vdpauinfo
    libva-utils
    intel-gpu-tools
    (alpaca.override {
      ollama = ollama-cuda;
    })
  ];

  services.libinput.enable = true;

  system.stateVersion = "25.11"; 
}