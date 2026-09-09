{
  services.radarr = {
    enable = true;
    openFirewall = false;
  };

  systemd.services.radarr = {
    unitConfig.RequiresMountsFor = [ "/mnt/nfs/media" ];
    serviceConfig = {
      MemoryHigh = "320M";
      MemoryMax = "384M";
      ReadWritePaths = [
        "/mnt/nfs/media/movies"
        "/mnt/nfs/media/downloads"
      ];
    };
  };
}
