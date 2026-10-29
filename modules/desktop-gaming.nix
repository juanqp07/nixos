{ config, pkgs, inputs, lib, ... }:

{
  # ============================================================
  # ARRANQUE Y KERNEL
  # ============================================================

  boot.kernelParams = [
    "quiet"
    "splash"
    "loglevel=3"
    "rd.systemd.show_status=false"
    "rd.udev.log_level=3"
    "udev.log_priority=3"
  ];

  services.cloudflare-warp.enable = true;
  boot.plymouth.enable = true;

  # ESP de 1 GB: limita las generaciones en /boot para que no se llene (kernel latest + initrd con firmware GPU).
  boot.loader.systemd-boot.configurationLimit = 8;

  boot.consoleLogLevel = 0;

  services.netbird.enable = true;

  # NetBird/WARP pueden crear rutas asimétricas o túneles; el modo loose
  # mantiene la validación de origen sin exigir que la respuesta use la misma interfaz.
  networking.firewall.checkReversePath = "loose";

  # SSH sigue disponible para administración remota, pero limitamos los
  # intentos fallidos y la duración de las sesiones de autenticación.
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    jails.sshd = {
      enabled = true;
      filter = "sshd[mode=aggressive]";
      settings = {
        maxretry = 5;
        findtime = "10m";
      };
    };
  };

  # Evita que los registros de escritorio crezcan sin límite.
  services.journald.settings.Journal = {
    SystemMaxUse = "512M";
    MaxRetentionSec = "2week";
  };

  # ============================================================
  # COMPATIBILIDAD CON CLINE CLI EN NIXOS
  # ============================================================

  # Cline CLI espera encontrar Bash en /bin/bash.
  # NixOS crea /bin/sh, pero no garantiza que exista /bin/bash.
  # Creamos un enlace al Bash de Nix después de la activación
  # del script binsh de NixOS, conservando /bin/sh intacto.
  system.activationScripts.cline-bash-compat = {
    deps = [ "binsh" ];
    text = ''
      ln -sfn "${pkgs.bashInteractive}/bin/bash" /bin/bash
    '';
  };


  # ============================================================
  # ENTORNO GRÁFICO (Plasma 6)
  # ============================================================

  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "es";
    variant = "";
  };

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

    # Arranca bajo demanda (socket activation).
    # Contenedores con --restart=always no arrancan solos al iniciar.
    onBoot = "ignore";
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
    # Comunicación y navegadores.
    openvpn
    telegram-desktop
    vesktop
    discord
    google-chrome

    # Ofimática e idiomas.
    onlyoffice-desktopeditors
    libreoffice
    hunspell
    hunspellDicts.es_ES
    typora

    # KDE y utilidades de escritorio.
    kdePackages.kate
    gedit
    kdePackages.kcalc
    kdePackages.filelight
    kdePackages.partitionmanager
    kdePackages.xdg-desktop-portal-kde
    wl-clipboard
    libnotify

    # Audio, vídeo y multimedia.
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

    # Desarrollo y herramientas CLI.
    vscode
    antigravity-ide
    jetbrains.idea
    opencode
    lmstudio
    bun
    android-tools
    bashInteractive
    go
    nodejs_24
    rustc
    cargo
    rustfmt
    clippy
    stdenv.cc

    # Contenedores, utilidades de compatibilidad y gestión de AppImage.
    distrobox
    lazydocker
    gearlever
    appimage-run

    # Hardware, monitorización y dispositivos.
    lm_sensors
    openrgb-with-all-plugins
    rpi-imager
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

    # vm.swappiness y vm.page-cluster se definen en el módulo común,
    # ya que ambos equipos utilizan zram.
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
      "com.github.sdv43.whaler"
      "io.github.dvlv.boxbuddyrs"
      "net.waterfox.waterfox"
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