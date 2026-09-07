{ ... }:
{
  # TEMPORARY: interim landing zone for Postgres and GitLab backups while
  # rpi4 is offline (since 2026-09-06). See
  # docs/runbooks/fleet-simplification-migration.md, Step 2. Delete this file
  # once rpi4 is back and services/postgres.nix / services/gitlab.nix have
  # reverted their rsync targets.
  #
  # Same shared "ssh_backup" keypair used to push to rpi4 today
  # (services/postgres.nix, services/gitlab.nix); the public half is
  # authorized here too so no new secret is needed for this reroute.
  systemd.tmpfiles.rules = [
    "d /var/backup-relay 0750 backup-relay users -"
    "d /var/backup-relay/postgres_backups 0755 backup-relay users 30d"
    "d /var/backup-relay/gitlab_backups 0755 backup-relay users 14d"
  ];
  users.users.backup-relay = {
    isSystemUser = true;
    group = "users";
    home = "/var/backup-relay";
    createHome = false;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIJAdeXwPDMiXhIbG8y4RwEiuIcHKsk2N08DC6KA85qQ postgres@xcloud-postgres"
    ];
  };
}
