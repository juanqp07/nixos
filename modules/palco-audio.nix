{ config, pkgs, lib, ... }:

{
  # ============================================================
  # PALCO-AUDIO — Pi 4B como receptor Bluetooth A2DP -> jack 3.5mm
  #
  # Cadena: Móvil (A2DP Source SBC) -> BlueZ (Sink) -> PipeWire ->
  #           DSP universal [HPF -> Compresor -> Limiter] -> jack.
  #
  # DISEÑO:
  # - Anti-apagón: reconexión activa + backup de claves BT.
  # - Universal: un solo perfil DSP que protege cualquier altavoz
  #   sin bajar el volumen máximo (limiter, no reductor).
  # - Fail-open: si el DSP falla, el audio sigue directo al jack.
  #
  # NOTA HONESTA: el jack integrado es PWM ~11 bits. El DSP evita
  # saturación y protege, pero no convierte el PWM en HiFi.
  # ============================================================

  # --- BLUETOOTH: A2DP sink siempre visible y re-conectable ---
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Name = "palco";
        # Clase: Audio Service + Audio/Video Major + Loudspeaker.
        Class = "0x200414";
        # BR/EDR clásico (A2DP). "le" dejaría sin música.
        ControllerMode = "bredr";
        FastConnectable = true;
        # 0 = visible/emparejable siempre (instalación fija).
        DiscoverableTimeout = 0;
        PairableTimeout = 0;
        AlwaysPairable = true;
        # "off" evita que el RPA rompa reconexión/discoverable.
        Privacy = "off";
        JustWorksRepairing = "always";
        Experimental = true;
      };
      Policy = {
        AutoEnable = true;
        ReconnectAttempts = 7;
        ReconnectIntervals = "1,2,4,8,16,32,64";
      };
    };
  };

  # Agente de emparejamiento persistente: acepta móviles sin PIN.
  # (bluetoothctl --agent es volátil; esto sobrevive reinicios.)
  systemd.services.bt-agent = {
    description = "Agente auto-pairing Bluetooth (NoInputNoOutput)";
    after = [ "bluetooth.service" ];
    partOf = [ "bluetooth.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.bluez-tools}/bin/bt-agent -c NoInputNoOutput";
      Restart = "always";
      RestartSec = 5;
    };
  };

  # Repone discoverable+pairable en cada arranque (main.conf solo
  # no basta tras reboot).
  systemd.services.palco-bt-discoverable = {
    description = "Palco: BT visible y emparejable tras arranque";
    after = [
      "bluetooth.service"
      "bt-agent.service"
    ];
    requires = [ "bluetooth.service" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [
      bluez
      bluez-tools
    ];
    script = ''
      for i in $(seq 1 30); do
        bluetoothctl show >/dev/null 2>&1 && break
        sleep 2
      done
      printf 'power on\ndiscoverable on\npairable on\n' | bluetoothctl
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  # Reconexión ACTIVA: si no hay enlace A2DP, la Pi llama de vuelta
  # a los móviles emparejados. Tras un apagón la música vuelve sola
  # sin tocar el móvil (el fallo que había en Ubuntu).
  systemd.services.palco-bt-reaffirm = {
    description = "Palco: re-afirma BT y reconecta a móviles emparejados";
    after = [
      "bluetooth.service"
      "bt-agent.service"
    ];
    path = with pkgs; [
      bluez
      bluez-tools
      coreutils
      gnugrep
    ];
    script = ''
      bluetoothctl show 2>/dev/null | grep -q "Powered: yes" \
        || printf 'power on\n' | bluetoothctl >/dev/null
      printf 'discoverable on\npairable on\n' | bluetoothctl >/dev/null
      bluetoothctl paired-devices 2>/dev/null | while read -r _ mac _rest; do
        [ -n "$mac" ] || continue
        if ! bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
          timeout 20 bluetoothctl connect "$mac" >/dev/null 2>&1 || true
        fi
      done
    '';
    serviceConfig = {
      Type = "oneshot";
    };
  };

  systemd.timers.palco-bt-reaffirm = {
    description = "Palco: re-afirma BT cada 2 minutos";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "2min";
    };
  };

  # Backup/restore de claves de emparejamiento: BlueZ las escribe sin
  # fsync atómico; un corte a mitad de escritura las deja truncadas.
  # Al arrancar: si no hay claves válidas pero sí backup, restaura.
  # Si hay claves y no hay backup, lo crea (primer estado bueno).
  systemd.services.palco-bt-backup = {
    description = "Palco: protege claves de emparejamiento Bluetooth";
    before = [ "bluetooth.service" ];
    wantedBy = [ "multi-user.target" ];
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
        # Hay claves válidas: asegurar backup al día.
        tar -czf "$BACKUP" -C /var/lib bluetooth
        sync
      elif [ -f "$BACKUP" ]; then
        # Claves perdidas/corruptas: restaurar último estado bueno.
        tar -xzf "$BACKUP" -C /var/lib
        sync
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  # --- AUDIO: PipeWire headless (nada de PulseAudio) ---
  services.pulseaudio.enable = lib.mkForce false;
  security.rtkit.enable = true;

  # LV2 visibles para el daemon (imprescindible en headless).
  services.pipewire.extraLv2Packages = [ pkgs.lsp-plugins ];

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;

    # Reloj fijo 48kHz + remuestreo decente: evita reconversiones
    # entre SBC (44.1/48kHz) y el DAC.
    extraConfig.pipewire."20-palco-clock" = {
      "context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.allowed-rates" = [
          44100
          48000
        ];
        "resample.quality" = 5;
      };
    };

    # DSP UNIVERSAL: HPF 80Hz -> compresor 2:1 -> limiter -1dBFS.
    # Símbolos verificados contra lsp-plugins 1.2.35 (.ttl):
    #  - filter_stereo: ft=1 (Hi-pass), f en Hz, s=1 (24dB/oct).
    #  - compressor_stereo: al en ganancia lineal (0.1585=-16dB),
    #    cr=ratio, at/rt en ms, mk=makeup (1.0=sin cambios).
    #  - limiter_stereo: th en ganancia lineal (0.8913=-1dBFS),
    #    lk=lookahead en ms. boost/ALR en default (maximiza sin
    #    pasar el techo). ovs off por defecto (ahorra CPU en la Pi).
    # ifexists+nofail = fail-open: si el DSP falla, PipeWire arranca
    # igual y el audio va directo al jack.
    extraConfig.pipewire."50-palco-dsp" = {
      "context.modules" = [
        {
          name = "libpipewire-module-filter-chain";
          flags = [
            "ifexists"
            "nofail"
          ];
          args = {
            "node.description" = "palco DSP";
            "media.name" = "palco-dsp";
            "filter.graph" = {
              nodes = [
                {
                  type = "lv2";
                  name = "hpf";
                  plugin = "http://lsp-plug.in/plugins/lv2/filter_stereo";
                  control = {
                    "ft" = 1;
                    "f" = 80.0;
                    "s" = 1;
                  };
                }
                {
                  type = "lv2";
                  name = "comp";
                  plugin = "http://lsp-plug.in/plugins/lv2/compressor_stereo";
                  control = {
                    "al" = 0.158489;
                    "cr" = 2.0;
                    "at" = 20.0;
                    "rt" = 150.0;
                    "mk" = 1.0;
                  };
                }
                {
                  type = "lv2";
                  name = "lim";
                  plugin = "http://lsp-plug.in/plugins/lv2/limiter_stereo";
                  control = {
                    "th" = 0.891251;
                    "lk" = 5.0;
                  };
                }
              ];
              links = [
                {
                  output = "hpf:out_l";
                  input = "comp:in_l";
                }
                {
                  output = "hpf:out_r";
                  input = "comp:in_r";
                }
                {
                  output = "comp:out_l";
                  input = "lim:in_l";
                }
                {
                  output = "comp:out_r";
                  input = "lim:in_r";
                }
              ];
              inputs = [
                "hpf:in_l"
                "hpf:in_r"
              ];
              outputs = [
                "lim:out_l"
                "lim:out_r"
              ];
            };
            "capture.props" = {
              "media.class" = "Audio/Sink";
            };
            "playback.props" = {
              "node.passive" = true;
            };
          };
        }
      ];
    };

    # Política BT modo bolo: máxima estabilidad.
    # Solo SBC (+AAC para iPhone). SBC-XQ OFF: ~70% más payload =
    # cortes al límite de alcance. Lo que no se corta suena mejor.
    wireplumber.extraConfig."51-palco-bluetooth" = {
      "wireplumber.settings" = {
        "bluetooth.autoswitch-to-headset-profile" = false;
      };
      "monitor.bluez.properties" = {
        "bluez5.roles" = [
          "a2dp_sink"
          "a2dp_source"
        ];
        "bluez5.enable-sbc-xq" = false;
        "bluez5.enable-hw-volume" = true;
        "bluez5.codecs" = [
          "sbc"
          "aac"
        ];
      };
    };
  };

  # El DSP como sink por defecto (si existe; si no, no toca nada y
  # el audio sigue directo al jack = fail-open también aquí).
  systemd.user.services.palco-dsp-default = {
    description = "Palco: DSP como salida por defecto si existe";
    after = [
      "pipewire.service"
      "wireplumber.service"
    ];
    wantedBy = [ "pipewire.service" ];
    path = with pkgs; [
      wireplumber
      coreutils
      gnugrep
      gawk
      gnused
    ];
    script = ''
      for i in $(seq 1 30); do
        ID=$(wpctl status 2>/dev/null | grep -i "palco DSP" | head -1 | awk '{print $2}' | tr -d '.,:')
        if [ -n "$ID" ]; then
          wpctl set-default "$ID" || true
          exit 0
        fi
        sleep 2
      done
      exit 0
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  # PipeWire/WirePlumber de usuario sin sesión gráfica (headless).
  users.users.juan.linger = true;

  # Jack PWM clipea al 100%: fijar ~80% en cada arranque.
  # (El limiter digital no protege de saturación analógica posterior.)
  systemd.services.palco-jack-level = {
    description = "Palco: nivel jack ~80% (evita clipping PWM)";
    after = [ "sound.target" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ alsa-utils ];
    script = ''
      for ctl in Headphone PCM Master; do
        amixer -q -c 0 sset "$ctl" 80% unmute 2>/dev/null || true
      done
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  # --- HERRAMIENTAS ---
  environment.systemPackages = with pkgs; [
    bluez
    bluez-tools
    alsa-utils
    pipewire
    wireplumber
    util-linux # aporta `rfkill` para el modo bolo
    lsp-plugins
    lv2 # lv2ls/lv2info para verificar el DSP en la Pi
  ];

  # --- MODO BOLO (sin internet) / MODO CONFIG / DIAGNÓSTICO ---
  # En bolo: WiFi apagada = +estabilidad BT en 2.4GHz.
  environment.shellAliases = {
    palco-bolo = "sudo rfkill block wifi && printf 'power on\\ndiscoverable on\\npairable on\\n' | bluetoothctl";
    palco-config = "sudo rfkill unblock wifi && echo 'WiFi activada: usa nmtui para configurar red'";
    palco-estado = "bluetoothctl show && echo '---' && wpctl status | grep -Ei 'palco|alsa|bluez' ; echo '---' && systemctl --no-pager --failed";
    palco-dsp-check = "wpctl status | grep -i dsp ; echo '---' ; pw-dump 2>/dev/null | grep -o 'palco-dsp[^\\\"]*' | sort -u ; echo '--- (si no sale nada, el DSP no cargó: el audio sigue directo al jack)'";
  };

  # ============================================================
  # MEJORA FUTURA (2 líneas cuando quieras): HAT I2S HiFiBerry/DAC+
  # 1. hardware.raspberry-pi."4".audio.enable = lib.mkForce false;
  # 2. hardware.raspberry-pi.configtxt.settings.all.dtoverlay = [ "hifiberry-dacplus" ];
  #    (o "-std/-pro/-hd/-adc/-digi" según modelo; con kernel>=6.1.77
  #    el "-std" también vale). Requiere caja alta + RCA corto a DI.
  # ============================================================
}
