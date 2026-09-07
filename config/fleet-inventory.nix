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
        "proxmox-applications-1"
        "proxmox-applications-2"
        "proxmox-observability"
        "proxmox-dev"
        "rpi4"
        "gaming"
      ];

      hosts = cfg.nixosHosts ++ [
        # Not NixOS, load-bearing anyway.
        "proxmox" # the hypervisor, configured from ansible/
        "truenas-scale" # NFS for nearly all file state
        "m3pro" # workstation, scraped on purpose
      ];

      nodes = {
        proxmox-applications-1 = {
          sriovMac = "82:cc:a5:22:e5:01";
          tailscalePort = 41643;
        };
        proxmox-applications-2 = {
          sriovMac = "82:cc:a5:22:e5:02";
          tailscalePort = 41644;
        };
        proxmox-observability = {
          sriovMac = "82:cc:a5:22:e5:03";
          tailscalePort = 41645;
        };
        proxmox-dev = {
          sriovMac = "82:cc:a5:22:e5:07";
          tailscalePort = 41649;
        };
        rpi4 = {
          tailscalePort = 41651;
        };
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

    # Catches a scrape target for a host that does not exist, which is how
    # ghost entries survived for months: a dead target only shows up as a
    # permanently-down series that nobody correlates back to a typo.
    assertions =
      let
        targets = lib.concatMap (
          job: lib.concatMap (sc: sc.targets or [ ]) (job.static_configs or [ ])
        ) config.services.prometheus.scrapeConfigs;

        # Blackbox probe jobs carry full URLs as targets and relabel them onto
        # the exporter's own address, so the "target" is not a fleet host at all.
        isScrapeTarget = t: !(lib.hasInfix "://" t);

        hostOf = target: lib.head (lib.splitString ":" target);

        unknown = lib.unique (
          lib.filter (
            t:
            let
              h = hostOf t;
            in
            h != "localhost" && h != "127.0.0.1" && !(lib.elem h cfg.hosts)
          ) (lib.filter isScrapeTarget targets)
        );

        missingNodes = lib.filter (h: !(cfg.nodes ? ${h})) cfg.nixosHosts;
      in
      [
        {
          assertion = unknown == [ ];
          message = ''
            Prometheus scrape targets reference hosts that are not in
            fleet.inventory.hosts: ${lib.concatStringsSep ", " unknown}

            Either add the host to config/fleet-inventory.nix or remove the
            scrape target.
          '';
        }
        {
          assertion = missingNodes == [ ];
          message = ''
            fleet.inventory.nixosHosts without a fleet.inventory.nodes entry:
            ${lib.concatStringsSep ", " missingNodes}
          '';
        }
      ];
  };
}
