{
  services.postgresql = {
    enable = true;
    ensureDatabases = [ "vaultwarden" ];
    ensureUsers = [{
      name = "vaultwarden";
      ensureDBOwnership = true;
    }];
  };

  services.vaultwarden = {
    enable = true;
    dbBackend = "postgresql";
    config = {
      DOMAIN = "https://vaultwarden.alexmayers.co.za";
      ROCKET_ADDRESS = "0.0.0.0";
      ROCKET_PORT = 8088;
      DATABASE_URL = "postgresql:///vaultwarden?host=/run/postgresql";
    };
  };
  networking.firewall.allowedTCPPorts = [ 8088 ];
}