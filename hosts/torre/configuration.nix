{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];
  
  networking.hostName = "ordenador";

  # Carga drivers AMD antes de arrancar el entorno gráfico para evitar parpadeos
  boot.initrd.kernelModules = [ "amdgpu" ];
  services.xserver.videoDrivers = [ "amdgpu" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    # Soporte extra para Compute (Blender/IA) y decodificación
    extraPackages = with pkgs; [
      rocmPackages.clr
      rocmPackages.clr.icd
    ];
  };
  services.openssh.enable = true;
  environment.systemPackages = with pkgs; [
    prismlauncher headsetcontrol lunar-client
    lact
  ];
  
  services.udev.packages = [ pkgs.headsetcontrol ];

  # Optimización del servicio Headset
  systemd.services.headset-led-off = {
    description = "Apagar LEDs del Headset cíclicamente";
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
      User = "root"; # Necesita root para acceder al dispositivo USB
    };

    # Añadimos el PATH para asegurar que encuentre sleep y headsetcontrol
    path = with pkgs; [ headsetcontrol coreutils shotcut];
    
    script = ''
      while true; do
        headsetcontrol -l 0 -s 0
        sleep 30
      done
    '';
  };

  systemd.packages = [ pkgs.lact ];
  systemd.services.lactd.wantedBy = [ "multi-user.target" ];
  system.stateVersion = "25.11";
}