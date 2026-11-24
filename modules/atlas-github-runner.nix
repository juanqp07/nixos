{ pkgs, ... }:

let
  runnerPackages = with pkgs; [
    curl
    jq
    python3
    gawk
    unzip
  ];

  mkRunner =
    {
      name,
      url,
      tokenFile,
      labels,
      packages ? [ ],
    }:
    {
      enable = true;

      inherit name url tokenFile;
      tokenType = "access";

      # Ephemeral runners are re-registered after completing a job.
      ephemeral = true;

      # Replace a stale GitHub registration with this runner's same name.
      # This can happen when Atlas stops/reboots while the runner is idle.
      replace = true;

      extraLabels = [
        "atlas"
      ]
      ++ labels;

      # Some downloaded Linux tools (for example, Android SDK binaries) use
      # glibc. Keep the loader available without granting access to nix-daemon.
      extraEnvironment = {
        NIX_LD = "/run/current-system/sw/share/nix-ld/lib/ld.so";
        NIX_LD_LIBRARY_PATH = "/run/current-system/sw/share/nix-ld/lib";
      };

      # Keep common utilities shared, while project toolchains remain isolated
      # to the runner that needs them.
      extraPackages = runnerPackages ++ packages;

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
      packages = with pkgs; [
        nodejs_22
        postgresql_17
        gcc
        jdk17
        gitleaks
      ];
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
