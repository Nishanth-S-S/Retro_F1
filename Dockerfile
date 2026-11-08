# Formula Retro privacy policy, served by Caddy on Railway's $PORT.
FROM caddy:2-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY index.html privacy.html style.css /srv/
