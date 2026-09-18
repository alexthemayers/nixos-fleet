{ config, lib, ... }:
{
  config = lib.mkIf config.fleet.appOnThisHost.qbittorrent {
    # DHT/uTP on UDP 41666 used the OS default socket buffer (212 KiB).
    # That overflowed and fired TailscaleNodeUDPBufferErrors. Tailscale
    # already sets 14 MiB on its own sockets; this only changes the default
    # for apps that do not. TCP still autotunes up to tcp_rmem max.
    boot.kernel.sysctl = {
      "net.core.rmem_default" = 4194304;
      "net.core.wmem_default" = 4194304;
    };

    services.qbittorrent = {
      enable = true;
      openFirewall = false;
      webuiPort = config.fleet.apps.qbittorrent.port;
      # Leave serverConfig empty so the WebUI password and save path in
      # /var/lib/qBittorrent survive a switch. Set DefaultSavePath in the
      # UI to /mnt/nfs/media/downloads (runbook).
      extraArgs = [ "--confirm-legal-notice" ];
    };

    systemd.services.qbittorrent = {
      unitConfig.RequiresMountsFor = [ "/mnt/nfs/media" ];
      serviceConfig = {
        MemoryHigh = "640M";
        MemoryMax = "1G";
        ReadWritePaths = [ "/mnt/nfs/media/downloads" ];
      };
    };
  };
}
