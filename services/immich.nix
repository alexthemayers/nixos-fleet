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
    device = "truenas-scale:/mnt/hdd/photos";
    fsType = "nfs";
    options = [
      "rw"
      "nfsvers=4.1"
      "x-systemd.automount"
      "noauto"
      "_netdev"
      "x-systemd.mount-timeout=30"
      "x-systemd.device-timeout=5s"
      "x-systemd.requires=wait-for-nas.service"
      "x-systemd.after=wait-for-nas.service"
    ];
  };

  fileSystems."/mnt/nfs/immich/model-cache" = {
    device = "truenas-scale:/mnt/ssd/immich/model-cache";
    fsType = "nfs";
    options = [
      "rw"
      "nfsvers=4.1"
      "x-systemd.automount"
      "noauto"
      "_netdev"
      "x-systemd.mount-timeout=30"
      "x-systemd.device-timeout=5s"
      "x-systemd.requires=wait-for-nas.service"
      "x-systemd.after=wait-for-nas.service"
    ];
  };

  sops.secrets."immich/env" = {
    owner = "immich";
  };

  services.immich = {
    enable = true;
    secretsFile = config.sops.secrets."immich/env".path;

    user = "containers";
    group = "users";
    host = "0.0.0.0";
    port = 2283;

    environment = {
      IMMICH_LOG_FORMAT = "json";
    };

    database = {
      enable = true;
      host = "xcloud-postgres";
      port = 5432;
      user = "immich";
    };

    mediaLocation = "/mnt/nfs/immich/photos";

    machine-learning.enable = true;
    machine-learning.environment = {
      MACHINE_LEARNING_CACHE_FOLDER = lib.mkForce "/mnt/nfs/immich/model-cache";
    };
    accelerationDevices = [ "/dev/dri/renderD128" ];
  };
  users.groups.immich = { };
  users.users.immich = {
    group = "users";
    extraGroups = [
      "video"
      "render"
    ];
    isSystemUser = true;
  };
}
