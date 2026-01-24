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
    prismlauncher headsetcontrol
  ];
  services.udev.packages = [ pkgs.headsetcontrol ];

  # Servicio para ejecutar headsetcontrol automáticamente al arrancar
  systemd.services.headset_lights_off = {
    description = "Apagar luces del headset cada 30 segundos";
    after = [ "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      # Usamos la ruta directa a los binarios en la Nix Store
      ExecStart = "${pkgs.writeShellScript "headset-script" ''
        while true; do
          ${pkgs.headsetcontrol}/bin/headsetcontrol -l 0 -s 0
          sleep 30
        done
      ''}";
      Restart = "always";
      User = "juan";
    };
  };
}
