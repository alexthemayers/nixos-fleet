{
  config,
  lib,
  ...
}:
let
  cfg = config.fleet.apps;

  edgeType = lib.types.submodule {
    options = {
      domain = lib.mkOption {
        type = lib.types.str;
        description = "Public hostname, without scheme.";
      };
      scheme = lib.mkOption {
        type = lib.types.enum [
          "http"
          "https"
        ];
        default = "https";
        description = "Public URL scheme.";
      };
      listenerHost = lib.mkOption {
        type = lib.types.str;
        default = "xcloud-caddy";
        description = "Host that terminates TLS for this vhost.";
      };
      rateLimit = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "standard"
            "heavy"
            "ultraHeavy"
          ]
        );
        default = "standard";
        description = "Caddy rate-limit preset, or null for none.";
      };
      flushInterval = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Caddy reverse_proxy flush_interval, or null to omit.";
      };
      dialTimeout = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Caddy HTTP transport dial_timeout, or null to omit.";
      };
      wafBypassPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "URI prefixes that skip Coraza (streaming, sockets).";
      };
      wafBypassWebsockets = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Skip Coraza on Connection/Upgrade websocket handshakes.";
      };
    };
  };

  probeType = lib.types.submodule {
    options = {
      public = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Add this app's public URL to blackbox_http.";
      };
      internal = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Add http://host:port to blackbox_http_internal.";
      };
      path = lib.mkOption {
        type = lib.types.str;
        default = "/";
        description = "Path on the public URL for the blackbox probe.";
      };
    };
  };
in
{
  options.fleet.apps = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options = {
            host = lib.mkOption {
              type = lib.types.str;
              description = "Inventory hostname that runs the process.";
            };
            port = lib.mkOption {
              type = lib.types.port;
              description = "Process listen port on the tailnet.";
            };
            unit = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "systemd unit name without .service.";
            };
            docs = lib.mkOption {
              type = lib.types.str;
              description = "Repo-relative service doc path.";
            };
            dashboard = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Grafana dashboard file name, or null if none yet.";
            };
            edge = lib.mkOption {
              type = lib.types.nullOr edgeType;
              default = null;
              description = "Public Caddy vhost. Null means tailnet-only.";
            };
            probe = lib.mkOption {
              type = probeType;
              default = { };
              description = "Blackbox coverage for this app.";
            };
          };
        }
      )
    );
    default = { };
    description = ''
      Cross-host application registry. Pure data: host, port, public URL,
      probe. Evaluated on every machine so Caddy on xcloud-caddy and the
      app module on the serving VM cannot drift. Add an entry under
      fleet/apps/ and import it below.
    '';
  };

  options.fleet.publicHttpProbeTargets = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    internal = true;
    readOnly = true;
    description = "blackbox_http URLs derived from fleet.apps with probe.public.";
  };

  options.fleet.internalHttpProbeTargets = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    internal = true;
    readOnly = true;
    description = "blackbox_http_internal URLs from fleet.apps with probe.internal.";
  };

  config = {
    fleet.apps.jellyfin = import ../fleet/apps/jellyfin.nix;

    fleet.publicHttpProbeTargets = lib.mapAttrsToList (
      _: app: "${app.edge.scheme}://${app.edge.domain}${app.probe.path}"
    ) (lib.filterAttrs (_: app: app.probe.public && app.edge != null) cfg);

    fleet.internalHttpProbeTargets = lib.mapAttrsToList (
      _: app: "http://${app.host}:${toString app.port}"
    ) (lib.filterAttrs (_: app: app.probe.internal) cfg);

    assertions =
      let
        unknownHosts = lib.filter (a: !(lib.elem a.host config.fleet.inventory.hosts)) (lib.attrValues cfg);
        publicWithoutEdge = lib.filter (a: a.probe.public && a.edge == null) (lib.attrValues cfg);
        unknownListeners = lib.filter (
          a: a.edge != null && !(lib.elem a.edge.listenerHost config.fleet.inventory.hosts)
        ) (lib.attrValues cfg);
      in
      [
        {
          assertion = unknownHosts == [ ];
          message = ''
            fleet.apps host not in fleet.inventory.hosts:
            ${lib.concatMapStringsSep ", " (a: a.host) unknownHosts}
          '';
        }
        {
          assertion = publicWithoutEdge == [ ];
          message = "fleet.apps probe.public requires edge != null";
        }
        {
          assertion = unknownListeners == [ ];
          message = ''
            fleet.apps edge.listenerHost not in fleet.inventory.hosts:
            ${lib.concatMapStringsSep ", " (a: a.edge.listenerHost) unknownListeners}
          '';
        }
      ];
  };
}
