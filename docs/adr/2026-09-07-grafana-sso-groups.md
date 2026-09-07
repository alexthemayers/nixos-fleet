---
status: accepted
date: 2026-09-07
---

# Grafana access is Keycloak group membership

## Context and Problem Statement

Grafana generic OAuth mapped `GrafanaAdmin` to a hardcoded email
(`a.mayers102@gmail.com`) and gave every other authenticated user
`Viewer`. That does not match the Keycloak group pattern already used
for Jellyfin (`jellyfin:read` / `jellyfin:admin`). Adding or removing
Grafana admins meant editing Nix, not group membership.

## Considered Options

* Keep the email equality in `role_attribute_path`
* Map Grafana org roles from Keycloak client roles on the `roles` claim,
  the same way Jellyfin SSO-Auth does
* Use realm role `admin` or the Grafana email allow-list

## Decision Outcome

Chosen option: "Map Grafana org roles from Keycloak client roles on the
`roles` claim", because it matches
[jellyfin-sso-groups](2026-09-04-jellyfin-sso-groups.md) and keeps
membership in Keycloak.

Grafana Viewer is the Keycloak client role `grafana:read`. That role is
a child of `default-roles-master`, so every realm user (including new
ones) has it. Grafana server admin is opt-in: put the user in group
`grafana admin` (mapped to `grafana:admin`). Do not use realm role
`admin`.

The grafana client puts this client's roles on a multivalued `roles`
claim (ID token, access token, userinfo). Grafana
`role_attribute_path` maps `grafana:admin` to `GrafanaAdmin` and
`grafana:read` to `Viewer`. `role_attribute_strict` is on, so a token
without either role is denied. `grafana:admin` is a composite of
`grafana:read`.

### Consequences

Any Keycloak user who SSO-logs into Grafana gets `Viewer`. Server admin
requires the `grafana admin` group. The `grafana reader` group still
maps to `grafana:read` but is not required for login. Replacing the
email check means existing Grafana org roles refresh on the next OIDC
login.

See [grafana.md](../services/grafana.md) and
[keycloak.md](../services/keycloak.md).
