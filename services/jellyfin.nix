{ config, pkgs, ... }:
let
  nfsOptions = [
    "rw"
    "nfsvers=4.2"
    "_netdev"
    "noauto"
    "x-systemd.automount"
    "x-systemd.idle-timeout=600"
    "x-systemd.requires=jellyfin-wait-for-nas.service"
    "x-systemd.after=jellyfin-wait-for-nas.service"
  ];
in
{
  fileSystems."/mnt/nfs/media" = {
    device = "truenas-scale:/mnt/hdd/media";
    fsType = "nfs";
    options = nfsOptions;
  };

  fileSystems."/mnt/nfs/jellyfin/config" = {
    device = "truenas-scale:/mnt/ssd/jellyfin/config";
    fsType = "nfs";
    options = nfsOptions;
  };

  fileSystems."/mnt/nfs/jellyfin/cache" = {
    device = "truenas-scale:/mnt/ssd/jellyfin/cache";
    fsType = "nfs";
    options = nfsOptions;
  };

  services.jellyfin = {
    enable = true;
    openFirewall = true;
    # Defaults to running as user "jellyfin" and group "jellyfin"
    # dataDir defaults to /var/lib/jellyfin
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # VA-API driver (iHD) for Broadwell and newer
      intel-compute-runtime # OpenCL runtime (Critical for HDR Tone Mapping)
      vpl-gpu-rt # Intel QuickSync Video (QSV) runtime for Arrow Lake
    ];
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/jellyfin 0700 jellyfin jellyfin - -"
    "d /var/lib/jellyfin/cache 0700 jellyfin jellyfin - -"
  ];

  systemd.services.jellyfin-wait-for-nas = {
    description = "Wait for TrueNAS MagicDNS resolution for Jellyfin";
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    wants = [
      "network-online.target"
      "tailscaled.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "120s";
    };
    script = ''
      for i in {1..120}; do
        if ${pkgs.iputils}/bin/ping -c 1 -W 1 truenas-scale >/dev/null 2>&1; then
          echo "TrueNAS is reachable!"
          exit 0
        fi
        echo "Waiting for MagicDNS..."
        sleep 1
      done
      exit 1
    '';
  };

  systemd.services.jellyfin = {
    unitConfig.RequiresMountsFor = [
      "/mnt/nfs/media"
      "/mnt/nfs/jellyfin/config"
      "/mnt/nfs/jellyfin/cache"
    ];

    serviceConfig = {
      BindPaths = [
        "/mnt/nfs/jellyfin/config:/var/lib/jellyfin"
        "/mnt/nfs/jellyfin/cache:/var/lib/jellyfin/cache"
      ];
      SupplementaryGroups = [
        "render"
        "video"
      ];
      # This is the silver bullet for the shutdown hang:
      TimeoutStopSec = "15s";
      Restart = "on-failure";
      RestartSec = "10s";
    };

    environment = {
      JELLYFIN_PublishedServerUrl = "https://jellyfin.alexmayers.co.za";
    };

    preStart = ''
      # Ensure config directory exists
      mkdir -p /var/lib/jellyfin/config

      # Write JSON Serilog configuration file
      cat << 'EOF' > /var/lib/jellyfin/config/logging.json
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
      EOF
    '';
  };
}
