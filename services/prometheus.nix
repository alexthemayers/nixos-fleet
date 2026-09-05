{ config, ... }:
let
  inherit (config.fleet.inventory) nixosHosts;
  portTargets = port: extras: map (h: "${h}:${toString port}") (nixosHosts ++ extras);
  hostRelabel = [
    {
      source_labels = [ "__address__" ];
      regex = "([^:]+):.*";
      target_label = "host";
      replacement = "$1";
    }
  ];
  # Mimir's per-tenant series cap is a cliff, not a throttle: the ingester that
  # reaches its share of the cap rejects every new series, including the ruler's
  # own evaluation output, so alerting degrades with it. Dropping series nothing
  # reads buys headroom for free. Verify a name has no rule, dashboard, or alert
  # before adding it (docs/adr/2026-09-05-mimir-series-headroom.md). Prometheus
  # anchors these regexes, so a trailing `.*` is needed to catch histogram
  # `_bucket`/`_sum`/`_count` children.
  dropMetrics = names: [
    {
      source_labels = [ "__name__" ];
      regex = builtins.concatStringsSep "|" names;
      action = "drop";
    }
  ];
in
{
  users.users.alertmanager = {
    isSystemUser = true;
    group = "alertmanager";
  };
  users.groups.alertmanager = { };
  # amtool lives next to alertmanager; the service module does not put it on PATH.
  environment.systemPackages = [ config.services.prometheus.alertmanager.package ];
  systemd.services.alertmanager.serviceConfig.User = "alertmanager";
  systemd.services.alertmanager.serviceConfig.Group = "alertmanager";
  systemd.services.alertmanager.wants = [ "network-online.target" ];
  systemd.services.alertmanager.after = [
    "network-online.target"
    "tailscaled.service"
  ];
  # Address is not known at build time. fleet.clusterEnv writes it into
  # EnvironmentFile; upstream ExecStart is left alone so we do not depend on
  # the nixpkgs-internal envsubst path.
  fleet.clusterEnv.alertmanager = {
    service = "alertmanager.service";
    envFile = "/run/alertmanager-advertise.env";
    ipVariable = "ALERTMANAGER_ADVERTISE_ADDR";
    ipSuffix = ":9094";
    timeoutSec = 30;
  };

  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPorts = [
      9090 # Prometheus web
      9093 # Alertmanager web
      9094 # Alertmanager cluster gossip
    ];
    allowedUDPPorts = [
      9094 # Alertmanager cluster gossip
    ];
  };

  systemd.services.prometheus.wants = [ "network-online.target" ];
  systemd.services.prometheus.after = [
    "network-online.target"
    "tailscaled.service"
  ];
  systemd.services.prometheus.serviceConfig.MemoryMax = "1G";
  systemd.services.prometheus.serviceConfig.MemoryHigh = "896M";

  services.prometheus = {
    enable = true;
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
              # OIDC discovery is public. /admin* is CIDR-gated at the edge
              # (docs/adr/2026-08-29-keycloak-master.md); a WAN probe of
              # /admin/master/console/ is a permanent EndpointDown.
              "https://identity.alexmayers.co.za/realms/master/.well-known/openid-configuration"
              "https://grafana.alexmayers.co.za/login"
              "https://budget.alexmayers.co.za"
              "https://proxmox.alexmayers.co.za"
              "https://truenas.alexmayers.co.za/ui/"
              "https://ntfy.alexmayers.co.za"
              "https://paperless.alexmayers.co.za/accounts/login/"
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
              "proxmox-lb:2019"
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
        # A latency histogram of the rate limiter's own bookkeeping, bucketed
        # per zone and handler. Largest single contributor to the tenant series
        # count and no rule or dashboard reads it. The request/response
        # histograms are kept; they answer edge latency questions.
        metric_relabel_configs = dropMetrics [ "caddy_rate_limit_process_time_seconds_.*" ];
      }
      {
        job_name = "prometheus";
        static_configs = [
          {
            targets = [
              "proxmox-observability-1:9090"
              "proxmox-observability-2:9090"
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
            # proxmox is the hypervisor; its exporters are managed by ansible/.
            targets = portTargets 9558 [ "proxmox" ];
          }
        ];
        relabel_configs = hostRelabel;
        # One series per unit per host each. ServiceDown/BackupJobFailed read
        # systemd_unit_state and ServiceCrashLooping reads
        # systemd_service_restart_total; these three timestamps have no reader.
        metric_relabel_configs = dropMetrics [
          "systemd_unit_active_enter_time_seconds"
          "systemd_unit_active_exit_time_seconds"
          "systemd_unit_inactive_exit_time_seconds"
        ];
      }
      {
        job_name = "node exporter";
        static_configs = [
          {
            # m3pro is a laptop and proxmox is the hypervisor. Neither is a
            # NixOS fleet host; both are intentionally scraped and are excluded
            # from TargetDown in services/mimir-rules.nix.
            targets = portTargets 9100 [
              "m3pro"
              "proxmox"
            ];
          }
        ];
        relabel_configs = hostRelabel;
        # node-exporter's systemd collector duplicates the standalone systemd
        # exporter per unit per state. The alerts read the standalone
        # systemd_unit_state, and node_systemd_unit_state has no expr behind it:
        # the one dashboard mentioning it does so in a legacy "metric" field
        # whose query is systemd_unit_state. The collector stays enabled for
        # node_systemd_units and node_systemd_socket_*, which panels do query
        # and which are one series per state rather than per unit.
        metric_relabel_configs = dropMetrics [ "node_systemd_unit_state" ];
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
        static_configs = map (h: {
          targets = [ "${h}:9251" ];
          labels = {
            tailscale_machine = h;
          };
        }) nixosHosts;
      }
      {
        job_name = "smokeping-probers";
        scrape_interval = "5s";
        static_configs = [
          {
            targets = portTargets 9374 [ ];
          }
        ];
        relabel_configs = hostRelabel;
      }
      {
        job_name = "keycloak";
        static_configs = [
          {
            targets = [
              "proxmox-applications-1:9000"
              "proxmox-applications-2:9000"
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
            ];
          }
        ];
        relabel_configs = hostRelabel;
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
            targets = portTargets 12345 [ "proxmox" ];
          }
        ];
        relabel_configs = hostRelabel;
      }
      {
        job_name = "loki";
        static_configs = [
          {
            targets = [
              "proxmox-observability-1:3100"
              "proxmox-observability-2:3100"
            ];
          }
        ];
      }
      {
        job_name = "mimir";
        static_configs = [
          {
            targets = [
              "proxmox-observability-1:9009"
              "proxmox-observability-2:9009"
            ];
          }
        ];
      }
      {
        # Deployed by ansible/roles/smartctl_exporter but never scraped, so the
        # only disks with SMART data were invisible.
        job_name = "smartctl";
        static_configs = [
          {
            targets = [ "proxmox:9633" ];
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
      environmentFile = "/run/alertmanager-advertise.env";
      extraFlags = [
        "--cluster.listen-address 0.0.0.0:9094"
        "--cluster.advertise-address \${ALERTMANAGER_ADVERTISE_ADDR}"
      ];

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
          routes = [
            {
              receiver = "ntfy";
              matchers = [
                ''alertname=~"LowDiskSpace|NodeFilesystemAlmostOutOfSpace|NodeFilesystemSpaceFillingUp"''
              ];
              group_by = [
                "alertname"
                "instance"
                "device"
              ];
              group_wait = "30s";
              group_interval = "5m";
              repeat_interval = "12h";
            }
          ];
        };
        inhibit_rules = [
          {
            source_matchers = [ ''alertname="NodeFilesystemAlmostOutOfSpace"'' ];
            target_matchers = [ ''alertname="LowDiskSpace"'' ];
            equal = [
              "instance"
              "device"
            ];
          }
        ];
        receivers = [
          {
            name = "ntfy";
            webhook_configs = [
              {
                url = "http://127.0.0.1:8095/";
                send_resolved = true;
              }
            ];
          }
        ];
      };
    };
  };
}
