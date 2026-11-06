---
status: accepted
date: 2026-11-06
---

# One Vector pipeline in `config/vector/`, rendered by every consumer

## Context and Problem Statement

Vector ships the journal to Loki from three consumers: NixOS hosts
(`config/observability.nix`), the Debian guests (`fleet.debian_guest`
`monitoring` role), and the Proxmox host (`ansible/roles/vector`). The
remap and the Loki sink were written out three times. NixOS and the
Proxmox host carried the same ~110 line VRL by copy. The guests carried a
cut-down variant that dropped `level`, `syslog`, `process`, the kernel
`job`, the first-start age filter, and the Loki `out_of_order_action`.
Nothing failed when they drifted.

## Decision Drivers

* A label or buffer change must land on every host or none
* Guests should log in the same shape as NixOS hosts and the hypervisor
* CI has to fail when a consumer drifts ([zero-debt](../../.cursor/rules/zero-debt.mdc))

## Considered Options

* Keep three copies and add a drift check only
* Share the VRL and the Loki sink in `config/vector/`, render them in
  each consumer, and check the renders in CI
* Run one Vector config from a package or container

## Decision Outcome

Chosen option: "Share the VRL and the Loki sink in `config/vector/`,
render them in each consumer, and check the renders in CI".

1. `config/vector/journal-remap.vrl` holds the journal remap. `@host@` is
   the only substitution.
2. `config/vector/loki-sink.json` holds the static Loki sink fields:
   labels, disk buffer, encoding, ordering, healthcheck.
3. NixOS reads both with `builtins.readFile` / `builtins.fromJSON`. The
   Ansible roles read them with `lookup('file', ...)`.
4. `scripts/check-vector-config.py` (`make check-vector-config`, in
   `make ci`) renders every consumer, fails on drift from the shared files,
   and runs `vector validate` from `.#ci-tools`.

### Consequences

* Good, because one edit changes every host and CI fails when a consumer
  re-inlines or diverges
* Good, because the NixOS render is byte-identical to before (checked by
  `nix eval` of `services.vector.settings` on all three hosts)
* Bad, because the Debian guests change shape on the next deploy: Loki
  lines now carry `level`, `syslog`, `process`, and `timestamp`, the
  `job`/`host`/`service`/`syslog_id`/`syslog_facility` fields leave the
  JSON body (they stay labels), and journal entries older than one hour
  are dropped on first start. Label queries are unchanged. Queries that
  parsed those fields out of the line body need `level` or the labels
  instead.
* Bad, because the collection now reads `config/vector/` from the repo
  checkout (`playbook_dir` relative), so the roles run only from this tree.
  The check resolves each role's real default against its playbook
  directory, so a wrong relative path fails CI instead of the deploy.
* Bad, because guests and the hypervisor install Vector from the unpinned
  `apt.vector.dev` repo while CI validates against the `.#ci-tools`
  (nixpkgs) build. A newer apt release that rejects a shared option fails
  at the host's `vector validate` before restart, not in CI. The
  `current_boot_only` split above is the known case.

## Validation

`make check-vector-config` passes. After `make deploy-debian-*` and
`make deploy-proxmox-host`, `systemctl is-active vector` is `active` and
the journal shows no `vector validate` error, `VectorTargetDown` and
`LokiClientDrops` stay quiet, and a LogQL query for
`{host="<guest>"}` returns lines with a `level` field.
