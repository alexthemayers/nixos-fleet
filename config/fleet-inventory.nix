{
  config,
  lib,
  ...
}:
let
  cfg = config.fleet.inventory;
  hostname = config.networking.hostName;
in
{
  options.fleet.inventory = {
    hosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = ''
        Every machine the fleet may address by name: NixOS hosts plus the
        non-NixOS machines that are nonetheless scraped or depended on.

        This exists because the same list was previously written out by hand in
        six places - the Makefile, the CI ssh config, the smokeping argv, the
        iperf3 mesh, the Prometheus scrape jobs and the docs - and they had
        already drifted from each other. Four names in operator tooling
        (proxmox-video, proxmox-gaming, proxmox-gitlab, proxmox-db) referred to
        machines that no longer existed, so `make reboot-all` skipped seven live
        hosts and reported success.
      '';
    };

    nixosHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Hosts built and deployed from this flake.";
    };

    deployPausedHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = ''
        NixOS hosts that stay in the flake and in nixosHosts, but must
        not be activated.
      '';
    };

    nodes = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            sriovMac = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "iavf SR-IOV MAC on Proxmox VMs; null on bare metal and cloud.";
            };
            tailscalePort = lib.mkOption {
              type = lib.types.port;
              description = "Unique WireGuard port for this host's tailscaled.";
            };
          };
        }
      );
      description = "Per-host network identity. Adding a NixOS host means adding an entry here.";
    };
  };

  config = {
    fleet.inventory = {
      nixosHosts = [
        "xcloud-caddy"
        "xcloud-postgres"
        "gaming"
      ];

      deployPausedHosts = [ ];

      hosts = cfg.nixosHosts ++ [
        # Not NixOS, load-bearing anyway.
        "proxmox" # the hypervisor, configured from ansible/
        "truenas-scale" # NFS for nearly all file state
        "m3pro" # workstation, scraped on purpose
        "proxmox-applications-debian" # VM 109; collection fleet.debian_guest
        "proxmox-gitlab-debian" # VM 110; GitLab
        "proxmox-observability-debian" # VM 111; metrics, logs, Grafana, ntfy
        "proxmox-dev" # MagicDNS name of VM 112, the Debian builder
      ];

      nodes = {
        gaming = {
          tailscalePort = 41642;
        };
        xcloud-caddy = {
          tailscalePort = 41642;
        };
        xcloud-postgres = {
          tailscalePort = 41642;
        };
      };
    };

    services.tailscale.port = lib.mkIf (cfg.nodes ? ${hostname}) (
      lib.mkForce cfg.nodes.${hostname}.tailscalePort
    );

    # Scrape-target and host-relabel guards live in
    # scripts/check-prometheus-scrapes.py (committed prometheus.yml). The
    # old assertions here read config.services.prometheus.scrapeConfigs,
    # which is empty now that proxmox-observability is gone.
    assertions =
      let
        missingNodes = lib.filter (h: !(cfg.nodes ? ${h})) cfg.nixosHosts;

        pausedUnknown = lib.filter (h: !(lib.elem h cfg.nixosHosts)) cfg.deployPausedHosts;
      in
      [
        {
          assertion = missingNodes == [ ];
          message = ''
            fleet.inventory.nixosHosts without a fleet.inventory.nodes entry:
            ${lib.concatStringsSep ", " missingNodes}
          '';
        }
        {
          assertion = pausedUnknown == [ ];
          message = ''
            fleet.inventory.deployPausedHosts is not a subset of nixosHosts:
            ${lib.concatStringsSep ", " pausedUnknown}
          '';
        }
      ];
  };
}
