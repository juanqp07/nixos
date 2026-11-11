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
    # Keep explicit hardening where it changes the kernel defaults. IPv6
    # forwarding and ICMP echo replies retain their kernel defaults (0).
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
    # Host-specific thresholds can override these without mkForce.
    freeMemThreshold = lib.mkDefault 5;
    freeSwapThreshold = lib.mkDefault 5;
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

  # Mostrar asteriscos al introducir contraseñas en las solicitudes de sudo.
  # Afecta a todos los hosts que importan este módulo común.
  security.sudo.extraConfig = ''
    Defaults pwfeedback
  '';

  # Fish es el shell del sistema; las preferencias personales viven en Home Manager.
  programs.fish.enable = true;

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
    options = lib.mkDefault "--delete-older-than 30d";
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
      btop
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

      # Diagnóstico y archivos comprimidos
      stress-ng
      zip
      unzip
      unar
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
      rar
    ];

}
