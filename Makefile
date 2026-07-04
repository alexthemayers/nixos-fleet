.PHONY: deploy deploy-cloud deploy-proxmox deploy-gaming deploy-rpi lint build fmt edit-secrets reboot-all

CLOUD_TARGETS   := .\#xcloud-caddy .\#xcloud-postgres
PROXMOX_TARGETS := .\#proxmox-video .\#proxmox-gaming .\#proxmox-observability .\#proxmox-gitlab .\#proxmox-db
GAMING_TARGETS  := .\#gaming
RPI_TARGETS  := .\#rpi4

deploy: lint build
	nix run github:serokell/deploy-rs -- \
	--targets $(CLOUD_TARGETS) $(PROXMOX_TARGETS) $(GAMING_TARGETS) $(RPI_TARGETS) \
	--debug-logs \
	--skip-checks
    
deploy-proxmox:
	nix run github:serokell/deploy-rs -- \
	--targets $(PROXMOX_TARGETS) \
	--debug-logs \
	--skip-checks

deploy-cloud:
	nix run github:serokell/deploy-rs -- \
	--targets $(CLOUD_TARGETS) \
	--debug-logs \
	--skip-checks

deploy-gaming:
	nix run github:serokell/deploy-rs -- \
	--targets $(GAMING_TARGETS) \
	--debug-logs \
	--skip-checks
	
deploy-rpi:
	nix run github:serokell/deploy-rs -- \
	--targets $(RPI_TARGETS) \
	--debug-logs \
	--remote-build \
	--skip-checks
	
lint:
	./scripts/lint.sh

build:
	./scripts/build.sh

fmt: 
	nix fmt 

edit-secrets:
	sops secrets/secrets.yaml
	sops updatekeys secrets/secrets.yaml

reboot-all:
	@for host in xcloud-caddy xcloud-postgres proxmox-video proxmox-gaming proxmox-observability proxmox-gitlab proxmox-db gaming rpi4; do \
		echo "Rebooting $$host..."; \
		ssh -o ConnectTimeout=3 root@$$host "reboot" || echo "Failed to reboot $$host"; \
	done