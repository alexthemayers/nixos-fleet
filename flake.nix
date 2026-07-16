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
    in
    {
      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          buildInputs = [
            deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.deploy-rs
            inputs.attic.packages.${pkgs.stdenv.hostPlatform.system}.attic
            pkgs.git
            pkgs.openssh
            pkgs.gnumake
          ];
        };
      });
      checks = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
        system:
        let
          nodesForSystem = nixpkgs.lib.filterAttrs (
            name: node: self.nixosConfigurations.${name}.pkgs.stdenv.hostPlatform.system == system
          ) self.deploy.nodes;
        in
        deploy-rs.lib.${system}.deployChecks { nodes = nodesForSystem; }
      );
      nixosConfigurations = {
        proxmox-applications-1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./config/secrets.nix
            disko.nixosModules.disko
            ./disko/disk-config.nix
            ./hosts/proxmox-applications-1/configuration.nix
            ./config/basics.nix
            ./config/security.nix
            ./config/system.nix
            ./config/nfs.nix
            ./config/users.nix
            ./config/observability.nix
            ./services/tailscale.nix
            ./services/jellyfin.nix
            ./services/immich.nix
            ./services/keycloak.nix
            ./services/vaultwarden.nix
            ./services/vikunja.nix
            ./services/actualbudget.nix
            ./services/paperless.nix
            ./services/luanti.nix
            ./services/openarena.nix
          ];
        };

        proxmox-applications-2 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./config/secrets.nix
            disko.nixosModules.disko
            ./hosts/proxmox-applications-2/configuration.nix
            ./disko/disk-config.nix
            ./config/basics.nix
            ./config/security.nix
            ./config/system.nix
            ./config/users.nix
            ./config/observability.nix
            ./services/tailscale.nix
            ./services/keycloak.nix
            ./services/paperless.nix
            ./services/vikunja.nix
            ./services/gitlab.nix
            ./services/container-registry.nix
          ];
        };

        proxmox-observability-1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./config/secrets.nix
            disko.nixosModules.disko
            ./hosts/proxmox-observability-1/configuration.nix
            ./disko/disk-config.nix
            ./config/basics.nix
            ./config/security.nix
            ./config/system.nix
            ./config/users.nix
            ./config/observability.nix
            ./services/tailscale.nix
            ./services/grafana.nix
            ./services/prometheus.nix
            ./services/loki.nix
            ./services/mimir.nix
            ./services/tailscale-exporter.nix
            ./services/truenas/graphite_exporter.nix
            ./services/ntfy.nix
          ];
        };

        proxmox-observability-2 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./config/secrets.nix
            disko.nixosModules.disko
            ./hosts/proxmox-observability-2/configuration.nix
            ./disko/disk-config.nix
            ./config/basics.nix
            ./config/security.nix
            ./config/system.nix
            ./config/users.nix
            ./services/tailscale.nix
            ./services/grafana.nix
            ./services/prometheus.nix
            ./services/loki.nix
            ./services/mimir.nix
            ./services/ntfy.nix
          ];
        };

        proxmox-dev = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./config/secrets.nix
            disko.nixosModules.disko
            ./hosts/proxmox-dev/configuration.nix
            ./disko/disk-config.nix
            ./config/basics.nix
            ./config/security.nix
            ./config/system.nix
            ./config/users.nix
            ./config/observability.nix
            ./services/tailscale.nix
            ./services/gitlab-runner.nix
            ./services/coder.nix
          ];
        };

        proxmox-lb = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./config/secrets.nix
            disko.nixosModules.disko
            ./hosts/proxmox-lb/configuration.nix
            ./disko/disk-config.nix
            ./config/basics.nix
            ./config/security.nix
            ./config/system.nix
            ./config/users.nix
            ./services/tailscale.nix
            ./services/caddy-internal.nix
          ];
        };

        proxmox-db-1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./config/secrets.nix
            disko.nixosModules.disko
            ./hosts/proxmox-db-1/configuration.nix
            ./disko/disk-config.nix
            ./config/basics.nix
            ./config/security.nix
            ./config/system.nix
            ./config/users.nix
            ./config/observability.nix
            ./services/tailscale.nix
            ./services/garage.nix
            ./services/attic.nix
            inputs.attic.nixosModules.atticd
          ];
        };

        proxmox-db-2 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./config/secrets.nix
            disko.nixosModules.disko
            ./hosts/proxmox-db-2/configuration.nix
            ./disko/disk-config.nix
            ./config/basics.nix
            ./config/security.nix
            ./config/system.nix
            ./config/users.nix
            ./config/observability.nix
            ./services/tailscale.nix
            ./services/garage.nix
            ./services/attic.nix
            inputs.attic.nixosModules.atticd
          ];
        };

        xcloud-postgres = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./config/secrets.nix
            disko.nixosModules.disko
            ./hosts/xcloud-postgres/disk-config.nix
            ./hosts/xcloud-postgres/configuration.nix
            ./config/basics.nix
            ./config/security.nix
            ./config/system.nix
            ./config/users.nix
            ./config/observability.nix
            ./services/tailscale.nix
            ./services/postgres.nix
            ./services/redis.nix
          ];
        };

        xcloud-caddy = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./config/secrets.nix
            disko.nixosModules.disko
            ./disko/disk-config.nix
            ./hosts/xcloud-caddy/configuration.nix
            ./config/basics.nix
            ./config/security.nix
            ./config/system.nix
            ./config/users.nix
            ./config/observability.nix
            ./services/caddy.nix
            ./services/tailscale.nix
            ./services/oauth2-proxy.nix
          ];
        };

        gaming = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./config/secrets.nix
            disko.nixosModules.disko
            ./disko/disk-config.nix
            ./hosts/gaming/configuration.nix
            ./hosts/gaming/desktop.nix
            ./hosts/gaming/gaming.nix
            ./hosts/gaming/amdgpu.nix
            ./hosts/gaming/bluetooth.nix
            ./hosts/gaming/alex.nix
            ./config/basics.nix
            ./config/security.nix
            ./config/system.nix
            ./config/users.nix
            ./config/observability.nix
            ./services/tailscale.nix
            ./programs/ut2004.nix
          ];
        };

        rpi4 = nixos-raspberrypi.lib.nixosSystemFull {
          specialArgs = { inherit inputs; };
          modules = [
            {
              imports = with nixos-raspberrypi.nixosModules; [
                raspberry-pi-4.base
              ];
            }
            sops-nix.nixosModules.sops
            ./config/secrets.nix
            ./hosts/rpi4/hardware.nix
            ./hosts/rpi4/tags.nix
            ./hosts/rpi4/configuration.nix
            ./hosts/rpi4/usb-backup-mount.nix
            ./config/basics.nix
            ./config/security.nix
            ./config/system.nix
            ./config/users.nix
            ./config/observability.nix
            ./services/tailscale.nix
            ./services/blackbox-exporter.nix

            # Failover backups
            ./services/garage.nix
            #            ./services/mimir.nix
            #            ./services/loki.nix
            ./services/keycloak.nix
            ./services/vaultwarden.nix
            ./services/grafana.nix
            ./services/prometheus.nix
            ./services/ntfy.nix
          ];
        };
      };

      deploy.nodes = {
        gaming = {
          hostname = "gaming";
          sshOpts = [
            "-A"
            "-o"
            "StrictHostKeyChecking=no"
          ];
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.gaming;
          };
        };
        proxmox-applications-1 = {
          hostname = "proxmox-applications-1";
          sshOpts = [
            "-A"
            "-o"
            "StrictHostKeyChecking=no"
          ];
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.proxmox-applications-1;
          };
        };

        proxmox-applications-2 = {
          hostname = "proxmox-applications-2";
          sshOpts = [
            "-A"
            "-o"
            "StrictHostKeyChecking=no"
          ];
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.proxmox-applications-2;
            user = "root";
          };
        };

        proxmox-observability-1 = {
          hostname = "proxmox-observability-1";
          sshOpts = [
            "-A"
            "-o"
            "StrictHostKeyChecking=no"
          ];
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.proxmox-observability-1;
          };
        };

        proxmox-observability-2 = {
          hostname = "proxmox-observability-2";
          sshOpts = [
            "-A"
            "-o"
            "StrictHostKeyChecking=no"
          ];
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.proxmox-observability-2;
          };
        };

        proxmox-dev = {
          hostname = "proxmox-dev";
          sshOpts = [
            "-A"
            "-o"
            "StrictHostKeyChecking=no"
          ];
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.proxmox-dev;
          };
        };

        proxmox-lb = {
          hostname = "proxmox-lb";
          sshOpts = [
            "-A"
            "-o"
            "StrictHostKeyChecking=no"
          ];
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.proxmox-lb;
          };
        };

        proxmox-db-1 = {
          hostname = "proxmox-db-1";
          sshOpts = [
            "-A"
            "-o"
            "StrictHostKeyChecking=no"
          ];
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.proxmox-db-1;
          };
        };

        proxmox-db-2 = {
          hostname = "proxmox-db-2";
          sshOpts = [
            "-A"
            "-o"
            "StrictHostKeyChecking=no"
          ];
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.proxmox-db-2;
          };
        };

        xcloud-caddy = {
          hostname = "xcloud-caddy";
          sshOpts = [
            "-A"
            "-o"
            "StrictHostKeyChecking=no"
          ];
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.xcloud-caddy;
          };
        };

        xcloud-postgres = {
          hostname = "xcloud-postgres";
          sshOpts = [
            "-A"
            "-o"
            "StrictHostKeyChecking=no"
          ];
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.xcloud-postgres;
          };
        };

        rpi4 = {
          hostname = "rpi4";
          remoteBuild = true;
          sshOpts = [
            "-A"
            "-o"
            "StrictHostKeyChecking=no"
          ];
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.rpi4;
          };
        };
      };
    };
}
