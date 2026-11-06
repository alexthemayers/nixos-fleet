{
  host = "proxmox-gitlab-debian";
  port = 5005;
  docs = "docs/services/container-registry.md";
  module = null;
  edge = {
    domain = "registry.alexmayers.co.za";
    rateLimit = "ultraHeavy";
    rateLimitZone = "registry";
  };
  probe.public = true;
}
