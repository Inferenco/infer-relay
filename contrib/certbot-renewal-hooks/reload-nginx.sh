#!/bin/sh
# Post-renewal hook for certbot.
# Installed by docs/docker-production.md into:
#   /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
# Runs after every successful cert renewal to make nginx pick up the new cert.
set -eu
systemctl reload nginx
