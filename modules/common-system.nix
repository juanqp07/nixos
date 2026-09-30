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

  # ============================================================
  # RED Y KERNEL
  # ============================================================

  boot.kernel.sysctl = {
    # --- Rendimiento de Red ---
    "net.core.default_qdisc" = "cake";
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.ipv4.tcp_rmem" = "4096 87380 16777216";
    "net.ipv4.tcp_wmem" = "4096 65536 16777216";
    "net.ipv4.tcp_fastopen" = 3;

    # --- Seguridad de Red ---
    "net.ipv6.conf.all.forwarding" = 0;
    "net.ipv4.icmp_echo_ignore_all" = 0;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;

    # --- Memoria y Ficheros ---
    "fs.file-max" = 2097152;
    "fs.nr_open" = 1048576;
    "vm.swappiness" = 10;
    "vm.max_map_count" = 262144;

    # --- Conexiones ---
    "net.core.somaxconn" = 8192;
    "net.ipv4.tcp_max_syn_backlog" = 8192;

    # --- Streaming ---
    "net.ipv4.tcp_slow_start_after_idle" = 0;

    # --- MTU ---
    "net.ipv4.tcp_mtu_probing" = 1;
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
  services.netbird.enable = true;
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

  programs.fish.enable = true;

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

    allowed-users = [
      "@wheel"
    ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # ============================================================
  # PAQUETES CLI
  # ============================================================

  environment.systemPackages =
    with pkgs;
    [
      git
      wget
      curl
      vim
      btop
      htop
      fastfetch
      pciutils
      lshw
      usbutils
      dnsutils
      openssl
      zip
      unzip
      fish
      ripgrep
      fd
      jq
      bat
      tree
      direnv
      lynis
      nvd
      gedit
    ]
    # rar/unrar solo existen para x86_64-linux; en la Pi se usa unzip.
    ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
      rar
      unrar
    ];

  # ============================================================
  # ALIAS DE MANTENIMIENTO
  # ============================================================

  environment.shellAliases = {
    nix-up =
      "pushd ~/nixos > /dev/null && "
      + "echo '--- 🔄 Actualizando ---' && "
      + "nix flake update && "
      + "echo '--- 🏗️ Construyendo ---' && "
      + "sudo nixos-rebuild build --flake .#${config.networking.hostName} && "
      + "echo '--- 📋 Diferencias ---' && "
      + "nvd diff /run/current-system result && "
      + "echo '--- 🚀 Aplicando ---' && "
      + "sudo nixos-rebuild switch --flake .#${config.networking.hostName} && "
      + "popd > /dev/null";

    nix-full-maintenance = "nix-up && nix-clean";

    nix-clean =
      "sudo nix-collect-garbage --delete-older-than 7d && "
      + "nix-store --optimise";
  };
}