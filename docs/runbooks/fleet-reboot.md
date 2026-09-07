# Runbook: full fleet reboot

Reboots the hypervisor and every on-prem guest so boot order and
`fleet.waitForHost` are real. Cloud VMs reboot independently.

> Warnings
>
> - **Start VM 100 first.** Every other guest root is NFS on TrueNAS.
> - `make reboot-all` skips `gaming` and does not reboot the hypervisor.
> - `rpi4` and `gaming` may be offline; do not block on them.
> - Do not `qm destroy` anything in this window.

## Step 1 — Cloud

```bash
ssh root@xcloud-caddy reboot
ssh root@xcloud-postgres reboot
```

Wait until both answer SSH and `pg_isready` on `:5433` is 0.

## Step 2 — Guests, then the hypervisor

```bash
ssh root@proxmox 'qm shutdown 101 --timeout 120'
ssh root@proxmox 'qm shutdown 102 --timeout 120'
ssh root@proxmox 'qm shutdown 103 --timeout 120'
ssh root@proxmox 'qm shutdown 106 --timeout 120'
ssh root@proxmox reboot
```

## Step 3 — Boot order after the hypervisor is up

```bash
ssh root@proxmox 'qm start 100'
# wait until TrueNAS SSH and NFS answer
ssh root@truenas-scale true
ssh root@proxmox 'qm start 101; qm start 102; qm start 103; qm start 106'
```

## Step 4 — Verify

```bash
curl -sS -o /dev/null -w '%{http_code}\n' http://proxmox-applications-1:9000/health/ready
curl -sS -o /dev/null -w '%{http_code}\n' http://proxmox-observability:3903/health
curl -sS -o /dev/null -w '%{http_code}\n' http://proxmox-observability:3000/api/health
curl -sS -o /dev/null -w '%{http_code}\n' https://grafana.alexmayers.co.za/api/health
curl -sS -o /dev/null -w '%{http_code}\n' http://proxmox-dev:8080/attic/nix-cache-info
```

atticd and Grafana have `restartIfChanged = false` on deploy; after a
reboot the new process is the running one. Check `systemctl --failed` on
each guest.
