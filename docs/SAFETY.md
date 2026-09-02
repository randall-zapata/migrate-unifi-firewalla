# Safety

## Never deleted

- `/data/unifi` (jacobalberty data)
- `jacobalberty/unifi` image
- Firewalla system partitions
- Guest Wi-Fi / adopted devices (they keep informing to `172.16.1.2`)

## Cutover window

Downtime starts when the old `unifi` container is stopped and ends when the new UI answers on `:8443`. Devices retry inform on their own. Routes are added as soon as both new containers exist.

## False alarms from field runs

| Message | Reality |
|---|---|
| `mongo auth failed` right after `compose up` | Mongo was not listening yet. Wait and ping again. If containers are Up and UI is 200/302, do **not** rollback. |
| `inform` HTTP 400 from curl | Empty GET. Port is alive. Devices send a signed POST. |
| Newest backup looks like July | Copies in `/data/unifi-migration` got new mtimes. Use `/data/unifi/data/backup/autobackup/` and the `YYYYMMDD` in the filename. |
| No backup from today | Monthly autobackup at 00:30 UTC. `20260901_0030` is 1 Sep UTC / 31 Aug evening US Eastern. |
| Mobile app support ended | Ubiquiti policy on classic self-hosted Network. Not a script bug. Use the web UI. |

## After the old container is gone

Check before rollback:

```bash
sudo docker ps -a --filter name=unifi
curl -k -s -o /dev/null -w "UI %{http_code}\n" https://172.16.1.2:8443/
```

Rollback only if the new UI is dead and you need the old controller back immediately.

## Secrets

`.migration-env` holds Mongo passwords. Mode `600`. Not for git.
