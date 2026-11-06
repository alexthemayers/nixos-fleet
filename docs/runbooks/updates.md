# Runbook: updates

Cadence and reasons: [2026-11-04-update-process](../adr/2026-11-04-update-process.md).
A full reboot with no package changes: [fleet-reboot.md](fleet-reboot.md).
Rollback: [rollback.md](rollback.md).

| What | When | How |
|------|------|-----|
| Debian and Debian-Security on guests | nightly 03:30, automatic | `unattended-upgrades`; reboot slot below |
| Guest reboot after a kernel or libc update | nightly, automatic | VM 109 04:00, 110 04:20, 112 04:40, 111 05:00 |
| Third-party repos, images, `gitlab-ce`, `flake.lock` | monthly, first Tuesday | [Monthly window](#monthly-guest-window) |
| Hypervisor, then TrueNAS | quarterly, Sunday morning | [Quarterly window](#quarterly-hypervisor-window) |
| Critical CVE (kernel, QEMU, openssh, Tailscale) | within 72 hours | the same window, only that package |

Start every window after the 02:00 Postgres and 03:00 GitLab backups have
landed. Run it from the laptop, never from a CI job on the guest being
updated.

## Check first

Open the `Updates and reboots (alerts)` dashboard (`fleet-updates`), or:

```bash
for h in proxmox proxmox-applications-debian proxmox-gitlab-debian \
         proxmox-observability-debian proxmox-dev; do
  echo "== $h"
  ssh root@$h 'apt-get update -qq; apt list --upgradable 2>/dev/null | grep -v Listing;
    test -f /var/run/reboot-required && echo REBOOT-REQUIRED; uname -r; apt-mark showhold'
done
```

Stop if an alert is firing that the window would make worse (`ServiceDown`,
`BackupJobFailed`, a Postgres or NFS alert).

## Monthly guest window

One guest at a time, in this order: cloud hosts (below), 109, 110, 112, 111.
111 goes last so Prometheus and Grafana can watch the others restart.

1. **Snapshot** the guest root (a qcow2 on NFS):
   `ssh root@proxmox 'qm snapshot <vmid> pre-update-$(date +%F)'`. Delete the
   snapshot after a week with `qm delsnapshot`.
2. **Upgrade:** `ssh root@<guest> 'apt-get update && apt-get -y upgrade'`.
   This includes Tailscale, Vector, and GitLab Runner. `gitlab-ce` stays held
   (see below).
3. **Reboot** if `/var/run/reboot-required` exists:
   `ssh root@<guest> systemctl reboot`. Do not use `qm reboot`: it can hang
   and leave a lock (VM 110, 2026-11-04).
4. **Verify** with the table below, then go on to the next guest.

For VM 112 pause the runner first (`systemctl stop gitlab-runner`, which
lets no new job start; wait for running jobs) and start it again after.

### Verify, per guest

| VM | Check | Healthy |
|----|-------|---------|
| 109 | `ssh root@proxmox-applications-debian curl -s -o /dev/null -w '%{http_code}' localhost:9000/health/ready` (Keycloak), and `https://jellyfin.alexmayers.co.za/web/` | 200 |
| 110 | `ssh root@proxmox-gitlab-debian curl -s -o /dev/null -w '%{http_code}' localhost:8080/-/readiness` | 200. It is 502 for about 60 s after boot |
| 111 | on the guest: `curl -s localhost:9090/-/ready`, `curl -s localhost:3100/ready`, `curl -s localhost:3000/api/health` | 200. Loki is 503 for up to 3 minutes after boot |
| 112 | `ssh root@proxmox-dev nix --version`, `systemctl is-active gitlab-runner` | active |
| all | `systemctl --failed`, and `up{host="<guest>"}` in Prometheus | none failed, all 1 |

Then check that `HostRebootRequired` is clear.

### Container images

Images are pinned by digest in the `apps` and `observability` role defaults
(`debian_guest_obs_images` and `debian_guest_podman_apps`). Check upstream for a
newer tag, change the digest, then apply the role tag for that app:
`make deploy-debian-guest ANSIBLE_ARGS="--tags <app>"`. Each app user keeps
its own Podman store, so old images pile up: after a bump run
`podman image prune -a` as that user. VM 109's 35 GiB root was 96% full on
2026-11-04 (`NodeFilesystemAlmostOutOfSpace`), and apt needs room to unpack.
Before raising a
memory cap compare live RSS with the row in [memory.md](../memory.md). Grafana
stalled at a 512 MiB `MemoryHigh` for exactly that reason.

### GitLab

`gitlab-ce` is held at the version in `proxmox-gitlab-debian.yml`. Never
`apt upgrade` it. Follow GitLab's upgrade path for the next required stop,
and before you start:

1. `gitlab-backup create` on VM 110, then wait for `gitlab-backup-sync`.
2. A ZFS snapshot on TrueNAS of the GitLab and registry datasets. The
   qcow2 snapshot does not cover the loop images on NFS.
3. A fresh dump of the `gitlab` database from `xcloud-postgres`. A schema
   migration cannot be undone by the old package ([restore-gitlab.md](restore-gitlab.md)).

Then change `debian_guest_gitlab_version`, `apt-mark unhold gitlab-ce`,
`make deploy-debian-gitlab ANSIBLE_ARGS="--tags gitlab"`, and hold it again.

### Nix hosts

`nix flake update` on a branch, merge to `main` when the CI gate is green,
then deploy from `proxmox-dev` (`make deploy-host HOST=…` /
`./scripts/deploy-host.sh`). The NixOS hosts are `xcloud-caddy`,
`xcloud-postgres`, and `gaming`.
Do `xcloud-postgres` and `xcloud-caddy` one at a time: both are single
points of failure. Reboot only for a kernel change.

## Quarterly hypervisor window

Expect 10 to 12 minutes with every service down (2026-11-04: about 5 for
the guests to shut down, 2 for the host to boot, TrueNAS then a 90 s delay
(`startup order=1,up=90`), then 109 to 112, and Loki ready 3 minutes later).

1. Check [the pending list](#check-first), the alerts, and that last night's
   backups landed. Tell anyone who uses Jellyfin.
2. Snapshot VMs 109 to 112 (`qm snapshot`). Export the TrueNAS config and
   check that the last scrub was clean. Snapshot the datasets on TrueNAS (the hypervisor has no ZFS pool).
3. `make proxmox-host-check`. **Do not pass `--tags packages` or any tag
   that includes the `packages` role: the `apt_upgrade` task inherits that
   tag and runs a full `dist-upgrade`.** Run the upgrade on purpose:
   `cd ansible && ansible-playbook -i inventory/proxmox.ini proxmox.yml --tags apt_upgrade`.
4. **DKMS gate.** `ssh root@proxmox 'dkms status; dpkg --audit'`. Every
   module must show `installed` for the new kernel and `dpkg --audit` must be
   empty. A DKMS failure aborts the kernel postinst: the package stays half
   configured and `update-grub` still lists a kernel with no initrd. Do not
   reboot like that. Rebuild the module, or if the module is unused finish
   with the dkms hook disabled and say so in the log.
   `r8125` is needed. The host binds the iGPU with `vfio-pci`, so
   `i915-sriov-dkms` is not used at runtime.
5. `proxmox-boot-tool` is not used. GRUB boots the newest kernel
   (`GRUB_DEFAULT=0`) and there is no console: keep the previous kernel
   installed and confirm the new one has an `initrd.img-*` file and a
   `grub.cfg` entry before the reboot.
6. Stop the guests in reverse order (`qm shutdown <vmid> --timeout 120`):
   112, 111, 110, 109, then 100. Then `ssh root@proxmox reboot`. A host with
   `onboot` set starts them again in order.
7. **Verify:**
   * `uname -r` is the new kernel, `pveversion` is current
   * SR-IOV VFs exist: `ip -br link | grep -c enp2s0f1v`
   * the iGPU is bound: `lspci -nnk -s 00:02.0` shows `vfio-pci`, and the
     `node_hardware_pci_driver_bound{device_name="igpu"}` series is 1
   * `qm list` shows 100 and 109 to 112 running, and VMs 101, 102, 103, 106
     stay absent
   * the per-guest table above, and the `fleet-hardware` dashboard
8. VMs that were running during the upgrade still run the old QEMU. They pick
   up the new one with the reboot above. `qm reboot` does not.

Roll back with the previous kernel from the GRUB menu at the console, or
`qm rollback <vmid> pre-update-<date>` for a guest.

### TrueNAS

A TrueNAS update is the same outage with the guests stopped first: step 6
without the reboot, update VM 100, then start 100 and wait until `ssh
root@truenas-scale true` and NFS answer before starting 109 to 112.

## Out of band (critical CVE)

Update only the affected package set on the affected host, with the monthly
verify table. `HostSecurityUpdatesPending` reaches you after three days if
you miss it.

## Refresh a pinned vendor key

`get_url` fails with a checksum mismatch when a vendor rotates an APT
signing key ([ADR](../adr/2026-11-06-pin-ansible-downloads.md)). Treat the
failure as a stop, not a nuisance:

1. Fetch the key from the vendor's documented install page, not from the
   failing deploy. Compare the fingerprint with the vendor's published one
   (`gpg --show-keys <file>`).
2. Hash it: `curl -fsSL <url> | sha256sum`.
3. Update the hash where it is pinned and run `make check-ansible-downloads`:
   - guests: `debian_guest_*_key_sha256` in
     `collections/ansible_collections/fleet/debian_guest/inventory/group_vars/all.yml`
     (Tailscale, GitLab and GitLab Runner share one key, Vector uses Datadog's)
   - hypervisor: the `sha256` next to each key in
     `ansible/roles/apt_repos/tasks/main.yml`
4. Redeploy and confirm `apt update` succeeds on the host.

Collections are pinned in both `requirements.yml` files. Bump them together
with a green `make ansible-lint`.

## Alerts

[prometheus.md](../services/prometheus.md#alerting) lists `updates`:
`HostSecurityUpdatesPending`, `HostRebootRequired`, `HostUpdatesStale`,
`HypervisorUpdatesStale`, `HostAptCacheStale`.
