# GitLab API notes for nixos-fleet

## Auth

```bash
pass=$(printf 'protocol=https\nhost=gitlab.alexmayers.co.za\n\n' \
  | git credential fill | awk '/^password=/{sub(/^password=/, ""); print}')
```

Use header `PRIVATE-TOKEN: $pass`. Do not print the token.

## Project path

URL-encode the path: `nix%2Fnixos-fleet`. Numeric project id may 404 via
some MCP helpers; the encoded path works with REST.

## Endpoints used by the skill

| Need | Method | Path |
|------|--------|------|
| Open MR | POST | `/api/v4/projects/nix%2Fnixos-fleet/merge_requests` |
| MR state | GET | `/api/v4/projects/nix%2Fnixos-fleet/merge_requests/:iid` |
| Pipelines | GET | `.../merge_requests/:iid/pipelines` |
| Notes | GET/POST | `.../merge_requests/:iid/notes` |

## Work item MCP pitfall

`create_workitem_note` with `work_item_iid` equal to the MR iid can land on
the wrong work item. Prefer REST `.../merge_requests/:iid/notes` for MR
discussion.

## MCP

Repo [`.cursor/mcp.json`](../../mcp.json) points at the GitLab MCP HTTP
endpoint. Prefer REST with git credentials when MCP project lookup 404s.
