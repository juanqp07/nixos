{ pkgs, ... }:

let
  runnerPackages = with pkgs; [
    curl
    jq
    unzip
  ];

  mkRunner =
    {
      name,
      url,
      tokenFile,
      labels,
    }:
    {
      enable = true;

      inherit name url tokenFile;
      tokenType = "access";

      # A runner is re-registered after every job.
      ephemeral = true;

      extraLabels = [
        "atlas"
      ]
      ++ labels;

      extraPackages = runnerPackages;

      # Both runners share one resource-controlled systemd slice.
      serviceOverrides = {
        Slice = "github-runners.slice";
        CPUWeight = 20;
        IOWeight = 20;
        Nice = 10;
      };
    };
in
{
  # One isolated registration per private repository. Credentials, runner
  # state and workspaces are not shared between FCTV and Kigo.
  services.github-runners = {
    fctv = mkRunner {
      name = "atlas-fctv";
      url = "https://github.com/juanqp07/fctv";
      tokenFile = "/var/lib/secrets/github-runner/fctv.token";
      labels = [ "fctv" ];
    };

    kigo = mkRunner {
      name = "atlas-kigo";
      url = "https://github.com/juanqp07/kigo";
      tokenFile = "/var/lib/secrets/github-runner/kigo.token";
      labels = [ "kigo" ];
    };
  };

  # Aggregate limits keep CI from starving Atlas' production services.
  systemd.slices.github-runners.sliceConfig = {
    CPUQuota = "300%";
    MemoryHigh = "8G";
    MemoryMax = "10G";
    IOWeight = 20;
  };

  # Provision PATs manually; never store them in Git or the Nix Store.
  systemd.tmpfiles.rules = [
    "d /var/lib/secrets/github-runner 0700 root root -"
  ];

  # Avoid registration attempts until the corresponding PAT exists.
  systemd.services = {
    github-runner-fctv.unitConfig.ConditionPathExists = "/var/lib/secrets/github-runner/fctv.token";
    github-runner-kigo.unitConfig.ConditionPathExists = "/var/lib/secrets/github-runner/kigo.token";
  };
}
