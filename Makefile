.PHONY: deploy deploy-cloud deploy-proxmox deploy-gaming lint fmt edit-secrets

CLOUD_TARGETS   := .\#xcloud-caddy .\#xcloud-postgres
PROXMOX_TARGETS := .\#proxmox-video .\#proxmox-gaming .\#proxmox-observability .\#proxmox-gitlab
GAMING_TARGETS  := .\#gaming

deploy: lint
	nix run github:serokell/deploy-rs -- \
	--targets $(CLOUD_TARGETS) $(PROXMOX_TARGETS) $(GAMING_TARGETS) \
	--remote-build \
	--skip-checks
    
deploy-proxmox: lint
	nix run github:serokell/deploy-rs -- \
	--targets $(PROXMOX_TARGETS) \
	--remote-build \
	--skip-checks

deploy-cloud: lint
	nix run github:serokell/deploy-rs -- \
	--targets $(CLOUD_TARGETS) \
	--remote-build \
	--skip-checks

deploy-gaming: lint
	nix run github:serokell/deploy-rs -- \
	--targets $(GAMING_TARGETS) \
	--skip-checks

lint:
	nix flake check --all-systems

fmt: 
	nix fmt 

edit-secrets:
	sops secrets/secrets.yaml
	sops updatekeys secrets/secrets.yaml