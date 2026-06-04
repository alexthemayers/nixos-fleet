{ config, pkgs, ... }:
let
  nfsOptions = [
    "rw"
    "nfsvers=4.1"
    "_netdev"
    "noauto"
    "x-systemd.automount"
    "x-systemd.idle-timeout=600"
    "x-systemd.mount-timeout=30"
    "x-systemd.device-timeout=5s"
    "x-systemd.requires=wait-for-nas.service"
    "x-systemd.after=wait-for-nas.service"
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
    user = "containers";
    group = "nogroup";
    dataDir = "/mnt/nfs/jellyfin/config";
    cacheDir = "/mnt/nfs/jellyfin/cache";
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # VA-API driver (iHD) for Broadwell and newer
      intel-compute-runtime # OpenCL runtime (Critical for HDR Tone Mapping)
      vpl-gpu-rt # Intel QuickSync Video (QSV) runtime for Arrow Lake
    ];
  };
  systemd.network.wait-online.enable = true;
  systemd.services.wait-for-nas = {
    description = "Wait for TrueNAS to be reachable";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "15s";
    };
    script = ''
      set +e
      while ! ${pkgs.iputils}/bin/ping -c 1 -W 1 truenas-scale >/dev/null 2>&1; do
        echo "Waiting for truenas-scale..."
        sleep 2
      done
      echo "NAS is reachable!"
    '';
  };
  systemd.services.jellyfin = {
    unitConfig.RequiresMountsFor = [
      "/mnt/nfs/media"
      "/mnt/nfs/jellyfin/config"
      "/mnt/nfs/jellyfin/cache"
    ];

    serviceConfig = {
      SupplementaryGroups = [
        "render"
        "video"
      ];
      # This is the silver bullet for the shutdown hang:
      TimeoutStopSec = "15s";
    };

    environment = {
      JELLYFIN_PublishedServerUrl = "https://jellyfin.alexmayers.co.za";
    };

    preStart = ''
      # Ensure config directory exists
      mkdir -p /mnt/nfs/jellyfin/config/config

      # Write JSON Serilog configuration file
      cat << 'EOF' > /mnt/nfs/jellyfin/config/config/logging.json
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
