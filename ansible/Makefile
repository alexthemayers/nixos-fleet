.PHONY: help check apply deploy lint vault-edit ssh upgrade reboot

INVENTORY = inventory/proxmox.ini
PLAYBOOK = proxmox.yml

help:
	@echo "Proxmox Ansible Playbook Management"
	@echo ""
	@echo "Usage:"
	@echo "  make check        - Run ansible-playbook in dry-run mode (--check)"
	@echo "  make apply        - Run ansible-playbook to apply configurations (deploy)"
	@echo "  make deploy       - Alias for 'make apply'"
	@echo "  make lint         - Run ansible-lint against the playbook and roles"
	@echo "  make vault-edit   - Edit the encrypted Vault file (group_vars/all/vault.yml)"
	@echo "  make ssh          - Connect to the Proxmox host via SSH"
	@echo "  make upgrade      - Run apt dist-upgrade on the Proxmox host using Ansible ad-hoc"
	@echo "  make reboot       - Reboot the Proxmox host using Ansible ad-hoc"
	@echo ""

check:
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --check --diff

apply:
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --diff

deploy: apply

lint:
	ansible-lint $(PLAYBOOK)

vault-edit:
	ansible-vault edit group_vars/all/vault.yml

ssh:
	ssh root@proxmox

upgrade:
	ansible pve -i $(INVENTORY) -b -m apt -a "upgrade=dist update_cache=yes"

reboot:
	ansible pve -i $(INVENTORY) -b -m reboot
