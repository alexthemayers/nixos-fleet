# ADR: Jellyfin access is Keycloak group membership

**Status:** accepted (2026-09-04)

## Context

The Jellyfin SSO-Auth plugin posts to `/sso/OID/start/keycloak`. Keycloak
already had groups `jellyfin admin` and `jellyfin reader` mapped to client
roles `jellyfin:admin` and `jellyfin:read`, but the live plugin entry had
`EnableAuthorization` off and treated realm role `admin` as Jellyfin admin.
`alex.mayers` was a Keycloak realm-admin and not in `jellyfin admin`, so
SSO did not grant the Jellyfin dashboard. A second unused provider named
`Keycloak` listed the client roles against `realm_access.roles`, which
does not carry those client roles in the ID token.

## Decision

SSO library access is the Keycloak client role `jellyfin:read`. That role
is a child of `default-roles-master`, so every realm user (including new
ones) has it. The jellyfin client puts this client's roles on a
multivalued `roles` claim (ID token, access token, userinfo). SSO-Auth
`RoleClaim` is `roles`; `Roles` is `jellyfin:read` and `jellyfin:admin`;
`AdminRoles` is `jellyfin:admin`; `EnableAllFolders` stays on.

Jellyfin **admin** is still opt-in: put the user in group `jellyfin
admin` (mapped to `jellyfin:admin`). Do not use realm role `admin`. Keep
CanonicalLinks.

## Consequences

Any Keycloak user who SSO-logs into Jellyfin gets all libraries. Dashboard
access requires the `jellyfin admin` group. The `jellyfin reader` group
still maps to `jellyfin:read` but is not required for login.
`jellyfin:admin` is a composite of `jellyfin:read`. The jellyfin client
does not use full scope. Local Jellyfin password users are unchanged.
See [jellyfin.md](../services/jellyfin.md) and
[keycloak.md](../services/keycloak.md).
