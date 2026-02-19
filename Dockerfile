FROM alpine:3.21

LABEL org.opencontainers.image.title="htpdate-server" \
      org.opencontainers.image.description="NTP server synced via HTTPS — bypass UDP/123 blocks" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/tabilzad/htpdate-server"

RUN apk add --no-cache \
    chrony \
    htpdate \
    tzdata

COPY chrony.conf /etc/chrony/chrony.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 123/udp

HEALTHCHECK --interval=60s --timeout=5s --start-period=30s --retries=3 \
    CMD chronyc tracking || exit 1

ENTRYPOINT ["/entrypoint.sh"]
