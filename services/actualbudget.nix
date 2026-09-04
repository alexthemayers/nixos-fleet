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
    restartUnits = [ "actual.service" ];
  };
  fileSystems."/mnt/nfs/actualbudget" = {
    device = "truenas-scale:/mnt/ssd/actualbudget";
    fsType = "nfs";
    options = import ../config/nfs-mount.nix "actualbudget" [ ];
  };

  fleet.waitForHost.actualbudget.host = "truenas-scale";

  systemd.services.actual = {
    serviceConfig = {
      RequiresMountsFor = [ "/mnt/nfs/actualbudget" ];
      BindPaths = [ "/mnt/nfs/actualbudget:/var/lib/private/actual" ];
      Restart = lib.mkForce "on-failure";
      RestartSec = lib.mkForce "10s";
    };
  };
  services.actual = {
    enable = true;
    settings = {
      # nixpkgs default is 3000; caddy-internal and the tailscale0 hole are 5006.
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

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    5006 # Actual Budget (caddy-internal reverse_proxy)
  ];
}
