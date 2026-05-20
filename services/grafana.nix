{
  config,
  pkgs,
  lib,
  ...
}:
{
  sops.secrets."grafana/admin_password" = {
    owner = "grafana";
  };
  sops.secrets."grafana/secret_key" = {
    owner = "grafana";
  };
  sops.secrets."postgres/grafana_password" = {
    owner = "grafana";
  };

  services.grafana = {
    enable = true;

    settings = {
      server = {
        protocol = "http";
        http_addr = "0.0.0.0";
        http_port = 3000;

        domain = "grafana.alexmayers.co.za";
        root_url = "https://grafana.alexmayers.co.za/";
      };
      database = {
        type = "postgres";
        user = "grafana";
        name = "grafana";
        password = "$__file{${config.sops.secrets."postgres/grafana_password".path}}";
        host = "xcloud-postgres";
        port = 5432;
        ssl_mode = "disable";
      };
      security = {
        admin_email = "a.mayers102@gmail.com";
        admin_password = "$__file{${config.sops.secrets."grafana/admin_password".path}}";
        admin_user = "admin";
        secret_key = "$__file{${config.sops.secrets."grafana/secret_key".path}}";
      };
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
