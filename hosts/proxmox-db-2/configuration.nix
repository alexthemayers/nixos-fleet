{ ... }:
{
  networking.hostName = "proxmox-db-2";

  fleet.services.garage = {
    enable = true;
    dataDir = "/mnt/nfs/garage/data";
    mountNfs = true;
    nfsShare = "truenas-scale:/mnt/ssd/garage/data-replica-1";
    bootstrapS3 = false;
  };
}
