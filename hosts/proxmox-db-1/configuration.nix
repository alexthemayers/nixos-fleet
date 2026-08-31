{ ... }:
{
  networking.hostName = "proxmox-db-1";

  # The one atticd instance that runs background jobs and garbage collection.
  fleet.services.attic.mode = "monolithic";

  fleet.services.garage = {
    enable = true;
    dataDir = "/mnt/nfs/garage/data";
    mountNfs = true;
    nfsShare = "truenas-scale:/mnt/ssd/garage/data";
    bootstrapS3 = true;
  };
}
