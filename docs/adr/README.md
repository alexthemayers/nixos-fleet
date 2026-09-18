# Decision records

Decisions live here in [MADR 3.0.0](https://adr.github.io/madr/) form.
New records copy [adr-template.md](adr-template.md) to
`YYYY-MM-DD-slug.md` and get a row in the matching topic below. Why this
layout: [2026-09-06-use-madr.md](2026-09-06-use-madr.md). Why the index
is by topic:
[2026-09-18-adr-topic-index.md](2026-09-18-adr-topic-index.md). How to
tag claims: [how-to-audit.md](../how-to-audit.md).

Read the topic row for what is true. Open the ADR for why. Operate from
the service or runbook link. Live docs cite the governing accepted ADR,
not a superseded file.

## Topology

Three hubs are SPOFs (`xcloud-caddy`, `xcloud-postgres`,
`truenas-scale`). Edge and east-west clients talk to the serving VM.
There is no internal load balancer.

| Freeze | ADR | Doc |
|--------|-----|-----|
| No internal LB; one Keycloak and one Vikunja on apps-1 | [2026-09-07-no-internal-lb](2026-09-07-no-internal-lb.md) | [how-to-reverse-proxy.md](../how-to-reverse-proxy.md) |
| Observability is one VM | [2026-09-07-observability-monolith](2026-09-07-observability-monolith.md) | [monitoring.md](../monitoring.md) |
| Garage is one node on that VM | [2026-09-07-garage-on-obs-1](2026-09-07-garage-on-obs-1.md) | [garage.md](../services/garage.md) |
| VM roots stay on TrueNAS NFS | [2026-09-07-nfs-vm-roots](2026-09-07-nfs-vm-roots.md) | [proxmox-host.md](../services/proxmox-host.md) |
| `xcloud-postgres` is 1 GiB | [2026-09-04-xcloud-postgres-1g](2026-09-04-xcloud-postgres-1g.md) | [postgres.md](../services/postgres.md), [memory.md](../memory.md) |
| Two host lists plus `check-inventory` | [2026-08-29-inventory-check](2026-08-29-inventory-check.md) | [deployments.md](../deployments.md) |
| App enablement is `fleet.apps`, not host files | [2026-09-18-fleet-apps-enable-by-host](2026-09-18-fleet-apps-enable-by-host.md) | [custom-options.md](../custom-options.md) |

## Attic, deploy, CI

Fill Attic (public substituters only if a NAR is missing), then copy and
switch from Attic only. One monolithic node on `proxmox-dev`. Merge to
`main` deploys. GitLab is CI of record.

| Freeze | ADR | Doc |
|--------|-----|-----|
| One Attic `monolithic` node | [2026-08-29-attic-monolithic](2026-08-29-attic-monolithic.md) | [attic.md](../services/attic.md) |
| That node is `proxmox-dev` | [2026-09-04-attic-on-proxmox-dev](2026-09-04-attic-on-proxmox-dev.md) | [attic.md](../services/attic.md) |
| Attic is tailnet HTTP and a deploy SPOF | [2026-08-29-attic-tailnet](2026-08-29-attic-tailnet.md) | [attic.md](../services/attic.md) |
| Fill, then exclusive from Attic | [2026-08-30-attic-fill-then-exclusive](2026-08-30-attic-fill-then-exclusive.md) | [deployments.md](../deployments.md) |
| Copy from Attic, then switch | [2026-08-29-attic-deploy](2026-08-29-attic-deploy.md) | [deployments.md](../deployments.md) |
| Substituters: builders vs deployed hosts | [2026-08-29-substituters](2026-08-29-substituters.md) | [deployments.md](../deployments.md) |
| rpi4 fill and deploy run on the Pi | [2026-08-31-rpi4-native-build](2026-08-31-rpi4-native-build.md) | [rpi4.md](../hosts/rpi4.md) |
| GitLab is CI of record | [2026-08-29-gitlab-ci-of-record](2026-08-29-gitlab-ci-of-record.md) | [deployments.md](../deployments.md) |
| GitLab image, skip-switch, narinfo verify | [2026-08-31-gitlab-ci-pipeline](2026-08-31-gitlab-ci-pipeline.md) | [gitlab-runner.md](../services/gitlab-runner.md) |
| Deploy only hosts whose toplevel changed | [2026-09-08-incremental-gitlab-deploys](2026-09-08-incremental-gitlab-deploys.md) | [deployments.md](../deployments.md) |
| No staging; merge to `main` deploys | [2026-08-29-no-staging](2026-08-29-no-staging.md) | [deployments.md](../deployments.md) |
| Proxmox hypervisor is Ansible; vault stays local | [2026-08-31-proxmox-ansible](2026-08-31-proxmox-ansible.md) | [proxmox-host.md](../services/proxmox-host.md) |

## Edge and auth

WAF is DetectionOnly. oauth2-proxy is per-vhost. Keycloak `/admin` is
tailnet CIDR at the edge.

| Freeze | ADR | Doc |
|--------|-----|-----|
| WAF DetectionOnly | [2026-08-29-waf-detection-only](2026-08-29-waf-detection-only.md) | [caddy.md](../services/caddy.md) |
| oauth2-proxy is not fleet-wide | [2026-08-29-oauth2-proxy-coverage](2026-08-29-oauth2-proxy-coverage.md) | [oauth2-proxy.md](../services/oauth2-proxy.md) |
| Keycloak master realm and admin CIDR | [2026-08-29-keycloak-master](2026-08-29-keycloak-master.md) | [keycloak.md](../services/keycloak.md) |
| Jellyfin access is Keycloak groups | [2026-09-04-jellyfin-sso-groups](2026-09-04-jellyfin-sso-groups.md) | [jellyfin.md](../services/jellyfin.md) |
| Grafana access is Keycloak groups | [2026-09-07-grafana-sso-groups](2026-09-07-grafana-sso-groups.md) | [grafana.md](../services/grafana.md) |
| Vaultwarden has no edge failover to rpi4 | [2026-09-06-vaultwarden-no-edge-failover](2026-09-06-vaultwarden-no-edge-failover.md) | [vaultwarden.md](../services/vaultwarden.md) |
| Proxmox Administrator is Keycloak | [2026-09-07-proxmox-openid-admin](2026-09-07-proxmox-openid-admin.md) | [proxmox-host.md](../services/proxmox-host.md) |

## Garage

| Freeze | ADR | Doc |
|--------|-----|-----|
| Metadata is LMDB (`db.lmdb`) | [2026-09-05-garage-lmdb-migration](2026-09-05-garage-lmdb-migration.md) | [garage-lmdb.md](../runbooks/garage-lmdb.md) |

Single-node placement is under Topology.

## Observability

| Freeze | ADR | Doc |
|--------|-----|-----|
| Journal shipping is Vector, not Alloy | [2026-09-08-vector-replaces-alloy](2026-09-08-vector-replaces-alloy.md) | [monitoring.md](../monitoring.md) |
| Mimir series: cut cardinality, then raise the cap | [2026-09-05-mimir-series-headroom](2026-09-05-mimir-series-headroom.md) | [mimir.md](../services/mimir.md) |
| Delete Mimir ULIDs with no Garage blocks | [2026-09-05-mimir-delete-lost-blocks](2026-09-05-mimir-delete-lost-blocks.md) | [garage-metadata-resync.md](../runbooks/garage-metadata-resync.md) |
| ntfy JSON integer priority; one writer | [2026-09-04-ntfy-json-priority-single-writer](2026-09-04-ntfy-json-priority-single-writer.md) | [ntfy.md](../services/ntfy.md) |
| Blackbox prober is on `proxmox-observability` | [2026-09-06-blackbox-on-obs-1](2026-09-06-blackbox-on-obs-1.md) | [blackbox-exporter.md](../services/blackbox-exporter.md) |
| iperf3 mesh is on for every fleet host | [2026-09-06-iperf3-mesh-on](2026-09-06-iperf3-mesh-on.md) | [monitoring.md](../monitoring.md) |
| Desktops stay out of packet-loss alerts | [2026-09-01-workstation-probe-alerts](2026-09-01-workstation-probe-alerts.md) | [tailscale.md](../services/tailscale.md) |
| Hardware, VFIO, SR-IOV, GPU series | [2026-09-07-hardware-and-vfio-monitoring](2026-09-07-hardware-and-vfio-monitoring.md) | [proxmox-host.md](../services/proxmox-host.md) |

## Media

| Freeze | ADR | Doc |
|--------|-----|-----|
| Radarr and Sonarr own Movies/Shows acquisition | [2026-09-09-arr-stack-acquisition](2026-09-09-arr-stack-acquisition.md) | [media-automation.md](../services/media-automation.md) |
| *arr write Movies/Shows NFO and refresh Jellyfin | [2026-09-11-arr-writes-nfo-and-refreshes-jellyfin](2026-09-11-arr-writes-nfo-and-refreshes-jellyfin.md) | [jellyfin.md](../services/jellyfin.md) |
| Bazarr writes external `.srt` for Movies and Shows | [2026-09-11-bazarr-external-subs](2026-09-11-bazarr-external-subs.md) | [media-automation.md](../services/media-automation.md) |
| Jellyfin XML config is Nix-managed | [2026-09-04-jellyfin-declarative-config](2026-09-04-jellyfin-declarative-config.md) | [jellyfin.md](../services/jellyfin.md) |
| Jellyfin transcode throttling stays on | [2026-08-31-jellyfin-transcode-throttle](2026-08-31-jellyfin-transcode-throttle.md) | [jellyfin.md](../services/jellyfin.md) |

Anime and Documentaries still use sidecar NFO as the durable ID; that
contract is in [jellyfin.md](../services/jellyfin.md) and
[jellyfin-metadata.md](../runbooks/jellyfin-metadata.md).

## Process

| Freeze | ADR | Doc |
|--------|-----|-----|
| Agent instruction lives in Cursor rules | [2026-09-04-cursor-rules-over-agents-md](2026-09-04-cursor-rules-over-agents-md.md) | [AGENTS.md](../../AGENTS.md) |
| Use MADR 3.0; keep `YYYY-MM-DD-slug.md` | [2026-09-06-use-madr](2026-09-06-use-madr.md) | [adr-template.md](adr-template.md) |
| Topic index is the current-decision map | [2026-09-18-adr-topic-index](2026-09-18-adr-topic-index.md) | this file |

## History (superseded)

Do not cite these from live docs. The replacing ADR is the governing
record.

| Date | Replaced by | ADR |
|------|-------------|-----|
| 2026-08-29 | [no-internal-lb](2026-09-07-no-internal-lb.md) | [Four hubs as accepted SPOFs](2026-08-29-four-hubs.md) |
| 2026-08-30 | [no-internal-lb](2026-09-07-no-internal-lb.md) | [Garage S3 clients use the LB](2026-08-30-garage-s3-lb.md) |
| 2026-08-30 | [garage-s3-lb](2026-08-30-garage-s3-lb.md) then no-internal-lb | [Mimir S3 goes to db-1](2026-08-30-mimir-s3-db-1.md) |
| 2026-08-30 | [garage-lmdb-migration](2026-09-05-garage-lmdb-migration.md) | [Garage LMDB, parallel Attic uploads](2026-08-30-garage-lmdb.md) |
| 2026-09-08 | [vector-replaces-alloy](2026-09-08-vector-replaces-alloy.md) | [Alloy on xcloud-postgres is MemoryMax 384M](2026-09-08-xcloud-postgres-alloy-cap.md) |
| 2026-09-08 | [arr-stack-acquisition](2026-09-09-arr-stack-acquisition.md) | [Jellyfin identification lives in sidecar NFO](2026-09-08-jellyfin-sidecar-nfo.md) |
