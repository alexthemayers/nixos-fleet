# Data only. Imported by config/fleet-apps.nix on every host so Caddy,
# Prometheus, and the Jellyfin module share one host/port/URL.
{
  host = "proxmox-applications-1";
  port = 8096;
  docs = "docs/services/jellyfin.md";
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
