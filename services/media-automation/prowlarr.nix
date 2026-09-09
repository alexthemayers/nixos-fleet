{
  services.prowlarr = {
    enable = true;
    openFirewall = false;
  };

  systemd.services.prowlarr.serviceConfig = {
    MemoryHigh = "320M";
    MemoryMax = "384M";
  };
}
