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
| Observability is one VM | [2026-09-07-observability-monolith](2026-09-07-observability-monolith.md) | [proxmox-observability-debian.md](../services/proxmox-observability-debian.md) |
| Prometheus and Loki keep 62 days on local disk | [2026-11-04-local-metrics-and-logs](2026-11-04-local-metrics-and-logs.md) | [proxmox-observability-debian.md](../services/proxmox-observability-debian.md) |
| Garage is one node on that VM | [2026-09-07-garage-on-obs-1](2026-09-07-garage-on-obs-1.md) | [garage.md](../services/garage.md) |
| VM roots stay on TrueNAS NFS | [2026-09-07-nfs-vm-roots](2026-09-07-nfs-vm-roots.md) | [proxmox-host.md](../services/proxmox-host.md) |
| `xcloud-postgres` is 1 GiB | [2026-09-04-xcloud-postgres-1g](2026-09-04-xcloud-postgres-1g.md) | [postgres.md](../services/postgres.md), [memory.md](../memory.md) |
| Two host lists plus `check-inventory` | [2026-08-29-inventory-check](2026-08-29-inventory-check.md) | [deployments.md](../deployments.md) |
| App enablement is `fleet.apps`, not host files | [2026-09-18-fleet-apps-enable-by-host](2026-09-18-fleet-apps-enable-by-host.md) | [custom-options.md](../custom-options.md) |

## Deploy and CI

Production activation builds on the native builder and `nix copy`s the
closure with `deploy-rs`. Hosts substitute from `cache.nixos.org`. Attic
is removed. GitLab CI is lint/fmt/inventory/ansible-lint only; the
operator deploys. No staging. The NixOS Proxmox guests were removed from
the flake on 2026-11-04.

| Freeze | ADR | Doc |
|--------|-----|-----|
| Decommission Attic; deploy from the builder store | [2026-11-03-decommission-attic](2026-11-03-decommission-attic.md) | [deployments.md](../deployments.md) |
| rpi4 decommissioned; no aarch64-linux NixOS hosts | [2026-11-06-decommission-rpi4](2026-11-06-decommission-rpi4.md) | [deployments.md](../deployments.md) |
| CI is lint only; operator deploys; no staging | [2026-11-05-ci-lint-only](2026-11-05-ci-lint-only.md) | [deployments.md](../deployments.md) |
| Proxmox hypervisor is Ansible; vault stays local | [2026-08-31-proxmox-ansible](2026-08-31-proxmox-ansible.md) | [proxmox-host.md](../services/proxmox-host.md) |
| Debian apps guest is its own Ansible collection | [2026-11-01-debian-applications-guest](2026-11-01-debian-applications-guest.md) | [proxmox-applications-debian.md](../services/proxmox-applications-debian.md) |
| GitLab moves to a Debian guest in that collection | [2026-11-03-debian-gitlab-guest](2026-11-03-debian-gitlab-guest.md) | [proxmox-gitlab-debian.md](../services/proxmox-gitlab-debian.md) |
| One site.yml; `--limit` required; guest-agent vendor snippet | [2026-11-03-debian-guest-merged-playbook](2026-11-03-debian-guest-merged-playbook.md) | [proxmox-applications-debian.md](../services/proxmox-applications-debian.md) |
| Apps on VM 109 are rootless Podman system units | [2026-11-03-debian-guest-rootless-podman](2026-11-03-debian-guest-rootless-podman.md) | [proxmox-applications-debian.md](../services/proxmox-applications-debian.md) |
| Observability moves to a Debian guest in that collection | [2026-11-04-debian-observability-guest](2026-11-04-debian-observability-guest.md) | [proxmox-observability-debian.md](../services/proxmox-observability-debian.md) |
| Observability scrape and alert config is Ansible files | [2026-11-06-observability-config-in-ansible](2026-11-06-observability-config-in-ansible.md) | [proxmox-observability-debian.md](../services/proxmox-observability-debian.md) |
| Ansible guest secrets use inventory paths; alex-only recipients | [2026-11-06-ansible-guest-secrets](2026-11-06-ansible-guest-secrets.md) | [secrets.md](../secrets.md) |
| The builder moves to Debian and keeps the name proxmox-dev | [2026-11-04-debian-dev-guest](2026-11-04-debian-dev-guest.md) | [proxmox-dev-debian.md](../services/proxmox-dev-debian.md) |
| Guests patch nightly and reboot in a slot; hypervisor and TrueNAS update quarterly | [2026-11-04-update-process](2026-11-04-update-process.md) | [updates.md](../runbooks/updates.md) |
| Router reboots on demand from proxmox-dev with a sops password | [2026-11-05-router-reboot](2026-11-05-router-reboot.md) | [router-reboot.md](../runbooks/router-reboot.md) |

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
| Grafana Bearer `/api/*` skips forward-auth | [2026-11-05-grafana-api-bearer-bypass](2026-11-05-grafana-api-bearer-bypass.md) | [grafana.md](../services/grafana.md) |
| Vaultwarden has no edge failover | [2026-09-06-vaultwarden-no-edge-failover](2026-09-06-vaultwarden-no-edge-failover.md) | [vaultwarden.md](../services/vaultwarden.md) |
| Proxmox Administrator is Keycloak | [2026-09-07-proxmox-openid-admin](2026-09-07-proxmox-openid-admin.md) | [proxmox-host.md](../services/proxmox-host.md) |

## Garage

| Freeze | ADR | Doc |
|--------|-----|-----|
| Metadata is LMDB (`db.lmdb`) | [2026-09-05-garage-lmdb-migration](2026-09-05-garage-lmdb-migration.md) | [garage-lmdb.md](../runbooks/garage-lmdb.md) |
| Blocks and meta are iSCSI ext4 | [2026-09-18-garage-iscsi](2026-09-18-garage-iscsi.md) | [garage-iscsi.md](../runbooks/garage-iscsi.md) |

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
| Jellyfin XML config is declarative (now Ansible files) | [2026-09-04-jellyfin-declarative-config](2026-09-04-jellyfin-declarative-config.md) | [jellyfin.md](../services/jellyfin.md) |
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
| Eval fails closed on registry and freeze regressions | [2026-09-18-eval-time-guardrails](2026-09-18-eval-time-guardrails.md) | [custom-options.md](../custom-options.md) |

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
