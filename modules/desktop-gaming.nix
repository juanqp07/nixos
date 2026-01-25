{ config, pkgs, inputs, ... }:

{
  # --- KERNEL ---
  boot.kernelPackages = pkgs.linuxPackages_zen;

  boot.kernel.sysctl = {
    "net.core.default_qdisc" = "cake";
    "net.ipv4.tcp_congestion_control" = "bbr";
  };
  services.cloudflare-warp.enable = true;
  # --- ENTORNO GRÁFICO (Plasma 6) ---
  services.xserver.enable = true;
  services.xserver.xkb = { layout = "es"; variant = ""; };
  
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.desktopManager.plasma6.enable = true;

  # --- SONIDO (Solo necesario en Desktop) ---
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };
  
  # --- IMPRESIÓN ---
  services.printing.enable = true;

  # --- PERMISOS DE USUARIO ---
  users.users.juan.extraGroups = [ "video" "audio" "lp" "scanner" ];

  # --- GAMING ---
  programs.steam.enable = true;
  programs.gamemode.enable = true;

  # --- FUENTES ---
  fonts.packages = with pkgs; [
    noto-fonts noto-fonts-cjk-sans noto-fonts-color-emoji liberation_ttf
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
  ];

  # --- PAQUETES DE ESCRITORIO ---
  environment.systemPackages = with pkgs; [
    floorp-bin vesktop 
    onlyoffice-desktopeditors kdePackages.kate vscode
    vlc mpv yt-dlp ffmpeg
    distrobox
    kdePackages.xdg-desktop-portal-kde wl-clipboard
    protonplus supersonic-wayland
    antigravity python315
  ];

  # --- FLATPAK ---
  services.flatpak = {
    enable = true;
    remotes = [{
      name = "flathub";
      location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
    }];
    packages = [ "com.stremio.Stremio" "dev.fredol.open-tv" ];
    update.onActivation = true;
    uninstallUnmanaged = true; 
  };
}