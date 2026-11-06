# Debian builder

**Host:** `proxmox-dev-debian` (VM 112) · **MagicDNS:** `proxmox-dev` ·
**Collection:** [`fleet.debian_guest`](../../collections/ansible_collections/fleet/debian_guest)

Debian 13 replacement for `proxmox-dev` (VM 106). The Tailscale name
stays `proxmox-dev`. See
[2026-11-04-debian-dev-guest.md](../adr/2026-11-04-debian-dev-guest.md).

```bash
make deploy-debian-dev
make debian-dev-check
```

## Hardware

| Property | Value |
|----------|-------|
| VMID | 112 |
| CPU | `host`, 4 cores |
| RAM | 16 GiB, balloon off |
| Root | `truenas-storage`, 200 GiB |
| NIC | one VF from `Network-SRIOV`; MAC `82:cc:a5:22:e5:0c` |
| Tailscale | hostname `proxmox-dev`, port `41649` |

VM 106 was destroyed. A normal `make deploy-debian-dev` converges the
guest; there is no cutover flag.

## Updates

Debian and Debian-Security updates apply at 03:30 and the guest restarts at
04:40 when an update asks for it. Third-party repositories and images change
in the monthly window: [updates.md](../runbooks/updates.md).

## What runs

GitLab Runner `proxmox-gaming-runner`, rootless Podman, docker
executor, no privileged containers. Concurrency 10, limit 4. Each job
container is 12 GiB with no swap and 3 CPUs. The Podman service is
capped at 14 GiB. Registry mirrors are
`proxmox-gitlab-debian:5000`–`:5003`.

Multi-user Nix stays on this guest on purpose: it is the x86_64 deploy
builder (`ssh -A root@proxmox-dev`). Debian application guests do not
evaluate Nix. aarch64 stays on `rpi4`.

`backup-relay` owns `/var/backup-relay/`. Its shell is bash so the
rsync push can run. Postgres backups are kept 30 days and GitLab
backups 14 days. The push key is unchanged.

Coder does not run here.

## Router reboot

`proxmox-dev` is the only guest that drives the LAN router's web API. The
router credentials are in `secrets/router/secrets.yaml` (sops), encrypted to
the operator and to this VM's SSH host key. `make router-status` and `make
reboot-router` copy `scripts/router-reboot.py` to `/root/router-reboot/` and
run it there; the last log is `last-run.log`. Procedure:
[router-reboot.md](../runbooks/router-reboot.md).

## Observability

Node exporter, the systemd exporter, and Vector are the shared
monitoring role. Vector ships to `proxmox-observability-debian:3100`.
Runner metrics listen on `:9252`. The scrape target stays
`proxmox-dev:9252`.

## Rollback

VM 106 and its qcow2 disk were destroyed on 2026-11-04. There is no
NixOS builder to start. `secrets/proxmox-dev` remains (builder MagicDNS name). The Tailscale
node lives only on VM 112.
