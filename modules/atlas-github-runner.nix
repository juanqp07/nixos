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

      # A runner is destroyed and re-registered after each job.
      ephemeral = true;

      extraLabels = [
        "atlas"
        "nixos"
      ] ++ labels;

      extraPackages = runnerPackages;

      # All three runners share one resource-controlled systemd slice.
      serviceOverrides = {
        Slice = "github-runners.slice";
        CPUWeight = 20;
        IOWeight = 20;
        Nice = 10;
      };
    };
in
{
  # One isolated runner registration per repository. The host is shared, but
  # GitHub credentials and workspaces are not shared between projects.
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

    nixos = mkRunner {
      name = "atlas-nixos";
      url = "https://github.com/juanqp07/nixos";
      tokenFile = "/var/lib/secrets/github-runner/nixos.token";
      labels = [ "nixos-config" ];
    };
  };

  # Aggregate resource limits prevent three simultaneous jobs from starving
  # Atlas' Docker workloads and system services.
  systemd.slices.github-runners.sliceConfig = {
    CPUQuota = "300%";
    MemoryHigh = "10G";
    MemoryMax = "12G";
    IOWeight = 20;
  };

  # Provision PATs manually; never put them in Git or the Nix Store.
  systemd.tmpfiles.rules = [
    "d /var/lib/secrets/github-runner 0700 root root -"
  ];

  # Avoid failed registration loops before each PAT has been provisioned.
  systemd.services = {
    github-runner-fctv.unitConfig.ConditionPathExists = "/var/lib/secrets/github-runner/fctv.token";
    github-runner-kigo.unitConfig.ConditionPathExists = "/var/lib/secrets/github-runner/kigo.token";
    github-runner-nixos.unitConfig.ConditionPathExists = "/var/lib/secrets/github-runner/nixos.token";
  };
}
