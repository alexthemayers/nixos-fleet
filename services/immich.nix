{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf config.fleet.appOnThisHost.immich {
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
      options = import ../config/nfs-mount.nix "immich" [ ];
    };

    fileSystems."/mnt/nfs/immich/model-cache" = {
      device = "truenas-scale:/mnt/ssd/immich/model-cache";
      fsType = "nfs";
      options = import ../config/nfs-mount.nix "immich" [ ];
    };

    sops.secrets."immich/env" = {
      owner = config.services.immich.user;
      restartUnits = [ "immich-server.service" ];
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
      2283 # Immich (edge Caddy reverse_proxy)
    ];

    services.immich = {
      enable = true;
      secretsFile = config.sops.secrets."immich/env".path;

      # Defaults to running as user "immich" and group "immich"
      host = "0.0.0.0";

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

      machine-learning.environment = {
        MACHINE_LEARNING_CACHE_FOLDER = lib.mkForce "/var/lib/immich/model-cache";
        # ArmNN is not used on this host; leave OpenVINO off this unit
        # (no /dev/dri below) so ORT uses CPU instead of compiling for
        # the iGPU and 500ing every OCR/face job.
        MACHINE_LEARNING_ANN = "false";
      };
      accelerationDevices = [ "/dev/dri/renderD128" ];
    };
    systemd.tmpfiles.rules = [
      "d /var/lib/immich 0750 immich users - -"
      "d /var/lib/immich/photos 0750 immich users - -"
      "d /var/lib/immich/model-cache 0750 immich users - -"
    ];

    fleet.waitForHost.immich.host = "truenas-scale";
    fleet.waitFor.postgres.immich.forServices = [
      "immich-server.service"
      "immich-machine-learning.service"
    ];

    # Upstream sets Restart = "always" for both units. Narrowing that to
    # "on-failure" meant a clean exit(0) - which Immich does on some shutdown
    # paths - left the service stopped until someone noticed.
    systemd.services.immich-server = {
      serviceConfig = {
        RequiresMountsFor = [ "/mnt/nfs/immich/photos" ];
        BindPaths = [ "/mnt/nfs/immich/photos:/var/lib/immich/photos" ];
        RestartSec = lib.mkForce "10s";
      };
    };

    systemd.services.immich-machine-learning = {
      serviceConfig = {
        RequiresMountsFor = [ "/mnt/nfs/immich/model-cache" ];
        # Drop the iGPU bind from accelerationDevices. OpenVINO sees
        # renderD128, fails to compile on this Xe, and every ML request
        # 500s until gunicorn SIGINTs the worker.
        BindPaths = lib.mkForce [ "/mnt/nfs/immich/model-cache:/var/lib/immich/model-cache" ];
        DeviceAllow = lib.mkForce [ ];
        PrivateDevices = lib.mkForce true;
        # gunicorn writes $HOME/.gunicorn; DynamicUser HOME is /var/empty.
        Environment = [ "HOME=/var/lib/immich/model-cache" ];
        RestartSec = lib.mkForce "10s";
      };
    };

    users.users.immich = {
      extraGroups = [
        "video"
        "render"
      ];
    };

    fleet.alwaysRestart = [
      "immich-server"
      "immich-machine-learning"
    ];
  };
}
