# How-To: Dynamic Tailscale IP Injection

Clustered applications (e.g., Loki, Mimir, Alertmanager) require nodes to peer with each other over the network. In
`nixos-fleet`, all node-to-node communication occurs over the encrypted Tailscale mesh (`tailscale0`).

However, Tailscale IPs are dynamically allocated. Hardcoding IPs in your NixOS configuration modules breaks if a node's
IP changes or if you deploy a new node.

To solve this, we resolve the address **once at unit start** and hand it to the daemon through an `EnvironmentFile`.

## Implementation Concept

Add a bounded `ExecStartPre` that writes the discovered address into a file under `/run`, then list that file as an
`EnvironmentFile`. Upstream's `ExecStart` is left alone.

### Example (Loki / Mimir gossip)

1. **Write the resolver script.** It retries for a bounded period and *fails* if the interface never appears:

   ```nix
   let
     clusterEnvFile = "/run/loki-cluster.env";

     clusterEnvScript = pkgs.writeShellScript "loki-cluster-env" ''
       set -euo pipefail

       tailscale_ip() {
         ${pkgs.tailscale}/bin/tailscale ip -4 2>/dev/null | head -n1 && return 0
         ${pkgs.iproute2}/bin/ip -4 addr show dev tailscale0 2>/dev/null \
           | ${pkgs.gawk}/bin/awk '/inet /{print $2}' | cut -d/ -f1 | head -n1
       }

       ip=""
       for _ in $(seq 1 60); do
         ip=$(tailscale_ip || true)
         [ -n "$ip" ] && break
         sleep 1
       done

       if [ -z "$ip" ]; then
         echo "tailscale0 still has no IPv4 address after 60s; refusing to start Loki" >&2
         exit 1
       fi

       umask 077
       echo "LOKI_CLUSTER_IP=$ip" > ${clusterEnvFile}
     '';
   in
   ```

2. **Wire it into the unit.** The `+` prefix runs the pre-script as root, which it needs in order to write to `/run`
   even when the service itself is sandboxed:

   ```nix
   systemd.services.loki = {
     after = [ "tailscaled.service" "network-online.target" ];
     wants = [ "tailscaled.service" "network-online.target" ];
     serviceConfig = {
       ExecStartPre = [ "+${clusterEnvScript}" ];
       EnvironmentFile = [ clusterEnvFile ];
     };
   };
   ```

3. **Configure the application** to expand the environment variable:

   ```yaml
   # In your loki.yml config
   memberlist:
     bind_addr: ''${LOKI_CLUSTER_IP}
   ```

   Loki needs `-config.expand-env=true` for this; check the equivalent flag for other daemons.

## Do not override ExecStart with a polling loop

An earlier version of this pattern replaced `ExecStart` with a `/bin/sh -c` string containing an unbounded
`while ! ip addr show dev tailscale0; do sleep 1; done` loop before `exec`ing the daemon.

That is worse in three specific ways, and all three bit us:

- **It never fails.** A host where `tailscaled` does not come up sits in `activating` forever. systemd's `Restart=`,
  start limits, and any alerting keyed on unit failure never trigger, so the outage is invisible.
- **The shell becomes PID 1 of the unit**, so signal handling and exit statuses belong to `sh`, not the daemon.
- **It discards upstream's `ExecStart`**, including config validation and flags the NixOS module derives for you. Those
  have to be reproduced by hand and silently drift when the module is updated.

The `ExecStartPre` form avoids all of this: it is bounded, it fails loudly, it leaves `ExecStart` intact, and the
resolution happens once rather than being re-derived on every restart.

## Tradeoffs

- **Pros**: Dynamic, so node IP changes need no configuration edits. Fails fast and visibly when the mesh is down.
  Keeps the upstream unit definition.
- **Cons**: The address is resolved at start time, so a node whose Tailscale IP changes while the service is running
  needs a restart to pick it up. The application must support environment variable expansion in its config.
