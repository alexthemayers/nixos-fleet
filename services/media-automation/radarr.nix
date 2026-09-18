{ config, lib, ... }:
{
  config = lib.mkIf config.fleet.appOnThisHost.radarr {
    services.radarr = {
      enable = true;
      openFirewall = false;
    };

    systemd.services.radarr = {
      unitConfig.RequiresMountsFor = [ "/mnt/nfs/media" ];
      serviceConfig = {
        MemoryHigh = "768M";
        MemoryMax = "1G";
        ReadWritePaths = [
          "/mnt/nfs/media/movies"
          "/mnt/nfs/media/downloads"
        ];
      };
    };
  };
}
