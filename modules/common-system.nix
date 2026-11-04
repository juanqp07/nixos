{ config, pkgs, lib, ... }:

{
  # ============================================================
  # BOOT (x86_64 con UEFI; en Pi 4 lo gestiona extlinux + U-Boot)
  # ============================================================

  boot.loader.systemd-boot.enable = lib.mkDefault (
    pkgs.stdenv.hostPlatform.isx86_64
  );
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault (
    pkgs.stdenv.hostPlatform.isx86_64
  );

  # Evita que /boot se llene con generaciones antiguas (los hosts pueden sobrescribirlo).
  boot.loader.systemd-boot.configurationLimit = lib.mkDefault 10;

  boot.loader.systemd-boot.edk2-uefi-shell.enable = lib.mkDefault pkgs.stdenv.hostPlatform.isx86_64;
  # ============================================================
  # RED Y KERNEL
  # ============================================================

  boot.kernel.sysctl = {
    # --- Seguridad de red ---
    # La ruta inversa (rp_filter) se configura en networking.firewall por host:
    # los equipos con VPN necesitan tolerar rutas asimétricas.
    "net.ipv6.conf.all.forwarding" = 0;
    "net.ipv4.icmp_echo_ignore_all" = 0;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;

    # --- Memoria ---
    # Todos los hosts usan zram; afinar más exige medir presión de RAM y carga.
    "vm.swappiness" = 100;
    "vm.page-cluster" = 0;
    "vm.max_map_count" = 262144;
  };

  # ============================================================
  # ESTABILIDAD
  # ============================================================

  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 5;
  };

  security.pam.loginLimits = [
    {
      domain = "*";
      type = "soft";
      item = "nofile";
      value = "65536";
    }
    {
      domain = "*";
      type = "hard";
      item = "nofile";
      value = "65536";
    }
  ];

  # ============================================================
  # RED Y LOCALIZACIÓN
  # ============================================================

  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Madrid";

  i18n.defaultLocale = "es_ES.UTF-8";

  console.keyMap = lib.mkDefault "es";

  # Servicios base
  # NOTA: netbird NO va aquí. Cada host lo habilita explícitamente
  # (desktop-gaming.nix, servidor, zimablade). Palco no lo usa.
  # fwupd no tiene sentido en Pi 4 (sin UEFI/LVFS útil aquí)
  services.fwupd.enable = pkgs.stdenv.hostPlatform.isx86_64;

  # ============================================================
  # USUARIO
  # ============================================================

  users.users.juan = {
    isNormalUser = true;
    description = "juan";
    shell = pkgs.fish;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  programs.fish = {
    enable = true;

    # Oculta el saludo predeterminado en todas las sesiones interactivas.
    interactiveShellInit = ''
      set -g fish_greeting
    '';
  };

  # SSH con contraseña se mantiene deliberadamente para no depender de claves
  # que puedan perderse. Root no debe autenticarse directamente por SSH.
  services.openssh.settings.PasswordAuthentication = lib.mkDefault true;
  services.openssh.settings.PermitRootLogin = lib.mkDefault "no";
  services.openssh.settings.MaxAuthTries = lib.mkDefault 3;
  services.openssh.settings.LoginGraceTime = lib.mkDefault "30s";

  # direnv + nix-direnv: activa devShells al hacer `cd` (sin esto el
  # paquete direnv solo no integra el shell).
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # ============================================================
  # NIX
  # ============================================================

  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];

    auto-optimise-store = true;

    # Límite conservador; cada host define un presupuesto adecuado a su hardware.
    max-jobs = lib.mkDefault 2;
    cores = lib.mkDefault 1;

    allowed-users = [
      "@wheel"
    ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    # 30d en general para no perder rollback si un kernel latest rompe nvidia.
    # pico (zimablade) lo fuerza a 7d por disco pequeño, palco lo desactiva.
    options = "--delete-older-than 30d";
  };

  # ============================================================
  # PAQUETES CLI
  # ============================================================

  environment.systemPackages =
    with pkgs;
    [
      # Git y red
      git
      curl
      wget
      rsync
      dnsutils
      openssl
      mtr
  
      # Terminal y monitorización
      vim
      fish
      btop
      fastfetch
      tmux
  
      # Archivos y búsqueda
      ripgrep
      fd
      fzf
      bat
      tree
      jq
      file
      ncdu
  
      # Administración y hardware
      lsof
      pciutils
      lshw
      usbutils
      lm_sensors
  
      # NixOS
      nvd
      nix-output-monitor
  
      # Diagnóstico y archivos comprimidos
      stress-ng
      zip
      unzip
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
      rar
      unrar
    ];

  # ============================================================
  # ALIAS DE MANTENIMIENTO
  # ============================================================

  environment.shellAliases = {
    # Consulta las versiones de kernel configuradas en todos los hosts.
    kernels = "bash ~/nixos/scripts/kernel-versions.sh";

    # Comprueba reinicios según la estrategia switch/boot del host.
    nix-reboot-check = "bash ~/nixos/scripts/nix-reboot-check.sh";

    # Mantenimiento completo: interactivo o automático con -y.
    nix-maintain = "bash ~/nixos/scripts/nix-maintenance.sh maintain";

    # Actualiza todos los inputs, construye y pregunta antes de aplicar.
    nix-update = "bash ~/nixos/scripts/nix-maintenance.sh update";

    # Construye y aplica usando el flake.lock existente, sin actualizar inputs.
    nix-apply-locked = "bash ~/nixos/scripts/nix-maintenance.sh apply";

    # Limpia generaciones según nix.gc.options declaradas para el host actual.
    nix-clean = "bash ~/nixos/scripts/nix-maintenance.sh clean";

    # Lista las generaciones del perfil del sistema.
    nix-generations = "sudo nixos-rebuild list-generations";

    # Deduplicación completa manual; auto-optimise-store sigue cubriendo nuevas rutas.
    nix-optimise = "sudo nix-store --optimise";
  };
}
