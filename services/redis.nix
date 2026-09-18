{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.fleet.services.redis;
  redisExporters = {
    oauth2-proxy = {
      redisPort = 6379;
      metricsPort = 9121;
      passwordSecret = "redis/oauth2_proxy_password";
    };
    vikunja = {
      redisPort = 6380;
      metricsPort = 9122;
      passwordSecret = "redis/vikunja_password";
    };
    paperless = {
      redisPort = 6381;
      metricsPort = 9123;
      passwordSecret = "redis/paperless_password";
    };
  };
  exporterUnit = name: "prometheus-redis-exporter-${name}";
in
{
  options.fleet.services.redis = {
    enable = lib.mkEnableOption "Redis instances";
  };

  config = lib.mkMerge [
    (lib.mkIf config.fleet.appOnThisHost.redis {
      fleet.services.redis.enable = true;
    })
    (lib.mkIf cfg.enable {
      # Read by the redis ExecStartPre, which runs as root ("+" prefix upstream),
      # so these stay root-owned.
      sops.secrets."redis/oauth2_proxy_password" = {
        restartUnits = [ "redis-oauth2-proxy.service" ];
      };
      sops.secrets."redis/vikunja_password" = {
        restartUnits = [ "redis-vikunja.service" ];
      };
      sops.secrets."redis/paperless_password" = {
        restartUnits = [ "redis-paperless.service" ];
      };

      services.redis = {
        servers = {
          # Each instance listens on every interface because clients reach it over
          # the tailnet and the tailscale0 address is not known at build time.
          # Authentication, not the listen address, is the access control here.
          oauth2-proxy = {
            bind = "0.0.0.0 ::";
            enable = true;
            port = 6379;
            requirePassFile = config.sops.secrets."redis/oauth2_proxy_password".path;
            settings = {
              "protected-mode" = "yes";
              maxmemory = "16mb";
              "maxmemory-policy" = "allkeys-lru";
            };
          };
          vikunja = {
            bind = "0.0.0.0 ::";
            enable = true;
            port = 6380;
            requirePassFile = config.sops.secrets."redis/vikunja_password".path;
            settings = {
              "protected-mode" = "yes";
              maxmemory = "16mb";
              "maxmemory-policy" = "allkeys-lru";
            };
          };
          paperless = {
            bind = "0.0.0.0 ::";
            enable = true;
            port = 6381;
            requirePassFile = config.sops.secrets."redis/paperless_password".path;
            settings = {
              "protected-mode" = "yes";
              maxmemory = "32mb";
              "maxmemory-policy" = "allkeys-lru";
            };
          };
        };
      };

      networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
        6379 # redis: oauth2-proxy sessions
        6380 # redis: vikunja
        6381 # redis: paperless
        9121 # redis exporter: oauth2-proxy
        9122 # redis exporter: vikunja
        9123 # redis exporter: paperless
      ];

      # One exporter per instance. The nixpkgs module only takes a single
      # REDIS_PASSWORD, which left vikunja and paperless invisible.
      users.users.redis-exporter = {
        isSystemUser = true;
        group = "redis-exporter";
      };
      users.groups.redis-exporter = { };

      sops.templates = lib.mapAttrs' (
        name: spec:
        lib.nameValuePair "redis-exporter-${name}.env" {
          owner = "redis-exporter";
          group = "redis-exporter";
          restartUnits = [ "${exporterUnit name}.service" ];
          content = ''
            REDIS_ADDR=redis://127.0.0.1:${toString spec.redisPort}
            REDIS_PASSWORD=${config.sops.placeholder.${spec.passwordSecret}}
          '';
        }
      ) redisExporters;

      systemd.services = lib.mapAttrs' (
        name: spec:
        lib.nameValuePair (exporterUnit name) {
          description = "Prometheus redis exporter (${name})";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "redis-${name}.service"
          ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            User = "redis-exporter";
            Group = "redis-exporter";
            EnvironmentFile = config.sops.templates."redis-exporter-${name}.env".path;
            ExecStart = "${lib.getExe pkgs.prometheus-redis-exporter} --web.listen-address 0.0.0.0:${toString spec.metricsPort}";
            Restart = "always";
            RestartSec = "10s";
            MemoryMax = "32M";
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
          };
        }
      ) redisExporters;
    })
  ];
}
