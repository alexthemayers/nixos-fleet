{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = inputs@{ self, nixpkgs, ... }: 
    let
      systems = [ "x86_64-linux" "aarch64-darwin" ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs systems
        (system: f nixpkgs.legacyPackages.${system});
    in {
      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./configuration.nix
	./jellyfin
      ];
    };
  };
}
