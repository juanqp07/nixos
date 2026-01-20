{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "portatil-jqp";

  # Configuración WiFi específica del portátil
  networking.networkmanager.wifi.backend = "iwd";
  networking.wireless.iwd.enable = true;
  
  # Bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  # DRIVERS NVIDIA (Híbrido)
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics.enable = true; # Nuevo nombre de hardware.opengl

  hardware.nvidia = {
    modesetting.enable = true;
    open = false; # GTX 1050 Ti requiere drivers propietarios cerrados
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      # BUS ID COPIADOS DE TU CONFIG
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };
}
