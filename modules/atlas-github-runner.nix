{ lib, pkgs, ... }:

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
      persistentWorkDir ? false,
    }:
    {
      enable = true;
      # Heavy FCTV workspaces, SDK downloads and RUNNER_TEMP belong on disk,
      # not the small /run tmpfs. Keep a separate directory per runner.
      workDir = if persistentWorkDir then "/var/lib/github-runner-work/${name}" else null;

      inherit name url tokenFile;
      tokenType = "access";

      # Atlas is a fixed-capacity host, not an autoscaled runner pool. Keep the
      # registration and listener session across jobs instead of re-registering
      # the same remote name while GitHub is still closing the previous session.
      ephemeral = false;

      # This is used only when a fresh registration is required. Healthy state
      # is reused on service restarts and between jobs.
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
      }
      // lib.optionalAttrs persistentWorkDir {
        # Preserve the module's normal credential path and add a separate,
        # DynamicUser-owned persistent directory for the runner workspace.
        StateDirectory = lib.mkForce [
          "github-runner/${name}"
          "github-runner-work/${name}"
        ];
        StateDirectoryMode = "0700";

        # The upstream github-runner module adds BindPaths = [ cfg.workDir ]
        # whenever workDir is set. This workspace is already exposed through
        # StateDirectory above; adding a second bind for the same path makes
        # systemd fail while constructing the runner's mount namespace.
        BindPaths = lib.mkForce [ ];
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

  runnerRecovery =
    {
      serviceName,
      tokenFile,
    }:
    let
      stateGuard = pkgs.writeShellScript "github-runner-${serviceName}-state-guard" ''
        set -euo pipefail

        state_dir="''${STATE_DIRECTORY:-}"
        # systemd joins multiple StateDirectory entries with ':'. The first
        # path is the runner's registration state directory.
        state_dir="''${state_dir%%:*}"
        if [[ -z "$state_dir" ]]; then
          echo "GitHub runner state guard: STATE_DIRECTORY is not set." >&2
          exit 1
        fi

        config_marker="$state_dir/.nixos-current-config.json"
        if [[ -e "$config_marker" ]] &&
          { [[ ! -s "$state_dir/.runner" ]] || [[ ! -s "$state_dir/.credentials" ]]; }; then
          echo "GitHub runner ${serviceName}: registration state is incomplete; requesting a clean registration."
          rm -f -- "$config_marker" "$state_dir/.current-token" "$state_dir/.new-token"
        fi
      '';
    in
    {
      unitConfig = {
        ConditionPathExists = tokenFile;
        StartLimitIntervalSec = "15min";
        StartLimitBurst = 5;
      };

      serviceConfig = {
        # A persistent listener should not exit after a successful job. Restart
        # unexpected exits, but rate-limit repeated failures instead of flapping.
        Restart = lib.mkForce "always";
        RestartSec = "30s";

        # The upstream module hides .current-token from the listener. On a first
        # start, however, that file is created by ExecStartPre, after systemd has
        # already prepared the mount namespace. Prefix '-' keeps it inaccessible
        # when present while allowing the initial namespace setup when absent.
        # Keep the configured PAT inaccessible as well.
        InaccessiblePaths = lib.mkForce [
          "-/var/lib/github-runner/${serviceName}/.current-token"
          "-${tokenFile}"
        ];

        # Run with the runner's DynamicUser before the upstream configure hooks.
        # If GitHub deletes a registration, the listener removes .runner and
        # .credentials; invalidating these markers lets NixOS provision it again.
        ExecStartPre = lib.mkBefore [ "${stateGuard}" ];
      };
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
      # NixOS provides capability-enabled newuidmap/newgidmap wrappers here.
      # Keep this before pkgs.shadow so RootlessKit picks those wrappers first.
      "/run/wrappers"
      rootlesskit
      # BuildKit's git source resolver executes git from the daemon PATH.
      git
      slirp4netns
      util-linux
      iproute2
      runc
      fuse-overlayfs
      shadow
    ];

    environment = {
      HOME = "/var/lib/github-buildkit";
      XDG_RUNTIME_DIR = "/run/github-buildkit";
    };

    unitConfig = {
      # Prevent a broken worker from producing an unbounded restart loop.
      StartLimitIntervalSec = "15min";
      StartLimitBurst = 5;
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
      ExecStart = "${pkgs.rootlesskit}/bin/rootlesskit --net=slirp4netns --copy-up=/etc --disable-host-loopback ${pkgs.buildkit}/bin/buildkitd --rootless --oci-worker=true --oci-worker-binary=${pkgs.runc}/bin/runc --oci-worker-snapshotter=fuse-overlayfs --containerd-worker=false --addr unix:///run/github-buildkit/buildkitd.sock --root /var/lib/github-buildkit";
      Restart = "on-failure";
      RestartSec = "30s";
      Delegate = true;
      LimitNOFILE = 1048576;
      Slice = "github-runners.slice";
      CPUWeight = 20;
      IOWeight = 20;
      Nice = 10;
    };
  };

  # Three independent persistent registrations serve two private repositories.
  # FCTV has two workers so its independent workflow jobs can run concurrently.
  services.github-runners = {
    fctv = mkRunner {
      name = "atlas-fctv";
      url = "https://github.com/juanqp07/fctv";
      tokenFile = "/var/lib/secrets/github-runner/fctv.token";
      labels = [ "fctv" ];
      persistentWorkDir = true;
      packages = with pkgs; [
        nodejs_22
        postgresql_17
        gcc
        jdk17
        gitleaks
        gh
        # FCTV CI only: workflow linting, Playwright browser, and Compose config parsing.
        # Docker Compose is CLI-only here; this does not install or enable Docker Engine.
        actionlint
        chromium
        docker-compose
      ];
    };

    fctv2 = mkRunner {
      name = "atlas-fctv-2";
      url = "https://github.com/juanqp07/fctv";
      # The same repo-scoped PAT can register multiple runners for this repo.
      tokenFile = "/var/lib/secrets/github-runner/fctv.token";
      labels = [ "fctv" ];
      persistentWorkDir = true;
      packages = with pkgs; [
        nodejs_22
        postgresql_17
        gcc
        jdk17
        gitleaks
        gh
        # FCTV CI only: workflow linting, Playwright browser, and Compose config parsing.
        # Docker Compose is CLI-only here; this does not install or enable Docker Engine.
        actionlint
        chromium
        docker-compose
      ];
    };

    kigo = mkRunner {
      name = "atlas-kigo";
      url = "https://github.com/juanqp07/kigo";
      tokenFile = "/var/lib/secrets/github-runner/kigo.token";
      labels = [ "kigo" ];
      persistentWorkDir = true;
      packages = with pkgs; [
        gcc
        postgresql_17
        redis
        gitleaks
        python312
        python312Packages.virtualenv
      ];
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

  # Keep runner lifecycle policy and token prerequisites consistent for all
  # three registrations.
  systemd.services = {
    github-runner-fctv = runnerRecovery {
      serviceName = "fctv";
      tokenFile = "/var/lib/secrets/github-runner/fctv.token";
    };

    github-runner-fctv2 = runnerRecovery {
      serviceName = "fctv2";
      tokenFile = "/var/lib/secrets/github-runner/fctv.token";
    };

    github-runner-kigo = runnerRecovery {
      serviceName = "kigo";
      tokenFile = "/var/lib/secrets/github-runner/kigo.token";
    };
  };
}
