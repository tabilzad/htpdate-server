#!/bin/sh
set -e

# ---------------------------------------------------------------------------
# Configuration (override via environment variables)
# ---------------------------------------------------------------------------
HTTPS_SERVERS="${HTTPS_SERVERS:-www.google.com www.cloudflare.com www.apple.com www.microsoft.com}"
MIN_POLL="${MIN_POLL:-900}"      # minimum polling interval in seconds (default 15 min)
MAX_POLL="${MAX_POLL:-3600}"     # maximum polling interval in seconds (default 1 hour)

log() { echo "[htpdate-server] $*"; }

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
mkdir -p /var/lib/htpdate /var/lib/chrony /var/log/chrony /run/chrony

log "HTTPS servers: $HTTPS_SERVERS"
log "Poll interval: ${MIN_POLL}s – ${MAX_POLL}s"

# ---------------------------------------------------------------------------
# Start htpdate — HTTPS time sync daemon
#   -F  foreground (no fork, no pidfile) — required for Docker
#   -s  step on first poll, then auto-switch to slew
#   -x  compensate for clock frequency drift
#   -f  persist drift data across restarts
# ---------------------------------------------------------------------------
htpdate -F -s -x \
    -f /var/lib/htpdate/drift \
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
# Graceful shutdown
# ---------------------------------------------------------------------------
cleanup() {
    log "Shutting down ..."
    kill "$HTPDATE_PID" "$CHRONY_PID" 2>/dev/null
    wait "$HTPDATE_PID" "$CHRONY_PID" 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT

# Wait for children; if either exits the container stops and
# Docker's restart policy takes over.
wait
cleanup
