---
name: gitlab-mr
description: >-
  Create a GitLab merge request, poll for SWE or human review, address
  review comments with follow-up commits, and loop until the MR is
  approved and merged. Use when opening an MR, checking review,
  addressing REQUEST CHANGES, or driving an MR to merge on
  gitlab.alexmayers.co.za.
---

# GitLab MR create → poll → address

Fleet GitLab: project `nix/nixos-fleet`, API host
`https://gitlab.alexmayers.co.za`. Auth: `git credential fill` for that
host (PRIVATE-TOKEN). API quirks: [REFERENCE.md](REFERENCE.md).

Obey [zero-debt.mdc](../../rules/zero-debt.mdc): in-scope review items
(including non-blocking nits) are fixed in the same MR. Polite
“follow-up OK” does not defer them unless Alex overrides that turn.
No CI validation for load-bearing code is debt — do not open an MR that
adds unguarded production paths.

## 1. Create

Completion: MR URL exists; head SHA matches the pushed branch; description has Summary + Test plan that only claims work that ran.

1. Confirm work is on a branch off current `main` ([git-branch-from-main.mdc](../../rules/git-branch-from-main.mdc)).
2. `make fmt` and `make lint` green. If the change touches observability YAML, CI will also run `make check-obs-config` — run it on proxmox-dev when practical before push.
3. Commit only when Alex asked (or this skill turn is explicitly to open/drive the MR). Push to `gitlab`.
4. Open the MR via API (`POST .../projects/nix%2Fnixos-fleet/merge_requests`) targeting `main`. Title and body honest.

## 2. Arm poll

Completion: a background loop is running; smoke-check the terminal file.

1. Start a local 3-minute loop (see Cursor `/loop` skill — monitored shell):

```bash
while true; do
  sleep 180
  echo 'AGENT_LOOP_TICK_mr {"prompt":"Check GitLab MR !<iid> for new review, pipeline, and merge state. Address in-scope feedback under zero-debt; stop the loop when merged or closed."}'
done
```

2. `notify_on_output` on `^AGENT_LOOP_TICK_mr`. Record the PID.
3. Do not double-arm if a loop for this iid already runs.

## 3. On tick

Completion: acted on new review or reported wait status.

1. Fetch MR state, pipelines, and notes (newest first) via API.
2. Ignore own reply noise and system “added N commits” unless needed for SHA.
3. If `state` is `merged` or `closed`: kill the loop PID; report merge SHA; stop.
4. If new **REQUEST CHANGES** or actionable nits on the current head: go to step 4.
5. If pipeline failed: fix, push, reply; keep looping.
6. Otherwise: one-line status (waiting on review / CI); keep looping.

## 4. Address

Completion: new head pushed; reply posted on the MR; loop still armed until merge.

1. Fix every in-scope item, or justify with evidence in the MR reply (zero-debt).
2. `make fmt` / `make lint` (and obs checks when relevant).
3. Commit, push, POST a note summarizing fixes and justifications.
4. Re-arm is automatic if the loop still runs; otherwise restart step 2.

## 5. Stop

Completion: loop dead; Alex has merge SHA and any remaining operator-only action named explicitly (never silent debt).

Applies that this change required are done in-session (agent) or listed as the next required action before calling the work done.
