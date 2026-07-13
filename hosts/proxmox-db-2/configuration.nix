{
  modulesPath,
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    # Include the results of the hardware scan.
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
  ];
  # Bootloader.
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  services.qemuGuest.enable = true;

  networking.hostName = "proxmox-db-2";
  systemd.network.links."10-sriov" = {
    matchConfig.Driver = "iavf";
    linkConfig = {
      MACAddress = "82:cc:a5:22:e5:06";
    };
  };
  services.tailscale.port = lib.mkForce 41648;

  boot.kernelPackages = pkgs.linuxPackages_xanmod_latest;
  system.stateVersion = "25.11";

  fleet.disk.path = "/dev/sda";
  fleet.services.garage = {
    enable = true;
    dataDir = "/mnt/nfs/garage/data";
    mountNfs = true;
    nfsShare = "truenas-scale:/mnt/ssd/garage/data-replica-1";
    bootstrapS3 = false;
  };
}
