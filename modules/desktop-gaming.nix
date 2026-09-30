{ config, pkgs, inputs, ... }:

{
  # --- KERNEL ---
  boot.kernelParams = [
      "quiet"
      "splash"
      "boot.shell_on_fail"
      "loglevel=3"
      "rd.systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
    ];
  services.cloudflare-warp.enable = true;
  boot.plymouth.enable = true;

  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;
  # --- ENTORNO GRÁFICO (Plasma 6) ---
  services.xserver.enable = true;
  services.xserver.xkb = { layout = "es"; variant = ""; };
  services.displayManager.sddm = {
    enable = true;
    theme = "breeze";
  };
  services.displayManager.sddm.wayland.enable = true;
  services.desktopManager.plasma6.enable = true;
  programs.kdeconnect.enable = true;
  networking.networkmanager = {
    enable = true;
    plugins = [ pkgs.networkmanager-openvpn ];
  };
  services.dbus.packages = [ pkgs.networkmanager-openvpn ];

  # --- SONIDO ---
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

  # --- VIRTUALIZACIÓN (Podman & Distrobox) ---
  # --- VIRTUALIZACIÓN (Docker & Distrobox) ---
  virtualisation.containers.enable = true;

  virtualisation.docker = {
    enable = true;
  };

  #virtualisation.virtualbox.host.enable = true;
  #users.extraGroups.vboxusers.members = [ "juan" ];

  # --- PERMISOS DE USUARIO ---
  # Añadido "podman" a los grupos para gestión rootless
  users.users.juan = {
    isNormalUser = true;
    extraGroups = [ "wheel" "video" "audio" "lp" "scanner" "docker" "uinput" "render" ];
  };

  # --- GAMING ---
  programs.steam.enable = true;
  programs.gamemode.enable = true;
  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  # --- FUENTES ---
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

  services.syncthing = {
    enable = true;
    user = "juan";
    dataDir = "/home/juan";    # Directorio base para las carpetas sincronizadas
    configDir = "/home/juan/.config/syncthing"; # Donde se guardan las llaves y config
    openDefaultPorts = true;
    extraFlags = [ "--no-browser" ];
  };
  # --- PAQUETES DE ESCRITORIO ---
  environment.systemPackages = with pkgs; [
    inputs.nix-software-center.packages.${pkgs.system}.nix-software-center
    openvpn telegram-desktop
    inputs.subtui.packages.${pkgs.system}.default
    vesktop firefox
    onlyoffice-desktopeditors kdePackages.kate vscode
    vlc mpv yt-dlp ffmpeg
    prismlauncher 
    distrobox podman-compose
    kdePackages.xdg-desktop-portal-kde wl-clipboard
    protonplus supersonic
    antigravity-ide
    python3 kdePackages.kcalc
    heroic rustdesk-flutter
    go lm_sensors obs-studio gcc
    syncthing jetbrains.idea openjdk25
    feishin protonplus
    cloudflare-warp
    google-chrome
    hydralauncher
    libreoffice hunspell
    hunspellDicts.es_ES
    openrgb-with-all-plugins
    localsend eden
    nodejs pnpm bun
    gearlever typora
    kdePackages.partitionmanager
    rpi-imager opencode
    impression
    android-tools
    # android-studio movido a Flatpak (com.google.AndroidStudio):
    # el tarball de ~1.35GB desde dl.google.com rompía `nixos-rebuild`
    # con `curl: (56) Recv failure`. Se mantiene android-tools en el host
    # para adb/fastboot + udev rules.
    wireguard-tools
    curl
    jq
    git
    appimage-run
  ];


  services.hardware.openrgb.enable = true;
  programs.nix-ld.enable = true;
    programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc
    glibc
    zlib
    libz
    bzip2
    xz
    zstd
    lz4
    libgcc

    curl
    openssl
    nss
    nspr

    fontconfig
    freetype
    fribidi
    harfbuzz
    pango
    libthai
    libdatrie
    expat
    libxml2
    icu

    glib
    gtk3
    gtk4
    gdk-pixbuf
    cairo
    atk
    at-spi2-atk
    at-spi2-core
    libepoxy

    alsa-lib
    pipewire
    libpulseaudio
    libsndfile
    libsamplerate

    libx11
    libxext
    libxrandr
    libxrender
    libxi
    libxfixes
    libxcursor
    libxinerama
    libxcomposite
    libxdamage
    libxscrnsaver
    libxtst
    libxkbcommon
    libxkbfile

    libxcb
    libxcb-util
    libxcb-wm
    libxcb-image
    libxcb-keysyms
    libxcb-render-util
    libxcb-cursor

    wayland

    libGL
    libGLU
    mesa
    vulkan-loader
    libdrm
    libgbm

    ffmpeg
    libva
    libvdpau

    fuse3
    libarchive
    libffi
    libcap
    libuuid
    libusb1
    sqlite
    dbus

    libgpg-error

    # libcom_err.so.2
    e2fsprogs

    gnumake
    gcc
    python3
    nodejs_24
    deno
  ];

  # --- FLATPAK ---
  services.flatpak = {
    enable = true;
    remotes = [{
      name = "flathub";
      location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
    }];
    packages = [
      "com.stremio.Stremio"
      "dev.fredol.open-tv"
      "io.github.dvlv.boxbuddyrs"
      "io.github.ryubing.Ryujinx"
      "com.google.AndroidStudio"
    ];
    update.onActivation = true;
    uninstallUnmanaged = true; 
  };
}
