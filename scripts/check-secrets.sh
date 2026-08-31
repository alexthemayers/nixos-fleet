#!/usr/bin/env bash
# Compare each host's declared sops.secrets against the keys actually stored in
# secrets/<host>/secrets.yaml, in both directions.
#
#   missing  - declared in Nix but absent from the file. This is a failed
#              activation: sops-nix cannot render the secret and the deploy dies.
#   unused   - present in the file but not declared by that host. Harmless to
#              run, but it is a credential handed to a machine with no need for
#              it, which is exactly how the shared Garage and S3 keys ended up
#              readable from a privileged CI runner.
#
# Requires the operator's age key, so it runs locally rather than in CI.
# CI enforces the "missing" direction cheaply via the eval assertion in
# config/fleet-inventory.nix.
set -uo pipefail

cd "$(dirname "$0")/.."

HOSTS=$(nix eval --json '.#nixosConfigurations' --apply builtins.attrNames |
  python3 -c 'import sys,json; print(" ".join(json.load(sys.stdin)))')

status=0

for host in $HOSTS; do
  file="secrets/$host/secrets.yaml"
  if [ ! -f "$file" ]; then
    echo "$host: no $file"
    continue
  fi

  declared=$(nix eval --json ".#nixosConfigurations.$host.config.sops.secrets" 2>/dev/null |
    python3 -c 'import sys,json; print("\n".join(sorted(json.load(sys.stdin).keys())))')

  stored=$(sops -d --output-type json "$file" 2>/dev/null | python3 -c '
import sys, json


def walk(node, prefix=""):
    if isinstance(node, dict):
        for k, v in node.items():
            yield from walk(v, f"{prefix}{k}/")
    else:
        yield prefix.rstrip("/")


print("\n".join(sorted(walk(json.load(sys.stdin)))))
')

  missing=$(comm -23 <(echo "$declared") <(echo "$stored"))
  unused=$(comm -13 <(echo "$declared") <(echo "$stored"))

  if [ -n "$missing" ]; then
    echo "$host: MISSING (declared in Nix, absent from $file):"
    echo "$missing" | sed 's/^/    /'
    status=1
  fi

  if [ -n "$unused" ]; then
    echo "$host: unused (stored but never declared):"
    echo "$unused" | sed 's/^/    /'
  fi

  [ -z "$missing" ] && [ -z "$unused" ] && echo "$host: ok"
done

exit "$status"
