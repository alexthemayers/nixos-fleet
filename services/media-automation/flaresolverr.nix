{
  services.flaresolverr = {
    enable = true;
    openFirewall = false;
    port = 8191;
  };

  # Headless Chromium. 1G max dropped sessions during 1337x
  # solves (docs/memory.md).
  systemd.services.flaresolverr.serviceConfig = {
    MemoryHigh = "1G";
    MemoryMax = "2G";
  };
}
