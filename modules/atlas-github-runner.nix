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

      # All CI services share a resource-controlled systemd slice.
      serviceOverrides = {
        Slice = "github-runners.slice";
        CPUWeight = 20;
        IOWeight = 20;
        Nice = 10;
      };
    };
in
{
  # Three isolated registrations serve two private repositories. FCTV has
  # two workers so its independent workflow jobs can run concurrently.
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

    fctv2 = mkRunner {
      name = "atlas-fctv-2";
      url = "https://github.com/juanqp07/fctv";
      # The same repo-scoped PAT can register multiple runners for this repo.
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
  # Capacity: two FCTV jobs plus one Kigo job, sharing 3 CPU and 10 GiB.
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
    github-runner-fctv2.unitConfig.ConditionPathExists = "/var/lib/secrets/github-runner/fctv.token";
    github-runner-kigo.unitConfig.ConditionPathExists = "/var/lib/secrets/github-runner/kigo.token";
  };
}
