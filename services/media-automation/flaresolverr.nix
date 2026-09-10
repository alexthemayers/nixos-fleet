{
  services.flaresolverr = {
    enable = true;
    openFirewall = false;
    port = 8191;
  };

  # Headless Chromium. Check live RSS before raising
  # (docs/memory.md).
  systemd.services.flaresolverr.serviceConfig = {
    MemoryHigh = "768M";
    MemoryMax = "1G";
  };
}
