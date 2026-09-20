{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # ============================================================
  # IDENTIDAD / HARDWARE BASE
  # ============================================================

  networking.hostName = "elytra";

  # Mantener el stateVersion original de la instalación.
  # No se cambia simplemente por usar nixos-unstable.
  system.stateVersion = "25.11";

  # Firmware necesario para Intel/NVIDIA y microcódigo.
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;

  # NO fijamos linuxPackages_latest.
  # Dejar que NixOS seleccione el kernel por defecto del canal
  # mantiene mejor coordinados kernel + módulos externos + NVIDIA.
  #
  # boot.kernelPackages = pkgs.linuxPackages_latest;
  #
  # Si más adelante queremos probar otro kernel, lo hacemos
  # deliberadamente.

  # ============================================================
  # NVIDIA RTX 5050 + INTEL iGPU
  # ============================================================

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics = {
    enable = true;

    # Necesario para Steam/Wine/Proton y aplicaciones 32-bit.
    enable32Bit = true;

    # Intel Raptor Lake:
    # - intel-media-driver -> VA-API moderno / iHD
    # - vpl-gpu-rt        -> Intel VPL / QSV
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
    ];

    # 32-bit Intel VA-API para aplicaciones antiguas/compatibilidad.
    extraPackages32 = with pkgs.driversi686Linux; [
      intel-media-driver
    ];
  };

  hardware.nvidia = {
    # KMS necesario/recomendado para Wayland.
    modesetting.enable = true;

    # RTX 5050 / Blackwell soporta los módulos kernel abiertos.
    open = true;

    # NVIDIA Settings.
    nvidiaSettings = true;

    # Preferimos la rama Production antes que perseguir "latest".
    package = config.boot.kernelPackages.nvidiaPackages.production;

    # Gestión de energía.
    powerManagement = {
      enable = true;

      # En un portátil gaming híbrido prefiero no usar finegrained
      # mientras probamos rendimiento/estabilidad.
      finegrained = false;
    };

    # MUY importante en tu LOQ:
    # permite que nvidia-powerd gestione Dynamic Boost cuando el
    # firmware/hardware lo soporte.
    dynamicBoost.enable = true;

    # Intel iGPU -> pantalla / escritorio
    # NVIDIA -> juegos mediante PRIME Offload.
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };

      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  # ============================================================
  # WAYLAND / KDE / ELECTRON
  # ============================================================

  # Plasma 6 utiliza Wayland por defecto.
  # Esta variable hace que Electron/Chromium/VS Code prefieran
  # Wayland nativo.
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  # ============================================================
  # CPU / SCHEDULER
  # ============================================================

  # sched-ext.
  #
  # Cosmos es un scheduler ligero orientado a localidad CPU/cache.
  # Con estos flags usamos su perfil orientado a consistencia de
  # gaming, inspirado en el modo Gaming de CachyOS.
  #
  # Si en algún momento queremos comparar rendimiento puro,
  # podemos cambiarlo fácilmente a scx_lavd.
  services.scx = {
    enable = true;
    scheduler = "scx_cosmos";
    extraArgs = [
      "-s"
      "700"
      "-S"
    ];
  };

  # GameMode permite que los juegos soliciten un perfil de
  # rendimiento temporal.
  programs.gamemode = {
    enable = true;
    enableRenice = true;
  };

  # ============================================================
  # MEMORIA
  # ============================================================

  # Tu portátil tiene 16 GB y usas VS Code + OpenCode + navegador +
  # herramientas de desarrollo.
  #
  # ZRAM proporciona swap comprimida en RAM y evita depender de
  # una pequeña partición de swap en disco.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  # Evita congelaciones largas cuando algún proceso se dispara en
  # consumo de memoria.
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 5;
  };

  # ============================================================
  # KERNEL / SISTEMA
  # ============================================================

  boot.kernel.sysctl = {
    # Útil para VS Code, Node, watchers, proyectos grandes, etc.
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 1024;
  };

  # Thermald para gestión térmica en Intel.
  services.thermald.enable = true;

  # ============================================================
  # RED
  # ============================================================

  networking.networkmanager = {
    enable = true;

    # Evita que la tarjeta Wi-Fi entre en ahorro de energía.
    wifi.powersave = false;

    # Conserva la MAC del dispositivo.
    wifi.macAddress = "preserve";
  };

  # ============================================================
  # REALTEK RTL8852BE
  # ============================================================
  #
  # SOLO mantener esto si "lspci" confirma que tu Wi-Fi es RTL8852BE.
  #
  # Desactiva mecanismos de ahorro que pueden introducir problemas
  # de estabilidad/latencia con determinados módulos rtw89.

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
  # OLLAMA / CUDA
  # ============================================================

  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
  };

  # ============================================================
  # SERVICIOS GENERALES
  # ============================================================

  services.libinput.enable = true;

  # TRIM periódico para SSD.
  services.fstrim.enable = true;

  # ============================================================
  # HERRAMIENTAS DE MONITORIZACIÓN / GAMING / DESARROLLO
  # ============================================================

  environment.systemPackages = with pkgs; [
    # GPU / Vulkan / vídeo
    vulkan-tools
    libva-utils
    vdpauinfo
    intel-gpu-tools
    nvtopPackages.nvidia

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

    # Utilidades GPU/hardware
    pciutils
    usbutils

    # Control de brillo
    brightnessctl
  ];
}
