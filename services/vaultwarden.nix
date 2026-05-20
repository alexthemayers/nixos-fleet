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
      ROCKET_PORT = 8222;
      ROCKET_ADDRESS = "0.0.0.0";
      SIGNUPS_ALLOWED = true;
    };
  };
}
