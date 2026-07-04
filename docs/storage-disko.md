# Storage Partitioning & Bootstrapping with Disko

This document describes the declarative storage partitioning strategy used across the fleet and outlines the procedure
for partitioning and bootstrapping a new host using **Disko**.

---

## 📐 Declarative Disko Layout Schema

Most target hosts in this repository share a standardized disk partitioning scheme defined in the global configuration:

* **Global Config:** [disko/disk-config.nix](file:///Users/alex/code/nixos-fleet/disko/disk-config.nix)

Disko dynamically partitions the target device specified by the custom option `fleet.disk.path` using an **LVM-on-GPT**
strategy:

```
+-----------------------------------------------------------+
|                      Physical Disk                        |
+-----------------------------------------------------------+
  | (1MB Partition)   | (500MB ESP)     | (100% Free space)
  v                   v                 v
[boot]              [ESP]             [root]
(Type: EF02)        (FAT32 vfat)      (LVM Physical Volume)
                    Mounted: /boot              |
                                                v
                                        [pool] (Volume Group)
                                                |
                                                v
                                        [root] (Logical Volume)
                                        (ext4 filesystem)
                                        Mounted: /
```

### Partition Allocations

1. **`boot` Partition (1MB):** Type `EF02`. Used for BIOS compatibility on legacy GPT setups (allowing GRUB stage 1.5 to
   be embedded).
2. **`esp` Partition (500MB):** Type `EF00`. Formatted as FAT32 (`vfat`) and mounted to `/boot` to host the system EFI
   bootloader closures.
3. **`root` Partition (Remaining Disk):** Mapped as an LVM physical volume (`lvm_pv`) added to the volume group `pool`.
4. **`root` Logical Volume (100% Free):** Formatted as `ext4` with standard mount options and mounted directly to `/`.

---

## 🛠️ Host Bootstrapping Walkthrough

To provision a brand-new bare-metal machine or virtual machine using the repository's Disko configurations, follow these
steps:

### 1. Boot from NixOS Live Installer

Boot the target node using the official NixOS minimal live installer image.

### 2. Configure SSH and Fetch the Flake

Configure temporary network access and start the SSH agent to copy configurations:

```bash
# Set a temporary password for root
sudo passwd root

# Verify your IP address
ip addr
```

### 3. Format and Partition via Disko

From your local management workstation (with access to the repository flake), target the remote node using
`nixos-anywhere` to automate partitioning and installation.

If you prefer to perform formatting and installation **manually on the target node**:

```bash
# Retrieve the flake repository
git clone https://github.com/your-org/nixos-fleet.git /tmp/nixos-fleet
cd /tmp/nixos-fleet

# Run Disko to partition, format, and mount the disk automatically
# (Replace device path /dev/sda with your target disk path)
nix --experimental-features "nix-command flakes" run github:nix-community/disko -- \
  --mode disko ./disko/disk-config.nix \
  --write-to-disk
```

### 4. Build and Install Configuration

Once Disko finishes mounting filesystems under `/mnt`, install the target NixOS configuration declared in `flake.nix`:

```bash
# Generate hardware configuration details to /mnt/etc/nixos/
nixos-generate-config --no-filesystems --root /mnt

# Execute NixOS installation pointing to your host configuration
nixos-install --root /mnt --flake .#<hostname>

# Reboot the node
reboot
```

---

## 🗃️ Host-Specific Storage Customizations

While standard nodes follow the global LVM-on-GPT layout, certain nodes override this scheme:

* **`xcloud-postgres`** ([disk-config.nix](file:///Users/alex/code/nixos-fleet/hosts/xcloud-postgres/disk-config.nix)):
  Isolates the root operating system on `/dev/vda` and formats a dedicated storage volume `/dev/vdb` mounted directly on
  `/var/lib/postgresql` for PostgreSQL data transactions.
* **Loopback Mounts (`services.build-cache`)**:
  Dynamic mounts (e.g. for `/nix/var/nix/builds` and `/mnt/ssd/container-registry`) are allocated as loopback files
  inside NFS shares rather than physical partitions. See the **[Custom NixOS Options Guide](custom-options.md)** for
  details.
