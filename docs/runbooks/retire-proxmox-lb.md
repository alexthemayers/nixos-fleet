# Runbook: retire proxmox-lb

Removes VM 105 and the second routing tier. Why:
[no internal LB](../adr/2026-09-07-no-internal-lb.md).

> Warnings
>
> - **Deploy the edge last among public-path hosts.** Internal clients can
>   talk to backends while Caddy still uses `proxmox-lb:80`. Public traffic
>   flips when `xcloud-caddy` switches.
> - **Stop Keycloak and Vikunja on apps-2 before setting Keycloak
>   `cache=local` on apps-1.** Do not leave one JVM on Infinispan and one
>   on local cache.
> - VM 105 is **destroyed**. Do not recreate it. Rollback is a Nix
>   generation of `xcloud-caddy`, not starting the old guest.
> - Substituters stay `http://proxmox-dev:8080/attic`. Do not put Caddy in
>   front of multi-chunk NARs.

## Pre-flight

1. Fill Attic on `proxmox-dev` (`./scripts/build.sh`). If Garage is empty
   of NARs, `ATTIC_FILL_PUBLIC_ONLY=1`.
2. Confirm apps-1 Keycloak `/health/ready` on `:9000` and Vikunja
   `/api/v1/info` on `:3456` return 200.

## Step 1 — Deduplicate, then internal clients

From `ssh -A root@proxmox-dev` after rsync:

```bash
./scripts/deploy-from-attic.sh proxmox-applications-2
./scripts/deploy-from-attic.sh proxmox-applications-1
./scripts/deploy-from-attic.sh proxmox-observability
systemctl restart grafana mimir loki   # restartIfChanged = false
./scripts/deploy-from-attic.sh proxmox-dev
systemctl restart atticd
```

apps-2 no longer imports Keycloak or Vikunja. apps-1 Keycloak uses
`cache=local`. Grafana datasources, Alloy, Loki, Mimir, and Attic S3 now
use `proxmox-observability` (Grafana on loopback).

## Step 2 — Edge Caddy

```bash
./scripts/deploy-from-attic.sh xcloud-caddy
```

Confirm Host-header vhosts and UDP still work:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' -H 'Host: grafana.alexmayers.co.za' http://proxmox-observability:3000/api/health
curl -sS -o /dev/null -w '%{http_code}\n' https://grafana.alexmayers.co.za/api/health
curl -sS -o /dev/null -w '%{http_code}\n' http://proxmox-applications-1:9000/health/ready
curl -sS -o /dev/null -w '%{http_code}\n' http://proxmox-observability:3903/health
```

## Step 3 — Remaining Alloy hosts and the hypervisor

Alloy on every fleet host writes to `proxmox-observability:3100`. Deploy
`xcloud-postgres`, `gaming`, and `rpi4`. Then Ansible:

```bash
make deploy-proxmox-host
```

WAL on undeployed hosts buffers until this step.

## Step 4 — Stop and destroy VM 105

Done 2026-09-07 after the edge flip. Remaining hypervisor guests are
100–103 and 106.

```bash
ssh root@proxmox 'qm shutdown 105 --timeout 60'
ssh root@proxmox 'qm destroy 105 --purge 1'
ssh root@proxmox 'qm list'
```

## Rollback

`xcloud-caddy` Nix generation that still proxies `proxmox-lb:80` only
works if someone recreates VM 105. Prefer pointing the edge at the
serving VMs. Nix rollback: [rollback.md](rollback.md).
