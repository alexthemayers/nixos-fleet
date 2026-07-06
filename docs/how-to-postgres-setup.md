# How-To: PostgreSQL Initialization & Backups

In NixOS, the standard PostgreSQL module provides `ensureDatabases` and `ensureUsers`. While excellent for simple
setups, it lacks the flexibility to run complex schema initialization, install specific extensions (like `pgvector`), or
apply passwords from SOPS files.

To handle these requirements, `nixos-fleet` utilizes custom `oneshot` systemd scripts running after the database boots.

## 1. Custom Setup Scripts (`postgresql-custom-setup`)

Instead of fighting the declarative limits of `ensureDatabases`, we write an imperative script that runs on every boot
to guarantee the database is in the correct state.

### Implementation Concept

(See `services/postgres.nix` for the full implementation.)

1. **Define a systemd service** that waits for postgres:
   ```nix
   systemd.services.postgresql-custom-setup = {
     description = "Custom PostgreSQL Setup";
     requires = [ "postgresql.service" ];
     after = [ "postgresql.service" ];
     wantedBy = [ "multi-user.target" ];
     serviceConfig = {
       Type = "oneshot";
       User = "postgres";
       RemainAfterExit = true;
     };
     script = ''
       PSQL="psql -p 5432 -tA"

       # Poll until PostgreSQL responds
       until $PSQL -d postgres -c '\q' 2>/dev/null; do
         sleep 1
       done

       # Execute your setup commands
       $PSQL -d my_db -c "CREATE EXTENSION IF NOT EXISTS pgvector;"
       
       # Apply passwords from SOPS securely via psql variables
       password=$(tr -d '\n' < "${config.sops.secrets."postgres/my_app_password".path}")
       echo "ALTER ROLE my_app WITH PASSWORD :'pw';" | $PSQL -v "pw=$password"
     '';
   };
   ```

### Tradeoffs

- **Pros**: Unlimited flexibility. Securely applies SOPS passwords without leaking them to the Nix store.
- **Cons**: Imperative shell scripting within a declarative OS. You must ensure your SQL commands are idempotent (e.g.
  `CREATE EXTENSION IF NOT EXISTS` or `ALTER ROLE`).

## 2. Remote Backups over SSH

Since NixOS is stateless, the database data directory is the most critical state in the entire fleet. Backups must be
frequent and immediately sent off-site (to the `rpi4` backup node).

### Implementation

1. **Enable the native module** to dump the databases:
   ```nix
   services.postgresqlBackup = {
     enable = true;
     backupAll = true;
     compression = "zstd";
     location = "/var/backup/postgresql";
     startAt = "*-*-* 02:00:00";
   };
   ```
2. **Inject a `postStart` script** to rsync the dump over SSH using a SOPS key:
   ```nix
   systemd.services.postgresqlBackup = {
     postStart = ''
       # Sync to the remote backup node using a secure key
       rsync -avz --remove-source-files \
         -e "ssh -i ${config.sops.secrets."ssh_backup/privkey".path} -o StrictHostKeyChecking=accept-new" \
         /var/backup/postgresql/ \
         alex@rpi4:/mnt/usb-backup/postgres_backups/
     '';
   };
   ```

### Tradeoffs

- **Pros**: Fully automated, encrypted at rest (`zstd` handles compression, SSH handles transit encryption), removes
  local storage burden by deleting the source file immediately.
- **Cons**: Requires `rpi4` to be highly available during the backup window (2 AM). If it fails, `postgresqlBackup` will
  report a systemd error.
