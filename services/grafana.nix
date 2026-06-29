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
  sops.secrets."grafana/oauth_secret" = {
    owner = "grafana";
  };

  services.grafana = {
    enable = true;

    settings = {
      "auth.generic_oauth" = {
        enabled = true;
        name = "Keycloak-OAuth";
        allow_sign_up = true;
        use_pkce = true;
        client_id = "grafana";
        client_secret = "$__file{${config.sops.secrets."grafana/oauth_secret".path}}";

        scopes = "openid email profile offline_access";

        email_attribute_path = "email";
        login_attribute_path = "preferred_username";
        name_attribute_path = "name";

        auth_url = "https://identity.alexmayers.co.za/realms/master/protocol/openid-connect/auth";
        token_url = "https://identity.alexmayers.co.za/realms/master/protocol/openid-connect/token";
        api_url = "https://identity.alexmayers.co.za/realms/master/protocol/openid-connect/userinfo";

        allow_assign_grafana_admin = true;
        role_attribute_path = "email == 'a.mayers102@gmail.com' && 'GrafanaAdmin' || 'Viewer'";
      };
      server = {
        protocol = "http";
        http_addr = "0.0.0.0";
        http_port = 3000;

        domain = "grafana.alexmayers.co.za";
        root_url = "https://grafana.alexmayers.co.za/";
      };
      database = {
        type = "postgres";
        url = "postgres://grafana:$__file{${
          config.sops.secrets."postgres/grafana_password".path
        }}@xcloud-postgres:5432/grafana?sslmode=disable&binary_parameters=yes";
        max_open_conn = 5;
        max_idle_conn = 5;
      };
      security = {
        admin_email = "a.mayers102@gmail.com";
        admin_password = "$__file{${config.sops.secrets."grafana/admin_password".path}}";
        admin_user = "admin";
        secret_key = "$__file{${config.sops.secrets."grafana/secret_key".path}}";
      };
      log = {
        mode = "console";
      };
      "log.console" = {
        format = "json";
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
          url = "http://localhost:9009/prometheus";
          access = "proxy";
          isDefault = true;
          editable = false;
        }
        {
          name = "Loki";
          type = "loki";
          url = "http://localhost:3100";
          access = "proxy";
          jsonData.maxLines = 1000;
        }
        {
          name = "Alertmanager";
          type = "alertmanager";
          url = "http://localhost:9093";
          jsonData = {
            implementation = "prometheus";
          };
        }
      ];
    };
  };
}
