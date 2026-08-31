{ ... }:
{
  networking.hostName = "proxmox-observability-2";
  services.prometheus.alertmanager.clusterPeers = [
    "proxmox-observability-1.bee-phrygian.ts.net"
  ];
}
