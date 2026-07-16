{
  config,
  lib,
  pkgs,
  ...
}:
{
  users.users.alertmanager = {
    isSystemUser = true;
    group = "alertmanager";
  };
  users.groups.alertmanager = { };
  systemd.services.alertmanager.serviceConfig.User = "alertmanager";
  systemd.services.alertmanager.serviceConfig.Group = "alertmanager";
  systemd.services.alertmanager.wants = [ "network-online.target" ];
  systemd.services.alertmanager.after = [
    "network-online.target"
    "tailscaled.service"
  ];

  systemd.services.prometheus.wants = [ "network-online.target" ];
  systemd.services.prometheus.after = [
    "network-online.target"
    "tailscaled.service"
  ];

  services.prometheus = {
    enable = true;
    port = 9090;
    extraFlags = [
      "--log.format=json"
      "--enable-feature=agent"
    ];

    remoteWrite = [
      {
        url = "http://localhost:9009/api/v1/push";
        queue_config = {
          capacity = 500;
          max_samples_per_send = 200;
          batch_send_deadline = "5s";
          min_backoff = "500ms";
          max_backoff = "10s";
        };
      }
    ];

    globalConfig.scrape_interval = "30s";
    globalConfig.external_labels = {
      cluster = "nixos-fleet";
      __replica__ = config.networking.hostName;
    };
    scrapeConfigs = [
      {
        job_name = "blackbox_http";
        metrics_path = "/probe";
        params = {
          module = [ "http_2xx" ];
        };
        static_configs = [
          {
            targets = [
              "https://auth.alexmayers.co.za/ping"
              "https://gitlab.alexmayers.co.za/users/sign_in"
              "https://registry.alexmayers.co.za"
              "https://coder.alexmayers.co.za"
              "https://immich.alexmayers.co.za"
              "https://jellyfin.alexmayers.co.za/web/"
              "https://vaultwarden.alexmayers.co.za"
              "https://tasks.alexmayers.co.za"
              "https://identity.alexmayers.co.za/admin/master/console/"
              "https://grafana.alexmayers.co.za/login"
              "https://budget.alexmayers.co.za"
              "https://proxmox.alexmayers.co.za"
              "https://truenas.alexmayers.co.za/ui/"
              "https://prometheus.alexmayers.co.za/query"
              "https://alertmanager.alexmayers.co.za"
              "https://s3.alexmayers.co.za/health"
              "https://ntfy.alexmayers.co.za"
              "https://paperless.alexmayers.co.za/accounts/login/"
              "https://loki.alexmayers.co.za/ready"
              "https://mimir.alexmayers.co.za/ready"
            ];
          }
        ];
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            target_label = "__param_target";
          }
          {
            source_labels = [ "__param_target" ];
            target_label = "instance";
          }
          {
            target_label = "__address__";
            replacement = "rpi4:9115";
          }
        ];
      }
      {
        job_name = "caddy";
        static_configs = [
          {
            targets = [
              "xcloud-caddy:2019"
            ];
          }
        ];
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            regex = "([^:]+):.*";
            target_label = "host";
            replacement = "$1";
          }
        ];
      }
      {
        job_name = "prometheus";
        static_configs = [
          {
            targets = [
              "proxmox-observability-1:9090"
              "proxmox-observability-2:9090"
              "rpi4:9090"
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
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            regex = "([^:]+):.*";
            target_label = "host";
            replacement = "$1";
          }
        ];
      }
      {
        job_name = "postgres_pgbouncer";
        static_configs = [
          {
            targets = [
              "xcloud-postgres:9127"
            ];
          }
        ];
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            regex = "([^:]+):.*";
            target_label = "host";
            replacement = "$1";
          }
        ];
      }
      {
        job_name = "systemd exporter";
        static_configs = [
          {
            targets = [
              "gaming:9558"
              "proxmox:9558"
              "proxmox-observability-1:9558"
              "proxmox-lb:9558"
              "proxmox-dev:9558"
              "proxmox-db-1:9558"
              "proxmox-db-2:9558"
              "proxmox-applications-1:9558"
              "proxmox-applications-2:9558"
              "rpi4:9558"
              "xcloud-caddy:9558"
              "xcloud-postgres:9558"
            ];
          }
        ];
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            regex = "([^:]+):.*";
            target_label = "host";
            replacement = "$1";
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
              "rpi4:9100"
              "gaming:9100"
              "proxmox-observability-1:9100"
              "proxmox-observability-2:9100"
              "proxmox-lb:9100"
              "proxmox-dev:9100"
              "proxmox-db-1:9100"
              "proxmox-db-2:9100"
              "proxmox-applications-1:9100"
              "proxmox-applications-2:9100"
              "xcloud-caddy:9100"
              "xcloud-postgres:9100"
            ];
          }
        ];
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            regex = "([^:]+):.*";
            target_label = "host";
            replacement = "$1";
          }
        ];
      }
      {
        job_name = "tailscale exporter";
        static_configs = [
          {
            targets = [
              "proxmox-observability-1:9250"
            ];
          }
        ];
      }
      {
        job_name = "tailscale-client-metrics";
        static_configs = [
          {
            targets = [
              "rpi4:9251"
            ];
            labels = {
              tailscale_machine = "rpi4";
            };
          }
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
              "proxmox-observability-1:9251"
            ];
            labels = {
              tailscale_machine = "proxmox-observability-1";
            };
          }
          {
            targets = [
              "proxmox-observability-2:9251"
            ];
            labels = {
              tailscale_machine = "proxmox-observability-2";
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
          {
            targets = [
              "proxmox-lb:9251"
            ];
            labels = {
              tailscale_machine = "proxmox-lb";
            };
          }
          {
            targets = [
              "proxmox-dev:9251"
            ];
            labels = {
              tailscale_machine = "proxmox-dev";
            };
          }
          {
            targets = [
              "proxmox-db-1:9251"
            ];
            labels = {
              tailscale_machine = "proxmox-db-1";
            };
          }
          {
            targets = [
              "proxmox-db-2:9251"
            ];
            labels = {
              tailscale_machine = "proxmox-db-2";
            };
          }
          {
            targets = [
              "proxmox-applications-1:9251"
            ];
            labels = {
              tailscale_machine = "proxmox-applications-1";
            };
          }
          {
            targets = [
              "proxmox-applications-2:9251"
            ];
            labels = {
              tailscale_machine = "proxmox-applications-2";
            };
          }
        ];
      }
      {
        job_name = "smokeping-probers";
        scrape_interval = "5s";
        static_configs = [
          {
            targets = [
              "gaming:9374"
              "proxmox-dev:9374"
              "proxmox-lb:9374"
              "proxmox-db-1:9374"
              "proxmox-db-2:9374"
              "proxmox-applications-1:9374"
              "proxmox-applications-2:9374"
              "proxmox-observability-1:9374"
              "proxmox-observability-2:9374"
              "rpi4:9374"
              "xcloud-caddy:9374"
              "xcloud-postgres:9374"
            ];
          }
        ];
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            regex = "([^:]+):.*";
            target_label = "host";
            replacement = "$1";
          }
        ];
      }
      {
        job_name = "keycloak";
        static_configs = [
          {
            targets = [
              "proxmox-applications-1:9000"
              "proxmox-applications-2:9000"
              "rpi4:9000"
            ];
          }
        ];
      }
      {
        job_name = "grafana";
        static_configs = [
          {
            targets = [
              "proxmox-observability-1:3000"
              "proxmox-observability-2:3000"
              "rpi4:3000"
            ];
          }
        ];
      }
      {
        job_name = "gitlab";
        metrics_path = "/-/metrics";
        static_configs = [
          {
            targets = [
              "proxmox-applications-2:8080"
            ];
          }
        ];
      }
      {
        job_name = "gitlab-runner";
        static_configs = [
          {
            targets = [
              "proxmox-dev:9252"
            ];
          }
        ];
      }
      {
        job_name = "garage";
        static_configs = [
          {
            targets = [
              "proxmox-db-1:3903"
              "proxmox-db-2:3903"
              "rpi4:3903"
            ];
          }
        ];
      }
      {
        job_name = "coder";
        static_configs = [
          {
            targets = [
              "proxmox-dev:2112"
            ];
          }
        ];
      }
      {
        job_name = "vikunja";
        metrics_path = "/api/v1/metrics";
        static_configs = [
          {
            targets = [
              "proxmox-applications-1:3456"
              "proxmox-applications-2:3456"
            ];
          }
        ];
      }
      {
        job_name = "ntfy";
        static_configs = [
          {
            targets = [
              "proxmox-observability-1:2586"
              "proxmox-observability-2:2586"
              "rpi4:2586"
            ];
          }
        ];
      }
      {
        job_name = "oauth2-proxy";
        static_configs = [
          {
            targets = [
              "xcloud-caddy:44180"
            ];
          }
        ];
      }
      {
        job_name = "alloy";
        static_configs = [
          {
            targets = [
              "proxmox:12345"
              "rpi4:12345"
              "gaming:12345"
              "proxmox-observability-1:12345"
              "proxmox-observability-2:12345"
              "proxmox-lb:12345"
              "proxmox-dev:12345"
              "proxmox-db-1:12345"
              "proxmox-db-2:12345"
              "proxmox-applications-1:12345"
              "proxmox-applications-2:12345"
              "xcloud-caddy:12345"
              "xcloud-postgres:12345"
            ];
          }
        ];
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            regex = "([^:]+):.*";
            target_label = "host";
            replacement = "$1";
          }
        ];
      }
      {
        job_name = "loki";
        static_configs = [
          {
            targets = [
              "proxmox-observability-1:3100"
              "proxmox-observability-2:3100"
              "rpi4:3100"
            ];
          }
        ];
      }
      {
        job_name = "redis";
        static_configs = [
          {
            targets = [
              "xcloud-postgres:9121"
            ];
          }
        ];
      }
    ];

    alertmanager = {
      enable = true;
      listenAddress = "0.0.0.0";

      configuration = {
        route = {
          receiver = "ntfy";
          group_by = [
            "alertname"
            "host"
            "job"
          ];
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "12h";
        };
        receivers = [
          {
            name = "ntfy";
            webhook_configs = [
              {
                url = "http://localhost:8095/hook";
                send_resolved = true;
              }
            ];
          }
        ];
      };
    };
  };
}
