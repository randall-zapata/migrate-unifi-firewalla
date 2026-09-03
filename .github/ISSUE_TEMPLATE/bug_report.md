---
name: Bug report
about: Script failed or left the stack in a bad state
labels: bug
---

**Do not paste `.migration-env`, Mongo passwords, or UniFi admin passwords.**

### Hardware
- Firewalla series (Gold / Plus / Pro / SE):
- `uname -m`:
- AVX present? (`grep -c -w avx /proc/cpuinfo`):

### Versions
- Script version (first lines of the .sh):
- Old image (`docker inspect unifi --format '{{.Config.Image}}'`):
- Old Network version if known:

### Disk
```
df -h /data /var/lib/docker
```

### What you ran
```

```

### What happened
Paste preflight / step output (redact usernames if you want).

### After the failure
```
sudo docker ps -a --filter name=unifi
curl -k -s -o /dev/null -w "UI %{http_code}\n" https://172.16.1.2:8443/
```
