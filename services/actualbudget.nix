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
      "x-systemd.requires=actual-wait-for-nas.service"
      "x-systemd.after=actual-wait-for-nas.service"
    ];
  };

  systemd.services.actual-wait-for-nas = {
    description = "Wait for TrueNAS MagicDNS resolution for Actualbudget";
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    wants = [
      "network-online.target"
      "tailscaled.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "120s";
    };
    script = ''
      for i in {1..120}; do
        if ${pkgs.iputils}/bin/ping -c 1 -W 1 truenas-scale >/dev/null 2>&1; then
          echo "TrueNAS is reachable!"
          exit 0
        fi
        echo "Waiting for MagicDNS..."
        sleep 1
      done
      exit 1
    '';
  };

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
