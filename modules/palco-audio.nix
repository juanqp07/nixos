{ config, pkgs, lib, ... }:

{
  # ============================================================
  # PALCO-AUDIO
  #
  # Raspberry Pi 4B como receptor Bluetooth A2DP
  # con salida analógica por jack 3.5 mm.
  #
  # Móvil
  #   -> Bluetooth A2DP Source
  #   -> BlueZ
  #   -> PipeWire
  #   -> WirePlumber
  #   -> DSP
  #   -> ALSA
  #   -> Jack 3.5 mm
  #
  # DSP:
  #   HPF 45 Hz
  #   -> Compresor suave
  #   -> Limiter -1 dBFS
  # ============================================================

  # ------------------------------------------------------------
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
      ExecStart =
        "${pkgs.bluez-tools}/bin/bt-agent -c NoInputNoOutput";

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
  # PIPEWIRE
  # ------------------------------------------------------------

  services.pulseaudio.enable = lib.mkForce false;

  # RTKit para planificación realtime.
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;

    # En una máquina headless queremos que PipeWire arranque
    # inmediatamente al iniciar los servicios del usuario.
    socketActivation = false;

    # Audio real mediante PipeWire.
    audio.enable = true;

    alsa = {
      enable = true;
      support32Bit = false;
    };

    # Compatibilidad con aplicaciones PulseAudio.
    pulse.enable = true;

    wireplumber.enable = true;

    # Plugins LV2 usados por el DSP.
    extraLv2Packages = [
      pkgs.lsp-plugins
    ];

    # ----------------------------------------------------------
    # RELOJ / RENDIMIENTO
    # ----------------------------------------------------------

    extraConfig.pipewire."20-palco-clock" = {
      "context.properties" = {
        # Frecuencia interna preferida.
        "default.clock.rate" = 48000;

        # Mantener compatibilidad con música 44.1 kHz.
        "default.clock.allowed-rates" = [
          44100
          48000
        ];

        # Buena calidad de remuestreo sin cargar demasiado la Pi.
        "resample.quality" = 5;

        # Buffer conservador para maximizar estabilidad.
        "default.clock.quantum" = 1024;
        "default.clock.min-quantum" = 512;
        "default.clock.max-quantum" = 2048;
      };
    };

    # ----------------------------------------------------------
    # DSP
    # ----------------------------------------------------------

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
              # Cadena TRANSPARENTE: solo dinámica, cero ecualización.
              # El tono (graves/agudos) lo decide el móvil; aquí solo
              # se nivela y se ponen techo anti-saturación.
              nodes = [
                {
                  type = "lv2";
                  name = "comp";

                  plugin =
                    "http://lsp-plug.in/plugins/lv2/compressor_stereo";

                  control = {
                    # -12 dBFS.
                    "al" = 0.251189;

                    # 1.5:1, transparente.
                    "cr" = 1.5;

                    # Ataque 30 ms: deja pasar transitorios
                    # (bombo/caja intactos = calidad percibida).
                    "at" = 30.0;

                    # Release 200 ms.
                    "rt" = 200.0;

                    # Makeup +4 dB (= 1.584893 lineal): devuelve el
                    # nivel para que no suene más bajo que en directo.
                    # 0 dBFS -> -12+8 = -4, +4 = 0 -> el limiter
                    # lo deja en -1 dBFS.
                    "mk" = 1.584893;
                  };
                }

                {
                  type = "lv2";
                  name = "lim";

                  plugin =
                    "http://lsp-plug.in/plugins/lv2/limiter_stereo";

                  control = {
                    # Techo -1 dBFS.
                    "th" = 0.891251;

                    # Lookahead 5 ms.
                    "lk" = 5.0;

                    # ALR lento: nivela temas flojos/fuertes
                    # sin bombeo.
                    "alr_at" = 50.0;
                    "alr_rt" = 300.0;
                  };
                }
              ];

              links = [
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
                "comp:in_l"
                "comp:in_r"
              ];

              outputs = [
                "lim:out_l"
                "lim:out_r"
              ];
            };

            # Entrada virtual del DSP.
            "capture.props" = {
              "node.name" = "palco_dsp_input";
              "node.description" = "Palco DSP Input";
              "media.class" = "Audio/Sink";

              "audio.channels" = 2;

              "audio.position" = [
                "FL"
                "FR"
              ];
            };

            # Salida física del DSP.
            "playback.props" = {
              "node.name" = "palco_dsp_output";
              "node.description" = "Palco DSP Output";

              # Permite que WirePlumber lo conecte
              # automáticamente a la salida física.
              "node.passive" = true;

              "audio.channels" = 2;

              "audio.position" = [
                "FL"
                "FR"
              ];
            };
          };
        }
      ];
    };

    # ----------------------------------------------------------
    # WIREPLUMBER / BLUETOOTH A2DP
    # ----------------------------------------------------------

    wireplumber.extraConfig = {
      "10-palco-headless" = {
        "wireplumber.profiles" = {
          main = {
            # No depender de seat/session monitoring gráfico.
            "monitor.bluez.seat-monitoring" = "disabled";
          };
        };
      };

      "51-palco-bluetooth" = {
        "wireplumber.settings" = {
          # Nunca pasar automáticamente a HFP/HSP.
          # Conservamos exclusivamente audio de alta fidelidad.
          "bluetooth.autoswitch-to-headset-profile" = false;
          "bluetooth.profile-preference" = "quality";
        };

        "monitor.bluez.properties" = {
          "override.bluez5.roles" = [
            "a2dp_sink"
          ];

          "override.bluez5.codecs" = [
            "sbc"
            "sbc_xq"
            "aac"
          ];

          "bluez5.enable-sbc-xq" = true;
          "bluez5.enable-hw-volume" = true;
        };

        "monitor.bluez.rules" = [
          {
            matches = [
              {
                "device.name" = "~bluez_card.*";
              }
            ];

            actions = {
              "update-props" = {
                # Solo queremos reconectar A2DP.
                "bluez5.auto-connect" = [
                  "a2dp_sink"
                ];
              };
            };
          }
        ];
      };
    };
  };

  # ------------------------------------------------------------
  # ARRANQUE HEADLESS DE PIPEWIRE
  # ------------------------------------------------------------

  # Cuando socketActivation está desactivado, arrancamos
  # explícitamente los servicios al entrar en default.target.
  systemd.user.services.pipewire.wantedBy = [
    "default.target"
  ];

  systemd.user.services.wireplumber.wantedBy = [
    "default.target"
  ];

  systemd.user.services.pipewire-pulse.wantedBy = [
    "default.target"
  ];

  # ------------------------------------------------------------
  # DSP COMO SALIDA PREDETERMINADA
  # ------------------------------------------------------------

  systemd.user.services.palco-dsp-default = {
    description = "Palco: DSP como salida predeterminada";

    after = [
      "pipewire.service"
      "wireplumber.service"
    ];

    wants = [
      "pipewire.service"
      "wireplumber.service"
    ];

    wantedBy = [
      "default.target"
    ];

    path = with pkgs; [
      pipewire
      wireplumber
      coreutils
      gnugrep
      gawk
      gnused
    ];

    script = ''
      for i in $(seq 1 30); do
        ID=$(
          wpctl status 2>/dev/null \
            | awk '/palco DSP/ {
                gsub(/[.]/, "", $1);
                print $1;
                exit
              }'
        )

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

  # ------------------------------------------------------------
  # NIVEL DEL JACK
  # ------------------------------------------------------------

  systemd.services.palco-jack-level = {
    description = "Palco: nivel de salida jack al 80%";

    after = [
      "sound.target"
    ];

    wantedBy = [
      "multi-user.target"
    ];

    path = with pkgs; [
      alsa-utils
    ];

    script = ''
      for ctl in Headphone PCM Master; do
        amixer -q -c 0 sset "$ctl" 100% unmute 2>/dev/null || true
      done
    '';

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  # ------------------------------------------------------------
  # HERRAMIENTAS
  # ------------------------------------------------------------

  environment.systemPackages = with pkgs; [
    bluez
    bluez-tools
    alsa-utils
    pipewire
    wireplumber
    util-linux
    lsp-plugins
    lv2
  ];

  # ------------------------------------------------------------
  # ALIASES
  # ------------------------------------------------------------

  environment.shellAliases = {
    # Modo bolo:
    # Wi-Fi bloqueado, Bluetooth sigue activo.
    palco-bolo =
      "sudo rfkill block wifi && "
      + "printf 'power on\\ndiscoverable on\\npairable on\\n' "
      + "| bluetoothctl";

    # Modo configuración:
    # vuelve a permitir Wi-Fi.
    palco-config =
      "sudo rfkill unblock wifi && "
      + "echo 'WiFi activada: usa nmtui para configurar red'";

    # Estado general.
    palco-estado =
      "bluetoothctl show && "
      + "echo '---' && "
      + "bluetoothctl devices && "
      + "echo '---' && "
      + "wpctl status && "
      + "echo '---' && "
      + "aplay -l && "
      + "echo '---' && "
      + "systemctl --no-pager --failed";

    # Estado Bluetooth.
    palco-bt =
      "bluetoothctl show && "
      + "echo '---' && "
      + "bluetoothctl devices && "
      + "echo '---' && "
      + "bluetoothctl paired-devices && "
      + "echo '---' && "
      + "rfkill list bluetooth";

    # Estado DSP.
    palco-dsp-check =
      "wpctl status | grep -i 'palco DSP'; "
      + "echo '---'; "
      + "pw-dump 2>/dev/null "
      + "| grep -o 'palco-dsp[^\\\"]*' "
      + "| sort -u";

    # Prueba directa de audio.
    palco-audio-test =
      "speaker-test -t wav -c 2";
  };
}