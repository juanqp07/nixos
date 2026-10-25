{ config, pkgs, inputs, lib, ... }:

{
  # ============================================================
  # ARRANQUE Y KERNEL
  # ============================================================

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
    wayland.enable = true;
  };

  services.desktopManager.plasma6.enable = true;

  programs.kdeconnect.enable = true;


  # ============================================================
  # SONIDO Y BLUETOOTH
  # ============================================================

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;

    alsa.enable = true;
    alsa.support32Bit = true;

    pulse.enable = true;
    jack.enable = true;
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;

    settings = {
      General = {
        Experimental = true;
        FastConnectable = true;
      };

      Policy = {
        AutoEnable = true;
      };
    };
  };

  services.blueman.enable = true;


  # ============================================================
  # VIRTUALIZACIÓN: DOCKER + KVM + LIBVIRT
  # ============================================================

  # Docker como backend principal para los contenedores.
  # Distrobox sigue funcionando con Docker.
  virtualisation.docker.enable = true;

  # Máquinas virtuales mediante QEMU/KVM y libvirt.
  virtualisation.libvirtd = {
    enable = true;
  };

  #virtualisation.virtualbox.host.enable = true;
  #users.extraGroups.vboxusers.members = [ "juan" ];

  # --- PERMISOS DE USUARIO ---
  users.users.juan = {
    isNormalUser = true;

    extraGroups = [
      "wheel"
      "video"
      "audio"
      "lp"
      "scanner"
      "docker"
      "libvirtd"
      "uinput"
      "render"
    ];
  };


  # ============================================================
  # IMPRESIÓN Y SINCRONIZACIÓN
  # ============================================================

  services.printing.enable = true;

  services.syncthing = {
    enable = true;
    user = "juan";

    # Directorio base para las carpetas sincronizadas.
    dataDir = "/home/juan";

    # Configuración y claves de Syncthing.
    configDir = "/home/juan/.config/syncthing";

    openDefaultPorts = true;
    extraFlags = [
      "--no-browser"
    ];
  };


  # ============================================================
  # GAMING Y MANDOS
  # ============================================================

  programs.steam = {
    enable = true;

    remotePlay.openFirewall = true;
    gamescopeSession.enable = true;
  };

  hardware.steam-hardware.enable = true;
  hardware.xpadneo.enable = true;

  services.ratbagd.enable = true;

  services.power-profiles-daemon.enable = true;
  services.fstrim.enable = true;

  programs.gamemode = {
    enable = true;
    enableRenice = true;

    settings.general = {
      desiredgov = "performance";
      defaultgov = "powersave";
      renice = 10;
      inhibit_screensaver = 1;
      reaper_freq = 5;
    };
  };


  # ============================================================
  # OBSERVABILIDAD, APPIMAGE Y RGB
  # ============================================================

  programs.obs-studio = {
    enable = true;
    enableVirtualCamera = false;
  };

  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  services.hardware.openrgb.enable = true;


  # ============================================================
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
    inputs.nix-software-center.packages.${pkgs.stdenv.hostPlatform.system}.nix-software-center
    openvpn telegram-desktop
    vesktop discord firefox
    onlyoffice-desktopeditors kdePackages.kate vscode
    vlc mpv yt-dlp ffmpeg
    prismlauncher
    distrobox lazydocker
    kdePackages.xdg-desktop-portal-kde wl-clipboard
    protonplus supersonic
    antigravity-ide
    kdePackages.kcalc
    heroic rustdesk-flutter
    lm_sensors
    syncthing jetbrains.idea
    feishin
    cloudflare-warp

    # Navegadores.
    firefox
    google-chrome

    # Ofimática y edición.
    onlyoffice-desktopeditors
    libreoffice
    hunspell
    hunspellDicts.es_ES
    typora

    # KDE y utilidades de escritorio.
    kdePackages.kate
    kdePackages.kcalc
    kdePackages.filelight
    kdePackages.partitionmanager
    kdePackages.xdg-desktop-portal-kde
    wl-clipboard
    libnotify
    lm_sensors

    # Multimedia.
    vlc
    mpv
    yt-dlp
    ffmpeg
    supersonic
    feishin
    streamlink
    gopeed
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

    # Contenedores.
    distrobox
    lazydocker

    # Desarrollo.
    vscode
    antigravity-ide
    jetbrains.idea
    opencode
    bun
    android-tools

    # Android Studio se mantiene en Flatpak.
    # Se evita descargar el tarball durante nixos-rebuild.

    # Gestión de AppImage y utilidades.
    gearlever
    appimage-run

    # Hardware y dispositivos.
    openrgb-with-all-plugins
    rpi-imager

    # Compilación de Rust.
    rustc
    cargo
    rustfmt
    clippy
    stdenv.cc
  ];


  # ============================================================
  # NIX-LD: COMPATIBILIDAD CON BINARIOS LINUX
  # ============================================================

  programs.nix-ld.enable = true;

  programs.nix-ld.libraries = with pkgs; [
    # Runtime y bibliotecas básicas.
    stdenv.cc.cc
    glibc
    zlib
    libz
    bzip2
    xz
    zstd
    lz4
    libgcc

    # Seguridad y certificados.
    curl
    openssl
    nss
    nspr

    # Fuentes y renderizado de texto.
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

    # GTK y bibliotecas gráficas.
    glib
    gtk3
    gtk4
    gdk-pixbuf
    cairo
    atk
    at-spi2-atk
    at-spi2-core
    libepoxy

    # Audio.
    alsa-lib
    pipewire
    libpulseaudio
    libsndfile
    libsamplerate

    # X11.
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

    # XCB.
    libxcb
    libxcb-util
    libxcb-wm
    libxcb-image
    libxcb-keysyms
    libxcb-render-util
    libxcb-cursor

    # Wayland.
    wayland

    # OpenGL, Vulkan y vídeo.
    libGL
    libGLU
    mesa
    vulkan-loader
    libdrm
    libgbm
    ffmpeg
    libva
    libvdpau

    # Sistema de archivos y dispositivos.
    fuse3
    libarchive
    libffi
    libcap
    libuuid
    libusb1
    sqlite
    dbus
    libgpg-error
    e2fsprogs

    # Herramientas de compilación.
    gnumake
    gcc
    python3

    # Entornos de desarrollo.
    nodejs_24
    deno
    bun
    rustc
    cargo
    rustfmt
    clippy
  ];


  # ============================================================
  # MEMORIA Y SCHEDULER
  # ============================================================

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  services.scx = {
    enable = true;
    scheduler = "scx_cosmos";

    extraArgs = [
      "-s"
      "700"
    ];
  };

  boot.kernel.sysctl = {
    # El valor original común era 262144.
    # Se fuerza 1048576 para Proton y aplicaciones exigentes.
    "vm.max_map_count" = lib.mkForce 1048576;
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 1024;
  };


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
    ];

    packages = [
      "com.stremio.Stremio"
      "dev.fredol.open-tv"
      "io.github.ryubing.Ryujinx"
      "com.google.AndroidStudio"
    ];

    update.onActivation = true;

    # No desinstala aplicaciones instaladas manualmente.
    uninstallUnmanaged = false;
  };


  # ============================================================
  # OVERLAYS
  # ============================================================

  nixpkgs.overlays = [
    (final: prev: {
      gearlever = prev.gearlever.overridePythonAttrs (old: {
        makeWrapperArgs = [
          "--prefix"
          "PATH"
          ":"
          (prev.lib.makeBinPath [
            prev.file
            prev._7zz
            prev.which
            prev.appimage-run
            prev.desktop-file-utils
            prev.gtk4.dev
            prev.bintools
            prev.libnotify
            prev.dwarfs
            prev.squashfs-tools
          ])
        ];

        preFixup = (old.preFixup or "") + ''
          makeWrapperArgs+=("''${gappsWrapperArgs[@]}")
        '';
      });
    })
  ];
}