{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];
  
{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "torre";

  # ---------------------------------------------------------
  # 1. OPTIMIZACIÓN CPU (Ryzen 5 5600X)
  # ---------------------------------------------------------
  # Esencial: Actualiza el microcódigo de AMD para estabilidad y seguridad.
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # ---------------------------------------------------------
  # 2. GRÁFICOS Y GPU (Radeon RX 6700 XT)
  # ---------------------------------------------------------
  boot.initrd.kernelModules = [ "amdgpu" ];
  services.xserver.videoDrivers = [ "amdgpu" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true; # Necesario para Steam y Wine
    
    # Soporte para Compute (OpenCL/HIP)
    extraPackages = with pkgs; [
      rocmPackages.clr
      rocmPackages.clr.icd
    ];
  };

  # TRUCO IMPORTANTE PARA LA 6700 XT (RDNA 2)
  # La 6700 XT usa la arquitectura 'gfx1031'. ROCm a veces solo busca 'gfx1030' (6800/6900).
  # Forzamos la versión para que Blender/PyTorch funcionen sin errores.
  environment.variables = {
    "HSA_OVERRIDE_GFX_VERSION" = "10.3.0";
  };

  # ---------------------------------------------------------
  # 3. SERVICIOS Y PAQUETES
  # ---------------------------------------------------------
  services.openssh.enable = true;
  
  # Si ya tienes gamemode activado en otro lugar, genial. 
  # Si no, descomenta la siguiente línea para asegurarlo aquí:
  # programs.gamemode.enable = true;

  environment.systemPackages = with pkgs; [
    prismlauncher 
    headsetcontrol 
    lunar-client
    lact
    # Herramientas de diagnóstico recomendadas para tu GPU
    clinfo       # Verifica OpenCL
    vulkan-tools # Verifica Vulkan
    amdgpu_top   # Monitor de GPU en terminal (muy útil)
  ];

  # ---------------------------------------------------------
  # 4. CONFIGURACIÓN HEADSET (Optimización Systemd)
  # ---------------------------------------------------------
  services.udev.packages = [ pkgs.headsetcontrol ];

  # En lugar de un script con 'while sleep', usamos un Timer.
  # Es más eficiente y limpio para el sistema.

  # Definimos el servicio (qué hace)
  systemd.services.headset-led-off = {
    description = "Apagar LEDs del Headset (Ejecución única)";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = "${pkgs.headsetcontrol}/bin/headsetcontrol -l 0 -s 0";
    };
  };

  # Definimos el temporizador (cuándo lo hace)
  systemd.timers.headset-led-off = {
    description = "Timer para apagar LEDs del Headset cada 30s";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1m";        # Esperar 1 min al arrancar
      OnUnitActiveSec = "30s"; # Repetir cada 30s tras la última ejecución
      Unit = "headset-led-off.service";
    };
  };

  # ---------------------------------------------------------
  # 5. CONTROL GPU (LACT)
  # ---------------------------------------------------------
  systemd.packages = [ pkgs.lact ];
  systemd.services.lactd.wantedBy = [ "multi-user.target" ];

  system.stateVersion = "25.11"; # Mantén la versión con la que instalaste
}

    # Añadimos el PATH para asegurar que encuentre sleep y headsetcontrol
    path = with pkgs; [ headsetcontrol coreutils ];
    
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
