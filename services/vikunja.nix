{
  config,
  lib,
  pkgs,
  ...
}:
{
  fleet.waitFor.postgres.vikunja.forServices = [ "vikunja.service" ];
  fleet.waitForHost.vikunja-redis = {
    host = "xcloud-postgres";
    port = 6380;
    forServices = [ "vikunja.service" ];
  };

  users.users.vikunja = {
    group = "vikunja";
    isSystemUser = true;
  };
  users.groups.vikunja = { };
  sops.secrets = {
    "postgres/vikunja_password" = {
      owner = "vikunja";
      restartUnits = [ "vikunja.service" ];
    };
    "vikunja/client_secret" = {
      owner = "vikunja";
      restartUnits = [ "vikunja.service" ];
    };
    "vikunja/jwt_secret" = {
      owner = "vikunja";
      restartUnits = [ "vikunja.service" ];
    };
    "redis/vikunja_password" = {
      owner = "vikunja";
      restartUnits = [ "vikunja.service" ];
    };
  };
  sops.templates."vikunja-sso.env" = {
    owner = "vikunja";
    restartUnits = [ "vikunja.service" ];
    content = ''
      VIKUNJA_AUTH_OPENID_PROVIDERS_KEYCLOAK_CLIENTSECRET=${
        config.sops.placeholder."vikunja/client_secret"
      }
      VIKUNJA_REDIS_PASSWORD=${config.sops.placeholder."redis/vikunja_password"}
    '';
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    3456 # Vikunja (edge Caddy + Prometheus)
  ];

  services.vikunja = {
    enable = true;
    frontendScheme = "https";
    frontendHostname = "tasks.alexmayers.co.za";
    environmentFiles = [
      config.sops.templates."vikunja-sso.env".path
    ];
    settings = {
      service = {
        enableregistration = false;
        secret = "$__file{${config.sops.secrets."vikunja/jwt_secret".path}}";
      };
      log = {
        format = "structured";
      };
      metrics = {
        enabled = true;
      };

      database = {
        type = lib.mkForce "postgres";
        user = "vikunja";
        password = {
          file = config.sops.secrets."postgres/vikunja_password".path;
        };
        database = "vikunja";
        host = lib.mkForce "xcloud-postgres:5432";
      };
      auth = {
        openid = {
          enabled = true;
          providers = {
            keycloak = {
              name = "Keycloak";
              authurl = "https://identity.alexmayers.co.za/realms/master";
              logouturl = "https://identity.alexmayers.co.za/realms/master/protocol/openid-connect/logout";
              clientid = "vikunja";
            };
          };
        };
      };
      redis = {
        enabled = true;
        host = "xcloud-postgres:6380";
      };
      keyvalue = {
        type = "redis";
      };
      cache = {
        type = "redis";
      };
    };
  };
}
