{
  host = "proxmox-dev";
  port = 7080;
  docs = "docs/services/coder.md";
  module = "services/coder.nix";
  edge = {
    domain = "coder.alexmayers.co.za";
    rateLimit = "heavy";
  };
  probe.public = true;
}
