{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.disko.url = "github:nix-community/disko";
  inputs.disko.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { nixpkgs, disko, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs systems
        (system: f nixpkgs.legacyPackages.${system});
    in {

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
      nixosConfigurations.nixos-anywhere-vm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          ./configuration.nix
          ./caddy.nix
          ./cleanup.nix
          ./tailscale.nix
        ];
      };
    };
}
