{
  services.bazarr = {
    enable = true;
    openFirewall = false;
    listenPort = 6767;
  };

  # movies/ and series/ are 0770 uid/gid 3000 on the TrueNAS export.
  # Bazarr must write .srt next to *arr imports.
  users.groups.media-nfs.gid = 3000;
  users.users.bazarr.extraGroups = [ "media-nfs" ];

  systemd.services.bazarr = {
    unitConfig.RequiresMountsFor = [ "/mnt/nfs/media" ];
    serviceConfig = {
      MemoryHigh = "384M";
      MemoryMax = "512M";
      ReadWritePaths = [
        "/mnt/nfs/media/movies"
        "/mnt/nfs/media/series"
      ];
    };
  };
}
