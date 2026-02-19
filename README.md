# htpdate-server

[![Build & Publish](https://github.com/tabilzad/htpdate-server/actions/workflows/publish.yml/badge.svg)](https://github.com/tabilzad/htpdate-server/actions/workflows/publish.yml)
[![Docker Image Version](https://img.shields.io/docker/v/tabilzad/htpdate-server?sort=semver)](https://hub.docker.com/r/tabilzad/htpdate-server)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A lightweight Docker container that **serves real NTP on your LAN** while syncing time over **HTTPS** — bypassing ISPs
that block UDP/123.

```
Internet (TCP/443 — not blocked)        LAN (UDP/123)
─────────────────────────────────       ──────────────────
  www.google.com ─┐                       ┌─ desktop
  www.cloudflare.com ─┤  ┌─────────────┐  ├─ laptop
  www.apple.com ──────┤──│ htpdate │ chrony │──┤  server
  www.microsoft.com ──┘  └─────────────┘  └─ raspberry pi
                    HTTPS Date headers       NTP responses
```

## Quick start

```sh
docker run -d \
  --name htpdate-server \
  --restart unless-stopped \
  --cap-add SYS_TIME \
  -p 123:123/udp \
  tabilzad/htpdate-server:latest
```

Or with Docker Compose:

```sh
docker compose up -d
```

Then point your LAN clients at the Docker host:

```conf
# /etc/chrony/chrony.conf (on each client)
server <docker-host-ip> iburst
```

## How it works

| Component                                     | Role                                                                                                                                                  |
|-----------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------|
| [htpdate](https://github.com/twekkel/htpdate) | Fetches `Date:` headers from HTTPS servers and disciplines the system clock — step on first poll, slew thereafter, with frequency drift compensation. |
| [chrony](https://chrony-project.org/)         | Serves the synced system clock as a stratum-3 NTP source on UDP/123.                                                                                  |

The container requires the **`SYS_TIME`** capability so it can adjust the system clock.

## Configuration

All settings are passed as environment variables:

| Variable        | Default                                                             | Description                                             |
|-----------------|---------------------------------------------------------------------|---------------------------------------------------------|
| `HTTPS_SERVERS` | `www.google.com www.cloudflare.com www.apple.com www.microsoft.com` | Space-separated list of HTTPS hosts to fetch time from. |
| `MIN_POLL`      | `900`                                                               | Minimum polling interval in seconds (15 min).           |
| `MAX_POLL`      | `3600`                                                              | Maximum polling interval in seconds (1 hour).           |
| `TZ`            | `UTC`                                                               | Container timezone.                                     |

Example with custom servers and faster polling:

```sh
docker run -d \
  --name htpdate-server \
  --cap-add SYS_TIME \
  -p 123:123/udp \
  -e "HTTPS_SERVERS=time.cloudflare.com www.google.com" \
  -e MIN_POLL=300 \
  tabilzad/htpdate-server:latest
```

## Verifying

From the Docker host:

```sh
# Check htpdate + chrony status inside the container
docker exec htpdate-server chronyc tracking

# Query NTP from a LAN machine
chronyc sources          # if pointed at this server
ntpdate -q <docker-host-ip>
```

## Building locally

```sh
docker compose build
docker compose up -d
```


## License

[MIT](LICENSE)
