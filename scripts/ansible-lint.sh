#!/usr/bin/env bash
# Offline ansible-lint for both Ansible trees. Installs Galaxy deps into a
# disposable path; does not need the vault password.
set -euo pipefail

# ansible / ansible-lint refuse non-UTF-8 locales (CI images and Darwin
# shells often have LC_ALL=C or an empty LANG).
case "${LC_ALL:-${LANG:-}}" in
*UTF-8* | *utf8*) ;;
*)
  export LC_ALL=en_US.UTF-8
  export LANG=en_US.UTF-8
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
ansible-lint --offline \
  ansible/proxmox.yml \
  collections/ansible_collections/fleet/debian_guest/playbooks/site.yml
