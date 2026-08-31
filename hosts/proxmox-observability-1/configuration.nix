{ ... }:
{
  networking.hostName = "proxmox-observability-1";
  # The nixpkgs module appends :9094 itself.
  services.prometheus.alertmanager.clusterPeers = [
    "proxmox-observability-2.bee-phrygian.ts.net"
  ];
}
