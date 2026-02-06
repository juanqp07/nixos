{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "portatil";

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
    open = false; # Obligatorio en serie 10 (Pascal)
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    # Gestión de energía de la GPU dedicada
    powerManagement.enable = true;
    # Nota: finegrained solo funciona bien de la serie 16xx/20xx en adelante.
    # En la 1050 Ti lo dejamos desactivado para evitar inestabilidad.
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
    vdpauinfo  # Para verificar la aceleración de video
    libva-utils # Comando 'vainfo' para ver si Intel acelera video
  ];

  # Gestos táctiles si usas touchpad
  services.libinput.enable = true;
  # services.libinput-gestures.enable = true; # Requiere configuración de usuario

  system.stateVersion = "25.11";
}
do lshw -c display"
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
