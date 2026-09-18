{
  host = "proxmox-applications-1";
  port = 3456;
  docs = "docs/services/vikunja.md";
  edge = {
    domain = "tasks.alexmayers.co.za";
    rateLimitZone = "tasks";
    lbTryDuration = "5s";
    healthUri = "/api/v1/info";
    healthInterval = "5s";
    healthTimeout = "2s";
    healthStatus = "200";
    failDuration = "10s";
    maxFails = 1;
    unhealthyStatus = "5xx";
  };
  probe.public = true;
}
