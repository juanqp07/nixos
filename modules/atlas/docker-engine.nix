{ config, pkgs, ... }:

{
  virtualisation = {
    docker = {
      enable = true;
      # Poda semanal: con ~70 contenedores + watchtower, las imágenes viejas
      # se acumulan en /. Mismo patrón que pico.
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
      daemon.settings = {
        "log-driver" = "journald";

        # Con stateVersion >= 24.11 el default es false: cada reinicio de dockerd
        # (p. ej. un switch que cambie Docker) paraba todos los contenedores.
        "live-restore" = true;

        features = {
          "containerd-snapshotter" = true;
        };
      };
    };
  };
}
