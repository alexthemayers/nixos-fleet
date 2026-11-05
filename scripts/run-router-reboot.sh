#!/usr/bin/env bash
# Run scripts/router-reboot.py on proxmox-dev (the router is LAN-only).
#
#   ./scripts/run-router-reboot.sh status
#   ./scripts/run-router-reboot.sh reboot [--force] [--dry-run]
#
# Copies the script and the sops file to proxmox-dev. sops decrypts there with
# the host SSH key; the plaintext password never touches disk or a command
# line. `reboot` runs as a transient systemd unit and this wrapper follows its
# log, because the SSH path drops while the router restarts.
# See docs/runbooks/router-reboot.md.
set -euo pipefail

cd "$(dirname "$0")/.."

HOST="${ROUTER_RUN_HOST:-root@proxmox-dev}"
DIR=/root/router-reboot
LOG="$DIR/last-run.log"

cmd="${1:-}"
if [ "$cmd" != status ] && [ "$cmd" != reboot ]; then
	echo "usage: $0 status | reboot [--force] [--dry-run]" >&2
	exit 64
fi
shift
args=$(printf '%q ' "$cmd" "$@")

rsync -lt scripts/router-reboot.py "$HOST:$DIR/router-reboot.py"
rsync -lt secrets/router/secrets.yaml "$HOST:$DIR/secrets.yaml"
ssh "$HOST" "chown root:root $DIR/* && chmod 700 $DIR/router-reboot.py && chmod 600 $DIR/secrets.yaml"

if [ "$cmd" = status ]; then
	ssh "$HOST" "cd $DIR && python3 router-reboot.py $args"
	exit $?
fi

unit="router-reboot-$(date +%s)"
ssh "$HOST" ": > $LOG && systemd-run --quiet --unit=$unit --working-directory=$DIR \
	-p StandardOutput=append:$LOG -p StandardError=append:$LOG \
	python3 router-reboot.py $args"

pos=0
chunk=$(mktemp)
trap 'rm -f "$chunk"' EXIT
while true; do
	if ssh -o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 "$HOST" \
		"tail -c +$((pos + 1)) $LOG" >"$chunk" 2>/dev/null; then
		cat "$chunk"
		pos=$((pos + $(wc -c <"$chunk")))
		if grep -q '^EXIT=' "$chunk"; then
			code=$(grep '^EXIT=' "$chunk" | tail -1 | cut -d= -f2)
			exit "$code"
		fi
		# Unit gone with no EXIT line: the script crashed. Read the log.
		# systemctl is-active exits 3 for inactive; 255 is an SSH failure.
		if [ ! -s "$chunk" ]; then
			rc=0
			ssh -o ConnectTimeout=8 "$HOST" "systemctl is-active --quiet $unit" || rc=$?
			if [ "$rc" -eq 3 ]; then
				echo "router-reboot unit ended without an EXIT line; see $HOST:$LOG" >&2
				exit 1
			fi
		fi
	fi
	sleep 5
done
