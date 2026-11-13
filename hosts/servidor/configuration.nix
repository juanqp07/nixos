{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/atlas-docker.nix
  ];

  # --- KERNEL, CGROUPS Y RENDIMIENTO ---
  # cgroupv1 eliminado en kernel 6.x: no se fuerzan flags obsoletos.
  # Servidor: intel_pstate/HWP con governor powersave; irqbalance distribuye
  # interrupciones entre los P-cores/E-cores del i5-1250P. No se fuerza performance.
  boot.kernelPackages = pkgs.linuxPackages;
  hardware.enableRedistributableFirmware = true;

  # En Alder Lake, intel_pstate usa el modo activo por defecto cuando HWP está
  # disponible; no hace falta forzarlo con intel_pstate=active.
  # Servidor: intel_pstate+HWP escala solo (powersave + EPP balance_performance
  # por defecto): 400MHz en idle (fresco/silencioso) y turbo bajo carga.
  # Rendimiento bajo demanda sin el ruido/consumo del governor fijo.
  powerManagement.cpuFreqGovernor = "powersave";
  services.irqbalance.enable = true;

  # --- RED ---
  # NetworkManager ya se habilita en modules/common-system.nix.
  networking.hostName = "atlas";

  # Prioriza los servicios Docker permanentes frente a compilaciones del sistema.
  nix.settings = {
    max-jobs = 3;
    cores = 2;
  };

  # Docker usa journald como backend; limita el espacio de los registros persistentes.
  services.journald.extraConfig = ''
    SystemMaxUse=1G
    MaxRetentionSec=2week
  '';

  # Red privada con el resto de máquinas (interfaz wt0).
  services.netbird.enable = true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 8384 21115 21116 21117 21118 21119 22000 8621 25565 ];
    allowedUDPPorts = [ 21027 21116 22000 8621 ];
    # El DNS de AdGuard se publica desde Docker y pasa por FORWARD/DOCKER-USER,
    # no por INPUT. No abrir 53 en el firewall del host si no hay un DNS nativo.

    trustedInterfaces = [ "wt0" ];
    checkReversePath = "loose";
    # NOTA: no se usa extraCommands con iptables manual (duplicaba allowed*Ports
    # y docker escribe sus propias reglas de todas formas). Si quieres restringir
    # a LAN, filtra por interfaz con interfaces.wt0.allowed* en vez de global.
  };

  services.fail2ban = {
    enable = true;

    maxretry = 3;
    bantime = "24h";

    bantime-increment = {
      enable = true;
      rndtime = "15m";
      overalljails = true;
      maxtime = "90d";
      multipliers = "1 2 4 8 16 32 64";
    };

    jails = {
      sshd = {
        enabled = true;
        filter = "sshd[mode=aggressive]";

        settings = {
          maxretry = 3;
          findtime = "10m";
        };
      };
    };
  };
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    # Servidor secundario: login con contraseña permitido (igual que pico).
    settings.PasswordAuthentication = true;
  };
  # --- DOCKER Y CONTENEDORES ---
  programs.gnupg.agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-curses;  # o pinentry-gtk2 si tienes GUI
  };
  # --- ZRAM ---
  zramSwap = {
    enable = true;
    algorithm = "lz4";
    memoryPercent = 75;
    priority = 100;
   };


  # --- GPU / VA-API (Intel iGPU, headless: solo transcodificación) ---
    hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
      intel-compute-runtime
    ];
  };

  environment.variables = {
    # LANG procede de i18n.defaultLocale en common-system.nix.
    LIBVA_DRIVER_NAME = "iHD";
  };

  # --- USUARIOS ---
  users.users.juan = {
    isNormalUser = true;
    # El grupo docker concede privilegios equivalentes a root; se mantiene porque
    # el flujo de administración de este homelab y sus herramientas lo requieren.
    extraGroups = [ "docker" "video" "render" "dialout" ];
  };

  # --- ALMACENAMIENTO ---
  fileSystems."/mnt/datos" = {
    device = "/dev/disk/by-uuid/d1908c00-4835-41fd-851b-cb2903898ec7";
    fsType = "ext4";
    options = [ "defaults" "nofail" "noatime" "x-systemd.automount" "x-systemd.device-timeout=5" ];
  };

  # El disco contiene datos persistentes de contenedores. Si no monta, no arranques
  # Docker: evitar que los bind mounts creen directorios vacíos en la raíz del sistema.
  systemd.services.docker.unitConfig.RequiresMountsFor = "/mnt/datos";

  # --- HERRAMIENTAS DE SISTEMA / MONITORIZACIÓN ---
  environment.systemPackages = with pkgs; [
    htop iotop ethtool smartmontools pass gnupg docker-credential-helpers
    intel-gpu-tools # intel_gpu_top: verificar QSV/iGPU en jellyfin/immich
    libva-utils # vainfo: comprobar VA-API antes de probar una transcodificación
    lazydocker # gestión TUI de los ~70 contenedores
  ];

  # --- ACTUALIZACIONES AUTOMÁTICAS ---
  # Este path usa el checkout local y el flake.lock presente en él. El timer NO
  # ejecuta git pull ni sincroniza /home/juan/nixos con GitHub: esa sincronización
  # debe hacerse y revisarse por separado antes de preparar una nueva generación.
  system.autoUpgrade = {
    enable = true;
    flake = "path:/home/juan/nixos#atlas";
    upgrade = false;
    operation = "boot";
    flags = [
      "-L"
      "--no-write-lock-file"
    ];
    # Prepara la generación fuera del horario de uso; se activa en el siguiente reinicio planificado.
    dates = "04:00";
    randomizedDelaySec = "45min";
  };

  services.thermald.enable = true;
  # SMART: aviso temprano de fallo de disco (complementa a beszel).
  services.smartd.enable = true;
  # TRIM semanal para el NVMe (desktops y titan ya lo tienen).
  services.fstrim.enable = true;
  system.stateVersion = "25.11";
}
