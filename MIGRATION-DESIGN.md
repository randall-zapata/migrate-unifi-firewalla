# Migration design (invariants)

Companion to `migrate-unifi-firewalla.sh` v1.11. Read this before editing the script.

## Problem

mbierman’s Firewalla installer runs `jacobalberty/unifi` (last useful build 10.0.162). linuxserver ships current Network Application but requires an external MongoDB. DB files are not compatible. Path is: `.unf` backup → new stack → wizard restore.

UniFi OS Server in Docker was rejected for Gold (cgroup host, ~2 GB RAM, port fight with 8080/8443).

## Environment the script assumes

| Fact | Value |
|---|---|
| SSH user | `pi`, passwordless sudo |
| Compose dir | `/home/pi/.firewalla/run/docker/unifi/` |
| Compose file | `docker-compose.yaml` (schema `"3"`) |
| Compose binary | `docker-compose` 1.x |
| systemd | `docker-compose@unifi` |
| Boot hook | `/home/pi/.firewalla/config/post_main.d/start_unifi.sh` |
| Docker net | `unifi_default`, `172.16.1.0/24` |
| Controller IP | `172.16.1.2` |
| Routes | `172.16.1.0/24` in `lan_routable` and `wan_routable` |
| Old data | `/data/unifi` |
| Autobackups | `/data/unifi/data/backup/autobackup/*.unf` |

Keeping `172.16.1.2` is what lets adopted devices reconnect with no set-inform.

## Target

- `unifi` on `unifi_default` at `172.16.1.2` (linuxserver, `/config` → `/data/unifi-app`)
- `unifi-db` on an internal net only (`mongo:4.4` or `7.0`, `/data/unifi-db`, WiredTiger 0.5 GB)

## Control flow

1. Preflight
2. Backup (API local admin, or newest original autobackup with age gate)
3. Pull images while old controller still runs
4. Write compose + helpers
5. Warm Mongo, then remove warmup container
6. Stop old `unifi`
7. `compose up`, routes, wait Mongo, wait UI, check inform

## Field lessons in v1.11

- `/data` vs `/var/lib/docker` are different filesystems
- Copy mtime is not backup age; use filename `YYYYMMDD`
- Empty username must not skip API backup
- Mongo probe immediately after `up` is a false failure
- curl `/inform` → 400 is success
- Do not treat post-cutover probe failure as must-rollback
