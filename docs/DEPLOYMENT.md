# Deployment and backups

## The image

The `Dockerfile` has three stages:

1. `build`: gems, bootsnap and assets for the Rails app.
2. `ledger`: installs [Alire](https://alire.ada.dev/) (pinned release, SHA-256
   verified), selects the `gnat_native` + `gprbuild` toolchain, and builds
   the `ledger_core` shared library with
   `LEDGER_CORE_LIBRARY_TYPE=relocatable alr build --release`.
3. the final image: Ruby, the app, and the engine in `/rails/ledger_core/lib/`.

The library links dynamically against `libgnat-16.so` and `libgcc_s.so.1` from
the Alire toolchain. The `ledger` stage copies both beside
`libLedger_Core.so` and rewrites the library's RPATH to `$ORIGIN` with
`patchelf`, then checks with `ldd` that nothing resolves into the toolchain. The
runtime image therefore needs no Ada toolchain and no `LD_LIBRARY_PATH`.

`LEDGER_CORE_LIB=/rails/ledger_core/lib/libLedger_Core.so` is set in the image;
`LedgerEngine` loads that path (the default is `ledger_core/lib/libLedger_Core.so`
relative to the Rails root, which is where `script/build` puts it in development).
If the library is missing or cannot load, the app raises an error naming
`LEDGER_CORE_LIB`.

Only x86_64 is supported by the Alire release the Dockerfile downloads
(`config/deploy.yml` builds `amd64`). Bump `ALIRE_VERSION` and `ALIRE_SHA256`
together to upgrade; the GNAT version is whatever the crate's `alire.toml`
resolves to through Alire.

Build and check by hand:

```sh
docker build -t ammocounting .
docker run --rm --entrypoint "" -e SECRET_KEY_BASE_DUMMY=1 ammocounting \
  bin/rails runner 'p LedgerEngine.sum([1, 2, 3])'   # => 6
```

## Data on disk

All state is SQLite files in `/rails/storage`, which `config/deploy.yml` mounts
as the Docker volume `ammocounting_storage`:

| File                              | Contents                                  | Backup |
|-----------------------------------|-------------------------------------------|--------|
| `production.sqlite3`              | users, ledger, prices: **the only data that cannot be recreated** | required |
| `production_queue.sqlite3`        | Solid Queue jobs                          | optional |
| `production_cache.sqlite3`        | cache                                     | no |
| `production_cable.sqlite3`        | unused (ActionCable removed)              | no |

Rails runs SQLite in WAL mode, so each database may have `-wal` and `-shm` files
next to it. **Do not copy the `.sqlite3` file with `cp`, `rsync` or a volume
snapshot of a running app**: the copy can be missing committed transactions or be
corrupt. Take a consistent snapshot with SQLite's online backup, which is safe
while the app runs:

```sh
sqlite3 storage/production.sqlite3 ".backup storage/backups/production.sqlite3"
```

### Taking a backup with Kamal

`bin/kamal backup` (an alias in `config/deploy.yml`) writes a consistent
snapshot to `storage/backups/production.sqlite3` on the server's volume, replacing
the previous one. That is a snapshot beside the data, not a backup: copy it
off the server on a schedule, for example from cron on the host (adjust the
volume path with `docker volume inspect ammocounting_storage`):

```sh
# every hour: snapshot, then ship a dated copy somewhere else
kamal backup && \
  scp <host>:/var/lib/docker/volumes/ammocounting_storage/_data/backups/production.sqlite3 \
      "backups/production-$(date -u +%Y%m%dT%H%M%SZ).sqlite3"
```

Pick an interval to match how much trading history you can afford to lose, keep
several generations, and **test a restore** (below) at least once. The
alias has not been run against a real server.

### Checking and restoring

```sh
sqlite3 production.sqlite3 "PRAGMA integrity_check"   # prints: ok
```

To restore: stop the app (`bin/kamal app stop`), put the snapshot at
`storage/production.sqlite3` in the volume, delete any stale
`production.sqlite3-wal` and `-shm` files next to it, then start the app
(`bin/kamal app boot`). The entrypoint runs `db:prepare`, which applies any
newer migrations. The ledger's own checks (debits = credits, reconciliation)
run in the engine whenever a statement is produced, so a restored database that
disagrees with itself fails loudly rather than rendering wrong figures.

Append-only protection of postings is enforced in Rails models only (see
TODO.md), so a restore is also the recovery path for accidental `update_all` or
`delete_all` on the ledger tables.
