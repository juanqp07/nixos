{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "torre-jqp";

  # DRIVERS AMD
  # El kernel carga 'amdgpu' automáticamente, pero es bueno ser explícito
  boot.initrd.kernelModules = [ "amdgpu" ];
  services.xserver.videoDrivers = [ "amdgpu" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true; # Importante para Steam/Juegos
  };

  # Bluetooth (si tienes pincho USB o placa base con BT)
  hardware.bluetooth.enable = true;
}
