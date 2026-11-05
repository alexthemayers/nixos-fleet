# Runbook: full fleet reboot

Reboots the hypervisor and every on-prem guest with no package change, so
boot order and `fleet.waitForHost` are real. Updates:
[updates.md](updates.md). Cloud VMs reboot independently.

> Warnings
>
> - **TrueNAS (VM 100) starts first.** Every other guest root is NFS on it.
>   `startup: order=1,up=90,down=90` does this on a host boot.
> - Expect 10 to 12 minutes with every service down.
> - `make reboot-all` skips `gaming` and does not reboot the hypervisor.
> - `rpi4` and `gaming` may be offline; do not block on them.
> - Do not `qm destroy` anything in this window.
> - Do not use `qm reboot` on a guest. It can hang and leave a lock. Use
>   `qm shutdown <vmid> --timeout 120` then `qm start`, or reboot inside the
>   guest.

## Step 1 — Cloud

```bash
ssh root@xcloud-caddy reboot
ssh root@xcloud-postgres reboot
```

Wait until both answer SSH and `pg_isready` on `:5433` is 0.

## Step 2 — Guests, then the hypervisor

Pause the runner first: `ssh root@proxmox-dev systemctl stop gitlab-runner`.

```bash
for vm in 112 111 110 109 100; do
  ssh root@proxmox "qm shutdown $vm --timeout 120"
done
ssh root@proxmox reboot
```

The hypervisor starts 100, waits 90 s, then starts 109 to 112 about 3 s
apart. If a guest does not start, `ssh root@proxmox qm start <vmid>`.

## Step 3 — Verify

* `ssh root@proxmox qm list`: 100 and 109 to 112 running; 101, 102, 103,
  and 106 absent
* the per-guest checks in [updates.md](updates.md#verify-per-guest)
* `systemctl start gitlab-runner` on `proxmox-dev`
* `systemctl --failed` on each guest. Grafana and Loki have
  `restartIfChanged = false` on NixOS, but on these guests the unit that
  started at boot is the current one.
* GitLab returns 200 about 60 s after boot and Loki up to 3 minutes. Do not
  call that a failure before then.
