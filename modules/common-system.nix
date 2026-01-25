{ config, pkgs, lib, ... }:

{
  # --- BOOT ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # --- RED Y LOCALIZACIÓN ---
  networking.networkmanager.enable = true;
  time.timeZone = "Europe/Madrid";
  
  i18n.defaultLocale = "es_ES.UTF-8";
  # (Omití las extraLocaleSettings para ahorrar espacio, pero déjalas si quieres)

  console.keyMap = lib.mkDefault "es";

  # --- SERVICIOS DE RED ---
  services.netbird.enable = true;

  # --- CONFIGURACIÓN DE USUARIO ---
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
  nix.settings.auto-optimise-store = true;

  # --- PAQUETES ESENCIALES (SOLO CLI) --- 
  environment.systemPackages = with pkgs; [
    git wget curl vim btop htop fastfetch pciutils lshw usbutils dnsutils
  ];

  system.stateVersion = "25.11";
}