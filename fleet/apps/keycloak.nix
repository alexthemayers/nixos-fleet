{
  host = "proxmox-applications-1";
  port = 7777;
  docs = "docs/services/keycloak.md";
  module = "services/keycloak.nix";
  edge = {
    domain = "identity.alexmayers.co.za";
    rateLimitZone = "identity";
    adminCidrPath = "/admin*";
    lbTryDuration = "5s";
    healthUri = "/health/ready";
    healthPort = 9000;
    healthInterval = "5s";
    healthTimeout = "2s";
    healthStatus = "2xx";
    failDuration = "10s";
    maxFails = 3;
  };
  probe = {
    public = true;
    path = "/realms/master/.well-known/openid-configuration";
  };
}
