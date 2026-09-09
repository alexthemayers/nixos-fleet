{
  services.sonarr = {
    enable = true;
    openFirewall = false;
  };

  systemd.services.sonarr = {
    unitConfig.RequiresMountsFor = [ "/mnt/nfs/media" ];
    serviceConfig = {
      MemoryHigh = "320M";
      MemoryMax = "384M";
      ReadWritePaths = [
        "/mnt/nfs/media/series"
        "/mnt/nfs/media/downloads"
      ];
    };
  };
}
