{ config, pkgs, lib, ... }:

{

# ============================================================

# PALCO-AUDIO

#

# Raspberry Pi 4B como receptor Bluetooth A2DP -> jack 3.5mm

#

# Móvil

# -> Bluetooth A2DP

# -> BlueZ

# -> PipeWire / WirePlumber

# -> DSP

# -> ALSA

# -> Jack 3.5 mm

#

# DSP:

# HPF 80 Hz -> Compresor 2:1 -> Limiter -1 dBFS

# ============================================================

# ------------------------------------------------------------

# BLUETOOTH / BLUEZ

# ------------------------------------------------------------

hardware.bluetooth = {
enable = true;
powerOnBoot = true;


settings = {
  General = {
    Name = "palco";
    Class = "0x200414";

    # Solo Bluetooth clásico para A2DP.
    ControllerMode = "bredr";

    FastConnectable = true;

    # Siempre visible y emparejable.
    DiscoverableTimeout = 0;
    PairableTimeout = 0;
    AlwaysPairable = true;

    Privacy = "off";
    JustWorksRepairing = "always";
  };

  Policy = {
    AutoEnable = true;
    ReconnectAttempts = 7;
    ReconnectIntervals = "1,2,4,8,16,32,64";
  };
};


};

# ------------------------------------------------------------

# AGENTE DE EMPAREJAMIENTO

# ------------------------------------------------------------

systemd.services.bt-agent = {
description = "Palco: agente Bluetooth NoInputNoOutput";


after = [
  "bluetooth.service"
];

partOf = [
  "bluetooth.target"
];

wantedBy = [
  "multi-user.target"
];

serviceConfig = {
  ExecStart = "${pkgs.bluez-tools}/bin/bt-agent -c NoInputNoOutput";
  Restart = "always";
  RestartSec = 5;
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

# RECONEXIÓN BLUETOOTH

# ------------------------------------------------------------

systemd.services.palco-bt-reaffirm = {
description = "Palco: reconexión Bluetooth de móviles";


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
  rfkill unblock bluetooth 2>/dev/null || true

  bluetoothctl show 2>/dev/null \
    | grep -q "Powered: yes" \
    || printf 'power on\n' \
    | bluetoothctl >/dev/null 2>&1 || true

  printf 'discoverable on\npairable on\n' \
    | bluetoothctl >/dev/null 2>&1 || true

  bluetoothctl paired-devices 2>/dev/null \
    | while read -r _ mac _rest; do
        [ -n "$mac" ] || continue

        if ! bluetoothctl info "$mac" 2>/dev/null \
          | grep -q "Connected: yes"; then

          timeout 20 bluetoothctl connect "$mac" \
            >/dev/null 2>&1 || true
        fi
      done
'';

serviceConfig = {
  Type = "oneshot";
};


};

systemd.timers.palco-bt-reaffirm = {
description = "Palco: comprobar Bluetooth cada 2 minutos";


wantedBy = [
  "timers.target"
];

timerConfig = {
  OnBootSec = "1min";
  OnUnitActiveSec = "2min";
};


};

# ------------------------------------------------------------

# BACKUP DE CLAVES BLUETOOTH

# ------------------------------------------------------------

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

security.rtkit.enable = true;

services.pipewire = {
enable = true;


# Equipo headless: arrancar PipeWire sin depender de
# socket activation.
socketActivation = false;

alsa = {
  enable = true;
  support32Bit = false;
};

pulse.enable = true;
wireplumber.enable = true;

extraLv2Packages = [
  pkgs.lsp-plugins
];

# ----------------------------------------------------------
# RELOJ
# ----------------------------------------------------------

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
          nodes = [
            {
              type = "lv2";
              name = "hpf";

              plugin =
                "http://lsp-plug.in/plugins/lv2/filter_stereo";

              control = {
                "ft" = 1;
                "f" = 80.0;
                "s" = 1;
              };
            }

            {
              type = "lv2";
              name = "comp";

              plugin =
                "http://lsp-plug.in/plugins/lv2/compressor_stereo";

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

              plugin =
                "http://lsp-plug.in/plugins/lv2/limiter_stereo";

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
          "node.name" = "palco_dsp_input";
          "media.class" = "Audio/Sink";
          "audio.channels" = 2;
          "audio.position" = [
            "FL"
            "FR"
          ];
        };

        "playback.props" = {
          "node.name" = "palco_dsp_output";
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
# WIREPLUMBER
# ----------------------------------------------------------

wireplumber.extraConfig = {

  # Sistema sin escritorio/sesión gráfica.
  "10-palco-headless" = {
    "wireplumber.profiles" = {
      main = {
        "monitor.bluez.seat-monitoring" = "disabled";
      };
    };
  };

  # Bluetooth A2DP.
  "51-palco-bluetooth" = {
    "wireplumber.settings" = {
      "bluetooth.autoswitch-to-headset-profile" = false;
    };

    "monitor.bluez.properties" = {
      # Solo receptor A2DP.
      "bluez5.roles" = [
        "a2dp_sink"
      ];

      "bluez5.codecs" = [
        "sbc"
        "aac"
      ];

      "bluez5.enable-sbc-xq" = false;
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

# USUARIO HEADLESS

# ------------------------------------------------------------

users.users.juan.linger = true;

# ------------------------------------------------------------

# DSP POR DEFECTO

# ------------------------------------------------------------

systemd.user.services.palco-dsp-default = {
description = "Palco: DSP como salida predeterminada";


after = [
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
    amixer -q -c 0 sset "$ctl" 80% unmute 2>/dev/null || true
  done
'';

serviceConfig = {
  Type = "oneshot";
  RemainAfterExit = true;
};


};

# ------------------------------------------------------------

# PAQUETES

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
palco-bolo =
"sudo rfkill block wifi && "
+ "printf 'power on\ndiscoverable on\npairable on\n' "
+ "| bluetoothctl";


palco-config =
  "sudo rfkill unblock wifi && "
  + "echo 'WiFi activada: usa nmtui para configurar red'";

palco-estado =
  "bluetoothctl show && "
  + "echo '---' && "
  + "wpctl status && "
  + "echo '---' && "
  + "aplay -l && "
  + "echo '---' && "
  + "systemctl --no-pager --failed";

palco-bt =
  "bluetoothctl show && "
  + "echo '---' && "
  + "bluetoothctl devices && "
  + "echo '---' && "
  + "bluetoothctl paired-devices && "
  + "echo '---' && "
  + "rfkill list bluetooth";

palco-dsp-check =
  "wpctl status | grep -i 'palco DSP'; "
  + "echo '---'; "
  + "pw-dump 2>/dev/null "
  + "| grep -o 'palco-dsp[^\\\"]*' "
  + "| sort -u";

palco-audio-test =
  "speaker-test -t wav -c 2";


};
}
