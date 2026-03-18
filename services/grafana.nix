{
  config,
  pkgs,
  lib,
  ...
}:
{
  services.grafana = {
    enable = true;
    settings.security.secret_key = "SW2YcwTIb9zpOOhoPsMm";
    openFirewall = true;

    settings.server = {
      protocol = "http";
      http_addr = "0.0.0.0";
      http_port = 3000;

      domain = "grafana.alexmayers.co.za";
      root_url = "https://grafana.alexmayers.co.za/";
    };

    provision = {
      enable = true;
      dashboards.settings.providers = [
        {
          name = "My Flake Dashboards";
          # This copies the local directory into the Nix store and tells Grafana to read from it
          options.path = ./grafana/dashboards;
        }
      ];
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "http://proxmox-observability:9090";
          access = "proxy";
          isDefault = true;
          editable = false;
        }
        {
          name = "Loki";
          type = "loki";
          url = "http://proxmox-observability:3100";
          access = "proxy";
          jsonData.maxLines = 1000;
        }
      ];
    };
  };
}
