# Placeholder temporal para Raspberry Pi 4B.
# La imagen SD (sd-image-aarch64) ya define sus propios fileSystems.
# Tras el primer arranque con la SD, generar el real con:
#   sudo nixos-generate-config --show-hardware-config > ~/nixos/hosts/rpi4-bt/hardware-configuration.nix
# y hacer `git add` + rebuild con `nixos-rebuild switch --flake .#palco`.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ ];

  boot.initrd.availableKernelModules = [
    "pcie-brcmstb"
    "reset-raspberrypi"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # sd-image-aarch64.nix define / y /boot/firmware reales.
  # Se dejan marcadores nofail para que `nixos-rebuild build` evalúe en x86
  # con binfmt antes de tener la Pi delante.
  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
    options = [ "nofail" ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
