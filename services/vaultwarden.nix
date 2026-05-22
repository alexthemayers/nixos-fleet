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
      # https://github.com/dani-garcia/vaultwarden/blob/1.36.0/.env.template
      DOMAIN = "https://vaultwarden.alexmayers.co.za";
      ROCKET_PORT = 8222;
      ROCKET_ADDRESS = "0.0.0.0";
      SIGNUPS_ALLOWED = false;
      EXPERIMENTAL_CLIENT_FEATURE_FLAGS = "ssh-key-vault-item,ssh-agent";
    };
  };
}
