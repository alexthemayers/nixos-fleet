deploy: 
	nix run github:nix-community/nixos-anywhere -- --flake .#nixos-xcloud root@$(IP)

lint: 
	nix fmt *.nix
