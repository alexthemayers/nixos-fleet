{ config, lib, ... }:
{
  imports = [
    ./prowlarr.nix
    ./radarr.nix
    ./sonarr.nix
    ./qbittorrent.nix
    ./flaresolverr.nix
    ./bazarr.nix
  ];

  config = lib.mkIf config.fleet.appOnThisHost.radarr {
    fleet.waitForHost.media-automation = {
      host = "truenas-scale";
      forServices = [
        "radarr.service"
        "sonarr.service"
        "qbittorrent.service"
        "bazarr.service"
      ];
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
      config.fleet.apps.radarr.port
      config.fleet.apps.sonarr.port
      config.fleet.apps.prowlarr.port
      config.fleet.apps.qbittorrent.port
      config.fleet.apps.flaresolverr.port
      config.fleet.apps.bazarr.port
    ];

    fleet.alwaysRestart = [
      "radarr"
      "sonarr"
      "prowlarr"
      "qbittorrent"
      "flaresolverr"
      "bazarr"
    ];
  };
}
