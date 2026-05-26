{ config, pkgs, ... }:

{
  fileSystems."/mnt/usb-backup" = {
    device = "/dev/disk/by-uuid/463ab1af-2441-4f02-99e5-03286fe54aba";
    fsType = "ext4";
    options = [
      "defaults"
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
  };
  systemd.tmpfiles.rules = [
    "d /mnt/usb-backup/postgres_backups 0755 alex users 30d"
    "d /mnt/usb-backup/gitlab_backups 0755 alex users 14d"
  ];
  users.users.alex.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIJAdeXwPDMiXhIbG8y4RwEiuIcHKsk2N08DC6KA85qQ postgres@xcloud-postgres"
  ];
}
