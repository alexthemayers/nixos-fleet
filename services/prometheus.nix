{
  services.prometheus = {
    enable = true;
    port = 9090;

    globalConfig.scrape_interval = "5s";
    scrapeConfigs = [
      {
        job_name = "caddy";
        static_configs = [
          {
            targets = [
              "xcloud-caddy:2019"
            ];
          }
        ];
      }
      {
        job_name = "prometheus";
        static_configs = [
          {
            targets = [
              "proxmox-observability:9090"
            ];
          }
        ];
      }
      {
        job_name = "postgres";
        static_configs = [
          {
            targets = [
              "xcloud-postgres:9187"
            ];
          }
        ];
      }
      {
        job_name = "node exporter";
        static_configs = [
          {
            targets = [
              "m3pro:9100"
              "proxmox:9100"
              "gaming:9100"
              "proxmox-observability:9100"
              "proxmox-video:9100"
              "proxmox-gaming:9100"
              "proxmox-gitlab:9100"
              "xcloud-caddy:9100"
              "xcloud-postgres:9100"
            ];
          }
        ];
      }
      {
        job_name = "tailscale exporter";
        static_configs = [
          {
            targets = [
              "proxmox-observability:9250"
            ];
          }
        ];
      }
    ];
  };
}
