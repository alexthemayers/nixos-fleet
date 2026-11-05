{
  host = "truenas-scale";
  port = 80;
  docs = "docs/services/caddy.md";
  dashboard = "fleet-truenas.json";
  edge = {
    domain = "truenas.alexmayers.co.za";
    rateLimit = "heavy";
    auth = "forward";
    waf = false;
    securityHeaders = "loose";
  };
  probe = {
    public = true;
    path = "/ui/";
  };
}
