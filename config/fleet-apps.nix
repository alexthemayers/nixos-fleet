{
  config,
  lib,
  ...
}:
let
  cfg = config.fleet.apps;
  appsDir = ../fleet/apps;
  appFiles = lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n) (
    builtins.readDir appsDir
  );

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
        description = "Public URL scheme (the vhost listeners).";
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
            "vaultwarden"
          ]
        );
        default = "standard";
        description = "Caddy rate-limit preset, or null for none.";
      };
      rateLimitZone = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Caddy rate_limit zone name. Null uses the registry attr name.";
      };
      upstream = lib.mkOption {
        type = lib.types.enum [
          "remote"
          "loopback"
        ];
        default = "remote";
        description = "remote uses host:port; loopback uses 127.0.0.1:port.";
      };
      upstreamTls = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Dial the backend with https://.";
      };
      tlsInsecure = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Caddy tls_insecure_skip_verify on the upstream transport.";
      };
      auth = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "forward"
            "hybrid"
          ]
        );
        default = null;
        description = "oauth2-proxy on this vhost, or null for none.";
      };
      waf = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Coraza DetectionOnly on this vhost.";
      };
      wafExtraDirectives = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Extra Coraza SecRule lines (Grafana, GitLab).";
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
      adminCidrPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Abort this path unless the client is in 100.64.0.0/10.";
      };
      securityHeaders = lib.mkOption {
        type = lib.types.enum [
          "strict"
          "loose"
        ];
        default = "strict";
        description = "strict is the usual HSTS set; loose is HSTS plus -Server only.";
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
      lbTryDuration = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      lbTryInterval = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      healthUri = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      healthPort = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
      };
      healthInterval = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      healthTimeout = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      healthStatus = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      failDuration = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      maxFails = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
      };
      unhealthyStatus = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
    };
  };

  udpType = lib.types.submodule {
    options = {
      listenPort = lib.mkOption {
        type = lib.types.port;
        description = "UDP port Caddy layer4 listens on.";
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
        default = "";
        description = "Path on the public URL for the blackbox probe. Empty keeps the bare origin.";
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
            module = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Repo-relative NixOS module path. flake.nix imports it on
                `host` and `extraHosts` only (config/fleet-app-imports.nix).
                Null means no NixOS module (Proxmox, TrueNAS).
              '';
            };
            extraHosts = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Extra inventory hosts that also import this module.";
            };
            dashboard = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Grafana dashboard file name, or null if none yet.";
            };
            edge = lib.mkOption {
              type = lib.types.nullOr edgeType;
              default = null;
              description = "Public Caddy HTTP vhost. Null means no HTTPS vhost.";
            };
            udp = lib.mkOption {
              type = lib.types.nullOr udpType;
              default = null;
              description = "Caddy layer4 UDP proxy. Null means no UDP listener.";
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
      probe, UDP, module path. Evaluated on every machine so Caddy on
      xcloud-caddy and the app module on the serving VM cannot drift.
      Drop a file in fleet/apps/; it is imported by filename. flake.nix
      imports `module` on `host` plus `extraHosts`.
    '';
  };

  options.fleet.appOnThisHost = lib.mkOption {
    type = lib.types.attrsOf lib.types.bool;
    internal = true;
    readOnly = true;
    description = "Whether this host is fleet.apps.<name>.host or extraHosts.";
  };

  options.fleet.alwaysRestart = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "systemd unit names without .service that always restart.";
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
    fleet.apps = lib.mapAttrs' (
      file: _: lib.nameValuePair (lib.removeSuffix ".nix" file) (import (appsDir + "/${file}"))
    ) appFiles;

    fleet.publicHttpProbeTargets = lib.mapAttrsToList (
      _: app: "${app.edge.scheme}://${app.edge.domain}${app.probe.path}"
    ) (lib.filterAttrs (_: app: app.probe.public && app.edge != null) cfg);

    fleet.internalHttpProbeTargets = lib.mapAttrsToList (
      _: app: "http://${app.host}:${toString app.port}"
    ) (lib.filterAttrs (_: app: app.probe.internal) cfg);

    fleet.appOnThisHost = lib.mapAttrs (
      _: app: config.networking.hostName == app.host || lib.elem config.networking.hostName app.extraHosts
    ) cfg;

    systemd.services = lib.genAttrs config.fleet.alwaysRestart (_name: {
      startLimitIntervalSec = 0;
      serviceConfig = {
        Restart = lib.mkOverride 10 "always";
        RestartSec = lib.mkOverride 10 "10s";
      };
    });

    assertions =
      let
        apps = lib.attrValues cfg;
        unknownHosts = lib.filter (a: !(lib.elem a.host config.fleet.inventory.hosts)) apps;
        publicWithoutEdge = lib.filter (a: a.probe.public && a.edge == null) apps;
        unknownListeners = lib.filter (
          a: a.edge != null && !(lib.elem a.edge.listenerHost config.fleet.inventory.hosts)
        ) apps;
        dupVhosts = lib.filterAttrs (_: group: builtins.length group > 1) (
          lib.groupBy (a: "${a.edge.scheme}://${a.edge.domain}") (lib.filter (a: a.edge != null) apps)
        );
        dupUdp = lib.filterAttrs (_: group: builtins.length group > 1) (
          lib.groupBy (a: toString a.udp.listenPort) (lib.filter (a: a.udp != null) apps)
        );
        unknownExtra = lib.concatMap (
          a: lib.filter (h: !(lib.elem h config.fleet.inventory.hosts)) a.extraHosts
        ) apps;
        repo = ../.;
        named = lib.mapAttrsToList (n: a: a // { name = n; }) cfg;
        missingDocs = lib.filter (a: !(builtins.pathExists (repo + "/${a.docs}"))) named;
        missingModules = lib.filter (
          a: a.module != null && !(builtins.pathExists (repo + "/${a.module}"))
        ) named;
        dashboardExists =
          name:
          builtins.pathExists (repo + "/services/grafana/dashboards/${name}")
          || builtins.pathExists (repo + "/services/grafana/dashboards/fleet/${name}");
        missingDashboards = lib.filter (a: a.dashboard != null && !(dashboardExists a.dashboard)) named;
        atticApps = lib.filter (a: a.module == "services/attic.nix") named;
        wrongListener = lib.filter (a: a.edge != null && a.edge.listenerHost != "xcloud-caddy") named;
        keycloakAuth = cfg.keycloak.edge != null && cfg.keycloak.edge.auth != null;
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
        {
          assertion = dupVhosts == { };
          message = ''
            fleet.apps duplicate edge vhosts:
            ${lib.concatStringsSep ", " (lib.attrNames dupVhosts)}
          '';
        }
        {
          assertion = dupUdp == { };
          message = ''
            fleet.apps duplicate UDP listen ports:
            ${lib.concatStringsSep ", " (lib.attrNames dupUdp)}
          '';
        }
        {
          assertion = unknownExtra == [ ];
          message = ''
            fleet.apps extraHosts not in fleet.inventory.hosts:
            ${lib.concatStringsSep ", " unknownExtra}
          '';
        }
        {
          assertion = missingDocs == [ ];
          message = ''
            fleet.apps docs path does not exist:
            ${lib.concatMapStringsSep ", " (a: "${a.name} -> ${a.docs}") missingDocs}
          '';
        }
        {
          assertion = missingModules == [ ];
          message = ''
            fleet.apps module path does not exist:
            ${lib.concatMapStringsSep ", " (a: "${a.name} -> ${a.module}") missingModules}
          '';
        }
        {
          assertion = missingDashboards == [ ];
          message = ''
            fleet.apps dashboard file is missing under services/grafana/dashboards/:
            ${lib.concatMapStringsSep ", " (a: "${a.name} -> ${a.dashboard}") missingDashboards}
          '';
        }
        {
          assertion = builtins.length atticApps == 1;
          message = ''
            Exactly one fleet.apps entry may use services/attic.nix
            (docs/adr/2026-08-29-attic-monolithic.md). Found:
            ${lib.concatMapStringsSep ", " (a: a.name) atticApps}
          '';
        }
        {
          assertion = atticApps != [ ] && (builtins.head atticApps).extraHosts == [ ];
          message = "fleet.apps.attic extraHosts must be empty; a second import would run GC";
        }
        {
          assertion = wrongListener == [ ];
          message = ''
            Edge TLS terminates on xcloud-caddy only (docs/adr/2026-09-07-no-internal-lb.md):
            ${lib.concatMapStringsSep ", " (a: "${a.name} listenerHost=${a.edge.listenerHost}") wrongListener}
          '';
        }
        {
          assertion = !keycloakAuth;
          message = "Keycloak is the IdP; fleet.apps.keycloak.edge.auth must stay null (docs/adr/2026-08-29-oauth2-proxy-coverage.md)";
        }
      ];
  };
}
