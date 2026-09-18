{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Rootless Podman maps the docker-registry subuid/subgid range with the
  # setuid newuidmap/newgidmap wrappers. Setting a unit `path` replaces PATH
  # entirely (nixos/lib/systemd-lib.nix builds it from `path` alone), which
  # drops the default /run/wrappers/bin, so Podman exits with
  # `newuidmap ... executable file not found in $PATH`. dirOf wrapperDir is
  # /run/wrappers; `path` appends /bin, giving /run/wrappers/bin back.
  rootlessPodmanPath = [
    pkgs.crun
    pkgs.conmon
    pkgs.slirp4netns
    pkgs.fuse-overlayfs
    (builtins.dirOf config.security.wrapperDir)
  ];
in
{
  imports = [
    ../config/build-cache.nix
  ];

  # 1. Attach build cache loopback image for container registry storage
  services.build-cache.attachments.container-registry = {
    enable = true;
    nfsDevice = "truenas-scale:/mnt/ssd/container-registry";
    nfsMountPoint = "/mnt/nfs/container-registry";
    imageName = "container-registry.img";
    imageSize = "50G";
    targetMountPoint = "/mnt/ssd/container-registry";
    owner = "docker-registry";
    group = "docker-registry";
    mode = "0750";
  };

  # Configure subuid/subgid ranges to enable rootless Podman for the docker-registry user
  users.users.docker-registry = {
    subUidRanges = [
      {
        startUid = 500000;
        count = 65536;
      }
    ];
    subGidRanges = [
      {
        startGid = 500000;
        count = 65536;
      }
    ];
    isSystemUser = true;
    # GitLab's container registry already owns /var/lib/docker-registry
    # (WorkingDirectory of gitlab-container-registry). Sharing it as HOME made
    # podman `stat .../.config` fail with permission denied.
    home = "/var/lib/docker-registry-cache";
    createHome = true;
  };
  users.users.docker-registry.group = "docker-registry";
  users.groups.docker-registry = { };

  # 2. Pull-through registry cache containers running via Podman (configured as rootless)
  virtualisation.oci-containers.backend = "podman";
  # apps-2's generated registries.conf lists docker.io/quay.io locations but no
  # unqualified-search-registries, so short names like registry:2 fail before
  # Podman even looks at local images.
  virtualisation.containers.registries.search = [ "docker.io" ];
  virtualisation.oci-containers.containers = {
    docker-registry-cache = {
      image = "docker.io/library/registry:2";
      ports = [ "5000:5000" ];
      volumes = [
        "/mnt/ssd/container-registry/cache/docker:/var/lib/registry"
      ];
      environment = {
        REGISTRY_PROXY_REMOTEURL = "https://registry-1.docker.io";
      };
    };

    ghcr-registry-cache = {
      image = "docker.io/library/registry:2";
      ports = [ "5001:5000" ];
      volumes = [
        "/mnt/ssd/container-registry/cache/ghcr:/var/lib/registry"
      ];
      environment = {
        REGISTRY_PROXY_REMOTEURL = "https://ghcr.io";
      };
    };

    quay-registry-cache = {
      image = "docker.io/library/registry:2";
      ports = [ "5002:5000" ];
      volumes = [
        "/mnt/ssd/container-registry/cache/quay:/var/lib/registry"
      ];
      environment = {
        REGISTRY_PROXY_REMOTEURL = "https://quay.io";
      };
    };

    gcr-registry-cache = {
      image = "docker.io/library/registry:2";
      ports = [ "5003:5000" ];
      volumes = [
        "/mnt/ssd/container-registry/cache/gcr:/var/lib/registry"
      ];
      environment = {
        REGISTRY_PROXY_REMOTEURL = "https://gcr.io";
      };
    };
  };

  # Configure all systemd services for container registry management
  systemd.services = {
    container-registry-dir-init = {
      description = "Initialize subdirectories for Docker and GitLab Container Registries";
      after = [ "mnt-ssd-container\\x2dregistry.mount" ];
      requires = [ "mnt-ssd-container\\x2dregistry.mount" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /mnt/ssd/container-registry/cache/docker \
                 /mnt/ssd/container-registry/cache/ghcr \
                 /mnt/ssd/container-registry/cache/quay \
                 /mnt/ssd/container-registry/cache/gcr \
                 /mnt/ssd/container-registry/gitlab \
                 /var/lib/docker-registry-cache/docker-registry-cache \
                 /var/lib/docker-registry-cache/ghcr-registry-cache \
                 /var/lib/docker-registry-cache/quay-registry-cache \
                 /var/lib/docker-registry-cache/gcr-registry-cache
        chown -R docker-registry:docker-registry /mnt/ssd/container-registry/cache
        chown -R docker-registry:docker-registry /var/lib/docker-registry-cache
        chown -R gitlab:docker-registry /mnt/ssd/container-registry/gitlab
        chmod -R 770 /mnt/ssd/container-registry/cache
        chmod 770 /mnt/ssd/container-registry/gitlab
      '';
    };

    container-registry-gc = {
      description = "Garbage collect container registry caches";
      serviceConfig = {
        Type = "oneshot";
        User = "docker-registry";
        Group = "docker-registry";
      };
      path = rootlessPodmanPath;
      # Each cache container is created by its own podman-<name> unit under a
      # per-cache rootless Podman store (HOME) and runroot (XDG_RUNTIME_DIR).
      # `podman exec` only finds the running container when pointed at that
      # same store and runroot; a single shared context sees an empty store
      # and fails with "no such container". Set both per cache.
      script = ''
        set -euo pipefail

        failed=0
        for cache in docker ghcr quay gcr; do
          name="$cache-registry-cache"
          echo "Garbage collecting $name..."
          if out=$(HOME="/var/lib/docker-registry-cache/$name" \
               XDG_RUNTIME_DIR="/run/$name" \
               ${pkgs.podman}/bin/podman exec "$name" \
               bin/registry garbage-collect /etc/docker/registry/config.yml --delete-untagged 2>&1); then
            printf '%s\n' "$out"
          elif printf '%s' "$out" | grep -q 'Path not found: /docker/registry/v2/repositories'; then
            # A cache nothing has pulled through yet has no repositories dir;
            # registry garbage-collect exits non-zero. That is an empty cache,
            # not a failure.
            echo "$name has no repositories yet; nothing to collect."
          else
            printf '%s\n' "$out" >&2
            echo "Garbage collection failed for $name" >&2
            failed=1
          fi
        done

        exit "$failed"
      '';
      startAt = "Sunday 04:00:00";
    };
  }
  //
    lib.genAttrs
      [
        "podman-docker-registry-cache"
        "podman-ghcr-registry-cache"
        "podman-quay-registry-cache"
        "podman-gcr-registry-cache"
      ]
      (name: {
        requires = [ "container-registry-dir-init.service" ];
        after = [ "container-registry-dir-init.service" ];
        path = rootlessPodmanPath;
        environment = {
          # Per-cache HOME so containers.conf runroot is not shared across the
          # four units (they each have a different XDG_RUNTIME_DIR).
          HOME = "/var/lib/docker-registry-cache/${lib.removePrefix "podman-" name}";
          XDG_RUNTIME_DIR = "/run/${lib.removePrefix "podman-" name}";
          TMPDIR = "/run/${lib.removePrefix "podman-" name}";
        };
        serviceConfig = {
          User = lib.mkForce "docker-registry";
          Group = lib.mkForce "docker-registry";
          WorkingDirectory = "/var/lib/docker-registry-cache/${lib.removePrefix "podman-" name}";
          RuntimeDirectory = lib.removePrefix "podman-" name;
          RuntimeDirectoryMode = "0700";
          # Hard reset leaves /tmp/containers with a stale boot ID; Podman then
          # refuses to start until those dirs are deleted.
          ExecStartPre = lib.mkBefore [
            "${pkgs.writeShellScript "podman-clear-stale-tmp" ''
              rm -rf /tmp/containers /tmp/libpod
            ''}"
          ];
        };
      });

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    5000 # docker.io pull-through cache (gitlab-runner on proxmox-dev)
    5001 # ghcr.io pull-through cache
    5002 # quay.io pull-through cache
    5003 # gcr.io pull-through cache
  ];
}
