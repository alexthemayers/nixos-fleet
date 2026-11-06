#!/usr/bin/env bash
# Offline ansible-lint + syntax-check for both Ansible trees. Installs Galaxy
# deps into a disposable path; does not need the vault password.
set -euo pipefail

# ansible / ansible-lint refuse non-UTF-8 locales (CI images and Darwin
# shells often have LC_ALL=C or an empty LANG). Prefer C.UTF-8: nixos/nix
# ships it; en_US.UTF-8 is often missing from the image locale-archive.
case "${LC_ALL:-${LANG:-}}" in
*UTF-8* | *utf8*) ;;
*)
  export LC_ALL=C.UTF-8
  export LANG=C.UTF-8
  ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
collections_path="$(mktemp -d "${TMPDIR:-/tmp}/nixos-fleet-ansible-collections.XXXXXX")"
cleanup() {
  rm -rf "$collections_path"
}
trap cleanup EXIT

# Force into the temp path so a stale ~/.ansible/collections does not
# satisfy the install and leave -p empty.
export ANSIBLE_COLLECTIONS_PATH="$collections_path:${root}/collections"
ansible-galaxy collection install --force \
  -r "$root/ansible/requirements.yml" \
  -p "$collections_path"
ansible-galaxy collection install --force \
  -r "$root/collections/ansible_collections/fleet/debian_guest/requirements.yml" \
  -p "$collections_path"
# Do not read ansible/.vault_pass.txt (gitignored; absent in CI).
unset ANSIBLE_VAULT_PASSWORD_FILE

cd "$root"

# Playbook entrypoints plus collection roles (not only site.yml).
ansible-lint --offline \
  ansible/proxmox.yml \
  collections/ansible_collections/fleet/debian_guest/playbooks/site.yml \
  collections/ansible_collections/fleet/debian_guest/roles

# Syntax-check both playbooks (no connect).
ansible-playbook --syntax-check ansible/proxmox.yml
ansible-playbook --syntax-check \
  -i collections/ansible_collections/fleet/debian_guest/inventory/hosts.yml \
  collections/ansible_collections/fleet/debian_guest/playbooks/site.yml

echo "✓ ansible-lint + syntax-check ok"
