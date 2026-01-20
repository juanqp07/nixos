{ config, pkgs, ... }:

{
  # --- BOOT Y KERNEL ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # --- MANTENIMIENTO AUTOMÁTICO ---
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # Optimiza el espacio automáticamente en cada reconstrucción
  nix.settings.auto-optimise-store = true;

  # Actualización automática del sistema (Opcional)
  # system.autoUpgrade = {
  #   enable = true;
  #   flake = inputs.self.outPath;
  #   flags = [
  #     "--update-input" "nixpkgs"
  #     "-L" # print build logs
  #   ];
  #   dates = "04:00";
  #   randomizedDelaySec = "45min";
  # };

  # --- RED Y LOCALE ---
  networking.networkmanager.enable = true;
  time.timeZone = "Europe/Madrid";
  i18n.defaultLocale = "es_ES.UTF-8";
  
  # --- USUARIO ---
  users.users.juan = {
    isNormalUser = true;
    description = "juan";
    shell = pkgs.fish;
    extraGroups = [ "networkmanager" "wheel" ]; 
  };
  programs.fish.enable = true;

  # --- NIX SETTINGS ---
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  
  environment.systemPackages = with pkgs; [
    git wget curl btop htop fastfetch vim pciutils lshw
  ];
  
  system.stateVersion = "25.11";
}
