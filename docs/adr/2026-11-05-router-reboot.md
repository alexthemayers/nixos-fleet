---
status: accepted
date: 2026-11-05
---

# Reboot the LAN router on demand from proxmox-dev with a sops password

## Context and Problem Statement

The LAN router (`192.168.3.1`, Huawei WS7100-20, Afrihost firmware) holds
the NAT tables and the DHCP lease cache. After a long uptime, peers behind it
can fall back to DERP instead of a direct Tailscale path. Rebooting it clears
both, but it has only a web UI on the LAN: no SSH, and the Darwin operator
checkout cannot reach it. How does the operator, or an agent asked by the
operator, reboot it without the password living in the repo, the Nix store,
a doc, or an agent transcript beyond the one-off hand-over?

## Decision Drivers

* The password must not enter the Nix store, git in plaintext, docs, or rules
* The router is reachable from LAN guests only; `proxmox-dev` is on the LAN
* A reboot drops the internet and the tailnet for a few minutes, so it must
  not collide with the nightly backups, upgrades, and guest reboot slots
* It is the last rung after `systemctl restart tailscaled`, router port
  forwards, and DHCP reservations; nothing should reboot it automatically
* No new dependency outside the tree (`sops` comes from `nixpkgs` via `nix
  shell` on the builder)

## Considered Options

* Drive the web UI with a browser
* Run a script on `proxmox-dev` that speaks the router's own JSON API
* Leave the reboot manual (browser, or the power button)

## Decision Outcome

Chosen option: "Run a script on `proxmox-dev`", because the UI's login is a
documented SCRAM exchange over JSON that the standard library can reproduce,
and `proxmox-dev` is the one guest that is both on the LAN and already the
operator's build host.

* [`scripts/router-reboot.py`](../../scripts/router-reboot.py) logs in as
  `admin` (hard-coded by the router UI), verifies the server signatures,
  posts `/api/service/reboot.cgi`, waits for the router to return, and
  prints `tailscale ping` paths before and after. It pins the router's
  self-signed certificate by SHA-256 and makes one login attempt per run,
  because three failures lock the account.
* `make router-status` logs in and prints paths without rebooting.
  `make reboot-router` reboots; `ROUTER_ARGS=--dry-run` stops after login.
* The credentials are `secrets/router/secrets.yaml` (`router_username`,
  `router_password`), encrypted to the operator key and to the `proxmox-dev`
  SSH host key (`ssh-ed25519`, decrypted with
  `SOPS_AGE_SSH_PRIVATE_KEY_FILE=/etc/ssh/ssh_host_ed25519_key`). sops
  arrives through `nix shell nixpkgs#sops`; the plaintext lives in the
  script's memory only.
* The script refuses to reboot between 01:30 and 05:30 local time unless
  `--force`, which covers the 02:00 Postgres backup, 03:00 GitLab backup,
  03:30 upgrades, and the guest reboot slots
  ([updates.md](../runbooks/updates.md)).
* A reboot happens only when the operator asks in that turn. There is no
  timer, and no alert reacts to DERP by rebooting the router. Agent
  constraints: `.cursor/rules/router-reboot.mdc`.

### Consequences

* Good, because the operator can say "reboot the router" and the path to do
  it is one reviewed command
* Good, because the password sits only in sops, and the pinned certificate
  stops a LAN impostor from collecting the proof
* Bad, because a router firmware update can change the API and break the
  script; the fallback is the web UI
* Bad, because `proxmox-dev` is another holder of the secret, and a
  re-installed VM 112 needs `make updatekeys` for the new host key
* Bad, because the scheduled-work guard is a clock window, not a check of
  running jobs

## Validation

`make router-status` must print `Login OK` and the paths. `make reboot-router
ROUTER_ARGS=--dry-run` exercises the unit and log follower. `make fmt` and
`make lint`.

## Pros and Cons of the Options

### Drive the web UI with a browser

* Good, because it needs no protocol knowledge
* Bad, because the Darwin host cannot reach the router and the UI is not
  scriptable without brittle automation

### Run a script on proxmox-dev

* Good, because it reuses the UI's own API, and works from a LAN host
* Bad, because the API is undocumented

### Leave the reboot manual

* Good, because nothing is stored
* Bad, because the operator must be on the LAN, and agents cannot help

## More Information

Operate from [router-reboot.md](../runbooks/router-reboot.md). Secrets
pattern: [secrets.md](../secrets.md).
