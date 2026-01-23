{ config, pkgs, lib, ... }:

{
  # --- BOOT Y KERNEL ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # --- RED Y LOCALIZACIÓN ---
  networking.networkmanager.enable = true;
  time.timeZone = "Europe/Madrid";
  
  i18n.defaultLocale = "es_ES.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "es_ES.UTF-8";
    LC_IDENTIFICATION = "es_ES.UTF-8";
    LC_MEASUREMENT = "es_ES.UTF-8";
    LC_MONETARY = "es_ES.UTF-8";
    LC_NAME = "es_ES.UTF-8";
    LC_NUMERIC = "es_ES.UTF-8";
    LC_PAPER = "es_ES.UTF-8";
    LC_TELEPHONE = "es_ES.UTF-8";
    LC_TIME = "es_ES.UTF-8";
  };

  # --- TECLADO ---
  # Configuración para la consola (TTY)
  console.keyMap = lib.mkDefault "es";

  # Configuración para el entorno gráfico (X11/Wayland)
  services.xserver.xkb = {
    layout = lib.mkDefault "es";
    variant = lib.mkDefault "";
  };

  # --- SONIDO (Pipewire) ---
  # Desactivamos PulseAudio estándar para usar Pipewire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # --- SERVICIOS BÁSICOS ---
  services.printing.enable = lib.mkDefault true; # Impresoras
  services.netbird.enable = true;

  # --- CONFIGURACIÓN DE USUARIO ---
  users.users.juan = {
    isNormalUser = true;
    description = "juan";
    shell = pkgs.fish;
    extraGroups = [ "networkmanager" "wheel" "video" "audio" ]; 
  };
  programs.fish.enable = true;

  # --- NIX SETTINGS ---
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = lib.mkDefault "--delete-older-than 7d"; 
  };
  nix.settings.auto-optimise-store = true;

  # --- PAQUETES DEL SISTEMA --- 
  environment.systemPackages = with pkgs; [
    # Herramientas esenciales
    git wget curl vim btop htop fastfetch pciutils lshw usbutils
  ];

  system.stateVersion = "25.11";
}