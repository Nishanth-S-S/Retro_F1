# Retro F1 web build, served by Caddy on Railway's $PORT.
FROM caddy:2-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY index.* privacy.html support.html style.css /srv/
