# Production Deployment with nginx + certbot

This guide walks an operator through deploying Infer Relay on a single Linux
host behind nginx, with Let's Encrypt TLS via certbot, fronted at a real
domain like `https://your-domain.example`. (Substitute your actual domain
wherever `your-domain.example` appears.)

If you only want to run the relay locally without TLS, see
[Docker Compose](docker.md) instead.

## Prerequisites

- Linux host (Debian 12 or Ubuntu 24.04 verified; other distros require
  equivalent package manager commands)
- Public IPv4 address with ports 80 and 443 inbound allowed
- DNS A record pointing your domain to that public IP (allow ~5 minutes
  for propagation before running certbot)
- Docker Engine ≥ 20.10 with the Compose v2 plugin (verify with
  `docker compose version`)
- Root or sudo access (for installing nginx/certbot and binding ports
  80/443)
- An SSH session to the host

## Architecture

```
Internet ──(TCP 80/443)──> nginx (host) ──(127.0.0.1:4000)──> relay (Docker)
                                       │
                                       └──> certbot renews cert, hook reloads nginx
```

- nginx runs on the host and binds ports 80 and 443
- the relay container exposes port 4000 on the host's loopback interface
  (nginx is the only thing that talks to it directly)
- certbot runs on the host (not in a container), writes certs to
  `/etc/letsencrypt/live/<domain>/`, and a deploy hook reloads nginx on
  every successful renewal
- TLS cert files and nginx config stay on the host filesystem — they are
  never baked into a container image

## Step 1 — DNS

Verify the A record points at your public IP:

```console
$ dig +short your-domain.example
203.0.113.10
```

If you see nothing or the wrong IP, fix the record at your registrar
before continuing. certbot's HTTP-01 challenge needs port 80 reachable
on the public IP.

## Step 2 — Install nginx and certbot on the host

Debian/Ubuntu (recommended):

```console
$ sudo apt update
$ sudo apt install -y nginx
$ sudo snap install --classic certbot
$ sudo ln -sf /snap/bin/certbot /usr/bin/certbot
```

Verify:

```console
$ nginx -v
nginx version: nginx/1.24.0
$ certbot --version
certbot 2.11.0
```

## Step 3 — Configure the relay

Clone the repository and edit `config.toml`. At minimum:

```toml
[info]
relay_url = "wss://your-domain.example/"

[network]
port = 4000
# Make the relay see real client IPs in its logs (not 127.0.0.1):
remote_ip_header = "x-forwarded-for"
```

Production hardening suggestions (opt-in):

```toml
[network]
# Keep the default 0.0.0.0 bind INSIDE the container: Docker's port
# mapping reaches the relay via the container's bridge IP, so binding
# to 127.0.0.1 here makes it unreachable from the host (nginx would
# get 502). Restrict exposure on the HOST side instead, with the
# docker-compose port mapping `127.0.0.1:4000:4000` (see Step 6).
# address = "0.0.0.0"   # the default — do not set this to 127.0.0.1

[limits]
# Cap per-IP inbound traffic. Defaults are unlimited.
messages_per_sec = 5
subscriptions_per_min = 10

[options]
reject_future_seconds = 1800   # reject events more than 30 min in the future
```

See `config.toml` for the full list of options.

## Step 4 — Deploy with docker compose

```console
$ cd /path/to/infer-relay
$ docker compose up -d --build
$ docker compose ps              # status should be "healthy" after ~30s
$ docker compose logs --tail=50 relay
```

The compose file already bind-mounts `./config.toml` and persists the
SQLite database in a named volume. For details, see
[Docker Compose](docker.md).

## Step 5 — Verify the relay is listening locally

```console
$ curl -s http://127.0.0.1:4000/ -H 'Accept: application/nostr+json' | jq .
{
  "id": "wss://your-domain.example/",
  "name": "Infer Relay",
  "supported_nips": [1, 2, 9, 11, 12, 15, 16, 20, 22, 33, 40],
  ...
}

$ curl -sf http://127.0.0.1:4000/metrics | head -5
# HELP nostr_cmd_auth_total AUTH commands
# TYPE nostr_cmd_auth_total counter
nostr_cmd_auth_total 0
```

If `/metrics` returns Prometheus text and the NIP-11 JSON is valid, the
relay is healthy on the host loopback. Do **not** proceed to nginx until
this works. If either curl fails, see [Docker Compose](docker.md) →
"Troubleshooting".

## Step 6 — Configure nginx

The repository ships a drop-in site config at
`contrib/nginx/nostr-relay.conf`. Copy it to your sites-available
directory, substituting your domain name (the file uses
`your-domain.example` as a placeholder):

```console
$ sed 's/your-domain.example/your-actual-domain.example/g' \
      contrib/nginx/nostr-relay.conf \
      | sudo tee /etc/nginx/sites-available/your-actual-domain.example.conf
```

Enable the site and disable the default:

```console
$ sudo ln -s /etc/nginx/sites-available/your-actual-domain.example.conf \
             /etc/nginx/sites-enabled/
$ sudo rm -f /etc/nginx/sites-enabled/default
```

The config points at Let's Encrypt cert paths that do not exist yet,
and `nginx -t` refuses to load a missing certificate. Bootstrap a
throwaway self-signed cert at exactly those paths so nginx can start;
certbot replaces it with a trusted cert in Step 7:

```console
$ sudo mkdir -p /etc/letsencrypt/live/your-actual-domain.example
$ sudo openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
      -keyout /etc/letsencrypt/live/your-actual-domain.example/privkey.pem \
      -out    /etc/letsencrypt/live/your-actual-domain.example/fullchain.pem \
      -subj "/CN=your-actual-domain.example"
```

Validate and reload:

```console
$ sudo nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful

$ sudo systemctl reload nginx
```

At this stage `curl -sI http://your-actual-domain.example/` returns a
`301` redirect to HTTPS, and HTTPS serves the temporary self-signed
cert (browser warnings are expected until certbot replaces it in the
next step).

### Production hardening: bind the relay to localhost only

By default, the compose file exposes the relay on `0.0.0.0:4000` on the
host. For a single-host deployment behind nginx, tighten this to
`127.0.0.1:4000:4000` so the relay is reachable only from the host's
loopback:

```yaml
# docker-compose.yml
services:
  relay:
    ports:
      - "127.0.0.1:4000:4000"   # was: "4000:4000"
```

Then restart:

```console
$ docker compose up -d
```

## Step 7 — Obtain the TLS certificate

```console
$ sudo certbot --nginx -d your-actual-domain.example
```

certbot will:

1. Spin up a temporary HTTP listener (or use the webroot via the
   `/.well-known/acme-challenge/` location in your site config)
2. Run the ACME HTTP-01 challenge
3. Fetch the certificate from Let's Encrypt
4. Auto-modify `/etc/nginx/sites-enabled/your-actual-domain.example.conf`
   to point `ssl_certificate` and `ssl_certificate_key` at the new files

Cert files land at:

- `/etc/letsencrypt/live/your-actual-domain.example/fullchain.pem`
- `/etc/letsencrypt/live/your-actual-domain.example/privkey.pem`

The `--nginx` plugin also adds an HSTS header if it isn't already there.

If this is your first certbot run on this host, accept the email + ToS
prompts (or pass `--non-interactive --agree-tos -m you@example.com` to
script it).

## Step 8 — Verify HTTPS end-to-end

```console
$ curl -sI https://your-actual-domain.example/
HTTP/1.1 200 OK
server: nginx
...

$ curl -s https://your-actual-domain.example/ \
       -H 'Accept: application/nostr+json' | jq -r '.id'
wss://your-actual-domain.example/
```

WebSocket test (requires `wscat`, install with `npm i -g wscat`):

```console
$ wscat -c wss://your-actual-domain.example
Connected (press Ctrl+D to exit)
> ["REQ","test",{}]
< ["EOSE","test"]
```

You should see `Connected` and be able to send Nostr `REQ` messages.

## Step 9 — Set up automatic renewal

Certbot's systemd timer (`certbot.timer`) renews certs automatically,
but the post-renewal nginx reload needs a deploy hook. Install the
shipped hook:

```console
$ sudo install -m 755 contrib/certbot-renewal-hooks/reload-nginx.sh \
                   /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

Test the renewal pipeline (dry-run, no cert actually issued):

```console
$ sudo certbot renew --dry-run

Congratulations, all simulated renewals succeeded
```

After this, real renewals will trigger the hook, which reloads nginx to
pick up the new cert files. No further cron / systemd config required.

## Maintenance

### Backups

Daily SQLite backup using the `sqlite3 .backup` API (safe to run while
the relay is live):

```console
$ sudo mkdir -p /var/backups/nostr
$ sudo install -m 755 /dev/stdin /usr/local/bin/backup-nostr-db.sh <<'EOF'
#!/bin/sh
set -e
BACKUP=/var/backups/nostr/$(date +%Y%m%d_%H%M).db
cd /path/to/infer-relay
# NB: the .backup target is a path INSIDE the container (which runs as
# an unprivileged user), so use /tmp — host paths like /var/backups do
# not exist there.
docker compose exec -T relay sqlite3 /usr/src/app/db/nostr.db \
    ".backup '/tmp/nostr.db.tmp'"
docker compose cp relay:/tmp/nostr.db.tmp "${BACKUP}" \
    || docker compose cp relay:/usr/src/app/db/nostr.db "${BACKUP}"
bzip2 -9 "${BACKUP}"
# keep last 14 days
find /var/backups/nostr -name '*.db.bz2' -mtime +14 -delete
EOF
```

Schedule via cron or systemd timer. See
[Database Maintenance](database-maintenance.md) for vacuum and event
deletion commands.

### Log rotation

The compose file caps logs at 10 MB × 3 files via the `json-file`
driver. For long-term retention, forward `docker compose logs` to your
syslog / journald / log aggregator as desired.

### Updates

```console
$ cd /path/to/infer-relay
$ git pull
$ docker compose build --pull
$ docker compose up -d
$ docker compose logs --tail=20 relay   # verify a clean boot
```

`docker compose` only recreates the `relay` container if the image
changed; the named `relay-data` volume persists across deploys.

## Troubleshooting

### 502 Bad Gateway from nginx

nginx reaches the upstream but the relay refuses or times out. Check:

```console
$ sudo nginx -t                          # config syntax
$ sudo ss -tlnp | grep ':4000'           # relay listening on host
$ docker compose ps                      # container healthy?
$ docker compose logs --tail=50 relay    # relay-side errors
```

Most common cause: relay not yet listening because it is still applying
SQLite migrations on first boot. Wait 30 seconds and retry.

### certbot fails with "Connection refused" on port 80

Something else is bound to port 80 (often an existing nginx default
site, Apache, or a half-installed certbot standalone). Find it:

```console
$ sudo ss -tlnp | grep ':80'
```

Stop the conflicting service or finish the previous certbot attempt
(`sudo systemctl stop certbot`).

### WebSocket disconnects after 60 seconds

The default `proxy_read_timeout` of 60 seconds kills long-lived
WebSocket connections. The shipped nginx config sets
`proxy_read_timeout 3600s` — if you see 60-second disconnects, your
site config is being shadowed by a higher-priority `http {}` block:

```console
$ sudo nginx -T | grep proxy_read_timeout
```

### NIP-11 returns the wrong `id`

The `id` field is the URL the relay advertises. It comes from
`config.toml` `[info] relay_url`. If you see the wrong value:

```console
$ docker compose exec relay cat /usr/src/app/config.toml | grep relay_url
# If the bind-mount is wrong, the container won't see your edits:
$ docker compose restart relay
```

### Cert renewal silently failing

The systemd timer (`certbot.timer`) runs twice daily; check its status:

```console
$ sudo systemctl status certbot.timer
$ sudo journalctl -u certbot -n 50
```

If `certbot renew --dry-run` succeeds but the deploy hook never fires,
verify the hook is executable:

```console
$ sudo ls -l /etc/letsencrypt/renewal-hooks/deploy/
$ sudo cat /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

## Out of scope

This guide assumes a single-host docker-compose deployment with nginx
on the host and certbot on the host. The following are documented
elsewhere:

- **Traefik or HAProxy** instead of nginx — see [Reverse Proxy](reverse-proxy.md)
- **Systemd unit** (no Docker) — see `contrib/infer-relay.service` and
  [Running as a Linux system process](run-as-linux-system-process.md)
- **PostgreSQL backend** — see `config.toml` `[database]` and
  [Database Maintenance](database-maintenance.md)
- **Pay-to-relay (LNbits/CLN sidecar)** — see [Pay to Relay](pay-to-relay.md)
- **gRPC extensions (nauthz)** — see [gRPC Extensions](grpc-extensions.md)
