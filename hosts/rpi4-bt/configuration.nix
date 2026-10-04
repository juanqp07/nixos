{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # ============================================================
  # PALCO — Raspberry Pi 4B 8GB
  #
  # Móvil
  #   -> Bluetooth A2DP
  #   -> BlueZ
  #   -> PipeWire / WirePlumber
  #   -> DSP
  #   -> ALSA
  #   -> Jack 3.5 mm
  # ============================================================

  # ------------------------------------------------------------
  # KERNEL / BOOT
  # ------------------------------------------------------------

  boot.supportedFilesystems.zfs = lib.mkForce false;

  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.generic-extlinux-compatible.enable = lib.mkDefault true;

  boot.kernelParams = [
    "fsck.repair=yes"
  ];

  # Reduce el tamaño del initrd en la microSD.
  boot.initrd.compressor = "xz";

  boot.initrd.availableKernelModules = [
    "pcie-brcmstb"
    "reset-raspberrypi"
  ];

  # ------------------------------------------------------------
  # WATCHDOG
  # ------------------------------------------------------------

  systemd.settings.Manager = {
    RuntimeWatchdogSec = "10s";
    RebootWatchdogSec = "2min";
    ShutdownWatchdogSec = "2min";
  };

  # ------------------------------------------------------------
  # SISTEMA DE FICHEROS
  # ------------------------------------------------------------

  fileSystems."/" = {
    device = lib.mkForce "/dev/disk/by-label/NIXOS_SD";
    fsType = lib.mkForce "ext4";

    options = [
      "noatime"
      "commit=15"
      "barrier=1"
      "journal_checksum"
    ];
  };

  fileSystems."/boot/firmware" = {
    device = "/dev/disk/by-label/FIRMWARE";
    fsType = "vfat";

    options = [
      "nofail"
      "noatime"
    ];
  };

  # ------------------------------------------------------------
  # LOGS
  # ------------------------------------------------------------

  # Logs en RAM para reducir escrituras sobre la microSD.
  services.journald.settings.Journal = {
    Storage = "volatile";
    RuntimeMaxUse = "64M";
    RuntimeKeepFree = "100M";
  };

  # ------------------------------------------------------------
  # NIX
  # ------------------------------------------------------------

  # Esta máquina es un appliance; las generaciones se controlan
  # desde la máquina que construye/despliega la imagen.
  nix.gc.automatic = lib.mkForce false;
  nix.settings.auto-optimise-store = lib.mkForce false;

  # ------------------------------------------------------------
  # USUARIO
  # ------------------------------------------------------------

  users.users.juan.initialPassword = "nixos";

  # Útil para administración directa por consola.
  # QUITAR cuando tengas SSH por clave totalmente configurado.
  services.getty.autologinUser = "juan";

  # Necesario para que los servicios de usuario de PipeWire /
  # WirePlumber funcionen aunque no haya una sesión interactiva.
  users.users.juan.linger = true;

  users.users.juan.extraGroups = [
    "audio"
    "bluetooth"
    "video"
    "render"
    "dialout"
  ];

  # ------------------------------------------------------------
  # RASPBERRY PI
  # ------------------------------------------------------------

  hardware.raspberry-pi.firmware = {
    enable = true;
    uboot.enable = true;
  };

  hardware.enableRedistributableFirmware = true;

  # Evita que sd-image-aarch64 introduzca hardware innecesario.
  hardware.enableAllHardware = lib.mkForce false;

  # Routing del Bluetooth integrado de la Pi 4.
  hardware.raspberry-pi."4".bluetooth.enable = true;

  boot.kernelModules = [
    "hci_uart"
    "hci_bcm"
  ];

  # El audio del perfil Raspberry Pi ya proporciona el overlay
  # necesario. Evitamos audio.enable porque nuestra combinación
  # actual puede generar audio-on-overlay y FDT_ERR_NOTFOUND.
  hardware.raspberry-pi."4".audio.enable = false;

  hardware.raspberry-pi.configtxt.settings.all = {
    audio_pwm_mode = 2;
  };

  # ------------------------------------------------------------
  # MEMORIA
  # ------------------------------------------------------------

  zramSwap.enable = true;

  # ------------------------------------------------------------
  # RED
  # ------------------------------------------------------------

  networking.hostName = "palco";

  networking.networkmanager.enable = true;

  # Evita que Wi-Fi entre en powersave.
  networking.networkmanager.wifi.powersave = false;

  networking.firewall = {
    enable = true;

    allowedTCPPorts = [
      22
    ];

    allowedUDPPorts = [ ];
  };

  # ------------------------------------------------------------
  # NETBIRD: no se usa en palco (appliance Bluetooth, sin red privada).
  # ------------------------------------------------------------

  # ------------------------------------------------------------
  # SSH
  # ------------------------------------------------------------

  services.openssh = {
    enable = true;

    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  # ------------------------------------------------------------
  # ACTUALIZACIONES
  # ------------------------------------------------------------

  system.autoUpgrade.enable = lib.mkForce false;

  # ------------------------------------------------------------
  # HERRAMIENTAS BASE
  # ------------------------------------------------------------

  environment.systemPackages = with pkgs; [
    raspberrypi-eeprom
    libraspberrypi

    tmux
    ncdu
  ];

  # ------------------------------------------------------------
  # ESTADO DEL SISTEMA
  # ------------------------------------------------------------

  system.stateVersion = "25.11";
}