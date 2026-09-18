{
  host = "proxmox";
  port = 8006;
  docs = "docs/services/proxmox-host.md";
  dashboard = "fleet-hardware.json";
  edge = {
    domain = "proxmox.alexmayers.co.za";
    auth = "forward";
    waf = false;
    upstreamTls = true;
    tlsInsecure = true;
    securityHeaders = "loose";
  };
  probe.public = true;
}
