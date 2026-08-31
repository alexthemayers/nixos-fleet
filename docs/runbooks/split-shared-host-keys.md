# Runbook: split the shared SSH host key on proxmox-dev, db-1 and db-2

**Status:** done (2026-08-28), with one follow-up outstanding. The three hosts now
have distinct host keys and distinct sops age identities, and every credential
the shared identity exposed has been rotated **except** the Tailscale exporter
OAuth client — see "What is still open" at the bottom.

## What was wrong

`proxmox-dev`, `proxmox-db-1` and `proxmox-db-2` all presented the **same**
`ssh_host_ed25519_key`. They were cloned from one Proxmox template and the host
keys were never regenerated — the old key's comment was literally
`root@proxmox-db` on all three, which is how the clone lineage was confirmed.
Verify the current state with:

```bash
for h in proxmox-dev proxmox-db-1 proxmox-db-2; do
  ssh-keyscan -t ed25519 "$h" 2>/dev/null | grep -v '^#' | awk '{print $3}'
done | sort -u | wc -l   # must print 3
```

Two consequences follow, and the second is the serious one:

1. **SSH host identity is not unique.** Host key verification cannot tell these
   three machines apart, so pinning host keys (which this repo now does, via
   `ssh/fleet_known_hosts`) does not distinguish them.

2. **They share a sops age identity.** sops-nix derives each host's age key from
   its SSH host key, which is why all three resolve to
   `age167zzzgyhnmxapu0z9w3qgqww4krm0ztmg20vejldkz6lf54fzssseunmdt` in
   `.sops.yaml`. Any one of the three can decrypt the other two's secrets.
   `proxmox-dev` runs the GitLab runner, so until this is fixed a CI job on that
   host can read the Garage RPC secret and the object-storage credentials
   belonging to both database nodes.

Removing `--docker-privileged` from the runner (already done) narrows the path
but does not close it: the age key is readable by root on `proxmox-dev`
regardless.

## Fix

Do one host at a time and keep a console session open, because you are changing
the key you are authenticating against.

For each of `proxmox-dev`, `proxmox-db-1`, `proxmox-db-2`:

1. Generate a fresh host key on the host:

   ```bash
   ssh root@<host> 'rm -f /etc/ssh/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key.pub \
     && ssh-keygen -t ed25519 -N "" -f /etc/ssh/ssh_host_ed25519_key \
     && systemctl restart sshd'
   ```

2. Record the new key on your workstation and confirm it changed:

   ```bash
   ssh-keygen -R <host>
   ssh root@<host> true          # accept and verify the new fingerprint
   ssh-keyscan -t ed25519 <host> | ssh-to-age
   ```

3. Put that age recipient into `.sops.yaml`, replacing the shared anchor for
   this host only. After all three are done there must be three distinct values.

4. Re-encrypt every secret file to the new recipients and deploy:

   ```bash
   make updatekeys
   scripts/update-known-hosts.sh
   make deploy-proxmox
   ```

   `make updatekeys` only re-wraps the data key. It does **not** change any
   secret value, so step 5 is not optional.

## Rotate afterwards

Everything these three hosts could decrypt must be treated as exposed to the CI
runner and rotated once the keys are split:

- Garage RPC secret (`garage/rpc_secret`) — rotate on all Garage nodes together,
  the cluster will not form across mismatched secrets
- All Garage S3 credentials: `loki`, `mimir`, `attic`, `web-assets`
  (`garage key delete` / `garage key create`, then update each consumer's secret)
- `tailscale/exporter_env` (the Tailscale OAuth client)

Deploy the consumers of each credential in the same window as the rotation, or
Loki, Mimir and Attic will fail to reach object storage.

## What was actually done (2026-08-28)

Executed in this order, one host at a time for the key regeneration:

1. Fresh `ssh_host_ed25519_key` on each of the three hosts, old key backed up to
   `/root/ssh_host_ed25519_key.bak` on each. Because `services.openssh` uses
   `startWhenNeeded = true` (socket activation), existing sessions survived and
   new connections picked up the new key immediately.
2. `.sops.yaml` updated so `proxmox_dev`, `proxmox_db_1` and `proxmox_db_2` are
   three distinct recipients, then `make updatekeys` — only those three secret
   files changed. Verified afterwards that each file lists exactly one host
   recipient, so no host can decrypt another's secrets.
3. `scripts/update-known-hosts.sh` regenerated `ssh/fleet_known_hosts`, and every
   pinned entry was diffed against the live key before the file was deployed.
4. All three hosts rebuilt and switched; `sops-install-secrets` confirmed
   importing the new per-host age identity on each, and all secrets re-decrypted.
5. Rotated `garage/rpc_secret` and `garage/admin_token` on both db nodes, then
   restarted `garage` on both in parallel so the cluster never ran with
   mismatched secrets for long. Cluster came back with both nodes healthy.
6. Deleted and recreated all four Garage S3 keys (`loki`, `mimir`, `web-assets`,
   `attic`) via `garage key delete` + `garage-bootstrap`, which also re-granted
   the bucket permissions. New credentials written into the observability and db
   secret files and deployed.

### Gotcha worth knowing for the next rotation

Rotating a secret and deploying is **not** sufficient on its own. These secrets
reach their services as *file paths*, so the systemd unit definition is byte-identical
before and after a rotation and nothing restarts it — Loki and Mimir kept serving
with the old S3 keys (throwing `403 AccessDenied ... No such key: GK14e6802b...`)
even though the new keys were already on disk. They had to be restarted by hand.

The fix is `restartUnits` on the `sops.secrets`/`sops.templates` declaration; it
is now set for Garage, Loki, Mimir, Attic and the Tailscale exporter. Attic
picked up its new credentials automatically on deploy as a result.

## What is still open

- **`tailscale/exporter_env` (the Tailscale OAuth client) has not been rotated.**
  It requires creating a new OAuth client in the Tailscale admin console, which
  cannot be done from this repository. Once a new client exists, write it into
  `secrets/proxmox-observability-1/secrets.yaml`, redeploy that host, and confirm
  `prometheus-tailscale-exporter.service` is active and the Prometheus
  `tailscale exporter` job (`proxmox-observability-1:9250`) is `up`.
- The old host keys are still on disk as `/root/ssh_host_ed25519_key.bak` on each
  of the three hosts. Delete them once you are satisfied nothing regressed.
