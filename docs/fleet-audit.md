# NixOS Fleet Audit

Operational decisions distilled from this log live in [docs/adr/](adr/README.md).
This file remains the investigation narrative; do not treat it as the current
runbook.

**Version:** 5 (2026-08-28, evening)
**Scope:** Entire repository as it exists in the working tree; live systemd status sampled 2026-08-23 (all hosts except
`rpi4` and `gaming`); `nix eval` of the actual evaluated configuration; and a full-fleet live inspection (SSH, all
twelve hosts) at 2026-08-24 20:36 SAST covering resource saturation, service state, boot history, and journal analysis
back to 14 days. Version 4 re-checks the prioritized fix list against the tree and the running fleet (2026-08-28) and
marks what actually shipped. Version 5 adds a same-day evening pass that chased the live Alertmanager firing list down
to zero actionable alerts (see "Version 5: live incident and Alertmanager triage" after Remediation status) — it found
and fixed the actual root cause of the Loki crash-loop that v4 could only describe symptomatically, and it corrects one
of v4's own port claims that today's work made stale within hours of being written. Findings below the remediation
section are the original audit and are not rewritten except where marked "Version 5 correction".

Version 1 of this document was written from reading the tree. Version 2 re-derived the highest-severity claims from
`nix eval` against the real module system — **five findings in v1 were wrong**, including one rated Critical, and are
corrected in the changelog below. Version 3 adds a live full-fleet inspection, which caught something neither reading
the tree nor evaluating it could show: **a fleet-wide deploy happened during the audit window and reintroduced the
Vikunja outage this document had already diagnosed**, because the fix existed only in the uncommitted working tree.
Version 4 does not rewrite those findings; it records which prioritized fixes later shipped (see Remediation status).
See "Live evidence (2026-08-24, full-fleet inspection)" under Reliability for the full account, and the resource
saturation table in the same section for hard numbers behind several findings that were previously argued from
inventory alone.

---

## How to read this

Severity:

- **Critical** — can lose data, lose the fleet, or give an attacker a path that does not require much luck.
- **High** — the design does not do what it claims, or a failure of one component takes down more than it should.
- **Medium** — correctness, drift, footguns, unpaid maintenance.
- **Low** — noise, taste, small inconsistencies.

Every claim is tagged with how it was established:

- **[eval]** — verified by `nix eval` against the evaluated NixOS configuration. Highest confidence.
- **[live]** — observed on a running host via SSH on 2026-08-23.
- **[tree]** — read from source. Correct about what is written; may miss module defaults.
- **[inference]** — reasoning about upstream behavior that was not directly verified. Treat with suspicion.

v1 conflated [tree] with [eval] and got burned. Do not repeat that.

---

## Changelog: what v1 got wrong

| v1 finding                                                      | v1 severity           | Reality                                                                                                                                                                                                                                                                                        | Evidence               |
|-----------------------------------------------------------------|-----------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------|
| Alertmanager `ExecStart` points at a file nobody writes         | **Critical**          | **Wrong.** The upstream `ExecStartPre` survives the `mkForce` and runs `envsubst -i <checked-config> -o /tmp/alert-manager-substituted.yaml`. `PrivateTmp = true`, so `/tmp` is per-unit and regenerated on every start. It works. Downgraded to Medium (coupling to a nixpkgs-internal path). | [eval]                 |
| xcloud hosts may not have GRUB enabled                          | Medium                | **Wrong.** `boot.loader.grub.enable` evaluates to `true` on both. The option defaults to `!boot.isContainer`; the explicit `enable = true` on the Proxmox hosts is redundant, not load-bearing.                                                                                                | [eval]                 |
| Mimir RF=3 means one node down stops writes                     | High                  | **Wrong, and backwards.** Quorum is `floor(RF/2)+1`. RF=3 tolerates one failure (needs 2 of 3). RF=2 — which Loki uses — needs both replicas to ack. The real Mimir problem is capacity, not availability.                                                                                     | [inference, corrected] |
| Postgres `trust` + trusted tailnet = superuser from the tailnet | Critical (as phrased) | **Overstated.** The `trust` line is `127.0.0.1/32` only, which is not reachable from `tailscale0`. It is a local privilege escalation on `xcloud-postgres`, not a network one. Still serious, correctly scoped below.                                                                          | [tree]                 |
| iperf3 is exposed on the public interface of the cloud VMs      | High                  | **Wrong.** `services.iperf3.openFirewall` is `false`. Port 5201 is reachable on the tailnet only (because `tailscale0` is trusted).                                                                                                                                                            | [eval]                 |

Two v1 findings were **right for the wrong reason** and are now properly evidenced:

- Node exporter really is public on the cloud VMs — but not via `allowedTCPPorts` (which is `[22,80,443]` on
  `xcloud-caddy`). `openFirewall` under nftables emits
  `networking.firewall.extraInputRules = tcp dport 9100 accept comment "node-exporter"` with **no interface match**.
  Reading `allowedTCPPorts` alone would have told you it was closed. [eval]
- Paperless celery beat's `/var/tmp` schedule is ephemeral, but because `PrivateTmp = true`, not because `/var/tmp` is
  cleared. The consequence is beat re-deriving its schedule on restart, not "duplicate periodic jobs." [eval]

---

## Executive verdict

This repository is **not** a highly available, WAF-protected, fail-over cluster with per-host secret isolation and a CI
pipeline that checks then deploys.

It is a **single-region homelab plus two cloud VMs**, glued together with Tailscale, Nix flakes, and a lot of copied
host blocks. Almost every user-facing app depends on four hubs:

1. `xcloud-postgres` — PostgreSQL, PgBouncer, and all three Redis instances
2. `xcloud-caddy` — public HTTPS and both game UDP ports
3. `proxmox-lb` — internal HTTP load balancer, plus the S3/Loki/Mimir/Attic front door
4. `truenas-scale` — NFS for nearly all file state, and two of three Garage data directories

If any one of those dies, the "replicas" on `proxmox-applications-*`, `proxmox-observability-*`, and `rpi4` do not save
you. Several of those replicas are **scraped by Prometheus but never routed to by Caddy** — they are monitored zombies.

CI deploys to production on merge to `main` with `--skip-checks`. Lint evaluates derivation paths. There are no NixOS VM
tests, no restore drills, and no documented rollback.

None of this is theoretical. A live full-fleet inspection run during this audit (Reliability → "Live evidence,
2026-08-24") caught a fleet-wide deploy in progress that reintroduced the Vikunja outage this document had already
diagnosed, watched `xcloud-postgres` OOM-kill its own `nix-daemon` on two consecutive days under deploy load with only
1.9 GiB of RAM, found an 11-day silent backup failure, and found a 2,800-restart Loki crash-loop from a Garage 503 that
nothing paged anyone about. Every one of those is a direct, mechanical consequence of a finding already in this
document — they are not new categories of problem, they are this document's existing findings actually happening.

The craft that *is* here — sops templates, PgBouncer `auth_query`, Disko, memberlist-over-Tailscale, NFS loopback
images, and a genuinely careful Alertmanager wrapper — is real. It is undermined by inventory drift, `lib.mkForce`
coupling to module internals, oneshots that cannot fail, and documentation that was not updated when the topology
changed.

---

## What is actually good

Throwing this away would be stupid.

- **SOPS-nix coverage is complete.** Evaluating `config.sops.secrets` on all twelve hosts and diffing the attribute
  names against each `secrets/<host>/secrets.yaml` produces **zero missing keys**, including the nested
  `gitlab/active_record/{salt,primary,deterministic}` and `postgres/pgbouncer_exporter/{db_password,env_file}`. A single
  missing key is a failed activation, so this being clean by hand across 12 hosts and ~90 declarations is genuine
  discipline. [eval]
- **Secrets stay out of the store.** `sops.templates` + `EnvironmentFile`, Grafana `$__file{}`, GitLab's
  `<%= File.read(...) %>`, and blackbox's templated config file with `group = "keys"` + `SupplementaryGroups`. The one
  exception is Keycloak, below.
- **PgBouncer `auth_query` against `pg_shadow`** is a real design. Session pooling for Immich, Coder, and Vikunja is the
  correct exception. The Vikunja 2.5 `search_path` failure was a genuine pgx/PgBouncer interaction and
  `ignore_startup_parameters` is the right knob.
- **The Alertmanager wrapper is careful work.** It preserves `extraFlags`, `clusterPeers`, `logLevel`, and the storage
  path, and falls back from MagicDNS to the `tailscale0` address. It is the best of the `mkForce` wrappers. [eval]
- **nixpkgs validates the Alertmanager config at build time** (`checked-config` via `amtool`). This is a real validation
  gate the fleet gets for free. [eval]
- **Disko + `fleet.disk.path`** is a clean custom option shared by most Proxmox VMs.
- **Internal Caddy on `proxmox-lb`** is a better topology than the docs describe. Grafana cookie LB, Keycloak
  `/health/ready` on port 9000, and Garage health on 3903 are properly thought through.
- **Loki memberlist + `replication_factor = 2`** is the closest thing here to real clustering.
- **Vaultwarden `/admin` is IP-gated** to `100.64.0.0/10` at the edge. That is a real control; there should be more of
  them.
- **Caddy strips `X-Blackbox-Token` from JSON logs.** Someone thought about where the bypass token ends up.
- **Password SSH is off. Root is `prohibit-password`.**
- **`fleet.waitForHost`** is a good abstraction, misused at scale (below).

---

## Inventory: what the fleet really is

### NixOS hosts in `flake.nix` (12)

| Host                      | Role in code                                                                                  | README says                                                                                                  |
|---------------------------|-----------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------|
| `xcloud-caddy`            | Public Caddy + oauth2-proxy                                                                   | "Caddy, oauth2-proxy, **Fail2ban**" — no fail2ban anywhere in the tree                                       |
| `xcloud-postgres`         | Postgres 17, PgBouncer, 3× Redis, exporters                                                   | Accurate                                                                                                     |
| `proxmox-applications-1`  | Jellyfin, Immich, Keycloak, Vaultwarden, Vikunja, Actual, Paperless (full), Luanti, OpenArena | Accurate                                                                                                     |
| `proxmox-applications-2`  | GitLab, registry caches, Keycloak, Vikunja, Paperless **web only**                            | "stateless clustered" Paperless/Vikunja                                                                      |
| `proxmox-observability-1` | Grafana, Prometheus agent, Loki, Mimir, ntfy, Tailscale exporter, Graphite exporter           | Accurate                                                                                                     |
| `proxmox-observability-2` | Same **minus** Tailscale and Graphite exporters                                               | Docs treat obs-1/obs-2 as symmetric                                                                          |
| `proxmox-dev`             | Coder + GitLab runner (privileged Podman)                                                     | Accurate                                                                                                     |
| `proxmox-lb`              | Internal Caddy (HTTP + UDP L4)                                                                | "**Tailscale Subnet Router**" — no `--advertise-routes` anywhere                                             |
| `proxmox-db-1`            | Garage (NFS) + Attic `monolithic`                                                             | README omits Attic                                                                                           |
| `proxmox-db-2`            | Garage (different NFS dataset) + Attic `api-server`                                           | Same                                                                                                         |
| `rpi4`                    | Blackbox + Garage (USB) + Loki/Mimir/Grafana/Prometheus/ntfy/Keycloak/Vaultwarden             | "**Wireguard, Dynamic DNS, Failover Replicas (Identity, Vault, Gitlab)**" — no WireGuard, no DDNS, no GitLab |
| `gaming`                  | KDE + Steam + UT2004                                                                          | Accurate; should not be in the production deploy path                                                        |

Not NixOS, load-bearing anyway: **`truenas-scale`**, **`proxmox`** hypervisor. Also scraped: **`m3pro`** (a laptop).

### Ghost hosts still in operator tooling

| Name                      | Where it still appears                                                                  |
|---------------------------|-----------------------------------------------------------------------------------------|
| `proxmox-video`           | `Makefile` `reboot-all`, `.gitlab-ci.yml` `SSH_CONFIG`                                  |
| `proxmox-gaming`          | same                                                                                    |
| `proxmox-gitlab`          | same, **plus** `services/gitlab-runner.nix` registry mirrors `proxmox-gitlab:5000-5003` |
| `proxmox-db` (unnumbered) | Makefile, CI SSH config                                                                 |

`make reboot-all` SSHes to four dead names and **does not reboot** apps-1, apps-2, obs-2, dev, lb, db-1, or db-2. It is
worse than useless: it looks like it worked.

---

## Architecture

### The topology that actually exists

```
Internet
  → xcloud-caddy  :80/:443 + UDP 27960/30000        [SPOF - public edge]
      → proxmox-lb :80  (HTTP, Host-routed)         [SPOF - internal LB]
          → app VMs on Proxmox
      → rpi4:8222 (Vaultwarden only, 2nd upstream)
      → proxmox-lb UDP 27960/30000 → apps-1         (L4 chain is 2 hops)

App VMs
  → xcloud-postgres :5432 PgBouncer / :6379-6381 Redis   [SPOF - all state]
  → truenas-scale NFS                                     [SPOF - all files]
  → proxmox-lb :3902 Garage / :3100 Loki / :9009 Mimir / :8080 Attic / :9093 AM
```

Hub-and-spoke. The spokes multiply; the hubs do not.

### Critical: four hubs, no alternative [tree]

**1. `xcloud-postgres` is the data plane.** GitLab, Keycloak, Grafana, Vaultwarden, Immich, Paperless, Vikunja, Coder,
and Attic all use this one VM, as do all three Redis instances. `wal_level = "replica"` with no standby, no Patroni, and
no replication slot is costume jewelry. The backup is a daily `zstd` dump rsynced to a USB disk on a Pi with
`--remove-source-files`.

**2. `xcloud-caddy` is the public plane.** Every public vhost and both game UDP ports. No second edge. Internal HA
behind `proxmox-lb` is irrelevant when this VM is down.

**3. `proxmox-lb` is the east-west plane.** Public Caddy does `reverse_proxy proxmox-lb:80` for nearly every vhost. Loki
push, Mimir remote-write, Garage S3, Attic, and Alertmanager all traverse it. Alloy writes logs to
`http://proxmox-lb:3100` with **no WAL and no retry buffer** — when the LB is down, logs are simply lost.

**4. `truenas-scale` is the disk plane.** Jellyfin, Immich, Paperless, Actual, Luanti, OpenArena, GitLab state (ext4
loop image on NFS), container-registry, and **two of three Garage data directories**. `proxmox-db-1` →
`truenas-scale:/mnt/ssd/garage/data`; `proxmox-db-2` → `.../data-replica-1`. Two datasets on one NAS is one failure
domain. The only Garage copy off TrueNAS is the Pi's USB disk, mounted `nofail` with a 5s device timeout.

### High: HA is "import the module on more hosts" [tree, live]

| Service                                                                                          | Instances                            | Routed by Caddy?                                                                                    | Scraped?                    | Shared backend                                            | Verdict                                                                                 |
|--------------------------------------------------------------------------------------------------|--------------------------------------|-----------------------------------------------------------------------------------------------------|-----------------------------|-----------------------------------------------------------|-----------------------------------------------------------------------------------------|
| Keycloak                                                                                         | apps-1, apps-2, rpi4                 | apps-1 + apps-2 `round_robin`, health `/health/ready:9000`. **rpi4 absent.**                        | **all 3** incl. `rpi4:9000` | One Postgres. No `cache-stack`/Infinispan.                | Three independent Keycloaks, one DB. Sessions not replicated. Pi is a monitored zombie. |
| Grafana                                                                                          | obs-1, obs-2, rpi4                   | cookie LB obs-1/obs-2. **rpi4 absent.**                                                             | **all 3** incl. `rpi4:3000` | One Postgres                                              | Two writers/one DB works. Pi is a monitored zombie.                                     |
| ntfy                                                                                             | obs-1, obs-2, rpi4                   | `first` obs-1→obs-2. **rpi4 absent.**                                                               | **all 3** incl. `rpi4:2586` | **None.** Per-node `user.db`.                             | Failover means different users and empty history.                                       |
| Vaultwarden                                                                                      | apps-1, rpi4                         | Edge: `proxmox-lb:80` then `rpi4:8222`, `first`, `health_uri /alive`. Internal LB: **apps-1 only**. | —                           | One Postgres; Syncthing replicates `/var/lib/vaultwarden` | Only service with a real Pi route. Health check is Host-ambiguous (below).              |
| Vikunja                                                                                          | apps-1, apps-2                       | `round_robin`, **no health check**                                                                  | both                        | Postgres + Redis                                          | **[live] apps-1 `failed` on 2.5.0; apps-2 running 2.3.0.** Version skew.                |
| Paperless                                                                                        | apps-1 full; apps-2 **web only**     | `round_robin`, no `health_uri`                                                                      | —                           | NFS + Redis + Postgres                                    | **[live] apps-2 `paperless-web` inactive.** Not a cluster.                              |
| Loki                                                                                             | obs-1, obs-2, rpi4                   | LB obs-1/obs-2 `/ready`; Pi in memberlist                                                           | all 3                       | Garage S3, RF=2                                           | Closest to real clustering.                                                             |
| Mimir                                                                                            | same                                 | same                                                                                                | —                           | Garage S3, RF **defaulted to 3**                          | Availability is fine (quorum 2 of 3). Capacity is not (below).                          |
| Garage                                                                                           | db-1, db-2, rpi4                     | S3 LB **db-1/db-2 only**                                                                            | all 3 incl. `rpi4:3903`     | RF=2 over 2 NAS datasets + 1 USB                          | Numerically 3 nodes, effectively ~1 NAS + 1 stick.                                      |
| Attic                                                                                            | db-1 `monolithic`, db-2 `api-server` | `round_robin`, **no health checks**                                                                 | —                           | Shared Postgres + HTTP S3                                 | Split mode; a dead node still receives traffic.                                         |
| Prometheus                                                                                       | 3 agents                             | no vhost                                                                                            | —                           | remote_write to local Mimir                               | Agent mode: no local TSDB, no rule eval. Not HA Prometheus.                             |
| Jellyfin, Immich, GitLab, Coder, Actual, Luanti, OpenArena, oauth2-proxy, Caddy, Redis, Postgres | one each                             | —                                                                                                   | —                           | —                                                         | Honest single-instance. Stop implying otherwise.                                        |

The pattern is stark: **Prometheus knows about the Pi replicas; Caddy does not.** You are paying RAM on a 4 GB board,
and Postgres connections, for processes that can never serve a request.

> **Version 8 — stale (2026-08-29).** rpi4 no longer imports Grafana, Keycloak, ntfy, Loki, Mimir or Prometheus.
> Paperless LB is apps-1 only. Loki/Mimir `replication_factor = 1`. Health checks exist on the clustered internal
> vhosts. The Pi still runs Vaultwarden, Garage and blackbox; those rows above are the ones that remain true.

### High: Mimir capacity, not availability [tree + corrected inference]

Mimir's `ingester.ring.replication_factor` is never set, so it defaults to 3. With three ingesters, quorum is 2 — one
node down is survivable. v1 claimed the opposite; that was wrong.

The real problems:

1. **Every series is replicated to all three ingesters, including the Pi.** `MemoryMax = 2G` on a 4 GB board that also
   runs Garage, Loki, Grafana, Keycloak, Vaultwarden, ntfy, Prometheus, Syncthing, and Blackbox. RF=3 across 3 nodes
   means the weakest node holds a full copy of everything.
2. **`docs/services/mimir.md` claims RF=1.** Neither the code nor the default matches the doc.
3. `limits.ingestion_burst_size = 2147483647` and `max_global_series_per_user = 100000000` mean you will discover the
   capacity problem as an OOM, not as a limit.

> **Version 8 — fixed in tree.** `replication_factor = 1`, two obs nodes, no Pi ingester.
> `ingestion_rate = 25000`, `ingestion_burst_size = 100000`, `max_global_series_per_user = 300000`.

Loki's explicit `replication_factor = 2` needs both replicas to ack a write. dskit extends the replica set past
instances the ring marks unhealthy, so a cleanly-dead node is survivable; a **slow** node is not. Combined with
`ingester.autoforget_unhealthy = true`, a flapping Pi can be forgotten mid-write. `docs/services/loki.md` also claims
RF=1.

### High: everything authenticates against Keycloak `realms/master` [tree]

Grafana, GitLab, Vikunja, Paperless, Coder, Actual, and oauth2-proxy all point at
`https://identity.alexmayers.co.za/realms/master`. The master realm is where the admin console lives; blackbox even
probes `/admin/master/console/`. There is no application realm. One misconfigured client sits next to realm-admin.

### High: `flake.nix` is copy-paste, and it has already drifted [tree]

Twelve near-identical `nixosSystem` blocks and twelve near-identical `deploy.nodes`. No `mkHost`. Observed drift:

- `proxmox-applications-2`'s deploy profile sets `user = "root"`; no other host does.
- `config/nfs.nix` is imported only on apps-1 — and it opens **NFS server** ports on an NFS *client*, with an unused
  `libs` argument.
- `proxmox-observability-2` imports `config/observability.nix` in **both** its host file and `flake.nix`.
- Tailscale and Graphite exporters exist only on obs-1, but obs-2 is treated as a peer everywhere else.
- Module ordering of `disko/disk-config.nix` vs the host config is inconsistent between apps-1 and apps-2.
- `nixos-raspberrypi` does not `follows` nixpkgs, so the Pi tracks a second nixpkgs.

Adding a host means editing `flake.nix`, Prometheus scrape jobs (11 of them), `observability.nix` `waitForHost` +
smokeping argv, `network-testing.nix` `nodes`, both Caddy files, and the docs. Six inventories that must agree and
already do not.

---

## Implementation

### Medium (was Critical in v1): the Alertmanager wrapper is coupled to a nixpkgs internal [eval]

```
ExecStartPre = envsubst -i '/nix/store/...-checked-config' -o '/tmp/alert-manager-substituted.yaml'
ExecStart    = <forced wrapper> --config.file /tmp/alert-manager-substituted.yaml
PrivateTmp   = true
```

This works. The forced `ExecStart` only replaces `ExecStart`; the generated-and-validated config still lands in the
unit's private `/tmp` on every start.

The residual risk is real but bounded: `/tmp/alert-manager-substituted.yaml` is a nixpkgs implementation detail, not a
stable interface. If the module renames that path or moves generation into `ExecStart`, this unit silently starts with a
stale or missing config and the Mimir-ruler → Alertmanager → ntfy path dies quietly. Read the value from the module
(`cfg`) rather than hardcoding the string, or drop the `mkForce` and use `extraFlags` for the cluster address.

### High: `lib.mkForce` is the integration strategy [tree]

| Module                      | What is overridden                       | Risk                                                                                        |
|-----------------------------|------------------------------------------|---------------------------------------------------------------------------------------------|
| Loki                        | entire `ExecStart`                       | infinite `while` loop as PID 1 until `tailscale ip` answers; loses upstream flags/hardening |
| Mimir                       | entire `ExecStart`                       | same                                                                                        |
| Alertmanager                | `ExecStart`                              | nixpkgs temp-path coupling (above)                                                          |
| Attic                       | `ExecStart`                              | `monolithic` vs `api-server` selected by a hostname string compare                          |
| Paperless scheduler         | celery beat `--schedule`                 | ephemeral under `PrivateTmp`                                                                |
| Immich                      | `Restart = on-failure`                   | fights upstream's choice                                                                    |
| Vikunja                     | `database.type`, `database.host`         | fights the module's sqlite default                                                          |
| ntfy, Garage, gitlab-runner | `DynamicUser = false`                    | needed, but brittle                                                                         |
| Postgres                    | `log_destination`                        | fine until the module changes                                                               |
| gitlab-runner               | all of `/etc/containers/registries.conf` | currently points at a dead host                                                             |

The Loki and Mimir wrappers are the worst of these: they build a `/bin/sh -c '...'` string by concatenation, loop
forever waiting for a Tailscale address, and discard whatever hardening the module applied. A wedged `tailscaled`
produces a unit that hangs rather than fails, so systemd never restarts it and no alert fires.

### High: oneshots that cannot fail [tree]

- **`garage-bootstrap`** — `return 0` on key/bucket creation failure, with a log line that says "the cluster might not
  have quorum." Cluster **layout is not applied in Nix at all**; `garage layout assign/apply` is undocumented folklore.
  First boot can report success with no buckets.
- **`ntfy-custom-setup`** — `add || change-pass` masks both failures.
- **`postgresql-custom-setup`** — no `set -e`; a missing secret file silently skips that role's password;
  `RemainAfterExit = true` means it never re-runs. It also does
  `ALTER ROLE immich SET search_path TO immich, public, vectors` — `vectors` is the **pgvecto.rs** schema, while
  `shared_preload_libraries` loads **vchord**. One of those two is wrong.
- **`container-registry-gc`** — `|| true`.
- **Luanti `preStart`** — `curl -sL https://codeberg.org/mineclonia/mineclonia/archive/main.tar.gz | tar -x`, unpinned
  branch, unsigned, no checksum, re-runs whenever `game.conf` is missing. This is an unauthenticated remote code path
  into a service that runs on every boot.
- **`tailscale-udp-optimize`** — `ethtool -G ... || true`, and it sets `rx-gro-list on`. Tailscale's own guidance is
  `rx-gro-list off` alongside `rx-udp-gro-forwarding on`. This is plausibly making throughput worse while looking like
  tuning.

### High: Paperless across two hosts is a footgun [tree, live]

`hosts/proxmox-applications-2/configuration.nix` disables consumer, scheduler, task-queue, and create-dirs. Web stays
enabled. Internal Caddy round-robins both with **no `health_uri`** — only `unhealthy_status 5xx` after a user request
has already failed. [live] `paperless-web` on apps-2 was inactive, so roughly half of requests were failing into a
retry.

If anyone re-enables the workers on apps-2, two consumers race on one NFS consume directory.

> **Version 8 — fixed.** Internal Caddy proxies Paperless to apps-1 only. Workers on apps-2 stay masked.

### High: the GitLab runner is privileged where it matters [tree]

- Rootless Podman socket under `gitlab-runner` — that part is fine.
- `registrationFlags = [ "--docker-privileged" "--docker-network-mode" "host" ]` — a CI job is effectively root on
  `proxmox-dev` with host networking.
- `restartIfChanged = false` — deploys do not bounce it, so config changes land whenever it happens to restart.
- Registry mirrors point at `proxmox-gitlab:5000-5003`, **a host that does not exist**. Every mirrored pull silently
  falls through to the internet, and the pull-through caches on apps-2 are dead weight.

This matters more than it looks, because of the shared age key (below).

> **Version 8 — fixed.** No `--docker-privileged`, no host networking. Registry mirrors point at
> `proxmox-applications-2`. `restartIfChanged = false` remains so a deploy does not kill an in-flight job;
> `restartUnits` covers token rotation.

### High: GitLab identity settings auto-provision users [tree]

```
signup_enabled = true;
require_admin_approval_after_user_signup = true;
omniauth.block_auto_created_users = false;
omniauth.auto_sign_in_with_provider = "openid_connect";
omniauth.allow_single_sign_on = [ "openid_connect" ];
```

The admin-approval flag governs local signups. `block_auto_created_users = false` means anyone who can obtain a token
from the **master realm** gets an unblocked GitLab account created automatically. The blast radius of the Keycloak
issues below therefore includes your source control.

`client_auth_method = "query"` additionally puts the OIDC client secret in query strings, where it lands in access logs
and `Referer` headers.

> **Version 7 — fixed (2026-08-29).** `signup_enabled = false` and `block_auto_created_users = true`.
> `client_auth_method = "basic"`. Local password sign-up is off; an OIDC login still creates a blocked account until
> an admin approves it. Keycloak `realms/master` is unchanged (topology freeze).

### Medium (softened from v1): the GitLab nginx cache [tree]

`proxy_cache gitlab` on `location /` with the default key (`$scheme$proxy_host$request_uri`) and **no**
`proxy_cache_bypass`/`proxy_no_cache` on `Cookie` or `Authorization`.

v1 called this a straightforward authenticated-content leak. That was too strong: nginx does not cache responses
carrying `Set-Cookie`, and it honors `Cache-Control: private/no-store/no-cache` from upstream, which GitLab sets on
authenticated pages. So it is probably not leaking today.

It is still wrong: there is no defense in depth, and correctness depends entirely on GitLab tagging every authenticated
route correctly, forever. Add the explicit bypass.

### Medium: the GitLab backup shadows pg_dump by bind mount [tree]

```nix
BindReadOnlyPaths = [ "${pkgs.postgresql_17}/bin:${pkgs.postgresql_16}/bin" ];
```

This mounts the v17 binaries over the v16 path so `pg_dump` matches the server. It works until nixpkgs moves the GitLab
module to a different PostgreSQL version, at which point the source path vanishes and the **backup unit fails to
start**. A backup that breaks on a routine dependency bump, in a repo with no restore test, is a data-loss mechanism
with a delay fuse.

### Medium: Prometheus scrape lists are handmade and already inconsistent [tree]

- The `systemd exporter` job omits **`proxmox-observability-2:9558`**; the `node exporter` job includes it.
- `tailscale exporter` scrapes only obs-1 (correct — it only runs there, but nothing says so).
- Graphite/TrueNAS scrapes only `proxmox-observability-1:9108`, while the firewall opens **9109**.
- `blackbox_http` relabels every target to `rpi4:9115`. **The Pi is a single point of failure for all synthetic
  probing.**
- Ghost/foreign targets: `proxmox:9558`, `proxmox:9100`, `m3pro:9100`, `proxmox:12345`.

### Medium: `config/build-cache.nix` can shrink a live filesystem [tree]

```sh
truncate -s ${att.imageSize} "$IMG"      # runs on the EXISTING-image path too
e2fsck -fp "$IMG" || true
resize2fs "$IMG" || true
```

Lower `imageSize` in Nix and the next boot truncates the image **before** `resize2fs` shrinks the filesystem — that is
ext4 corruption, and the `|| true` hides it. The loop mount is `nofail`, so GitLab and the registry then start against
an empty local directory. Nothing prevents two hosts from attaching the same image.

Note the asymmetry: `/var/gitlab/state` (the loop mount) has **no** `nofail`, while `/var/lib/gitlab/shared/registry`
(the bind) does. One fails safe, one fails silently, and the difference looks accidental.

### Medium: `config/basics.nix` grows `~/.zshrc` forever [tree]

```nix
system.userActivationScripts.zshrc = ''
  echo 'POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true' >>! ~/.zshrc
'';
```

Appends on **every activation**, on every host, for every user. Also ships oh-my-zsh `docker kubectl nmap ruby rust`
plugins to all twelve machines including the Pi.

### Low: Jellyfin rewrites its own logging config every start [tree]

`preStart` heredocs `logging.json` on each start, silently reverting anything changed in the UI or on disk. Defensible,
undocumented.

### Low: UT2004 [tree]

A fixed-output derivation that pipes `yes y | bash` into the OldUnreal installer with `set +o pipefail`, downloading
commercial game data at build time. The installer script's hash is pinned and the FOD output hash is pinned, so it is
more reproducible than it looks. `meta.platforms` claims `aarch64-linux`, which is false for an x86 binary under
`steam-run`.

---

## Robustness

### High: `wait-for-host` runs on every host, for every other host [tree]

`config/observability.nix` declares `fleet.waitForHost` entries for `1.1.1.1`, all eleven fleet hostnames, and
`proxmox`. `config/wait-for-host.nix` sets `wantedBy = [ "multi-user.target" ]`, `maxRetries = 600`,
`TimeoutStartSec = "15m"`.

So **every** machine — including `gaming` and both cloud VMs — starts a dozen ping loops at boot. Smokeping only `wants`
them, so failures do not block the boot, they just stretch it. Blocked ICMP to `1.1.1.1` is fifteen minutes of boot-time
drag across twelve machines.

Jellyfin and Actual Budget then duplicate the mechanism with their own bespoke 120-second loops.
`docs/todo-deviations.md` has known about this for a while and both boxes are still unchecked.

> **Version 8 — fixed (2026-08-29).** Smokeping wait units are tombstoned. Jellyfin and Actual Budget now use
> `fleet.waitForHost`. `docs/todo-deviations.md` matches.

### High: the USB backup mount fails open [tree]

`hosts/rpi4/usb-backup-mount.nix` uses `nofail` with `x-systemd.device-timeout=5s`. If the disk is absent or slow, the
mount is skipped and `/mnt/usb-backup` stays an empty directory on the SD card — which `systemd.tmpfiles` then helpfully
populates with `postgres_backups/`, `gitlab_backups/`, and `garage/data/`.

Postgres dumps and GitLab archives then rsync **into the SD card**. When the USB disk later mounts, it covers those
files. You get a clean-looking backup job, a green systemd unit, and nothing on the disk you think you are backing up
to. Garage's Pi replica lives at that same path.

> **Version 8 — fixed in tree.** The mount is fail-closed (no `nofail`). Not live-checked: `rpi4` still unreachable.

### High: `rsync --remove-source-files` on both backup paths [tree]

`postgresqlBackup.postStart` and `gitlab-backup-sync` both delete the local artifact as a side effect of transfer. A
full destination, a half-transfer, or an SSH blip leaves the local copy gone and the remote incomplete. Both use
`StrictHostKeyChecking=accept-new`.

The Pi is also the rsync destination — so the failure mode in the previous finding and this one compound.

> **Version 8 — fixed.** Copy, checksum-verify, then delete. `StrictHostKeyChecking=yes`. Restore procedure is in
> `docs/runbooks/restore-postgres.md` and `docs/runbooks/restore-gitlab.md`.

### Medium: NFS mount options are inconsistent [tree]

- Jellyfin mounts media with `async` — writes can be lost on a crash.
- Actual Budget's mount lacks `noauto` while using `x-systemd.automount`.
- Luanti, OpenArena, Immich, Paperless, and Garage use the `noauto` + automount + `wait-for-host` pattern correctly.

### Medium: the Pi is over-committed [tree]

Garage + Mimir (2 G cap) + Loki (2 G cap) + Grafana + Prometheus + ntfy + Keycloak + Vaultwarden + Syncthing + Blackbox,
on 4 GB. Most of those have no route. The OOM killer will pick something, and because Mimir RF=3 includes the Pi, it may
pick an ingester holding a replica of every series.

---

## Security

### Critical: Keycloak ships with `initialAdminPassword = "admin"` [tree]

`services/keycloak.nix`, in the world-readable Nix store, on apps-1, apps-2, **and** rpi4. The identity vhost is public,
has **no** oauth2-proxy, and its WAF is detection-only with a 500/min rate limit. Blackbox probes
`/admin/master/console/`, which confirms the admin console is reachable from the edge.

`docs/todo-deviations.md` has this filed as an unchecked TODO. It is the single highest-value finding in this document.
Everything in the fleet authenticates against this realm, and GitLab auto-creates unblocked accounts from it.

> **Version 6 — fixed (2026-08-28).** `initialAdminPassword` is gone. Keycloak reads `KC_BOOTSTRAP_ADMIN_*` from a
> sops template (`services/keycloak.nix`). The identity vhost aborts `/admin*` unless the client is in
> `100.64.0.0/10`. Applications still use `realms/master` (topology freeze). GitLab now has
> `block_auto_created_users = true`; local signup is flipped off in a later pass.

### Critical: `trustedInterfaces = [ "tailscale0" ]` makes per-service firewall rules decorative [eval]

Set in **both** `config/security.nix` and `services/tailscale.nix` (the evaluated value is
`["tailscale0","tailscale0","lo"]` — the duplicate confirms the double definition). Every
`networking.firewall.interfaces."tailscale0".allowedTCPPorts` in the tree is a comment with extra steps.

Reachable from any device on the tailnet, with no further authentication:

| Port           | Service                                          | Auth                                                              |
|----------------|--------------------------------------------------|-------------------------------------------------------------------|
| 6379/6380/6381 | Redis ×3                                         | password (sops `requirePassFile`, no TLS) — see Version 5 note   |
| 5433           | PostgreSQL                                       | scram                                                             |
| 3903           | Garage admin API                                 | token                                                             |
| 2019           | Caddy **metrics** (`xcloud-caddy` and `proxmox-lb`) | **none** — see Version 5 correction below                     |
| 3100 / 9009    | Loki / Mimir                                     | **none** (`auth_enabled = false`, `multitenancy_enabled = false`) |
| 8384           | Syncthing GUI                                    | **none** (docs claim it is bound to tailscale0; it is `0.0.0.0`)  |
| 44180          | oauth2-proxy metrics                             | none                                                              |
| 9251           | `tailscale web --readonly`                       | none                                                              |
| 5201           | iperf3                                           | none                                                              |
| 12345          | Alloy                                            | none                                                              |
| 8080           | Attic                                            | token                                                             |
| `/-/metrics`   | GitLab (`ip_whitelist` includes `100.64.0.0/10`) | none                                                              |

> **Version 6 — fixed (2026-08-28 / 2026-08-29).** `trustedInterfaces = [ "tailscale0" ]` has been removed from
> both `config/security.nix` and `services/tailscale.nix`. `inet nixos-fw` on every deployed host now has a
> port-matched `iifname "tailscale0" tcp dport { ... } accept` and **no** blanket accept in that table. Canary was
> `proxmox-dev`: an unlisted listening port (5355) times out from the tailnet; the listed scrape ports still return
> 200. The remaining hosts were rolled out the same way (excluding `rpi4`, still unreachable, and `gaming`).
>
> Ports that *were* open only because of the blanket trust and are now **closed** on purpose:
>
> - raw Postgres `5433` (clients go through PgBouncer on `5432`)
> - Syncthing GUI `8384` (bound to loopback; the sync protocol on `22000` is allowed on the Vaultwarden hosts)
>
> Ports that remain reachable from the tailnet, now because they have an explicit rule: Redis 6379/6380/6381
> (passworded), Garage 3903 (token), Caddy metrics 2019 (none), Loki/Mimir (none), oauth2-proxy metrics 44180,
> `tailscale web` 9251, iperf3 5201, Alloy 12345, Attic 8080, plus the rest of the scrape and reverse-proxy
> listeners that caddy-internal and Prometheus actually use (Keycloak 7777/9000/JGroups, Vikunja, ntfy, Jellyfin,
> Immich, Grafana, GitLab 8080/5005, Coder 7080/2112, paperless, Actual, container-registry caches, exporters).
>
> **Caveats, do not skip:**
>
> 1. Tailscale still inserts `table ip filter` / `ts-input` with `iifname "tailscale0" accept`. That verdict is
>    *not* final: nftables `accept` only ends the current chain, and `inet nixos-fw` has `policy drop`, so the
>    NixOS port list is what actually filters. Confirmed live on the canary.
> 2. `rpi4` was unreachable and still has `trustedInterfaces` until B2/B3 are replayed against it. Blackbox
>    (`:9115`) already has an explicit rule waiting in `services/blackbox-exporter.nix`.
> 3. SSH `22` is still `openFirewall = true` on every interface, including the public NIC of the cloud VMs. That
>    is independent of this finding.

The security model is still "Tailscale is the perimeter," but it is no longer "every port on every host." A reusable
auth key is still membership of the tailnet; it is no longer an implicit allow-all on `tailscale0`.

> **Version 5 correction (kept for history):** Caddy's admin API was bound to `127.0.0.1:2019` on `xcloud-caddy`
> before the v4 write-up claimed otherwise. As of 2026-08-28 the admin API on both Caddy instances is
> `admin 127.0.0.1:2020`, and `:2019` is a dedicated metrics vhost. Redis `requirepass` shipped since v4.

### Critical: Redis has no authentication [tree]

`services/redis.nix`: `bind = "0.0.0.0 ::"`, `"protected-mode" = "no"`, no `requirepass`, no TLS, on `xcloud-postgres`.
Instance 6379 holds **oauth2-proxy sessions**. Anyone on the tailnet can read or forge SSO sessions for every service
behind `forward_auth`.

`docs/services/oauth2-proxy.md` still claims `redis://127.0.0.1:6379` on `xcloud-caddy`. The code says
`redis://xcloud-postgres:6379`.

> **Version 6 — fixed (2026-08-28).** All three Redis instances have `requirePassFile` and `protected-mode = yes`.
> Live `PING` without a password returns `NOAUTH Authentication required.` Bind is still `0.0.0.0` with no TLS;
> authentication, not the listen address, is the access control. The oauth2-proxy docs claim about `127.0.0.1`
> was also rewritten.

### Critical: one age key covers three hosts, and the blast radius is concrete [tree]

`.sops.yaml`:

```
proxmox_dev = proxmox_db_1 = proxmox_db_2 = age167zzzgyhnmxapu0z9w3qgqww4krm0ztmg20vejldkz6lf54fzssseunmdt
```

`docs/secrets.md` explicitly promises the opposite: "if a host key is compromised, only that specific host's secrets can
be decrypted."

Now combine it with the secrets inventory. `secrets/proxmox-db-1/secrets.yaml` and `secrets/proxmox-db-2/secrets.yaml`
contain `garage/rpc_secret`, `garage/admin_token`, `attic/env`, `attic/s3_*`, `loki/s3_*`, and `mimir/s3_*`.

`proxmox-dev` runs the GitLab runner with `--docker-privileged --docker-network-mode host`. **Any CI job that can read
the repo checkout and the host's age key can decrypt the Garage RPC secret and every object-storage credential in the
fleet.** That is one untrusted merge request away.

There is also a dangling null recipient under `proxmox-applications-2`:

```yaml
      - age:
          - *alex
          - *proxmox_applications_2
          -
```

> **Version 6 — fixed (2026-08-28).** This finding is closed. The three hosts were given fresh
> `ssh_host_ed25519_key`s (the old key's comment was `root@proxmox-db` on all three, confirming the clone
> lineage), `.sops.yaml` now carries three distinct age recipients, and `make updatekeys` re-wrapped the three
> affected secret files. Verified per-host isolation: each of `secrets/proxmox-{dev,db-1,db-2}/secrets.yaml` now
> lists exactly one host recipient, so none of the three can decrypt another's secrets. `ssh/fleet_known_hosts`
> was regenerated and every pinned entry diffed against the live key before deploy.
>
> Rotated afterwards, since the CI runner on `proxmox-dev` could previously read all of it: `garage/rpc_secret`
> and `garage/admin_token` (both db nodes restarted in parallel so the cluster never sat on mismatched secrets),
> and all four Garage S3 key pairs (`loki`, `mimir`, `web-assets`, `attic`) via delete + `garage-bootstrap`
> recreate, with consumers redeployed. Cluster, Loki, Mimir and Attic all verified healthy afterwards.
>
> **Still open:** `tailscale/exporter_env` (the Tailscale OAuth client) has *not* been rotated — it needs a new
> OAuth client created in the Tailscale admin console, which is a manual step outside this repo. Until then,
> treat the tailnet API credential as exposed to anything that had root on those three hosts. See
> `docs/runbooks/split-shared-host-keys.md`.
>
> The dangling null recipient under `proxmox-applications-2` noted above is also gone, as are the
> over-provisioned `loki/s3_*` and `mimir/s3_*` entries on the db nodes and the `attic/s3_*` duplicates — the
> db nodes now carry only `attic/env`, and `tailscale/exporter_env` is no longer present on non-owner hosts.

> **Version 6 — new finding, found while rotating the above:** *a rotated secret does not reach its service.*
> Every secret in this tree is delivered as a **file path** (`environmentFile`, `requirePassFile`, or a path
> interpolated into a config file). The systemd unit definition is therefore byte-identical before and after a
> rotation, so `switch-to-configuration switch` restarts nothing and the service keeps using the value it read
> at startup. This was not theoretical: after deploying the new S3 credentials, Loki and Mimir on both
> observability hosts continued to throw `403 AccessDenied ... No such key: GK14e6802b...` — the *old* key ID —
> while the correct new key sat in `/run/secrets/rendered/loki.env`. They only recovered after a manual
> `systemctl restart`.
>
> `sops-nix` solves this with `restartUnits`/`reloadUnits`, which restarts a unit only when the secret's on-disk
> content actually changes. Before this session it was used **nowhere** in the tree; `services/ntfy.nix` was the
> only file handling it at all, via a hand-rolled `restartTriggers` on the template content. It is now set for
> Garage, Loki, Mimir, Attic and the Tailscale exporter (Attic picked up its rotated credentials automatically
> as a result), and has been extended to the remaining secret-consuming services. Anyone rotating a secret
> should still verify the consuming process actually restarted rather than trusting a clean deploy.

### High: secrets are over-provisioned [eval, new in v2]

Coverage is complete. Scoping is not. Diffing declared `sops.secrets` against the stored files shows every host carries
credentials it never reads:

| Secret                                                      | Present in                         | Declared by                            |
|-------------------------------------------------------------|------------------------------------|----------------------------------------|
| `tailscale/exporter_env`                                    | **all 12 hosts**                   | obs-1 only                             |
| `coder/client_secret`, `postgres/coder_password`            | proxmox-dev, **proxmox-lb**        | proxmox-dev only                       |
| `loki/s3_*`, `mimir/s3_*`                                   | obs-1, obs-2, rpi4, **db-1, db-2** | the three observability nodes          |
| `attic/s3_access_key`, `attic/s3_secret_key`                | db-1, db-2                         | nobody — the service reads `attic/env` |
| `postgres/immich_password`, `postgres/vaultwarden_password` | apps-1                             | xcloud-postgres only                   |
| `postgres/vaultwarden_password`                             | rpi4                               | xcloud-postgres only                   |

Two of these are more than untidiness:

1. **`proxmox-lb` declares exactly one secret — `tailscale/auth_key` — and stores three.** It runs only Caddy and
   Tailscale, and holds Coder's OIDC client secret and database password for no reason.
2. **`proxmox-db-1` and `proxmox-db-2` declare four secrets each and store ten.** The six extras are the Loki, Mimir,
   and Attic S3 credentials. Since those two files are encrypted to the age key that `proxmox-dev` also holds, the
   privileged GitLab runner can decrypt the object-storage credentials for the entire observability stack — even though
   neither `proxmox-dev` nor the db nodes have any reason to read them.

The Tailscale API credential, which can enumerate the tailnet, is decryptable by **every host key in the fleet**,
including `gaming` — a desktop workstation with Steam on it.

> **Version 7 — fixed (2026-08-29).** Re-diffed with `scripts/check-secrets.sh`. Real leftover credentials from the
> table above were already gone (exporter_env only on obs-1; Coder only on proxmox-dev; no Attic S3 keys; no
> application DB passwords on apps-1/rpi4). What remained was empty YAML stubs (`loki: {}`, `mimir: {}` on the db
> files; `coder: {}` / `postgres: {}` on lb; grafana/ntfy/loki/mimir/postgres stubs on rpi4). Those stubs are deleted.
> `tailscale/exporter_env` is still not rotated (needs the Tailscale admin console). The shared-age-key blast radius
> that made the db-node extras dangerous was closed in Version 6.

### High: the WAF never blocks [tree]

`SecRuleEngine DetectionOnly` in every `coraza_waf` block in `services/caddy.nix`. `docs/standards.md` and
`docs/how-to-reverse-proxy.md` both sell Coraza + OWASP CRS as protection. It logs and forwards.

Jellyfin and Immich additionally route `/videos/*`, `/Items/*`, `/Audio/*`, `/hls/*`, `/stream/*`, `/api/assets/*`,
`/api/media/*`, `/socket*`, and all WebSocket upgrades through `handle` blocks that **omit the WAF entirely** — so even
flipping to blocking mode would leave those paths uncovered.

The CSP is `default-src 'self' https: wss: data: blob: 'unsafe-inline' 'unsafe-eval'`, which permits essentially
everything. HSTS is set to `preload` on a homelab.

### High: oauth2-proxy coverage is a patchwork [tree]

Protected: `grafana` (hybrid), `budget`, `paperless`, `proxmox`, `truenas`.

Unprotected at the edge: `jellyfin`, `immich`, `gitlab`, `registry`, `coder`, **`identity`**, `vaultwarden`, `tasks`,
`ntfy`, `auth`.

Additional issues:

- `email-domain = "*"` — any successfully authenticated identity is accepted.
- Grafana and Paperless run oauth2-proxy **and** native OIDC, so users authenticate twice.
- `X-Blackbox-Token` bypasses `forward_auth` on every protected vhost. The token is a shared static secret distributed
  to `xcloud-caddy` and `rpi4`.
- `skip-jwt-bearer-tokens = true` with `extra-jwt-issuers = "...=grafana"`.
- One instance, on the public edge SPOF, with sessions in the unauthenticated Redis.

### High: node exporter is genuinely public on the cloud VMs [eval]

`config/observability.nix` sets `openFirewall = true` for the node exporter and is imported by **every** host. Under
nftables this becomes:

```
networking.firewall.extraInputRules = tcp dport 9100 accept comment "node-exporter"
```

with no interface match. `xcloud-caddy`'s `allowedTCPPorts` is `[22,80,443]`, so a casual reading says port 9100 is
closed. It is not. Both internet-facing VMs expose full host metrics — kernel version, filesystem layout, network
topology, process counts — to anyone who scans them.

iperf3 is **not** exposed publicly (`openFirewall = false`), correcting v1.

> **Version 8 — fixed.** `openFirewall = false`; 9100 is allowed on `tailscale0` only.

### High: Jellyfin, OpenArena, and Luanti open ports on all interfaces [eval]

`proxmox-applications-1` evaluates to:

- TCP `[22, 8096, 8920]` — Jellyfin HTTP and HTTPS
- UDP `[1900, 7359, 27960, 30000, 41643]` — DLNA/SSDP discovery, client discovery, OpenArena, Luanti

None of these are restricted to `tailscale0`. On a flat home LAN, every device can reach Jellyfin directly, bypassing
Caddy, the WAF, and the rate limits. The public edge additionally opens UDP 27960 and 30000 to the internet for two game
servers.

> **Version 8 — partial.** Jellyfin/OpenArena/Luanti on the app host are `tailscale0` only. Public UDP `27960` and
> `30000` on `xcloud-caddy` is the intended edge forward.

### High: Postgres `trust` is a local privilege escalation [tree, scope corrected]

```
host    postgres    postgres    127.0.0.1/32    trust
host    postgres    postgres    ::1/128         trust
```

Required for PgBouncer's `auth_query`. It is **not** reachable from the tailnet (v1 said otherwise). But any local
process or user on `xcloud-postgres` — including anything that can be coerced into making a loopback connection —
becomes the `postgres` superuser without a password, and from there can read `pg_shadow` for every application role.

PgBouncer listens on `*` with a `"*"` catch-all database entry, so it is a general-purpose proxy to 5433 for the whole
tailnet.

### High: SSH and deploy posture [tree]

- All twelve `deploy.nodes` use `sshOpts = [ "-A" "-o" "StrictHostKeyChecking=no" ]`. Agent forwarding **as root**, no
  host-key verification. `.gitlab-ci.yml` even carries a TODO to pin `known_hosts`, which the flake then overrides.
- `root`'s `authorized_keys` contains the admin key **and** the GitLab CI deploy key on every host.
- `xcloud-caddy` and `xcloud-postgres` set `security.sudo.wheelNeedsPassword = false`.

> **Version 7 — partial (2026-08-29).** Passwordless sudo is gone from both cloud VMs (`alex` is a locked account with
> no password, so `sudo` now prompts and cannot succeed; root SSH is key-only). Host keys are pinned in
> `ssh/fleet_known_hosts`; `sshOpts` no longer forwards the agent. The GitLab CI deploy key on every root account is
> unchanged. **Version 8:** SSH 22 on the two cloud VMs is allowed on `tailscale0` only (`openFirewall = false`).
> Provider console is the out-of-band path. The CI deploy key stays.

### High: the Nix substituter is plain HTTP [tree]

`http://proxmox-lb:8080/attic` in `config/system.nix` and in the CI `NIX_CONFIG`. The public key is pinned, so store
paths are signature-checked — but the fetch is unauthenticated and unencrypted, and CI adds the same substituter while
running as root on a fresh installer.

Broader pattern: internal Caddy is HTTP-only, Grafana `protocol = "http"`, Keycloak `http-enabled = true` with
`useSSL = false` to Postgres, Loki/Mimir/Attic → Garage with `insecure = true`, Coder with `sslmode=disable`, Proxmox
with `tls_insecure_skip_verify`, TrueNAS over `http://`. Caddy's `trusted_proxies` covers `100.64.0.0/10`,
`192.168.0.0/16`, `10.0.0.0/8`, and `172.16.0.0/12`, so any of those hops can spoof `X-Forwarded-For`.

> **Version 8 — partial, then reverted in Version 9.** A public `https://attic.alexmayers.co.za` vhost was added and
> then removed. Substituters on deployed hosts are tailnet-only `http://proxmox-lb:8080/attic`. East-west HTTP for
> Grafana/Garage/Coder is unchanged. The fetch is still unauthenticated HTTP on the tailnet; signatures are the access
> control.

### Medium: Vaultwarden replication is subtle and under-specified [tree]

Syncthing replicates `/var/lib/vaultwarden` between apps-1 and rpi4. With the Postgres backend, that directory holds
attachments, sends, and — importantly — `rsa_key.pem`, the JWT signing key. Replicating it is **necessary** for the Pi
to be a usable failover, so this is not the blunder v1 implied.

The problems that remain:

1. Both instances run continuously against the same Postgres. `lb_policy first` keeps traffic on one, but nothing stops
   both from writing attachments if the health check flaps.
2. A Syncthing conflict on `rsa_key.pem` invalidates every session.
3. The edge health check is `health_uri /alive` against upstream `proxmox-lb:80`. Internal Caddy routes by `Host`, and
   there is no `http://proxmox-lb` vhost serving `/alive`. Whether the primary is ever considered healthy depends on
   Caddy's default `Host` handling for health probes — which is exactly the sort of thing that should not be left to
   inference on a password vault. **Test this deliberately.**

### Medium: audit rules that will not be read [tree]

`config/security.nix` enables auditd with `chmod`/`chown`/`setuid` syscall auditing on hosts running GitLab and Immich.
That is a high-volume firehose into the journal, then into Loki, then into Garage on TrueNAS. There is no dashboard or
alert consuming it. The watch on `/etc/nixos` is dead weight on an immutable system.

### Low: privacy and PII [tree]

ACME email, Grafana admin email, GitLab `email_from`, OpenArena server name, and Luanti `name = "alex"` are all in the
flake. `gravatar.enabled = true` sends user email hashes to a third party. Syncthing device IDs are hardcoded.

`secrets/proxmox-dev/secrets-fixed.yaml.bak` and `secrets/proxmox-lb/secrets-fixed.yaml.bak` are committed encrypted
leftovers that will not follow key rotation.

---

## Documentation

Volume is not accuracy. The docs are extensive and, in the load-bearing places, wrong.

### Critical: the documentation describes a different system

| Document                            | Claim                                                                  | Reality                                                             |
|-------------------------------------|------------------------------------------------------------------------|---------------------------------------------------------------------|
| README                              | rpi4: WireGuard, DDNS, GitLab failover                                 | None exist                                                          |
| README                              | xcloud-caddy: Fail2ban                                                 | Not in the tree                                                     |
| README                              | proxmox-lb: Tailscale subnet router                                    | Internal Caddy; no `--advertise-routes`                             |
| README                              | db nodes: Garage                                                       | Also Attic, omitted from the service index                          |
| `docs/services/caddy.md`            | direct backends; rpi4 upstreams for grafana/prometheus/alertmanager/s3 | Everything goes to `proxmox-lb:80`; **those vhosts do not exist**   |
| `docs/services/grafana.md`          | `localhost:9009`, `lb_policy first`, rpi4 failover                     | `http://proxmox-lb:9009/prometheus`; cookie LB; no rpi4             |
| `docs/services/keycloak.md`         | `lb_policy first`                                                      | `round_robin`; no rpi4                                              |
| `docs/services/garage.md`           | rpi4 at `/var/lib/garage/data`; db-1 and db-2 on the **same** share    | rpi4 at `/mnt/usb-backup/garage/data`; db-2 on `data-replica-1`     |
| `docs/services/loki.md`, `mimir.md` | S3 at `proxmox-db:3902`; RF=1                                          | `proxmox-lb:3902`; both set `replication_factor = 1`                |
| `docs/services/oauth2-proxy.md`     | Redis at `127.0.0.1:6379` on xcloud-caddy                              | `xcloud-postgres:6379`                                              |
| `docs/services/tailscale.md`        | MSS `set 1232`                                                         | `tcp option maxseg size set rt mtu`                                 |
| `docs/how-to-postgres-setup.md`     | sample uses `psql -p 5432`                                             | Postgres is on **5433**; 5432 is PgBouncer                          |
| `docs/how-to-dynamic-tailscale.md`  | `ip addr show` + `writeShellScript`                                    | `tailscale ip -4` inside `/bin/sh -c` strings                       |
| `docs/custom-options.md`            | `hosts/proxmox-dev/buildcache.nix`                                     | File does not exist                                                 |
| `docs/services/gitlab-runner.md`    | 150 G loopback on proxmox-dev                                          | No build-cache attachment on that host                              |
| `docs/deployments.md`               | lint runs `nix flake check`; rpi4 builds on CI                         | Lint evals `drvPath`; small/cloud/Pi nodes now `remoteBuild = false` |
| `docs/standards.md`                 | session pooling for Immich and Coder                                   | Also Vikunja                                                        |
| `docs/storage-disko.md`             | `git clone .../your-org/...`, `--write-to-disk`                        | Placeholder org, stale invocation                                   |
| Rate limits                         | 200/min                                                                | 500 / 1000 / 2000 per minute                                        |

The `psql -p 5432` example is the most operationally dangerous: someone follows the runbook, connects to PgBouncer, and
debugs the wrong daemon during an incident.

`file://` absolute paths appear throughout `docs/monitoring.md`, `docs/storage-disko.md`, `docs/custom-options.md`, and
`docs/hosts/*.md`. They resolve on exactly one laptop.

### High: undocumented services

Attic, Redis, OpenArena, and caddy-internal have code and no documentation. Attic is a binary cache that CI and every
host trusts.

> **Version 6 — partial.** `docs/services/attic.md` and `docs/services/caddy-internal.md` now exist. Redis/OpenArena
> docs were not added in this pass.

> **Version 8 — fixed.** `docs/services/redis.md` and `docs/services/openarena.md` added.

### High: `docs/todo-deviations.md` is a fig leaf

Two items: the wait-for-host duplication and the Keycloak password. Both unchecked. It does not mention `--skip-checks`,
shared age keys, ghost hosts, HTTP Attic, unauthenticated Redis, detection-only WAF, the four SPOFs, or the unrouted Pi
replicas.

> **Version 8 — rewritten.** Keycloak admin password and the two wait-for-host loops are closed.
> `docs/todo-deviations.md` no longer pretends those are open. Topology freeze items stay in this audit.

### High: `make edit-secrets` targets a file that does not exist

```make
edit-secrets:
	sops secrets/secrets.yaml
	sops updatekeys secrets/secrets.yaml
```

The layout is `secrets/<hostname>/secrets.yaml`. This target is left over from a previous scheme and will fail or create
a stray file that matches no `creation_rules` entry.

> **Version 7 — fixed.** `make edit-secrets HOST=<hostname>` edits `secrets/<hostname>/secrets.yaml` and refuses to
> run without `HOST` or if the file is missing.

---

## Extensibility

### High: there are no per-service enable flags

Only `fleet.services.garage` and `fleet.services.redis` are real options. Everything else is "import the whole module."
The consequences are visible in the tree:

- Disabling Paperless workers on apps-2 required `systemd.services.paperless-*.enable = false` — masking units rather
  than configuring the service. [live] confirmed the units show as `masked`.
- The Pi imports Grafana, Keycloak, ntfy, and Prometheus in full because there is no way to import "just the failover
  parts."

A host should be inventory plus a list of enabled services. Today a host is a bespoke `modules = [ ... ]` list.

### High: six parallel inventories

`flake.nix`, Prometheus `scrapeConfigs` (11 jobs), `observability.nix` (`waitForHost` + smokeping argv),
`network-testing.nix` `nodes`, the two Caddy files, and the docs. They have already diverged — obs-2 is missing from the
systemd exporter job, and four dead hostnames survive in the Makefile and CI.

> **Version 8 — partial.** `config/fleet-inventory.nix` plus `check-inventory`. Scrape lists are still handmade.

### Medium: the gaming workstation is in the production path

`make lint`, `make build`, and `make deploy` all include `gaming`. An eval error in `hosts/gaming/gaming.nix`, or a
UT2004 FOD hash change, blocks fleet-wide lint. `NIXPKGS_ALLOW_UNFREE = "1"` is set globally in CI because of it. CI's
`deploy-gaming` is manual; the local `make deploy` is not.

### Medium: pins are scattered and partly floating

Caddy plugins (including `caddy-ratelimit` at a floating commit-date pseudo-version), Coder 2.33.8 as a tarball,
Luanti's Mineclonia from `main` with no hash, Xanmod kernels, `nixpkgs-unstable` with no channel policy, and
`nixos-raspberrypi` on its own nixpkgs.

---

## Resilience

### Critical: rpi4 is not a failover node

What actually routes to the Pi:

- **Vaultwarden** — a real second upstream, with a health check that needs verification.
- **Loki / Mimir memberlist** — it participates, but its storage is the same Garage that is mostly on TrueNAS.
- **Garage storage** — on `nofail` USB, and **not** in the S3 load balancer.
- **Blackbox** — the *only* blackbox exporter, which makes the Pi a SPOF for all synthetic monitoring.

What the docs promise and the config does not deliver: Grafana, Keycloak, ntfy, Prometheus, Alertmanager, S3, GitLab.

The unrouted replicas are not free. They consume RAM on the weakest node, they open Postgres connections, Keycloak runs
schema migrations against the shared database from a third node, and Prometheus scrapes them so they appear in
dashboards as though they were serving traffic.

### High: no restore drill, no RPO, no RTO

Postgres and GitLab both dump-and-rsync. There is no documented restore procedure, no test restore, and no statement of
acceptable data loss. Immich photos live on NFS, so a database dump alone does not reconstitute the service.
`docs/how-to-postgres-setup.md` documents backup and stops.

> **Version 8 — docs only, not a drill.** [restore-postgres.md](runbooks/restore-postgres.md) and
> [restore-gitlab.md](runbooks/restore-gitlab.md) state RPO (last successful dump) and RTO (untested). No live restore
> was run.

### Medium: `magicRollback = false` where recovery is hardest

Disabled on `proxmox-observability-1`, `proxmox-observability-2`, and `rpi4`. A bad activation on those hosts does not
auto-revert, and nothing in `docs/deployments.md` explains generations, `nixos-rebuild --rollback`, or how to recover a
host that stops answering SSH. `make reboot-all` — the only recovery-shaped tool in the repo — points at the wrong
inventory.

> **Version 7 — stale.** `mkNode` defaults `magicRollback = true` and no host overrides it. `make reboot-all` iterates
> `PROD_HOSTS`. Rollback procedure is in `docs/runbooks/rollback.md`.

### Medium: `services.tailscale.port` collides between two hosts [tree]

`rpi4` and `proxmox-db-1` both `lib.mkForce 41647`; every other host has a unique value in the 41642–41650 range. Two
hosts using the same local WireGuard port is harmless in isolation. It matters if the per-host port scheme exists to
support NAT port-forwarding or per-host firewall rules at the router — in which case one of these two never gets a
direct path and silently falls back to DERP relays. Given the deliberate sequence, this looks like a copy-paste slip
rather than a decision.

---

## Performance

### High: a full-mesh iperf3 load generator runs on production, forever

`config/network-testing.nix` runs a root Python daemon on every host. It builds 110 directed pairs across 11 nodes,
wakes on every 10-second boundary, and if it owns the current slot runs `iperf3 -t 2` (capped at 120 Mbit only when a
cloud host is involved). `xcloud-postgres` participates. The metrics directory is mode `0775`.

This competes with WAL writes, GitLab clones, and Immich uploads for the same links, and the resulting alerts ("under 1
Gbps between VMs") are noise generators.

Layered on top: `prometheus-smokeping-prober` on every host pings **twelve** targets at `--ping.interval=1s`, and
Prometheus scrapes those probers every **5 seconds**. That is roughly 144 ICMP packets per second fleet-wide purely for
latency graphs.

> **Version 8 — fixed.** The mesh is opt-in and unset. `iperf3` is installed; the coordinator unit is not.

### High: three Prometheus agents scrape everything

Each agent carries `external_labels.__replica__ = <hostname>` and remote-writes to its local Mimir; Mimir has
`accept_ha_samples = true` with `ha_tracker.kvstore.store = "memberlist"`. If HA dedup works, you pay 3× scrape load for
1× ingest. If it does not, you pay 3× ingest — and with `ingestion_burst_size = 2147483647` and
`max_global_series_per_user = 100000000`, nothing will tell you.

Note that Mimir's HA tracker on memberlist is less battle-tested than on Consul/etcd. This is worth verifying with
`cortex_ha_tracker_elected_replica_changes_total` rather than assuming.

### Medium: `target = "all"` on three Loki and three Mimir nodes

Three compactors per system, competing over the same object storage. Combined with `autoforget_unhealthy = true` in Loki
and RF=3 in Mimir, the Pi is doing full ingester, compactor, and store-gateway duty on a microSD-backed 4 GB board.

### Medium: Postgres is sized for a smaller fleet

`shared_buffers = 512MB`, `max_connections = 100`, `max_parallel_workers_per_gather = 0`, on the documented 10 GB data
volume. PgBouncer allocates GitLab 50 and Immich 30 of those 100 connections. Immich's vector indexes and GitLab's
tables share the volume.

### Medium: Tailscale GRO tuning is likely inverted

`ethtool -K "$INTERFACE" rx-udp-gro-forwarding on rx-gro-list on`. Tailscale's guidance pairs `rx-udp-gro-forwarding on`
with `rx-gro-list **off**`. This runs on every host at boot and is presented in the docs as an optimization.

---

## Reliability

### Live evidence (2026-08-23)

Every application unit on the ten checked hosts was `active/running` except two:

1. **Vikunja on `proxmox-applications-1`** — `failed`, `start-limit-hit`, five restarts in two seconds. Log:
   `Could not connect to db: pq: unsupported startup parameter: search_path (08P01)`. Binary **2.5.0**.
   `proxmox-applications-2` was running **2.3.0** and healthy.
2. **`paperless-web` on `proxmox-applications-2`** — inactive, while internal Caddy round-robins to it with no health
   check.

The Vikunja failure is the fleet's reliability story in one incident: the same Nix expression produced two different
versions on two nodes that Caddy treats as interchangeable; the failure is invisible to the load balancer because there
is no health check; and nothing in CI or lint could have caught it because both closures evaluate fine.

### Live evidence (2026-08-24, full-fleet inspection, 20:36 SAST)

A second live pass was run 26 hours after the first: `uptime`, `free`, `df`, `systemctl --failed`, top memory/CPU
consumers, OOM history, restart counts, boot timings, and NFS mount state were collected from all twelve hosts over
SSH. `gaming` was offline and excluded. This pass caught something the tree can never show: **a fleet-wide deploy
happened during the audit window**, and its aftermath is more informative than the audit's static findings.

#### The fleet redeployed itself mid-audit, and the known fix did not ship

Eight of twelve hosts — `proxmox-applications-1`, `proxmox-applications-2`, `proxmox-db-1`, `proxmox-db-2`,
`proxmox-dev`, `proxmox-lb`, `proxmox-observability-1`, `proxmox-observability-2` — show **43–44 minutes of uptime**,
all having booted within the same minute (`19:51–19:52 SAST`). `xcloud-caddy` (27 days), `xcloud-postgres` (35 days),
and `rpi4` (8 days) were untouched. This is a fleet-wide deploy or reboot, not a coincidence.

The working tree has carried a fix for the Vikunja/PgBouncer `search_path` incident since before this audit began
(`services/postgres.nix:80`, `ignore_startup_parameters = "extra_float_digits,search_path"`). That fix **did not ship**
in this deploy:

```
# git working tree
80:        ignore_startup_parameters = "extra_float_digits,search_path";

# live on xcloud-postgres, post-deploy
ignore_startup_parameters=extra_float_digits
```

And the consequence is immediate and mechanical. Freshly booted, `vikunja.service` on `proxmox-applications-1` fails
five times in under a second and hits `start-limit-hit`, logging the exact same error as the original incident:

```
Aug 24 19:52:11 proxmox-applications-1 vikunja[1211]: {"level":"ERROR","msg":"Could not connect to db: pq: unsupported startup parameter: search_path (08P01)"}
...
Aug 24 19:52:12 proxmox-applications-1 systemd[1]: vikunja.service: Failed with result 'start-limit-hit'.
```

This is the single clearest data point in this entire audit for **Deployment processes** and **Validation mechanism**:
a known, already-diagnosed, already-fixed outage was reintroduced by a deploy because the fix sat in the working tree
(visible in `git status` at the top of this document) instead of being committed and shipped. No test, no lint, and no
CI gate would have caught this either way — the failure mode isn't a bad change, it's an **unshipped good change**, and
nothing in the pipeline distinguishes "fix written" from "fix deployed." Confirms **High: version skew across
"clustered" nodes is unmanaged**, below, and adds a sharper case: it is not just that apps-1 and apps-2 can diverge, it
is that the repository's own working tree can diverge from every host in the fleet with no signal anywhere.

#### `remoteBuild` is putting production Postgres at risk of OOM, live

`xcloud-postgres` runs Postgres, PgBouncer, and three Redis instances in **1.9 GiB of RAM** — confirmed by `free -h`
(`available` was 561 MiB at inspection time, with 71 MiB literally free). The kernel OOM-killed processes on this host
on **two consecutive days**, both times clustered in the same few minutes as the fleet deploy activity:

```
Aug 23 19:42:02 xcloud-postgres kernel: Out of memory: Killed process 929792 (systemd) ...
Aug 23 19:42:02 xcloud-postgres kernel: Out of memory: Killed process 929794 ((sd-pam)) ...
Aug 23 19:42:02 xcloud-postgres kernel: Out of memory: Killed process 929842 (nix-daemon) total-vm:1311028kB, anon-rss:150740kB ...
Aug 24 19:44:54 xcloud-postgres kernel: Out of memory: Killed process 958847 (systemd) ...
Aug 24 19:46:46 xcloud-postgres kernel: Out of memory: Killed process 959410 (systemd) ...
Aug 24 19:46:49 xcloud-postgres kernel: Out of memory: Killed process 959460 (nix-daemon) total-vm:1348312kB, anon-rss:204316kB ...
```

`xcloud-postgres` did not reboot in this window — it kept its 35-day uptime — but `nix-daemon` and the login session
that invoked it were repeatedly killed while `deploy-rs`'s `remoteBuild = true` compiled a new system closure **on the
production database VM itself**, competing with PgBouncer and three Redis instances for under 2 GiB of RAM. Postgres
was not the process killed this time. It is the smallest thing on that host and the OOM killer has not chosen it yet.
This is luck, not design, and it happened on back-to-back days. Confirms and sharpens **Critical: `remoteBuild` means
the opposite of what the docs say** under Deployment processes: the risk isn't just that the Pi builds unsupervised,
it's that every RAM-starved VM in the fleet — including the one holding all relational state — rebuilds itself under
memory pressure on every deploy.

#### The Postgres backup silently failed for at least 11 days

`postgresqlBackup.timer` runs nightly at 02:00 SAST and rsyncs dumps to `rpi4:/mnt/usb-backup`. The run on
**2026-08-23** failed outright:

```
Aug 23 02:02:52 xcloud-postgres postgresqlBackup-post-start[910150]: ssh: connect to host rpi4 port 22: Connection timed out
Aug 23 02:02:52 xcloud-postgres systemd[1]: postgresqlBackup.service: Failed with result 'exit-code'.
```

The **2026-08-24** run then transferred a backlog stretching back to `all_2026-08-13_02-00-46.sql.zstd` — eleven
distinct daily dumps in one run — and took **21 minutes 3 seconds** of wall clock time on a host with 1.9 GiB of RAM,
overlapping with the OOM window above:

```
Aug 24 02:21:03 xcloud-postgres systemd[1]: postgresqlBackup.service: Consumed 36.775s CPU time over 21min 3.882s wall
clock time, 160.4M memory peak, 6.9G read from disk, 587.8M written to disk, ... 3.4G outgoing IP traffic.
```

Two readings, both bad. Either the destination (`rpi4`) has been intermittently unreachable for well over a week and
each night's failure was silent because nothing alerts on `postgresqlBackup.service` failing, or backups had been
silently queuing locally for 11 days before this one run happened to catch up. Either way: **a production database
backup job failed for over a week with zero operator-visible signal**, which is the exact gap called out in
**High: no restore drill, no RPO, no RTO** under Resilience — that finding assumed backups run but are untested; live
evidence shows they don't reliably run either. Add "alert on `postgresqlBackup.service` failure" to the fix list; it is
cheaper than everything else in this section combined.

#### Loki crash-looped over 2,800 times in a single day, and nothing paged

`journalctl --list-boots` on `proxmox-observability-1` shows the host rebooted **eight times in roughly 30 hours** on
2026-08-23, including two boots that lasted only **34 and 38 seconds** before the next reboot — consistent with either
a wedged activation or an external (hypervisor/watchdog) reset. Within that period, `loki.service` had already
accumulated a restart counter over **2,800**, all `status=1/FAILURE`, roughly 24–25 seconds apart:

```
Aug 17 15:18:19 proxmox-observability-1 systemd[1]: loki.service: Scheduled restart job, restart counter is at 2800.
Aug 17 15:18:44 proxmox-observability-1 systemd[1]: loki.service: Scheduled restart job, restart counter is at 2801.
Aug 17 15:19:08 proxmox-observability-1 systemd[1]: loki.service: Scheduled restart job, restart counter is at 2802.
```

The root cause is in the log Loki prints right before each crash — the `mkForce`-wrapped `ExecStart` starts fine, joins
memberlist, and then dies in module init because Garage (this fleet's S3 backend) returned `503 Service Unavailable`:

```
Aug 17 15:15:08 proxmox-observability-1 sh[159327]: init compactor: failed to init delete store: operation error S3:
DeleteObject, exceeded maximum number of attempts, 3, https response error StatusCode: 503, ... api error
ServiceUnavailable: Service Unavailable
Aug 17 15:15:08 proxmox-observability-1 sh[159327]: error initialising module: compactor
```

Loki treats a **transient** object-store 503 as a fatal startup error rather than retrying with backoff, so a Garage
blip that should be a few seconds of query errors instead becomes an indefinite crash-loop, 24 seconds at a time,
until Garage recovers. 2,800 restarts × ~25s is roughly 19 hours of continuous crash-looping — the better part of a
day — with no evidence anyone was paged, because Alertmanager has no rule for "unit is crash-looping" (only for
specific application-level symptoms), and this is exactly the theoretical risk called out in **High: `lib.mkForce` is
the integration strategy**: "The Loki and Mimir wrappers ... loop forever ... A wedged `tailscaled` produces a unit
that hangs rather than fails." The live failure mode turned out to be worse than predicted — it doesn't hang, it
crash-loops fast enough to generate tens of thousands of journal lines and non-trivial CPU/log churn, and it directly
implicates **Garage's own reliability** (`Critical: four hubs, no alternative` → `truenas-scale is the disk plane`):
when the shared Garage backend degrades, it doesn't just serve slow queries, it can take down every Loki node that
tries to (re)start during the outage.

#### Resource saturation, measured

| Host | RAM used/total | RAM available | Root disk | Load avg (1m) | Notes |
|---|---|---|---|---|---|
| `xcloud-postgres` | 1.4/1.9 GiB (74%) | 561 MiB | 64% | 0.51 | Repeated OOM kills, see above |
| `xcloud-caddy` | 806 MiB/1.9 GiB (42%) | 1.1 GiB | 67% | 0.21 | One OOM kill of `nix` on Aug 16 |
| `proxmox-applications-1` | 3.6/11 GiB (33%) | 8.1 GiB | **83%**, 5.7 GiB free | 0.32 | Vikunja failed; disk headroom is the tightest in the fleet outside the two 1.9 GiB VMs |
| `proxmox-applications-2` | 5.0/11 GiB (45%) | 6.7 GiB | 50% | 0.16 | Healthy |
| `proxmox-observability-1` | 2.5/3.8 GiB (66%) | 1.3 GiB | 54% | 0.43 | Mimir alone: ~1.0 GiB RSS (24% of host RAM) |
| `proxmox-observability-2` | 2.5/3.8 GiB (66%) | 1.3 GiB | 43% | 0.39 | Mimir alone: ~0.9 GiB RSS |
| `proxmox-db-1` / `proxmox-db-2` | ~0.85/3.8 GiB (22%) | 3.0 GiB | 35–39% | 0.13–0.14 | Comfortable headroom |
| `proxmox-dev` | 0.95/15 GiB (6%) | 14 GiB | 35% (of 197 GiB) | 0.09 | Coder had 6 restarts since boot |
| `proxmox-lb` | 677 MiB/1.9 GiB (36%) | 1.3 GiB | 32% | 0.02 | Tailscale daemon alone: 10% CPU average |
| `rpi4` | 2.9/7.6 GiB (38%) | 4.7 GiB | 34% (root), 17% (USB backup, 114 GiB) | **3.04 / 3.38 / 3.96** | Sustained load near or above core count; see below |

`rpi4`'s load average is the standout: sustained at 3–4 on the fleet's weakest node, with `ps` reporting `tailscaled`
at 76% average CPU utilization since boot, `systemd` at 48%, `mimir` at 33%, `garage` at 21%, and `prometheus` at 15%,
concurrently. This is not a spike, it is the steady state 8 days into an uptime window, and it corroborates
**Medium: the Pi is over-committed** under Robustness with hard numbers rather than an inventory argument. The USB
backup disk is, at least right now, correctly mounted with real data on it (17% of 114 GiB) — the "backups silently
writing into an empty SD card" risk described under **High: the USB backup mount fails open** did not manifest during
this snapshot, but the mechanism (`nofail` + 5s timeout) is unchanged and the risk is about what happens when the disk
is *not* present, which this snapshot cannot rule out.

The `proxmox-applications-1` disk figure (83% used, 5.7 GiB free on a 34 GiB root volume, NFS mounts are separate and
mostly idle) deserves a dedicated look outside this audit: at the observed rate it is the first host in the fleet
likely to hit ENOSPC, which would take Jellyfin, Immich, Keycloak, Vaultwarden, Vikunja, Actual, Paperless, Luanti,
and OpenArena down simultaneously — every service on that VM. `nix-collect-garbage -d` and an inventory of
`/nix/store` and `/var/lib/*` growth would be the first two steps.

#### Confirmed live, briefly

A handful of tree-based findings elsewhere in this document were checked directly against running state and hold up:

- **Redis is genuinely unauthenticated** (Security → `Critical: Redis has no authentication`): `redis-cli -p 6379/6380/6381 ping` returned `PONG` with no credentials from a plain SSH session on `xcloud-postgres` itself, let alone the tailnet.
- **PostgreSQL connection pressure is real, not theoretical** (Performance → `Medium: Postgres is sized for a smaller fleet`): `pg_stat_activity` showed 42 of 100 `max_connections` in use during otherwise idle, off-peak conditions.
- **The iperf3 load generator is live** (Performance → `High: a full-mesh iperf3 load generator runs on production, forever`): the `iperf3-speedtest-coordinator` root process and a listening `iperf3 --server` were both observed running on `proxmox-observability-1`.
- **`nixos-upgrade.service` does not exist anywhere in the fleet** — confirming that the `NixOSConfigurationFailed` alert in `services/mimir-rules.nix` (Reliability → `Medium: the alerting rules are borrowed and partly inapplicable`) monitors a feature this fleet has never enabled. It cannot fire true and cannot fire false; it is inert.
- **Garage cluster health could not be verified live** — `garage status` requires an interactive sudo password on all three nodes and there is no read-only path (metrics endpoint, admin API without a token) that this audit had credentials for. That is itself a finding: there is no way to check Garage's cluster health without a live human at a terminal with the root password, which is a poor position to be in during an actual incident.

### High: version skew across "clustered" nodes is unmanaged

Nothing records or enforces that apps-1 and apps-2 must run the same closure. `deploy-rs` targets are independent CI
jobs. A partial deploy leaves a heterogeneous "cluster" indefinitely.

> **Version 8.** Flake check `co-routed-peers` asserts Grafana/Loki/Mimir/ntfy packages match on obs-1/obs-2 and
> Keycloak's package matches on apps-1/apps-2. Whole-closure equality is not required (obs-1 also runs extra exporters).

### High: several load balancers have no health checks

Vikunja (`round_robin`, none), Paperless (`round_robin`, `unhealthy_status 5xx` only), Attic (`round_robin`, none).
Grafana, Keycloak, ntfy, Loki, Mimir, and Garage do have proper `health_uri` blocks — the pattern exists in the same
file and was simply not applied consistently.

> **Version 8 — fixed.** `health_uri` on the clustered internal vhosts. Paperless is apps-1 only.

### Medium: the alerting rules are borrowed and partly inapplicable

`services/mimir-rules.nix` carries Kubernetes service-discovery alerts, `runbook_url`s pointing at prometheus-operator
runbooks, and `PrometheusNotIngestingSamples` against agent-mode Prometheus. One agent-mode false positive was
explicitly disabled with a comment; the rest were not. `GpuDriverHangDetected` is built on EDAC memory counters.

---

## Deployment processes

### Critical: production deploys skip the checks the repo defines

```yaml
- nix develop -c deploy $NIX_FLAGS --targets "$TARGETS" --debug-logs --skip-checks
```

Identical in every `Makefile` deploy target. `flake.nix` defines `deployChecks`; `scripts/lint.sh` evaluates their
`drvPath`; the deploy then skips running them. Merging to `main` auto-deploys every Proxmox, xcloud, and rpi4 node in
parallel jobs. There is no staging, no canary, and no documented abort procedure.

> **Version 6 — fixed (2026-08-28).** `--skip-checks` is gone from the Makefile and from GitLab deploy jobs. CI
> `check-inventory` runs `make check-inventory`. There is still no staging environment; that is a separate finding.

### Critical: `remoteBuild` means the opposite of what the docs say

deploy-rs `remoteBuild = true` builds **on the target host**. `docs/deployments.md` and `docs/hosts/rpi4.md` both claim
the Pi's closure is built on CI precisely to avoid taxing the Pi.

`scripts/build.sh` filters hosts by `builtins.currentSystem`, so x86_64 CI **never builds rpi4**. Combined with
`--skip-checks`, the aarch64 closure — Grafana, Mimir, Loki, Keycloak, Vaultwarden, Garage — is compiled unsupervised on
a 4 GB Raspberry Pi.

`proxmox-applications-2` already sets `boot.binfmt.emulatedSystems = [ "aarch64-linux" ]`. The machinery for a proper
cross-build exists and is unused.

> **Version 6 — fixed in tree (2026-08-28).** `remoteBuild = false` on `xcloud-caddy`, `xcloud-postgres`, `proxmox-lb`,
> and `rpi4`. `docs/deployments.md` matches. The Pi itself was not deployed in that pass (still unreachable).

### High: CI installs Nix from the internet on every job

`curl ... https://install.determinate.systems/nix | sh` in `before_script`, on `debian:trixie-slim`, with a 24-hour job
timeout, injecting `extra-substituters = http://proxmox-lb:8080/attic` into the installer. The SSH private key is
written to `~/.ssh/id_ed25519` in the same block, and `SSH_CONFIG` disables host-key checking for a list that is **half
ghost hosts**.

> **Version 8 — pinned.** Installer URL is `.../nix/tag/v3.22.2`. Host-key checking uses `ssh/fleet_known_hosts`.

### High: two CI systems, one of which is decorative

GitLab holds the real deploy pipeline. `.github/workflows/lint.yml` runs `make lint` via
`DeterminateSystems/nix-installer-action@main` — an unpinned moving tag — with no format check, no build, and no deploy.
A green GitHub badge on a pull request says nothing about whether GitLab will ship it.

> **Version 8.** GitHub Action pinned to `DeterminateSystems/nix-installer-action@v22`. GitLab is still the deploy path.

### High: the Makefile uses a different deploy-rs than the flake

`nix run github:serokell/deploy-rs` ignores `flake.lock`; CI uses the flake input. Local and CI deploys can use
different tool versions against the same fleet.

`build-remote` rsyncs the whole tree to `root@gaming` and builds there, while `proxmox-dev` — the actual builder, with
binfmt and a build cache — sits idle.

> **Version 7 — fixed (2026-08-29).** The Makefile `DEPLOY` variable is `nix develop -c deploy`, so local deploys use
> the same `deploy-rs` as the flake. `build-remote` still rsyncs to a builder; that path is unused by CI.

### High: no rollback runbook exists

Covered under Resilience. It belongs here too: the deployment process has no defined reverse.

> **Version 7 — fixed (2026-08-29).** [docs/runbooks/rollback.md](runbooks/rollback.md) covers generations,
> `nixos-rebuild --rollback`, console recovery, and `make reboot-all`. `docs/deployments.md` links to it.
> `magicRollback` currently defaults to `true` on every node (the Medium finding that obs/`rpi4` opted out is stale).

---

## Validation mechanism

### What exists

1. `scripts/lint.sh` — evaluates `checks.{x86_64,aarch64}-linux.deploy-schema.drvPath`, then each
   `deploy.nodes.<host>.profiles.system.path.drvPath`. Sequential.
2. `nix fmt -- --ci` in the GitLab `format` job.
3. `scripts/build.sh` — `nix build` per host **for the current architecture only**, optional Attic push.
4. GitHub `make lint` on push and PR.
5. **nixpkgs-provided config validation**, which the repo gets for free and does not acknowledge: Alertmanager's config
   is `amtool`-checked at build time [eval]. This is real and worth keeping in mind before adding more `mkForce`.
6. Runtime: blackbox probes (from the Pi only), Prometheus/Mimir rules (dependent on the alerting path actually
   working).

### What does not exist

- `nix flake check` as actually run (the docs claim it; the script does not do it).
- Any `nixosTest` / VM integration test.
- `nixos-rebuild dry-activate`.
- `caddy validate` on either Caddy config. `enableConfigCheck = false` on blackbox means its templated YAML is never
  checked at eval time either.
- Any test that the six inventories agree — the `systemd exporter` gap and four ghost hostnames would each be a two-line
  assertion.
- Any test that "clustered" hosts run the same closure. This is the exact gap that produced the live Vikunja 2.5-vs-2.3
  split.
- Restore tests for Postgres or GitLab.
- Any check that `sops.secrets` declarations match `secrets/<host>/secrets.yaml`. They currently do — verified by eval
  for this audit — but nothing keeps them in sync, and the **inverse** check (secrets stored but never declared) is what
  would have surfaced the over-provisioning above. Both directions are a short `assertion` away, since
  `config.sops.secrets` and the YAML key list are both readable at eval time.

**The only gate before production is "the derivation evaluates."** Every finding in this document passes lint.

The cheapest high-value additions, in order:

1. `assertions` in a shared module comparing the fleet host list against Prometheus targets, smokeping args,
   `network-testing.nix` nodes, and the Makefile inventory generated from the flake.
2. An eval-time assertion that each host's declared `sops.secrets` keys exist in its secrets file.
3. `nix flake check` for real, and stop passing `--skip-checks`.
4. A `nixosTest` for the PgBouncer + Postgres + one client path. That single test would have caught the Vikunja
   regression.

---

## Prioritized fix list

**Do this one first, tonight, before anything else on this list:** COMPLETED (2026-08-28). Live on
`xcloud-postgres`: `ignore_startup_parameters=extra_float_digits,search_path`. `vikunja.service` on
`proxmox-applications-1` is `active`.

If only ten more things happen, in this order:

1. COMPLETED (in-scope). `initialAdminPassword` is gone; Keycloak reads `KC_BOOTSTRAP_ADMIN_*` from a sops template.
   `/admin*` on the identity vhost aborts unless the client is in `100.64.0.0/10`. Applications still use
   `realms/master` (out of this remediation's topology freeze).
2. COMPLETED (2026-08-28). Shared age recipient on `proxmox-dev` / `proxmox-db-1` / `proxmox-db-2` split; Garage
   RPC/admin tokens and all four S3 keys rotated. `tailscale/exporter_env` is the one remaining manual rotation
   (Tailscale admin console). See `docs/runbooks/split-shared-host-keys.md`.
3. COMPLETED. Makefile and `.gitlab-ci.yml` no longer pass `--skip-checks`. CI `check-inventory` job runs
   `make check-inventory`.
4. COMPLETED (Redis). Live on `xcloud-postgres`: `redis-cli -p 6379/6380/6381 ping` returns
   `NOAUTH Authentication required.` `protected-mode` is `yes`. `trustedInterfaces` was removed in a later pass
   (Version 6); Redis is now reachable on `tailscale0` only because of an explicit allow-list.
5. COMPLETED. `services.prometheus.exporters.node.openFirewall = false`. Live `nft` on `xcloud-postgres` has no
   global `dport 9100 accept`; 9100 is reachable via the trusted-interface accept on `tailscale0`/`lo` only.
6. COMPLETED in tree. Postgres/GitLab backups copy-then-delete. USB mount is fail-closed (`hosts/rpi4/usb-backup-mount.nix`).
   `rpi4` was unreachable on 2026-08-28, so the USB unit was not live-checked.
7. COMPLETED. Ghost names are gone from the Makefile, CI `SSH_CONFIG`, and gitlab-runner mirrors (now
   `proxmox-applications-2:5000-5003`). `reboot-all` iterates `PROD_HOSTS`.
8. COMPLETED for the listed doc lies (README roles, RF numbers, `psql -p 5433`, oauth2 Redis host, Attic/caddy-internal
   docs). Routing or deleting the unrouted Pi replicas was out of scope and is still OPEN.
9. COMPLETED in tree. `remoteBuild = false` on `xcloud-caddy`, `xcloud-postgres`, `proxmox-lb`, and `rpi4`.
   `docs/deployments.md` matches. `rpi4` itself was not deployed in this pass.
10. COMPLETED in tree. Internal Caddy has `health_uri` on Vikunja, Paperless, Attic, and the other clustered
    upstreams. `config/fleet-inventory.nix` asserts scrape targets against the host list. Same-closure assertion for
    co-routed hosts was not added.
11. COMPLETED in tree. `services/mimir-rules.nix` has unit-failed, crash-loop, backup-failed, and backup-stale rules.
    Live on `proxmox-observability-1` (grafana/ntfy/smokeping active; loki/mimir were still `activating` at check time).
12. COMPLETED. Same four hosts as item 9 set `remoteBuild = false` so CI copies a prebuilt closure instead of compiling
    on the 1.9 GiB VMs.

Do not add more replicas until the four hubs are either made redundant or explicitly documented as single-instance.
Adding a fourth Keycloak changes nothing while one Postgres holds the fleet.

---

## Remediation status (2026-08-28)

Config-only work from this audit (Nix, CI, Makefile, sops pruning, docs, inventory assertions) was implemented in the
tree and then pushed to the fleet. Topology and product changes (second edge, Patroni, WAF blocking, deleting Pi
replicas, splitting cloned SSH host keys) were explicitly out of scope.

### What was checked live

| Check | Result |
|---|---|
| PgBouncer `search_path` | Live on `xcloud-postgres` |
| Redis AUTH on 6379/6380/6381 | Live: `NOAUTH` without a password |
| Node exporter public `dport 9100 accept` | Absent from `inet nixos-fw` on `xcloud-postgres` |
| Keycloak bootstrap env / identity `/admin*` gate | Live on `proxmox-applications-1` (unit active; Caddyfile in tree) |
| Vikunja on apps-1 | `active` (was `start-limit-hit` in the 2026-08-24 evidence) |
| Smokeping `wait-for-host-smokeping-*` coupling | `Wants=` count 0; `wait-for-host-smokeping-rpi4` masked or absent on every reachable host |
| iperf3 mesh daemon | Not installed (`iperf3-speedtest-coordinator` not-found); mesh is opt-in and unset |
| Ghost hostnames in operator tooling | Gone from Makefile / CI SSH config |
| `--skip-checks` | Gone from Makefile and GitLab deploy jobs |

Running generation `26.11.20260813.6b5e5b7` confirmed on: `xcloud-caddy`, `xcloud-postgres`, `proxmox-lb`,
`proxmox-db-1`, `proxmox-db-2`, `proxmox-dev`, `proxmox-observability-1`, `proxmox-observability-2`,
`proxmox-applications-1`, `gaming`.

### Still open after this pass

- **`rpi4` is unreachable.** USB fail-closed and `remoteBuild = false` are in the tree only. B2/B3 firewall rules
  also need a deploy once it is back.
- **`tailscale/exporter_env`** has not been rotated (needs a new OAuth client in the Tailscale admin console).
- Detection-only WAF, Keycloak `realms/master`, and the unrouted Pi replicas (topology freeze).
- **Four hubs, no alternative** (`xcloud-postgres`, `xcloud-caddy`, `proxmox-lb`, `truenas-scale`).

---

## Version 5: live incident and Alertmanager triage (2026-08-28, evening)

Separately from the remediation pass above, Alertmanager (`proxmox-lb:9093`) was showing 38 firing alerts. Working
through them live turned up a real root cause the v4 audit had only described symptomatically (the Loki crash-loop,
line ~977), plus several smaller fixes. Backup-timer staleness and rpi4 connectivity/blackbox alerts were explicitly
descoped by the operator and are not covered here — see "Still open" below.

### Root cause found: Garage metadata corruption, not just a Garage outage

The Loki crash-loop the v4 audit documented (2,800+ restarts, `S3: DeleteObject ... 503 ServiceUnavailable`) was
previously understood only as "Garage returned 503." Tonight's investigation found *why*: `/var/lib/garage/meta/db.sqlite`
on **both** `proxmox-db-1` and `proxmox-db-2` was malformed (health endpoint returned `200`, but S3 `ListObjects` on
either node returned `503`, so every S3 client — Loki, Mimir, Attic — failed the same way regardless of which node it
happened to hit). Fixed live:

- `proxmox-db-1`: `sqlite3 .recover` produced an image that passed `integrity_check`; installed as `db.sqlite`, old
  files kept as `.malformed` / `.pre-recover.*`.
- `proxmox-db-2`: sqlite/WAL/SHM moved aside and allowed to resync from cluster state (RF=2, zone redundancy maximum).
- Unauthenticated S3 `GET` on both nodes went from `503` to the expected `403`, and Loki's `GetObject` calls started
  succeeding.
- `services/garage.nix` now sets `metadata_auto_snapshot_interval = "6h"` so a torn write to a live `db.sqlite` — the
  likely original cause — snapshots instead of corrupting the only copy.
- Residual: some partitions still log `block_ref` messagepack decode errors (recovery artifacts on data that was
  already unreadable). Reads work. **Open follow-up:** `garage repair --yes -a block-refs` / `blocks` on both nodes.

Separately, `/var/lib/loki/index/wal/*` on `proxmox-observability-1` was root-owned from a prior root-started run, which
by itself would have kept crashing Loki even after Garage recovered. `services/loki.nix` now runs a
`+`-prefixed `ExecStartPre` that `mkdir -p`s and `chown -R loki:loki`s `index`, `index_cache`, and `compactor` before
every start.

### Other alerts fixed this pass

- **`TargetDown` on `xcloud-caddy:2019`** — see the Version 5 correction under "Critical: `trustedInterfaces`" above.
  Prometheus's `caddy` scrape job now targets both `xcloud-caddy:2019` and `proxmox-lb:2019`; both report `up` from
  both observability Prometheus agents.
- **`LowDiskSpace`** on `gaming` (`nix-collect-garbage -d` freed 44.2 GiB; 82% used / 163 GiB free, back above the 15%
  threshold) and `xcloud-postgres` (journal vacuum + store GC freed ~3.4 GiB; 65% used / 4.8 GiB free on a 15G root —
  tight, see "Next iteration" candidates below).
- **`TailscaleNodeHighPacketLoss`**: 11 of the alert's instances were smokeping probes *to* `rpi4`, which the operator
  had already flagged as a known-unreachable, out-of-scope host tonight. `services/mimir-rules.nix` now excludes
  `exported_host=~"rpi4.*"` from the alert expression rather than continuing to page on a host nobody is fixing this
  session.
- **`ServiceRestartingRepeatedly`** on `paperless-scheduler.service`, `gitlab-db-config.service`, `gitlab-runner.service`
  (proxmox-applications-1 / -2 / -dev) — all had `NRestarts=0` and were `active` at check time; the alert's
  `increase()` window is 6h and was still counting restarts from an earlier-in-the-day outage (apps-2 GitLab/registry
  incident, unrelated to this pass). `loki.service` was the one real, ongoing crash loop and is covered above.

### Still open after this pass

- **Backup timers (`gitlab-backup.timer`, `postgresqlBackup.timer`) and rpi4 connectivity/blackbox `TargetDown`** — out
  of scope for this pass at the operator's request; still firing.
- **Garage `block-refs`/`blocks` repair** launched 2026-08-29 (`garage repair --yes -a` on both nodes). Messagepack
  decode noise in the last 10 minutes: **0** on both db nodes. Resync queues were still draining at check time
  (healthy; S3 `403`, Loki/Mimir `/ready` `200`).
- **`proxmox-observability-1` guest RAM** — 6 GiB is set in the Proxmox balloon config but the VM has not been
  rebooted, so it is still running with the old 3.8 GiB.
- **`xcloud-postgres` disk headroom** — 4.8 GiB free on a 15G root after cleanup is still the tightest margin in the
  fleet outside the Pi; the v4 audit's own resource-saturation table already flagged this VM's disk as worth
  watching (line ~1014).

---

## Closing

This is the work of someone who learned real NixOS patterns and then scaled the number of hosts faster than the control
plane for those hosts. The failure mode is not amateurism — it is that the documentation and the HA vocabulary were
never updated when the topology became hub-and-spoke, and CI was handed root on twelve machines without being handed
tests.

Two concrete lessons from writing v2 of this document:

- **Reading Nix is not the same as evaluating it.** Five findings in v1 were wrong because module defaults,
  `ExecStartPre`, and nftables rule generation are invisible in the source. `nix eval` is cheap; use it before believing
  a security claim.
- **The absence of a port in `allowedTCPPorts` does not mean the port is closed.** That one is worth remembering the
  next time this fleet is audited.

Treat Tailscale as a VPN, not a security boundary. Treat `xcloud-postgres`, `xcloud-caddy`, `proxmox-lb`, and
`truenas-scale` as the availability design, because they are. Treat `rpi4` as a blackbox prober and a backup target
until something routes to it. Then the parts that are genuinely well built — sops templating, PgBouncer, Disko,
memberlist, Garage, the internal load balancer, the Alertmanager wrapper — will sit inside a system that matches its own
description.

---

## Version 7: leftover Criticals and High nits (2026-08-29)

Docs and operator tooling first, then the remaining live High items that did not need a topology decision.

- Audit headings for skip-checks, `remoteBuild`, Makefile deploy-rs, `make edit-secrets`, Keycloak admin, Redis AUTH,
  and `trustedInterfaces` now have Version 6/7 notes matching the live fleet.
- Empty leftover sops stubs pruned from `proxmox-lb`, `proxmox-db-1`, `proxmox-db-2`, and `rpi4`. `scripts/check-secrets.sh`
  reports **ok** on every host. Deployed lb + both db nodes (rpi4 still unreachable, file-only).
- GitLab `signup_enabled = false` live in `/run/gitlab/config/gitlab.yml`. `/users/sign_up` 302s to `/users/sign_in`;
  the sign-in page still posts to `/users/auth/openid_connect`. Deployed `proxmox-applications-2`.
- Passwordless sudo removed on `xcloud-caddy` and `xcloud-postgres`. `alex` is a locked account (`passwd -S` = `L`);
  `sudo -n true` now fails with `a password is required`. Root SSH is unchanged.
- Rollback runbook: `docs/runbooks/rollback.md`. `magicRollback` defaults to `true` on every node.
- Garage `repair --yes -a block-refs` and `blocks` launched on both db nodes. Messagepack decode lines in the following
  10 minutes: 0. Loki/Mimir `/ready` 200, unauthenticated S3 403, Garage `/health` 200. Resync queues still draining.
- **`rpi4` still unreachable** (SSH timeout). USB fail-closed and B2/B3 stay in-tree only.

Alertmanager stayed at 16 firing through this pass (15 `TargetDown`, almost all rpi4 blackbox; 1 Tailscale
retransmission). No new internal `TargetDown`.

---

## Version 8: remaining High items (2026-08-29)

- Audit headings that were already live (HA table, GitLab runner, Paperless LB, node exporter, USB fail-closed,
  rsync copy-then-delete, iperf mesh, health_uri, Mimir RF/limits) marked Version 8.
- Jellyfin and Actual Budget use `fleet.waitForHost`. `docs/todo-deviations.md` rewritten.
- Restore runbooks + RPO/RTO stated; no live restore drill.
- SSH 22 on xcloud VMs is tailscale0-only. CI deploy key kept.
- Attic HTTPS vhost `attic.alexmayers.co.za` was added here; Version 9 removed it (tailnet-only).
- CI: Determinate installer `v3.22.2`, GitHub Action `@v22`. Flake check `co-routed-peers`.
- `rpi4` still unreachable.

---

## Version 9: tailnet-only Attic as the deploy store (2026-08-29)

- Public `attic.alexmayers.co.za` vhost removed. Fleet `nix.settings.substituters` is only
  `http://proxmox-lb:8080/attic`. Builders pass `cache.nixos.org` on the command line / CI `NIX_CONFIG`.
- `make build` and CI build require `ATTIC_TOKEN` and always `attic push`. Production deploys
  `nix copy --from` Attic then `switch-to-configuration` (`scripts/deploy-from-attic.sh`).
- `atticd` uses PgBouncer `:5432` (raw `:5433` is firewalled). `pool_mode=session` for the `attic` database.
  Missing Garage chunk keys were cleared (truncate attic `chunk`/`nar`/`object`) and closures re-pushed with
  `--ignore-upstream-cache-filter`. Internal Caddy Attic proxy uses `flush_interval -1` so NAR streams are not
  truncated. `nix.settings.substituters` is `mkForce`d so cache.nixos.org is not merged back in.
- `rpi4` still unreachable. `gaming` stays off the production deploy path.


