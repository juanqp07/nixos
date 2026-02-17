{ config, pkgs, lib, ... }:

{
  # --- BOOT ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernel.sysctl = {
      # --- Rendimiento de Red ---
      "net.core.default_qdisc" = "cake";
      "net.ipv4.tcp_congestion_control" = "bbr";
      "net.core.rmem_max" = 16777216;
      "net.core.wmem_max" = 16777216;
      "net.ipv4.tcp_rmem" = "4096 87380 16777216";
      "net.ipv4.tcp_wmem" = "4096 65536 16777216";
      "net.ipv4.tcp_tw_reuse" = 1;
  
      # --- Seguridad de Red (AJUSTADO PARA DOCKER) ---
      "net.ipv6.conf.all.forwarding" = 0;
      "net.ipv4.icmp_echo_ignore_all" = 1;
      "net.ipv4.conf.all.rp_filter" = 0;
      "net.ipv4.conf.default.rp_filter" = 0;
  
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv6.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.ipv6.conf.default.accept_redirects" = 0;
      "net.ipv4.conf.all.accept_source_route" = 0;
      "net.ipv6.conf.all.accept_source_route" = 0;
      "net.ipv4.conf.default.accept_source_route" = 0;
      "net.ipv6.conf.default.accept_source_route" = 0;
  
      # --- Memoria y Ficheros ---
      "fs.file-max" = 2097152;
      "fs.nr_open" = 1048576;
      "vm.swappiness" = 10;
      "vm.max_map_count" = 262144;
  
      # --- Miscelánea de Seguridad ---
      "kernel.sysrq" = 0;
    };
  # --- RED Y LOCALIZACIÓN ---
  networking.networkmanager.enable = true;
  time.timeZone = "Europe/Madrid";
  
  i18n.defaultLocale = "es_ES.UTF-8";

  console.keyMap = lib.mkDefault "es";

  # --- SERVICIOS DE RED ---
  services.netbird.enable = true;

  # --- CONFIGURACIÓN DE USUARIO ---
  users.users.juan = {
    isNormalUser = true;
    description = "juan";
    shell = pkgs.fish;
    extraGroups = [ "networkmanager" "wheel" ]; 
  };
  programs.fish.enable = true;

  # --- NIX SETTINGS ---
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d"; 
  };
  nix.settings.auto-optimise-store = true;
  services.fwupd.enable = true;
  # --- PAQUETES ESENCIALES (SOLO CLI) --- 
  environment.systemPackages = with pkgs; [
    git wget curl vim btop htop fastfetch pciutils lshw usbutils dnsutils openssl zip unzip fish
    ripgrep fd jq bat tree direnv lynis
  ];  

  # --- MANTENIMIENTO ---
  environment.shellAliases = {
    # Mantenimiento total: Actualiza flake, aplica cambios, limpia basura y optimiza
    nix-full-maintenance = "pushd ~/nixos && nix flake update && sudo nixos-rebuild switch --flake .#$(hostname) && sudo nix-collect-garbage -d && nix-store --optimize && popd";

    # Actualización rápida (solo sistema, sin borrar historial)
    nix-up = "pushd ~/nixos && sudo fwupdmgr update && nix flake update && sudo nixos-rebuild switch --flake .#$(hostname) && popd";

    # Limpieza profunda de archivos viejos
    nix-clean = "sudo nix-collect-garbage -d && nix-store --optimize";

    # Sincronización Pro: Pull, Actualizar Flake, Rebuild, Git Commit/Push y Limpieza
    nix-sync = ''
      pushd ~/nixos && \
      git pull && \
      nix flake update && \
      sudo nixos-rebuild switch --flake .#$(hostname) && \
      git add flake.lock && \
      git commit -m "chore: update flake.lock ($(date +%Y-%m-%d))" && \
      git push && \
      sudo nix-collect-garbage -d && \
      nix-store --optimize && \
      popd
    '';
  };

}
