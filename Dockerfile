FROM alpine:3.23

LABEL org.opencontainers.image.title="htpdate-server" \
      org.opencontainers.image.description="NTP server synced via HTTPS — bypass UDP/123 blocks" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/tabilzad/htpdate-server"

# Fuzzy version pins: exact -rX pins break as soon as Alpine rebuilds a
# package, since old revisions are dropped from the repo index.
# hadolint ignore=DL3018
RUN apk add --no-cache \
    chrony~=4.8 \
    htpdate~=2.0.0 \
    tzdata \
 && apk upgrade --no-cache

COPY chrony.conf /etc/chrony/chrony.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 123/udp

HEALTHCHECK --interval=60s --timeout=5s --start-period=30s --retries=3 \
    CMD pgrep htpdate >/dev/null && chronyc tracking || exit 1

ENTRYPOINT ["/entrypoint.sh"]
