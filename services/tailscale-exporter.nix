{ pkgs, config, ... }:
{
  sops.secrets."tailscale/exporter_env" = { };
  services.prometheus.exporters.tailscale = {
    enable = true;
    user = "tailscale-exporter";
    environmentFile = config.sops.secrets."tailscale/exporter_env".path;
  };
}
