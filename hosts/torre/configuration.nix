{ config, pkgs, lib, ... }: # Añadimos 'lib' aquí

{

  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "titan";

  # ---------------------------------------------------------
  # 1. OPTIMIZACIÓN CPU (Ryzen 5 5600X)
  # ---------------------------------------------------------
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # ---------------------------------------------------------
  # 2. GRÁFICOS Y GPU (Radeon RX 6700 XT)
  # ---------------------------------------------------------
  boot.initrd.kernelModules = [ "amdgpu" ];
  services.xserver.videoDrivers = [ "amdgpu" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true; 
    
    extraPackages = with pkgs; [
      rocmPackages.clr
      rocmPackages.clr.icd
    ];
  };

  environment.variables = {
    "HSA_OVERRIDE_GFX_VERSION" = "10.3.0";
  };

  # ---------------------------------------------------------
  # 3. SERVICIOS Y PAQUETES
  # ---------------------------------------------------------
  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [
    prismlauncher 
    headsetcontrol 
    lunar-client
    lact
    clinfo       
    vulkan-tools 
    amdgpu_top   
    lmstudio
    jellyfin-desktop
  ];

  # ---------------------------------------------------------
  # 4. CONFIGURACIÓN HEADSET (Usando Timers, no scripts infinitos)
  # ---------------------------------------------------------
  services.udev.packages = [ pkgs.headsetcontrol ];

  systemd.services.headset-led-off = {
    description = "Apagar LEDs del Headset (Ejecución única)";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = "${pkgs.headsetcontrol}/bin/headsetcontrol -l 0 -s 0";
    };
  };

  systemd.timers.headset-led-off = {
    description = "Timer para apagar LEDs del Headset cada 30s";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1m";
      OnUnitActiveSec = "30s";
      Unit = "headset-led-off.service";
    };
  };

  # ---------------------------------------------------------
  # 5. CONTROL GPU (LACT)
  # ---------------------------------------------------------
  systemd.packages = [ pkgs.lact ];
  systemd.services.lactd.wantedBy = [ "multi-user.target" ];

  system.stateVersion = "25.11"; 
}
