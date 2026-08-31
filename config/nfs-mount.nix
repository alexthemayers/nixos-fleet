# Shared NFS automount options. GitLab's state image must not idle-unmount;
# do not use this helper there.
waitName: extra:
[
  "rw"
  "nfsvers=4.2"
  "_netdev"
  "noauto"
  "x-systemd.automount"
  "x-systemd.idle-timeout=600"
  "x-systemd.requires=wait-for-host-${waitName}.service"
  "x-systemd.after=wait-for-host-${waitName}.service"
]
++ extra
