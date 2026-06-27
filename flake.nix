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
            pkgs.git
            pkgs.openssh
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
        proxmox-gitlab = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./config/secrets.nix
            disko.nixosModules.disko
            ./hosts/proxmox-gitlab/configuration.nix
            ./disko/disk-config.nix
            ./config/basics.nix
            ./config/security.nix
            ./config/system.nix
            ./config/users.nix
            ./config/observability.nix
            ./services/tailscale.nix
            ./services/gitlab.nix
            ./services/keycloak.nix
            ./services/vaultwarden.nix
            ./services/vikunja.nix
            ./services/actualbudget.nix
            ./services/paperless.nix
          ];
        };

        proxmox-observability = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./config/secrets.nix
            disko.nixosModules.disko
            ./hosts/proxmox-observability/configuration.nix
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
            ./services/tailscale-exporter.nix
            ./services/truenas/graphite_exporter.nix
          ];
        };

        proxmox-gaming = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./config/secrets.nix
            disko.nixosModules.disko
            ./hosts/proxmox-gaming/configuration.nix
            ./disko/disk-config.nix
            ./config/basics.nix
            ./config/security.nix
            ./config/system.nix
            ./config/users.nix
            ./config/observability.nix
            ./services/tailscale.nix
            ./services/coder.nix
            ./services/gitlab-runner.nix
            ./services/luanti.nix
          ];
        };

        proxmox-db = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./config/secrets.nix
            disko.nixosModules.disko
            ./hosts/proxmox-db/configuration.nix
            ./disko/disk-config.nix
            ./config/basics.nix
            ./config/security.nix
            ./config/system.nix
            ./config/users.nix
            ./config/observability.nix
            ./services/tailscale.nix
            ./services/garage.nix
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

        proxmox-video = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./config/secrets.nix
            disko.nixosModules.disko
            ./disko/disk-config.nix
            ./hosts/proxmox-video/configuration.nix
            ./config/basics.nix
            ./config/security.nix
            ./config/system.nix
            ./config/nfs.nix
            ./config/users.nix
            ./config/observability.nix
            ./services/tailscale.nix
            ./services/jellyfin.nix
            ./services/immich.nix
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
            #            ./services/containers/podman.nix
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
            ./services/garage.nix

            # Failover backups
            ./services/keycloak.nix
            ./services/vaultwarden.nix
            ./services/grafana.nix
            ./services/prometheus.nix
          ];
        };
      };

      deploy.nodes = {
        proxmox-gitlab = {
          hostname = "proxmox-gitlab";
          sshOpts = [ "-A" ];
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.proxmox-gitlab;
          };
        };
        gaming = {
          hostname = "gaming";
          sshOpts = [ "-A" ];
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.gaming;
          };
        };
        proxmox-video = {
          hostname = "proxmox-video";
          sshOpts = [ "-A" ];
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.proxmox-video;
          };
        };

        proxmox-gaming = {
          hostname = "proxmox-gaming";
          sshOpts = [ "-A" ];
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.proxmox-gaming;
          };
        };

        proxmox-observability = {
          hostname = "proxmox-observability";
          sshOpts = [ "-A" ];
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.proxmox-observability;
          };
        };

        proxmox-db = {
          hostname = "proxmox-db";
          sshOpts = [ "-A" ];
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.proxmox-db;
          };
        };

        xcloud-caddy = {
          hostname = "xcloud-caddy";
          sshOpts = [ "-A" ];
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.xcloud-caddy;
          };
        };

        xcloud-postgres = {
          hostname = "xcloud-postgres";
          sshOpts = [ "-A" ];
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.xcloud-postgres;
          };
        };

        rpi4 = {
          hostname = "rpi4";
          remoteBuild = true;
          sshOpts = [ "-A" ];
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.rpi4;
          };
        };
      };
    };
}
