{ pkgs, ... }:

let
  tokenFile = "/var/lib/secrets/github-runner/fctv.token";
in
{
  # Runner exclusivo de FCTV. NixOS ejecuta el servicio con DynamicUser y
  # aislamiento systemd; no se añade al grupo docker ni se expone el socket.
  services.github-runners.fctv = {
    enable = true;

    url = "https://github.com/juanqp07/fctv";
    name = "atlas-fctv";

    # PAT fine-grained guardado fuera del repositorio y del Nix Store.
    inherit tokenFile;
    tokenType = "access";

    # Registra un runner nuevo por trabajo y limpia su estado al terminar.
    ephemeral = true;

    extraLabels = [
      "atlas"
      "nixos"
      "fctv"
    ];

    extraPackages = with pkgs; [
      curl
      jq
      unzip
    ];

    # Evita que una compilación CI monopolice Atlas o su memoria.
    serviceOverrides = {
      CPUQuota = "400%";
      CPUWeight = 25;
      IOWeight = 50;
      MemoryMax = "8G";
      Nice = 10;
    };
  };

  # El directorio existe tras el rebuild, pero el PAT se provisiona manualmente.
  systemd.tmpfiles.rules = [
    "d /var/lib/secrets/github-runner 0700 root root -"
  ];

  # No intentar registrar el servicio hasta que el secreto esté instalado.
  systemd.services.github-runner-fctv.unitConfig.ConditionPathExists = tokenFile;
}
