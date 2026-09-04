# ADR: Agent instruction lives in Cursor rules

**Status:** accepted (2026-09-04)

## Context

`AGENTS.md` had become the agent runbook: deploy location, landmines, CI vs
local, and the script index. That duplicated [deployments.md](../deployments.md)
and the ADRs, and it was a second essay for every Cursor session. Cursor
project rules (`.cursor/rules/*.mdc`) are the mechanism for agent behaviour.

## Decision

- Agent do/don't lives in `.cursor/rules/`. One concern per file.
  `alwaysApply` for constraints that apply every turn; `globs` for
  path-specific craft.
- Operational facts (tables, procedures, mechanisms) live in `docs/` and
  ADRs. A rule states a constraint in one or two sentences and links the doc.
- `AGENTS.md` is a pointer and a rule index, not a second copy. Do not grow it
  with new landmines or make-target lists.
- Dedup: change a fact in the doc; change a rule only when the agent
  constraint changed. Do not paste the same table into both.

## Consequences

Cursor loads rules via frontmatter. Tools that only read `AGENTS.md` follow
the pointer. New agent guidance is a `.mdc` (and an ADR if it is a freeze).
See [`.cursor/rules/agent-source-of-truth.mdc`](../../.cursor/rules/agent-source-of-truth.mdc).
