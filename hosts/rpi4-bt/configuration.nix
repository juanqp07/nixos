{ config, pkgs, lib, inputs, ... }:

{
imports = [
./hardware-configuration.nix
];

# ============================================================

# PALCO — Raspberry Pi 4B 8GB

#

# Móvil -> Bluetooth A2DP -> BlueZ -> PipeWire/DSP -> jack 3.5mm

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

# ------------------------------------------------------------

# INITRD

# ------------------------------------------------------------

# Reducimos el tamaño del initrd para evitar problemas de lectura

# desde la microSD con U-Boot.

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
device = lib.mkDefault "/dev/disk/by-label/NIXOS_SD";
fsType = lib.mkDefault "ext4";


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

services.journald.settings.Journal = {
Storage = "volatile";
RuntimeMaxUse = "64M";
RuntimeKeepFree = "100M";
};

# ------------------------------------------------------------

# NIX

# ------------------------------------------------------------

nix.gc.automatic = lib.mkForce false;
nix.settings.auto-optimise-store = lib.mkForce false;

users.users.juan.initialPassword = "nixos";

services.getty.autologinUser = "juan";

# ------------------------------------------------------------

# RASPBERRY PI

# ------------------------------------------------------------

hardware.raspberry-pi.firmware = {
enable = true;
uboot.enable = true;
};

hardware.enableRedistributableFirmware = true;

# sd-image-aarch64 habilita todo el hardware por defecto.

# Lo desactivamos para no introducir módulos de otras plataformas.

hardware.enableAllHardware = lib.mkForce false;

# ------------------------------------------------------------

# BLUETOOTH INTEGRADO

# ------------------------------------------------------------

# Routing del Bluetooth interno de la Raspberry Pi 4.

hardware.raspberry-pi."4".bluetooth.enable = true;

# Módulos necesarios para el Bluetooth UART Broadcom.

boot.kernelModules = [
"hci_uart"
"hci_bcm"
];

# ------------------------------------------------------------

# AUDIO ANALÓGICO

# ------------------------------------------------------------

# No usamos el overlay audio-on-overlay porque producía:

#

# FDT_ERR_NOTFOUND

#

# El perfil común de Raspberry Pi ya añade dtparam=audio=on.

hardware.raspberry-pi."4".audio.enable = false;

# ------------------------------------------------------------

# ZRAM

# ------------------------------------------------------------

zramSwap.enable = true;

# ------------------------------------------------------------

# RED

# ------------------------------------------------------------

networking.hostName = "palco";

networking.networkmanager.enable = true;

networking.networkmanager.wifi.powersave = false;

networking.firewall = {
enable = true;


allowedTCPPorts = [
  22
];

allowedUDPPorts = [ ];


};

# ------------------------------------------------------------

# NETBIRD

# ------------------------------------------------------------

# No se necesita VPN en este equipo.

services.netbird.enable = lib.mkForce false;

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

# USUARIO

# ------------------------------------------------------------

users.users.juan.extraGroups = [
"audio"
"bluetooth"
"video"
"render"
"dialout"
];

# ------------------------------------------------------------

# PAQUETES BASE

# ------------------------------------------------------------

environment.systemPackages = with pkgs; [
raspberrypi-eeprom
libraspberrypi
tmux
ncdu
];

# ------------------------------------------------------------

# ESTADO

# ------------------------------------------------------------

system.stateVersion = "25.11";
}
