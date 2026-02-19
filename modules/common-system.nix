{ config, pkgs, lib, ... }:

{
  # --- BOOT ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernel.sysctl = {
      # Reiniciar automáticamente 10 segundos después de un Kernel Panic
      "kernel.panic" = 10;
      
      # Reiniciar si hay un "Oops" (fallo interno del kernel)
      "kernel.panic_on_oops" = 1;
    
      # Reiniciar si el sistema se queda sin memoria (OOM) en lugar de intentar matar procesos
      "vm.panic_on_oom" = 1;
    
      # Reiniciar si se detecta un bloqueo de software (soft lockup)
      "kernel.softlockup_panic" = 1;

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
{ config, pkgs, lib, ... }:

{
  # --- 1. BOOT Y RESILIENCIA DEL KERNEL ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Parámetros para que el kernel se reinicie si falla en etapas tempranas
  boot.kernelParams = [ 
    "panic=10"                # Reiniciar tras 10s de pánico
    "boot.panic_on_fail"      # Reiniciar si falla el montaje del sistema de archivos
    "nmi_watchdog=1"          # Activa el detector de bloqueos de hardware
  ];

  boot.kernel.sysctl = {
    # --- Auto-reinicio en Fallos Críticos ---
    "kernel.panic" = 10;
    "kernel.panic_on_oops" = 1;
    "vm.panic_on_oom" = 1;           # Reinicia si se agota la RAM totalmente
    "kernel.softlockup_panic" = 1;   # Reinicia si detecta un núcleo de CPU bloqueado
    "kernel.hung_task_panic" = 1;    # Reinicia si un proceso queda bloqueado > 5 min
    "kernel.hung_task_timeout_secs" = 300;
    
    # Habilitar SysRq para rescate manual (permite comandos de emergencia al kernel)
    "kernel.sysrq" = 1;

    # --- Rendimiento de Red (Optimizado) ---
    "net.core.default_qdisc" = "cake";
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.ipv4.tcp_rmem" = "4096 87380 16777216";
    "net.ipv4.tcp_wmem" = "4096 65536 16777216";
    "net.ipv4.tcp_tw_reuse" = 1;
    "net.ipv4.tcp_fastopen" = 3;

    # --- Seguridad de Red (Compatible con Docker) ---
    "net.ipv6.conf.all.forwarding" = 0;
    "net.ipv4.icmp_echo_ignore_all" = 1; # No responde a pings externos
    "net.ipv4.conf.all.rp_filter" = 0;
    "net.ipv4.conf.default.rp_filter" = 0;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;

    # --- Memoria y Ficheros ---
    "fs.file-max" = 2097152;
    "fs.nr_open" = 1048576;
    "vm.swappiness" = 10;
    "vm.max_map_count" = 262144;
  };

  # --- 2. SERVICIOS DE ESTABILIDAD ---
  
  # EarlyOOM: Mata procesos antes de que el sistema se congele totalmente
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5; 
    freeSwapThreshold = 5;
  };

  # --- 3. RED Y LOCALIZACIÓN ---
  networking.networkmanager.enable = true;
  time.timeZone = "Europe/Madrid";
  i18n.defaultLocale = "es_ES.UTF-8";
  console.keyMap = lib.mkDefault "es";

  # Servicios base
  services.netbird.enable = true;
  services.fwupd.enable = true;

  # --- 4. CONFIGURACIÓN DE USUARIO ---
  users.users.juan = {
    isNormalUser = true;
    description = "juan";
    shell = pkgs.fish;
    extraGroups = [ "networkmanager" "wheel" ]; 
  };
  programs.fish.enable = true;

  # --- 5. NIX SETTINGS ---
  nixpkgs.config.allowUnfree = true;
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    allowed-users = [ "@wheel" ];
  };
  
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d"; 
  };

  # --- 6. PAQUETES ESENCIALES (SOLO CLI) --- 
  environment.systemPackages = with pkgs; [
    git wget curl vim btop htop fastfetch pciutils lshw usbutils dnsutils openssl zip unzip fish
    ripgrep fd jq bat tree direnv lynis
  ];  

  # --- 7. ALIAS DE MANTENIMIENTO ---
  environment.shellAliases = {
    nix-full-maintenance = "pushd ~/nixos && nix flake update && sudo nixos-rebuild switch --flake .#$(hostname) && sudo nix-collect-garbage -d && nix-store --optimize && popd";
    nix-up = "pushd ~/nixos && nix flake update && sudo nixos-rebuild switch --flake .#$(hostname) && sudo fwupdmgr update && popd";
    nix-clean = "sudo nix-collect-garbage -d && nix-store --optimize";
  };
}
  };

}
