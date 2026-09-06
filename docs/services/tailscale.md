# Tailscale Network Service Configuration

This document describes the deployment and configuration details of the **Tailscale Network** daemon in the
`nixos-fleet` infrastructure.

## Overview

Tailscale is the mesh virtual private network (VPN) overlay that interconnects all nodes and services in the fleet. It
is deployed as a core module across **all target hosts** in the fleet.

## Networking and Routing

- **Overlay Interface**: Exposes the `tailscale0` interface (assigned to subnet `100.64.0.0/10` and IPv6
  `fd7a:115c:a1e0::/48`).
- **Firewall**: `tailscale0` is **not** a trusted interface. Ingress on the tailnet is limited to the ports each
  service declares under `networking.firewall.interfaces."tailscale0"`. UDP `41642` (the Tailscale wire protocol,
  host-specific in practice) is allowed globally so nodes can form the mesh. `checkReversePath = "loose"` so
  encapsulated packets are not dropped as spoofed.
- **Reverse Path Filtering**: Configured with `checkReversePath = "loose"` to allow proper routing of encapsulated
  virtual packets.
- **Metrics/Web UI Port**: Exposes a read-only local status page on `0.0.0.0:9251` (`tailscale web --readonly`).

## Secrets Management

- **`tailscale/auth_key`**: Decrypted by SOPS. This is an ephemeral or reusable authentication key used to auto-register
  newly provisioned nodes into the Tailscale network at boot time:
  ```nix
  services.tailscale.authKeyFile = config.sops.secrets."tailscale/auth_key".path;
  ```

## Key Configurations and Network Optimizations

To handle high-throughput inter-service operations (such as databases and backups) over virtual VPN links, the following
optimizations are applied:

1. **TCP MSS Clamping (MTU Resolution)**:
    - VPN encapsulation introduces overhead, reducing the maximum transmission unit (MTU). This can lead to silent
      packet drops and connection hangs (MTU black holes).
    - To prevent this, the network configures **TCP MSS Clamping** using `nftables`. This intercepts TCP SYN packets
      traversing `tailscale0` and clamps their maximum segment size to `rt mtu` — the MSS derived from the route's own
      MTU — rather than a hardcoded constant, so it stays correct if the tunnel MTU changes. Both the `forward` and
      `output` hooks are covered:
      ```nix
      networking.nftables.tables.mangle = {
        family = "inet";
        content = ''
          chain forward {
            type filter hook forward priority mangle; policy accept;
            iifname "tailscale0" tcp flags syn tcp option maxseg size set rt mtu
            oifname "tailscale0" tcp flags syn tcp option maxseg size set rt mtu
          }
          chain output {
            type filter hook output priority mangle; policy accept;
            oifname "tailscale0" tcp flags syn tcp option maxseg size set rt mtu
          }
        '';
      };
      ```

2. **UDP GRO Offloading (`tailscale-udp-optimize`)**:
    - Because virtual overlay networks encapsulate all packets into UDP, high throughput creates significant CPU
      processing overhead.
    - The fleet runs a oneshot startup optimization service (`tailscale-udp-optimize`):
        - It automatically detects the host's physical network adapter interface handling the default gateway.
        - Uses `ethtool` to enable UDP **Generic Receive Offload (GRO)** forwarding (
          `rx-udp-gro-forwarding on rx-gro-list on`). This groups incoming packets before routing, saving CPU cycles.
        - Increases network adapter ring buffers (`rx 1024 tx 1024`) to prevent packet drops caused by virtual buffer
          overflows (common under QEMU VirtIO drivers).

3. **Systemd Resolved DNS Integration**:
    - Forces resolved interface configuration (`services.resolved.enable = true`) and overrides network-manager
      settings (`networking.networkmanager.dns = "systemd-resolved"`) to ensure hostnames resolve via MagicDNS.

## Alerting (DERP vs direct)

`tailscale web --readonly` on `:9251` exports `tailscaled_outbound_bytes_total`
with `path` labels `derp`, `direct_ipv4`, `direct_ipv6`, `peer_relay_ipv4`,
and `peer_relay_ipv6`. There is no `path="direct"` and no
`tailscale_derp_io_bytes_total`. Every node keeps ~25 B/s of DERP keepalive,
so alerts require real volume.

| Alert | Catches |
|---|---|
| `TailscaleConnectionRelayed` | outbound >1 KiB/s on `derp` and none on `direct_*` |
| `TailscaleDERPInsteadOfDirect` | more than half of outbound bytes on `derp`, and >10 KiB/s |
| `TailscaleDERPRelaySpike` | `derp` above 50 KiB/s even if some direct remains |

Rules are in the `tailscale-mesh` group in
[`services/mimir-rules.nix`](../../services/mimir-rules.nix).
Dashboards: Tailscale API, Tailscale machine.
