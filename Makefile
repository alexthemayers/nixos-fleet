.PHONY: deploy deploy-cloud deploy-proxmox deploy-gaming deploy-rpi lint fmt edit-secrets

CLOUD_TARGETS   := .\#xcloud-caddy .\#xcloud-postgres
PROXMOX_TARGETS := .\#proxmox-video .\#proxmox-gaming .\#proxmox-observability .\#proxmox-gitlab
GAMING_TARGETS  := .\#gaming
RPI_TARGETS  := .\#rpi4

deploy: lint
	nix run github:serokell/deploy-rs -- \
	--targets $(CLOUD_TARGETS) $(PROXMOX_TARGETS) $(GAMING_TARGETS) $(RPI_TARGETS) \
	--remote-build \
	--skip-checks
    
deploy-proxmox:
	nix run github:serokell/deploy-rs -- \
	--targets $(PROXMOX_TARGETS) \
	--remote-build \
	--skip-checks

deploy-cloud:
	nix run github:serokell/deploy-rs -- \
	--targets $(CLOUD_TARGETS) \
	--remote-build \
	--skip-checks

deploy-gaming:
	nix run github:serokell/deploy-rs -- \
	--targets $(GAMING_TARGETS) \
	--remote-build \
	--skip-checks
	
deploy-rpi:
	nix run github:serokell/deploy-rs -- \
	--targets $(RPI_TARGETS) \
	--remote-build \
	--skip-checks
	
lint:
	nix flake check --all-systems

fmt: 
	nix fmt 

edit-secrets:
	sops secrets/secrets.yaml
	sops updatekeys secrets/secrets.yaml