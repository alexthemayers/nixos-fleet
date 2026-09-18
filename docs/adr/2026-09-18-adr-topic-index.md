---
status: accepted
date: 2026-09-18
---

# Current decisions are the topic index, not the date-sorted pile

## Context and Problem Statement

This tree has dozens of one-decision ADRs under `docs/adr/`. Operators and
agents opened the chronological [README.md](README.md) to learn what is
true today, then hit superseded records (`proxmox-lb`, four hubs, Alloy
caps) next to the freeze that replaced them. Live service docs still
linked those superseded files. How should current topology and product
freezes be found without merging or deleting the records?

## Decision Drivers

* One decision per file stays ([use MADR](2026-09-06-use-madr.md))
* Existing `docs/adr/YYYY-MM-DD-slug.md` links must keep working
* Current truth already lives in service docs; ADRs are why, not how
* Superseded records are history, not the live citation

## Considered Options

* Delete superseded ADRs and merge related accepted files into one
  ADR per topic
* Keep the date-sorted table; ask readers to skip `superseded` rows
* Keep one-decision files in place; make [README.md](README.md) a
  topic index; live docs cite only the governing accepted ADR

## Decision Outcome

Chosen option: "Keep one-decision files in place; make README.md a
topic index; live docs cite only the governing accepted ADR", because
MADR already forbids merging files and the date-sorted table hid which
record still applies.

Do not delete, rename, or move ADR files. Do not copy Decision Outcome
prose into a second essay. The topic index is one sentence plus links
to the governing ADR and the service or runbook that operates it.
Superseded records stay in a History table on that index and in
cross-links from the ADR that replaced them.

### Consequences

* Good, because "three hubs, no internal LB" is one row, not four
  chronological files
* Good, because git history and inbound links stay valid
* Bad, because a new freeze needs both an ADR file and a README row
* Bad, because superseded files remain in the directory and will show
  up in search

## Validation

[README.md](README.md) is grouped by topic. Grep of `docs/services/`,
`docs/runbooks/`, `docs/standards.md`, and `README.md` does not cite a
superseded ADR as current. Agent rule:
[`.cursor/rules/docs-adrs.mdc`](../../.cursor/rules/docs-adrs.mdc).

## More Information

Template: [adr-template.md](adr-template.md). Layout:
[2026-09-06-use-madr.md](2026-09-06-use-madr.md).
