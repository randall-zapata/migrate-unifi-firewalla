# migrate-unifi-firewalla

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Migrate a UniFi Network controller on a **Firewalla Gold-series** router from the community [mbierman installer](https://github.com/mbierman/unifi-installer-for-Firewalla) (`jacobalberty/unifi`) to linuxserver Network Application + external MongoDB.

**Inform address stays `172.16.1.2`.** `/data/unifi` and the jacobalberty image are never deleted.

Current script: **v1.11**

> Official UniFi mobile apps no longer support classic self-hosted Network. Use the web UI at `https://172.16.1.2:8443`. This is not UniFi OS Server.

## Quick start

```bash
curl -fsSL -o migrate-unifi-firewalla.sh \
  https://raw.githubusercontent.com/randall-zapata/migrate-unifi-firewalla/main/migrate-unifi-firewalla.sh
scp migrate-unifi-firewalla.sh pi@<firewalla-ip>:/tmp/
chmod 755 /tmp/migrate-unifi-firewalla.sh
bash /tmp/migrate-unifi-firewalla.sh --preflight
bash /tmp/migrate-unifi-firewalla.sh
```

Prefer a [GitHub Release](https://github.com/randall-zapata/migrate-unifi-firewalla/releases) asset when one exists so you are not tracking `main`.

Use a **local** UniFi admin (not ui.com SSO). Type `SKIP` only for the newest `/data/unifi/data/backup/autobackup/*.unf` (must be < 48h unless `--allow-stale-backup`).

## Security

- Do not commit or paste `/home/pi/.firewalla/run/docker/unifi/.migration-env` (Mongo passwords).
- Do not publish `:8443` / `:8080` to the internet.
- See [SECURITY.md](SECURITY.md).

## Docs

- [docs/USAGE.md](docs/USAGE.md)
- [docs/SAFETY.md](docs/SAFETY.md)
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
- [MIGRATION-DESIGN.md](MIGRATION-DESIGN.md)
- [CHANGELOG.md](CHANGELOG.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)

## License

[MIT](LICENSE). Community script. Not affiliated with Ubiquiti or Firewalla.
