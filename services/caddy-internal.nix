{
  config,
  lib,
  pkgs,
  ...
}:
{
  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPorts = [
      80
      443
      3902 # S3 API
      3903 # Garage admin health (proxied to db-1/db-2)
      3100 # Loki
      9009 # Mimir
      9093 # Alertmanager
      8080 # Attic
      2019 # Caddy Prometheus metrics (admin API stays on loopback)
    ];
    allowedUDPPorts = [
      27960 # openarena
      30000 # luanti
    ];
  };

  services.caddy = {
    enable = true;
    package = import ../config/caddy-package.nix { inherit pkgs; };

    globalConfig = ''
      admin 127.0.0.1:2020 {
        origins 127.0.0.1:2020 localhost:2020
      }
      metrics {
        per_host
      }
      servers {
        trusted_proxies static 100.64.0.0/10 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12
      }
      layer4 {
        udp/:27960 {
          route {
            proxy udp/proxmox-applications-1:27960
          }
        }
        udp/:30000 {
          route {
            proxy udp/proxmox-applications-1:30000
          }
        }
      }
    '';

    virtualHosts = {
      "http://:2019" = {
        extraConfig = ''
          metrics
        '';
      };
      "http://jellyfin.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-applications-1:8096 {
              flush_interval -1
            }
        '';
      };
      "http://immich.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-applications-1:2283 {
              flush_interval -1
            }
        '';
      };
      "http://grafana.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-observability-1:3000 proxmox-observability-2:3000 {
              lb_policy cookie grafana_lb
              health_uri /api/health
              health_interval 5s
              health_timeout 2s
              health_status 200
              flush_interval -1
            }
        '';
      };
      "http://gitlab.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-applications-2:8080
        '';
      };
      "http://registry.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy http://proxmox-applications-2:5005
        '';
      };
      "http://coder.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-dev:7080
        '';
      };
      "http://budget.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-applications-1:5006
        '';
      };
      # Single instance on apps-1. Do not add apps-2 unless it is a full replica.
      "http://paperless.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-applications-1:28981 {
              lb_try_duration 5s
              health_uri /accounts/login/
              health_interval 10s
              health_timeout 5s
              health_status 2xx
              fail_duration 30s
              max_fails 1
              unhealthy_status 5xx
            }
        '';
      };
      "http://identity.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-applications-1:7777 proxmox-applications-2:7777 {
              lb_policy round_robin
              lb_try_duration 5s
              health_uri /health/ready
              health_port 9000
              health_interval 5s
              health_timeout 2s
              health_status 2xx
              fail_duration 10s
              max_fails 1
              unhealthy_status 5xx
            }
        '';
      };
      "http://vaultwarden.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-applications-1:8222 {
              lb_policy first
              lb_try_duration 5s
              health_uri /alive
              health_interval 5s
              health_timeout 2s
              health_status 200
              fail_duration 10s
              max_fails 1
              unhealthy_status 5xx
              flush_interval -1
            }
        '';
      };
      # Without a health check this pair round-robined into a Vikunja that had
      # been failing on start-limit-hit for a day.
      "http://tasks.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-applications-1:3456 proxmox-applications-2:3456 {
              lb_policy round_robin
              lb_try_duration 5s
              health_uri /api/v1/info
              health_interval 5s
              health_timeout 2s
              health_status 200
              fail_duration 10s
              max_fails 1
              unhealthy_status 5xx
            }
        '';
      };
      "http://ntfy.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-observability-1:2586 proxmox-observability-2:2586 {
              lb_policy first
              lb_try_duration 5s
              health_uri /v1/health
              health_interval 5s
              health_timeout 2s
              health_status 200
              fail_duration 10s
              max_fails 1
              unhealthy_status 5xx
            }
        '';
      };
      # Port-only site addresses (`http://:3100`) match any Host, including
      # curl to 127.0.0.1. `http://proxmox-lb:3100` only matched that Host, so
      # probes without it got an empty HTTP 200 from Caddy while the backends
      # were down. unhealthy_status 5xx makes GET /ready 503 when none are up.
      "http://:3902" = {
        extraConfig = ''
          reverse_proxy /health proxmox-db-1:3903 proxmox-db-2:3903 {
              lb_policy round_robin
          }
          reverse_proxy proxmox-db-1:3902 proxmox-db-2:3902 {
              lb_policy round_robin
              # One backend per request. Retrying mid-GET after 5s closed
              # large S3 objects ("Connection closed by foreign host").
              lb_try_duration 0s
              flush_interval -1
              health_uri /health
              health_port 3903
              health_interval 5s
              health_timeout 2s
              health_status 200
              fail_duration 10s
              max_fails 1
              unhealthy_status 5xx
          }
        '';
      };
      "http://:3903" = {
        extraConfig = ''
          reverse_proxy proxmox-db-1:3903 proxmox-db-2:3903 {
              lb_policy round_robin
              lb_try_duration 5s
              health_uri /health
              health_interval 5s
              health_timeout 2s
              health_status 200
              fail_duration 10s
              max_fails 1
              unhealthy_status 5xx
          }
        '';
      };
      "http://:3100" = {
        extraConfig = ''
          reverse_proxy proxmox-observability-1:3100 proxmox-observability-2:3100 {
              lb_policy round_robin
              lb_try_duration 5s
              health_uri /ready
              health_interval 5s
              health_timeout 2s
              health_status 200
              fail_duration 10s
              max_fails 1
              unhealthy_status 5xx
          }
        '';
      };
      "http://:9009" = {
        extraConfig = ''
          reverse_proxy proxmox-observability-1:9009 proxmox-observability-2:9009 {
              lb_policy round_robin
              lb_try_duration 5s
              health_uri /ready
              health_interval 5s
              health_timeout 2s
              health_status 200
              fail_duration 10s
              max_fails 1
              unhealthy_status 5xx
          }
        '';
      };
      "http://:9093" = {
        extraConfig = ''
          reverse_proxy proxmox-observability-1:9093 proxmox-observability-2:9093 {
              lb_policy round_robin
              lb_try_duration 5s
              health_uri /-/healthy
              health_interval 5s
              health_timeout 2s
              health_status 2xx
              fail_duration 10s
              max_fails 1
              unhealthy_status 5xx
          }
        '';
      };
      # Attic (atticd + attic-nar-proxy) lives on proxmox-dev. atticd 307s
      # single-chunk NARs to Garage at proxmox-lb:3902. Nix does not treat
      # that as a valid substituter NAR. proxmox-dev :8080 is
      # attic-nar-proxy (services/attic.nix), which follows that 307. This
      # hop still rewrites Location onto :8080 and proxies .chunk in case a
      # 307 leaks through, and streams with flush_interval -1.
      "http://:8080" = {
        extraConfig = ''
          @atticChunk path_regexp \.chunk$
          handle @atticChunk {
            reverse_proxy proxmox-lb:3902 {
              header_up Host proxmox-lb:3902
              flush_interval -1
            }
          }

          handle {
            route {
              header Location replace http://proxmox-db-1:3902 http://proxmox-lb:8080
              header Location replace http://proxmox-lb:3902 http://proxmox-lb:8080
              reverse_proxy proxmox-dev:8080 {
                flush_interval -1
                health_uri /
                health_interval 10s
                health_timeout 5s
                health_status 2xx
                fail_duration 10s
                max_fails 1
                unhealthy_status 5xx
              }
            }
          }
        '';
      };
    };
  };
}
