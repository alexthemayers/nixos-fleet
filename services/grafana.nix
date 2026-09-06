{
  config,
  pkgs,
  lib,
  ...
}:
{
  fleet.waitFor.postgres.grafana.forServices = [ "grafana.service" ];

  # Grafana reads all four of these from disk at startup (three as *_FILE env
  # vars, oauth_secret via `$__file{}`), so a rotated value needs a restart.
  sops.secrets."grafana/admin_password" = {
    owner = "grafana";
    restartUnits = [ "grafana.service" ];
  };
  sops.secrets."grafana/secret_key" = {
    owner = "grafana";
    restartUnits = [ "grafana.service" ];
  };
  sops.secrets."postgres/grafana_password" = {
    owner = "grafana";
    restartUnits = [ "grafana.service" ];
  };
  sops.secrets."grafana/oauth_secret" = {
    owner = "grafana";
    restartUnits = [ "grafana.service" ];
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    3000 # Grafana (caddy-internal + Prometheus scrape)
  ];

  services.grafana = {
    enable = true;

    settings = {
      auth = {
        login_maximum_inactive_lifetime_duration = "30m";
        login_maximum_lifetime_duration = "10h";
      };

      "auth.generic_oauth" = {
        enabled = true;
        name = "Keycloak-OAuth";
        allow_sign_up = true;
        use_pkce = true;
        client_id = "grafana";
        client_secret = "$__file{${config.sops.secrets."grafana/oauth_secret".path}}";
        use_refresh_token = true;
        auth_token_refresh = true;
        scopes = "openid email profile offline_access";

        email_attribute_path = "email";
        login_attribute_path = "preferred_username";
        name_attribute_path = "name";

        auth_url = "https://identity.alexmayers.co.za/realms/master/protocol/openid-connect/auth";
        token_url = "https://identity.alexmayers.co.za/realms/master/protocol/openid-connect/token";
        api_url = "https://identity.alexmayers.co.za/realms/master/protocol/openid-connect/userinfo";
        signout_redirect_url = "https://identity.alexmayers.co.za/realms/master/protocol/openid-connect/logout?post_logout_redirect_uri=https://grafana.alexmayers.co.za/login";

        allow_assign_grafana_admin = true;
        role_attribute_path = "email == 'a.mayers102@gmail.com' && 'GrafanaAdmin' || 'Viewer'";
      };
      server = {
        http_addr = "0.0.0.0";

        domain = "grafana.alexmayers.co.za";
        root_url = "https://grafana.alexmayers.co.za/";
      };
      live = {
        allowed_origins = "https://grafana.alexmayers.co.za";
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
        secret_key = "$__file{${config.sops.secrets."grafana/secret_key".path}}";
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
          # Copies the tree into the Nix store. Community JSON stays at the
          # root of that path; fleet-authored boards live in fleet/.
          options = {
            path = ./grafana/dashboards;
            foldersFromFilesStructure = true;
          };
        }
      ];
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "http://proxmox-lb:9009/prometheus";
          isDefault = true;
          editable = false;
          jsonData = {
            prometheusType = "Mimir";
            httpMethod = "POST";
          };
        }
        {
          # Mimir is history. This agent is "is the fleet up right now" when
          # Mimir or the LB is down. Not default, so existing dashboards stay
          # on long-term storage.
          name = "Prometheus (local)";
          type = "prometheus";
          uid = "prometheus-local";
          url = "http://127.0.0.1:9090";
          isDefault = false;
          editable = false;
        }
        {
          name = "Loki";
          type = "loki";
          url = "http://proxmox-lb:3100";
          jsonData = {
            maxLines = 1000;
          };
        }
        {
          name = "Alertmanager";
          type = "alertmanager";
          url = "http://proxmox-lb:9093";
          jsonData = {
            oauthPassThru = true;
            implementation = "prometheus";
          };
        }
      ];
    };
  };

  systemd.services.grafana.stopIfChanged = false;
  systemd.services.grafana.restartIfChanged = false;
  systemd.services.grafana.serviceConfig.MemoryMax = "768M";
}
