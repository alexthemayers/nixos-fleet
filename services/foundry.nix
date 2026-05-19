{
  config,
  lib,
  pkgs,
  ...
}:
{
  networking.firewall.allowedTCPPorts = [ 30000 ];
  systemd.services.foundry-server = {
    description = "Node.js Web Server";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.nodejs_20}/bin/node ${./packages/foundry}/main.js";
      WorkingDirectory = "./packages/foundry";
      StateDirectory = "foundry";

      Restart = "always";
      RestartSec = "5s";

      # Security: Runs as a transient unprivileged user
      DynamicUser = true;
      Environment = [
        "PORT=30000"
        "FOUNDRY_VTT_DATA_PATH=/var/lib/foundry"
        "NODE_ENV=production"
      ];
    };
  };
}
