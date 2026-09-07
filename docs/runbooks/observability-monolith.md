# Runbook: observability monolith and Garage on obs-1

Collapses `proxmox-observability-2`, `proxmox-db-1`, and `proxmox-db-2` onto
`proxmox-observability`. Why:
[observability monolith](../adr/2026-09-07-observability-monolith.md),
[Garage on obs-1](../adr/2026-09-07-garage-on-obs-1.md).

> Warnings
>
> - **Garage `replication_factor` cannot change on a live cluster.** This
>   cutover is a **new** RF=1 layout on obs-1, not a layout-remove of db-2.
>   Import the existing S3 keys so Loki, Mimir, and Attic do not need a
>   secret rotation.
> - **Raise obs-1 RAM before enabling Garage on it.** The 4 GiB guest is
>   already pressing Grafana and Prometheus caps. Target 8 GiB / 4 vCPU
>   (VM 103).
> - **Deploy order matters.** obs-1 (new Garage) while the old cluster is
>   still serving `proxmox-lb:3902`, then copy objects, then switch Caddy
>   (deploy `proxmox-lb`), then destroy the old VMs.
> - **Do not mount the live db-1 data dir on the new node.** The new
>   cluster uses `truenas-scale:/mnt/ssd/garage/obs`. Two Garage daemons
>   must not share a data directory.
> - **Rename Tailscale before the first `deploy-from-attic.sh
>   proxmox-observability`.** That script SSHs to the flake hostname. Set
>   `tailscale set --hostname=proxmox-observability` on the live guest
>   (still reachable as `proxmox-observability-1`) first.
> - Do not `chown` `/var/lib/garage` to `garage`. Do not `garage repair
>   blocks`. Clients stay on `proxmox-lb:3902`.

## Pre-flight

1. Snapshot the VM disks (same command as
   [fleet-simplification-migration.md](fleet-simplification-migration.md)
   Step 1).
2. Confirm the old cluster is healthy:

   ```bash
   ssh root@proxmox-db-1 'garage status'
   ```

3. Decrypt the live S3 keys on the operator workstation (do not print them
   into chat or a ticket). You need `loki/s3_access_key` +
   `loki/s3_secret_key`, the mimir pair, and Attic's Garage key from
   `secrets/proxmox-dev/secrets.yaml` (`attic/env` or the bootstrap key
   file on db-1 under `/var/lib/garage/keys/attic-key.txt`).

## Step 1 — Size the guest and rename it

```bash
ssh root@proxmox 'qm set 103 --memory 8192 --cores 4 --name proxmox-observability'
ssh root@proxmox 'qm config 103 | grep -E "memory|cores|name"'
ssh root@truenas-scale 'mkdir -p /mnt/ssd/garage/obs'
ssh root@proxmox-observability-1 'tailscale set --hostname=proxmox-observability'
# wait until MagicDNS answers
tailscale ping -c 1 proxmox-observability
```

Reboot VM 103 if QEMU does not hot-plug the RAM. Confirm `free -h` shows
~8 GiB before Step 2. `ssh/fleet_known_hosts` pins both names to the same
host key for the DNS handoff.

## Step 2 — Deploy obs-1 (new Garage, old S3 still on db VMs)

The guest now imports `services/garage.nix`, RF=1, NFS
`truenas-scale:/mnt/ssd/garage/obs`. The old daemons keep
`/mnt/ssd/garage/data` until you destroy them.

**Do not deploy `proxmox-lb` yet.** Caddy must keep round-robin to db-1/db-2
until the new node has keys, buckets, and a copy of the objects.

```bash
# from proxmox-dev, after rsync of this tree
./scripts/deploy-from-attic.sh proxmox-observability
```

Restart the units this generation changes (`restartIfChanged = false` on
Loki/Mimir/ntfy):

```bash
ssh root@proxmox-observability 'systemctl restart garage loki mimir grafana prometheus alertmanager ntfy-sh'
```

## Step 3 — Layout the new cluster and import keys

`garage-bootstrap.service` **creates new keys** if `loki-key` / `mimir-key` /
`attic-key` are missing. Stop it before applying the layout, or it will mint
credentials that do not match the sops secrets Loki, Mimir, and Attic already
use.

On obs-1, after `garage.service` is active:

```bash
ssh root@proxmox-observability
systemctl stop garage-bootstrap
eval $(grep -E 'GARAGE_RPC_SECRET_FILE|GARAGE_ADMIN_TOKEN_FILE' /etc/systemd/system/garage.service)
export GARAGE_RPC_SECRET=$(cat "$GARAGE_RPC_SECRET_FILE")
export GARAGE_ADMIN_TOKEN=$(cat "$GARAGE_ADMIN_TOKEN_FILE")

garage status
# node ID is the hex in the first column of unconfigured / layout nodes

garage layout assign -z dc1 -c 1T <node-id>
garage layout apply --version 1
garage status   # one node, replication_factor 1, cluster_healthy
```

Import the **existing** keys (the names bootstrap also uses):

```bash
garage key import --yes -n loki-key "<loki access>" "<loki secret>"
garage key import --yes -n mimir-key "<mimir access>" "<mimir secret>"
garage key import --yes -n attic-key "<attic access>" "<attic secret>"
# web-assets-key: import if a live client uses it; otherwise let bootstrap create it
systemctl start garage-bootstrap
systemctl reset-failed garage-bootstrap
```

Bootstrap then creates missing buckets and `bucket allow`. Confirm
`garage key info loki-key` shows the imported access key, not a new one.

## Step 4 — Copy objects, or refill Attic

While db-1/db-2 still serve `proxmox-lb:3902`, sync into the new node on
`:3902` (tailnet, not the LB, so you do not race yourself):

```bash
# example: rclone or mc, path-style, region garage, insecure
# source:  http://proxmox-db-1:3902  buckets loki, mimir, attic, web-assets
# dest:    http://proxmox-observability:3902
```

Attic is faster to **re-fill** from `cache.nixos.org` than to copy
([fill-then-exclusive](../adr/2026-08-30-attic-fill-then-exclusive.md)).
Loki (31 days) and Mimir blocks are reconstructible if you skip the copy;
Grafana history has a gap until new samples arrive.

Postgres still has Attic narinfos after an empty Garage. atticd then
returns **200** with a truncated NAR, which is not a substituter miss, so
a normal fill retries Attic and never reaches `cache.nixos.org`. Fill
without Attic as a substituter:

```bash
# on proxmox-dev, after rsync
ATTIC_FILL_PUBLIC_ONLY=1 ./scripts/build.sh
```

Then `make verify-from-attic` (or `./scripts/verify-from-attic.sh`) on
proxmox-dev. Confirm a GET of a known Attic key on
**proxmox-observability:3902** returns 200 before Step 5 if you copied
objects; after a public-only fill, the push itself is the proof.

## Step 5 — Point Caddy at proxmox-observability

```bash
./scripts/deploy-from-attic.sh proxmox-lb
curl -sS -o /dev/null -w '%{http_code}\n' http://proxmox-lb:3903/health
```

Then deploy `proxmox-dev` so Attic's wait-for-host follows
`proxmox-observability:3902`. Restart `atticd` if the switch left the old
process.

Loki and Mimir on `proxmox-observability` already wait for local Garage;
they do not need a second host deploy.

## Step 6 — Retire the old VMs

When Grafana, Attic (`nix copy` a known path), and `garage status` on
`proxmox-observability` look right for a full scrape interval:

```bash
ssh root@proxmox 'qm shutdown 104 --timeout 60'   # obs-2
ssh root@proxmox 'qm shutdown 107 --timeout 60'   # db-1
ssh root@proxmox 'qm shutdown 108 --timeout 60'   # db-2
ssh root@proxmox 'qm destroy 104 --purge 1'
ssh root@proxmox 'qm destroy 107 --purge 1'
ssh root@proxmox 'qm destroy 108 --purge 1'
```

Done 2026-09-07. Do **not** delete TrueNAS `ssd/garage/data` or
`ssd/garage/data-replica-1` until you are sure nothing still reads them.
Live Garage is `truenas-scale:/mnt/ssd/garage/obs`.

## Step 7 — Alerts and docs check

- `LokiRingWrongSize` should want 1, not 2. Restart `mimir.service` on
  `proxmox-observability` (`restartIfChanged = false`).
- `GarageClusterUnhealthy` description names `proxmox-observability`.
- `make check-inventory` and `make lint` already passed on this tree.

## Rollback

The db and obs-2 guests are gone. Rollback is a Nix generation of
`proxmox-observability`, not starting 104/107/108.
[rollback.md](rollback.md). Keep `ssd/garage/data` until you decide the
old objects are unused.
