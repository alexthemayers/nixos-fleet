{
  host = "proxmox-applications-debian";
  port = 28981;
  docs = "docs/services/paperless.md";
  module = "services/paperless.nix";
  edge = {
    domain = "paperless.alexmayers.co.za";
    auth = "forward";
    waf = false;
    lbTryDuration = "5s";
    healthUri = "/accounts/login/";
    healthInterval = "10s";
    healthTimeout = "5s";
    healthStatus = "2xx";
    failDuration = "30s";
    maxFails = 1;
    unhealthyStatus = "5xx";
  };
  probe = {
    public = true;
    path = "/accounts/login/";
  };
}
