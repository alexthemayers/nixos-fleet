{
  config,
  pkgs,
  lib,
  ...
}:
{
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-compute-runtime
      intel-vaapi-driver
    ];
  };

  fileSystems."/mnt/nfs/immich/photos" = {
    device = "truenas-scale.bee-phrygian.ts.net:/mnt/hdd/photos";
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

  fileSystems."/mnt/nfs/code" = {
    device = "truenas-scale.bee-phrygian.ts.net:/mnt/ssd/code";
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

  fileSystems."/mnt/nfs/immich/model-cache" = {
    device = "truenas-scale.bee-phrygian.ts.net:/mnt/ssd/immich/model-cache";
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

  services.immich = {
    enable = true;

    host = "0.0.0.0";
    port = 2283;

    mediaLocation = "/mnt/nfs/immich/photos";

    machine-learning.enable = true;
    machine-learning.environment = {
      MACHINE_LEARNING_CACHE_FOLDER = lib.mkForce "/mnt/nfs/immich/model-cache";
    };
    accelerationDevices = [ "/dev/dri/renderD128" ];
  };
  users.users.immich.extraGroups = [
    "video"
    "render"
  ];
}
