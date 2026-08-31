{
  modulesPath,
  config,
  lib,
  pkgs,
  ...
}:
let
  node = config.fleet.inventory.nodes.${config.networking.hostName} or { };
in
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  services.qemuGuest.enable = true;
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_xanmod_latest;
  system.stateVersion = "25.11";
  fleet.disk.path = lib.mkDefault "/dev/sda";

  systemd.network.links."10-sriov" = lib.mkIf (node ? sriovMac && node.sriovMac != null) {
    matchConfig.Driver = "iavf";
    linkConfig.MACAddress = node.sriovMac;
  };
}
