---
name: distill
description: Distill Alex's preferences and repeated legwork into rules, skills, docs, or the ledger.
disable-model-invocation: true
---

# Distill

Tail step after the asked task. Classify every **signal** from this turn.
Completion: every signal is filed (home edited, ledger row written or bumped,
ask issued, or blocked), or the reply carries a filing note when this turn
cannot edit files. A signal left only in chat is unfinished.

## Signals

Two sources:

1. **Alex's words** — a correction, an always / never / remember, praise or
   rejection of a way of working.
2. **Repeated legwork** — the same concrete action (same files, command
   sequence, or fact) in a later task or later session. Retries while the
   same task is still in progress are one attempt. A similar vibe does not
   count. Vague rows are not written.

## Steps

1. **Decide whether this turn needs distill.**
   - One-line edit or pure question, and no signal → stop.
   - Procedure, no signal → read [`.cursor/preferences/ledger.md`](../../preferences/ledger.md)
     only to merge or bump a matching row. Do not follow candidate text.
     Then stop unless a match needs a mention or an ask.
   - Signal present → continue.
   Completion: branch chosen.

2. **Check whether the preference is already written.**
   - Clear wording exists and was followed → no write.
   - Wording exists and was missed → sharpen that sentence (leading word,
     positive target). A miss is a pointer failure, not a second copy.
   - Absent → pick a home (step 3).
   Completion: already-encoded case handled, or home still needed.

3. **Pick the narrowest home** (see [Homes](#homes)).
   Completion: one destination named, or `undecided` for the ledger.

4. **Apply the evidence bar** (see [Evidence bar](#evidence-bar)).
   Completion: write, ask, ledger, or blocked chosen.

5. **Write, ask, or ledger.**
   - Write without asking when the bar and [Write policy](#write-policy) allow.
   - Ask first (name destination, one sentence, context cost) and do not write
     yet when the policy requires a yes.
   - Append or bump a ledger row when not yet law. Shape:
     [LEDGER.md](LEDGER.md). Mention a new row in one sentence; do not ask on
     create. On a later match of `candidate`, ask and wait. On `declined` or
     `blocked`, do not ask and do not follow.
   - If this turn cannot edit files, put the row in the reply in ledger shape.
     The next writable turn files it.
   Completion: files changed, ask outstanding, or filing note in the reply.

6. **Prune while the ledger is open.**
   Merge duplicates. Delete a row once its home contains the sentence. Leave
   `declined` and `blocked`. Do not drop a row for age. Do not mine old
   transcripts. Name distill paths in one sentence in the reply; the operator
   commits.
   Completion: ledger consistent with homes; reply names distill paths.

## Homes

Do not invent a fourth essay. Prefer an existing file.

| Kind | Home |
|------|------|
| Always / never for the agent | Existing [`.cursor/rules/`](../../rules/) file, or a new one after a yes. `alwaysApply: true` only when every turn needs it; otherwise `globs`. One concern, under 50 lines, link the doc instead of copying it. |
| Procedure to run again | Skill under [`.cursor/skills/`](../../skills/). Default user-invoked. Model-invoke only when Alex accepts an ask that says the description loads every turn. Follow `writing-for-agents`. |
| How the fleet works, or a real decision | [`docs/`](../../../docs/) or a MADR under [`docs/adr/`](../../../docs/adr/), plus the topic row. Point at [`docs-adrs.mdc`](../../rules/docs-adrs.mdc) and [`docs-formatting.mdc`](../../rules/docs-formatting.mdc); do not restate them. |
| Not yet law | One ledger candidate. |

Legwork may propose a skill, or one sentence in a file that already exists —
not a new always-on rule. Legwork only appends or bumps the ledger; it does
not edit a rule, skill, or doc.

In-repo only unless Alex says the preference is global. No soft always-on
taste file. No personal Cursor rules or agent stores by default.

## Evidence bar

- Alex says remember it, or states always / never → eligible this turn.
- The same preference shows up again (this chat, or an existing candidate) →
  eligible.
- One ambiguous thing Alex said → ledger only.
- Concrete later-task / later-session legwork repeat → ledger candidate.
  Mention on create. Ask on the next match. Never an unprompted skill or
  rule edit.
- Wording already exists and was followed → no write.
- Wording exists and was missed → sharpen that sentence.
- Preference contradicts a freeze or an accepted ADR → status `blocked`, with
  the link. Do not edit the decision
  ([infrastructure.mdc](../../rules/infrastructure.mdc)).

## Write policy

**Without asking:** ledger append or bump; sharpen a sentence Alex just
restated or contradicted; one new sentence in the rule, skill, or doc that
already owns the concern, when Alex just said it. Legwork cannot use the
sentence path.

**Ask first, do not write yet:** any new file (always-on rule, glob rule,
skill, ADR), or anything that would change a freeze. A no on promotion marks
the row `declined`. Do not ask again. Leave the row so a later agent does not
recreate it. Alex's later "remember this", or an explicit always / never,
reopens it.

**Secrets:** ledger rows hold no passwords, tokens, or vault material.

## Incentive

The win is the smallest durable edit. A new always-on file is a cost, because
every later turn pays it. Sharpening one existing sentence beats a new
artifact. No score. No required retro.
