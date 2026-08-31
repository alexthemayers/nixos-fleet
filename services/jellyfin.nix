{ config, pkgs, ... }:
let
  nfsOpts = import ../config/nfs-mount.nix "jellyfin" [
    "rsize=1048576"
    "wsize=1048576"
    "async"
    "noatime"
  ];
  loggingJson = pkgs.writeText "jellyfin-logging.json" ''
    {
      "Serilog": {
        "MinimumLevel": {
          "Default": "Information",
          "Override": {
            "Microsoft": "Warning",
            "System": "Warning"
          }
        },
        "WriteTo": [
          {
            "Name": "Console",
            "Args": {
              "outputTemplate": "{{\"time\":\"{Timestamp:o}\",\"level\":\"{Level}\",\"message\":\"{Message:lj}\",\"context\":\"{SourceContext}\",\"exception\":\"{Exception}\"}}{NewLine}"
            }
          }
        ],
        "Enrich": [
          "FromLogContext",
          "WithMachineName",
          "WithThreadId"
        ]
      }
    }
  '';
in
{
  fileSystems."/mnt/nfs/media" = {
    device = "truenas-scale:/mnt/hdd/media";
    fsType = "nfs";
    options = nfsOpts;
  };

  fileSystems."/mnt/nfs/jellyfin/config" = {
    device = "truenas-scale:/mnt/ssd/jellyfin/config";
    fsType = "nfs";
    options = nfsOpts;
  };



  services.jellyfin = {
    enable = true;
    # openFirewall also opens the DLNA/auto-discovery ports on every interface.
    # Clients reach Jellyfin through Caddy over the tailnet on 8096.
    openFirewall = false;
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    8096 # Jellyfin (caddy-internal reverse_proxy)
  ];

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-compute-runtime
      vpl-gpu-rt
    ];
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/jellyfin 0700 jellyfin jellyfin - -"
    "d /var/lib/jellyfin/cache 0700 jellyfin jellyfin - -"
  ];

  fleet.waitForHost.jellyfin.host = "truenas-scale";

  systemd.services.jellyfin = {
    unitConfig.RequiresMountsFor = [
      "/mnt/nfs/media"
      "/mnt/nfs/jellyfin/config"
    ];

    serviceConfig = {
      BindPaths = [
        "/mnt/nfs/jellyfin/config:/var/lib/jellyfin"
        "/mnt/nfs/media:/media"
      ];
      BindReadOnlyPaths = [
        "${loggingJson}:/var/lib/jellyfin/config/logging.json"
      ];
      SupplementaryGroups = [
        "render"
        "video"
      ];
      TimeoutStopSec = "15s";
      Restart = "on-failure";
      RestartSec = "10s";
    };

    environment = {
      JELLYFIN_PublishedServerUrl = "https://jellyfin.alexmayers.co.za";
    };

    preStart = ''
      mkdir -p /var/lib/jellyfin/config
    '';
  };
}
