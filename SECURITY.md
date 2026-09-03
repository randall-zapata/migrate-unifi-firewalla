# Security

## Secrets this project creates

After a successful migrate, Mongo passwords are written to:

`/home/pi/.firewalla/run/docker/unifi/.migration-env`

Mode should be `600`. **Never commit that file. Never paste it into a GitHub issue.**

`.gitignore` already excludes `.migration-env` and `.env`.

## Network scope

The controller is bound to `172.16.1.2` on the Firewalla Docker bridge. Inform is `http://172.16.1.2:8080/inform` on the LAN. Do not publish `:8443` or `:8080` to the internet.

The script talks only to that local URL and to Docker Hub / linuxserver for image pulls.

## Reporting a vulnerability

Open a private note to the repo owner rather than a public issue if it involves credentials, a remote-exec path, or a way to wipe `/data/unifi` without intent.

This is a community bash script with no warranty.
