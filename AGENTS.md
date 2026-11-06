# Agent notes for nixos-fleet

Agent do/don't lives in [`.cursor/rules/`](.cursor/rules/), not in this file.
Do not grow this file. Dedup and layering:
[`.cursor/rules/agent-source-of-truth.mdc`](.cursor/rules/agent-source-of-truth.mdc).

| Rule | When |
|------|------|
| [agent-source-of-truth.mdc](.cursor/rules/agent-source-of-truth.mdc) | always — where instruction lives |
| [git-commits.mdc](.cursor/rules/git-commits.mdc) | always — operator commits |
| [git-branch-from-main.mdc](.cursor/rules/git-branch-from-main.mdc) | always — pull main, branch before work |
| [zero-debt.mdc](.cursor/rules/zero-debt.mdc) | always — no known leftover; no CI gap |
| [fmt-lint.mdc](.cursor/rules/fmt-lint.mdc) | always — done bar |
| [docs-adrs.mdc](.cursor/rules/docs-adrs.mdc) | always — docs are part of the change |
| [docs-formatting.mdc](.cursor/rules/docs-formatting.mdc) | `docs/**`, README |
| [code-practices.mdc](.cursor/rules/code-practices.mdc) | always — secrets, waitForHost, Attic |
| [code-nix.mdc](.cursor/rules/code-nix.mdc) | `**/*.nix` |
| [code-scripts.mdc](.cursor/rules/code-scripts.mdc) | `scripts/**`, Makefile |
| [deploy.mdc](.cursor/rules/deploy.mdc) | always — where to build and switch |
| [infrastructure.mdc](.cursor/rules/infrastructure.mdc) | always — landmines and freezes |
| [inventory-secrets.mdc](.cursor/rules/inventory-secrets.mdc) | always — adding a host, per-host sops |
| [alerts-on-fix.mdc](.cursor/rules/alerts-on-fix.mdc) | always — alert after a fix |
| [alert-timeseries.mdc](.cursor/rules/alert-timeseries.mdc) | always — vet PromQL against Mimir |
| [prometheus-scrape.mdc](.cursor/rules/prometheus-scrape.mdc) | always — scrape new services |
| [alert-fidelity.mdc](.cursor/rules/alert-fidelity.mdc) | always — quiet, accurate alerts |
| [memory-limits.mdc](.cursor/rules/memory-limits.mdc) | always — document MemoryMax |
| [grafana-dashboards.mdc](.cursor/rules/grafana-dashboards.mdc) | always — dashboard with each alert |
| [router-reboot.mdc](.cursor/rules/router-reboot.mdc) | always — router reboot on request only |
| [distill.mdc](.cursor/rules/distill.mdc) | always — distill preferences into rules, skills, ledger |

Operational facts (make targets, CI vs local, script index, operator rsync):
[docs/deployments.md](docs/deployments.md). Decisions:
[docs/adr/README.md](docs/adr/README.md). Service docs: [docs/](docs/).
Custom options: [docs/custom-options.md](docs/custom-options.md).
How to tag claims: [docs/how-to-audit.md](docs/how-to-audit.md).

Read order when touching a service: `.cursor/rules/` →
[docs/adr/README.md](docs/adr/README.md) →
[docs/deployments.md](docs/deployments.md) → the service or host doc.
