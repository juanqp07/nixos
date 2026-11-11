{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "elytra";

  # El portátil tiene 16 GiB; limita la memoria y el impacto interactivo durante compilaciones.
  nix.settings = {
    max-jobs = 4;
    cores = 2;
  };

  # Gestión global de memoria para Elytra.
  # common-system.nix conserva los valores generales de los demás hosts (5 %).
  # En este portátil, empezar en 10 % permite que earlyoom envíe SIGTERM con
  # más margen; los umbrales SIGKILL implícitos quedan en el 5 %.
  services.earlyoom = {
    freeMemThreshold = lib.mkForce 10;
    freeSwapThreshold = lib.mkForce 10;
  };

  # Elytra conserva scx_cosmos en modo Auto (sin argumentos de perfil Gaming).
  # Titan hereda el modo Gaming (-s 700) del módulo compartido.
  services.scx-loader.config.default_mode = lib.mkForce "Auto";

  # Mantener el stateVersion de la instalación.
  system.stateVersion = "25.11";

  # ============================================================
  # APPIMAGE / GEAR LEVER
  # Bibliotecas para Orbiscreen, Nuvio y el WebKitGTK de Nori
  # ============================================================

  programs.appimage.package = pkgs.appimage-run.override {
    extraPkgs = appimagePkgs: with appimagePkgs; [
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

  hardware.enableRedistributableFirmware = true;

  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Se conservan las mitigaciones de vulnerabilidades de CPU del kernel.
  # Desactivarlas no garantiza más FPS y reduce la protección frente a ciertos ataques.

  boot.kernelParams = [
    "nvidia-drm.fbdev=1"
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
  ];

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

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    LIBVA_DRIVER_NAME = "iHD";
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

  services.fstrim.enable = true;

  # Dev remoto (VSCode Remote-SSH al portátil)
  services.openssh.enable = true;

  # Sunshine para Moonlight: instalado, pero sin arranque automático.
  # En Wayland, CAP_SYS_ADMIN permite la captura DRM/KMS.
  services.sunshine = {
    enable = true;
    autoStart = false;
    capSysAdmin = true;
    openFirewall = true;
  };

  # Evita que SDDM muestre automáticamente el teclado virtual (regresión de Plasma 6.8).
  services.displayManager.sddm.settings.General.InputMethod = lib.mkForce "";

  # Workaround para la inicialización gráfica de Plasma 6.8 con NVIDIA híbrida:
  # solo cambia el greeter de SDDM a X11; la sesión de Plasma puede seguir en Wayland.
  services.displayManager.sddm.wayland.enable = false;

  # Weylus (control remoto por tablet): web 1701/tcp + websocket 9001/tcp.
  # Sin esto el firewall por defecto de NixOS bloquea el acceso desde fuera.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 1701 9001 ];
  };

  # ============================================================
  # CARDWIRE
  # Workaround temporal para la revisión nixpkgs f4a03c0.
  # Nixpkgs corrigió CardWire 0.12.3 usando SQLite del sistema:
  # https://github.com/NixOS/nixpkgs/pull/585159
  # Aplicado solo a Elytra, que es donde se instala CardWire.
  # Evita duplicar SQLite cuando la corrección llegue al pin de nixpkgs.
  # ============================================================

  nixpkgs.overlays = [
    (final: prev: {
      cardwire = prev.cardwire.overrideAttrs (old:
        let
          buildInputs = old.buildInputs or [ ];
        in
        {
          buildInputs = buildInputs ++ lib.optional (!(lib.elem final.sqlite buildInputs)) final.sqlite;
        }
      );
    })
  ];

  # ============================================================
  # UTILIDADES
  # ============================================================

  environment.systemPackages = with pkgs; [
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
    btop
    powertop
    lm_sensors
    smartmontools
    pciutils
    usbutils
    cardwire

    # Portátil
    brightnessctl
  ] ++ [
    # Aplicación declarativa, aislada con sus dependencias de WebKitGTK 4.1.
    (pkgs.callPackage ../../packages/nori.nix { })
    # Cliente de terminal de Nori.
    (pkgs.callPackage ../../packages/nori-cli.nix { })
  ];
}
