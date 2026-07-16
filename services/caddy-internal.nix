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
      3100 # Loki
      9009 # Mimir
      9093 # Alertmanager
      8080 # Attic
    ];
    allowedUDPPorts = [
      27960 # openarena
      30000 # luanti
    ];
  };

  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [
        "github.com/corazawaf/coraza-caddy/v2@v2.5.0"
        "github.com/mholt/caddy-l4@v0.1.1"
        "github.com/mholt/caddy-ratelimit@v0.1.1-0.20260612195517-5625512f24f6"
      ];
      hash = "sha256-3lGfwEVaEH4Z+sa44Kqst+b+m0KhX8Aphd+8W6deEoA=";
    };

    globalConfig = ''
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
              lb_policy round_robin
              health_uri /api/health
              flush_interval -1
              health_interval 5s
              health_timeout 2s
              health_status 200
            }
        '';
      };
      "http://mimir.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-observability-1:9009 proxmox-observability-2:9009 {
              lb_policy round_robin
              health_uri /ready
              health_interval 5s
              health_timeout 2s
              health_status 200
            }
        '';
      };
      "http://loki.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-observability-1:3100 proxmox-observability-2:3100 {
              lb_policy round_robin
              health_uri /ready
              health_interval 5s
              health_timeout 2s
              health_status 200
            }
        '';
      };
      "http://prometheus.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-observability-1:9090 proxmox-observability-2:9090 {
              lb_policy round_robin
              health_uri /-/healthy
              health_interval 5s
              health_timeout 2s
              health_status 2xx
            }
        '';
      };
      "http://alertmanager.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-observability-1:9093 proxmox-observability-2:9093 {
              lb_policy round_robin
              health_uri /-/healthy
              health_interval 5s
              health_timeout 2s
              health_status 2xx
            }
        '';
      };
      "http://gitlab.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-applications-2:8080 {
              flush_interval -1
            }
        '';
      };
      "http://registry.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy http://proxmox-applications-2:5005
        '';
      };
      "http://coder.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-dev:7080 {
              flush_interval -1
            }
        '';
      };
      "http://budget.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-applications-1:5006
        '';
      };
      "http://paperless.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-applications-1:28981 proxmox-applications-2:28981 {
              lb_policy round_robin
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
            }
        '';
      };
      "http://s3.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy /health proxmox-db-1:3903 proxmox-db-2:3903 {
              lb_policy round_robin
            }
          reverse_proxy proxmox-db-1:3902 proxmox-db-2:3902 {
              lb_policy round_robin
              lb_try_duration 5s
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
      "http://tasks.alexmayers.co.za" = {
        extraConfig = ''
          reverse_proxy proxmox-applications-1:3456 proxmox-applications-2:3456 {
              lb_policy round_robin
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
      "http://proxmox-lb:3902" = {
        extraConfig = ''
          reverse_proxy /health proxmox-db-1:3903 proxmox-db-2:3903 {
              lb_policy round_robin
          }
          reverse_proxy proxmox-db-1:3902 proxmox-db-2:3902 {
              lb_policy round_robin
              lb_try_duration 5s
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
      "http://proxmox-lb:3100" = {
        extraConfig = ''
          reverse_proxy proxmox-observability-1:3100 proxmox-observability-2:3100 {
              lb_policy round_robin
              health_uri /ready
              health_interval 5s
              health_timeout 2s
              health_status 200
          }
        '';
      };
      "http://proxmox-lb:9009" = {
        extraConfig = ''
          reverse_proxy proxmox-observability-1:9009 proxmox-observability-2:9009 {
              lb_policy round_robin
              health_uri /ready
              health_interval 5s
              health_timeout 2s
              health_status 200
          }
        '';
      };
      "http://proxmox-lb:9093" = {
        extraConfig = ''
          reverse_proxy proxmox-observability-1:9093 proxmox-observability-2:9093 {
              lb_policy round_robin
              health_uri /-/healthy
              health_interval 5s
              health_timeout 2s
              health_status 2xx
          }
        '';
      };
      "http://proxmox-lb:8080" = {
        extraConfig = ''
          reverse_proxy proxmox-db-1:8080 proxmox-db-2:8080 {
              lb_policy round_robin
              lb_try_duration 5s
              fail_duration 10s
              max_fails 1
              unhealthy_status 5xx
          }
        '';
      };
    };
  };
}
