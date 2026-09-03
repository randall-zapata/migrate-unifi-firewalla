#!/bin/bash
# migrate-unifi-firewalla.sh (v1.11)
# See header in --help. Never deletes /data/unifi or jacobalberty image.
set -u -o pipefail
COMPOSE_DIR=/home/pi/.firewalla/run/docker/unifi
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yaml"
ENV_FILE="$COMPOSE_DIR/.migration-env"
ENV_DOT="$COMPOSE_DIR/.env"
INIT_SH="$COMPOSE_DIR/init-mongo.sh"
OLD_DATA=/data/unifi
APP_DATA=/data/unifi-app
DB_DATA=/data/unifi-db
MIG_ROOT=/data/unifi-migration
CTRL_IP=172.16.1.2
CTRL_URL="https://$CTRL_IP:8443"
SUBNET=172.16.1.0/24
OLD_IMAGE_PREFIX="jacobalberty/unifi"
NEW_IMAGE_PREFIX="lscr.io/linuxserver/unifi-network-application"
OLD_UPDATER=/home/pi/.firewalla/run/docker/updatedocker.sh
LOCK_FILE=/tmp/migrate-unifi-firewalla.lock
STAMP=$(date +%Y%m%d-%H%M%S)
MIG_DIR="$MIG_ROOT/$STAMP"
PREFLIGHT=0; BACKUP_FILE=""; BACKUP_DAYS=-1; MONGO_TAG=""; UNIFI_TAG="10.6.101"
ASSUME_YES=0; WIPE_NEW=0; RESUME=0; BACKUP_STAYS_LOCAL=0; ALLOW_MAJOR_JUMP=0; ALLOW_STALE_BACKUP=0
DO_RESTORE=0; RESTORE_ANYWAY=0; AUTO=0; DO_CLEANUP=0; CLEANUP_ONLY=0
UNIFI_TAG_EXPLICIT=0; CUTOVER_DONE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --preflight) PREFLIGHT=1 ;;
    --backup-file) BACKUP_FILE="$2"; shift ;;
    --settings-only) BACKUP_DAYS=0 ;;
    --mongo-tag) MONGO_TAG="$2"; shift ;;
    --unifi-tag) UNIFI_TAG="$2"; UNIFI_TAG_EXPLICIT=1; shift ;;
    --wipe-new-data) WIPE_NEW=1 ;;
    --resume) RESUME=1 ;;
    --backup-stays-local) BACKUP_STAYS_LOCAL=1 ;;
    --allow-major-jump) ALLOW_MAJOR_JUMP=1 ;;
    --allow-stale-backup) ALLOW_STALE_BACKUP=1 ;;
    --restore) DO_RESTORE=1 ;;
    --no-restore) DO_RESTORE=0 ;;
    --restore-anyway) RESTORE_ANYWAY=1; DO_RESTORE=1 ;;
    --cleanup) DO_CLEANUP=1 ;;
    --cleanup-only) DO_CLEANUP=1; CLEANUP_ONLY=1 ;;
    --auto) AUTO=1; ASSUME_YES=1; DO_RESTORE=1; BACKUP_STAYS_LOCAL=1; DO_CLEANUP=1 ;;
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help)
      cat <<EOF
migrate-unifi-firewalla.sh v1.11
  --preflight --backup-file PATH --settings-only --mongo-tag --unifi-tag
  --wipe-new-data --resume --backup-stays-local --allow-major-jump
  --restore --restore-anyway --no-restore
  --cleanup --cleanup-only   safe /data cleanup (never /data/unifi)
  --auto  implies -y --restore --backup-stays-local --cleanup
  --allow-stale-backup  permit cutover if newest .unf is older than 48h
  -y
EOF
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
  shift
done
c_ok(){ echo -e "  ✅ $*"; }
c_warn(){ echo -e "  ⚠️  $*"; }
c_info(){ echo -e "  ▸ $*"; }
die(){ echo -e "\n  ❌ $*\n" >&2; [ "$CUTOVER_DONE" = 1 ] && echo "  Rollback: $COMPOSE_DIR/rollback.sh" >&2; exit 1; }
hr(){ echo -e "\n────────────────────────────────────────────────────────────\n  $*\n────────────────────────────────────────────────────────────"; }
log(){ [ -n "${RUNLOG:-}" ] && printf '%s %s\n' "$(date -Iseconds)" "$*" >> "$RUNLOG" || true; }
confirm(){ [ "$ASSUME_YES" = 1 ] && return 0; read -rp "  $1 [y/N] " ans; [[ "$ans" =~ ^[Yy]$ ]] || die "Aborted."; }
json_esc(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
randpw(){ tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32; }
unf_ok(){
  local f="$1" sz magic
  [ -f "$f" ] && [ -s "$f" ] || return 1
  sz=$(stat -c %s "$f" 2>/dev/null || echo 0)
  [ "$sz" -gt 10240 ] || return 1
  magic=$(od -An -tx1 -N4 "$f" 2>/dev/null | tr -d ' \n')
  case "$magic" in 504b0304|504b0506|504b0708) return 0 ;; esac
  printf '%s' "$magic" | grep -q '504b' && return 0
  case "$f" in *.unf|*.UNF) return 0 ;; esac
  return 1
}
require(){ local msg="$1"; shift; if "$@"; then c_ok "validated: $msg"; return 0; fi; die "validation failed: $msg"; }
image_present(){ sudo docker image inspect "$1" >/dev/null 2>&1; }
container_running(){ [ "$(sudo docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null || echo false)" = "true" ]; }
container_absent(){ ! sudo docker inspect "$1" >/dev/null 2>&1; }
ui_up(){ local c; c=$(curl -ks --max-time 5 -o /dev/null -w '%{http_code}' "$CTRL_URL/" || true); echo "$c" | grep -Eq '200|302'; }
inform_up(){ local c; c=$(curl -ks --max-time 5 -o /dev/null -w '%{http_code}' "http://$CTRL_IP:8080/inform" || true); echo "$c" | grep -Eq '^(200|400|401|403|404|405)$'; }
have_unf(){ [ -n "${API_BACKUP:-}" ] && [ -f "$API_BACKUP" ] && unf_ok "$API_BACKUP"; }
# Never trust mtime of files we just copied into $MIG_DIR — cp resets mtime
# unless -p, and the last file copied looks "newest". Prefer the original
# autobackup dir, then parse YYYYMMDD from the UniFi filename.
newest_autobackup(){
  local f
  f=$(sudo ls -t "$OLD_DATA"/data/backup/autobackup/*.unf 2>/dev/null | head -1)
  [ -n "$f" ] && { echo "$f"; return; }
  f=$(sudo ls -1 "$MIG_DIR"/autobackup/autobackup_*.unf 2>/dev/null | sort | tail -1)
  echo "$f"
}
backup_stamp_from_name(){
  local b; b=$(basename "$1")
  # autobackup_10.0.162_20260901_0030_1788222600040.unf
  echo "$b" | grep -oE '20[0-9]{6}' | head -1
}
backup_age_hours(){
  local f="$1" now m stamp ymd
  [ -f "$f" ] || { echo 9999; return; }
  now=$(date +%s)
  stamp=$(backup_stamp_from_name "$f")
  if [ -n "$stamp" ]; then
    ymd=$(date -d "$stamp" +%s 2>/dev/null || date -j -f %Y%m%d "$stamp" +%s 2>/dev/null || true)
    if [ -n "$ymd" ]; then echo $(( (now - ymd) / 3600 )); return; fi
  fi
  m=$(stat -c %Y "$f")
  echo $(( (now - m) / 3600 ))
}
require_fresh_backup(){
  local f="$1" age
  [ -n "$f" ] && [ -f "$f" ] || die "No .unf. Re-run, log in with a local admin so a fresh backup can be taken, or pass --backup-file."
  unf_ok "$f" || die "Backup $f is not a valid .unf"
  age=$(backup_age_hours "$f")
  c_info "Backup $f age=${age}h size=$(stat -c %s "$f") bytes"
  if [ "$age" -gt 48 ] && [ "$ALLOW_STALE_BACKUP" != 1 ]; then
    die "Newest backup is ${age}h old. Log in so the script can take a fresh .unf, pass --backup-file PATH, or --allow-stale-backup."
  fi
  if [ "$age" -gt 48 ]; then
    c_warn "Using stale backup (${age}h) because --allow-stale-backup was set."
  else
    c_ok "Backup is fresh enough (${age}h old)"
  fi
}
ensure_mig_workspace(){
  sudo mkdir -p "$MIG_DIR/autobackup" || die "Cannot create $MIG_DIR"
  sudo chown -R pi:pi "$MIG_ROOT" 2>/dev/null || sudo chown -R "$(id -u pi):$(id -g pi)" "$MIG_ROOT"
  [ -w "$MIG_DIR" ] || die "$MIG_DIR not writable by pi"
}
cleanup_data(){
  hr "Cleanup (never deletes /data/unifi or jacobalberty)"
  c_info "Before: /data $(df --output=avail -h /data | tail -1 | tr -d ' ') free"
  sudo du -sh /data/unifi /data/unifi-app /data/unifi-db /data/unifi-migration 2>/dev/null | sed 's/^/    /' || true
  if [ -d "$MIG_ROOT" ]; then
    mapfile -t stamps < <(sudo ls -1dt "$MIG_ROOT"/20* 2>/dev/null || true)
    if [ "${#stamps[@]}" -gt 1 ]; then
      local s
      for s in "${stamps[@]:1}"; do
        c_info "Removing old migration stamp $s"
        sudo rm -rf "$s"
      done
    fi
    if [ -L "$MIG_ROOT/latest.unf" ] && [ ! -e "$MIG_ROOT/latest.unf" ]; then
      sudo rm -f "$MIG_ROOT/latest.unf" "$MIG_ROOT/latest-settings.unf"
    fi
  fi
  if ! sudo docker inspect unifi >/dev/null 2>&1 && [ "$WIPE_NEW" = 1 ]; then
    sudo rm -rf "$APP_DATA" "$DB_DATA"
    c_ok "Wiped leftover $APP_DATA $DB_DATA"
  fi
  sudo docker container prune -f >/dev/null 2>&1 || true
  sudo docker network prune -f >/dev/null 2>&1 || true
  sudo docker image prune -f >/dev/null 2>&1 || true
  c_info "After:  /data $(df --output=avail -h /data | tail -1 | tr -d ' ') free"
  image_present "$OLD_IMAGE_PREFIX:latest" && c_ok "jacobalberty image still present"
  [ -d "$OLD_DATA" ] && c_ok "/data/unifi still present"
}
ensure_routes(){
  local ID
  ID=$(sudo docker network ls | awk '$2 == "unifi_default" {print $1}')
  [ -n "$ID" ] || return 0
  ip route show table lan_routable 2>/dev/null | grep -q "${SUBNET%/*}" || sudo ip route add "$SUBNET" dev "br-$ID" table lan_routable
  ip route show table wan_routable 2>/dev/null | grep -q "${SUBNET%/*}" || sudo ip route add "$SUBNET" dev "br-$ID" table wan_routable
  sudo ipset create -! docker_lan_routable_net_set hash:net 2>/dev/null || true
  sudo ipset create -! docker_wan_routable_net_set hash:net 2>/dev/null || true
  sudo ipset add -! docker_lan_routable_net_set "$SUBNET" 2>/dev/null || true
  sudo ipset add -! docker_wan_routable_net_set "$SUBNET" 2>/dev/null || true
  c_ok "Routes/ipsets for $SUBNET on br-$ID"
}
mongo_auth_ping(){
  local sh="$1"
  sudo docker exec unifi-db bash -c "$sh --quiet --authenticationDatabase admin -u unifi -p \"\$MONGO_PASS\" --eval 'db.adminCommand(\"ping\").ok'" 2>/dev/null | grep -q 1
}
wait_for_ui(){
  local label="$1" max="${2:-150}" i CODE
  echo -n "  Waiting for UI ($label)"
  for i in $(seq 1 "$max"); do
    sleep 4; echo -n "."
    CODE=$(curl -ks --max-time 5 -o /dev/null -w '%{http_code}' "$CTRL_URL/" || true)
    case "$CODE" in 200|302) echo; c_ok "Web UI HTTP $CODE"; return 0 ;; esac
    sudo docker ps --format '{{.Names}}' | grep -qx unifi || { echo; return 1; }
  done
  echo; return 1
}
image_digest(){ sudo docker image inspect "$1" --format '{{index .RepoDigests 0}}' 2>/dev/null || echo unknown; }
load_env(){ [ -f "$ENV_FILE" ] || return 0; set -a; # shellcheck disable=SC1090
  . "$ENV_FILE"; set +a; }
dc(){ load_env; ( cd "$COMPOSE_DIR" && $DC "$@" ); }
sync_dotenv(){ umask 077; cp "$ENV_FILE" "$ENV_DOT"; chmod 600 "$ENV_FILE" "$ENV_DOT"; umask 022; }

exec 9>"$LOCK_FILE"
flock -n 9 || die "Another migration holds $LOCK_FILE"

hr "Preflight checks"
[ "$(id -un)" = "pi" ] || die "Run as pi"
[ -d /home/pi/.firewalla ] || die "Not a Firewalla"
sudo -n true 2>/dev/null || die "Need passwordless sudo"
c_ok "Running as pi on a Firewalla"
command -v docker >/dev/null || die "docker missing"
sudo docker info >/dev/null 2>&1 || die "Docker not running"
c_ok "Docker daemon reachable"
if command -v docker-compose >/dev/null 2>&1; then DC="sudo docker-compose"
elif sudo docker compose version >/dev/null 2>&1; then DC="sudo docker compose"
else die "No compose"; fi
c_ok "Compose command: $DC"
[ -d "$COMPOSE_DIR" ] && [ -f "$COMPOSE_FILE" ] || die "mbierman compose missing"
c_ok "Compose project dir present"

CUR_IMAGE=$(sudo docker inspect unifi --format '{{.Config.Image}}' 2>/dev/null || true)
CUR_STATE=$(sudo docker inspect unifi --format '{{.State.Status}}' 2>/dev/null || true)
case "$CUR_IMAGE" in
  "$NEW_IMAGE_PREFIX"*|*linuxserver/unifi-network-application*)
    if [ "$CLEANUP_ONLY" != 1 ]; then
      die "Already migrated ($CUR_IMAGE). Use unifi-restore.sh / unifi-update.sh / unifi-status.sh / rollback.sh or --cleanup-only"
    fi ;;
  "$OLD_IMAGE_PREFIX"*) c_ok "Existing controller: $CUR_IMAGE ($CUR_STATE)" ;;
  "") c_warn "No unifi container" ;;
  *) c_warn "Unexpected image: $CUR_IMAGE" ;;
esac
OLD_VER=""
[ "$CUR_STATE" = "running" ] && OLD_VER=$(curl -ks --max-time 8 "$CTRL_URL/status" 2>/dev/null | grep -oE '"server_version":"[^"]+"' | head -1 | cut -d'"' -f4 || true)
[ -n "$OLD_VER" ] && c_ok "Running controller version: $OLD_VER"

ARCH=$(uname -m)
HAS_AVX=$(grep -c -m1 -w avx /proc/cpuinfo 2>/dev/null || true); HAS_AVX=${HAS_AVX:-0}
[ -z "$MONGO_TAG" ] && { if [ "$ARCH" = "x86_64" ] && [ "$HAS_AVX" -ge 1 ]; then MONGO_TAG="7.0"; else MONGO_TAG="4.4"; fi; }
c_ok "CPU: $ARCH AVX: $([ "$HAS_AVX" -ge 1 ] && echo yes || echo no) → Mongo $MONGO_TAG"
MONGO_MAJOR="${MONGO_TAG%%.*}"
if [ "$ARCH" = "x86_64" ] && [ "$HAS_AVX" -lt 1 ]; then
  case "$MONGO_MAJOR" in ''|*[!0-9]*) ;; *) [ "$MONGO_MAJOR" -ge 5 ] && die "Need --mongo-tag 4.4 (no AVX)" ;; esac
fi
MEM_AVAIL=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
MEM_TOTAL=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
PREFER_SETTINGS_RESTORE=0
[ "$MEM_AVAIL" -lt 2000 ] && PREFER_SETTINGS_RESTORE=1 && c_warn "Only ${MEM_AVAIL}MB RAM free — settings-only restore"

DISK_AVAIL=$(df --output=avail -m /data | tail -1 | tr -d ' ')
if [ "$DO_CLEANUP" = 1 ] || [ "$DISK_AVAIL" -lt 3000 ]; then
  [ "$DO_CLEANUP" = 1 ] || c_info "/data under 3GB — running safe cleanup"
  cleanup_data
  DISK_AVAIL=$(df --output=avail -m /data | tail -1 | tr -d ' ')
fi
if [ "$CLEANUP_ONLY" = 1 ]; then c_ok "Cleanup-only done. /data free ${DISK_AVAIL}MB"; exit 0; fi
if [ "$DISK_AVAIL" -lt 1200 ]; then die "Only ${DISK_AVAIL}MB free on /data after cleanup"; fi
if [ "$DISK_AVAIL" -lt 3000 ]; then c_warn "Only ${DISK_AVAIL}MB free on /data (images use Docker root)"; else c_ok "Disk free on /data: ${DISK_AVAIL}MB"; fi
DOCKER_ROOT=$(sudo docker info -f '{{.DockerRootDir}}' 2>/dev/null || echo /var/lib/docker)
if [ -d "$DOCKER_ROOT" ]; then
  DOCKER_FREE=$(df --output=avail -m "$DOCKER_ROOT" | tail -1 | tr -d ' ')
  [ "${DOCKER_FREE:-0}" -lt 1500 ] && die "Docker root only ${DOCKER_FREE}MB free"
  c_ok "Docker root $DOCKER_ROOT free: ${DOCKER_FREE}MB"
fi
TZ_VAL=$(cat /etc/timezone 2>/dev/null || echo America/New_York)
PUID=$(id -u pi); PGID=$(id -g pi)
c_ok "TZ=$TZ_VAL PUID=$PUID PGID=$PGID"
[ -n "$BACKUP_FILE" ] && { unf_ok "$BACKUP_FILE" || die "bad --backup-file"; c_ok "Using $BACKUP_FILE"; }
APP_HAS_DATA=0; DB_HAS_DATA=0
[ -d "$APP_DATA" ] && [ -n "$(sudo ls -A "$APP_DATA" 2>/dev/null)" ] && APP_HAS_DATA=1
[ -d "$DB_DATA" ] && [ -n "$(sudo ls -A "$DB_DATA" 2>/dev/null)" ] && DB_HAS_DATA=1
if [ "$PREFLIGHT" = 1 ]; then echo; c_info "Preflight only"; echo; exit 0; fi

hr "Plan"
echo "  $NEW_IMAGE_PREFIX:$UNIFI_TAG + mongo:$MONGO_TAG at $CTRL_IP"
confirm "Proceed?"
ensure_mig_workspace
RUNLOG="$MIG_DIR/migrate.log"
log "start v1.9"

hr "Step 1 — Backup"
cp "$COMPOSE_FILE" "$MIG_DIR/docker-compose.yaml.jacobalberty" 2>/dev/null || true
if sudo ls "$OLD_DATA"/data/backup/autobackup/*.unf >/dev/null 2>&1; then
  sudo ls -t "$OLD_DATA"/data/backup/autobackup/*.unf | head -3 | while read -r f; do sudo cp -p "$f" "$MIG_DIR/autobackup/"; done
  sudo chown -R pi:pi "$MIG_DIR/autobackup" 2>/dev/null || true
  c_ok "Copied newest autobackups by mtime: $(sudo ls -t "$OLD_DATA"/data/backup/autobackup/*.unf 2>/dev/null | head -1)"
fi
API_BACKUP=""; SETTINGS_BACKUP=""
if [ -n "$BACKUP_FILE" ]; then
  cp "$BACKUP_FILE" "$MIG_DIR/" && API_BACKUP="$MIG_DIR/$(basename "$BACKUP_FILE")"
  c_ok "Using --backup-file $API_BACKUP"
elif [ "$CUR_STATE" = "running" ]; then
  c_info "A *fresh* .unf will be taken now. Use a LOCAL admin (not ui.com / SSO)."
  c_info "Type SKIP only if you accept the newest on-disk autobackup (must pass --allow-stale-backup if it is >48h old)."
  LOGIN_OK=0; COOKIE=$(mktemp); HDRS=$(mktemp); RESP=$(mktemp)
  trap 'rm -f "$COOKIE" "$HDRS" "$RESP"' EXIT
  for _try in 1 2 3; do
    read -rp "  Controller admin username: " UNIFI_USER
    if [ "$UNIFI_USER" = "SKIP" ] || [ "$UNIFI_USER" = "skip" ]; then
      c_warn "Skipped API backup on request."
      break
    fi
    if [ -z "$UNIFI_USER" ]; then
      c_warn "Empty username ignored. Enter a local admin or type SKIP."
      continue
    fi
    read -rsp "  Password: " UNIFI_PASS; echo
    printf '{"username":"%s","password":"%s","remember":false,"strict":true}' "$(json_esc "$UNIFI_USER")" "$(json_esc "$UNIFI_PASS")" \
      | curl -ks --max-time 60 -c "$COOKIE" -b "$COOKIE" -D "$HDRS" -H 'Content-Type: application/json' -d @- "$CTRL_URL/api/login" -o "$RESP"
    unset UNIFI_PASS
    LOGIN_OK=0
    grep -q '"rc":"ok"' "$RESP" 2>/dev/null && LOGIN_OK=1
    grep -qi unifises "$COOKIE" 2>/dev/null && LOGIN_OK=1
    [ "$LOGIN_OK" = 1 ] && break
    c_warn "Login failed ($_try/3). SSO accounts will always fail."
  done
  if [ "$LOGIN_OK" = 1 ]; then
    CSRF=$(grep -i '^x-csrf-token:' "$HDRS" | awk '{print $2}' | tr -d '\r' | tail -1)
    c_ok "Logged in — taking settings-only and full backups"
    fetch_backup(){
      local days="$1" dest="$2" dl
      curl -ks --max-time 1800 -c "$COOKIE" -b "$COOKIE" -H 'Content-Type: application/json' ${CSRF:+-H "X-Csrf-Token: $CSRF"} \
        -d "{\"cmd\":\"backup\",\"days\":$days}" "$CTRL_URL/api/s/default/cmd/backup" -o "$RESP"
      dl=$(grep -oE '/dl/[^"]+\.unf' "$RESP" | head -1)
      [ -n "$dl" ] || { c_warn "backup cmd days=$days produced no download URL"; return 1; }
      curl -ks --max-time 1800 -b "$COOKIE" "$CTRL_URL$dl" -o "$dest"
      unf_ok "$dest"
    }
    fetch_backup 0 "$MIG_DIR/unifi-settings-$STAMP.unf" && SETTINGS_BACKUP="$MIG_DIR/unifi-settings-$STAMP.unf" && c_ok "Settings backup $(stat -c %s "$SETTINGS_BACKUP") bytes"
    if [ "$BACKUP_DAYS" != 0 ]; then
      fetch_backup -1 "$MIG_DIR/unifi-full-$STAMP.unf" && API_BACKUP="$MIG_DIR/unifi-full-$STAMP.unf" && c_ok "Full backup $(stat -c %s "$API_BACKUP") bytes"
    fi
    if [ "${PREFER_SETTINGS_RESTORE:-0}" = 1 ] && [ -n "$SETTINGS_BACKUP" ]; then
      API_BACKUP="$SETTINGS_BACKUP"
      c_info "Low RAM: restore file set to settings-only"
    fi
    [ -z "$API_BACKUP" ] && API_BACKUP="$SETTINGS_BACKUP"
    [ -n "$API_BACKUP" ] && ln -sfn "$API_BACKUP" "$MIG_ROOT/latest.unf" && c_ok "latest.unf -> $API_BACKUP"
    curl -ks -b "$COOKIE" -X POST "$CTRL_URL/api/logout" -o /dev/null
  fi
fi
if [ -z "$API_BACKUP" ]; then
  API_BACKUP=$(newest_autobackup)
  [ -n "$API_BACKUP" ] && c_warn "No API backup — newest on-disk file is $API_BACKUP"
fi
require_fresh_backup "${API_BACKUP:-}"

hr "Step 2 — Pull"
need_pull(){ [ "$RESUME" = 1 ] || return 0; image_present "$1" && return 1; return 0; }
need_pull "$NEW_IMAGE_PREFIX:$UNIFI_TAG" && sudo docker pull "$NEW_IMAGE_PREFIX:$UNIFI_TAG"
need_pull "docker.io/mongo:$MONGO_TAG" && sudo docker pull "docker.io/mongo:$MONGO_TAG"
require "linuxserver image" image_present "$NEW_IMAGE_PREFIX:$UNIFI_TAG"
require "mongo image" image_present "docker.io/mongo:$MONGO_TAG"
UNIFI_DIGEST=$(image_digest "$NEW_IMAGE_PREFIX:$UNIFI_TAG")
UNIFI_IMAGE_REF="$NEW_IMAGE_PREFIX:$UNIFI_TAG"
case "$UNIFI_DIGEST" in *@sha256:*) UNIFI_IMAGE_REF="$UNIFI_DIGEST" ;; esac
MONGO_IMAGE_REF="docker.io/mongo:$MONGO_TAG"

hr "Step 3 — Compose"
if [ -f "$ENV_FILE" ]; then load_env; c_info "Reusing $ENV_FILE"; else MONGO_ROOT_PASS=$(randpw); MONGO_PASS=$(randpw); fi
umask 077
printf 'MONGO_ROOT_PASS=%s\nMONGO_PASS=%s\nMONGO_TAG=%s\nUNIFI_TAG=%s\n' "$MONGO_ROOT_PASS" "$MONGO_PASS" "$MONGO_TAG" "$UNIFI_TAG" > "$ENV_FILE"
sync_dotenv
sudo mkdir -p "$APP_DATA" "$DB_DATA"
sudo chown "$PUID:$PGID" "$APP_DATA"
[ -f "$COMPOSE_DIR/docker-compose.yaml.jacobalberty" ] || cp "$COMPOSE_FILE" "$COMPOSE_DIR/docker-compose.yaml.jacobalberty"
cat > "$INIT_SH" <<'EOF'
#!/bin/bash
if which mongosh >/dev/null 2>&1; then mongo_init_bin=mongosh; else mongo_init_bin=mongo; fi
"${mongo_init_bin}" <<EOJS
use ${MONGO_AUTHSOURCE}
db.auth("${MONGO_INITDB_ROOT_USERNAME}", "${MONGO_INITDB_ROOT_PASSWORD}")
db.createUser({user:"${MONGO_USER}",pwd:"${MONGO_PASS}",roles:["clusterMonitor",{db:"${MONGO_DBNAME}",role:"dbOwner"},{db:"${MONGO_DBNAME}_stat",role:"dbOwner"},{db:"${MONGO_DBNAME}_audit",role:"dbOwner"},{db:"${MONGO_DBNAME}_restore",role:"dbOwner"}]})
EOJS
EOF
chmod 644 "$INIT_SH"
cat > "$COMPOSE_FILE" <<EOF
version: "3"
services:
  unifi-db:
    container_name: unifi-db
    image: $MONGO_IMAGE_REF
    command: --wiredTigerCacheSizeGB 0.5
    environment:
      - MONGO_INITDB_ROOT_USERNAME=root
      - MONGO_INITDB_ROOT_PASSWORD=$MONGO_ROOT_PASS
      - MONGO_USER=unifi
      - MONGO_PASS=$MONGO_PASS
      - MONGO_DBNAME=unifi
      - MONGO_AUTHSOURCE=admin
    volumes:
      - $DB_DATA:/data/db
      - $INIT_SH:/docker-entrypoint-initdb.d/init-mongo.sh:ro
    restart: unless-stopped
    networks: [internal]
  unifi:
    container_name: unifi
    image: $UNIFI_IMAGE_REF
    depends_on: [unifi-db]
    environment:
      - PUID=$PUID
      - PGID=$PGID
      - TZ=$TZ_VAL
      - MONGO_USER=unifi
      - MONGO_PASS=$MONGO_PASS
      - MONGO_HOST=unifi-db
      - MONGO_PORT=27017
      - MONGO_DBNAME=unifi
      - MONGO_AUTHSOURCE=admin
      - MEM_LIMIT=1024
      - MEM_STARTUP=1024
    volumes: [ "$APP_DATA:/config" ]
    restart: unless-stopped
    networks:
      default:
        ipv4_address: $CTRL_IP
      internal: {}
networks:
  default:
    driver: bridge
    ipam: { config: [ { subnet: $SUBNET } ] }
  internal:
    driver: bridge
    internal: true
EOF
chmod 600 "$COMPOSE_FILE"
dc config >/dev/null 2>"$MIG_DIR/compose-validate.log" || { cat "$MIG_DIR/compose-validate.log"; cp "$COMPOSE_DIR/docker-compose.yaml.jacobalberty" "$COMPOSE_FILE"; die "compose invalid"; }
c_ok "Compose validates"
cat > "$COMPOSE_DIR/rollback.sh" <<EOF
#!/bin/bash
set -u; cd $COMPOSE_DIR || exit 1
sudo docker rm -f unifi unifi-db 2>/dev/null || true
sudo docker network rm unifi_internal 2>/dev/null || true
cp docker-compose.yaml.jacobalberty docker-compose.yaml
$DC up -d
echo "Old UI $CTRL_URL"
EOF
chmod +x "$COMPOSE_DIR/rollback.sh"
cat > "$COMPOSE_DIR/unifi-update.sh" <<EOF
#!/bin/bash
set -u; cd $COMPOSE_DIR || exit 1
[ "\${1:-}" = "--i-have-a-backup" ] || { echo "Take a .unf then $0 --i-have-a-backup"; exit 2; }
$DC pull unifi && $DC up -d
EOF
chmod +x "$COMPOSE_DIR/unifi-update.sh"
cat > "$COMPOSE_DIR/unifi-status.sh" <<EOF
#!/bin/bash
sudo docker ps -a --filter name=unifi
curl -ks -o /dev/null -w "UI %{http_code}\\n" $CTRL_URL/
df -h /data /var/lib/docker
sudo du -sh $APP_DATA $DB_DATA $OLD_DATA 2>/dev/null
EOF
chmod +x "$COMPOSE_DIR/unifi-status.sh"
cat > "$COMPOSE_DIR/unifi-restore.sh" <<'EOF'
#!/bin/bash
set -u
FILE="${1:-}"; [ -f "$FILE" ] || { echo "Usage: $0 FILE.unf"; exit 2; }
sudo docker exec unifi mkdir -p /config/data/backup 2>/dev/null || true
sudo docker cp "$FILE" unifi:/config/data/backup/migrate-restore.unf || exit 1
curl -ks --max-time 180 -F "file=@${FILE};type=application/octet-stream" -F cmd=restore https://172.16.1.2:8443/api/upload/backup || true
echo "If wizard remains, upload in the browser."
EOF
chmod +x "$COMPOSE_DIR/unifi-restore.sh"
require "rollback.sh" test -x "$COMPOSE_DIR/rollback.sh"
require "old data" test -d "$OLD_DATA"

hr "Step 4 — Warm Mongo"
MONGO_SH=mongo
case "$MONGO_MAJOR" in ''|*[!0-9]*) ;; *) [ "$MONGO_MAJOR" -ge 6 ] && MONGO_SH=mongosh ;; esac
sudo docker rm -f unifi-db >/dev/null 2>&1 || true
sudo docker network inspect unifi_internal >/dev/null 2>&1 || sudo docker network create --driver bridge --internal unifi_internal >/dev/null
sudo docker run -d --name unifi-db --network unifi_internal --restart no \
  -e MONGO_INITDB_ROOT_USERNAME=root -e MONGO_INITDB_ROOT_PASSWORD="$MONGO_ROOT_PASS" \
  -e MONGO_USER=unifi -e MONGO_PASS="$MONGO_PASS" -e MONGO_DBNAME=unifi -e MONGO_AUTHSOURCE=admin \
  -v "$DB_DATA:/data/db" -v "$INIT_SH:/docker-entrypoint-initdb.d/init-mongo.sh:ro" \
  docker.io/mongo:$MONGO_TAG --wiredTigerCacheSizeGB 0.5 >/dev/null || die "warmup failed"
echo -n "  Waiting for Mongo"
for i in $(seq 1 90); do
  sleep 2; echo -n "."
  mongo_auth_ping "$MONGO_SH" && { echo; c_ok "Mongo warmed"; break; }
  [ "$i" = 90 ] && { echo; sudo docker rm -f unifi-db >/dev/null; die "warmup timeout"; }
done
sudo docker stop unifi-db >/dev/null; sudo docker rm unifi-db >/dev/null
require "warmup gone" container_absent unifi-db

hr "Step 5 — Stop old"
confirm "Stop the old container now?"
systemctl is-active --quiet docker-compose@unifi 2>/dev/null && sudo systemctl stop docker-compose@unifi && sleep 2
if sudo docker inspect unifi >/dev/null 2>&1; then
  sudo docker update --restart=no unifi >/dev/null 2>&1 || true
  sudo docker stop unifi >/dev/null && sudo docker rm unifi >/dev/null
  c_ok "Old container removed"
fi
CUTOVER_DONE=1
require "old gone" container_absent unifi

hr "Step 6 — Start new"
dc up -d || die "compose up failed"
require "unifi up" container_running unifi
require "db up" container_running unifi-db
ensure_routes
echo -n "  Re-checking MongoDB"
ok=0
for i in $(seq 1 30); do
  sleep 2; echo -n "."
  if mongo_auth_ping "$MONGO_SH"; then echo; c_ok "MongoDB ready"; ok=1; break; fi
done
[ "$ok" = 1 ] || { echo; sudo docker logs --tail 40 unifi-db; die "mongo auth failed after 60s"; }
wait_for_ui "first start" 150 || die "UI down"
require "UI" ui_up
inform_up && c_ok "inform :8080 answering (curl 400 is normal)" || c_warn "inform not up yet"
[ -f "$OLD_UPDATER" ] && mv "$OLD_UPDATER" "${OLD_UPDATER}.jacobalberty-disabled" 2>/dev/null || true
sudo systemctl start docker-compose@unifi 2>/dev/null || true

hr "Done"
echo "  Open $CTRL_URL and Restore from backup"
echo "  File: ${API_BACKUP:-$OLD_DATA/data/backup/autobackup}"
echo "  rollback: $COMPOSE_DIR/rollback.sh"
