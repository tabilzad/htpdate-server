#!/bin/sh
set -e

# ---------------------------------------------------------------------------
# Configuration (override via environment variables)
# ---------------------------------------------------------------------------
HTTPS_SERVERS="${HTTPS_SERVERS:-www.google.com www.cloudflare.com www.apple.com www.microsoft.com}"
SYNC_INTERVAL="${SYNC_INTERVAL:-60}"   # seconds between HTTPS time syncs

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[https-ntp] $(date -u '+%Y-%m-%d %H:%M:%S UTC') $*"; }

# Parse an HTTP Date header (RFC 7231) into a format busybox date accepts.
#   Input:  "Thu, 15 Feb 2024 12:34:56 GMT"
#   Output: "2024-02-15 12:34:56"
parse_http_date() {
    local input="$1"
    local day month_name year time mon

    day=$(echo "$input"  | awk '{print $2}')
    month_name=$(echo "$input" | awk '{print $3}')
    year=$(echo "$input" | awk '{print $4}')
    time=$(echo "$input" | awk '{print $5}')

    case "$month_name" in
        Jan) mon=01;; Feb) mon=02;; Mar) mon=03;; Apr) mon=04;;
        May) mon=05;; Jun) mon=06;; Jul) mon=07;; Aug) mon=08;;
        Sep) mon=09;; Oct) mon=10;; Nov) mon=11;; Dec) mon=12;;
        *)   return 1;;
    esac

    echo "${year}-${mon}-${day} ${time}"
}

# Attempt to sync from a single HTTPS server.
sync_from_server() {
    local server="$1"
    local date_header parsed

    date_header=$(curl -sI --connect-timeout 5 --max-time 10 "https://$server" 2>/dev/null \
        | grep -i '^[Dd]ate:' \
        | sed 's/^[Dd]ate: *//;s/\r$//')

    [ -z "$date_header" ] && return 1

    parsed=$(parse_http_date "$date_header") || return 1

    date -u -s "$parsed" >/dev/null 2>&1
    return 0
}

# Try every configured server; succeed on the first one that responds.
do_sync() {
    for server in $HTTPS_SERVERS; do
        if sync_from_server "$server"; then
            log "Synced from $server -> $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
            return 0
        else
            log "Failed: $server"
        fi
    done
    log "WARNING: all HTTPS time sources failed"
    return 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
mkdir -p /var/lib/chrony /var/log/chrony /run/chrony

# 1. Initial time sync (best-effort)
log "Initial time sync from: $HTTPS_SERVERS"
do_sync || log "Continuing with unsynchronized clock"

# 2. Start chrony NTP server (foreground via -d)
log "Starting chrony NTP server on UDP/123 ..."
chronyd -d -f /etc/chrony/chrony.conf &
CHRONY_PID=$!

# 3. Graceful shutdown on SIGTERM / SIGINT
cleanup() {
    log "Shutting down ..."
    kill "$CHRONY_PID" 2>/dev/null
    wait "$CHRONY_PID" 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT

# 4. Periodic HTTPS time sync loop
log "Periodic sync every ${SYNC_INTERVAL}s"
while true; do
    sleep "$SYNC_INTERVAL" &
    wait $!                       # interruptible by signals
    do_sync || true
done
