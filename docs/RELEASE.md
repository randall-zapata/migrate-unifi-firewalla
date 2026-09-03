# Cutting a release

This repo's GitHub connection cannot create Releases from the API used here. Do it in the browser after the real script is on `main`.

1. Confirm `migrate-unifi-firewalla.sh` on `main` starts with `# migrate-unifi-firewalla.sh (v1.11)` and is ~24 KB, not the 406-byte stub.
2. Open https://github.com/randall-zapata/migrate-unifi-firewalla/releases/new
3. Tag: `v1.11` (create on `main`)
4. Title: `v1.11`
5. Attach `migrate-unifi-firewalla.sh` as a binary asset
6. Paste CHANGELOG v1.11 notes in the body
7. Publish

Topics (About → gear on the repo home): `firewalla`, `unifi`, `ubiquiti`, `docker`, `mongodb`, `migration`.
