{ config, pkgs, ... }:
{
  sops.secrets."vaultwarden/env" = {
    owner = "vaultwarden";
  };

  services.vaultwarden = {
    enable = true;
    dbBackend = "postgresql";
    environmentFile = config.sops.secrets."vaultwarden/env".path;
    config = {
      DOMAIN = "https://vaultwarden.alexmayers.co.za";
    };
  };
  networking.firewall.allowedTCPPorts = [ 8222 ];
}
