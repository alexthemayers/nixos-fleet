.PHONY: deploy deploy-host deploy-cloud-host proxmox-host-check deploy-debian-guest debian-guest-check deploy-debian-gitlab debian-gitlab-check deploy-debian-observability debian-observability-check deploy-debian-dev debian-dev-check deploy-gaming lint ansible-lint check-inventory check-mimir-rules check-obs-config check-dashboard-jobs check-secrets check-secrets-keys check-jellyfin-xml shellcheck test-router-reboot test-check-dashboard-jobs check-docs-links check-live-promql print-hosts print-deploy-paused fmt fmt-check edit-secrets updatekeys update-known-hosts reboot-all router-status reboot-router bench-jellyfin-io jellyfin-library-audit changed-hosts

# Single source of truth for the fleet inventory used by the operator targets.
# Keep in sync with config/fleet-inventory.nix; scripts/check-inventory.sh
# compares the two and CI fails when they drift.
# DEPLOY_PAUSED hosts stay in PROD_HOSTS (inventory) and are not activated.
CLOUD_HOSTS   := xcloud-caddy xcloud-postgres
GAMING_HOSTS  := gaming
DEPLOY_PAUSED :=

PROD_HOSTS := $(CLOUD_HOSTS) $(GAMING_HOSTS)

# Production activation is: build on this machine, nix-copy the
# closure, switch. Paused hosts are skipped.
define deploy_hosts
	@for host in $(1); do \
		case " $(DEPLOY_PAUSED) " in \
			*" $$host "*) echo "Skipping $$host (deploy paused)"; continue ;; \
		esac; \
		./scripts/deploy-host.sh $$host; \
	done
endef

deploy: lint
	$(call deploy_hosts,$(PROD_HOSTS))

deploy-host:
	@if [ -z "$(HOST)" ]; then \
		echo "ERROR: HOST is not set. Usage: make deploy-host HOST=<hostname>"; \
		echo "Known hosts: $(PROD_HOSTS)"; \
		exit 1; \
	fi
	./scripts/deploy-host.sh $(HOST)

deploy-proxmox-host:
	cd ansible && ansible-playbook -i inventory/proxmox.ini proxmox.yml

proxmox-host-check:
	cd ansible && ansible-playbook -i inventory/proxmox.ini proxmox.yml --check --diff

# Debian guests (VM 109 apps, VM 110 GitLab). Not the hypervisor playbook.
# site.yml refuses to run without --limit. Extra flags: ANSIBLE_ARGS="--tags jellyfin".
# PROXMOX_ANSIBLE_HOST overrides the hypervisor name when it does not resolve.
DEBIAN_GUEST_DIR := collections/ansible_collections/fleet/debian_guest
DEBIAN_GUEST_PLAY = ANSIBLE_CONFIG=$(DEBIAN_GUEST_DIR)/ansible.cfg \
	ANSIBLE_COLLECTIONS_PATH=collections:$(HOME)/.ansible/collections \
	ansible-playbook -i $(DEBIAN_GUEST_DIR)/inventory/hosts.yml \
		$(DEBIAN_GUEST_DIR)/playbooks/site.yml

deploy-debian-guest:
	$(DEBIAN_GUEST_PLAY) --limit proxmox-applications-debian $(ANSIBLE_ARGS)

debian-guest-check:
	$(DEBIAN_GUEST_PLAY) --limit proxmox-applications-debian --check --diff $(ANSIBLE_ARGS)

# VM 110. Omnibus GitLab on Debian.
deploy-debian-gitlab:
	$(DEBIAN_GUEST_PLAY) --limit proxmox-gitlab-debian $(ANSIBLE_ARGS)

debian-gitlab-check:
	$(DEBIAN_GUEST_PLAY) --limit proxmox-gitlab-debian --check --diff $(ANSIBLE_ARGS)

# VM 111. MagicDNS hostname proxmox-observability-debian.
deploy-debian-observability:
	$(DEBIAN_GUEST_PLAY) --limit proxmox-observability-debian $(ANSIBLE_ARGS)

debian-observability-check:
	$(DEBIAN_GUEST_PLAY) --limit proxmox-observability-debian --check --diff $(ANSIBLE_ARGS)

# VM 112. MagicDNS stays proxmox-dev.
deploy-debian-dev:
	$(DEBIAN_GUEST_PLAY) --limit proxmox-dev-debian $(ANSIBLE_ARGS)

debian-dev-check:
	$(DEBIAN_GUEST_PLAY) --limit proxmox-dev-debian --check --diff $(ANSIBLE_ARGS)

deploy-cloud:
	$(call deploy_hosts,$(CLOUD_HOSTS))

deploy-gaming:
	./scripts/deploy-host.sh gaming

lint:
	./scripts/lint.sh

# Offline ansible-lint for ansible/ and fleet.debian_guest. Not folded into
# make lint (Nix flake check stays Nix-only).
ansible-lint:
	./scripts/ansible-lint.sh

check-inventory:
	./scripts/check-inventory.sh

check-jellyfin-xml:
	./scripts/check-jellyfin-xml.sh

shellcheck:
	./scripts/shellcheck.sh

# Hygiene + promtool for the committed Prometheus alert rules.
# Hygiene runs on Darwin; promtool needs x86_64 (CI / proxmox-dev).
check-mimir-rules:
	./scripts/check-mimir-rules.sh

# promtool + amtool on committed observability YAML. In GitLab CI.
check-obs-config:
	./scripts/check-obs-config.sh

# Dashboard/rules PromQL job= and host= vs scrapes/inventory. Needs nix eval
# unless HOSTS_JSON is set. In CI via check-obs-config.
check-dashboard-jobs:
	@hosts_json=$$(mktemp); \
	trap 'rm -f "$$hosts_json"' EXIT; \
	if [ -n "$${HOSTS_JSON:-}" ]; then cp "$$HOSTS_JSON" "$$hosts_json"; \
	else nix eval --json \
	  '.#nixosConfigurations.xcloud-caddy.config.fleet.inventory.hosts' \
	  >"$$hosts_json"; fi; \
	python3 ./scripts/check-dashboard-jobs.py "$$hosts_json"

# Requires the operator age key. Not run in CI.
check-secrets:
	./scripts/check-secrets.sh

# Required secret key *names* without decrypt. In GitLab + GitHub CI.
check-secrets-keys:
	python3 ./scripts/check-secrets-keys.py

# Pure helpers in router-reboot.py (no live router).
test-router-reboot:
	python3 ./scripts/test_router_reboot.py

# Pure helpers in check-dashboard-jobs.py (no flake eval).
test-check-dashboard-jobs:
	python3 ./scripts/test_check_dashboard_jobs.py

# Relative markdown links + scripts/* refs outside ADRs.
check-docs-links:
	python3 ./scripts/check-docs-links.py

# Live Prometheus sample. Manual / scheduled only; allow_failure in CI.
check-live-promql:
	./scripts/check-live-promql.sh

# Consumed by scripts/check-inventory.sh.
print-hosts:
	@echo $(PROD_HOSTS)

print-deploy-paused:
	@echo $(DEPLOY_PAUSED)

# Hosts whose toplevel outPath differs from BEFORE (default origin/main).
BEFORE ?= origin/main
changed-hosts:
	./scripts/changed-hosts.sh $(BEFORE)

# 4K Jellyfin I/O bench (transcode + Direct Play). Builds x86_64-linux Go on
# proxmox-dev, runs on proxmox-applications-debian.
# Override: HOST=... DURATION=120s BENCH_CMD=directplay
BENCH_CMD ?= all
bench-jellyfin-io:
	./scripts/run-jellyfin-io-bench.sh $(BENCH_CMD)

# Read-only media-share audit on proxmox-applications-debian (NFO ids,
# multi-movie folders, nested season packs, rarsets, AppleDouble).
# Override: HOST= MEDIA=
jellyfin-library-audit:
	./scripts/jellyfin-library-audit.sh

fmt:
	nix fmt

fmt-check:
	nix fmt -- --ci 

# Per-host secret files live at secrets/<hostname>/secrets.yaml.
# NixOS: host flake name. Ansible guests: inventory MagicDNS name
# (e.g. HOST=proxmox-applications-debian). See docs/adr/2026-11-06-ansible-guest-secrets.md.
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

# Router (192.168.3.1) web admin from proxmox-dev. router-status logs in and
# prints Tailscale paths, no reboot. reboot-router reboots it; refuses
# 01:30-05:30 unless ROUTER_ARGS=--force. Only when the operator asks
# (.cursor/rules/router-reboot.mdc, docs/runbooks/router-reboot.md).
router-status:
	./scripts/run-router-reboot.sh status

reboot-router:
	./scripts/run-router-reboot.sh reboot $(ROUTER_ARGS)

# gaming is the usual deploy builder and a desktop; do not reboot it with the
# fleet.
reboot-all:
	@for host in $(CLOUD_HOSTS); do \
		echo "Rebooting $$host..."; \
		ssh -o ConnectTimeout=3 root@$$host "reboot" || echo "Failed to reboot $$host"; \
	done
