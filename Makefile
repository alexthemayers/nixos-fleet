deploy: deploy-cloud deploy-proxmox deploy-gaming 

deploy-proxmox: lint
	nix run github:serokell/deploy-rs -- \
	--targets .#proxmox-video .#proxmox-gaming .#proxmox-observability .#proxmox-gitlab \
	--skip-checks
	
deploy-cloud: lint
	nix run github:serokell/deploy-rs -- \
	--targets .#xcloud-caddy .#xcloud-postgres \
	--skip-checks

deploy-gaming: lint
	nix run github:serokell/deploy-rs -- \
	--targets .#gaming \
	--skip-checks

lint:
	nix flake check --all-systems

fmt: 
	nix fmt 

edit-secrets:
	sops secrets/secrets.yaml
	sops updatekeys secrets/secrets.yaml
