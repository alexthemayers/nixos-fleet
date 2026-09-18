{
  host = "proxmox-applications-1";
  port = 30000;
  docs = "docs/services/luanti.md";
  module = "services/luanti.nix";
  unit = "minetest-server";
  udp.listenPort = 30000;
}
