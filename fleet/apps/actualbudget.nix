{
  host = "proxmox-applications-1";
  port = 5006;
  docs = "docs/services/actualbudget.md";
  module = "services/actualbudget.nix";
  unit = "actual";
  edge = {
    domain = "budget.alexmayers.co.za";
    rateLimitZone = "budget";
    auth = "forward";
    waf = false;
  };
  probe.public = true;
}
