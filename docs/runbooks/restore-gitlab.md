# Runbook: restore GitLab

**Status:** documented, **not drill-tested** (2026-08-29).

GitLab state lives on `proxmox-applications-2` in the NFS loop image
`/var/gitlab/state` plus a daily backup tarball rsynced off-host to
`rpi4:/mnt/usb-backup/gitlab_backups/` — **temporarily**
`proxmox-dev:/var/backup-relay/gitlab_backups/` while `rpi4` is offline (since
2026-09-07, see
[`fleet-simplification-migration.md`](fleet-simplification-migration.md) Step
2; `services/gitlab.nix` has the live target in a `backupTarget` let-binding).
Restoring the tarball does not replace a Disko reinstall; it reloads GitLab's
own backup into an already-running instance.

Postgres for GitLab is on `xcloud-postgres`. A GitLab backup includes the
database dump GitLab took itself. If you also restore the fleet-wide Postgres
dump from [restore-postgres.md](restore-postgres.md), pick **one** source of
truth for the `gitlab` database or you will load two different catalogs.

## RPO and RTO

- **RPO:** last successful `gitlab-backup` + `gitlab-backup-sync`. The sync
  copies, checksum-verifies, then deletes local tarballs. Same Pi dependency as
  Postgres.
- **RTO:** untested. GitLab restore is slow (repositories, artifacts, registry
  metadata). Budget hours, not minutes.

## Restore (outline)

1. Confirm the tarball on the Pi (or a copy you pulled off it) is complete.
2. Copy it to `/var/gitlab/state/backup/` on `proxmox-applications-2`.
3. Follow GitLab's restore procedure for the version this flake pins
   (`gitlab-rake gitlab:backup:restore BACKUP=<timestamp>` or the nixos
   equivalent once the backup unit has placed the file). Stop Puma/Sidekiq
   first so nothing writes during the load.
4. Restore `gitlab.rb` / sops secrets from this repo, not from memory. The
   registry cert, `gitlab/secret`, and Active Record keys in
   `secrets/proxmox-applications-2/secrets.yaml` must match the backup.
5. Registry blobs live in the GitLab registry path on the same loop image. If
   that image is gone, the tarball alone does not bring container images back.

## What this does not restore

- The fleet Postgres roles other than GitLab.
- Container-registry pull-through caches on apps-2 (those are disposable).
- CI job logs older than GitLab's own backup retention.
