{
  host = "proxmox-applications-1";
  port = 2283;
  docs = "docs/services/immich.md";
  module = "services/immich.nix";
  edge = {
    domain = "immich.alexmayers.co.za";
    rateLimit = "ultraHeavy";
    flushInterval = "-1";
    lbTryDuration = "45s";
    lbTryInterval = "250ms";
    dialTimeout = "2s";
    wafBypassPaths = [
      "/api/assets/*"
      "/api/media/*"
      "/socket*"
    ];
    wafBypassWebsockets = true;
  };
  probe.public = true;
}
