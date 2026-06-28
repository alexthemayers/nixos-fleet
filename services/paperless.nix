{
  config,
  pkgs,
  lib,
  ...
}:
{
  sops.secrets."postgres/paperless_password" = {
    owner = "paperless";
    group = "paperless";
  };

  sops.secrets."paperless/admin_password" = {
    owner = "paperless";
    group = "paperless";
  };

  sops.secrets."paperless/client_secret" = {
    owner = "paperless";
    group = "paperless";
  };

  sops.templates."paperless.env" = {
    owner = "paperless";
    group = "paperless";
    content = ''
      PAPERLESS_DBPASS="${config.sops.placeholder."postgres/paperless_password"}"
      PAPERLESS_SOCIALACCOUNT_PROVIDERS='{"openid_connect": {"APPS": [{"provider_id": "keycloak", "name": "Keycloak", "client_id": "paperless", "secret": "${
        config.sops.placeholder."paperless/client_secret"
      }", "settings": {"server_url": "https://identity.alexmayers.co.za/realms/master/.well-known/openid-configuration"}}]}}'
    '';
  };

  fileSystems."/mnt/nfs/paperless" = {
    device = "truenas-scale:/mnt/ssd/paperless";
    fsType = "nfs";
    options = [
      "nfsvers=4.2"
      "_netdev"
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=600"
      "x-systemd.requires=wait-for-host-paperless.service"
      "x-systemd.after=wait-for-host-paperless.service"
    ];
  };

  fleet.waitForHost.paperless.host = "truenas-scale";

  systemd.services.paperless-consumer.serviceConfig.RequiresMountsFor = [ "/mnt/nfs/paperless" ];
  systemd.services.paperless-scheduler.serviceConfig.RequiresMountsFor = [ "/mnt/nfs/paperless" ];
  systemd.services.paperless-task-queue.serviceConfig.RequiresMountsFor = [ "/mnt/nfs/paperless" ];
  systemd.services.paperless-web.serviceConfig.RequiresMountsFor = [ "/mnt/nfs/paperless" ];

  systemd.services.paperless-create-dirs = {
    description = "Create Paperless directories on NFS mount";
    requires = [ "mnt-nfs-paperless.mount" ];
    after = [ "mnt-nfs-paperless.mount" ];
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

  systemd.services.paperless-consumer.after = [ "paperless-create-dirs.service" ];
  systemd.services.paperless-scheduler.after = [ "paperless-create-dirs.service" ];
  systemd.services.paperless-task-queue.after = [ "paperless-create-dirs.service" ];
  systemd.services.paperless-web.after = [ "paperless-create-dirs.service" ];

  systemd.services.paperless-consumer.wants = [ "paperless-create-dirs.service" ];
  systemd.services.paperless-scheduler.wants = [ "paperless-create-dirs.service" ];
  systemd.services.paperless-task-queue.wants = [ "paperless-create-dirs.service" ];
  systemd.services.paperless-web.wants = [ "paperless-create-dirs.service" ];

  services.paperless = {
    enable = true;
    dataDir = "/mnt/nfs/paperless";
    address = "0.0.0.0";
    port = 28981;
    passwordFile = config.sops.secrets."paperless/admin_password".path;
    environmentFile = config.sops.templates."paperless.env".path;

    settings = {
      PAPERLESS_URL = "https://paperless.alexmayers.co.za";
      PAPERLESS_TRUSTED_PROXIES = "100.64.0.0/10";

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
}
