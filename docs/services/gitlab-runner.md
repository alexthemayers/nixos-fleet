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
   the private rootless Podman socket. GitLab jobs use the `nixos/nix` image (Nix preinstalled; `.#ci-tools` for
   bash/make/openssh/python3). rpi4 jobs override to `debian:trixie-slim` and only SSH. See
   [adr/2026-08-31-gitlab-ci-pipeline.md](../adr/2026-08-31-gitlab-ci-pipeline.md).
   ```toml
   [[runners]]
     executor = "docker"
     [runners.docker]
       host = "unix:///run/gitlab-runner/podman.sock"
   ```
4. **State storage**: the runner keeps its state on the local VM disk at `/var/lib/gitlab-runner`. There is no
   build-cache attachment on `proxmox-dev` and no `hosts/proxmox-dev/buildcache.nix`; the `config/build-cache.nix`
   loopback-image module exists but its only consumer is the container registry (see
   [container-registry.md](container-registry.md)). Runner disk usage is therefore bounded by the VM disk, which is
   worth watching if job artifacts grow.
5. **No privileged containers**: `--docker-privileged` is deliberately off so a
   CI job cannot read the operator age key on this host. aarch64 fill/deploy
   does **not** run here: GitLab `fill-attic-rpi4` / `deploy-rpi4` ssh to
   `rpi4` and compile natively ([adr/2026-08-31-rpi4-native-build.md](../adr/2026-08-31-rpi4-native-build.md)).

## Key Configurations
- **Registry Mirrors Integration**: Overwrites `/etc/containers/registries.conf` for Podman runtimes to force the runner
  to pull image layers from the local caches (e.g. `proxmox-applications-2:5000` for Docker Hub) rather than downloading
  them
  over the WAN on every job run.
- **Concurrency**: Set to a maximum of `10` concurrent jobs.
- **DynamicUser Disabled**: Dynamic system users are disabled on the systemd service to prevent group and file
  permission conflicts when interacting with the socket.

## Alerting

Rules live in the `gitlab-runner` group in
[`services/mimir-rules.nix`](../../services/mimir-rules.nix). User job
failures (`gitlab_runner_failed_jobs_total`) are not paged.
Dashboard: `fleet-gitlab`.

| Alert | Catches |
|---|---|
| `GitLabRunnerErrors` | `level=~"error|fatal|panic"` |
| `GitLabRunnerHealthCheckFailing` | worker health-check failures |
| `GitLabRunnerConfigLoadFailed` | config reload errors |
