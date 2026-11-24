{ pkgs, ... }:

let
  runnerPackages = with pkgs; [
    curl
    jq
    python3
    gawk
    unzip
    # Docker CLI + Buildx client only. No runner gets the production Docker socket.
    docker-client
    docker-buildx
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

      # Runners may access only the dedicated rootless BuildKit socket.
      # This is deliberately NOT the host Docker socket: membership in the
      # docker group would grant effective root access to Atlas.
      serviceOverrides = {
        Slice = "github-runners.slice";
        CPUWeight = 20;
        IOWeight = 20;
        Nice = 10;
        SupplementaryGroups = [ "github-buildkit" ];
      };

      # Some downloaded Linux tools (for example, Android SDK binaries) use
      # glibc. Keep the loader available without granting access to nix-daemon.
      extraEnvironment = {
        NIX_LD = "/run/current-system/sw/share/nix-ld/lib/ld.so";
        NIX_LD_LIBRARY_PATH = "/run/current-system/sw/share/nix-ld/lib";
      };

      # Keep common utilities shared, while project toolchains remain isolated
      # to the runner that needs them.
      extraPackages = runnerPackages ++ packages;
    };
in
{
  # Dedicated unprivileged account and subordinate ID ranges for rootless BuildKit.
  users.groups.github-buildkit = { };
  users.users.github-buildkit = {
    isSystemUser = true;
    group = "github-buildkit";
    home = "/var/lib/github-buildkit";
    createHome = true;
    subUidRanges = [
      {
        startUid = 200000;
        count = 65536;
      }
    ];
    subGidRanges = [
      {
        startGid = 200000;
        count = 65536;
      }
    ];
  };

  # One isolated rootless BuildKit daemon is shared by the three trusted
  # private-repository runners. It has no access to the production Docker API.
  systemd.services.github-buildkit = {
    description = "Rootless BuildKit for GitHub Actions runners on Atlas";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    path = with pkgs; [
      rootlesskit
      slirp4netns
      fuse-overlayfs
      shadow
    ];

    environment = {
      HOME = "/var/lib/github-buildkit";
      XDG_RUNTIME_DIR = "/run/github-buildkit";
    };

    serviceConfig = {
      Type = "simple";
      User = "github-buildkit";
      Group = "github-buildkit";
      UMask = "0007";
      StateDirectory = "github-buildkit";
      StateDirectoryMode = "0700";
      RuntimeDirectory = "github-buildkit";
      RuntimeDirectoryMode = "0770";
      ExecStart = "${pkgs.buildkit}/bin/buildkitd --rootless --addr unix:///run/github-buildkit/buildkitd.sock --root /var/lib/github-buildkit";
      Restart = "on-failure";
      RestartSec = "5s";
      Delegate = true;
      LimitNOFILE = 1048576;
      Slice = "github-runners.slice";
      CPUWeight = 20;
      IOWeight = 20;
      Nice = 10;
    };
  };

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
  # BuildKit is placed in the same slice so builds count against the same budget.
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
