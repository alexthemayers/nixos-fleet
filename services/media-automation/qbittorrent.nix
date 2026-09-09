{
  services.qbittorrent = {
    enable = true;
    openFirewall = false;
    webuiPort = 8081;
    # Leave serverConfig empty so the WebUI password and save path in
    # /var/lib/qBittorrent survive a switch. Set DefaultSavePath in the
    # UI to /mnt/nfs/media/downloads (runbook).
    extraArgs = [ "--confirm-legal-notice" ];
  };

  systemd.services.qbittorrent = {
    unitConfig.RequiresMountsFor = [ "/mnt/nfs/media" ];
    serviceConfig = {
      MemoryHigh = "448M";
      MemoryMax = "512M";
      ReadWritePaths = [ "/mnt/nfs/media/downloads" ];
    };
  };
}
