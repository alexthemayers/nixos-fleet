.PHONY: deploy deploy-from-attic deploy-rs deploy-cloud deploy-proxmox deploy-proxmox-host proxmox-host-check deploy-gaming deploy-rpi lint check-inventory check-mimir-rules check-secrets print-hosts build build-rpi build-remote verify-from-attic verify-from-attic-rpi fmt fmt-check edit-secrets updatekeys update-known-hosts reboot-all bench-jellyfin-io changed-hosts

# Single source of truth for the fleet inventory used by the operator targets.
# Keep in sync with config/fleet-inventory.nix; scripts/check-inventory.sh
# compares the two and CI fails when they drift.
CLOUD_HOSTS   := xcloud-caddy xcloud-postgres
PROXMOX_HOSTS := proxmox-applications-1 proxmox-applications-2 proxmox-observability proxmox-dev
RPI_HOSTS     := rpi4
GAMING_HOSTS  := gaming

PROD_HOSTS := $(CLOUD_HOSTS) $(PROXMOX_HOSTS) $(RPI_HOSTS) $(GAMING_HOSTS)

flake_target = $(addprefix .\#,$(1))

CLOUD_TARGETS   := $(call flake_target,$(CLOUD_HOSTS))
PROXMOX_TARGETS := $(call flake_target,$(PROXMOX_HOSTS))
GAMING_TARGETS  := $(call flake_target,$(GAMING_HOSTS))
RPI_TARGETS     := $(call flake_target,$(RPI_HOSTS))

# deploy-rs remains available as a fallback (magicRollback). Production
# activation copies the closure from Attic, then switch-to-configuration.
# nix-develop.sh fills the shell into Attic then uses Attic-only substituters
# when ATTIC_TOKEN is set; otherwise it is plain `nix develop`.
DEPLOY := ./scripts/nix-develop.sh -c deploy

require-attic-token = @if [ -z "$$ATTIC_TOKEN" ] && [ ! -s /root/.attic-token ]; then \
	echo "ERROR: ATTIC_TOKEN is not set. Export it or write /root/.attic-token"; \
	exit 1; \
fi

deploy: lint
	$(require-attic-token)
	@for host in $(PROD_HOSTS); do \
		if [ "$$host" = "rpi4" ]; then \
			./scripts/run-on-rpi4.sh ./scripts/deploy-from-attic.sh rpi4 || echo "Skipping rpi4 (unreachable or failed)"; \
			continue; \
		fi; \
		./scripts/deploy-from-attic.sh $$host; \
	done

deploy-from-attic:
	$(require-attic-token)
	@if [ -z "$(HOST)" ]; then \
		echo "ERROR: HOST is not set. Usage: make deploy-from-attic HOST=<hostname>"; \
		echo "Known hosts: $(PROD_HOSTS)"; \
		exit 1; \
	fi
	./scripts/deploy-from-attic.sh $(HOST)

# Old path: nix copy from the builder store via deploy-rs.
deploy-rs: lint build
	$(DEPLOY) \
	--targets $(CLOUD_TARGETS) $(PROXMOX_TARGETS) $(RPI_TARGETS) $(GAMING_TARGETS) \
	--debug-logs

deploy-proxmox:
	$(require-attic-token)
	@for host in $(PROXMOX_HOSTS); do \
		./scripts/deploy-from-attic.sh $$host; \
	done

deploy-proxmox-host:
	cd ansible && ansible-playbook -i inventory/proxmox.ini proxmox.yml

proxmox-host-check:
	cd ansible && ansible-playbook -i inventory/proxmox.ini proxmox.yml --check --diff

deploy-cloud:
	$(require-attic-token)
	@for host in $(CLOUD_HOSTS); do \
		./scripts/deploy-from-attic.sh $$host; \
	done

deploy-gaming:
	$(require-attic-token)
	./scripts/deploy-from-attic.sh gaming

deploy-rpi:
	$(require-attic-token)
	./scripts/run-on-rpi4.sh ./scripts/deploy-from-attic.sh rpi4

lint:
	./scripts/lint.sh

check-inventory:
	./scripts/check-inventory.sh

# promtool validation of the generated Mimir rules: PromQL parsing and
# annotation templates, which the eval-time checks in services/mimir-rules.nix
# cannot do. The rules file is an x86_64-linux derivation, so this does not run
# on the Darwin checkout; run it on proxmox-dev. Not in CI, which is --no-build.
check-mimir-rules:
	./scripts/check-mimir-rules.sh

# Requires the operator age key. Not run in CI.
check-secrets:
	./scripts/check-secrets.sh

# Consumed by scripts/check-inventory.sh.
print-hosts:
	@echo $(PROD_HOSTS)

# Hosts whose toplevel outPath differs from BEFORE (default origin/main).
BEFORE ?= origin/main
changed-hosts:
	./scripts/changed-hosts.sh $(BEFORE)

build:
	./scripts/build.sh

# Native aarch64 fill on rpi4. Do not fill the Pi from proxmox-dev.
build-rpi:
	$(require-attic-token)
	./scripts/run-on-rpi4.sh ./scripts/build.sh

# Narinfo-check current-system tooling and hosts on Attic (no NAR download).
# Same script GitLab runs after fill-attic.
verify-from-attic:
	$(require-attic-token)
	./scripts/verify-from-attic.sh

verify-from-attic-rpi:
	$(require-attic-token)
	./scripts/run-on-rpi4.sh ./scripts/verify-from-attic.sh

build-remote:
	$(require-attic-token)
	rsync -avz --delete \
		--exclude='.git/' \
		--exclude='result' \
		--exclude='.direnv/' \
		--exclude='.devenv/' \
		--exclude='.idea/' \
		./ root@proxmox-dev:/tmp/nixos-fleet/
	ssh root@proxmox-dev "cd /tmp/nixos-fleet && \
		ATTIC_TOKEN=\"$$ATTIC_TOKEN\" ./scripts/build.sh"

# 4K Jellyfin I/O bench (transcode + Direct Play). Builds x86_64-linux Go on
# proxmox-dev, runs on apps-1.
# Override: HOST=... DURATION=120s BENCH_CMD=directplay
BENCH_CMD ?= all
bench-jellyfin-io:
	./scripts/run-jellyfin-io-bench.sh $(BENCH_CMD)

fmt:
	nix fmt

fmt-check:
	nix fmt -- --ci 

# Per-host secret files live at secrets/<hostname>/secrets.yaml.
# Usage: make edit-secrets HOST=proxmox-applications-1
edit-secrets:
	@if [ -z "$(HOST)" ]; then \
		echo "ERROR: HOST is not set. Usage: make edit-secrets HOST=<hostname>"; \
		echo "Known hosts: $(PROD_HOSTS)"; \
		exit 1; \
	fi
	@if [ ! -f secrets/$(HOST)/secrets.yaml ]; then \
		echo "ERROR: secrets/$(HOST)/secrets.yaml does not exist."; \
		exit 1; \
	fi
	sops secrets/$(HOST)/secrets.yaml

update-known-hosts:
	./scripts/update-known-hosts.sh

# Rekey every host file after changing recipients in .sops.yaml.
updatekeys:
	@for host in $(PROD_HOSTS); do \
		if [ -f secrets/$$host/secrets.yaml ]; then \
			echo "Updating keys for $$host..."; \
			sops updatekeys --yes secrets/$$host/secrets.yaml; \
		fi; \
	done

# gaming is the usual deploy builder and a desktop; do not reboot it with the
# fleet. rpi4 is skipped when it does not answer.
reboot-all:
	@for host in $(CLOUD_HOSTS) $(PROXMOX_HOSTS) $(RPI_HOSTS); do \
		echo "Rebooting $$host..."; \
		ssh -o ConnectTimeout=3 root@$$host "reboot" || echo "Failed to reboot $$host"; \
	done
