{ config, pkgs, ... }:

{
  # --- SISTEMA Y NIX ---
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  # --- KERNEL ---
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # --- RED ---
  networking.networkmanager.enable = true;
  networking.enableIPv6 = false; 
  
  boot.kernel.sysctl = {
    "net.core.default_qdisc" = "cake";
    "net.ipv4.tcp_congestion_control" = "bbr";
  };

  # --- ENTORNO GRÁFICO (Plasma 6) ---
  services.xserver.enable = true; # Necesario para compatibilidad XWayland
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true; # Login en Wayland
  services.desktopManager.plasma6.enable = true;
  
  services.xserver.xkb = { layout = "es"; variant = ""; };
  console.keyMap = "es";

  # --- SONIDO (Pipewire) ---
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # --- GAMING ---
  programs.steam.enable = true;
  programs.gamemode.enable = true;

  # --- FUENTES (Vital para OnlyOffice/VSCode) ---
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-emoji
    liberation_ttf
    fira-code
    fira-code-symbols
    (nerdfonts.override { fonts = [ "FiraCode" "DroidSansMono" ]; })
  ];

  # --- PAQUETES ---
  environment.systemPackages = with pkgs; [
    # Navegación y Comunicación
    firefox vesktop # Vesktop es mejor que Discord oficial en Wayland
    
    # Productividad
    onlyoffice-desktopeditors kdePackages.kate vscode
    
    # Multimedia
    vlc mpv yt-dlp ffmpeg
    
    # Desarrollo y Herramientas
    git gcc cmake gnumake podman-compose
    distrobox rustdesk-flutter
    
    # Wayland Utilities
    kdePackages.xdg-desktop-portal-kde
    wl-clipboard # Para copiar/pegar en terminal Wayland
  ];

  # --- VIRTUALIZACIÓN ---
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };
  virtualisation.virtualbox.host.enable = true;
  users.extraGroups.vboxusers.members = [ "juan" ];

  # --- USUARIO ---
  users.users.juan = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "podman" ];
  };
}