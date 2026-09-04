# Agent notes for nixos-fleet

Agent do/don't lives in [`.cursor/rules/`](.cursor/rules/), not in this file.
Do not grow this file. Dedup and layering:
[`.cursor/rules/agent-source-of-truth.mdc`](.cursor/rules/agent-source-of-truth.mdc).

| Rule | When |
|------|------|
| [agent-source-of-truth.mdc](.cursor/rules/agent-source-of-truth.mdc) | always — where instruction lives |
| [git-commits.mdc](.cursor/rules/git-commits.mdc) | always — operator commits |
| [fmt-lint.mdc](.cursor/rules/fmt-lint.mdc) | always — done bar |
| [docs-adrs.mdc](.cursor/rules/docs-adrs.mdc) | always — docs are part of the change |
| [docs-formatting.mdc](.cursor/rules/docs-formatting.mdc) | `docs/**`, README |
| [code-practices.mdc](.cursor/rules/code-practices.mdc) | always — secrets, waitForHost, Attic |
| [code-nix.mdc](.cursor/rules/code-nix.mdc) | `**/*.nix` |
| [code-scripts.mdc](.cursor/rules/code-scripts.mdc) | `scripts/**`, Makefile |
| [deploy.mdc](.cursor/rules/deploy.mdc) | always — where to build and switch |
| [infrastructure.mdc](.cursor/rules/infrastructure.mdc) | always — landmines and freezes |
| [inventory-secrets.mdc](.cursor/rules/inventory-secrets.mdc) | always — adding a host, per-host sops |

Operational facts (make targets, CI vs local, script index, operator rsync):
[docs/deployments.md](docs/deployments.md). Decisions:
[docs/adr/README.md](docs/adr/README.md). Service docs: [docs/](docs/).
Custom options: [docs/custom-options.md](docs/custom-options.md).
[docs/fleet-audit.md](docs/fleet-audit.md) is an investigation log, not the spec.

Read order when touching a service: `.cursor/rules/` →
[docs/adr/README.md](docs/adr/README.md) →
[docs/deployments.md](docs/deployments.md) → the service or host doc.
