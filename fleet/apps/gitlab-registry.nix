{
  host = "proxmox-gitlab-debian";
  port = 5005;
  docs = "docs/services/container-registry.md";
  module = "services/gitlab.nix";
  edge = {
    domain = "registry.alexmayers.co.za";
    rateLimit = "ultraHeavy";
    rateLimitZone = "registry";
  };
  probe.public = true;
}
