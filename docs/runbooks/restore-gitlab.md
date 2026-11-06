# Runbook: restore GitLab

**Status:** documented, **not drill-tested** (2026-08-29).

GitLab state lives on `proxmox-gitlab-debian` in the NFS loop image
`/var/gitlab/state` plus a daily backup tarball rsynced off-host to
`backup-relay@proxmox-dev:/var/backup-relay/gitlab_backups/` on VM 112
(permanent; see [proxmox-dev-debian.md](../services/proxmox-dev-debian.md);
backup target is set in the Debian GitLab role / guest doc).
Restoring the tarball does not replace a Disko reinstall; it reloads GitLab's
own backup into an already-running instance.

Postgres for GitLab is on `xcloud-postgres`. A GitLab backup includes the
database dump GitLab took itself. If you also restore the fleet-wide Postgres
dump from [restore-postgres.md](restore-postgres.md), pick **one** source of
truth for the `gitlab` database or you will load two different catalogs.

## RPO and RTO

- **RPO:** last successful `gitlab-backup` + `gitlab-backup-sync`. The sync
  copies, checksum-verifies, then deletes local tarballs. Same relay
  dependency as Postgres.
- **RTO:** untested. GitLab restore is slow (repositories, artifacts, registry
  metadata). Budget hours, not minutes.

## Restore (outline)

1. Confirm the tarball on `proxmox-dev` (or a copy you pulled off it) is complete.
2. Copy it to `/var/gitlab/state/backup/` on `proxmox-gitlab-debian`
   (VM 102 only if that NixOS disk has been started for rollback).
3. Follow GitLab's restore procedure for the version this flake pins
   (`gitlab-rake gitlab:backup:restore BACKUP=<timestamp>` or the nixos
   equivalent once the backup unit has placed the file). Stop Puma/Sidekiq
   first so nothing writes during the load.
4. Restore `gitlab.rb` / sops secrets from this repo, not from memory. The
   registry cert, `gitlab/secret`, and Active Record keys in
   `secrets/proxmox-gitlab-debian/secrets.yaml` must match the backup.
5. Registry blobs live in the GitLab registry path on the same loop image. If
   that image is gone, the tarball alone does not bring container images back.

## What this does not restore

- The fleet Postgres roles other than GitLab.
- Container-registry pull-through caches on apps-2 (those are disposable).
- CI job logs older than GitLab's own backup retention.
