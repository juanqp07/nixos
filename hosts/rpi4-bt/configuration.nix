{ config, pkgs, lib, inputs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # ============================================================
  # PALCO — Raspberry Pi 4B 8GB como receptor Bluetooth -> jack
  # Uso: sin internet en bolo, solo red para configurar.
  # Imagen SD: nix build .#nixosConfigurations.palco.config.system.build.sdImage
  # ============================================================

  # El kernel downstream pineado de nixos-hardware para Pi 4 no
  # compila ZFS: forzar desactivado para que la SD compile.
  boot.supportedFilesystems.zfs = lib.mkForce false;

  # Boot por U-Boot + extlinux (lo fuerza nixos-hardware, se deja
  # explícito para que no dependa del orden de módulos).
  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.generic-extlinux-compatible.enable = lib.mkDefault true;

  # Reparación automática sin pedir tecla tras un corte de luz.
  boot.kernelParams = [ "fsck.repair=yes" ];

  # Watchdog hardware bcm2835 (máx 15s): reinicia si el sistema se
  # cuelga. Del tirón de cable se encarga el arranque limpio.
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "10s";
    RebootWatchdogSec = "2min";
    ShutdownWatchdogSec = "2min";
  };

  # / con opciones anti-tirón (viven aquí y no en hardware-configuration
  # porque ese fichero se regenera en la Pi y las perdería).
  # noatime = menos escrituras; commit=15 = compromiso writes/ventana;
  # barrier + journal_checksum = journal fiable ante cortes.
  fileSystems."/" = {
    device = lib.mkDefault "/dev/disk/by-label/NIXOS_SD";
    fsType = lib.mkDefault "ext4";
    options = [
      "noatime"
      "commit=15"
      "barrier=1"
      "journal_checksum"
    ];
  };

  # Logs a RAM: cero escrituras a la SD en bolo + arranque más rápido.
  # (Sin red no hay log persistente del crash anterior: en la prueba
  # de sonido, vigilar con `journalctl -f` por SSH.)
  services.journald.settings.Journal = {
    Storage = "volatile";
    RuntimeMaxUse = "64M";
    RuntimeKeepFree = "100M";
  };

  # Sin GC/optimización automáticas en bolo: evitan reescrituras
  # masivas de la store justo antes o durante un evento.
  nix.gc.automatic = lib.mkForce false;
  nix.settings.auto-optimise-store = lib.mkForce false;

  # Firmware Pi en /boot/firmware (config.txt, dtbs, overlays, u-boot).
  # OJO: cada rebuild reescribe config.txt, no editarlo a mano en la Pi.
  fileSystems."/boot/firmware" = {
    device = "/dev/disk/by-label/FIRMWARE";
    fsType = "vfat";
    options = [
      "nofail"
      "noatime"
    ];
  };

  hardware.raspberry-pi.firmware = {
    enable = true;
    uboot.enable = true;
  };

  # Jack 3.5mm integrado (dtparam=audio=on).
  # AVISO honesto: es PWM ~11 bits, SINAD ~56dB, 0.35Vrms.
  # Vale para probar; para PA seria pasar a HAT I2S (ver palco-audio.nix).
  hardware.raspberry-pi."4".audio.enable = true;

  hardware.enableRedistributableFirmware = true;

  zramSwap.enable = true;

  # --- RED ---
  networking.hostName = "palco";
  networking.networkmanager.enable = true;
  # Evita picos de coexistencia WiFi/BT cuando haya red para configurar.
  networking.networkmanager.wifi.powersave = false;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    allowedUDPPorts = [ ];
  };

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = true;
  };

  # Sin internet en bolo: nada de autoUpgrade (fallaría y puede
  # dejar la máquina a medias antes de un evento).
  system.autoUpgrade.enable = lib.mkForce false;

  # --- USUARIO ---
  users.users.juan.extraGroups = [
    "audio"
    "bluetooth"
    "video"
    "render"
    "dialout"
  ];

  # --- PAQUETES BASE DEL HOST (audio/BT en modules/palco-audio.nix) ---
  environment.systemPackages = with pkgs; [
    raspberrypi-eeprom
    libraspberrypi # incluye `vcgencmd`
    tmux
    ncdu
  ];

  system.stateVersion = "25.11";
}
