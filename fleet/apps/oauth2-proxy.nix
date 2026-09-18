{
  host = "xcloud-caddy";
  port = 4180;
  docs = "docs/services/oauth2-proxy.md";
  module = "services/oauth2-proxy.nix";
  edge = {
    domain = "auth.alexmayers.co.za";
    rateLimitZone = "auth";
    upstream = "loopback";
  };
  probe = {
    public = true;
    path = "/ping";
  };
}
