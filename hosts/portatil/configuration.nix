{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "elytra";

  # Elytra es un portátil interactivo de 16 GiB: limitar builds concurrentes
  # reduce los picos de memoria y deja margen al escritorio durante nix-maintain.
  # Nix solicita hasta 2 cores por derivación y ejecuta como máximo 2 derivaciones:
  # 4 cores de build solicitados en total (no es una cuota CPU rígida).
  nix.settings = {
    max-jobs = 2;
    cores = 2;
  };

  # El daemon y sus procesos de build heredan SCHED_IDLE. El kernel solo les
  # da CPU cuando no compiten con tareas interactivas de prioridad normal.
  nix.daemonCPUSchedPolicy = "idle";

  # Gestión global de memoria para Elytra.
  # common-system.nix conserva los valores generales de los demás hosts (5 %).
  # En este portátil, empezar en 10 % permite que earlyoom envíe SIGTERM con
  # más margen; los umbrales SIGKILL implícitos quedan en el 5 %.
  services.earlyoom = {
    freeMemThreshold = 10;
    freeSwapThreshold = 10;
  };

  # Elytra conserva scx_cosmos en modo Auto (sin argumentos de perfil Gaming).
  # Titan hereda el modo Gaming (-s 700) del módulo compartido.
  services.scx-loader.config.default_mode = "Auto";

  # Perfiles energéticos AC/batería declarados en PowerDevil (Plasma 6).
  home-manager.users.juan.imports = [ ../../home/juan/laptop-power.nix ];

  # Acceso alternativo que abre Horizon con el SDK disponible para compilar mods nativos.
  # El acceso normal de Flatpak sigue arrancando Horizon sin modo de desarrollo.
  home-manager.users.juan.xdg.desktopEntries.horizon-native-mods = {
    name = "Horizon (compilar mods nativos)";
    comment = "Abre Horizon con Freedesktop SDK 26.08 para compilar mods Rust nativos.";
    exec = "${pkgs.flatpak}/bin/flatpak run --devel dev.playhorizon.Horizon";
    icon = "dev.playhorizon.Horizon";
    terminal = false;
    categories = [ "Game" ];
  };

  # Mantener el stateVersion de la instalación.
  system.stateVersion = "25.11";

  # ============================================================
  # APPIMAGE / GEAR LEVER
  # Bibliotecas para Orbiscreen, Nuvio y el WebKitGTK de Nori
  # ============================================================

  programs.appimage.package = pkgs.appimage-run.override {
    extraPkgs =
      appimagePkgs: with appimagePkgs; [
        libunwind
        elfutils
        libffi
        libgpg-error
        pcre2
        mpv-unwrapped
        webkitgtk_4_1
      ];
  };

  # ============================================================
  # HARDWARE / FIRMWARE
  # ============================================================

  # hardware-configuration.nix habilita el microcódigo mediante
  # config.hardware.enableRedistributableFirmware (activado aquí).
  hardware.enableRedistributableFirmware = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Se conservan las mitigaciones de vulnerabilidades de CPU del kernel.
  # Desactivarlas no garantiza más FPS y reduce la protección frente a ciertos ataques.

  # El módulo NVIDIA del pin añade modeset/fbdev y la preservación de VRAM
  # a modprobe.d cuando PRIME offload, modesetting y powerManagement están activos.

  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # ============================================================
  # NVIDIA RTX 5050 + INTEL iGPU
  # ============================================================

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;

    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
    ];
  };

  hardware.nvidia = {
    modesetting.enable = true;

    # Blackwell → open kernel modules
    open = true;

    nvidiaSettings = true;

    # Para gaming/hardware reciente: selector latest (elige la más nueva entre
    # production y new_feature en nixpkgs; no significa exclusivamente production).
    branch = "latest";

    powerManagement = {
      enable = true;
      finegrained = true;
      kernelSuspendNotifier = true;
    };

    # El firmware/controlador confirma soporte de Notebook Dynamic Boost.
    # Redistribuye presupuesto CPU/GPU bajo carga; no implica ahorro en reposo.
    dynamicBoost.enable = true;

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
  # CPU / SCHED-EXT, GAMEMODE, MEMORIA, SYSCTL, BLUETOOTH
  # Heredados de modules/desktop-gaming.nix (paridad elytra+titan).
  # ============================================================

  # ============================================================
  # THERMALS
  # ============================================================

  services.thermald.enable = true;

  # ============================================================
  # WAYLAND / ELECTRON
  # ============================================================

  # NIXOS_OZONE_WL ya viene de modules/desktop-gaming.nix.
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
  };

  # ============================================================
  # NETWORKMANAGER
  # ============================================================

  networking.networkmanager = {
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

  services.pipewire.wireplumber.extraConfig."11-bluetooth-policy" = {
    "wireplumber.settings" = {
      "bluetooth.autoswitch-to-headset-profile" = false;
    };
  };

  # ============================================================
  # BLUETOOTH: heredado de modules/desktop-gaming.nix
  # ============================================================

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

  # fstrim está habilitado en desktop-gaming.nix.

  # Dev remoto (VSCode Remote-SSH al portátil).
  # Al ser un portátil que se conecta a Wi-Fi ajenas, SSH y Sunshine no se abren
  # en todas las interfaces: solo por NetBird (wt0). Para volver a abrirlos en la
  # LAN, pon openFirewall = true y borra las reglas de wt0 de abajo.
  services.openssh = {
    enable = true;
    openFirewall = false;
  };

  # Sunshine para Moonlight: instalado, pero sin arranque automático.
  # En Wayland, CAP_SYS_ADMIN permite la captura DRM/KMS.
  services.sunshine = {
    enable = true;
    autoStart = false;
    capSysAdmin = true;
    openFirewall = false;
  };

  # Puertos de SSH y de Sunshine (puerto base 47989) solo por NetBird.
  networking.firewall.interfaces.wt0 = {
    allowedTCPPorts = [
      22
      47984
      47989
      47990
      48010
    ];
    allowedUDPPorts = [
      47998
      47999
      48000
      48002
      48010
    ];
  };

  # Evita que SDDM muestre automáticamente el teclado virtual (regresión de Plasma 6.8).
  services.displayManager.sddm.settings.General.InputMethod = lib.mkForce "";

  # ============================================================
  # HORIZON + COMPILACIÓN DE MODS NATIVOS
  # ============================================================

  # Horizon se distribuye desde FlatPark; Flathub sigue proporcionando su SDK.
  services.flatpak.remotes = [
    {
      name = "flatpark";
      location = "https://dl.flatpark.org/flatpark.flatpakrepo";
    }
  ];

  services.flatpak.packages = [
    {
      appId = "dev.playhorizon.Horizon";
      origin = "flatpark";
    }
  ];

  # La compilación de mods nativos se ejecuta dentro del sandbox de Flatpak.
  # El Freedesktop SDK contiene el compilador C, pkg-config y los headers de ALSA/libudev.
  # No se instalan esas dependencias globalmente en NixOS.
  systemd.services.horizon-native-mod-sdk = {
    description = "Install Freedesktop SDK 26.08 for Horizon native mods";
    wantedBy = [ "default.target" ];
    after = [ "flatpak-managed-install.service" ];
    path = [ pkgs.flatpak ];
    serviceConfig.Type = "oneshot";
    script = ''
      flatpak --system --noninteractive install --or-update flathub org.freedesktop.Sdk//26.08
    '';
  };

  # Mantiene actualizado el SDK, que no forma parte de la lista de aplicaciones
  # administradas por nix-flatpak.
  systemd.timers.horizon-native-mod-sdk = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };

  # ============================================================
  # UTILIDADES
  # ============================================================

  environment.systemPackages =
    with pkgs;
    [
      # Gaming extra específico portátil (base común en desktop-gaming.nix)
      nvtopPackages.nvidia
      vulkan-tools

      # Intel / vídeo
      intel-gpu-tools
      libva-utils
      vdpauinfo

      # Gaming
      # mangohud/gamescope/protonup-qt/gamemode en desktop-gaming.nix

      # Sistema
      powertop
      smartmontools
      cardwire

      # Portátil
      brightnessctl
    ]
    ++ [
      # Aplicación declarativa, aislada con sus dependencias de WebKitGTK 4.1.
      (pkgs.callPackage ../../packages/nori.nix { })
      # Cliente de terminal de Nori.
      (pkgs.callPackage ../../packages/nori-cli.nix { })
    ];
}
