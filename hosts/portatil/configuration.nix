{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "elytra";

  # Mantener el stateVersion de la instalación.
  system.stateVersion = "25.11";

  # ============================================================
  # HARDWARE / FIRMWARE
  # ============================================================

  hardware.enableRedistributableFirmware = true;

  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;

  # ============================================================
  # NVIDIA RTX 5050 + INTEL iGPU
  # ============================================================

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;

    extraPackages = with pkgs; [
      # Intel Raptor Lake
      intel-media-driver
      vpl-gpu-rt
    ];
  };

  hardware.nvidia = {
    modesetting.enable = true;

    # RTX 5050 / Blackwell
    open = true;

    nvidiaSettings = true;

    # Rama Production.
    # Mejor que perseguir siempre la versión "latest".
    branch = "production";

    powerManagement = {
      enable = true;

      # Lo dejamos desactivado para priorizar estabilidad
      # en PRIME Offload.
      finegrained = false;

      # Driver >= 595 + open modules.
      kernelSuspendNotifier = true;
    };

    # Dynamic Boost / nvidia-powerd.
    dynamicBoost.enable = true;

    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };

      # Confirmados mediante lspci:
      # 00:02.0 Intel
      # 01:00.0 NVIDIA
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  # Si powerManagement.enable escribe VRAM temporal durante
  # suspensión, usar /var/tmp en vez de /tmp.
  boot.kernelParams = [
    "nvidia.NVreg_TemporaryFilePath=/var/tmp"
  ];

  # ============================================================
  # CPU / SCHED-EXT
  # ============================================================

  services.scx = {
    enable = true;
    scheduler = "scx_cosmos";

    # Modo Gaming de Cosmos.
    # CachyOS usa exactamente estos argumentos.
    extraArgs = [
      "-s"
      "700"
      "-S"
    ];
  };

  # ============================================================
  # GAMEMODE
  # ============================================================

  programs.gamemode = {
    enable = true;
    enableRenice = true;

    settings = {
      general = {
        # Llevar la CPU al governor performance mientras juegas.
        desiredgov = "performance";

        # Volver al governor normal al terminar.
        defaultgov = "powersave";

        # Prioridad ligeramente mayor para el juego.
        renice = 10;

        # Evitar que se active el salvapantallas durante el juego.
        inhibit_screensaver = 1;

        # Comprobar clientes con frecuencia razonable.
        reaper_freq = 5;
      };
    };
  };

  # ============================================================
  # MEMORIA
  # ============================================================

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 5;
  };

  # ============================================================
  # KERNEL / DESARROLLO / GAMING
  # ============================================================

  boot.kernel.sysctl = {
    "vm.max_map_count" = lib.mkForce 2147483642;
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 1024;
  };

  # ============================================================
  # THERMALS
  # ============================================================

  services.thermald.enable = true;

  # ============================================================
  # WAYLAND / ELECTRON
  # ============================================================

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  # ============================================================
  # NETWORKMANAGER
  # ============================================================

  networking.networkmanager = {
    enable = true;

    wifi.powersave = false;
    wifi.macAddress = "preserve";
  };

  # ============================================================
  # REALTEK RTL8852BE
  # ============================================================

  boot.extraModprobeConfig = ''
    options rtw89_pci disable_aspm_l1=1 disable_aspm_l1ss=1
    options rtw89_core disable_ps_mode=1
  '';

  # ============================================================
  # BLUETOOTH
  # ============================================================

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;

    settings = {
      General = {
        Experimental = true;
        FastConnectable = true;
      };

      Policy = {
        AutoEnable = true;
      };
    };
  };

  services.blueman.enable = true;

  # ============================================================
  # OLLAMA / NVIDIA CUDA
  # ============================================================

  #services.ollama = {
   # enable = true;
    #package = pkgs.ollama-cuda;
  #};

  # ============================================================
  # SISTEMA
  # ============================================================

  services.libinput.enable = true;

  services.fstrim.enable = true;

  # ============================================================
  # UTILIDADES
  # ============================================================

  environment.systemPackages = with pkgs; [
    # NVIDIA / GPU
    nvtopPackages.nvidia
    vulkan-tools

    # Intel / vídeo
    intel-gpu-tools
    libva-utils
    vdpauinfo

    # Gaming
    mangohud
    gamescope
    protonup-qt
    gamemode

    # Sistema
    btop
    powertop
    lm_sensors
    smartmontools
    pciutils
    usbutils

    # Portátil
    brightnessctl
  ];
}