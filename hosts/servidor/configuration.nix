{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # --- KERNEL, CGROUPS Y RENDIMIENTO ---
  boot.kernelPackages = pkgs.linuxPackages_latest;
  hardware.enableRedistributableFirmware = true;
  boot.kernelParams = [
    "systemd.unified_cgroup_hierarchy=1"
    "cgroup_no_v1=all"
    "i915.enable_guc=3"
  ];
  boot.kernel.sysctl = {
    "net.core.default_qdisc" = "cake";
    "net.ipv4.tcp_congestion_control" = "bbr";

    "vm.swappiness" = 10;         # evitar swap agresivo
    "fs.file-max" = 200000;      # aumentar límite de ficheros abiertos

    "net.core.rmem_max" = 16777216; # 16MB
    "net.core.wmem_max" = 16777216; # 16MB
    "net.core.netdev_max_backlog" = 250000;
  };

  # --- RED ---
  networking.networkmanager.enable = true;
  networking.hostName = "atlas";

  # --- DOCKER Y CONTENEDORES ---
  virtualisation.docker = {
    enable = true;
    daemon = {
      settings = {
        # claves con guiones es más seguro escribirlas como strings
        "storage-driver" = "overlay2";
        "log-driver"     = "journald";
      };
    };
  };

  # --- DOCKGE ---
  virtualisation.oci-containers.backend = "docker";
  virtualisation.oci-containers.containers.dockge = {
    image = "cmcooper1980/dockge:latest"; 
    autoStart = true;
    ports = [ "5001:5001" ];
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock"
      "/mnt/datos/AppData/dockge/data:/app/data"
      "/mnt/datos/AppData/dockge/stacks:/opt/stacks"
    ];
    environment = {
      DOCKGE_STACKS_DIR = "/opt/stacks";
    };
  };

  systemd.tmpfiles.rules = [
    "d /mnt/datos/AppData/dockge/data 0755 juan users -"
    "d /mnt/datos/AppData/dockge/stacks 0755 juan users -"
  ];
  # --- ZRAM ---
  zramSwap = {
    enable = true;
    algorithm = "lz4";
    memoryPercent = 75;
    priority = 100;
   };


  # --- GPU / VA-API (Intel iGPU) ---
  services.xserver.videoDrivers = [ "modesetting" ];
  
  hardware.graphics = {
    enable = true;
    # Paquetes recomendados por la wiki + utilidades de comprobación
    extraPackages = with pkgs; [
      intel-media-driver   # VA-API (iHD) userspace - necesario para Quick Sync / VAAPI
      vpl-gpu-rt           # oneVPL (QSV runtime) - recomendado para GPUs modernas
      libva-utils          # utilidades (vainfo) -> prueba/diagnóstico (opcional pero útil)
      intel-compute-runtime # opcional: OpenCL / Level Zero si necesitas compute
    ];
  };

  hardware.opengl = {
    enable = true;        # obliga a crear /run/opengl-driver con libs/icd
    driSupport = true;    # soporte DRI (necesario para /dev/dri)
    extraPackages = with pkgs; [
      vulkan-loader       # loader ICD para Vulkan
      vulkan-tools        # vulkaninfo, vkcube (pruebas)
      intel-graphics-compiler  # opcional: compilador Intel (ayuda a ecosistema)
      # intel-compute-runtime   # opcional: si también quieres OpenCL/Level Zero (compute)
    ];
  };

  # --- USUARIOS ---
  users.users.juan = {
    isNormalUser = true;
    extraGroups = [ "docker" "video" "render" "dialout" ];
  };

  # --- ALMACENAMIENTO ---
  fileSystems."/mnt/datos" = {
    device = "/dev/disk/by-uuid/d1908c00-4835-41fd-851b-cb2903898ec7";
    fsType = "ext4";
    options = [ "defaults" "nofail" "noatime" ];
  };

  # --- HERRAMIENTAS DE SISTEMA / MONITORIZACIÓN ---
  environment.systemPackages = with pkgs; [
    vim htop ncdu iotop ethtool smartmontools zram-generator
  ];

  services.thermald.enable = true;
  system.stateVersion = "25.11";
}
