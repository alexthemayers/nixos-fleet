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
    owner = "root";
    group = "root";
    mode = "0755";
  };

  # 2. Systemd service to initialize the subdirectories for caches and gitlab registry
  systemd.services.container-registry-dir-init = {
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
      chown -R root:root /mnt/ssd/container-registry/cache
      chown -R gitlab:docker-registry /mnt/ssd/container-registry/gitlab
      chmod -R 755 /mnt/ssd/container-registry/cache
      chmod 770 /mnt/ssd/container-registry/gitlab
    '';
  };

  # 3. Pull-through registry cache containers running via rootful Podman
  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers = {
    docker-registry-cache = {
      image = "registry:2";
      ports = [ "127.0.0.1:5000:5000" ];
      volumes = [
        "/mnt/ssd/container-registry/cache/docker:/var/lib/registry"
      ];
      environment = {
        REGISTRY_PROXY_REMOTEURL = "https://registry-1.docker.io";
      };
    };

    ghcr-registry-cache = {
      image = "registry:2";
      ports = [ "127.0.0.1:5001:5000" ];
      volumes = [
        "/mnt/ssd/container-registry/cache/ghcr:/var/lib/registry"
      ];
      environment = {
        REGISTRY_PROXY_REMOTEURL = "https://ghcr.io";
      };
    };

    quay-registry-cache = {
      image = "registry:2";
      ports = [ "127.0.0.1:5002:5000" ];
      volumes = [
        "/mnt/ssd/container-registry/cache/quay:/var/lib/registry"
      ];
      environment = {
        REGISTRY_PROXY_REMOTEURL = "https://quay.io";
      };
    };

    gcr-registry-cache = {
      image = "registry:2";
      ports = [ "127.0.0.1:5003:5000" ];
      volumes = [
        "/mnt/ssd/container-registry/cache/gcr:/var/lib/registry"
      ];
      environment = {
        REGISTRY_PROXY_REMOTEURL = "https://gcr.io";
      };
    };
  };

  # Set systemd service dependencies for the OCI containers to wait for directory initialization
  systemd.services.podman-docker-registry-cache = {
    requires = [ "container-registry-dir-init.service" ];
    after = [ "container-registry-dir-init.service" ];
  };
  systemd.services.podman-ghcr-registry-cache = {
    requires = [ "container-registry-dir-init.service" ];
    after = [ "container-registry-dir-init.service" ];
  };
  systemd.services.podman-quay-registry-cache = {
    requires = [ "container-registry-dir-init.service" ];
    after = [ "container-registry-dir-init.service" ];
  };
  systemd.services.podman-gcr-registry-cache = {
    requires = [ "container-registry-dir-init.service" ];
    after = [ "container-registry-dir-init.service" ];
  };

  # 4. Configure Podman mirrors to pull from local pull-through caches
  environment.etc."containers/registries.conf.d/mirror.conf".text = ''
    [[registry]]
    location = "docker.io"
    [[registry.mirror]]
    location = "localhost:5000"
    insecure = true

    [[registry]]
    location = "ghcr.io"
    [[registry.mirror]]
    location = "localhost:5001"
    insecure = true

    [[registry]]
    location = "quay.io"
    [[registry.mirror]]
    location = "localhost:5002"
    insecure = true

    [[registry]]
    location = "gcr.io"
    [[registry.mirror]]
    location = "localhost:5003"
    insecure = true
  '';

  # 5. Weekly automated garbage collection service to prune unreferenced cache layers
  systemd.services.container-registry-gc = {
    description = "Garbage collect container registry caches";
    serviceConfig = {
      Type = "oneshot";
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
}
