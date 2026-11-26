{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Empaqueta los comandos de Palco junto con la biblioteca visual compartida.
  # Así funcionan aunque el repositorio no esté clonado en la Raspberry Pi.
  palcoCommand = pkgs.writeShellScriptBin "palco-command" ''
    export TERMINAL_STYLE_LIB="${../../scripts/terminal-style.sh}"
    exec ${pkgs.bash}/bin/bash ${../../scripts/palco-cli.sh} "$@"
  '';
in
{
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
    description = "Palco: nivel de salida jack al 100%";

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

  environment.systemPackages =
    with pkgs;
    [
      bluez
      bluez-tools
      alsa-utils
      pipewire
      wireplumber
      util-linux
      lsp-plugins
      lv2
    ]
    ++ [ palcoCommand ];

  # ------------------------------------------------------------
  # ALIASES
  # ------------------------------------------------------------

  environment.shellAliases = {
    # Comandos empaquetados: la interfaz visual es común al resto de la suite.
    palco-bolo = "palco-command bolo";
    palco-config = "palco-command config";
    palco-estado = "palco-command estado";
    palco-bt = "palco-command bt";
    palco-dsp-check = "palco-command dsp-check";
    palco-audio-test = "palco-command audio-test";
  };
}
