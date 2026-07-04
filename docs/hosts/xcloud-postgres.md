# Database Host Profile: `xcloud-postgres`

This document details the configuration and storage architecture of **`xcloud-postgres`**, the centralized database node
that hosts services across the entire fleet.

---

## 💾 Storage Architecture & Disk Separation

Unlike standard nodes that mount filesystems on a single LVM root pool, the database host isolates database directories
onto a separate virtual block device to ensure reliability and facilitate resizing.

* **Disko Implementation:
  ** [hosts/xcloud-postgres/disk-config.nix](file:///Users/alex/code/nixos-fleet/hosts/xcloud-postgres/disk-config.nix)

```
        +-------------------------------------------------------+
        |                  xcloud-postgres VM                   |
        +-------------------------------------------------------+
                |                                       |
                v                                       v
      [/dev/vda] (20GB Disk)                  [/dev/vdb] (10GB Disk)
  +-----------+-----------+               +-----------------------------+
  |    ESP    |  LVM Vol  |               |        Postgres Vol         |
  |  (/boot)  |    (/)    |               |    (/var/lib/postgresql)    |
  +-----------+-----------+               +-----------------------------+
```

### Partition Scheme

1. **OS Root Disk (`/dev/vda`):**
   Hosts the operating system. Configured with a `GPT` partition table containing a `1MB` bios boot partition, a `500MB`
   ESP FAT32 partition (`/boot`), and an LVM physical volume mapped to the `pool` volume group hosting the `/` root ext4
   partition.
2. **Dedicated Database Disk (`/dev/vdb`):**
   A separate disk partition mapped entirely to an `ext4` filesystem mounted directly to `/var/lib/postgresql`.

### Benefits of Disk Isolation

* **Preventing OS Hangs:** If database logs or tables swell, only the isolated database disk runs out of space. The core
  operating system partition remains unaffected, allowing administrative SSH connections to remain active.
* **Targeted Snapshots & Backups:** Enables cloud platform snapshots of database volumes independently from OS system
  disks.
* **I/O Performance:** Isolates high-write database transactions from system log operations.

---

## 🔑 Database Service & Connection Architecture

The database software runs PostgreSQL 17. The connection flow, user mappings, and pgBouncer pooling are documented in
the **[PostgreSQL Service Guide](../services/postgres.md)**.

### Key Integration Points:

- **PgBouncer Port (`5432`):** Direct database operations and queries connect here.
- **Postgres Port (`5433`):** Internal database port, inaccessible to external networks.
- **PgBouncer Dynamic Auth:** Queries the `pg_shadow` table dynamically using `scram-sha-256` hashing to authorize
  incoming requests, bypassing static configuration text files.

---

## ⚡ Network Optimization

Because this database server accepts connections from the entire Tailscale mesh network, it relies on network
optimizations defined in [config/system.nix](file:///Users/alex/code/nixos-fleet/config/system.nix):

* **TCP BBR Congestion Control:** Enabled via `tcp_bbr` kernel module to handle high-bandwidth packets.
* **TCP Keepalives:** Set to `tcp_keepalive_time = 60` and `tcp_keepalive_intvl = 10` to ensure connection tunnels
  traversing firewalls do not drop idle database connections.
* **TCP MTU Probing:** Enforces dynamic segment discovery (`tcp_mtu_probing = 1`) to prevent packet black holes
  resulting from VPN overlay MTU restrictions.
