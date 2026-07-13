{
  config,
  pkgs,
  lib,
  ...
}:

{
  sops.secrets."gitlab/runner_token" = {
    owner = "gitlab-runner";
    group = "gitlab-runner";
    mode = "0440";
  };

  sops.templates."gitlab-runner-env" = {
    owner = "gitlab-runner";
    group = "gitlab-runner";
    mode = "0440";
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

  # Initialize the GitLab Runner state subdirectory on the Nix build loopback mount
  systemd.services.gitlab-runner-dir-init = {
    description = "Initialize GitLab Runner state directory on Nix build mount";
    after = [ "nix-var-nix-builds.mount" ];
    requires = [ "nix-var-nix-builds.mount" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /nix/var/nix/builds/gitlab-runner
      chown -R gitlab-runner:gitlab-runner /nix/var/nix/builds/gitlab-runner
      chmod 700 /nix/var/nix/builds/gitlab-runner
    '';
  };

  # Bind mount the directory to /var/lib/gitlab-runner
  fileSystems."/var/lib/gitlab-runner" = {
    device = "/nix/var/nix/builds/gitlab-runner";
    fsType = "none";
    options = [
      "bind"
      "nofail"
      "x-systemd.requires=gitlab-runner-dir-init.service"
      "x-systemd.after=gitlab-runner-dir-init.service"
    ];
  };

  # Create a systemd service that runs the Podman API service in rootless mode under the gitlab-runner user
  systemd.services.gitlab-runner-podman-socket = {
    description = "Podman API Socket for gitlab-runner (Rootless)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    unitConfig.RequiresMountsFor = "/var/lib/gitlab-runner";
    restartIfChanged = false;
    serviceConfig = {
      Type = "simple";
      User = "gitlab-runner";
      Group = "gitlab-runner";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /var/lib/gitlab-runner/.config /var/lib/gitlab-runner/.local/share";
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
      proxmox-gaming-runner = {
        authenticationTokenConfigFile = config.sops.templates."gitlab-runner-env".path;
        executor = "docker";
        dockerImage = "alpine:latest";
        limit = 4;
        dockerVolumes = [
          "nix-store-cache:/nix"
        ];
        # Specify podman socket via registrationFlags
        registrationFlags = [
          "--docker-host"
          "unix:///run/gitlab-runner/podman.sock"
        ];
      };
    };
  };

  # Ensure gitlab-runner systemd service starts after our podman socket service
  systemd.services.gitlab-runner = {
    wants = [ "network-online.target" ];
    after = [
      "gitlab-runner-podman-socket.service"
      "network-online.target"
      "tailscaled.service"
    ];
    requires = [ "gitlab-runner-podman-socket.service" ];
    unitConfig.RequiresMountsFor = "/var/lib/gitlab-runner";
    restartIfChanged = false;
    # Disable DynamicUser and run as static user/group to prevent permission conflicts
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "gitlab-runner";
      Group = "gitlab-runner";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  # Force direct overwrite of the main registries.conf file to inject registry mirrors
  environment.etc."containers/registries.conf".text = lib.mkForce ''
    unqualified-search-registries = ["docker.io", "quay.io", "ghcr.io", "gcr.io"]

    [[registry]]
    location = "docker.io"
    [[registry.mirror]]
    location = "proxmox-gitlab:5000"
    insecure = true

    [[registry]]
    location = "ghcr.io"
    [[registry.mirror]]
    location = "proxmox-gitlab:5001"
    insecure = true

    [[registry]]
    location = "quay.io"
    [[registry.mirror]]
    location = "proxmox-gitlab:5002"
    insecure = true

    [[registry]]
    location = "gcr.io"
    [[registry.mirror]]
    location = "proxmox-gitlab:5003"
    insecure = true
  '';
}
