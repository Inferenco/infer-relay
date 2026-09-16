# Docker Deployment Guide

This guide covers running Infer Relay with `docker compose`.
For building from source without Docker, see [Build and Run (without
Docker)](#) in the README. For putting the relay behind a reverse proxy
with TLS, see [Reverse Proxy](reverse-proxy.md).

## Prerequisites

* Docker Engine ≥ 20.10
* Compose v2 plugin (`docker compose` CLI) — the legacy
  `docker-compose` Python script is not supported.

Verify with:

```console
$ docker compose version
Docker Compose version v2.x.x
```

## Quick Start

```console
$ docker compose up -d
$ docker compose logs -f relay
$ docker compose ps            # status should be "healthy"
```

The relay is now listening on `ws://localhost:8080`.  Connect with any
Nostr client (e.g. `noscl`).

## What `docker compose` Does

| Aspect | Detail |
|---|---|
| Build context | Repo root (`.`) — the `Dockerfile` and `Cargo.lock` are copied in |
| Image tag | `infer-relay:local` (built from local source) |
| Port mapping | `8080:8080` — container port 8080 to host port 8080 |
| Named volume | `relay-data` mounted at `/usr/src/app/db` (see [Volume Strategy](#volume-strategy)) |
| Healthcheck | `curl --fail http://127.0.0.1:8080/metrics` every 30s, 3 retries |
| Log driver | `json-file` with `max-size: 10m`, `max-file: 3` (auto-rotated) |

## Volume Strategy

The compose file uses a **named volume** (`relay-data`) for the SQLite
database.  This is intentional: SQLite's WAL mode creates three files
(`nostr.db`, `nostr.db-wal`, `nostr.db-shm`) that must live together on
the same filesystem.  A named volume keeps them together across container
restarts without any host-side path management.

### Inspecting the Database

Shell into the container and run `sqlite3`:

```console
$ docker compose exec relay sqlite3 /usr/src/app/db/nostr.db ".tables"
events          nostr_events  nostr_relay_info  nostr_user_relay

$ docker compose exec relay sqlite3 /usr/src/app/db/nostr.db "SELECT id, kind, content FROM nostr_events ORDER BY created_at DESC LIMIT 5;"
```

### Backing Up the Database

```console
$ docker compose exec relay sqlite3 /usr/src/app/db/nostr.db ".backup '/usr/src/app/db/backup.db'"
$ docker compose cp relay:/usr/src/app/db/backup.db ./backup.db
```

### Switching to a Bind Mount

For host-side inspection or backup without `docker compose exec`, swap the
volume in `docker-compose.yml`:

```yaml
# Replace the named volume with a bind mount:
    volumes:
      - ./data:/usr/src/app/db
```

Then create the directory and ensure the container can write to it:

```console
$ mkdir -p ./data
$ docker compose up -d
```

## Logs

The relay logs to **stdout** via `tracing-subscriber` (fmt subscriber).
Override the filter at runtime with `RUST_LOG`:

```console
$ RUST_LOG=debug,infer_relay=trace docker compose up
```

Common filters:

| Filter | Effect |
|---|---|
| `RUST_LOG=info` | Default — startup, connection, and error messages only |
| `RUST_LOG=debug` | Per-connection logging (expensive) |
| `RUST_LOG=warn,infer_relay=info` | Suppress relay chatter, keep startup |

Tail recent logs:

```console
$ docker compose logs --tail=200 -f relay
```

## First-boot log output

On a fresh `docker compose up -d`, the relay uses its built-in defaults
silently when no `config.toml` is mounted.  The first line in
`docker compose logs relay` should be the structured tracing-prefixed
`Starting up from main` info line — there is no preceding "Error reading
config file" warning.

A healthy boot looks like this:

```
infer-relay  | [ts]  INFO infer_relay: Starting up from main
infer-relay  | [ts]  INFO infer_relay::server: listening on: 0.0.0.0:8080
infer-relay  | [ts]  INFO infer_relay::repo::sqlite: Built a connection pool "writer" (min=0, max=2)
infer-relay  | [ts]  INFO infer_relay::repo::sqlite: Built a connection pool "maintenance" (min=0, max=2)
infer-relay  | [ts]  INFO infer_relay::repo::sqlite: Built a connection pool "reader" (min=4, max=8)
infer-relay  | [ts]  INFO infer_relay::repo::sqlite_migration: DB version = 18
```

If you see `Error reading config file` on boot, it means a `config.toml`
is mounted but failed to parse (typically a syntax error or unknown TOML
key).  The relay will still start using defaults, but your custom
configuration is not being applied.  See the [Troubleshooting](#troubleshooting)
section below for how to fix it.

A real parse error (e.g. a typo in `config.toml`) prints exactly one
softer line:

```
Warning: could not parse config.toml (...); using built-in defaults.
```

This is informational — the relay still functions correctly.  See the
[Custom `config.toml`](#custom-configtoml) section for how to mount a real
one.

## Healthcheck

The healthcheck probes `http://127.0.0.1:8080/metrics` — a plain-text
Prometheus metrics endpoint that always returns 200 OK with no redirect
and no authentication.  This is more reliable than `/` when
pay-to-relay is enabled (which returns a 307 redirect for unauthenticated
requests).

## Custom `config.toml`

To override the relay's listening address, port, rate limits, or other
settings, bind-mount your config file:

```yaml
    volumes:
      - ./config.toml:/usr/src/app/config.toml:ro
      - relay-data:/usr/src/app/db
```

Then edit `./config.toml` on the host and restart:

```console
$ docker compose restart
```

## Graceful Shutdown

The relay handles `SIGTERM` gracefully — it stops accepting new
connections and finishes draining in-flight subscriptions before
terminating.  Use `docker compose stop` (sends SIGTERM) rather than
`docker compose kill` (SIGKILL) for clean shutdowns:

```console
$ docker compose stop    # clean shutdown
$ docker compose down    # stop + remove containers
```

## Troubleshooting

### Container is "unhealthy"

```console
$ docker compose logs relay
$ docker compose exec relay curl -v http://127.0.0.1:8080/metrics
```

If the healthcheck curl fails, the relay may still be starting up
(SQLite migration, DB init).  Wait for `start_period` (30s) to elapse
or check `docker compose logs relay` for errors.

### Build fails on crates.io rate limit

```console
# Retry with backoff:
$ docker compose build --no-cache

# Or pull deps first:
$ docker compose build --no-cache && docker compose up
```

### Permission denied on volume

If you switched to a bind mount and get "Permission denied", the host
directory likely has the wrong ownership.  The relay runs as `appuser`
(uid 1000) inside the container:

```console
$ sudo chown 1000:1000 ./data
$ docker compose up -d
```

### Port already in use

Change the host port in `docker-compose.yml`:

```yaml
    ports:
      - "8081:8080"
```

Or stop the conflicting container:

```console
$ docker stop nostr-relay   # or whatever the container is named
$ docker compose up -d
```

### Seeing "Error reading config file" on boot

If you see this line in `docker compose logs relay`, it means a
`config.toml` exists in the container's working directory but could not
be parsed (typically a syntax error or unknown TOML key).  The relay
will still start using defaults, but your custom configuration is not
being applied.

Fix the file or remove it from the bind mount:

```console
$ docker compose exec relay ls -la /usr/src/app/config.toml
$ docker compose exec relay cat /usr/src/app/config.toml    # inspect
$ docker compose restart relay
```

If you deliberately want to run with defaults, simply remove the bind
mount from `docker-compose.yml`.

## Out of Scope

This guide covers the Docker Compose setup only.  The following are
documented elsewhere:

* **Reverse proxy + TLS**: see [Reverse Proxy](reverse-proxy.md)
* **PostgreSQL backend**: see `config.toml` or the [database maintenance](database-maintenance.md) guide
* **CLN/LND sidecar**: not included in this compose file
