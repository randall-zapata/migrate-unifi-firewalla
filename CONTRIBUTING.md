# Contributing

Read [MIGRATION-DESIGN.md](MIGRATION-DESIGN.md) before changing behavior.

## Invariants (do not break)

- Controller IP `172.16.1.2` on Docker net `unifi_default` / `172.16.1.0/24`
- Compose file schema `"3"` for Firewalla `docker-compose` 1.29.x
- Never delete `/data/unifi` or the jacobalberty image
- Mongo `4.4` on x86_64 without AVX (do not upgrade in place to 7.0)
- Backup freshness from UniFi filename date, not staged-copy mtime

## How to test

On a Gold still running jacobalberty:

```bash
bash migrate-unifi-firewalla.sh --preflight
bash -n migrate-unifi-firewalla.sh
```

Do not test `--wipe-new-data` against a site that still needs rollback.

## Docs

Update README and CHANGELOG in the same change as the script.
