# Custom NixOS Options

To maintain clean configurations and handle complex mounting behaviors uniformly across the fleet, this repository
implements custom NixOS modules under the `config/` directory. This document describes the option schemas, use cases,
and underlying mechanics of these options.

---

## NFS loop images (Debian GitLab guest)

The NixOS `services.build-cache` module is gone. GitLab and the registry
caches on `proxmox-gitlab-debian` mount their NFS loop images from the
`fleet.debian_guest` gitlab and registry_cache roles. See
[proxmox-gitlab-debian.md](services/proxmox-gitlab-debian.md) and
[container-registry.md](services/container-registry.md).

---

## 📡 Storage Availability Guards (`fleet.waitForHost`)

* **Implementation:** [config/wait-for-host.nix](../config/wait-for-host.nix)
* **Use Cases:** Inherited by [config/basics.nix](../config/basics.nix) and applied
  globally to all nodes.

### The Problem

Since the fleet mounts remote directories over the network (specifically via the Tailscale overlay network), a boot-time
race condition exists. If systemd attempts to mount NFS shares before the network card is fully online, before Tailscale
registers, or before the target NAS is reachable, the mount fails. This can result in system boots dropping into
emergency mode.

### The Solution

The `fleet.waitForHost` module declares dependency-aware ping checkpoints. It creates oneshot systemd services that
block target mounts until connectivity to the destination IP/hostname is verified.

### Configuration Schema

Options are defined under `fleet.waitForHost.<name>`:

* **`host`** (string, required): Hostname or IP to reach.
* **`port`** (TCP port, optional): If set, wait for that port to accept connections. If unset, ICMP ping.
* **`maxRetries`** (int, default `600`): Wall-clock seconds to wait before failing.
* **`forServices`** (list of unit names, default `[]`): Units that `Requires=` and `After=` this wait.
  NFS mounts still use `x-systemd.requires=wait-for-host-<name>.service` instead.

Waits are **not** `wantedBy = multi-user.target`. They only run when a mount or service requires them, so VMs can boot
in any order: a host that does not need Postgres will not stall 600s if `xcloud-postgres` is still coming up.

### Systemd Integration

For each declared check, `wait-for-host-${name}.service` is created:

- `after` / `wants` `network-online.target` and `tailscaled.service`.
- `TimeoutStartSec` is `maxRetries + 30` seconds.
- Ping (`ping -c 1 -W 1`) or TCP (`nc -z -w 1 host port`), retried until success or timeout.

Presets under `fleet.waitFor.garage.<name>` and `fleet.waitFor.postgres.<name>` expand to the usual
`proxmox-observability:3902` and `xcloud-postgres:5432` waits.

---

## App registry (`fleet.apps`)

* **Implementation:** [config/fleet-apps.nix](../config/fleet-apps.nix)
* **Entries:** [fleet/apps/](../fleet/apps/) — one data file per application.

Cross-host facts (serving host, port, public URL, probe, UDP, module) live
here so Caddy, Prometheus, flake imports, and the app module cannot drift.
The files are data only: no `config` references. Drop
`fleet/apps/<name>.nix`; `config/fleet-apps.nix` imports every file in
that directory. Caddy HTTP vhosts, layer4 UDP, and blackbox targets are
generated from this set. flake.nix imports `module` on `host` plus
`extraHosts`
([adr/2026-09-18-fleet-apps-enable-by-host.md](adr/2026-09-18-fleet-apps-enable-by-host.md)).

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `host` | string | | Inventory hostname that runs the process |
| `port` | port | | Tailnet listen port |
| `unit` | string | attr name | systemd unit without `.service` |
| `docs` | string | | Repo-relative service doc |
| `module` | null or string | `null` | Repo-relative NixOS module; flake imports it on `host`/`extraHosts` |
| `extraHosts` | list of string | `[]` | Extra inventory hosts that also import `module` |
| `dashboard` | null or string | `null` | Grafana dashboard file name |
| `edge` | null or submodule | `null` | Public Caddy HTTP vhost |
| `edge.domain` | string | | Public hostname, no scheme |
| `edge.scheme` | `http` / `https` | `https` | Vhost listener scheme |
| `edge.listenerHost` | string | `xcloud-caddy` | Host that terminates TLS |
| `edge.rateLimit` | preset / null | `standard` | `standard`, `heavy`, `ultraHeavy`, `vaultwarden` |
| `edge.rateLimitZone` | null or string | attr name | Caddy rate_limit zone name |
| `edge.upstream` | `remote` / `loopback` | `remote` | loopback is `127.0.0.1:port` |
| `edge.upstreamTls` | bool | `false` | Dial backend with `https://` |
| `edge.tlsInsecure` | bool | `false` | Skip backend TLS verify |
| `edge.auth` | null / `forward` / `hybrid` | `null` | oauth2-proxy on this vhost |
| `edge.apiBearerBypass` | bool | `false` | With `hybrid`, skip oauth2-proxy for `Authorization: Bearer` on `/api/*` |
| `edge.waf` | bool | `true` | Coraza DetectionOnly |
| `edge.wafExtraDirectives` | lines | `""` | Extra SecRule lines |
| `edge.wafBypassPaths` | list of string | `[]` | URI prefixes that skip Coraza |
| `edge.wafBypassWebsockets` | bool | `false` | Skip Coraza on websocket upgrade |
| `edge.adminCidrPath` | null or string | `null` | Abort unless source is tailnet CGNAT |
| `edge.securityHeaders` | `strict` / `loose` | `strict` | |
| `edge.flushInterval` / `dialTimeout` / `lbTryDuration` / `healthUri` / … | null or value | `null` | Caddy `reverse_proxy` knobs; omitted when null |
| `udp.listenPort` | port | | Caddy layer4 UDP listen port |
| `probe.public` | bool | `false` | Add the public URL to `blackbox_http` |
| `probe.internal` | bool | `false` | Add `http://host:port` to `blackbox_http_internal` |
| `probe.path` | string | `""` | Path on the public URL; empty keeps the bare origin |

Eval-time checks (`make lint` evaluates these; they are not `checks.`
derivations): `host`, `edge.listenerHost`, and `extraHosts` must be in
`fleet.inventory.hosts`; `probe.public` requires `edge`; edge
`scheme://domain` and UDP `listenPort` must be unique; `docs`, `module`,
and `dashboard` paths must exist; `listenerHost` is `xcloud-caddy`;
Keycloak `edge.auth` is null; `edge.apiBearerBypass` requires
`edge.auth = "hybrid"`. Host files must not mention `fleet.apps`,
`fleet.services`, or `virtualHosts`. Deployed substituters must not name
Attic. flake.nix
imports each `module` on `host` plus `extraHosts` only
([adr/2026-09-18-fleet-apps-enable-by-host.md](adr/2026-09-18-fleet-apps-enable-by-host.md),
[adr/2026-09-18-eval-time-guardrails.md](adr/2026-09-18-eval-time-guardrails.md)).

---

## Fleet inventory (`fleet.inventory`)

* **Implementation:** [config/fleet-inventory.nix](../config/fleet-inventory.nix)

`nixosHosts` / `hosts` are the addressable name lists. `deployPausedHosts`
stays inside `nixosHosts` and is not activated (`proxmox-applications-1`,
`proxmox-applications-2`). `nodes.<hostname>` holds `tailscalePort` and
optional `sriovMac`. Prometheus fleet scrape jobs and
`services.tailscale.port` are derived from this. Adding a NixOS host means
adding the name to `nixosHosts` **and** a `nodes` entry.

---

## Cluster gossip address (`fleet.clusterEnv`)

* **Implementation:** [config/cluster-env.nix](../config/cluster-env.nix)

Writes the host's tailscale0 IPv4 into an `EnvironmentFile` before Loki, Mimir, or Alertmanager start.
systemd loads `EnvironmentFile` before `ExecStartPre`, so this cannot be an `ExecStartPre` on the daemon.
How-to: [how-to-dynamic-tailscale.md](how-to-dynamic-tailscale.md).

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `service` | string | | Systemd unit that consumes the file |
| `envFile` | string | `/run/${name}-cluster.env` | Path of the generated EnvironmentFile |
| `ipVariable` | string | | Variable set to the tailscale0 IPv4 |
| `ipSuffix` | string | `""` | Appended (e.g. `:9094`) |
| `extra` | attrs of string | `{}` | Extra `KEY=value` lines |
| `timeoutSec` | int | `60` | Seconds to wait for an address |

---

## iperf3 mesh (`fleet.networkTesting`)

* **Implementation:** [config/network-testing.nix](../config/network-testing.nix)

`enable` turns on the coordinated iperf3 daemon. `config/observability.nix` sets
it on every fleet host. `rpi4` is commented out of the peer list for now
([monitoring.md](monitoring.md)). Dashboard: `fleet-iperf3`.

---

## Garage (`fleet.services.garage`)

* **Implementation:** [services/garage.nix](../services/garage.nix)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | | Garage S3 daemon |
| `dataDir` | string | `/var/lib/garage/data` | NFS mount when `mountNfs`; unused as `data_dir` when `mountIscsi` |
| `mountNfs` | bool | `false` | Leftover TrueNAS NFS + loop image (migrate source) |
| `nfsShare` | string | `truenas-scale:/mnt/ssd/garage/data` | NFS path |
| `mountIscsi` | bool | `false` | iSCSI LUN is `data_dir` and `metadata_dir` |
| `iscsiPortal` | string | `192.168.3.9` | TrueNAS LAN IPv4. Not MagicDNS |
| `iscsiTarget` | string | `iqn.2005-10.org.freenas.ctl:garage` | Target IQN |
| `iscsiMount` | string | `/mnt/iscsi/garage` | ext4 mount of the LUN |
| `iscsiInitiatorName` | string | `iqn.2026-09.za.co.alexmayers:proxmox-observability` | Must match the TrueNAS ACL |
| `iscsiAllowMkfs` | bool | `false` | Opt-in `mkfs.ext4 -F` on an empty LUN; refuse unexpected FS/PT signatures |
| `bootstrapS3` | bool | `false` | Create buckets/keys on this node |
| `loopbackImage` | string | `/mnt/nfs/garage/data/.garage-blocks.img` | Retired image; migrate source |
| `loopbackMount` | string | `/mnt/nfs/garage/data/.blocks-ext4` | Retired loop mount |
| `loopbackImageSize` | string | `100G` | Virtual size of the retired image |

When `mountIscsi` is set, Garage `data_dir` is `/mnt/iscsi/garage/data`
and `metadata_dir` is `/mnt/iscsi/garage/meta`. Portal is LAN
`192.168.3.9:3260`
([garage-iscsi.md](runbooks/garage-iscsi.md)).
Decision: [2026-09-18-garage-iscsi.md](adr/2026-09-18-garage-iscsi.md).

Do not `chown` meta to `garage`. S3 clients use `proxmox-observability:3902`.

---

## Redis (`fleet.services.redis`)

* **Implementation:** [services/redis.nix](../services/redis.nix)

`enable` starts the oauth2-proxy, vikunja, and paperless Redis instances on
`xcloud-postgres`. Passwords are sops files, not Nix strings.

---

## Disko disk path (`fleet.disk.path`)

* **Implementation:** [disko/disk-config.nix](../disko/disk-config.nix)

String path of the boot disk for the shared GPT layout. Hosts set this to the
device Disko should partition.

---

## Shared NFS automount options

* **Implementation:** [config/nfs-mount.nix](../config/nfs-mount.nix)

A function, not a module: `import ../config/nfs-mount.nix "paperless" [ ]`.
Always includes `nconnect=8` and `noatime`. Do not use it for GitLab state
(must not idle-unmount). NFS congestion alerts:
[nfs-congestion.md](runbooks/nfs-congestion.md).
