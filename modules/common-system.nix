{ config, pkgs, ... }:

{
  # --- BOOT Y KERNEL ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

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
    # Usamos mkDefault para que sea un "si nadie dice lo contrario, usa 7d"
    options = lib.mkDefault "--delete-older-than 7d"; 
  };
  nix.settings.auto-optimise-store = true;

  # --- PAQUETES DEL SISTEMA --- 
  environment.systemPackages = with pkgs; [
    git wget curl btop htop fastfetch vim pciutils lshw
  ];

  services.netbird.enable = true;
  
  system.stateVersion = "25.11";
}
