{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:

{
  # ============================================================
  # ARRANQUE Y KERNEL
  # ============================================================

  # "splash" lo añade boot.plymouth y "loglevel" boot.consoleLogLevel (0).
  boot.kernelParams = [
    "quiet"
    "rd.systemd.show_status=false"
    "rd.udev.log_level=3"
    "udev.log_priority=3"
  ];

  boot.loader.timeout = 0;

  services.cloudflare-warp.enable = true;
  boot.plymouth.enable = true;

  # Acelerar arranque: no esperar a que la red esté online ni a udev-settle.
  systemd.services.NetworkManager-wait-online.enable = false;
  systemd.services.systemd-udev-settle.enable = false;

  # ESP de 1 GB: limita las generaciones en /boot para que no se llene (kernel latest + initrd con firmware GPU).
  boot.loader.systemd-boot.configurationLimit = 8;

  boot.consoleLogLevel = 0;

  services.netbird.enable = true;

  # NetBird/WARP pueden crear rutas asimétricas; mantenemos validación de origen
  # sin exigir que cada paquete vuelva por la misma interfaz.
  networking.firewall.checkReversePath = "loose";

  # SSH permanece habilitado para administración remota; bloquea intentos repetidos.
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    jails.sshd = {
      enabled = true;
      settings = {
        # El filtro va en settings: la opción jails.<n>.filter de nixpkgs
        # descarta el valor de texto y usaría "sshd" sin el modo aggressive.
        filter = "sshd[mode=aggressive]";
        maxretry = 5;
        findtime = "10m";
      };
    };
  };

  # Evita que los registros de escritorio ocupen disco sin límite.
  services.journald.settings.Journal = {
    SystemMaxUse = "512M";
    MaxRetentionSec = "2week";
  };

  # ============================================================
  # COMPATIBILIDAD CON CLINE CLI EN NIXOS
  # ============================================================

  # Cline CLI espera encontrar Bash en /bin/bash.
  # NixOS crea /bin/sh, pero no garantiza que exista /bin/bash.
  # Creamos un enlace al Bash de Nix después de la activación
  # del script binsh de NixOS, conservando /bin/sh intacto.
  system.activationScripts.cline-bash-compat = {
    deps = [ "binsh" ];
    text = ''
      ln -sfn "${pkgs.bashInteractive}/bin/bash" /bin/bash
    '';
  };

  # ============================================================
  # IMPRESIÓN Y SINCRONIZACIÓN
  # ============================================================

  services.printing.enable = true;

  services.syncthing = {
    enable = true;
    user = "juan";

    # Directorio base para las carpetas sincronizadas.
    dataDir = "/home/juan";

    # Configuración y claves de Syncthing.
    configDir = "/home/juan/.config/syncthing";

    openDefaultPorts = true;

    extraFlags = [
      "--no-browser"
    ];
  };

  # ============================================================

}
