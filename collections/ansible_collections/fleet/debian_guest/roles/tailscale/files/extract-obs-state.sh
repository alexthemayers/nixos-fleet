#!/bin/bash
# Stop VM 103 and copy its local state off the qcow2. One writer: the
# Debian guest is about to take the Tailscale node and the ntfy database.
set -euo pipefail

vmid="${1:?vmid}"
dest="${2:?dest}"

if qm status "$vmid" | grep -q running; then
  qm shutdown "$vmid" --timeout 120 || true
fi

stopped=0
for _ in $(seq 1 36); do
  if qm status "$vmid" | grep -q stopped; then
    stopped=1
    break
  fi
  sleep 5
done
if [ "$stopped" -ne 1 ]; then
  qm stop "$vmid"
  sleep 3
fi
qm status "$vmid" | grep -q stopped

if ! command -v guestfish >/dev/null 2>&1; then
  apt-get update
  apt-get install -y libguestfs-tools
fi

vol=$(qm config "$vmid" | sed -n 's/^scsi0: //p' | cut -d, -f1)
disk=$(pvesm path "$vol")
rm -rf "$dest"
mkdir -p "$dest"

if [ "$#" -gt 2 ]; then
  paths=("${@:3}")
else
  paths=(
    /var/lib/tailscale
    /var/lib/ntfy-sh
    /var/lib/grafana
    /var/lib/alertmanager
    /var/lib/prometheus/alertmanager
    /var/lib/loki
  )
fi

# NixOS root is LVM. One appliance lists the directories; a second copies
# the ones that exist. virt-copy-out cannot inspect this disk.
# One is-dir and one is-file per path. A runner config is a file; the
# Tailscale state and the backup tree are directories.
checks=""
for path in "${paths[@]}"; do
  checks+="is-dir ${path}"$'\n'"is-file ${path}"$'\n'
done
present=$(guestfish --ro -a "$disk" <<EOF
run
mount /dev/pool/root /
$checks
EOF
)

fish=$(mktemp)
{
  echo run
  echo "mount /dev/pool/root /"
  i=0
  while IFS= read -r is_dir && IFS= read -r is_file; do
    path="${paths[$i]}"
    i=$((i + 1))
    if [ "$is_dir" = "true" ] || [ "$is_file" = "true" ]; then
      echo "copy-out $path $dest"
    else
      echo "skip $path" >&2
    fi
  done <<<"$present"
} >"$fish"

guestfish --ro -a "$disk" -f "$fish"
rm -f "$fish"
find "$dest" -maxdepth 2 -type d -printf '%p\n'
