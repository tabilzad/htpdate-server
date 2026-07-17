#!/bin/sh
set -e

# ---------------------------------------------------------------------------
# Configuration (override via environment variables)
# ---------------------------------------------------------------------------
# NOTE: use https:// URLs — htpdate polls bare hostnames over plain HTTP :80.
HTTPS_SERVERS="${HTTPS_SERVERS:-https://www.google.com https://www.apple.com https://www.fastly.com https://www.amazon.com}"
MIN_POLL="${MIN_POLL:-900}"      # minimum polling interval in seconds (default 15 min)
MAX_POLL="${MAX_POLL:-3600}"     # maximum polling interval in seconds (default 1 hour)

DRIFT_FILE=/var/lib/htpdate/drift
# htpdate rewrites its drift file on every successful poll. If the file goes
# stale for this long, htpdate is assumed hung and the container exits so
# Docker's restart policy can recover it.
WATCHDOG_STALE="${WATCHDOG_STALE:-$(( MAX_POLL * 4 ))}"

log() { echo "[htpdate-server] $*"; }

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
mkdir -p /var/lib/htpdate /var/lib/chrony /var/log/chrony /run/chrony
# chronyd drops privileges to the chrony user and needs to write its run
# and log directories itself.
chown chrony:chrony /var/lib/chrony /var/log/chrony /run/chrony
chmod 750 /run/chrony

log "HTTPS servers: $HTTPS_SERVERS"
log "Poll interval: ${MIN_POLL}s – ${MAX_POLL}s"

# ---------------------------------------------------------------------------
# Start htpdate — HTTPS time sync daemon
#   -F  foreground (no fork, no pidfile) — required for Docker
#   -s  step on first poll, then auto-switch to slew
#   -x  compensate for clock frequency drift
#   -f  persist drift data across restarts
# ---------------------------------------------------------------------------
# shellcheck disable=SC2086  # HTTPS_SERVERS is intentionally word-split
htpdate -F -s -x \
    -f "$DRIFT_FILE" \
    -m "$MIN_POLL" \
    -M "$MAX_POLL" \
    $HTTPS_SERVERS &
HTPDATE_PID=$!
log "htpdate started (PID $HTPDATE_PID)"

# ---------------------------------------------------------------------------
# Start chrony — NTP server for LAN clients
#   -d  foreground (no detach)
# ---------------------------------------------------------------------------
chronyd -d -f /etc/chrony/chrony.conf &
CHRONY_PID=$!
log "chrony started (PID $CHRONY_PID) — serving NTP on UDP/123"

# ---------------------------------------------------------------------------
# Graceful shutdown (docker stop / ctrl-c) — exit 0 so a
# `restart: unless-stopped` policy leaves the container down.
# ---------------------------------------------------------------------------
cleanup() {
    log "Shutting down ..."
    kill "$HTPDATE_PID" "$CHRONY_PID" 2>/dev/null || true
    wait "$HTPDATE_PID" "$CHRONY_PID" 2>/dev/null || true
    exit 0
}
trap cleanup TERM INT

# ---------------------------------------------------------------------------
# Supervise both daemons. If either one exits — or htpdate is still alive
# but has stopped syncing (drift file no longer updated) — exit non-zero so
# Docker's restart policy brings the whole pair back up together.
# ---------------------------------------------------------------------------
START_TS="$(date +%s)"
FAILURE=""
while [ -z "$FAILURE" ]; do
    if ! kill -0 "$HTPDATE_PID" 2>/dev/null; then
        FAILURE="htpdate exited unexpectedly"
    elif ! kill -0 "$CHRONY_PID" 2>/dev/null; then
        FAILURE="chrony exited unexpectedly"
    else
        now="$(date +%s)"
        last="$(stat -c %Y "$DRIFT_FILE" 2>/dev/null || echo "$START_TS")"
        # Before htpdate's first drift update, measure from container start.
        [ "$last" -lt "$START_TS" ] && last="$START_TS"
        if [ $(( now - last )) -gt "$WATCHDOG_STALE" ]; then
            FAILURE="htpdate has not updated $DRIFT_FILE in ${WATCHDOG_STALE}s — assuming it is hung"
        else
            # Background sleep + wait so the TERM/INT trap fires immediately.
            sleep 30 &
            wait "$!" || true
        fi
    fi
done

log "$FAILURE — exiting so Docker can restart the container"
kill "$HTPDATE_PID" "$CHRONY_PID" 2>/dev/null || true
wait "$HTPDATE_PID" "$CHRONY_PID" 2>/dev/null || true
exit 1
