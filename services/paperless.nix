{
  config,
  pkgs,
  lib,
  ...
}:
let
  # services.paperless splits into several units and hands the same
  # environmentFile to each, so a rotated credential has to restart all of them
  # or the ones left behind keep using the old value.
  paperlessUnits = [
    "paperless-web.service"
    "paperless-consumer.service"
    "paperless-scheduler.service"
    "paperless-task-queue.service"
  ];
in
{
  sops.secrets."postgres/paperless_password" = {
    owner = "paperless";
    group = "paperless";
    restartUnits = paperlessUnits;
  };

  sops.secrets."paperless/admin_password" = {
    owner = "paperless";
    group = "paperless";
    restartUnits = paperlessUnits;
  };

  sops.secrets."paperless/client_secret" = {
    owner = "paperless";
    group = "paperless";
    restartUnits = paperlessUnits;
  };

  sops.secrets."redis/paperless_password" = {
    owner = "paperless";
    group = "paperless";
    restartUnits = paperlessUnits;
  };

  sops.templates."paperless.env" = {
    owner = "paperless";
    group = "paperless";
    restartUnits = paperlessUnits;
    content = ''
      PAPERLESS_DBPASS="${config.sops.placeholder."postgres/paperless_password"}"
      PAPERLESS_REDIS="redis://:${
        config.sops.placeholder."redis/paperless_password"
      }@xcloud-postgres:6381"
      PAPERLESS_SOCIALACCOUNT_PROVIDERS='{"openid_connect": {"APPS": [{"provider_id": "keycloak", "name": "Keycloak", "client_id": "paperless", "secret": "${
        config.sops.placeholder."paperless/client_secret"
      }", "settings": {"server_url": "https://identity.alexmayers.co.za/realms/master/.well-known/openid-configuration"}}]}}'
    '';
  };

  fileSystems."/mnt/nfs/paperless" = {
    device = "truenas-scale:/mnt/ssd/paperless";
    fsType = "nfs";
    options = import ../config/nfs-mount.nix "paperless" [ ];
  };

  fleet.waitForHost.paperless.host = "truenas-scale";
  fleet.waitFor.postgres.paperless.forServices = [
    "paperless-web.service"
    "paperless-consumer.service"
    "paperless-scheduler.service"
    "paperless-task-queue.service"
  ];
  fleet.waitForHost.paperless-redis = {
    host = "xcloud-postgres";
    port = 6381;
    forServices = [
      "paperless-web.service"
      "paperless-consumer.service"
      "paperless-scheduler.service"
      "paperless-task-queue.service"
    ];
  };

  systemd.services.paperless-consumer.unitConfig.RequiresMountsFor = [ "/mnt/nfs/paperless" ];
  systemd.services.paperless-scheduler.unitConfig.RequiresMountsFor = [ "/mnt/nfs/paperless" ];
  # The schedule database has to outlive the process. /var/tmp is private and
  # discarded per-unit because PrivateTmp is set, so beat re-derived its
  # schedule from scratch on every restart. Keep it next to the rest of the
  # Paperless state on NFS; /var/lib/paperless is not created for this host
  # because dataDir is the NFS mount.
  systemd.services.paperless-scheduler.serviceConfig.ExecStart =
    lib.mkForce "${config.services.paperless.package}/bin/celery --app paperless beat --loglevel INFO --schedule ${config.services.paperless.dataDir}/celerybeat-schedule";
  systemd.services.paperless-task-queue.unitConfig.RequiresMountsFor = [ "/mnt/nfs/paperless" ];
  systemd.services.paperless-web.unitConfig.RequiresMountsFor = [ "/mnt/nfs/paperless" ];

  systemd.services.paperless-create-dirs = {
    description = "Create Paperless directories on NFS mount";
    requires = [ "mnt-nfs-paperless.mount" ];
    after = [
      "mnt-nfs-paperless.mount"
      "nscd.service"
    ];
    before = [
      "paperless-consumer.service"
      "paperless-scheduler.service"
      "paperless-task-queue.service"
      "paperless-web.service"
    ];
    wantedBy = [
      "paperless-consumer.service"
      "paperless-scheduler.service"
      "paperless-task-queue.service"
      "paperless-web.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "paperless";
      Group = "paperless";
    };
    script = ''
      mkdir -p /mnt/nfs/paperless/consume /mnt/nfs/paperless/media
    '';
  };

  systemd.services.paperless-consumer.after = [
    "paperless-create-dirs.service"
    "nscd.service"
  ];
  systemd.services.paperless-scheduler.after = [
    "paperless-create-dirs.service"
    "nscd.service"
  ];
  systemd.services.paperless-task-queue.after = [
    "paperless-create-dirs.service"
    "nscd.service"
  ];
  systemd.services.paperless-web.after = [
    "paperless-create-dirs.service"
    "nscd.service"
  ];

  systemd.services.paperless-consumer.wants = [ "paperless-create-dirs.service" ];
  systemd.services.paperless-scheduler.wants = [ "paperless-create-dirs.service" ];
  systemd.services.paperless-task-queue.wants = [ "paperless-create-dirs.service" ];
  systemd.services.paperless-web.wants = [ "paperless-create-dirs.service" ];

  # Local redis-paperless is disabled (Redis is on xcloud-postgres:6381). The
  # nixpkgs module still sets SupplementaryGroups=redis-paperless, and systemd
  # fails the units with 216/GROUP because that group does not exist.
  systemd.services.paperless-web.serviceConfig.SupplementaryGroups = lib.mkForce [ ];
  systemd.services.paperless-consumer.serviceConfig.SupplementaryGroups = lib.mkForce [ ];
  systemd.services.paperless-scheduler.serviceConfig.SupplementaryGroups = lib.mkForce [ ];
  systemd.services.paperless-task-queue.serviceConfig.SupplementaryGroups = lib.mkForce [ ];
  systemd.services.paperless-create-dirs.serviceConfig.SupplementaryGroups = lib.mkForce [ ];

  services.paperless = {
    enable = true;
    dataDir = "/mnt/nfs/paperless";
    address = "0.0.0.0";
    passwordFile = config.sops.secrets."paperless/admin_password".path;
    environmentFile = config.sops.templates."paperless.env".path;

    settings = {
      PAPERLESS_URL = "https://paperless.alexmayers.co.za";
      PAPERLESS_TRUSTED_PROXIES = "100.64.0.0/10";

      # PAPERLESS_REDIS is set in paperless.env because it embeds a password.

      # Database Configuration
      PAPERLESS_DBHOST = "xcloud-postgres";
      PAPERLESS_DBPORT = 5432;
      PAPERLESS_DBNAME = "paperless";
      PAPERLESS_DBUSER = "paperless";

      # Keycloak SSO OIDC Configuration
      PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
      PAPERLESS_SOCIALACCOUNT_ALLOW_SIGNUPS = "true";
      PAPERLESS_SOCIALACCOUNT_EMAIL_VERIFICATION = "none";
      PAPERLESS_SOCIALACCOUNT_AUTO_SIGNUP = "true";
    };
  };

  services.redis.servers.paperless.enable = lib.mkForce false;

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    28981 # paperless-web (edge Caddy reverse_proxy)
  ];
}
