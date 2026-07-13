# Container Registry Service Configuration

This document describes the deployment and configuration details of the **Container Registry** service in the
`nixos-fleet` infrastructure.

## Overview

The container registry system acts as a pull-through cache for remote container images and provides storage for GitLab's
container registry. It is deployed on **`proxmox-applications-2`**.

## Networking and Ports

Local registry cache containers expose the following ports:

- `5000` (TCP) &rarr; Docker Hub Registry Cache
- `5001` (TCP) &rarr; GHCR Registry Cache
- `5002` (TCP) &rarr; Quay Registry Cache
- `5003` (TCP) &rarr; GCR Registry Cache
- `5005` (TCP) &rarr; GitLab Container Registry (reverse proxied via Caddy as `registry.alexmayers.co.za`)

## Storage and Mounts

To handle heavy registry IO without impacting SSD lifecycle or saturating the host's filesystem, a loopback NFS
attachment is configured:

- **Build Cache Attachment**: `services.build-cache.attachments.container-registry` mounts the NFS share
  `truenas-scale:/mnt/ssd/container-registry` to `/mnt/nfs/container-registry`.
- **Loopback Mount**: A sparse image file `container-registry.img` (50G size) is created on the NFS share and mounted
  locally to `/mnt/ssd/container-registry` formatted as `ext4`.
- **Registry Folders**: Subdirectories are structured as follows:
    - `/mnt/ssd/container-registry/cache/docker`, `/ghcr`, `/quay`, `/gcr` (used by Podman cache containers).
    - `/mnt/ssd/container-registry/gitlab` (bind-mounted to `/var/lib/gitlab/shared/registry` for GitLab's registry
      storage).

## Key Configurations

- **Rootless Podman Cache Containers**: Caches are deployed using rootless Podman containers run as the system user
  `docker-registry`. Sub-uid/gid mappings are defined to isolate container operations:
  ```nix
  users.users.docker-registry = {
    subUidRanges = [ { startUid = 500000; count = 65536; } ];
    subGidRanges = [ { startGid = 500000; count = 65536; } ];
  };
  ```
- **Weekly Garbage Collection**: A oneshot systemd service (`container-registry-gc`) runs at Sunday 04:00:00 to clean up
  untagged cached layers across all registries using:
  ```bash
  podman exec <container> bin/registry garbage-collect /etc/docker/registry/config.yml --delete-untagged
  ```
- **Registry Mirrors**: Host nodes route their container runtime pull requests to these local caches by overriding
  `/etc/containers/registries.conf` (e.g. mapping `docker.io` requests to `proxmox-applications-2:5000`).
