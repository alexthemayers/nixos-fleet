{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.fleet.waitForHost;
in
{
  options.fleet.waitForHost = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          host = lib.mkOption {
            type = lib.types.str;
            description = "Hostname or IP address to ping until it responds";
          };
          maxRetries = lib.mkOption {
            type = lib.types.int;
            default = 600;
            description = "Maximum number of ping attempts (1 attempt per second)";
          };
        };
      }
    );
    default = { };
    description = "Wait for specific hosts to become reachable via ping";
  };

  config = {
    systemd.services = lib.mkMerge (
      lib.mapAttrsToList (name: opts: {
        "wait-for-host-${name}" = {
          description = "Wait for ${name} (${opts.host}) to become reachable";
          after = [
            "network-online.target"
            "tailscaled.service"
          ];
          wants = [
            "network-online.target"
            "tailscaled.service"
          ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            TimeoutStartSec = "15m";
          };

          script = ''
            echo "Waiting for ${name} (${opts.host}) to be reachable..."
            retries=${toString opts.maxRetries}
            while ! ${pkgs.iputils}/bin/ping -c 1 -W 1 "${opts.host}" >/dev/null 2>&1; do
              if [ "$retries" -le 0 ]; then
                echo "Timeout waiting for ${name} (${opts.host})" >&2
                exit 1
              fi
              sleep 1
              retries=$((retries - 1))
            done
            echo "${name} is reachable."
          '';
        };
      }) cfg
    );
  };
}
