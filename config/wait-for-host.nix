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
            description = "Hostname or IP to wait for (ping, or TCP if port is set).";
          };
          port = lib.mkOption {
            type = lib.types.nullOr lib.types.port;
            default = null;
            description = ''
              If set, wait until this TCP port accepts connections instead of ICMP.
              Use this for Postgres, Redis, Garage S3, Keycloak, and similar.
            '';
          };
          maxRetries = lib.mkOption {
            type = lib.types.int;
            default = 600;
            description = "Seconds to wait before failing (one check per second).";
          };
          forServices = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            example = [ "keycloak.service" ];
            description = ''
              Systemd units that must not start until this wait succeeds.
              Each gets after= and requires= on wait-for-host-<name>.service.
            '';
          };
        };
      }
    );
    default = { };
    description = "Wait for a remote host (and optional TCP port) before starting dependent units.";
  };

  options.fleet.waitFor.garage = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.forServices = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
      }
    );
    default = { };
    description = "Garage S3 waits on proxmox-db-1:3902 and proxmox-lb:3902.";
  };

  options.fleet.waitFor.postgres = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.forServices = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
      }
    );
    default = { };
    description = "Postgres/PgBouncer waits on xcloud-postgres:5432.";
  };

  config = {
    fleet.waitForHost = lib.mkMerge (
      lib.mapAttrsToList (name: opts: {
        "${name}-garage" = {
          host = "proxmox-db-1";
          port = 3902;
          inherit (opts) forServices;
        };
        "${name}-garage-lb" = {
          host = "proxmox-lb";
          port = 3902;
          inherit (opts) forServices;
        };
      }) config.fleet.waitFor.garage
      ++ lib.mapAttrsToList (name: opts: {
        "${name}-postgres" = {
          host = "xcloud-postgres";
          port = 5432;
          inherit (opts) forServices;
        };
      }) config.fleet.waitFor.postgres
    );

    systemd.services = lib.mkMerge (
      lib.concatLists (
        lib.mapAttrsToList (
          name: opts:
          let
            waitUnit = "wait-for-host-${name}.service";
            check =
              if opts.port == null then
                ''${pkgs.iputils}/bin/ping -c 1 -W 1 "${opts.host}" >/dev/null 2>&1''
              else
                ''${pkgs.netcat}/bin/nc -z -w 1 "${opts.host}" ${toString opts.port} >/dev/null 2>&1'';
            target = if opts.port == null then opts.host else "${opts.host}:${toString opts.port}";
          in
          [
            {
              "wait-for-host-${name}" = {
                description = "Wait for ${name} (${target}) to become reachable";
                after = [
                  "network-online.target"
                  "tailscaled.service"
                ];
                wants = [
                  "network-online.target"
                  "tailscaled.service"
                ];

                # Not wantedBy multi-user.target. A wait only runs when a mount
                # or service Requires it, so an unrelated down host cannot stall
                # boot for 600s.
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  # Script loops maxRetries times at ~1s each; give systemd a
                  # little headroom so it does not SIGTERM the loop first.
                  TimeoutStartSec = "${toString (opts.maxRetries + 30)}s";
                };

                script = ''
                  echo "Waiting for ${name} (${target})..."
                  deadline=$((SECONDS + ${toString opts.maxRetries}))
                  while ! ${check}; do
                    if [ "$SECONDS" -ge "$deadline" ]; then
                      echo "Timeout waiting for ${name} (${target}) after ${toString opts.maxRetries}s" >&2
                      exit 1
                    fi
                    sleep 1
                  done
                  echo "${name} is reachable."
                '';
              };
            }
          ]
          ++ map (svc: {
            ${lib.removeSuffix ".service" svc} = {
              after = [ waitUnit ];
              requires = [ waitUnit ];
            };
          }) opts.forServices
        ) cfg
      )
    );
  };
}
