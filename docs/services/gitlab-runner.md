# GitLab Runner Service Configuration

This document describes the deployment and configuration details of the **GitLab Runner** service in the `nixos-fleet`
infrastructure.

## Overview

The GitLab Runner compiles software and runs CI/CD jobs. In this fleet, it is deployed on the main builder node, *
*`proxmox-dev`**.

## Networking and Ports

- **Metrics Interface**: Exposes Prometheus metrics on `[::]:9252`.
- **Backend Communications**: Connects outwards to GitLab via `https://gitlab.alexmayers.co.za`.

## Secrets Management

- **`gitlab/runner_token`**: Decrypted by SOPS and written to an environment file (`gitlab-runner-env`) to authorize the
  runner with GitLab.

## Storage and Rootless Podman Execution

To isolate build environments and keep them secure, the runner uses **rootless Podman**:

1. **User Scope**: Runs as system user `gitlab-runner`. Sub-uid/gid mappings are defined to enable rootless networking
   and filesystem operations.
2. **Podman Socket Service**: A dedicated service (`gitlab-runner-podman-socket`) executes `podman system service`
   listening on a private UNIX socket at `unix:///run/gitlab-runner/podman.sock` under the `gitlab-runner` user.
3. **Execution Configuration**: The runner is registered with the `docker` executor, passing `--docker-host` pointing to
   the private rootless Podman socket:
   ```toml
   [[runners]]
     executor = "docker"
     [runners.docker]
       host = "unix:///run/gitlab-runner/podman.sock"
   ```
4. **State Bind Mount (`build-cache.nix`)**: To accelerate IO, prevent local SD/SSD degradation, and decouple the
   storage requirement from the VM disk size, the state directory `/var/lib/gitlab-runner` is bind-mounted to
   `/nix/var/nix/builds/gitlab-runner`. This path is provided by `hosts/proxmox-dev/buildcache.nix`, which configures a
   150G sparse image (`proxmox-dev-buildcache.img`) stored on the TrueNAS NFS share and mounted as a local ext4 loopback
   device.

## Key Configurations

- **Registry Mirrors Integration**: Overwrites `/etc/containers/registries.conf` for Podman runtimes to force the runner
  to pull image layers from the local caches (e.g. `proxmox-applications-2:5000` for Docker Hub) rather than downloading
  them
  over the WAN on every job run.
- **Concurrency**: Set to a maximum of `10` concurrent jobs.
- **DynamicUser Disabled**: Dynamic system users are disabled on the systemd service to prevent group and file
  permission conflicts when interacting with the socket.
