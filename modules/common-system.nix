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
    "net.ipv4.icmp_echo_ignore_all" = 0; # No responde a pings externos
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

    # Evita el cuello de botella en el "saludo" de la conexión (vital para IPTV/m3u)
    "net.core.somaxconn" = 8192;
    "net.ipv4.tcp_max_syn_backlog" = 8192;
    
    # Recuperación instantánea tras pausa en streaming
    "net.ipv4.tcp_slow_start_after_idle" = 0;
    
    # Ayuda con la compatibilidad de MTU en redes con Cloudflare
    "net.ipv4.tcp_mtu_probing" = 1;
  };

  # --- 2. SERVICIOS DE ESTABILIDAD ---
  
  # EarlyOOM: Mata procesos antes de que el sistema se congele totalmente
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5; 
    freeSwapThreshold = 5;
  };

  security.pam.loginLimits = [
    { domain = "*"; type = "soft"; item = "nofile"; value = "65536"; }
    { domain = "*"; type = "hard"; item = "nofile"; value = "65536"; }
  ];

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
    git wget curl vim btop htop fastfetch pciutils lshw usbutils 
    dnsutils openssl zip unzip fish ripgrep fd jq bat tree direnv lynis nvd
  ];  

  # --- 7. ALIAS DE MANTENIMIENTO ---
  environment.shellAliases = {
    nix-up = "pushd ~/nixos > /dev/null && echo '--- 🔄 Actualizando ---' && nix flake update && echo '--- 🏗️ Construyendo ---' && sudo nixos-rebuild build --flake .#pico && echo '--- 📋 Diferencias ---' && nvd diff /run/current-system result && echo '--- 🚀 Aplicando ---' && sudo nixos-rebuild switch --flake .#pico && popd > /dev/null";
    nix-full-maintenance = "nix-up && nix-clean"; 
    nix-clean = "sudo nix-collect-garbage --delete-older-than 7d && nix-store --optimise";
  };
}
