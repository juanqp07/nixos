{ lib, pkgs, ... }:

let
  privacyGrabber = ../scripts/rustdesk-privacy-grabber.py;
  privacyMonitor = ../scripts/rustdesk-privacy-monitor.py;

  privacyCli = pkgs.writeShellApplication {
    name = "rustdesk-privacy";
    runtimeInputs = [
      pkgs.systemd
      pkgs.libnotify
      pkgs.util-linux
    ];
    text = builtins.readFile ../scripts/rustdesk-privacy.sh;
  };

  privacyMonitorCli = pkgs.writeShellApplication {
    name = "rustdesk-privacy-watcher";
    runtimeInputs = [
      pkgs.dbus
      pkgs.systemd
      privacyCli
    ];
    text = "${pkgs.python3}/bin/python3 ${privacyMonitor}";
  };
in
{
  # Solo se importa en Elytra desde flake.nix.
  environment.systemPackages = [ privacyCli ];

  # El proceso privilegiado solo mantiene abiertos los event nodes físicos.
  # RustDesk crea sus dispositivos remotos mediante uinput, que el helper excluye.
  systemd.services.rustdesk-privacy-grabber = {
    description = "RustDesk physical input and screen privacy mode";
    after = [ "systemd-udevd.service" ];
    wants = [ "systemd-udevd.service" ];

    path = [ pkgs.brightnessctl ];

    serviceConfig = {
      Type = "notify";
      NotifyAccess = "main";
      User = "root";
      Group = "root";

      ExecStart = "${pkgs.python3}/bin/python3 ${privacyGrabber} --daemon";
      ExecStopPost = "${pkgs.python3}/bin/python3 ${privacyGrabber} --restore";

      TimeoutStartSec = "30s";
      TimeoutStopSec = "10s";
      Restart = "no";
      UMask = "0077";

      # Hardening compatible con acceso a /dev/input y retroiluminación sysfs.
      ProtectSystem = "full";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = [ "AF_UNIX" ];
      LockPersonality = true;
    };
  };

  # juan solo puede iniciar/detener esta unidad concreta; no obtiene permisos
  # generales para administrar servicios del sistema.
  security.polkit.enable = true;
  security.polkit.extraConfig = lib.mkAfter ''
    polkit.addRule(function(action, subject) {
      if (subject.user === "juan" &&
          action.id === "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") === "rustdesk-privacy-grabber.service" &&
          (action.lookup("verb") === "start" || action.lookup("verb") === "stop")) {
        return polkit.Result.YES;
      }
    });
  '';

  # Lanzador accesible desde el menú de aplicaciones y atajo global de KDE.
  # En Plasma 6 Wayland, el atajo se termina de registrar al iniciar sesión.
  home-manager.users.juan = { pkgs, lib, ... }: {
    xdg.dataFile."applications/org.kde.rustdesk-privacy.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Privacidad de RustDesk
      Comment=Apaga la pantalla física y bloquea los controles locales
      Exec=${privacyCli}/bin/rustdesk-privacy toggle
      Icon=preferences-desktop-screenlocking
      Terminal=false
      StartupNotify=false
      X-KDE-GlobalAccel-CommandShortcut=true
    '';

    home.activation.registerRustDeskPrivacyShortcut =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 \
          --file kglobalshortcutsrc \
          --group services \
          --group org.kde.rustdesk-privacy.desktop \
          --key _launch \
          "Ctrl+Alt+P,none,Privacidad de RustDesk"
      '';
  };
}
