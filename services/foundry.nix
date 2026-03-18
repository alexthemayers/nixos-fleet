{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.foundry-server;
in
{
  options.services.foundry-server = {
    enable = lib.mkEnableOption "Foundry Server";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.nodejs_20;
      description = "The Node.js package to use.";
    };

    scriptPath = lib.mkOption {
      type = lib.types.path;
      description = "Absolute path to the main entry point (e.g., index.js).";
    };

    workingDir = lib.mkOption {
      type = lib.types.path;
      description = "The directory where the JS files are located.";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = [ 30000 ];

    systemd.services.foundry-server = {
      description = "Node.js Web Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/node ${cfg.scriptPath}";
        WorkingDirectory = "${cfg.workingDir}";
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
  };
}
