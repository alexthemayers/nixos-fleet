# Codebase deviations

This list used to be two unchecked boxes that were already the wrong picture of
the fleet (Keycloak `initialAdminPassword`, and two hand-rolled NFS wait loops).
Keep it short and true. Topology and product freezes live in
[adr/](adr/README.md) (topic index). How to tag claims: [how-to-audit.md](how-to-audit.md).

## Closed

- **Keycloak `initialAdminPassword = "admin"`** — gone. Bootstrap admin password
  comes from sops; `/admin*` on the identity vhost is gated to the tailnet.
- **Jellyfin / Actual Budget wait loops** — both mounts now use
  `fleet.waitForHost` (`wait-for-host-jellyfin`, `wait-for-host-actualbudget`),
  the same pattern as Paperless, Immich, Luanti, OpenArena, and GitLab.
- **`postgresqlBackup` verify file in `/run`** — fixed. `postStart` runs as
  `postgres` and cannot create `/run/postgresql-backup-verify.txt`, so the
  redirect failed and the unit exited 1 every night from 2026-08-26 on. The
  dumps still reached the off-host target; what never ran was the
  `find -delete` after it,
  so `/var/backup/postgresql` grew to 3.3G and filled the root disk to 86%.
  Now `RuntimeDirectory=postgresql-backup` and the scratch file is
  `$RUNTIME_DIRECTORY/verify.txt`. See [services/postgres.md](services/postgres.md).
- **Prometheus kept running stale config and rules** — the observability role
  notified a `/-/reload` handler, but `prometheus.yml` and `rules.yaml` are
  bind-mounted as single files and `copy` writes a new inode, so the container
  never saw the update (still scraping `rpi4`, still on the pre-merge rules).
  Found on 2026-11-06 by comparing the container's inode and `rpi4` in
  `/api/v1/status/config`. The handler now restarts the unit;
  `test_check_prometheus_scrapes.py` fails if a reload handler returns.
- **Grafana dashboard prune used `copy: delete: true`** — `delete` is a
  `synchronize` option, so the observability role failed on the first real
  deploy while `ansible-lint --offline`, `--syntax-check` and `--check` all
  passed. The role now installs with `copy` and prunes by difference (`find`
  plus `file: absent`, guarded against an empty list), which also removes
  the stale Garage and Mimir dashboards. `scripts/check-ansible-module-args.py`
  checks every task argument against `ansible-doc` in `make ansible-lint`.

## Still a deviation (on purpose, for now)

Nothing in this file. Remaining High items that are product or topology
decisions (WAF DetectionOnly, oauth2-proxy coverage, Keycloak `realms/master`,
three hubs) are ADRs under [adr/](adr/README.md), not coding-standard slips.
