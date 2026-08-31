{ pkgs, config, ... }:
{
  sops.secrets."tailscale/exporter_env" = {
    restartUnits = [ "prometheus-tailscale-exporter.service" ];
  };
  services.prometheus.exporters.tailscale = {
    enable = true;
    user = "tailscale-exporter";
    environmentFile = config.sops.secrets."tailscale/exporter_env".path;
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    9250 # tailscale exporter
  ];
}
