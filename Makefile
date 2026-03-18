deploy: deploy-cloud deploy-proxmox # deploy-gaming 

deploy-proxmox: lint
	nix run github:serokell/deploy-rs -- \
	--targets .#proxmox-video .#proxmox-gaming .#proxmox-observability .#proxmox-gitlab \
	--remote-build \
	--skip-checks
	
deploy-cloud: lint
	nix run github:serokell/deploy-rs -- \
	--targets .#xcloud-caddy .#xcloud-postgres \
	--remote-build \
	--skip-checks

deploy-gaming: lint
	nix run github:serokell/deploy-rs -- \
	--targets .#gaming \
	--remote-build \
	--skip-checks

lint: 
	nix flake check --all-systems
