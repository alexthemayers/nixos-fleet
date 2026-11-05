# fleet.debian_guest

Installs and maintains `proxmox-applications-debian` (VM 109),
`proxmox-gitlab-debian` (VM 110), and `proxmox-observability-debian`
(VM 111). Hardware and cutover notes:
[proxmox-applications-debian.md](../../../../docs/services/proxmox-applications-debian.md),
[proxmox-gitlab-debian.md](../../../../docs/services/proxmox-gitlab-debian.md).
Decisions:
[2026-11-01-debian-applications-guest.md](../../../../docs/adr/2026-11-01-debian-applications-guest.md),
[2026-11-03-debian-guest-merged-playbook.md](../../../../docs/adr/2026-11-03-debian-guest-merged-playbook.md),
[2026-11-03-debian-guest-rootless-podman.md](../../../../docs/adr/2026-11-03-debian-guest-rootless-podman.md).

This collection is not the hypervisor playbook in [`ansible/`](../../../../ansible/).

## Roles

| Role | Runs on | What it does |
|------|---------|--------------|
| `vm` | `proxmox` | VM on `truenas-storage` from the Debian generic image, cicustom guest-agent snippet, X710 VF, iGPU when the NixOS VM is stopped |
| `base` | guest | SSH, guest agent, generic kernel (the cloud kernel has no `iavf`) |
| `network` | guest | iavf MAC and DHCP |
| `tailscale` | guest | package, listen port, and `tailscale up` when the node is not already running |
| `apps` | apps guest | Rootless Podman system units for the fifteen application workloads |
| `gitlab` | gitlab guest | Omnibus GitLab (held), backups, state loop image |
| `registry_cache` | gitlab guest | Rootless pull-through caches |

`site.yml` refuses to run without `--limit`, and refuses while the NixOS VM
that shares the guest's data is running. The last play sets virtio `net0` to
`link_down`: traffic uses the X710 VF.

## Usage

From the repository root:

```bash
ansible-galaxy collection install -r collections/ansible_collections/fleet/debian_guest/requirements.yml
make deploy-debian-guest
make debian-guest-check
```

Every make target passes `--limit`. Extra flags go in `ANSIBLE_ARGS`, e.g.
`make deploy-debian-guest ANSIBLE_ARGS="--tags jellyfin"`. Tags: one per role
(`base`, `network`, `tailscale`, `firewall`, `monitoring`, `nfs`, `apps`,
`gitlab`, `registry_cache`), one per application inside `apps`, and
`provision` for the VM itself. Check mode reads the VM through `qm` but
changes nothing. When `proxmox` does not resolve in SSH config, set
`PROXMOX_ANSIBLE_HOST` to an address the controller can SSH to. Do not commit
that address.

VM 110 uses the same playbook. Apply it only after VM 102 is stopped:

```bash
make deploy-debian-gitlab
make debian-gitlab-check
make deploy-debian-observability
make deploy-debian-observability ANSIBLE_ARGS="-e debian_guest_cutover=true"
```

The `vm` role needs `snippets` in the content of the `local` storage
(`make deploy-proxmox-host`). Guest SSH goes through `ProxyJump` to the
hypervisor, then to the LAN address the guest agent reports.
