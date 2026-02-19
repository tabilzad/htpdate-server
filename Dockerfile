FROM alpine:3.21

LABEL org.opencontainers.image.title="htpdate-server" \
      org.opencontainers.image.description="NTP server synced via HTTPS — bypass UDP/123 blocks" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/tabilzad/htpdate-server"

# hadolint ignore=DL3018
RUN apk add --no-cache \
    chrony=4.6.1-r0 \
    htpdate=2.0.0-r0 \
    tzdata=2025c-r0 \
 && apk upgrade --no-cache

COPY chrony.conf /etc/chrony/chrony.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 123/udp

HEALTHCHECK --interval=60s --timeout=5s --start-period=30s --retries=3 \
    CMD chronyc tracking || exit 1

ENTRYPOINT ["/entrypoint.sh"]
