# Architecture Decision Records

Decisions live here. [fleet-audit.md](../fleet-audit.md) is the investigation
log that produced many of them; it is not the operational source of truth.

| Date | ADR |
|------|-----|
| 2026-09-04 | [Jellyfin access is Keycloak group membership](2026-09-04-jellyfin-sso-groups.md) |
| 2026-09-04 | [Jellyfin XML config is Nix-managed](2026-09-04-jellyfin-declarative-config.md) |
| 2026-09-04 | [xcloud-postgres sized for 1 GiB RAM](2026-09-04-xcloud-postgres-1g.md) |
| 2026-09-04 | [ntfy JSON integer priority; single writer](2026-09-04-ntfy-json-priority-single-writer.md) |
| 2026-09-01 | [Desktops stay out of packet-loss alerts](2026-09-01-workstation-probe-alerts.md) |
| 2026-08-31 | [GitLab CI image, skip-switch, narinfo verify](2026-08-31-gitlab-ci-pipeline.md) |
| 2026-08-31 | [Jellyfin transcode throttling stays on](2026-08-31-jellyfin-transcode-throttle.md) |
| 2026-08-31 | [rpi4 fill and deploy run on the Pi](2026-08-31-rpi4-native-build.md) |
| 2026-08-31 | [Proxmox hypervisor is Ansible; vault stays local](2026-08-31-proxmox-ansible.md) |
| 2026-08-29 | [Four hubs as accepted SPOFs](2026-08-29-four-hubs.md) |
| 2026-08-30 | [Garage S3 clients use the LB; fix the cluster](2026-08-30-garage-s3-lb.md) |
| 2026-08-30 | [Mimir S3 goes to db-1, not the LB](2026-08-30-mimir-s3-db-1.md) (superseded) |
| 2026-08-30 | [Garage LMDB, parallel Attic uploads](2026-08-30-garage-lmdb.md) |
| 2026-08-30 | [Fill Attic, then deploy exclusively from it](2026-08-30-attic-fill-then-exclusive.md) |
| 2026-08-29 | [Deploy from Attic, then switch](2026-08-29-attic-deploy.md) |
| 2026-08-29 | [Substituters: builders vs deployed hosts](2026-08-29-substituters.md) |
| 2026-08-29 | [Attic is tailnet HTTP and a deploy SPOF](2026-08-29-attic-tailnet.md) |
| 2026-08-29 | [WAF DetectionOnly](2026-08-29-waf-detection-only.md) |
| 2026-08-29 | [oauth2-proxy is not fleet-wide](2026-08-29-oauth2-proxy-coverage.md) |
| 2026-08-29 | [Keycloak master realm and admin CIDR](2026-08-29-keycloak-master.md) |
| 2026-08-29 | [GitLab is CI of record](2026-08-29-gitlab-ci-of-record.md) |
| 2026-08-29 | [No staging; merge to main deploys](2026-08-29-no-staging.md) |
| 2026-08-29 | [Inventory duplication plus check-inventory](2026-08-29-inventory-check.md) |
| 2026-08-29 | [One Attic monolithic node](2026-08-29-attic-monolithic.md) |
