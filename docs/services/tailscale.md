# Tailscale Network Service Configuration

This document describes the deployment and configuration details of the **Tailscale Network** daemon in the `nixos-fleet` infrastructure.

## Overview
Tailscale is the mesh virtual private network (VPN) overlay that interconnects all nodes and services in the fleet. It is deployed as a core module across **all target hosts** in the fleet.

## Networking and Routing
- **Overlay Interface**: Exposes the `tailscale0` interface (assigned to subnet `100.64.0.0/10` and IPv6 `fd7a:115c:a1e0::/48`).
- **Firewall Trust**: The local firewall is configured to trust the `tailscale0` interface (`trustedInterfaces = [ "tailscale0" ]`). Standard ports are allowed through this subnet, keeping public exposure minimal.
- **Reverse Path Filtering**: Configured with `checkReversePath = "loose"` to allow proper routing of encapsulated virtual packets.
- **Metrics/Web UI Port**: Exposes a read-only local status page on `0.0.0.0:9251` (`tailscale web --readonly`).

## Secrets Management
- **`tailscale/auth_key`**: Decrypted by SOPS. This is an ephemeral or reusable authentication key used to auto-register newly provisioned nodes into the Tailscale network at boot time:
  ```nix
  services.tailscale.authKeyFile = config.sops.secrets."tailscale/auth_key".path;
  ```

## Key Configurations and Network Optimizations

To handle high-throughput inter-service operations (such as databases and backups) over virtual VPN links, the following optimizations are applied:

1. **TCP MSS Clamping (MTU Resolution)**:
   - VPN encapsulation introduces overhead, reducing the maximum transmission unit (MTU). This can lead to silent packet drops and connection hangs (MTU black holes).
   - To prevent this, the network configures **TCP MSS Clamping** using `nftables`. This intercepts outgoing TCP SYN packets traversing `tailscale0` and limits their maximum segment size (MSS) to `1232` bytes:
     ```nix
     networking.nftables.tables.mangle = {
       family = "inet";
       content = ''
         chain output {
           type filter hook output priority mangle; policy accept;
           oifname "tailscale0" tcp flags syn tcp option maxseg size set 1232
         }
       '';
     };
     ```

2. **UDP GRO Offloading (`tailscale-udp-optimize`)**:
   - Because virtual overlay networks encapsulate all packets into UDP, high throughput creates significant CPU processing overhead.
   - The fleet runs a oneshot startup optimization service (`tailscale-udp-optimize`):
     - It automatically detects the host's physical network adapter interface handling the default gateway.
     - Uses `ethtool` to enable UDP **Generic Receive Offload (GRO)** forwarding (`rx-udp-gro-forwarding on rx-gro-list on`). This groups incoming packets before routing, saving CPU cycles.
     - Increases network adapter ring buffers (`rx 1024 tx 1024`) to prevent packet drops caused by virtual buffer overflows (common under QEMU VirtIO drivers).

3. **Systemd Resolved DNS Integration**:
   - Forces resolved interface configuration (`services.resolved.enable = true`) and overrides network-manager settings (`networking.networkmanager.dns = "systemd-resolved"`) to ensure hostnames resolve via MagicDNS.
