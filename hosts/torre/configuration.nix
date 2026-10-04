{ config, pkgs, lib, ... }: # Añadimos 'lib' aquí

{

  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "titan";
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # mitigations=off: +5-15% en juegos en Ryzen. Solo máquina personal,
  # nunca en servidores expuestos. Asumes riesgo Spectre/Meltdown.
  # amd_pstate activo (mejor que acpi-cpufreq en Zen 2/3 con kernel latest).
  boot.kernelParams = [
    "mitigations=off"
    "amd_pstate=active"
  ];

  # Permite construir la imagen SD de palco (aarch64) desde la torre.
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
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
  # scx/gamemode/zram/inotify/bluetooth heredados de desktop-gaming.nix
  # zram al 25%: con 32GB físicos, 50% (16GB) es excesivo y gasta CPU.
  # ---------------------------------------------------------
  zramSwap.memoryPercent = lib.mkForce 25;

  services.openssh.enable = true;

  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
  };
  services.avahi.publish.enable = true;
  services.avahi.publish.userServices = true;

  services.fstrim.enable = true;
  services.smartd.enable = true;

  environment.systemPackages = with pkgs; [
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
  # 5. MONTAR NVME
  # ---------------------------------------------------------
    
  fileSystems."/mnt/nvme" = {
    device = "/dev/disk/by-uuid/a8f2e7ba-5fe6-473d-82f6-ce00fae06297";
    fsType = "ext4";
    options = [ "defaults" "nofail" "noatime" "x-systemd.automount" "x-systemd.device-timeout=5" ];
  };


  # ---------------------------------------------------------
  # 5. CONTROL GPU (LACT)
  # ---------------------------------------------------------
  systemd.packages = [ pkgs.lact ];
  systemd.services.lactd.wantedBy = [ "multi-user.target" ];

  system.stateVersion = "25.11"; 
}
