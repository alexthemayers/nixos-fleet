{
  config,
  pkgs,
  lib,
  ...
}:
let
  app = config.fleet.apps.actualbudget;
in
{
  config = lib.mkIf config.fleet.appOnThisHost.actualbudget {
    users.users.actual = {
      group = "actual";
      isSystemUser = true;
    };
    users.groups.actual = { };
    sops.secrets."actualbudget/client_secret" = {
      owner = "actual";
      restartUnits = [ "actual.service" ];
    };
    fileSystems."/mnt/nfs/actualbudget" = {
      device = "truenas-scale:/mnt/ssd/actualbudget";
      fsType = "nfs";
      options = import ../config/nfs-mount.nix "actualbudget" [ ];
    };

    fleet.waitForHost.actualbudget.host = "truenas-scale";

    systemd.services.actual = {
      serviceConfig = {
        RequiresMountsFor = [ "/mnt/nfs/actualbudget" ];
        BindPaths = [ "/mnt/nfs/actualbudget:/var/lib/private/actual" ];
      };
    };
    services.actual = {
      enable = true;
      settings = {
        # nixpkgs default is 3000; edge Caddy and the tailscale0 hole are the registry port.
        port = app.port;
        openId = {
          discoveryURL = "https://identity.alexmayers.co.za/realms/master/.well-known/openid-configuration";
          client_id = "actualbudget";

          client_secret._secret = config.sops.secrets."actualbudget/client_secret".path;

          server_hostname = "${app.edge.scheme}://${app.edge.domain}";
          authMethod = "openid";
        };
      };
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
      app.port
    ];

    fleet.alwaysRestart = [ app.unit ];
  };
}
