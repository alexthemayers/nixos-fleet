{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.fleet.clusterEnv;
in
{
  options.fleet.clusterEnv = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options = {
            service = lib.mkOption {
              type = lib.types.str;
              description = "Systemd unit that consumes the EnvironmentFile.";
            };
            envFile = lib.mkOption {
              type = lib.types.str;
              default = "/run/${name}-cluster.env";
              description = "Runtime path of the generated EnvironmentFile.";
            };
            ipVariable = lib.mkOption {
              type = lib.types.str;
              description = "Environment variable set to the tailscale0 IPv4 address.";
            };
            ipSuffix = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Appended to the address (e.g. :9094 for Alertmanager).";
            };
            extra = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "Additional KEY=value lines written into the file.";
            };
            timeoutSec = lib.mkOption {
              type = lib.types.int;
              default = 60;
            };
          };
        }
      )
    );
    default = { };
    description = ''
      Oneshot that writes a Tailscale IPv4 address into an EnvironmentFile
      before a clustered daemon starts. systemd loads EnvironmentFile before
      ExecStartPre, so the file has to exist from a separate unit.
    '';
  };

  config = {
    systemd.services = lib.mkMerge (
      lib.mapAttrsToList (
        name: opts:
        let
          unit = "${name}-cluster-env";
          svcName = lib.removeSuffix ".service" opts.service;
          extraEchoes = lib.concatMapStringsSep "\n            " (k: "echo \"${k}=${opts.extra.${k}}\"") (
            lib.attrNames opts.extra
          );
          script = pkgs.writeShellScript "${name}-cluster-env" ''
            set -euo pipefail

            tailscale_ip() {
              ${pkgs.tailscale}/bin/tailscale ip -4 2>/dev/null | head -n1 && return 0
              ${pkgs.iproute2}/bin/ip -4 addr show dev tailscale0 2>/dev/null \
                | ${pkgs.gawk}/bin/awk '/inet /{print $2}' | cut -d/ -f1 | head -n1
            }

            ip=""
            for _ in $(seq 1 ${toString opts.timeoutSec}); do
              ip=$(tailscale_ip || true)
              [ -n "$ip" ] && break
              sleep 1
            done

            if [ -z "$ip" ]; then
              echo "tailscale0 still has no IPv4 address after ${toString opts.timeoutSec}s; refusing to start ${name}" >&2
              exit 1
            fi

            umask 077
            {
              echo "${opts.ipVariable}=$ip${opts.ipSuffix}"
              ${extraEchoes}
            } > ${opts.envFile}
          '';
        in
        {
          ${unit} = {
            description = "Resolve the tailscale0 address ${name} gossips on";
            before = [ opts.service ];
            requiredBy = [ opts.service ];
            after = [
              "tailscaled.service"
              "network-online.target"
            ];
            wants = [
              "tailscaled.service"
              "network-online.target"
            ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = script;
            };
          };
          ${svcName} = {
            after = [ "${unit}.service" ];
            requires = [ "${unit}.service" ];
            serviceConfig.EnvironmentFile = [ opts.envFile ];
          };
        }
      ) cfg
    );
  };
}
