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

  environment.systemPackages = with pkgs; [
    btop
  ];

  networking.hostName = "proxmox-observability";
  systemd.network.links."10-sriov" = {
    matchConfig.Driver = "iavf";
    linkConfig = {
      MACAddress = "82:cc:a5:22:e5:03";
    };
  };
  services.tailscale.port = lib.mkForce 41648;
  services.prometheus.alertmanager.clusterPeers = [ "rpi4" ];

  system.stateVersion = "25.11";

  fleet.disk.path = "/dev/sda";
}
