{
  config,
  lib,
  ...
}:
{
  sops.secrets."postgres/keycloak_password" = {
    restartUnits = [ "keycloak.service" ];
  };
  sops.secrets."keycloak/bootstrap_admin_password" = {
    restartUnits = [ "keycloak.service" ];
  };

  # KC_BOOTSTRAP_ADMIN_* is only consumed when the realm database has no admin
  # yet. It is delivered as an EnvironmentFile so the value never reaches the
  # world-readable Nix store, unlike services.keycloak.initialAdminPassword.
  # Note: restarting Keycloak re-reads the database password, but it does *not*
  # re-apply a rotated KC_BOOTSTRAP_ADMIN_PASSWORD -- that is only consumed when
  # the realm database has no admin yet. Rotating the bootstrap admin password
  # requires changing it in Keycloak itself.
  sops.templates."keycloak-bootstrap.env" = {
    restartUnits = [ "keycloak.service" ];
    content = ''
      KC_BOOTSTRAP_ADMIN_USERNAME=admin
      KC_BOOTSTRAP_ADMIN_PASSWORD=${config.sops.placeholder."keycloak/bootstrap_admin_password"}
    '';
  };

  services.keycloak = {
    enable = true;
    database = {
      host = "xcloud-postgres";
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

  fleet.waitFor.postgres.keycloak.forServices = [ "keycloak.service" ];

  systemd.services.keycloak.serviceConfig.EnvironmentFile =
    config.sops.templates."keycloak-bootstrap.env".path;

  # Crashloop until Postgres (or Keycloak itself) is actually usable. Do not
  # cap StartLimitInterval: a 600s wait that then gives up leaves SSO dead.
  systemd.services.keycloak.serviceConfig.Restart = lib.mkForce "always";
  systemd.services.keycloak.serviceConfig.RestartSec = "10s";
  systemd.services.keycloak.unitConfig.StartLimitIntervalSec = 0;

  systemd.services.keycloak.environment = {
    JAVA_OPTS_APPEND = "-Djgroups.bind.address=match-interface:tailscale0 -Djgroups.bind_addr=match-interface:tailscale0 -Djava.net.preferIPv4Stack=true";
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    7777 # Keycloak HTTP (caddy-internal reverse_proxy)
    9000 # Keycloak health (caddy-internal health_port)
    7800 # JGroups cluster (bound to tailscale0)
    57800 # JGroups FD_SOCK (bound to tailscale0)
  ];
}
