# Troubleshooting

Gather this first:

```bash
uname -m
grep -c -w avx /proc/cpuinfo
sudo docker inspect unifi --format '{{.Config.Image}} {{.State.Status}}'
curl -ks https://172.16.1.2:8443/status | head -c 200; echo
df -h /data /var/lib/docker
head -2 /tmp/migrate-unifi-firewalla.sh
```

## Preflight: not enough space on /data

Images live on `/var/lib/docker`, not `/data`. The script runs safe cleanup when `/data` is under 3 GB (old migration stamps only). It never deletes `/data/unifi`.

```bash
bash migrate-unifi-firewalla.sh --cleanup-only
sudo docker system df
```

## mongo auth failed right after compose up

Usually Mongo is not listening yet. Check:

```bash
sudo docker ps -a --filter name=unifi
sudo docker exec unifi-db bash -c 'mongo --quiet --authenticationDatabase admin -u unifi -p "$MONGO_PASS" --eval "db.adminCommand(\"ping\").ok"'
curl -k -s -o /dev/null -w "UI %{http_code}\n" https://172.16.1.2:8443/
```

If both containers are Up and UI is 200/302, **do not rollback**. Wait and restore in the browser.

## inform HTTP 400

Empty `curl` GET. The port is alive. Devices send a signed POST.

## Newest backup looks like July / no file from today

Copies under `/data/unifi-migration` get new mtimes. Use:

```bash
ls -t /data/unifi/data/backup/autobackup/*.unf | head -1
```

Filename `autobackup_10.0.162_20260901_0030_*.unf` is 1 Sep 00:30 **UTC** (evening of 31 Aug in US Eastern). Monthly autobackup will not have “today” unless you took a manual backup.

## No 172.16.1.0/24 in lan_routable

```bash
ID=$(sudo docker network ls | awk '$2 == "unifi_default" {print $1}')
sudo ip route add 172.16.1.0/24 dev br-$ID table lan_routable
sudo ip route add 172.16.1.0/24 dev br-$ID table wan_routable
sudo ipset add -! docker_lan_routable_net_set 172.16.1.0/24
sudo ipset add -! docker_wan_routable_net_set 172.16.1.0/24
```

## Already migrated

Expected if the image is already linuxserver. Use `unifi-restore.sh`, `unifi-update.sh`, `unifi-status.sh`, or `rollback.sh` — not the migrator.

## Mobile app: Support Ended

Ubiquiti dropped official mobile support for classic self-hosted Network. Use `https://172.16.1.2:8443`. This script does not install UniFi OS Server on a Gold.

## Need the old controller back

Only if the new UI is dead:

```bash
/home/pi/.firewalla/run/docker/unifi/rollback.sh
```
