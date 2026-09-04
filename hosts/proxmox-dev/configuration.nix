{ ... }:
{
  networking.hostName = "proxmox-dev";

  # The one atticd instance that runs background jobs and garbage collection.
  fleet.services.attic.mode = "monolithic";
}
