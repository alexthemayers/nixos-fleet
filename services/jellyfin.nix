{ config, pkgs, ... }:

{
  fileSystems."/mnt/nfs/music" = {
    device = "192.168.3.101:/mnt/hdd/music";
    fsType = "nfs";
    options = [
      "rw"
      "nfsvers=4.1"
      "x-systemd.automount"
      "noauto"
      "_netdev"
      "x-systemd.mount-timeout=30"
      "x-systemd.requires=wait-for-nas.service"
      "x-systemd.after=wait-for-nas.service"
    ];
  };

  fileSystems."/mnt/nfs/media" = {
    device = "192.168.3.101:/mnt/hdd/media";
    fsType = "nfs";
    options = [
      "rw"
      "nfsvers=4.1"
      "x-systemd.automount"
      "noauto"
      "_netdev"
      "x-systemd.mount-timeout=30"
      "x-systemd.requires=wait-for-nas.service"
      "x-systemd.after=wait-for-nas.service"
    ];
  };

  fileSystems."/mnt/nfs/jellyfin/config" = {
    device = "192.168.3.101:/mnt/ssd/jellyfin/config";
    fsType = "nfs";
    options = [
      "rw"
      "nfsvers=4.1"
      "x-systemd.automount"
      "noauto"
      "_netdev"
      "x-systemd.mount-timeout=30"
      "x-systemd.requires=wait-for-nas.service"
      "x-systemd.after=wait-for-nas.service"
    ];
  };

  fileSystems."/mnt/nfs/jellyfin/cache" = {
    device = "192.168.3.101:/mnt/ssd/jellyfin/cache";
    fsType = "nfs";
    options = [
      "rw"
      "nfsvers=4.1"
      "x-systemd.automount"
      "noauto"
      "_netdev"
      "x-systemd.mount-timeout=30"
      "x-systemd.requires=wait-for-nas.service"
      "x-systemd.after=wait-for-nas.service"
    ];
  };

  services.jellyfin = {
    enable = true;
    openFirewall = true;
    user = "containers";
    group = "nogroup";
    dataDir = "/mnt/nfs/jellyfin/config";
    cacheDir = "/mnt/nfs/jellyfin/cache";
  };

  systemd.tmpfiles.rules = [
    "L+ /cache  - - - - /mnt/nfs/jellyfin/cache"
    "L+ /config - - - - /mnt/nfs/jellyfin/config"
    "L+ /media  - - - - /mnt/nfs/media"
  ];

  hardware.graphics.enable = true;
  systemd.network.wait-online.enable = true;
  systemd.network.wait-online.extraArgs = [ "--interface=ens18" ];
  systemd.services.wait-for-nas = {
    description = "Wait for TrueNAS to be reachable";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set +e
      while ! ${pkgs.iputils}/bin/ping -c 1 -W 1 192.168.3.101 >/dev/null 2>&1; do
        echo "Waiting for 192.168.3.101..."
        sleep 2
      done
      echo "NAS is reachable!"
    '';
  };
  systemd.services.jellyfin = {
    # after = [ "network-online.target" "tailscaled.service" ];
    after = [
      "network-online.target"
      "wait-for-nas.service"
    ];
    wants = [
      "network-online.target"
      "wait-for-nas.service"
    ];
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
      BindPaths = [
        "/cache"
        "/config"
        "/media"
      ];
    };

    environment = {
      JELLYFIN_PublishedServerUrl = "https://jellyfin.alexmayers.co.za";
    };
  };
}
