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
    services.redis = {
      servers = {
        oauth2-proxy = {
          bind = "0.0.0.0 ::";
          enable = true;
          port = 6379;
          settings = {
            "protected-mode" = "no";
          };
        };
        vikunja = {
          bind = "0.0.0.0 ::";
          enable = true;
          port = 6380;
          settings = {
            "protected-mode" = "no";
          };
        };
      };
    };
    services.prometheus.exporters.redis = {
      enable = true;
    };
  };
}
