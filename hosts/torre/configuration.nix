{ config, pkgs, lib, ... }: # Añadimos 'lib' aquí

{

  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "titan";

    boot.kernel.sysctl = {
    # --- Rendimiento de Red ---
    "net.core.default_qdisc" = "cake";
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.ipv4.tcp_rmem" = "4096 87380 16777216";
    "net.ipv4.tcp_wmem" = "4096 65536 16777216";
    "net.ipv4.tcp_tw_reuse" = 1;

    # --- Seguridad de Red ---
    "net.ipv4.ip_forward" = 0;
    "net.ipv6.conf.all.forwarding" = 0;
    "net.ipv4.icmp_echo_ignore_all" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
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

  # ---------------------------------------------------------
  # 1. OPTIMIZACIÓN CPU (Ryzen 5 5600X)
  # ---------------------------------------------------------
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # ---------------------------------------------------------
  # 2. GRÁFICOS Y GPU (Radeon RX 6700 XT)
  # ---------------------------------------------------------
  boot.initrd.kernelModules = [ "amdgpu" ];
  services.xserver.videoDrivers = [ "amdgpu" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true; 
    
    extraPackages = with pkgs; [
      rocmPackages.clr
      rocmPackages.clr.icd
    ];
  };

  environment.variables = {
    "HSA_OVERRIDE_GFX_VERSION" = "10.3.0";
  };

  # ---------------------------------------------------------
  # 3. SERVICIOS Y PAQUETES
  # ---------------------------------------------------------
  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [
    prismlauncher 
    headsetcontrol 
    lunar-client
    lact
    clinfo       
    vulkan-tools 
    amdgpu_top   
    lmstudio
  ];

  # ---------------------------------------------------------
  # 4. CONFIGURACIÓN HEADSET (Usando Timers, no scripts infinitos)
  # ---------------------------------------------------------
  services.udev.packages = [ pkgs.headsetcontrol ];

  systemd.services.headset-led-off = {
    description = "Apagar LEDs del Headset (Ejecución única)";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = "${pkgs.headsetcontrol}/bin/headsetcontrol -l 0 -s 0";
    };
  };

  systemd.timers.headset-led-off = {
    description = "Timer para apagar LEDs del Headset cada 30s";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1m";
      OnUnitActiveSec = "30s";
      Unit = "headset-led-off.service";
    };
  };

  # ---------------------------------------------------------
  # 5. CONTROL GPU (LACT)
  # ---------------------------------------------------------
  systemd.packages = [ pkgs.lact ];
  systemd.services.lactd.wantedBy = [ "multi-user.target" ];

  system.stateVersion = "25.11"; 
}
