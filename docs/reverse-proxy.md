# Reverse Proxy Setup Guide

It is recommended to run `Infer Relay` behind a reverse proxy such
as `haproxy`, `nginx` or `traefik` to provide TLS termination.  Simple examples
for `haproxy`, `nginx` and `traefik` configurations are documented here.

## Minimal HAProxy Configuration

Assumptions:

* HAProxy version is `2.4.10` or greater (older versions not tested).
* Hostname for the relay is `your-domain.example`.
* Your relay should be available over wss://your-domain.example
* Your (NIP-11) relay info page should be available on https://your-domain.example
* SSL certificate is located in `/etc/certs/example.com.pem`.
* Relay is running on port 8080.
* Limit connections to 400 concurrent.
* HSTS (HTTP Strict Transport Security) is desired.
* Only TLS 1.2 or greater is allowed.

```
global
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options prefer-client-ciphers no-sslv3 no-tlsv10 no-tlsv11 no-tls-tickets

frontend fe_prod
    mode    http
    bind    :443 ssl crt /etc/certs/example.com.pem alpn h2,http/1.1
    bind    :80
    http-request set-header X-Forwarded-Proto https if { ssl_fc }
    redirect scheme https code 301 if !{ ssl_fc }
    acl host_relay hdr(host) -i -m beg your-domain.example
    use_backend relay if host_relay
    # HSTS (1 year)
    http-response set-header Strict-Transport-Security max-age=31536000

backend relay
    mode http
    timeout connect 5s
    timeout client 50s
    timeout server 50s
    timeout tunnel 1h
    timeout client-fin 30s
    option tcp-check
    default-server maxconn 400 check inter 20s fastinter 1s
    server relay 127.0.0.1:8080
```

### HAProxy Notes

You may experience WebSocket connection problems with Firefox if
HTTP/2 is enabled, for older versions of HAProxy (2.3.x).  Either
disable HTTP/2 (`h2`), or upgrade HAProxy.

## Bare-bones Nginx Configuration

Assumptions:

* `Nginx` version is `1.18.0` or newer (tested on 1.18, 1.22, 1.24).
* Hostname for the relay is `your-domain.example` (substitute your actual domain).
* SSL certificate and key are located at `/etc/letsencrypt/live/your-domain.example/`.
* Relay is running on port `4000` (set via `[network] port = 4000` in `config.toml`).
* For a full end-to-end production deployment (DNS, certbot, hardening), see
  [Production Deployment with nginx + certbot](docker-production.md).

```
http {
    # WebSocket upgrade helper (required for HTTP/1.1 -> WS upgrade on /).
    # `map` is only valid inside the `http` context.
    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }

    server {
        listen 443 ssl;
        listen [::]:443 ssl;
        # Optional; the `http2` directive requires nginx >= 1.25.1.
        # http2 on;
        server_name your-domain.example;

        ssl_certificate     /etc/letsencrypt/live/your-domain.example/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/your-domain.example/privkey.pem;
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers off;
        ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;

        ssl_session_cache   shared:SSL:10m;
        ssl_session_timeout 1d;
        ssl_session_tickets off;
        ssl_stapling        on;
        ssl_stapling_verify on;

        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options           "DENY"              always;
        add_header X-Content-Type-Options    "nosniff"           always;
        add_header Referrer-Policy           "no-referrer"       always;
        server_tokens off;

        location / {
            proxy_pass http://127.0.0.1:4000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade    $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Host              $host;
            proxy_set_header X-Real-IP         $remote_addr;
            proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            proxy_read_timeout    3600s;
            proxy_send_timeout    3600s;
            proxy_connect_timeout 5s;
            proxy_buffering          off;
            proxy_request_buffering  off;
            tcp_nodelay on;
        }
    }
}
```

### Nginx Notes

The above configuration was tested on `nginx` `1.18.0` on `Ubuntu` `20.04` and `22.04`

For help installing `nginx` on `Ubuntu`, see [this guide](https://www.digitalocean.com/community/tutorials/how-to-install-nginx-on-ubuntu-20-04).

For guidance on using `letsencrypt` to obtain a cert on `Ubuntu`, including an `nginx` plugin, see [this post](https://www.digitalocean.com/community/tutorials/how-to-secure-nginx-with-let-s-encrypt-on-ubuntu-20-04).


## Example Traefik Configuration

Assumptions:

* `Traefik` version is `2.9` (other versions not tested).
* `Traefik` is used for provisioning of Let's Encrypt certificates.
* `Traefik` is running in `Docker`, using `docker compose` and labels for the static configuration. An equivalent setup using a Traefik config file is possible too (but not covered here).
* Strict Transport Security is enabled.
* Hostname for the relay is `your-domain.example`, email address for ACME certificates provider is `name@example.com`.
* ipv6 is enabled, a viable private ipv6 subnet is specified in the example below.
* Relay is running on port `8080`.

```
version: '3'

networks:
  nostr:
    enable_ipv6: true
    ipam:
      config:
        - subnet: fd00:db8:a::/64
          gateway: fd00:db8:a::1

services:
  traefik:
    image: traefik:v2.9
    networks:
      nostr:
    command:
      - "--log.level=ERROR"
      # letsencrypt configuration
      - "--certificatesResolvers.http.acme.email==name@example.com"
      - "--certificatesResolvers.http.acme.storage=/certs/acme.json"
      - "--certificatesResolvers.http.acme.httpChallenge.entryPoint=http"
      # define entrypoints
      - "--entryPoints.http.address=:80"
      - "--entryPoints.http.http.redirections.entryPoint.to=https"
      - "--entryPoints.http.http.redirections.entryPoint.scheme=https"
      - "--entryPoints.https.address=:443"
      - "--entryPoints.https.forwardedHeaders.insecure=true"
      - "--entryPoints.https.proxyProtocol.insecure=true"
      # docker provider (get configuration from container labels)
      - "--providers.docker.endpoint=unix:///var/run/docker.sock"
      - "--providers.docker.exposedByDefault=false"
      - "--providers.file.directory=/config"
      - "--providers.file.watch=true"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "$(pwd)/traefik/certs:/certs"
      - "$(pwd)/traefik/config:/config"
    logging:
      driver: "local"
    restart: always

  # example nostr config. only labels: section is relevant for Traefik config
  nostr:
   image: infer-relay:latest
   container_name: nostr-relay
   networks:
     nostr:
   restart: always
   user: 100:100
   volumes:
   - '$(pwd)/nostr/data:/usr/src/app/db:Z'
   - '$(pwd)/nostr/config/config.toml:/usr/src/app/config.toml:ro,Z'
   labels:
     - "traefik.enable=true"
     - "traefik.http.routers.nostr.entrypoints=https"
     - "traefik.http.routers.nostr.rule=Host(`your-domain.example`)"
     - "traefik.http.routers.nostr.tls.certresolver=http"
     - "traefik.http.routers.nostr.service=nostr"
     - "traefik.http.services.nostr.loadbalancer.server.port=8080"
     - "traefik.http.services.nostr.loadbalancer.passHostHeader=true"
     - "traefik.http.middlewares.nostr.headers.sslredirect=true"
     - "traefik.http.middlewares.nostr.headers.stsincludesubdomains=true"
     - "traefik.http.middlewares.nostr.headers.stspreload=true"
     - "traefik.http.middlewares.nostr.headers.stsseconds=63072000"
     - "traefik.http.routers.nostr.middlewares=nostr"
```

### Traefik Notes

Traefik will take care of the provisioning and renewal of certificates. In case of an ipv4-only relay, simply detele the `enable_ipv6:` and `ipam:` entries in the `networks:` section of the docker-compose file.

## See also

* [Production Deployment with nginx + certbot](docker-production.md) — full
  step-by-step guide for a single-host production deployment with nginx on
  the host, Let's Encrypt via certbot, and Docker Compose for the relay.
