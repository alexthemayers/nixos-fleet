{
  config,
  pkgs,
  lib,
  ...
}:
{
  sops.secrets."attic/env" = {
    owner = "atticd";
    group = "atticd";
  };

  services.atticd = {
    enable = true;
    environmentFile = config.sops.secrets."attic/env".path;
    settings = {
      listen = "[::]:8080";
      chunking = {
        nar-size-threshold = 65536;
        min-size = 16384;
        avg-size = 262144;
        max-size = 1048576;
      };
      storage = {
        type = "s3";
        region = "garage"; # Garage ignores region, but it's required by S3 clients
        bucket = "attic";
        endpoint = "http://127.0.0.1:3902"; # Connect to the local Garage daemon instance
      };
    };
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8080 ];
}
