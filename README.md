# migrate-unifi-firewalla

Migrate a UniFi Network controller on a **Firewalla Gold-series** box from the community [mbierman/unifi-installer-for-Firewalla](https://github.com/mbierman/unifi-installer-for-Firewalla) layout (`jacobalberty/unifi`) to:

- `lscr.io/linuxserver/unifi-network-application` (pinned default: **10.6.101**)
- `docker.io/mongo:4.4` or `7.0` (4.4 on Golds without AVX)

**Inform address stays `172.16.1.2`.** Adopted APs and switches keep talking to the same IP. `/data/unifi` and the jacobalberty image are never deleted (rollback).

Script version: **v1.11**

## Who this is for

- Firewalla Gold / Gold Plus / Gold Pro / Gold SE
- UniFi already installed with the mbierman Docker installer
- You want a current Network Application release and a separate MongoDB

This is **not** UniFi OS Server. Official mobile apps have dropped classic self-hosted Network. The web UI at `https://172.16.1.2:8443` still works. Do not put UniFi OS Server on a 4 GB Firewalla.

## What it does not touch

- `/data/unifi` (old install = rollback)
- `jacobalberty/unifi` image
- Firewalla routing except `172.16.1.0/24` on `unifi_default` (same as the installer)
- Gold-SE MASQUERADE in `start_unifi.sh`

## Quick start

On a laptop:

```bash
curl -fsSL -o migrate-unifi-firewalla.sh \
  https://raw.githubusercontent.com/randall-zapata/migrate-unifi-firewalla/main/migrate-unifi-firewalla.sh
scp migrate-unifi-firewalla.sh pi@<firewalla>:/tmp/
```

On the Firewalla (user `pi`):

```bash
chmod 755 /tmp/migrate-unifi-firewalla.sh
bash /tmp/migrate-unifi-firewalla.sh --preflight
bash /tmp/migrate-unifi-firewalla.sh
```

Use a **local** UniFi admin (not ui.com SSO) when asked so the script can take a **fresh** `.unf`. Type `SKIP` only if you accept the newest file under `/data/unifi/data/backup/autobackup/` (must be < 48 hours old unless you pass `--allow-stale-backup`).

After the script finishes:

1. Open `https://172.16.1.2:8443`
2. Restore the **newest original** `.unf` from `/data/unifi/data/backup/autobackup/` (filename date `YYYYMMDD`, not a copy under `/data/unifi-migration`)
3. On a 4 GB Gold, prefer a **settings-only** restore if the wizard offers it
4. Confirm Inform Host is still `172.16.1.2`

Do **not** re-run the migrator if `unifi` is already `linuxserver/unifi-network-application`. Use the helpers it writes:

| Helper | Path |
|---|---|
| Restore `.unf` | `~/.firewalla/run/docker/unifi/unifi-restore.sh FILE.unf` |
| Update app | `~/.firewalla/run/docker/unifi/unifi-update.sh --i-have-a-backup` |
| Status | `~/.firewalla/run/docker/unifi/unifi-status.sh` |
| Roll back to jacobalberty | `~/.firewalla/run/docker/unifi/rollback.sh` |

## Useful flags

```text
--preflight              checks only
--backup-file PATH       use this .unf
--settings-only          API backup without stats history
--allow-stale-backup     allow a .unf older than 48 hours
--cleanup / --cleanup-only
--wipe-new-data          wipe leftover /data/unifi-app and /data/unifi-db
--mongo-tag 4.4          required on Gold x86_64 without AVX
--unifi-tag 10.6.101
--auto                   -y + restore attempt + cleanup; still needs a local admin or --backup-file
```

## Disk and RAM (Gold)

Images live on **`/var/lib/docker`**, not `/data`. `/data` only needs the new app + db dirs while `/data/unifi` stays.

Typical Gold: ~4 GB RAM, ~1 GB free while the old controller is running. Restore **settings-only**. Mongo is capped at 0.5 GB WiredTiger cache. Do not move Mongo to `7.0` on a CPU without AVX.

## After cutover checks

```bash
curl -k -s -o /dev/null -w "UI %{http_code}\n" https://172.16.1.2:8443/
curl -s -o /dev/null -w "inform %{http_code}\n" http://172.16.1.2:8080/inform
# inform 400 from curl is normal (empty GET)
ip route show table lan_routable | grep 172.16.1
```

## Design

Read [MIGRATION-DESIGN.md](MIGRATION-DESIGN.md) before changing invariants (`172.16.1.2`, `unifi_default`, compose schema `"3"`, Firewalla `docker-compose` 1.x).

## Disclaimer

Community script. No warranty. Test on one site, keep `/data/unifi` until devices look adopted. Not affiliated with Ubiquiti or Firewalla.

## License

MIT
