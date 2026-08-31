{
  description = "Unified flake for nixos-fleet";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    deploy-rs.url = "github:serokell/deploy-rs";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
      #      inputs.nixpkgs.follows = "nixpkgs";
    };
    attic = {
      url = "github:zhaofengli/attic";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      disko,
      deploy-rs,
      sops-nix,
      nixos-raspberrypi,
      attic,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Host keys are pinned in ssh/fleet_known_hosts and installed as the
      # global known_hosts (config/basics.nix), so deploys verify them.
      # -A is deliberately absent: nothing in an activation needs the operator's
      # SSH agent, and forwarding it to eleven root shells is a needless risk.
      fleetSshOpts = [
        "-o"
        "StrictHostKeyChecking=yes"
        "-o"
        "ControlMaster=auto"
        "-o"
        "ControlPath=~/.ssh/deploy-%C"
        "-o"
        "ControlPersist=10m"
      ];

      # remoteBuild = true makes the *target* evaluate and build its own closure.
      # On the 1.9 GiB cloud VMs that is what OOM-killed nix-daemon next to
      # Postgres on two consecutive days, so those build on the deployer instead.
      # The 4–6 GiB observability VMs cannot compile Loki/Mimir/Grafana either.
      # rpi4 is aarch64: fill and deploy run on the Pi itself
      # (scripts/run-on-rpi4.sh), not qemu on proxmox-dev.
      mkNode =
        {
          hostname,
          system ? "x86_64-linux",
          remoteBuild ? true,
          magicRollback ? true,
        }:
        {
          inherit hostname remoteBuild magicRollback;
          sshOpts = fleetSshOpts;
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.${system}.activate.nixos self.nixosConfigurations.${hostname};
          };
        };

      commonModules = [
        sops-nix.nixosModules.sops
        ./config/secrets.nix
        ./config/basics.nix
        ./config/security.nix
        ./config/system.nix
        ./config/users.nix
        ./config/observability.nix
        ./services/tailscale.nix
      ];

      proxmoxModules = commonModules ++ [
        disko.nixosModules.disko
        ./disko/disk-config.nix
        ./config/proxmox-vm.nix
      ];

      mkSystem =
        modules:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
          };
          inherit modules;
        };
    in
    {
      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
      # Fill this into Attic with the host closures so deploy scripts can
      # realize the CLI without `nix develop` (the shell pulls stdenv).
      packages = forAllSystems (
        pkgs:
        {
          attic = inputs.attic.packages.${pkgs.stdenv.hostPlatform.system}.attic;
        }
        // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          jellyfin-io-bench = pkgs.buildGoModule {
            pname = "jellyfin-io-bench";
            version = "1.0.0";
            src = ./scripts/jellyfin-io-bench;
            vendorHash = null;
            env.CGO_ENABLED = "0";
            meta.mainProgram = "jellyfin-io-bench";
            meta.description = "Jellyfin 4K transcode I/O bench; run on proxmox-applications-1";
          };
        }
      );
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          buildInputs = [
            deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.deploy-rs
            inputs.attic.packages.${pkgs.stdenv.hostPlatform.system}.attic
            pkgs.git
            pkgs.openssh
            pkgs.gnumake
            # scripts/check-inventory.sh and scripts/check-secrets.sh
            pkgs.python3
          ];
        };
      });
      checks = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          lib = nixpkgs.lib;
          nodesForSystem = nixpkgs.lib.filterAttrs (
            name: node: self.nixosConfigurations.${name}.pkgs.stdenv.hostPlatform.system == system
          ) self.deploy.nodes;
          deployChecks = deploy-rs.lib.${system}.deployChecks { nodes = nodesForSystem; };
          # Co-routed replicas import the same service modules, but deploy jobs
          # are independent, so a partial merge can leave Keycloak or Grafana
          # on different package versions indefinitely. Compare packages, not
          # whole closures: obs-1 also runs the Tailscale and Graphite exporters,
          # and the two app hosts run different workloads.
          coRouted =
            if system != "x86_64-linux" then
              { }
            else
              let
                obs1 = self.nixosConfigurations.proxmox-observability-1.config;
                obs2 = self.nixosConfigurations.proxmox-observability-2.config;
                apps1 = self.nixosConfigurations.proxmox-applications-1.config;
                apps2 = self.nixosConfigurations.proxmox-applications-2.config;
                pairs = [
                  {
                    name = "grafana.package";
                    a = obs1.services.grafana.package;
                    b = obs2.services.grafana.package;
                  }
                  {
                    name = "loki.package";
                    a = obs1.services.loki.package;
                    b = obs2.services.loki.package;
                  }
                  {
                    name = "mimir.package";
                    a = obs1.services.mimir.package;
                    b = obs2.services.mimir.package;
                  }
                  {
                    name = "ntfy-sh.package";
                    a = obs1.services.ntfy-sh.package;
                    b = obs2.services.ntfy-sh.package;
                  }
                  {
                    name = "keycloak.package";
                    a = apps1.services.keycloak.package;
                    b = apps2.services.keycloak.package;
                  }
                ];
                mismatches = lib.filter (p: p.a != p.b) pairs;
              in
              {
                co-routed-peers =
                  if mismatches == [ ] then
                    pkgs.writeText "co-routed-peers-ok" "ok"
                  else
                    throw "co-routed package skew: ${lib.concatMapStringsSep ", " (p: p.name) mismatches}";
              };
        in
        deployChecks // coRouted
      );
      nixosConfigurations = {
        proxmox-applications-1 = mkSystem (
          proxmoxModules
          ++ [
            ./hosts/proxmox-applications-1/configuration.nix
            ./services/jellyfin.nix
            ./services/immich.nix
            ./services/keycloak.nix
            ./services/vaultwarden.nix
            ./services/vikunja.nix
            ./services/actualbudget.nix
            ./services/paperless.nix
            ./services/luanti.nix
            ./services/openarena.nix
          ]
        );

        proxmox-applications-2 = mkSystem (
          proxmoxModules
          ++ [
            ./hosts/proxmox-applications-2/configuration.nix
            ./services/keycloak.nix
            ./services/vikunja.nix
            ./services/gitlab.nix
            ./services/container-registry.nix
          ]
        );

        proxmox-observability-1 = mkSystem (
          proxmoxModules
          ++ [
            ./hosts/proxmox-observability-1/configuration.nix
            ./services/grafana.nix
            ./services/prometheus.nix
            ./services/loki.nix
            ./services/mimir.nix
            ./services/tailscale-exporter.nix
            ./services/truenas/graphite_exporter.nix
            ./services/ntfy.nix
          ]
        );

        proxmox-observability-2 = mkSystem (
          proxmoxModules
          ++ [
            ./hosts/proxmox-observability-2/configuration.nix
            ./services/grafana.nix
            ./services/prometheus.nix
            ./services/loki.nix
            ./services/mimir.nix
            ./services/ntfy.nix
          ]
        );

        proxmox-dev = mkSystem (
          proxmoxModules
          ++ [
            ./hosts/proxmox-dev/configuration.nix
            ./services/gitlab-runner.nix
            ./services/coder.nix
          ]
        );

        proxmox-lb = mkSystem (
          proxmoxModules
          ++ [
            ./hosts/proxmox-lb/configuration.nix
            ./services/caddy-internal.nix
          ]
        );

        proxmox-db-1 = mkSystem (
          proxmoxModules
          ++ [
            ./hosts/proxmox-db-1/configuration.nix
            ./services/garage.nix
            ./services/attic.nix
            inputs.attic.nixosModules.atticd
          ]
        );

        proxmox-db-2 = mkSystem (
          proxmoxModules
          ++ [
            ./hosts/proxmox-db-2/configuration.nix
            ./services/garage.nix
            ./services/attic.nix
            inputs.attic.nixosModules.atticd
          ]
        );

        xcloud-postgres = mkSystem (
          commonModules
          ++ [
            disko.nixosModules.disko
            ./config/xcloud-vm.nix
            ./hosts/xcloud-postgres/disk-config.nix
            ./hosts/xcloud-postgres/configuration.nix
            ./services/postgres.nix
            ./services/redis.nix
          ]
        );

        xcloud-caddy = mkSystem (
          commonModules
          ++ [
            disko.nixosModules.disko
            ./disko/disk-config.nix
            ./config/xcloud-vm.nix
            ./hosts/xcloud-caddy/configuration.nix
            ./services/caddy.nix
            ./services/oauth2-proxy.nix
          ]
        );

        gaming = mkSystem (
          commonModules
          ++ [
            disko.nixosModules.disko
            ./disko/disk-config.nix
            ./hosts/gaming/configuration.nix
            ./hosts/gaming/desktop.nix
            ./hosts/gaming/gaming.nix
            ./hosts/gaming/amdgpu.nix
            ./hosts/gaming/bluetooth.nix
            ./hosts/gaming/alex.nix
            ./programs/ut2004.nix
          ]
        );

        rpi4 = nixos-raspberrypi.lib.nixosSystemFull {
          specialArgs = {
            inherit inputs;
          };
          modules = commonModules ++ [
            {
              imports = with nixos-raspberrypi.nixosModules; [
                raspberry-pi-4.base
              ];
            }
            ./hosts/rpi4/hardware.nix
            ./hosts/rpi4/tags.nix
            ./hosts/rpi4/configuration.nix
            ./hosts/rpi4/usb-backup-mount.nix
            ./services/blackbox-exporter.nix
            ./services/vaultwarden.nix
          ];
        };
      };

      deploy.nodes = {
        proxmox-applications-1 = mkNode {
          hostname = "proxmox-applications-1";
          remoteBuild = false;
        };
        proxmox-applications-2 = mkNode {
          hostname = "proxmox-applications-2";
          remoteBuild = false;
        };
        proxmox-observability-1 = mkNode {
          hostname = "proxmox-observability-1";
          remoteBuild = false;
        };
        proxmox-observability-2 = mkNode {
          hostname = "proxmox-observability-2";
          remoteBuild = false;
        };
        proxmox-dev = mkNode {
          hostname = "proxmox-dev";
          remoteBuild = false;
        };
        proxmox-lb = mkNode {
          hostname = "proxmox-lb";
          remoteBuild = false;
        };
        proxmox-db-1 = mkNode {
          hostname = "proxmox-db-1";
          remoteBuild = false;
        };
        proxmox-db-2 = mkNode {
          hostname = "proxmox-db-2";
          remoteBuild = false;
        };
        xcloud-caddy = mkNode {
          hostname = "xcloud-caddy";
          remoteBuild = false;
        };
        xcloud-postgres = mkNode {
          hostname = "xcloud-postgres";
          remoteBuild = false;
        };
        rpi4 = mkNode {
          hostname = "rpi4";
          system = "aarch64-linux";
          remoteBuild = false;
        };

        gaming = mkNode {
          hostname = "gaming";
          remoteBuild = false;
        };
      };
    };
}
