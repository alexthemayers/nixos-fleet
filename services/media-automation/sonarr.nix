{ config, lib, ... }:
{
  config = lib.mkIf config.fleet.appOnThisHost.sonarr {
    services.sonarr = {
      enable = true;
      openFirewall = false;
    };

    systemd.services.sonarr = {
      unitConfig.RequiresMountsFor = [ "/mnt/nfs/media" ];
      serviceConfig = {
        MemoryHigh = "768M";
        MemoryMax = "1G";
        ReadWritePaths = [
          "/mnt/nfs/media/series"
          "/mnt/nfs/media/downloads"
        ];
      };
    };
  };
}
