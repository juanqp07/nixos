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

  boot.loader.timeout = 0;

  services.cloudflare-warp.enable = true;
  boot.plymouth.enable = true;

  # Acelerar arranque: no esperar a que la red esté online ni a udev-settle.
  systemd.services.NetworkManager-wait-online.enable = false;
  systemd.services.systemd-udev-settle.enable = false;

  # ESP de 1 GB: limita las generaciones en /boot para que no se llene (kernel latest + initrd con firmware GPU).
  boot.loader.systemd-boot.configurationLimit = 8;

  boot.consoleLogLevel = 0;

  services.netbird.enable = true;

  # NetBird/WARP pueden crear rutas asimétricas; mantenemos validación de origen
  # sin exigir que cada paquete vuelva por la misma interfaz.
  networking.firewall.checkReversePath = "loose";

  # SSH permanece habilitado para administración remota; bloquea intentos repetidos.
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

  # Evita que los registros de escritorio ocupen disco sin límite.
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

  # KDE Plasma 6 como único entorno gráfico, con SDDM como gestor de inicio.
  services.displayManager.sddm.enable = true;
  services.xserver.displayManager.lightdm.enable = lib.mkForce false;

  services.desktopManager.plasma6.enable = true;

  # Discover se instala automáticamente al habilitar Flatpak/fwupd en Plasma.
  # No lo necesitamos: las aplicaciones Flatpak se gestionan declarativamente.
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    discover
  ];

  # Preferencias y alias personales del escritorio gestionados por Home Manager.
  # Este módulo solo se añade a Elytra y Titan desde el Flake.
  home-manager.users.juan.imports = [
    ../home/juan/desktop.nix
  ];

  programs.kdeconnect.enable = true;

  # Montaje automático de unidades extraíbles (USB, incluida PS Vita con VitaShell).
  services.udisks2.enable = true;

  # Descubrimiento de dispositivos locales (Chromecast, Google Cast, etc.).
  # Este módulo se importa tanto en Elytra como en Titan.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;

    # Publicación mDNS explícita con las opciones actuales de Avahi.
    settings.publish = {
      "disable-publishing" = false;
      disable-user-service-publishing = false;
      publish-addresses = true;
    };
  };

  # Stremio: el Chromecast recibe el vídeo desde el servidor local del PC.
  # 11470 = HTTP y 12470 = HTTPS. No configurar port forwarding en el router.
  networking.firewall.allowedTCPPorts = [ 11470 12470 ];


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
    # Comunicación, navegación y acceso remoto.
    openvpn
    telegram-desktop
    vesktop
    discord
    rustdesk-flutter
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
    android-studio
    rustc
    cargo
    rustfmt
    clippy
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
    python3
    python3Packages.pip
    mkdocs
    rustup
    stdenv.cc

    # Contenedores y gestión de AppImage.
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

  # scx-loader sustituye al módulo services.scx eliminado en nixpkgs.
  # Titan usa el modo Gaming de scx_cosmos (-s 700); Elytra lo sobrescribe
  # a Auto en hosts/portatil/configuration.nix.
  services.scx-loader = {
    enable = true;

    config = {
      default_sched = "scx_cosmos";
      default_mode = "Gaming";
    };
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


  # ============================================================
  # OVERLAYS
  # ============================================================

  nixpkgs.overlays = [
    # Workaround temporal para rustdesk-flutter 1.5.0 en nixpkgs f4a03c0:
    # tras dejar de vendorizar las dependencias Rust, libsodium-sys necesita
    # localizar libsodium mediante pkg-config. El paquete omitía libsodium
    # de buildInputs (NixOS/nixpkgs#585458).
    #
    # Se evita duplicarlo cuando nixpkgs ya incluya la dependencia.
    (final: prev: {
      rustdesk-flutter = prev.rustdesk-flutter.overrideAttrs (old:
        let
          inputs = old.buildInputs or [ ];
        in
        {
          buildInputs = inputs ++ lib.optional (!(lib.elem final.libsodium inputs)) final.libsodium;
        }
      );
    })
    # Workaround temporal para OpenCode 2.2.5 con Bun 1.4.4.
    # NixOS/nixpkgs#582675 ya está fusionado, pero la corrección aún no
    # ha llegado a nixos-unstable. Retirar este override cuando llegue.
    (final: prev: {
      opencode = prev.opencode.overrideAttrs (old: {
        node_modules = old.node_modules.overrideAttrs (_: {
          outputHash = "sha256-prx9dX7kUvs/E3zopkaPk5LXh3xJAy5sZeum/W8L7cA=";
        });
      });
    })
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