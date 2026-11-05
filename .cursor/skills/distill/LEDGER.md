# Ledger entry shape

Read when writing or bumping a row in
[`.cursor/preferences/ledger.md`](../../preferences/ledger.md).

Each entry:

```markdown
### <id-slug>

- **status:** `candidate` | `declined` | `blocked`
- **proposed home:** `<path>` | `undecided`
- **statement:** one sentence an agent can follow
- **evidence:**
  - YYYY-MM-DD — gist of what Alex said, or the concrete repeat (no transcript dump)
```

Rules:

- The first evidence entry creates the row. Mention it in one sentence; do not
  ask.
- A later match of `candidate` asks (destination, one sentence, context cost)
  and does not write until Alex says yes.
- A match of `declined` or `blocked` does not ask and does not follow.
- `blocked` includes a link to the freeze or accepted ADR.
- Delete the entry once its home contains the statement.
- Leave `declined` and `blocked`. Merge duplicates. Do not drop for age.
- No secrets in any field.
