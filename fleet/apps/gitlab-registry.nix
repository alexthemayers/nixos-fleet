{
  host = "proxmox-applications-2";
  port = 5005;
  docs = "docs/services/container-registry.md";
  edge = {
    domain = "registry.alexmayers.co.za";
    rateLimit = "ultraHeavy";
    rateLimitZone = "registry";
  };
  probe.public = true;
}
