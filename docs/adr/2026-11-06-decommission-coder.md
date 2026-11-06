---
status: accepted
date: 2026-11-06
---

# Decommission Coder

## Context and Problem Statement

Coder is not running. The builder is Debian `proxmox-dev` and does not
start it. Postgres still had a `coder` role/database/pool until this
change. The old stub said not to recreate without an ADR.

## Decision Drivers

* Drop unused DB slots on the 1 GiB `xcloud-postgres` hub
* Clear the "do not recreate" stub with an explicit decision

## Considered Options

* Keep the Postgres role for a possible return
* Remove Nix management and operator-DROP the database/role
* Recreate Coder on the Debian builder

## Decision Outcome

Chosen option: "Remove Nix management and operator-DROP the
database/role", because nothing consumes it.

1. Nix no longer declares the `coder` database, role, pgbouncer pool, or
   `postgres/coder_password` sops secret.
2. Operator on `xcloud-postgres` (after a final dump if wanted):

```sql
DROP DATABASE IF EXISTS coder;
DROP ROLE IF EXISTS coder;
```

3. Remove leftover `coder` ciphertext. Nothing reads these keys
   (grepped; not decrypted), and the agent cannot edit sops YAML without
   the age key. Run `make edit-secrets HOST=<host>` for each:

   | Host file | Keys to delete |
   |-----------|----------------|
   | `secrets/proxmox-dev/secrets.yaml` | `coder/client_secret`, `postgres/coder_password` |
   | `secrets/xcloud-postgres/secrets.yaml` | `postgres/coder_password` |

   Then `make check-secrets`.
4. Do not recreate Coder without a new ADR.

### Consequences

* Good, because the hub no longer reserves pool slots for a dead app
* Bad, because bringing Coder back needs a new design and ADR

## Validation

`rg coder services/postgres.nix` is empty after merge. Operator confirms
`\du` / `\l` lack `coder`.

## More Information

[postgres.md](../services/postgres.md),
[2026-11-04-debian-dev-guest.md](2026-11-04-debian-dev-guest.md).
