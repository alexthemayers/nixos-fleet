---
status: accepted
date: 2026-09-07
---

# Proxmox Administrator is alex.mayers@Keycloak

## Context and Problem Statement

The OpenID realm on `proxmox` is named `Keycloak` and uses
`username-claim preferred_username`. Keycloak user `alex.mayers` therefore
logs in as `alex.mayers@Keycloak`. Ansible `user.cfg` granted
Administrator to `alex@keycloak`, a userid that cannot authenticate
against that realm. GUI ACL edits do not persist because `pve_config`
replaces `/etc/pve/user.cfg`.

## Considered Options

* Keep `alex@keycloak` in the template
* Grant Administrator only in the Proxmox UI
* Declare `alex.mayers@Keycloak` in Ansible and grant Administrator there
* Map PVE roles from a Keycloak `groups-claim`

## Decision Outcome

Chosen option: "Declare `alex.mayers@Keycloak` in Ansible and grant
Administrator there", because that is the userid OpenID actually
creates, and `user.cfg` is owned by
[`ansible/roles/pve_config/`](../../ansible/roles/pve_config/).

Do not use `alex@keycloak`. Do not add this ACL only in the UI. Realm
name case and `preferred_username` must match
[`domains.cfg.j2`](../../ansible/roles/pve_config/templates/domains.cfg.j2).
Keycloak is the default login realm (`default 1`).

The unused `terraform-prov@pve` user, API token, `TerraformProv` role,
and token ACL are removed. PVE 9 ignored that token line
(`ignore invalid acl token`).

### Consequences

OpenID login as `alex.mayers` has Administrator on `/` after
`pve_config` apply. The next playbook run no longer deletes that user
or the ACL. Recreating a Terraform provider token is out of band if
one is needed again.

## Validation

On `proxmox`: `pveum user list` shows `alex.mayers@Keycloak`;
`pveum acl list` shows Administrator on `/` for that user and
`root@pam`.

## More Information

[proxmox-host.md](../services/proxmox-host.md),
[2026-08-31-proxmox-ansible.md](2026-08-31-proxmox-ansible.md).
