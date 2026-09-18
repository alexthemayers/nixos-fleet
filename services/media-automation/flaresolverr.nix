{ config, lib, ... }:
{
  config = lib.mkIf config.fleet.appOnThisHost.flaresolverr {
    services.flaresolverr = {
      enable = true;
      openFirewall = false;
      port = config.fleet.apps.flaresolverr.port;
    };

    # Headless Chromium. 1G max dropped sessions during 1337x
    # solves (docs/memory.md).
    systemd.services.flaresolverr.serviceConfig = {
      MemoryHigh = "1G";
      MemoryMax = "2G";
    };
  };
}
