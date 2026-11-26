{ config, pkgs, lib, ... }:

{
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

}
