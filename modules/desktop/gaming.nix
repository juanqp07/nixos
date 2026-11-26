{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:

{
  # GAMING Y MANDOS
  # ============================================================

  programs.steam = {
    enable = true;

    remotePlay.openFirewall = true;
    gamescopeSession.enable = true;
  };

  hardware.steam-hardware.enable = true;
  hardware.xpadneo.enable = true;

  services.ratbagd.enable = true;

  services.power-profiles-daemon.enable = true;
  services.fstrim.enable = true;

  programs.gamemode = {
    enable = true;
    enableRenice = true;

    settings.general = {
      desiredgov = "performance";
      defaultgov = "powersave";
      renice = 10;
      inhibit_screensaver = 1;
      reaper_freq = 5;
    };
  };

  # ============================================================
  # OBSERVABILIDAD, APPIMAGE Y RGB
  # ============================================================

  programs.obs-studio = {
    enable = true;
    enableVirtualCamera = false;
  };

  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  services.hardware.openrgb.enable = true;

  # ============================================================
  # MEMORIA Y SCHEDULER
  # ============================================================

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    # Usa el default upstream del módulo NixOS (50 %); Titan lo sobrescribe.
  };

  # scx-loader sustituye al módulo services.scx eliminado en nixpkgs.
  # Gaming es el default compartido; Elytra selecciona Auto en su host.
  services.scx-loader = {
    enable = true;

    config = {
      default_sched = "scx_cosmos";
      default_mode = lib.mkDefault "Gaming";
    };
  };

  boot.kernel.sysctl = {
    # vm.max_map_count ya usa el valor 1048576 predeterminado en este pin NixOS.
    # vm.swappiness y vm.page-cluster se definen en el módulo común.
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 1024;
  };

  # ============================================================

}
