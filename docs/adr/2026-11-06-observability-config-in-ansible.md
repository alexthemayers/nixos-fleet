---
status: accepted
date: 2026-11-06
---

# Observability config lives in fleet.debian_guest files

## Context and Problem Statement

The Debian observability guest still evaluated a render-only
`nixosConfigurations.proxmox-observability` at apply time to build
Prometheus, Alertmanager, Graphite, and alert rules. The other Debian
guests already ran from Ansible alone. How should observability config
be owned so the flake no longer ships a phantom host?

## Decision Drivers

* The four Proxmox guests are already live on Debian
* Caddy on `xcloud-caddy` still needs `fleet/apps` for edge vhosts
* Apply-time `nix eval` couples Ansible to a host that is not deployed

## Considered Options

* Keep the phantom NixOS configuration as a render source
* Commit the rendered YAML into `fleet.debian_guest` and delete the
  phantom host
* Move scrape and alert config into a new non-Nix generator

## Decision Outcome

Chosen option: "Commit the rendered YAML into `fleet.debian_guest` and
delete the phantom host", because the guest already converges from
Ansible and the render step was the last Nix dependency for those four
VMs.

Prometheus scrapes, Alertmanager routes, the Graphite mapping, and the
live alert rules are files under
`collections/ansible_collections/fleet/debian_guest/roles/observability/files/`.
`fleet/apps` stays the Caddy edge registry with `module = null` for
Debian apps. Grafana dashboards, the ntfy webhook, and Jellyfin managed
XML live in the collection. `make check-mimir-rules` validates the
committed `rules.yaml`.

### Consequences

* Good, because Ansible alone converges the Debian guests
* Bad, because a new public app needs both a `fleet/apps` entry and a
  Prometheus scrape or probe edit
* Bad, because alert hygiene is no longer a Nix eval assertion; it is a
  Python check plus promtool
* Bad, because scrape-target and host-relabel guards left
  `fleet-inventory.nix` when `scrapeConfigs` went empty; they now live in
  `scripts/check-prometheus-scrapes.py` (wired from `scripts/lint.sh`)

## Validation

`nixosConfigurations` has no `proxmox-observability`.
`make debian-observability-check` installs the committed files with no
`nix eval`. `scripts/check-alert-rules.py` accepts `rules.yaml`.
`scripts/check-prometheus-scrapes.py` accepts the committed
`prometheus.yml` against `fleet.inventory.hosts`.

## More Information

[proxmox-observability-debian.md](../services/proxmox-observability-debian.md),
[2026-11-04-debian-observability-guest.md](2026-11-04-debian-observability-guest.md),
[2026-11-04-local-metrics-and-logs.md](2026-11-04-local-metrics-and-logs.md).
