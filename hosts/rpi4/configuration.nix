{
  modulesPath,
  config,
  lib,
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    btop
  ];

  networking.hostName = "rpi4";
  services.tailscale.port = lib.mkForce 41647;
  services.prometheus.alertmanager.clusterPeers = [
    "proxmox-observability-1.bee-phrygian.ts.net:9094"
    "proxmox-observability-2.bee-phrygian.ts.net:9094"
  ];

  system.stateVersion = "25.11";

  fleet.services.garage = {
    enable = true;
    dataDir = "/mnt/usb-backup/garage/data";
  };
}
