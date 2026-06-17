{
  config,
  pkgs,
  lib,
  ...
}:
{
  users.users.actual = {
    group = "actual";
    isSystemUser = true;
  };
  users.groups.actual = { };
  sops.secrets."actualbudget/client_secret" = {
    owner = "actual";
  };
  fileSystems."/mnt/nfs/actualbudget" = {
    device = "truenas-scale:/mnt/ssd/actualbudget";
    fsType = "nfs";
    options = [
      "nfsvers=4.2"
      "_netdev"
      "x-systemd.automount"
      "x-systemd.idle-timeout=600"
    ];
  };

  systemd.services.actual = {
    serviceConfig = {
      RequiresMountsFor = [ "/mnt/nfs/actualbudget" ];
      BindPaths = [ "/mnt/nfs/actualbudget:/var/lib/private/actual" ];
    };
  };
  services.actual = {
    enable = true;
    settings = {
      port = 5006;

      openId = {
        discoveryURL = "https://identity.alexmayers.co.za/realms/master/.well-known/openid-configuration";
        client_id = "actualbudget";

        client_secret._secret = config.sops.secrets."actualbudget/client_secret".path;

        server_hostname = "https://budget.alexmayers.co.za";
        authMethod = "openid";
      };
    };
  };
}
