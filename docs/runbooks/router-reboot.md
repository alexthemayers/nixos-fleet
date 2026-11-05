# Runbook: reboot the LAN router

Reboots the router at `192.168.3.1` from `proxmox-dev` to clear NAT tables
and the DHCP cache so Tailscale goes direct again. Decision:
[2026-11-05-router-reboot](../adr/2026-11-05-router-reboot.md).

> Warnings
>
> - **This is the last rung.** The internet and the tailnet drop for about
>   two to five minutes, including your SSH path. Try the ladder below first.
> - The script refuses 01:30 to 05:30 local time (backups, nightly upgrades,
>   guest reboot slots). `ROUTER_ARGS=--force` overrides; do not, unless the
>   fleet is down anyway.
> - Never run it on a timer or from an alert. Reboot only on request.
> - Three failed logins lock the account. The script makes one attempt and
>   stops. If it reports `login rejected`, do not rerun it in a loop; check
>   `count` and `waitTime`, then fix the password (see below).
> - Do not print the password or write it to a doc, rule, or the Nix store.
> - A VM 112 reinstall changes its SSH host key. Then `sops` cannot decrypt;
>   update `.sops.yaml` and run `sops updatekeys --yes secrets/router/secrets.yaml`.

## When to use it

Direct paths are the norm (`tailscale ping` says `via <ip:port>`, not
`DERP`). The `TailscaleDERPRelaySpike` alert and `tailscale status` show
relayed peers. Go down this list and stop when the paths are direct:

1. `systemctl restart tailscaled` on the affected node.
2. Router UDP port forwards for the pinned WireGuard ports, to the LAN
   addresses: `proxmox` 41639 (`192.168.3.100`), 109 41653 (`.23`), 110 41644
   (`.26`), 111 41645 (`.31`), 112 41649 (`.32`).
3. DHCP reservations for those addresses.
4. Reboot the router (this runbook).

## Steps

1. Check the paths first (login only, no reboot):

   ```bash
   make router-status
   ```

   Expect `Login OK`, then one line per online peer with `direct` or
   `RELAY`.

2. Reboot. The script runs as a transient unit on `proxmox-dev` and the make
   target follows its log, reconnecting when the SSH path returns:

   ```bash
   make reboot-router
   # dry run: login and checks only
   make reboot-router ROUTER_ARGS=--dry-run
   ```

3. Read the output. The router answers `deviceinfo` again with a lower
   `UpTime`, then the script waits 30 seconds and runs `tailscale ping` on
   every online peer up to six times. It exits 0 when all are direct, 1 when
   some remain relayed, and prints which.

4. For relayed peers, restart `tailscaled` there, then `tailscale ping` them
   again.

The log of the last run is `/root/router-reboot/last-run.log` on
`proxmox-dev`.

## Change the password

Change it on the router first, then in sops:

```bash
sops secrets/router/secrets.yaml
```

Edit `router_password` in the editor. Then `make router-status`. The router
account is `admin`; the UI hard-codes the name.

## If the script fails

| Output | Meaning |
|---|---|
| `certificate does not match the pinned fingerprint` | Router cert changed (firmware or factory reset) or a LAN impostor. Check by hand, then update `CERT_SHA256` in `scripts/router-reboot.py`. |
| `login rejected: err=... count=...` | Wrong password or locked. Do not retry blindly. |
| `sops could not read` | `proxmox-dev` host key is not a recipient. `sops updatekeys`. |
| `router still answering after the reboot request` | Request not accepted. Reboot from the UI. |
| `did not return within 420s` | Power-cycle the router. |
