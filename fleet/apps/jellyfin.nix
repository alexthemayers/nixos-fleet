{
  host = "proxmox-applications-debian";
  port = 8096;
  docs = "docs/services/jellyfin.md";
  module = "services/jellyfin";
  edge = {
    domain = "jellyfin.alexmayers.co.za";
    rateLimit = "ultraHeavy";
    flushInterval = "-1";
    dialTimeout = "15s";
    wafBypassPaths = [
      "/videos/*"
      "/Items/*"
      "/Audio/*"
      "/hls/*"
      "/stream/*"
      "/socket*"
    ];
    wafBypassWebsockets = true;
  };
  probe = {
    public = true;
    path = "/web/";
  };
}
