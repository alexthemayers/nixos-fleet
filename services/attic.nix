{
  config,
  pkgs,
  lib,
  ...
}:
{
  sops.secrets."attic/env" = {
    owner = config.services.atticd.user;
    group = config.services.atticd.group;
    mode = "0440";
  };

  users.users.atticd = {
    group = "atticd";
    isSystemUser = true;
  };
  users.groups.atticd = { };

  services.atticd = {
    user = config.users.users.atticd.name;
    group = config.users.groups.atticd.name;
    enable = true;
    environmentFile = config.sops.secrets."attic/env".path;
    configFile = pkgs.writeText "server.toml" ''
      listen = "[::]:8080"

      [database]

      [chunking]
      avg-size = 262144
      max-size = 1048576
      min-size = 16384
      nar-size-threshold = 65536

      [storage]
      bucket = "attic"
      endpoint = "http://proxmox-lb:3902"
      region = "garage"
      type = "s3"
    '';
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8080 ];
}
