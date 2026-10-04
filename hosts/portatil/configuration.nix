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

  boot.kernelPackages = pkgs.linuxPackages_latest;

  # mitigations=off: +5-15% en juegos en CPU Intel. Solo máquina personal,
  # nunca en servidores expuestos. Asumes riesgo Spectre/Meltdown.
  boot.kernelParams = [ "mitigations=off" ];

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

    # NVIDIA Production Branch
    branch = "latest";

    powerManagement = {
      enable = true;
      finegrained = false;
      kernelSuspendNotifier = true;
    };

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

    # Portátil
    brightnessctl
  ];
}