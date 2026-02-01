{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "portatil";

  # --- RED ---
  networking.networkmanager.wifi.backend = "iwd";
  networking.wireless.iwd.enable = true;
  
  # --- BLUETOOTH ---
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  # --- GESTIÓN DE ENERGÍA (Vital para portátiles) ---
  # Evita que el PC se caliente demasiado (Intel CPU)
  services.thermald.enable = true;
  

  # --- GRÁFICOS NVIDIA (Híbrido) ---
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics.enable = true;

  hardware.nvidia = {
    modesetting.enable = true;
    
    # La 1050 Ti usa drivers propietarios estables sin problemas.
    # Open = false es obligatorio para Pascal (serie 10).
    open = false; 
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    
    prime = {
      # Modo Offload: La Nvidia duerme hasta que la llamas.
      # Para juegos: click derecho -> "Ejecutar con tarjeta gráfica dedicada"
      # O por comando: "nvidia-offload %command%"
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      
      # VERIFICA ESTAS ID CON "sudo lshw -c display"
      # Si están mal, no arrancará el entorno gráfico.
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };
  
  environment.systemPackages = with pkgs; [
    powertop 
    libinput-gestures
    nvtopPackages.nvidia # Para ver si la GPU Nvidia está trabajando o durmiendo
    brightnessctl # Útil si las teclas de brillo fallan en Plasma
  ];
  system.stateVersion = "25.11";
}