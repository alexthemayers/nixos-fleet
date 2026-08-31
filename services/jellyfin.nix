{ config, pkgs, ... }:
let
  nfsBase = import ../config/nfs-mount.nix "jellyfin" [ ];
  # Media is read-heavy; large r/w sizes and async keep sequential reads off the NAS fast.
  nfsMediaOpts = nfsBase ++ [
    "rsize=1048576"
    "wsize=1048576"
    "async"
    "noatime"
  ];
  # Config/metadata share this dataset — avoid async so library DB writes are not buffered unsafely.
  nfsConfigOpts = nfsBase ++ [
    "rsize=1048576"
    "wsize=1048576"
    "noatime"
  ];
  # Transcode/HLS cache: original architecture, same opts as media (async, 1 MiB r/w).
  nfsCacheOpts = nfsMediaOpts;
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
    options = nfsMediaOpts;
  };

  fileSystems."/mnt/nfs/jellyfin/config" = {
    device = "truenas-scale:/mnt/ssd/jellyfin/config";
    fsType = "nfs";
    options = nfsConfigOpts;
  };

  fileSystems."/mnt/nfs/jellyfin/cache" = {
    device = "truenas-scale:/mnt/ssd/jellyfin/cache";
    fsType = "nfs";
    options = nfsCacheOpts;
  };

  services.jellyfin = {
    enable = true;
    # openFirewall also opens the DLNA/auto-discovery ports on every interface.
    # Clients reach Jellyfin through Caddy over the tailnet on 8096.
    openFirewall = false;
    # Default cacheDir is /var/cache/jellyfin; BindPaths maps the SSD NFS dataset there.
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
  fleet.waitForHost.jellyfin.host = "truenas-scale";

  systemd.services.jellyfin = {
    unitConfig.RequiresMountsFor = [
      "/mnt/nfs/media"
      "/mnt/nfs/jellyfin/config"
      "/mnt/nfs/jellyfin/cache"
    ];

    serviceConfig = {
      BindPaths = [
        "/mnt/nfs/jellyfin/config:/var/lib/jellyfin"
        "/mnt/nfs/jellyfin/cache:/var/cache/jellyfin"
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
      # Pin transcode throttling. encoding.xml is NFS state the dashboard can
      # edit; a UI uncheck would otherwise survive until someone notices iowait.
      enc=/var/lib/jellyfin/config/encoding.xml
      if [ -f "$enc" ]; then
        ${pkgs.gnused}/bin/sed -i \
          -e 's|<EnableThrottling>[fF]alse</EnableThrottling>|<EnableThrottling>true</EnableThrottling>|' \
          "$enc"
      fi
    '';
  };
}
