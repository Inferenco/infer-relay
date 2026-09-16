# Infer Relay

Infer Relay is a [Nostr](https://github.com/nostr-protocol/nostr) relay server
written in Rust. It implements the full Nostr relay protocol, persists data to
SQLite, and is designed to be deployed standalone or behind a reverse proxy
for TLS termination.

[![CI](https://github.com/Inferenco/infer-relay/actions/workflows/ci.yml/badge.svg)](https://github.com/Inferenco/infer-relay/actions/workflows/ci.yml)

## Features

[NIPs](https://github.com/nostr-protocol/nips) with a relay-specific implementation:

- [x] NIP-01: [Basic protocol flow description](https://github.com/nostr-protocol/nips/blob/master/01.md)
- [x] NIP-02: [Contact List and Petnames](https://github.com/nostr-protocol/nips/blob/master/02.md)
- [ ] NIP-03: [OpenTimestamps Attestations for Events](https://github.com/nostr-protocol/nips/blob/master/03.md)
- [x] NIP-05: [Mapping Nostr keys to DNS-based internet identifiers](https://github.com/nostr-protocol/nips/blob/master/05.md)
- [x] NIP-09: [Event Deletion](https://github.com/nostr-protocol/nips/blob/master/09.md)
- [x] NIP-11: [Relay Information Document](https://github.com/nostr-protocol/nips/blob/master/11.md)
- [x] NIP-12: [Generic Tag Queries](https://github.com/nostr-protocol/nips/blob/master/12.md)
- [x] NIP-15: [End of Stored Events Notice](https://github.com/nostr-protocol/nips/blob/master/15.md)
- [x] NIP-16: [Event Treatment](https://github.com/nostr-protocol/nips/blob/master/16.md)
- [x] NIP-20: [Command Results](https://github.com/nostr-protocol/nips/blob/master/20.md)
- [x] NIP-22: [Event `created_at` limits](https://github.com/nostr-protocol/nips/blob/master/22.md) (_future-dated events only_)
- [ ] NIP-26: [Event Delegation](https://github.com/nostr-protocol/nips/blob/master/26.md) (_implemented, but currently disabled_)
- [x] NIP-28: [Public Chat](https://github.com/nostr-protocol/nips/blob/master/28.md)
- [x] NIP-33: [Parameterized Replaceable Events](https://github.com/nostr-protocol/nips/blob/master/33.md)
- [x] NIP-40: [Expiration Timestamp](https://github.com/nostr-protocol/nips/blob/master/40.md)
- [x] NIP-42: [Authentication of clients to relays](https://github.com/nostr-protocol/nips/blob/master/42.md)
- [x] NIP-91: [AND operator for filters](https://github.com/nostr-protocol/nips/pull/1365)

## Quick Start

```console
$ git clone https://github.com/Inferenco/infer-relay
$ cd infer-relay
$ cp config.toml.example config.toml
$ docker compose up -d --build
$ docker compose logs -f relay
```

The relay is now listening on `ws://localhost:8080`. Connect with any Nostr
client (e.g. [`noscl`](https://github.com/fiatjaf/noscl)).

## Build and Run (without Docker)

Building `infer-relay` requires an installation of Cargo & Rust:
https://www.rust-lang.org/tools/install

System packages (Debian/Ubuntu):

```console
$ sudo apt-get install -y build-essential cmake protobuf-compiler pkg-config libssl-dev
```

Clone and build:

```console
$ git clone https://github.com/Inferenco/infer-relay
$ cd infer-relay
$ cargo build -r
```

The relay binary is at `target/release/infer-relay`. Run with logging:

```console
$ RUST_LOG=info,infer_relay=info ./target/release/infer-relay
```

## Configuration

All settings live in `config.toml.example` at the repo root — copy it to
`config.toml` (which is `.gitignore`'d) and edit. The file documents every
section: `[info]`, `[diagnostics]`, `[database]`, `[logging]`, `[grpc]`,
`[network]`, `[options]`, `[limits]`, `[authorization]`, `[verified_users]`,
and `[pay_to_relay]`.

For Docker, mount it into the container:

```console
$ docker compose up -d --build
```

The compose file already bind-mounts `./config.toml` and persists the SQLite
database. See [Docker Deployment](docs/docker.md) for details.

## Deployment

- **Docker Compose** — see [Docker Deployment](docs/docker.md).
- **Production hardening (nginx + certbot)** — see
  [Production Deployment with nginx + certbot](docs/docker-production.md).
- **Reverse proxy (HAProxy, nginx, Traefik)** — see
  [Reverse Proxy Setup](docs/reverse-proxy.md).
- **Systemd unit on a Linux host** — see
  [Run as a Linux system process](docs/run-as-linux-system-process.md).

## Docs

Documentation lives in [`docs/`](docs/):

**Deployment**

- [Docker Deployment](docs/docker.md) — quickstart with `docker compose`.
- [Production Deployment with nginx + certbot](docs/docker-production.md) —
  full guide for a single-host production deployment with TLS via Let's
  Encrypt.
- [Reverse Proxy Setup](docs/reverse-proxy.md) — HAProxy, nginx, and Traefik
  examples for TLS termination.

**Operation**

- [Database Maintenance](docs/database-maintenance.md) — backing up,
  vacuuming, and pruning the SQLite store.
- [Run as a Linux system process](docs/run-as-linux-system-process.md) —
  systemd unit, no Docker.

**Features**

- [Pay to Relay](docs/pay-to-relay.md) — Lightning-paid admission and
  per-event posting via LNbits / Core Lightning.
- [Author Verification (NIP-05)](docs/user-verification-nip05.md) — design
  document for NIP-05-based author gating.
- [gRPC Extensions](docs/grpc-extensions.md) — design document for
  externalized event-admission decisions (nauthz).

## Community & Support

Join the Inferenco Telegram channel for development discussions, support, and
release announcements:

**https://t.me/inferenco**

## Contributing

Bug reports, feature requests, and pull requests are welcome on the
[GitHub issue tracker](https://github.com/Inferenco/infer-relay/issues).

## License

This project is MIT licensed.

Copyright © 2026 Inferenco.
