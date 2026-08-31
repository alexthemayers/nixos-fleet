{
  config,
  pkgs,
  lib,
  ...
}:

{
  # A restart here can interrupt an in-progress CI job, so rotate the runner
  # token during a quiet window. The alternative -- leaving it off -- means a
  # rotated token silently never takes effect, which is worse.
  sops.secrets."gitlab/runner_token" = {
    owner = "gitlab-runner";
    group = "gitlab-runner";
    mode = "0440";
    restartUnits = [ "gitlab-runner.service" ];
  };

  sops.templates."gitlab-runner-env" = {
    owner = "gitlab-runner";
    group = "gitlab-runner";
    mode = "0440";
    restartUnits = [ "gitlab-runner.service" ];
    content = ''
      CI_SERVER_URL="https://gitlab.alexmayers.co.za"
      CI_SERVER_TOKEN="${config.sops.placeholder."gitlab/runner_token"}"
    '';
  };

  # Enable Podman on the host
  virtualisation.podman = {
    enable = true;
  };

  # Configure subuid/subgid ranges for the gitlab-runner user
  users.users.gitlab-runner = {
    isSystemUser = true;
    group = "gitlab-runner";
    subUidRanges = [
      {
        startUid = 400000;
        count = 65536;
      }
    ];
    subGidRanges = [
      {
        startGid = 400000;
        count = 65536;
      }
    ];
  };
  users.groups.gitlab-runner = { };

  systemd.tmpfiles.rules = [
    "d /var/lib/gitlab-runner/.config 0755 gitlab-runner gitlab-runner -"
    "d /var/lib/gitlab-runner/.local/share 0755 gitlab-runner gitlab-runner -"
  ];

  # Create a systemd service that runs the Podman API service in rootless mode under the gitlab-runner user
  systemd.services.gitlab-runner-podman-socket = {
    description = "Podman API Socket for gitlab-runner (Rootless)";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      "nscd.service"
    ];
    restartIfChanged = false;
    stopIfChanged = false;
    serviceConfig = {
      Type = "simple";
      User = "gitlab-runner";
      Group = "gitlab-runner";
      ExecStart = "${pkgs.podman}/bin/podman system service --time=0 unix:///run/gitlab-runner/podman.sock";
      RuntimeDirectory = "gitlab-runner";
      RuntimeDirectoryMode = "0700";
      StateDirectory = "gitlab-runner";
      Environment = [
        "HOME=/var/lib/gitlab-runner"
        "XDG_RUNTIME_DIR=/run/gitlab-runner"
        "CONTAINERS_EVENTS_BACKEND=file"
        "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin"
      ];
      Restart = "always";
      RestartSec = "5s";
    };
  };

  # Configure the GitLab Runner service
  services.gitlab-runner = {
    enable = true;
    settings = {
      concurrent = 10;
      listen_address = "[::]:9252";
    };
    services = {
      # The name is historical - it refers to a host that no longer exists, and
      # this runner has always run on proxmox-dev. It is left alone because the
      # attribute name is the systemd unit and the registered runner identity;
      # renaming it forces a re-registration against GitLab rather than being a
      # cosmetic change.
      proxmox-gaming-runner = {
        authenticationTokenConfigFile = config.sops.templates."gitlab-runner-env".path;
        executor = "docker";
        dockerImage = "alpine:latest";
        limit = 4;
        # Specify podman socket via registrationFlags
        # No --docker-privileged and no host networking: a CI job on this host
        # can otherwise read the age key that also decrypts the db-node secrets.
        registrationFlags = [
          "--docker-host"
          "unix:///run/gitlab-runner/podman.sock"
        ];
      };
    };
  };

  # Ensure gitlab-runner systemd service starts after our podman socket service
  fleet.waitForHost.gitlab-runner-gitlab = {
    host = "proxmox-applications-2";
    port = 8080;
    forServices = [ "gitlab-runner.service" ];
  };

  systemd.services.gitlab-runner = {
    wants = [ "network-online.target" ];
    after = [
      "gitlab-runner-podman-socket.service"
      "network-online.target"
      "tailscaled.service"
      "nscd.service"
    ];
    requires = [ "gitlab-runner-podman-socket.service" ];
    restartIfChanged = false;
    stopIfChanged = false;
    # Disable DynamicUser and run as static user/group to prevent permission conflicts
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "gitlab-runner";
      Group = "gitlab-runner";
      Restart = "always";
      RestartSec = "5s";
    };
    environment = {
      RUNNER_OUTPUT_LIMIT = "16384"; # 16 MB log limit to prevent truncation
    };
  };

  # Force direct overwrite of the main registries.conf file to inject registry mirrors.
  # The caches run on proxmox-applications-2 (services/container-registry.nix);
  # the previous proxmox-gitlab target has not existed for some time, so every
  # mirrored pull silently fell through to the internet.
  environment.etc."containers/registries.conf".text = lib.mkForce ''
    unqualified-search-registries = ["docker.io", "quay.io", "ghcr.io", "gcr.io"]

    [[registry]]
    location = "docker.io"
    [[registry.mirror]]
    location = "proxmox-applications-2:5000"
    insecure = true

    [[registry]]
    location = "ghcr.io"
    [[registry.mirror]]
    location = "proxmox-applications-2:5001"
    insecure = true

    [[registry]]
    location = "quay.io"
    [[registry.mirror]]
    location = "proxmox-applications-2:5002"
    insecure = true

    [[registry]]
    location = "gcr.io"
    [[registry.mirror]]
    location = "proxmox-applications-2:5003"
    insecure = true
  '';

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    9252 # gitlab-runner Prometheus metrics
  ];
}
