# Usage

## Prerequisites

- SSH as `pi` with passwordless sudo
- Existing mbierman UniFi install (`/home/pi/.firewalla/run/docker/unifi/docker-compose.yaml`)
- Docker running
- Enough free space on `/var/lib/docker` (~1.5 GB+) and `/data` (~1.2 GB after cleanup)
- A **local** UniFi admin, or a `.unf` you already copied off-box

## Recommended path

```bash
bash migrate-unifi-firewalla.sh --preflight
bash migrate-unifi-firewalla.sh
```

Log in with the local admin when prompted. The script takes a settings `.unf` and, unless `--settings-only`, a full `.unf`.

Then restore in the browser at `https://172.16.1.2:8443`.

## If you cannot log in to the old UI

Take a backup in the old UI first (Settings → System → Backups), copy it off the box, then:

```bash
bash migrate-unifi-firewalla.sh --backup-file /tmp/my-backup.unf
```

Or accept the newest on-disk autobackup only if it is fresh:

```bash
ls -t /data/unifi/data/backup/autobackup/*.unf | head -1
bash migrate-unifi-firewalla.sh --allow-stale-backup
```

`--allow-stale-backup` is for cases where you know the file is old and still want to cut over.

## Tight disk

The script runs a **safe** cleanup when `/data` is under 3 GB: old `/data/unifi-migration/20*` stamps except the newest, dangling `latest.unf` links, unused Docker containers/networks/images. It never deletes `/data/unifi` or the jacobalberty image.

```bash
bash migrate-unifi-firewalla.sh --cleanup-only
df -h /data /var/lib/docker
```

## Tight RAM (~1 GB free)

Use settings-only for the wizard restore. A full-history restore can OOM a Gold.

```bash
bash migrate-unifi-firewalla.sh --settings-only
```

## Already migrated

```text
Already migrated (lscr.io/linuxserver/unifi-network-application:...).
Use unifi-restore.sh / unifi-update.sh / unifi-status.sh / rollback.sh
```

That is expected. Do not re-run the migrator.

## Routes after a reboot

The installer boot hook should re-add `172.16.1.0/24`. If LAN clients cannot reach the UI:

```bash
ID=$(sudo docker network ls | awk '$2 == "unifi_default" {print $1}')
sudo ip route add 172.16.1.0/24 dev br-$ID table lan_routable
sudo ip route add 172.16.1.0/24 dev br-$ID table wan_routable
sudo ipset add -! docker_lan_routable_net_set 172.16.1.0/24
sudo ipset add -! docker_wan_routable_net_set 172.16.1.0/24
```
