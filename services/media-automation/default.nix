{
  imports = [
    ./prowlarr.nix
    ./radarr.nix
    ./sonarr.nix
    ./qbittorrent.nix
    ./flaresolverr.nix
  ];

  fleet.waitForHost.media-automation = {
    host = "truenas-scale";
    forServices = [
      "radarr.service"
      "sonarr.service"
      "qbittorrent.service"
    ];
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    7878 # Radarr
    8989 # Sonarr
    9696 # Prowlarr
    8081 # qBittorrent WebUI
    8191 # FlareSolverr (Prowlarr uses 127.0.0.1; tailnet for probe)
  ];
}
