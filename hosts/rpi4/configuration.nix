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
  services.prometheus.alertmanager.clusterPeers = [ "proxmox-observability" ];

  system.stateVersion = "25.11";
}
