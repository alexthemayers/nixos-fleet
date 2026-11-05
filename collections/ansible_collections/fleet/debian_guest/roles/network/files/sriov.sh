#!/bin/bash
# Apply the fleet iavf MAC, or print that interface's global IPv4.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: sriov.sh apply|address <mac>" >&2
  exit 2
fi

action=$1
mac=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')

modprobe iavf

iface=
for path in /sys/class/net/*; do
  name=$(basename "$path")
  if [ "$name" = "lo" ]; then
    continue
  fi
  driver=$(basename "$(readlink -f "$path/device/driver" 2>/dev/null)" 2>/dev/null || true)
  if [ "$driver" = "iavf" ]; then
    iface=$name
    break
  fi
done

if [ -z "$iface" ]; then
  echo "no iavf interface" >&2
  exit 1
fi

case "$action" in
  apply)
    current=$(cat "/sys/class/net/$iface/address")
    if [ "$current" != "$mac" ]; then
      ip link set "$iface" down
      ip link set "$iface" address "$mac"
      ip link set "$iface" up
      echo changed
      networkctl reload
      networkctl reconfigure "$iface"
    else
      echo ok
    fi
    ;;
  address)
    addr=$(ip -4 -o addr show dev "$iface" scope global | awk 'NR == 1 { split($4, a, "/"); print a[1] }')
    if [ -z "$addr" ]; then
      exit 1
    fi
    printf '%s\n' "$addr"
    ;;
  *)
    echo "usage: sriov.sh apply|address <mac>" >&2
    exit 2
    ;;
esac
