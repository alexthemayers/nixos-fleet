{
  config,
  pkgs,
  lib,
  ...
}:
{
  services.openarena.enable = true;
  services.openarena.openPorts = true;
  services.openarena.extraFlags = [
    "+set sv_hostname \"Alex's OpenArena\""
    "+map oa_dm1"
  ];

  fileSystems."/mnt/nfs/openarena" = {
    device = "truenas-scale:/mnt/ssd/openarena";
    fsType = "nfs";
    options = [
      "rw"
      "nfsvers=4.2"
      "_netdev"
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=600"
      "x-systemd.requires=wait-for-host-openarena.service"
      "x-systemd.after=wait-for-host-openarena.service"
    ];
  };

  fleet.waitForHost.openarena.host = "truenas-scale";

  systemd.services.openarena = {
    serviceConfig = {
      RequiresMountsFor = [ "/mnt/nfs/openarena" ];
      BindPaths = [ "/mnt/nfs/openarena:/var/lib/openarena" ];
    };
  };
}
