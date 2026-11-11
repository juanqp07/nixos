{ config, pkgs, lib, ... }: # Añadimos 'lib' aquí

{

  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "titan";

  # La torre tiene más margen térmico y 32 GiB; permite paralelismo moderado sin saturar sus 12 hilos.
  nix.settings = {
    max-jobs = 6;
    cores = 2;
  };
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Mantener mitigaciones de CPU activadas: el aumento de rendimiento al
  # desactivarlas depende de la carga y no justifica asumirlo sin benchmarks.
  # amd_pstate activo usa el control CPPC/EPP de Ryzen cuando el firmware lo soporta.
  boot.kernelParams = [
    "amd_pstate=active"
  ];

  # Permite construir la imagen SD de palco (aarch64) desde la torre.
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
  # ---------------------------------------------------------
  # 1. OPTIMIZACIÓN CPU (Ryzen 5 5600X)
  # ---------------------------------------------------------
  # ---------------------------------------------------------
  # 2. GRÁFICOS Y GPU (Radeon RX 6700 XT)
  # ---------------------------------------------------------
  hardware.amdgpu = {
    initrd.enable = true; # carga amdgpu en el initrd (antes: boot.initrd.kernelModules)
    opencl.enable = true; # ROCm OpenCL (antes: rocmPackages.clr y clr.icd a mano)
  };
  services.xserver.videoDrivers = [ "amdgpu" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  environment.variables = {
    "HSA_OVERRIDE_GFX_VERSION" = "10.3.0";
  };

  # ---------------------------------------------------------
  # 3. SERVICIOS Y PAQUETES
  # scx/gamemode/zram/inotify/bluetooth heredados de desktop-gaming.nix
  # zram al 25%: con 32GB físicos, 50% (16GB) es excesivo y gasta CPU.
  # ---------------------------------------------------------
  # 25 % de capacidad máxima: 8 GiB sobre 32 GiB de RAM, sin reserva física al arranque.
  zramSwap.memoryPercent = 25;

  services.openssh.enable = true;

  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
  };

  # fstrim está habilitado en desktop-gaming.nix.
  services.smartd.enable = true;

  environment.systemPackages = with pkgs; [
    # JDK 25: requerido por horizon-prepare y otras herramientas que fijan esta versión.
    temurin-bin-25
    headsetcontrol
    lunar-client
    clinfo
    vulkan-tools
    amdgpu_top

    # Aplicación declarativa compartida con Elytra.
    (callPackage ../../packages/nori.nix { })
    # Cliente de terminal de Nori.
    (callPackage ../../packages/nori-cli.nix { })
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
  # 5. SSD DE JUEGOS (1 TB, ext4)
  # ---------------------------------------------------------

  fileSystems."/mnt/juegos" = {
    device = "/dev/disk/by-uuid/c1e5373f-923c-4cad-98fa-187a01897700";
    fsType = "ext4";
    options = [ "defaults" "noatime" ];
  };

  # Preparar las bibliotecas y garantizar que juan pueda escribir en ellas.
  # tmpfiles se ejecuta después de montar los sistemas de archivos locales.
  systemd.tmpfiles.rules = [
    # Crear los directorios si faltan.
    "d /mnt/juegos 0775 juan users -"
    "d /mnt/juegos/Games 0775 juan users -"
    "d /mnt/juegos/Games/Steam 0775 juan users -"
    "d /mnt/juegos/Games/Heroic 0775 juan users -"
    "d /mnt/juegos/Downloads 0775 juan users -"
    "d /mnt/juegos/Data 0775 juan users -"

    # Corregir también propietario y permisos si los directorios ya existían.
    "z /mnt/juegos 0775 juan users -"
    "z /mnt/juegos/Games 0775 juan users -"
    "z /mnt/juegos/Games/Steam 0775 juan users -"
    "z /mnt/juegos/Games/Heroic 0775 juan users -"
    "z /mnt/juegos/Downloads 0775 juan users -"
    "z /mnt/juegos/Data 0775 juan users -"
  ];


  # ---------------------------------------------------------
  # 5. CONTROL GPU (LACT)
  # ---------------------------------------------------------
  # El módulo services.lact instala el paquete y arranca lactd (antes se hacía a mano).
  services.lact.enable = true;

  # En AMD hace falta para que LACT pueda aplicar overclock/undervolt (requiere reiniciar;
  # el kernel puede marcarse como alterado, como con cualquier modo overdrive).
  hardware.amdgpu.overdrive.enable = true;

  # GameMode necesita este grupo para autorizar cambios temporales de governor y split-lock.
  users.users.juan.extraGroups = [ "gamemode" ];

  system.stateVersion = "25.11"; 
}
