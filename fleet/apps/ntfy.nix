{
  host = "proxmox-observability";
  port = 2586;
  docs = "docs/services/ntfy.md";
  dashboard = "fleet-ntfy.json";
  edge = {
    domain = "ntfy.alexmayers.co.za";
    lbTryDuration = "5s";
    healthUri = "/v1/health";
    healthInterval = "5s";
    healthTimeout = "2s";
    healthStatus = "200";
    failDuration = "10s";
    maxFails = 1;
    unhealthyStatus = "5xx";
  };
  probe.public = true;
}
