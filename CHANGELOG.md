# Changelog

## v1.11

- Pick newest autobackup from `/data/unifi/.../autobackup` only
- Backup age from filename `YYYYMMDD`, not copy mtime
- `cp -p` when staging copies
- Retry inform after UI is up; HTTP 400 counts as alive
- Done banner prints script-picked file and newest original

## v1.10

- Fresh `.unf` required before cutover (48 hour gate)
- Empty username no longer skips; type `SKIP` on purpose
- API backup takes settings + full when logged in
- `--allow-stale-backup`
- Wait up to 60s for Mongo after `compose up`
- `ensure_routes` as soon as both containers exist

## v1.9

- `--auto` with per-step `require` gates
- `--cleanup` / `--cleanup-only` (never `/data/unifi`)
- Disk forecast split: `/data` vs Docker root
- Helpers: `unifi-restore.sh`, `unifi-status.sh`, `unifi-update.sh`, `rollback.sh`

## Earlier

v1.1–v1.8: preflight, API backup, linuxserver compose, Mongo warmup, Firewalla invariants (`172.16.1.2`, compose v1, boot hook).
