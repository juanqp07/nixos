{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];
  
  networking.hostName = "ordenador";

  boot.initrd.kernelModules = [ "amdgpu" ];
  services.xserver.videoDrivers = [ "amdgpu" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  
  environment.systemPackages = with pkgs; [
    prismlauncher headsetcontrol lunar-client
  ];
  services.udev.packages = [ pkgs.headsetcontrol ];

  # Servicio para ejecutar headsetcontrol automáticamente al arrancar
  systemd.services.headset-led-off = {
    description = "Apagar LEDs del Headset cíclicamente";
    wantedBy = [ "multi-user.target" ];
    
    # Esto asegura que el comando se reinicie si falla
    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
    };

    # Aquí definimos el script.
    # Usamos ${pkgs.headsetcontrol} para referenciar la ruta exacta del binario
    # sin necesidad de instalarlo globalmente si no quieres.
    script = ''
      while true; do
        ${pkgs.headsetcontrol}/bin/headsetcontrol -l 0 -s 0
        ${pkgs.coreutils}/bin/sleep 30
      done
    '';
  };
}
