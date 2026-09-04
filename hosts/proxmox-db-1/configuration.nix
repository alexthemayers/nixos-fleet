{ ... }:
{
  networking.hostName = "proxmox-db-1";

  fleet.services.garage = {
    enable = true;
    dataDir = "/mnt/nfs/garage/data";
    mountNfs = true;
    nfsShare = "truenas-scale:/mnt/ssd/garage/data";
    bootstrapS3 = true;
  };
}
