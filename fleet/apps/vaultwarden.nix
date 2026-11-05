{
  host = "proxmox-applications-debian";
  port = 8222;
  docs = "docs/services/vaultwarden.md";
  module = "services/vaultwarden.nix";
  edge = {
    domain = "vaultwarden.alexmayers.co.za";
    rateLimit = "vaultwarden";
    adminCidrPath = "/admin*";
    flushInterval = "-1";
    healthUri = "/alive";
    healthInterval = "5s";
    healthTimeout = "2s";
    healthStatus = "200";
    failDuration = "10s";
    maxFails = 1;
    unhealthyStatus = "5xx";
  };
  probe.public = true;
}
