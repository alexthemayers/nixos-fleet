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
      BindPaths = [ "/mnt/nfs/immich/model-cache:/var/lib/immich/model-cache" ];
      RestartSec = lib.mkForce "10s";
    };
  };

  users.users.immich = {
    extraGroups = [
      "video"
      "render"
    ];
  };
}
