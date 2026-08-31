{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.fleet.services.redis;
in
{
  options.fleet.services.redis = {
    enable = lib.mkEnableOption "Redis instances";
  };

  config = lib.mkIf cfg.enable {
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
          };
        };
        vikunja = {
          bind = "0.0.0.0 ::";
          enable = true;
          port = 6380;
          requirePassFile = config.sops.secrets."redis/vikunja_password".path;
          settings = {
            "protected-mode" = "yes";
          };
        };
        paperless = {
          bind = "0.0.0.0 ::";
          enable = true;
          port = 6381;
          requirePassFile = config.sops.secrets."redis/paperless_password".path;
          settings = {
            "protected-mode" = "yes";
          };
        };
      };
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
      6379 # redis: oauth2-proxy sessions
      6380 # redis: vikunja
      6381 # redis: paperless
      9121 # redis exporter
    ];

    sops.templates."redis-exporter.env" = {
      restartUnits = [ "prometheus-redis-exporter.service" ];
      content = ''
        REDIS_PASSWORD=${config.sops.placeholder."redis/oauth2_proxy_password"}
      '';
    };

    services.prometheus.exporters.redis = {
      enable = true;
    };
    systemd.services.prometheus-redis-exporter.serviceConfig.EnvironmentFile =
      config.sops.templates."redis-exporter.env".path;
  };
}
