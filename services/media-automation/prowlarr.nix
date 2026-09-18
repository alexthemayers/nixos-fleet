{ config, lib, ... }:
{
  config = lib.mkIf config.fleet.appOnThisHost.prowlarr {
    services.prowlarr = {
      enable = true;
      openFirewall = false;
    };

    systemd.services.prowlarr.serviceConfig = {
      MemoryHigh = "512M";
      MemoryMax = "768M";
    };
  };
}
