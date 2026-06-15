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
      "nfsvers=4.2"
      "_netdev"
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=600"
    ];
  };

  fileSystems."/mnt/nfs/immich/model-cache" = {
    device = "truenas-scale:/mnt/ssd/immich/model-cache";
    fsType = "nfs";
    options = [
      "rw"
      "nfsvers=4.2"
      "_netdev"
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=600"
    ];
  };

  sops.secrets."immich/env" = {
    owner = config.services.immich.user;
  };

  services.immich = {
    enable = true;
    secretsFile = config.sops.secrets."immich/env".path;

    # Defaults to running as user "immich" and group "immich"
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

    mediaLocation = "/var/lib/immich/photos";

    machine-learning.enable = true;
    machine-learning.environment = {
      MACHINE_LEARNING_CACHE_FOLDER = lib.mkForce "/var/lib/immich/model-cache";
    };
    accelerationDevices = [ "/dev/dri/renderD128" ];
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/immich 0750 immich users - -"
    "d /var/lib/immich/photos 0750 immich users - -"
    "d /var/lib/immich/model-cache 0750 immich users - -"
  ];

  systemd.services.immich-server = {
    serviceConfig = {
      RequiresMountsFor = [ "/mnt/nfs/immich/photos" ];
      BindPaths = [ "/mnt/nfs/immich/photos:/var/lib/immich/photos" ];
    };
  };

  systemd.services.immich-machine-learning = {
    serviceConfig = {
      RequiresMountsFor = [ "/mnt/nfs/immich/model-cache" ];
      BindPaths = [ "/mnt/nfs/immich/model-cache:/var/lib/immich/model-cache" ];
    };
  };

  users.users.immich = {
    extraGroups = [
      "video"
      "render"
    ];
  };
}
