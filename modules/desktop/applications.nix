{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:

{
  # FUENTES
  # ============================================================

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    liberation_ttf
    fira-code
    fira-code-symbols
    mplus-outline-fonts.githubRelease
    dina-font
    proggyfonts
  ];

  # ============================================================
  # PAQUETES DEL ESCRITORIO
  # ============================================================

  environment.systemPackages = with pkgs; [
    # CLI y diagnóstico propios de los escritorios.
    fastfetch
    nix-output-monitor

    # Comunicación, navegación y acceso remoto.
    openvpn
    wireguard-tools
    rustdesk-flutter
    telegram-desktop
    vesktop
    discord
    pi-coding-agent

    # Ofimática e idiomas.
    hunspell
    hunspellDicts.es_ES
    marktext

    # KDE y utilidades de escritorio.
    kdePackages.kate
    gedit
    kdePackages.kcalc
    kdePackages.filelight
    kdePackages.partitionmanager
    kdePackages.xdg-desktop-portal-kde
    wl-clipboard
    libnotify

    # Audio, vídeo y multimedia. pw-jack está disponible para clientes JACK.
    pipewire.jack
    vlc
    mpv
    yt-dlp
    ffmpeg
    streamlink
    gopeed
    supersonic
    feishin
    musicpresence
    impression

    # Gaming.
    prismlauncher
    heroic
    hydralauncher
    eden
    mangohud
    gamescope
    protonplus
    protonup-qt
    protontricks

    # Desarrollo: las herramientas base de Python y Rust se instalan
    # desde modules/common/development.nix; Bun, Go y Java siguen en devShells.
    # Node se instala en modules/common/development.nix (runtime del plugin
    # opencode-router).
    android-studio
    vscode
    antigravity-ide
    jetbrains.idea
    opencode
    opencode-desktop
    lmstudio
    android-tools

    # Contenedores y gestión de AppImage. appimage-run lo instala
    # programs.appimage (con las extraPkgs de cada host).
    distrobox
    lazydocker
    gearlever

    # Hardware, monitorización y dispositivos.
    openrgb-with-all-plugins
    rpi-imager
  ];

  # ============================================================
  # FLATPAK
  # ============================================================

  services.flatpak = {
    enable = true;

    remotes = [
      {
        name = "flathub";
        location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      }
      {
        # Repositorio oficial de NVIDIA GeForce NOW para Linux.
        name = "geforcenow";
        location = "https://international.download.nvidia.com/GFNLinux/flatpak/geforcenow.flatpakrepo";
      }
      {
        # Repositorio comunitario de Anycubic Slicer Next para Linux.
        name = "anycubic-slicer-next";
        location = "https://develonrails.github.io/anycubic-slicer-next/anycubic-slicer-next.flatpakrepo";
      }
    ];

    packages = [
      "com.stremio.Stremio"
      "org.onlyoffice.desktopeditors"
      "dev.fredol.open-tv"
      "com.github.sdv43.whaler"
      "io.github.dvlv.boxbuddyrs"
      "net.waterfox.waterfox"
      "io.github.totoshko88.RustConn"

      # Cliente nativo oficial de NVIDIA GeForce NOW para Linux.
      {
        appId = "com.nvidia.geforcenow";
        origin = "geforcenow";
      }

      # Anycubic Slicer Next (reempaquetado comunitario, no oficial).
      {
        appId = "com.anycubic.AnycubicSlicer";
        origin = "anycubic-slicer-next";
      }
    ];

    # No hacer descargas durante cada nixos-rebuild switch: las activaciones
    # siguen siendo previsibles y pueden funcionar sin conexión.
    update.onActivation = false;
    update.auto = {
      enable = true;
      onCalendar = "weekly";
    };

    # No desinstala aplicaciones instaladas manualmente.
    uninstallUnmanaged = false;
  };

}
