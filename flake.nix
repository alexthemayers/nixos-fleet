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
      # aarch64-darwin: laptop formatter and devShell. No aarch64-linux
      # NixOS hosts (rpi4 decommissioned).
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Host keys are pinned in ssh/fleet_known_hosts and installed as the
      # global known_hosts (config/basics.nix), so deploys verify them.
      # -A is deliberately absent: nothing in an activation needs the operator's
      # SSH agent, and forwarding it to every deploy target is a needless risk.
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
      # On the 1 GiB postgres VM that OOM-killed nix-daemon, so every node
      # builds on the deployer instead. Deploy-host.sh sets remoteBuild =
      # false for the cloud VMs for the same reason.
      # fastConnection = true: nix copy from this builder store. The target
      # does not fetch NARs during the copy. Host nix.conf still lists
      # cache.nixos.org for everything else.
      mkNode =
        {
          hostname,
          system ? "x86_64-linux",
          remoteBuild ? true,
          magicRollback ? true,
        }:
        {
          inherit hostname remoteBuild magicRollback;
          fastConnection = true;
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

      mkSystem =
        modules:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
          };
          inherit modules;
        };

      # Reads fleet/apps/*.nix (not config.fleet.apps) so heavy modules are
      # only imported on the host that runs them.
      # See docs/adr/2026-09-18-fleet-apps-enable-by-host.md.
      fleetAppModules = import ./config/fleet-app-imports.nix nixpkgs.lib;
    in
    {
      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
      packages = forAllSystems (
        pkgs:
        {
          # GitLab jobs use the nixos/nix image (Nix preinstalled) plus this
          # join: bash, make, openssh, python3, rsync, ansible, ansible-lint.
          ci-tools = pkgs.symlinkJoin {
            name = "ci-tools";
            paths = [
              pkgs.ansible
              pkgs.ansible-lint
              # amtool: attr is prometheus-alertmanager (not pkgs.alertmanager).
              pkgs.prometheus-alertmanager
              pkgs.bash
              pkgs.coreutils
              pkgs.diffutils
              pkgs.findutils
              pkgs.git
              pkgs.gnugrep
              pkgs.gnumake
              pkgs.gnused
              pkgs.gnutar
              pkgs.gzip
              pkgs.openssh
              # promtool is the prometheus.cli output, not pkgs.prometheus.
              pkgs.prometheus.cli
              (pkgs.python3.withPackages (ps: [ ps.pyyaml ]))
              pkgs.rsync
              pkgs.shellcheck
            ]
            # check-vector-config runs `vector validate`. Darwin builds Vector
            # from source, so Darwin skips it (ALLOW_NO_VECTOR=1).
            ++ nixpkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.vector;
            meta.description = "CLI tools GitLab jobs need on top of nixos/nix";
          };
        }
        // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          jellyfin-io-bench = pkgs.buildGoModule {
            pname = "jellyfin-io-bench";
            version = "1.0.0";
            src = ./scripts/jellyfin-io-bench;
            vendorHash = null;
            env.CGO_ENABLED = "0";
            meta.mainProgram = "jellyfin-io-bench";
            meta.description = "Jellyfin 4K transcode and Direct Play I/O bench; run on proxmox-applications-debian";
          };
        }
      );
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          buildInputs = [
            deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.deploy-rs
            pkgs.git
            pkgs.openssh
            pkgs.gnumake
            # scripts/check-inventory.sh and scripts/check-secrets.sh
            pkgs.python3
          ];
        };
      });
      checks = nixpkgs.lib.genAttrs [ "x86_64-linux" ] (
        system:
        let
          nodesForSystem = nixpkgs.lib.filterAttrs (
            name: node: self.nixosConfigurations.${name}.pkgs.stdenv.hostPlatform.system == system
          ) self.deploy.nodes;
        in
        deploy-rs.lib.${system}.deployChecks { nodes = nodesForSystem; }
      );
      nixosConfigurations = {
        xcloud-postgres = mkSystem (
          commonModules
          ++ [
            disko.nixosModules.disko
            ./config/xcloud-vm.nix
            ./hosts/xcloud-postgres/disk-config.nix
            ./hosts/xcloud-postgres/configuration.nix
            ./services/postgres.nix
          ]
          ++ fleetAppModules "xcloud-postgres"
        );

        xcloud-caddy = mkSystem (
          commonModules
          ++ [
            disko.nixosModules.disko
            ./disko/disk-config.nix
            ./config/xcloud-vm.nix
            ./hosts/xcloud-caddy/configuration.nix
          ]
          ++ fleetAppModules "xcloud-caddy"
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
      };

      deploy.nodes = {
        xcloud-caddy = mkNode {
          hostname = "xcloud-caddy";
          remoteBuild = false;
        };
        xcloud-postgres = mkNode {
          hostname = "xcloud-postgres";
          remoteBuild = false;
        };
        gaming = mkNode {
          hostname = "gaming";
          remoteBuild = false;
        };
      };
    };
}
