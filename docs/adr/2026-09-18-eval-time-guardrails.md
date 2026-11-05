---
status: accepted
date: 2026-09-18
---

# Eval fails closed on registry, substituter, WAF, and scrape freezes

## Context and Problem Statement

Phases 1–5 moved app enablement into `fleet.apps`, documented current
topology, and stopped live docs from citing superseded ADRs. Those
invariants still lived in Cursor rules. `make lint` is `nix flake check
--all-systems --no-build`, so a derivation in `checks.` is evaluated and
never run. How should a drive-by that puts Attic back on a host, blocking WAF, or a
scrape job without `host` fail?

## Decision Drivers

* Lint already evaluates every `nixosConfigurations`
* Agent rules are not a merge gate
* `checks.` runCommand greps do not execute under `--no-build`

## Considered Options

* Keep the freezes in Cursor rules only
* Add `checks.` derivations that grep the tree
* NixOS `assertions` (and `throw` in generated files) so eval fails

## Decision Outcome

Chosen option: "NixOS `assertions` so eval fails", because `make lint`
already evaluates every host and does not build `checks.`.

Assertions cover:

* `fleet.apps` docs, module, and dashboard paths exist
* Edge `listenerHost` is `xcloud-caddy`; Keycloak `edge.auth` is null
* `hosts/**/*.nix` do not mention `fleet.apps`, `fleet.services`, or
  `virtualHosts`
* Deployed `nix.settings` substituters do not name Attic
  ([2026-11-03-decommission-attic.md](2026-11-03-decommission-attic.md))
* Caddy Coraza stays `SecRuleEngine DetectionOnly`
* Hostname:port Prometheus jobs set a `host` relabel (URL probes exempt)

Do not move these into `checks.` while lint is `--no-build`.

### Consequences

* Good, because a flipped freeze fails on the laptop and in GitLab `test`
* Good, because the same eval already loads `mimir-rules.nix` throws
* Bad, because a new freeze needs an assertion, not only an ADR row
* Bad, because `pathExists` in a git flake only sees tracked files

## Validation

`make lint`. Break a path or add an Attic URL to `config/system.nix` and
confirm eval throws.

## More Information

[custom-options.md](../custom-options.md#app-registry-fleetapps),
[config/eval-guards.nix](../../config/eval-guards.nix),
[config/fleet-apps.nix](../../config/fleet-apps.nix).
