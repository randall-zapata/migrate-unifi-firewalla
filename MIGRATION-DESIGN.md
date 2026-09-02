See companion design notes in this repository. Invariants: inform IP 172.16.1.2, compose dir /home/pi/.firewalla/run/docker/unifi, never delete /data/unifi, Mongo 4.4 on Gold without AVX, backup age from UniFi filename YYYYMMDD not copy mtime.

Full design document: keep 172.16.1.2, unifi_default 172.16.1.0/24, Firewalla docker-compose 1.x, linuxserver + external mongo, restore via wizard .unf.
