FROM alpine:3.21

RUN apk add --no-cache \
    chrony \
    curl \
    tzdata

COPY chrony.conf /etc/chrony/chrony.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 123/udp

HEALTHCHECK --interval=60s --timeout=5s --start-period=30s --retries=3 \
    CMD chronyc tracking || exit 1

ENTRYPOINT ["/entrypoint.sh"]
