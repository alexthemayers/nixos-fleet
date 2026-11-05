# GitLab Runner Service Configuration

This document describes the deployment and configuration details of the
**GitLab Runner** service in the `nixos-fleet` infrastructure.

## Overview

The GitLab Runner runs CI jobs. It runs on **`proxmox-dev-debian`**, which
answers on the tailnet as `proxmox-dev`. See
[proxmox-dev-debian.md](proxmox-dev-debian.md).

CI is lint/fmt/inventory/ansible-lint only. It does not build host
toplevels or deploy
([adr/2026-11-05-ci-lint-only.md](../adr/2026-11-05-ci-lint-only.md)).

## Networking and Ports

- **Metrics Interface**: Exposes Prometheus metrics on `[::]:9252`.
- **Backend Communications**: Connects outwards to GitLab via
  `https://gitlab.alexmayers.co.za`.

## Secrets Management

- **`gitlab/runner_token`**: Decrypted by SOPS and written to an
  environment file (`gitlab-runner-env`) to authorize the runner with
  GitLab.

## Storage and Rootless Podman Execution

To isolate build environments and keep them secure, the runner uses
**rootless Podman**:

1. **User Scope**: Runs as system user `gitlab-runner`. Sub-uid/gid
   mappings are defined to enable rootless networking and filesystem
   operations.
2. **Podman socket**: `gitlab-runner-podman.service` runs `podman system
   service` as `gitlab-runner` on
   `unix:///run/gitlab-runner/podman.sock`. `XDG_RUNTIME_DIR` is
   `/run/user/<uid>`, created before start. Pasta's AppArmor profile
   allows its netns and pid files only on that path. The socket
   directory is a systemd `RuntimeDirectory` and does not hold them. A
   cache volume starts a permission container on this network; that
   container fails when the runtime directory is `/run/gitlab-runner`.
3. **Execution Configuration**: The runner is registered with the
   `docker` executor, passing `--docker-host` pointing to the private
   rootless Podman socket. GitLab jobs use the `nixos/nix` image (Nix
   preinstalled; `.#ci-tools` for bash/make/openssh/python3/ansible/
   ansible-lint). See
   [adr/2026-11-05-ci-lint-only.md](../adr/2026-11-05-ci-lint-only.md).
   ```toml
   [[runners]]
     executor = "docker"
     [runners.docker]
       host = "unix:///run/gitlab-runner/podman.sock"
   ```
4. **State storage**: the runner keeps its state on the local VM disk at
   `/var/lib/gitlab-runner`. There is no build-cache attachment on
   `proxmox-dev` and no `hosts/proxmox-dev/buildcache.nix`; the
   `config/build-cache.nix` loopback-image module exists but its only
   consumer is the container registry (see
   [container-registry.md](container-registry.md)). Runner disk usage is
   therefore bounded by the VM disk, which is worth watching if job
   artifacts grow.
5. **No privileged containers**: `--docker-privileged` is deliberately
   off so a CI job cannot read the operator age key on this host.

## Key Configurations

- **Registry Mirrors Integration**: Overwrites
  `/etc/containers/registries.conf` for Podman runtimes to force the
  runner to pull image layers from the local caches (e.g.
  `proxmox-applications-2:5000` for Docker Hub) rather than downloading
  them over the WAN on every job run.
- **Concurrency**: Set to a maximum of `10` concurrent jobs; the docker
  executor `limit` is 4. The `test` job also takes
  `resource_group: proxmox-dev-nix` so a flake check does not overlap
  other Nix work on the 12 GiB VM.
- **DynamicUser Disabled**: Dynamic system users are disabled on the
  systemd service to prevent group and file permission conflicts when
  interacting with the socket.

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
