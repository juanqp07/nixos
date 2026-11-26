{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:

{
  # SONIDO Y BLUETOOTH
  # ============================================================

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;

    alsa.enable = true;
    alsa.support32Bit = true;

    pulse.enable = true;
    # JACK se usa mediante pw-jack <aplicación> para evitar LD_LIBRARY_PATH global.
    # services.pipewire.jack.enable está deprecado en el pin actual de nixpkgs.
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;

    settings = {
      General = {
        Experimental = true;
        # FastConnectable se deja en su valor predeterminado (false): evita
        # consumo adicional para conexiones entrantes que estos equipos no necesitan.
      };

      Policy = {
        AutoEnable = true;
      };
    };
  };

  services.blueman.enable = true;

  # ============================================================

}
