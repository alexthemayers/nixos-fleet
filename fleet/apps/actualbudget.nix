{
  host = "proxmox-applications-debian";
  port = 5006;
  docs = "docs/services/actualbudget.md";
  module = null;
  unit = "actual";
  edge = {
    domain = "budget.alexmayers.co.za";
    rateLimitZone = "budget";
    auth = "forward";
    waf = false;
  };
  probe.public = true;
}
