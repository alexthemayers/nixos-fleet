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
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      disko,
      deploy-rs,
      sops-nix,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);

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
            # ./services/gitlab.nix
            ./services/keycloak.nix
            ./services/vaultwarden.nix
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
          ];
        };
        proxmox-gaming = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
          };
          modules = [
            disko.nixosModules.disko
            ./hosts/proxmox-gaming/configuration.nix
            ./disko/disk-config.nix
            ./config/basics.nix
            ./config/security.nix
            ./config/system.nix
            ./config/users.nix
            ./config/observability.nix
            ./services/tailscale.nix
            ./services/openarena.nix
            # ./services/foundry.nix
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
      };

      deploy.nodes = {
        proxmox-gitlab = {
          hostname = "proxmox-gitlab";
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.proxmox-gitlab;
          };
        };
        gaming = {
          hostname = "gaming";
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.gaming;
          };
        };
        proxmox-video = {
          hostname = "proxmox-video";
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.proxmox-video;
          };
        };

        proxmox-gaming = {
          hostname = "proxmox-gaming";
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.proxmox-gaming;
          };
        };

        proxmox-observability = {
          hostname = "proxmox-observability";
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.proxmox-observability;
          };
        };

        xcloud-caddy = {
          hostname = "xcloud-caddy";
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.xcloud-caddy;
          };
        };

        xcloud-postgres = {
          hostname = "xcloud-postgres";
          profiles.system = {
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.xcloud-postgres;
          };
        };
      };
    };
}
