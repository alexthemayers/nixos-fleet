# ADR: Jellyfin XML config is Nix-managed

**Status:** accepted (2026-09-04)

## Context

Jellyfin on `proxmox-applications-1` stored server, encoding, network,
branding, library, and plugin settings as XML on
`truenas-scale:/mnt/ssd/jellyfin/config`. Only `logging.json` and a
`preStart` sed of `EnableThrottling` came from this repo. Dashboard edits
were the real source of truth, including the SSO-Auth client secret in
plaintext on NFS.

nixpkgs `services.jellyfin.transcoding` writes a subset of `encoding.xml`
and would drop QSV, VPP tonemap, and throttle timing already on this
host. The unmaintained `declarative-jellyfin` flake mutates SQLite.
Neither matches how this fleet injects config (store files +
`BindReadOnlyPaths`, secrets via sops).

## Decision

Ship the extracted XML under `services/jellyfin/`. A oneshot copies it
into `/run/jellyfin/live` and `BindPaths` overlays those files (writable)
so Jellyfin can rewrite `encoding.xml` on start. `network.xml`
`KnownProxies` is rendered at start from MagicDNS for `xcloud-caddy` and
`proxmox-lb` (plus `127.0.0.1`). The SSO-Auth `OidSecret` is
`jellyfin/sso_oid_secret` in the apps-1 sops file.

Users, watch state, `library.db` / `jellyfin.db`, metadata, and plugin
DLLs stay on the NFS share. Edit the files in `services/jellyfin/` and
deploy; do not rely on the dashboard for those settings.

## Consequences

A dashboard save of a managed file is shadowed until the next start, then
lost. Do not chown the config dataset to the NixOS `jellyfin` uid; NFS
still shows uid 3000 and the binds do not need a chown.
`EnableThrottling` remains on in `encoding.xml`
([2026-08-31-jellyfin-transcode-throttle](2026-08-31-jellyfin-transcode-throttle.md)).
Rotate the Keycloak `jellyfin` client secret in sops, not in the XML.
