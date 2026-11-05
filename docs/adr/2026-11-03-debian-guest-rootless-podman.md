---
status: accepted
date: 2026-11-03
---

# Application workloads on the Debian guest run as rootless Podman units

## Context and Problem Statement

VM 109 (`proxmox-applications-debian`) ran fifteen application workloads
as native packages, hand-built trees, and ad-hoc units. How should those
workloads be packaged so digests are pinned, NFS uids stay correct, and
`systemd_unit_state` / Vector still see real system units?

## Decision Drivers

* User quadlets are invisible to `systemd_unit_state` and need linger.
* NFS datasets are owned by pinned uids (immich 3000, arr stack, …).
* MagicDNS names (`xcloud-postgres`) and `127.0.0.1` peers must resolve
  inside the process network namespace.
* The guest root disk is 35 GiB; multi-GB official images do not fit
  next to each other.

## Considered Options

* Keep native packages and hand builds
* User-level Podman quadlets
* System units with `User=<app>` that call `podman run` (registry_cache
  pattern)

## Decision Outcome

Chosen option: "System units with `User=<app>` that call `podman run`",
because that is already how `registry_cache` runs and it stays visible
to systemd exporters and Vector. One `container.service.j2` plus
`debian_guest_podman_apps` drives every cut-over. Images are
digest-pinned. Containers that need NFS use `--userns=keep-id` and
`keep-groups`. Host networking is used where MagicDNS or localhost
peers require it; published ports otherwise use slirp4netns (pasta
fails under this guest's RuntimeDirectory). GitLab Omnibus and the
registry caches stay native.

### Consequences

* Good, because every app is a digests-and-env-file unit the playbook
  can rebuild.
* Bad, because keep-id ID-maps large layers onto the root disk; Immich
  and Jellyfin needed image parking/pruning, and Keycloak skips
  keep-id (no NFS volumes).
* Neutral, because soak cleanup (`roles/apps/tasks/cleanup.yml`) removes
  the native packages and trees; Paperless keeps `/opt/paperless` as the
  thin-image bind mount.

## Validation

Each unit is `active` with its smoke URL (Immich
`/api/server/ping`, Jellyfin `/health`, Keycloak `/health/ready`, …).
`MemoryHigh` / `MemoryMax` are set on the Podman units and listed in
[memory.md](../memory.md).

## More Information

Service docs under `docs/services/`. Collection role:
`roles/apps`.
