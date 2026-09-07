# Decision records

Decisions live here in [MADR 3.0.0](https://adr.github.io/madr/) form.
New records copy [adr-template.md](adr-template.md) to
`YYYY-MM-DD-slug.md`. Why this layout:
[2026-09-06-use-madr.md](2026-09-06-use-madr.md).

[fleet-audit.md](../fleet-audit.md) is the investigation log that produced
many of them; it is not the operational source of truth.

| Date | Status | ADR |
|------|--------|-----|
| 2026-09-07 | accepted | [Proxmox Administrator is alex.mayers@Keycloak](2026-09-07-proxmox-openid-admin.md) |
| 2026-09-07 | accepted | [VM root disks stay on TrueNAS NFS](2026-09-07-nfs-vm-roots.md) |
| 2026-09-07 | accepted | [Grafana access is Keycloak group membership](2026-09-07-grafana-sso-groups.md) |
| 2026-09-07 | accepted | [No internal load balancer; edge talks to the serving VM](2026-09-07-no-internal-lb.md) |
| 2026-09-07 | accepted | [Garage is a single node on proxmox-observability](2026-09-07-garage-on-obs-1.md) |
| 2026-09-07 | accepted | [Observability is one VM, not a pair](2026-09-07-observability-monolith.md) |
| 2026-09-07 | accepted | [Hardware, VFIO, SR-IOV, and GPU Passthrough Observability](2026-09-07-hardware-and-vfio-monitoring.md) |
| 2026-09-06 | accepted | [Use Markdown Any Decision Records 3.0](2026-09-06-use-madr.md) |
| 2026-09-06 | accepted | [Vaultwarden has no edge failover to rpi4](2026-09-06-vaultwarden-no-edge-failover.md) |
| 2026-09-06 | accepted | [Blackbox prober lives on proxmox-observability](2026-09-06-blackbox-on-obs-1.md) |
| 2026-09-06 | accepted | [iperf3 throughput mesh is on for every fleet host](2026-09-06-iperf3-mesh-on.md) |
| 2026-09-05 | accepted | [Delete Mimir ULIDs with no remaining Garage blocks](2026-09-05-mimir-delete-lost-blocks.md) |
| 2026-09-05 | accepted | [Mimir series headroom: cardinality, then cap](2026-09-05-mimir-series-headroom.md) |
| 2026-09-05 | accepted | [Garage metadata moves to LMDB](2026-09-05-garage-lmdb-migration.md) |
| 2026-09-04 | accepted | [Attic stack runs on proxmox-dev](2026-09-04-attic-on-proxmox-dev.md) |
| 2026-09-04 | accepted | [Jellyfin access is Keycloak group membership](2026-09-04-jellyfin-sso-groups.md) |
| 2026-09-04 | accepted | [Jellyfin XML config is Nix-managed](2026-09-04-jellyfin-declarative-config.md) |
| 2026-09-04 | accepted | [xcloud-postgres sized for 1 GiB RAM](2026-09-04-xcloud-postgres-1g.md) |
| 2026-09-04 | accepted | [ntfy JSON integer priority; single writer](2026-09-04-ntfy-json-priority-single-writer.md) |
| 2026-09-04 | accepted | [Agent instruction lives in Cursor rules](2026-09-04-cursor-rules-over-agents-md.md) |
| 2026-09-01 | accepted | [Desktops stay out of packet-loss alerts](2026-09-01-workstation-probe-alerts.md) |
| 2026-08-31 | accepted | [GitLab CI image, skip-switch, narinfo verify](2026-08-31-gitlab-ci-pipeline.md) |
| 2026-08-31 | accepted | [Jellyfin transcode throttling stays on](2026-08-31-jellyfin-transcode-throttle.md) |
| 2026-08-31 | accepted | [rpi4 fill and deploy run on the Pi](2026-08-31-rpi4-native-build.md) |
| 2026-08-31 | accepted | [Proxmox hypervisor is Ansible; vault stays local](2026-08-31-proxmox-ansible.md) |
| 2026-08-29 | superseded | [Four hubs as accepted SPOFs](2026-08-29-four-hubs.md) |
| 2026-08-30 | superseded | [Garage S3 clients use the LB; fix the cluster](2026-08-30-garage-s3-lb.md) |
| 2026-08-30 | superseded | [Mimir S3 goes to db-1, not the LB](2026-08-30-mimir-s3-db-1.md) |
| 2026-08-30 | superseded | [Garage LMDB, parallel Attic uploads](2026-08-30-garage-lmdb.md) |
| 2026-08-30 | accepted | [Fill Attic, then deploy exclusively from it](2026-08-30-attic-fill-then-exclusive.md) |
| 2026-08-29 | accepted | [Deploy from Attic, then switch](2026-08-29-attic-deploy.md) |
| 2026-08-29 | accepted | [Substituters: builders vs deployed hosts](2026-08-29-substituters.md) |
| 2026-08-29 | accepted | [Attic is tailnet HTTP and a deploy SPOF](2026-08-29-attic-tailnet.md) |
| 2026-08-29 | accepted | [WAF DetectionOnly](2026-08-29-waf-detection-only.md) |
| 2026-08-29 | accepted | [oauth2-proxy is not fleet-wide](2026-08-29-oauth2-proxy-coverage.md) |
| 2026-08-29 | accepted | [Keycloak master realm and admin CIDR](2026-08-29-keycloak-master.md) |
| 2026-08-29 | accepted | [GitLab is CI of record](2026-08-29-gitlab-ci-of-record.md) |
| 2026-08-29 | accepted | [No staging; merge to main deploys](2026-08-29-no-staging.md) |
| 2026-08-29 | accepted | [Inventory duplication plus check-inventory](2026-08-29-inventory-check.md) |
| 2026-08-29 | accepted | [One Attic monolithic node](2026-08-29-attic-monolithic.md) |
