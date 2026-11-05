{
  config,
  pkgs,
  lib,
  ...
}:
let
  app = config.fleet.apps.vaultwarden;
in
{
  config = lib.mkIf config.fleet.appOnThisHost.vaultwarden {
    fleet.waitFor.postgres.vaultwarden.forServices = [ "vaultwarden.service" ];

    sops.secrets."vaultwarden/env" = {
      owner = "vaultwarden";
      restartUnits = [ "vaultwarden.service" ];
    };

    services.vaultwarden = {
      enable = true;
      dbBackend = "postgresql";
      environmentFile = config.sops.secrets."vaultwarden/env".path;
      config = {
        # https://github.com/dani-garcia/vaultwarden/blob/1.36.0/.env.template
        DOMAIN = "${app.edge.scheme}://${app.edge.domain}";
        ROCKET_PORT = app.port;
        ROCKET_ADDRESS = "0.0.0.0";
        SIGNUPS_ALLOWED = false;
        EXPERIMENTAL_CLIENT_FEATURE_FLAGS = "ssh-key-vault-item,ssh-agent";
      };
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
      app.port
    ];

    fleet.alwaysRestart = [ "vaultwarden" ];
  };
}
