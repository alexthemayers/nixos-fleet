# How-To: Dynamic Tailscale IP Injection

Clustered applications (e.g., Loki, Mimir, Keycloak) require nodes to peer with each other over the network. In
`nixos-fleet`, all node-to-node communication occurs over the encrypted Tailscale mesh (`tailscale0`).

However, Tailscale IPs are dynamically allocated. Hardcoding IPs in your Nix OS configuration modules breaks if a node's
IP changes or if you deploy a new node.

To solve this, we use **Dynamic IP Injection** at service startup.

## Implementation Concept

We override the systemd `ExecStart` of a service. We write a small wrapper script that queries the `tailscale0` IP
address using the `ip` command, exports it as an environment variable, and then launches the actual daemon.

### Example (Loki / Mimir Gossip)

1. **Define the IP retrieval logic** in a script using `writeShellScript`:
   ```nix
   let
     startupScript = pkgs.writeShellScript "loki-startup" ''
       # Wait for the tailscale0 interface to appear
       while ! ${pkgs.iproute2}/bin/ip -4 addr show dev tailscale0 >/dev/null 2>&1; do
         sleep 1
       done

       # Extract the IP address
       TAILSCALE_IP=$(${pkgs.iproute2}/bin/ip -4 addr show dev tailscale0 | ${pkgs.gawk}/bin/awk '/inet / {print $2}' | ${pkgs.coreutils}/bin/cut -d/ -f1)
       
       echo "Discovered Tailscale IP: $TAILSCALE_IP"
       export TAILSCALE_IP
       
       # Exec into the actual binary
       exec ${config.services.loki.package}/bin/loki -config.file=${config.services.loki.configFile} -config.expand-env=true
     '';
   in
   ```

2. **Override the `ExecStart`** in the systemd service to use your wrapper:
   ```nix
   systemd.services.loki = {
     serviceConfig = {
       ExecStart = [
         "" # Clear the original ExecStart provided by the NixOS module
         "${startupScript}"
       ];
     };
   };
   ```

3. **Configure the application** to read the environment variable:
   ```yaml
   # In your loki.yml config
   memberlist:
     bind_addr: ''${TAILSCALE_IP}
   ```

## Tradeoffs

- **Pros**: Completely dynamic. No need to update Nix configurations when node IPs change. Highly resilient in
  multi-node clusters.
- **Cons**: Overriding `ExecStart` bypasses some of the safety checks or default arguments provided by the upstream
  NixOS module. You must ensure your wrapper script passes all necessary arguments to the binary. It also requires the
  application to support expanding environment variables in its configuration file (e.g., Loki's
  `-config.expand-env=true`).
