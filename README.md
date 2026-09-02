# migrate-unifi-firewalla

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Migrate a UniFi Network controller on a **Firewalla Gold-series** router from the community [mbierman installer](https://github.com/mbierman/unifi-installer-for-Firewalla) (`jacobalberty/unifi`) to:

| Role | Image | Default tag |
|---|---|
| Network Application | `lscr.io/linuxserver/unifi-network-application` | `10.6.101` |
| Database | `docker.io/mongo` | `4.4` on Golds without AVX, else `7.0` |

**Inform address stays `172.16.1.2`.** Adopted APs and switches keep talking to the same IP. The old tree `/data/unifi` and the jacobalberty image are **never deleted**, so you can roll back.

Current script: **v1.11**

> Official UniFi mobile apps no longer support classic self-hosted Network. The web UI at `https://172.16.1.2:8443` still works. This project does **not** install UniFi OS Server (it does not fit a 4 GB Firewalla).

## Who this is for

- Firewalla **Gold / Gold Plus / Gold Pro / Gold SE**
- UniFi already installed with the mbierman Docker installer
- You want a current Network Application build and a separate MongoDB

Not for: Cloud Key, UniFi OS consoles, Raspberry Pi-only images, or a first-time UniFi install (use mbierman first).

## What it does not touch

- `/data/unifi` (old install = rollback source)
- `jacobalberty/unifi` image
- Firewalla WAN / LAN policy except `172.16.1.0/24` on `unifi_default`
- Gold-SE MASQUERADE rules in `start_unifi.sh`

## Quick start

On a laptop:

```bash
curl -fsSL -o migrate-unifi-firewalla.sh \
  https://raw.githubusercontent.com/randall-zapata/migrate-unifi-firewalla/main/migrate-unifi-firewalla.sh
scp migrate-unifi-firewalla.sh pi@<firewalla-ip>:/tmp/
```

On the Firewalla as user `pi`:

```bash
chmod 755 /tmp/migrate-unifi-firewalla.sh
bash /tmp/migrate-unifi-firewalla.sh --preflight
bash /tmp/migrate-unifi-firewalla.sh
```

Use a **local** UniFi admin (not ui.com SSO) so the script can take a fresh `.unf`. Type `SKIP` only if you accept the newest file under `/data/unifi/data/backup/autobackup/` (must be under 48 hours old unless `--allow-stale-backup`). Empty username is ignored.

## After cutover

1. Open `https://172.16.1.2:8443`
2. Restore the newest **original** `.unf` from `/data/unifi/data/backup/autobackup/` (filename date `YYYYMMDD`)
3. On a 4 GB Gold, prefer settings-only
4. Confirm Inform Host is still `172.16.1.2`

Do not re-run the migrator if the container is already linuxserver. Use the helpers in `/home/pi/.firewalla/run/docker/unifi/`.

```bash
curl -k -s -o /dev/null -w "UI %{http_code}\n" https://172.16.1.2:8443/
curl -s -o /dev/null -w "inform %{http_code}\n" http://172.16.1.2:8080/inform
# inform 400 from empty curl GET is normal
ip route show table lan_routable | grep 172.16.1
```

## Flags

| Flag | Meaning |
|---|---|
| `--preflight` | Checks only |
| `--backup-file PATH` | Use this `.unf` |
| `--settings-only` | API backup without stats |
| `--allow-stale-backup` | Allow `.unf` older than 48h |
| `--cleanup` / `--cleanup-only` | Safe `/data` cleanup (never `/data/unifi`) |
| `--wipe-new-data` | Wipe leftover new app/db dirs |
| `--mongo-tag 4.4` | Required without AVX |
| `--unifi-tag 10.6.101` | Pin linuxserver tag |
| `--auto` | `-y` + restore attempt + cleanup |
| `-y` | Confirm prompts |

## Helpers on the box

| Helper | Path |
|---|---|
| Restore | `/home/pi/.firewalla/run/docker/unifi/unifi-restore.sh FILE.unf` |
| Update | `/home/pi/.firewalla/run/docker/unifi/unifi-update.sh --i-have-a-backup` |
| Status | `/home/pi/.firewalla/run/docker/unifi/unifi-status.sh` |
| Rollback | `/home/pi/.firewalla/run/docker/unifi/rollback.sh` |

## Disk and RAM

Images live on `/var/lib/docker`. New data is `/data/unifi-app` and `/data/unifi-db`. Leave `/data/unifi` for rollback. Typical Gold has ~1 GB free RAM — restore settings-only. Do not move Mongo to 7.0 without AVX.

## Docs

- [docs/USAGE.md](docs/USAGE.md)
- [docs/SAFETY.md](docs/SAFETY.md)
- [MIGRATION-DESIGN.md](MIGRATION-DESIGN.md)
- [CHANGELOG.md](CHANGELOG.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)

## Disclaimer

Community script. No warranty. Not affiliated with Ubiquiti or Firewalla.

## License

[MIT](LICENSE)
