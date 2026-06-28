{
  config,
  lib,
  pkgs,
  ...
}:

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
  };

  # 2. Pull-through registry cache containers running via Podman (configured as rootless)
  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers = {
    docker-registry-cache = {
      image = "registry:2";
      ports = [ "5000:5000" ];
      volumes = [
        "/mnt/ssd/container-registry/cache/docker:/var/lib/registry"
      ];
      environment = {
        REGISTRY_PROXY_REMOTEURL = "https://registry-1.docker.io";
      };
    };

    ghcr-registry-cache = {
      image = "registry:2";
      ports = [ "5001:5000" ];
      volumes = [
        "/mnt/ssd/container-registry/cache/ghcr:/var/lib/registry"
      ];
      environment = {
        REGISTRY_PROXY_REMOTEURL = "https://ghcr.io";
      };
    };

    quay-registry-cache = {
      image = "registry:2";
      ports = [ "5002:5000" ];
      volumes = [
        "/mnt/ssd/container-registry/cache/quay:/var/lib/registry"
      ];
      environment = {
        REGISTRY_PROXY_REMOTEURL = "https://quay.io";
      };
    };

    gcr-registry-cache = {
      image = "registry:2";
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
                 /mnt/ssd/container-registry/gitlab
        chown -R docker-registry:docker-registry /mnt/ssd/container-registry/cache
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
        RuntimeDirectory = "docker-registry-gc";
        RuntimeDirectoryMode = "0700";
      };
      environment = {
        HOME = "/var/lib/docker-registry";
        XDG_RUNTIME_DIR = "/run/docker-registry-gc";
      };
      script = ''
        echo "Garbage collecting docker-registry-cache..."
        ${pkgs.podman}/bin/podman exec docker-registry-cache bin/registry garbage-collect /etc/docker/registry/config.yml --delete-untagged || true

        echo "Garbage collecting ghcr-registry-cache..."
        ${pkgs.podman}/bin/podman exec ghcr-registry-cache bin/registry garbage-collect /etc/docker/registry/config.yml --delete-untagged || true

        echo "Garbage collecting quay-registry-cache..."
        ${pkgs.podman}/bin/podman exec quay-registry-cache bin/registry garbage-collect /etc/docker/registry/config.yml --delete-untagged || true

        echo "Garbage collecting gcr-registry-cache..."
        ${pkgs.podman}/bin/podman exec gcr-registry-cache bin/registry garbage-collect /etc/docker/registry/config.yml --delete-untagged || true
      '';
      startAt = "Sunday 04:00:00";
    };
  } // lib.genAttrs [
    "podman-docker-registry-cache"
    "podman-ghcr-registry-cache"
    "podman-quay-registry-cache"
    "podman-gcr-registry-cache"
  ] (name: {
    requires = [ "container-registry-dir-init.service" ];
    after = [ "container-registry-dir-init.service" ];
    environment = {
      HOME = "/var/lib/docker-registry";
      XDG_RUNTIME_DIR = "/run/${lib.removePrefix "podman-" name}";
    };
    serviceConfig = {
      User = "docker-registry";
      Group = "docker-registry";
    };
  });
}
