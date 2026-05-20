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
      {
        job_name = "tailscale-client-metrics";
        static_configs = [
          #          {
          #            targets = [
          #              "m3pro:9251"
          #            ];
          #            labels = {
          #              tailscale_machine = "m3pro";
          #            };
          #          }
          #          {
          #            targets = [
          #              "proxmox:9251"
          #            ];
          #            labels = {
          #              tailscale_machine = "proxmox";
          #            };
          #          }
          {
            targets = [
              "gaming:9251"
            ];
            labels = {
              tailscale_machine = "gaming";
            };
          }
          {
            targets = [
              "proxmox-video:9251"
            ];
            labels = {
              tailscale_machine = "proxmox-video";
            };
          }
          {
            targets = [
              "proxmox-observability:9251"
            ];
            labels = {
              tailscale_machine = "proxmox-observability";
            };
          }
          {
            targets = [
              "proxmox-gaming:9251"
            ];
            labels = {
              tailscale_machine = "proxmox-gaming";
            };
          }
          {
            targets = [
              "proxmox-gitlab:9251"
            ];
            labels = {
              tailscale_machine = "proxmox-gitlab";
            };
          }
          {
            targets = [
              "xcloud-caddy:9251"
            ];
            labels = {
              tailscale_machine = "xcloud-caddy";
            };
          }
          {
            targets = [
              "xcloud-postgres:9251"
            ];
            labels = {
              tailscale_machine = "xcloud-postgres";
            };
          }
        ];
      }
    ];
  };
}
