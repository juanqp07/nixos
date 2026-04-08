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
  virtualisation.containers.enable = true;
  virtualisation.podman = {
    enable = true;
    # Crea un alias de 'docker' para podman
    dockerCompat = true;
    # Necesario para que los contenedores se comuniquen entre sí
    defaultNetwork.settings.dns_enabled = true;
  };

  #virtualisation.virtualbox.host.enable = true;
  #users.extraGroups.vboxusers.members = [ "juan" ];

  # --- PERMISOS DE USUARIO ---
  # Añadido "podman" a los grupos para gestión rootless
  users.users.juan = {
    isNormalUser = true;
    extraGroups = [ "wheel" "video" "audio" "lp" "scanner" "podman" "uinput" "render" ];
  };

  # --- GAMING ---
  programs.steam.enable = true;
  programs.gamemode.enable = true;
  programs.appimage.binfmt = true;

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
    inputs.subtui.packages.${pkgs.system}.default
    floorp-bin vesktop 
    onlyoffice-desktopeditors kdePackages.kate vscode
    vlc mpv yt-dlp ffmpeg
    prismlauncher 
    distrobox podman-compose
    kdePackages.xdg-desktop-portal-kde wl-clipboard
    protonplus supersonic-wayland
    antigravity
    python3 kdePackages.kcalc
    heroic rustdesk-flutter
    go lm_sensors obs-studio gcc
    syncthing jetbrains.idea openjdk25
    feishin protonplus
    bottles cloudflare-warp
    google-chrome
    hydralauncher
    libreoffice hunspell
    hunspellDicts.es_ES
    openrgb-with-all-plugins
    lmstudio localsend
  ];
  services.hardware.openrgb.enable = true;
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc # Librerías base de C++
    zlib         # Muy común para compresión
    fuse3        # Útil para sistemas de archivos
    icu          # Soporte de internacionalización
    nss          # Seguridad de red
    openssl      # Cifrado (necesario para casi todo lo que use red)
    curl         # Para descargar cosas desde el binario
    expat        # Parseo de XML
    libxml2      # Más XML
    glibc
    libz
  ];

  # --- FLATPAK ---
  services.flatpak = {
    enable = true;
    remotes = [{
      name = "flathub";
      location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
    }];
    packages = [ "com.stremio.Stremio" "dev.fredol.open-tv" "io.github.dvlv.boxbuddyrs" "com.github.iwalton3.jellyfin-media-player" "io.github.ryubing.Ryujinx" ];
    update.onActivation = true;
    uninstallUnmanaged = true; 
  };
}
