{ config, pkgs, ... }:
{
  sops.secrets."postgres/keycloak_password" = { };
  services.keycloak = {
    enable = true;
    initialAdminPassword = "admin";
    database = {
      type = "postgresql";
      host = "xcloud-postgres";
      port = 5432;
      name = "keycloak";
      username = "keycloak";
      passwordFile = config.sops.secrets."postgres/keycloak_password".path;
      useSSL = false;
    };
    settings = {
      hostname = "identity.alexmayers.co.za";
      http-port = 7777;
      http-host = "0.0.0.0";
      http-enabled = true;
      proxy-headers = "xforwarded";
      "log-console-output" = "json";
      "health-enabled" = true;
      "metrics-enabled" = true;
    };
  };

  systemd.services.keycloak.environment = {
    JAVA_OPTS_APPEND = "-Djgroups.bind_addr=match-interface:tailscale0";
  };
}
