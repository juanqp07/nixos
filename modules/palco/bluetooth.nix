{
  config,
  pkgs,
  lib,
  ...
}:

{
  # BLUETOOTH / BLUEZ
  # ------------------------------------------------------------

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;

    settings = {
      General = {
        # Nombre visible del receptor.
        Name = "palco";

        # Clase Bluetooth de dispositivo de audio.
        Class = "0x200414";

        # Solo Bluetooth clásico.
        # A2DP funciona sobre BR/EDR y no necesitamos BLE.
        ControllerMode = "bredr";

        # Facilita el establecimiento de la conexión.
        FastConnectable = true;

        # Receptor permanentemente visible y emparejable.
        DiscoverableTimeout = 0;
        PairableTimeout = 0;
        AlwaysPairable = true;

        # Configuración de privacidad sencilla para un appliance.
        Privacy = "off";

        # Permite reparar automáticamente emparejamientos JustWorks.
        JustWorksRepairing = "always";
      };

      Policy = {
        AutoEnable = true;

        # Reintentos de conexión progresivos.
        ReconnectAttempts = 7;
        ReconnectIntervals = "1,2,4,8,16,32,64";
      };
    };
  };

  # ------------------------------------------------------------
  # AGENTE BLUETOOTH
  # ------------------------------------------------------------

  # Agente permanente para dispositivos sin interacción
  # teclado/pantalla durante el emparejamiento.
  systemd.services.bt-agent = {
    description = "Palco: agente Bluetooth NoInputNoOutput";

    after = [
      "bluetooth.service"
    ];

    requires = [
      "bluetooth.service"
    ];

    partOf = [
      "bluetooth.service"
    ];

    wantedBy = [
      "multi-user.target"
    ];

    serviceConfig = {
      ExecStart = "${pkgs.bluez-tools}/bin/bt-agent -c NoInputNoOutput";

      Restart = "always";
      RestartSec = 3;
    };
  };

  # ------------------------------------------------------------
  # BLUETOOTH VISIBLE / EMPAREJABLE
  # ------------------------------------------------------------

  systemd.services.palco-bt-discoverable = {
    description = "Palco: Bluetooth visible y emparejable";

    after = [
      "bluetooth.service"
      "bt-agent.service"
    ];

    requires = [
      "bluetooth.service"
    ];

    wantedBy = [
      "multi-user.target"
    ];

    path = with pkgs; [
      bluez
      bluez-tools
      coreutils
      util-linux
    ];

    script = ''
      rfkill unblock bluetooth 2>/dev/null || true

      for i in $(seq 1 30); do
        if bluetoothctl show >/dev/null 2>&1; then
          break
        fi

        sleep 2
      done

      printf 'power on\ndiscoverable on\npairable on\n' \
        | bluetoothctl >/dev/null 2>&1 || true
    '';

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  # ------------------------------------------------------------
  # BACKUP DE CLAVES BLUETOOTH
  # ------------------------------------------------------------

  # Protege los emparejamientos frente a problemas de la
  # microSD o una reinstalación accidental.
  systemd.services.palco-bt-backup = {
    description = "Palco: backup de claves Bluetooth";

    before = [
      "bluetooth.service"
    ];

    wantedBy = [
      "multi-user.target"
    ];

    path = with pkgs; [
      coreutils
      gnutar
      gzip
      gnugrep
    ];

    script = ''
      BACKUP=/var/lib/palco/bluetooth-backup.tgz

      mkdir -p /var/lib/palco

      if grep -rq "LinkKey" /var/lib/bluetooth/ 2>/dev/null; then
        tar -czf "$BACKUP" -C /var/lib bluetooth
        sync

      elif [ -f "$BACKUP" ]; then
        tar -xzf "$BACKUP" -C /var/lib
        sync
      fi
    '';

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  # ------------------------------------------------------------

}
