#!/bin/sh
# One-shot setup for the openclaw gateway. Runs as root on every
# 'docker compose up' (install, make update, make restart) - not when Docker
# itself restarts the gateway (crash, reboot, 'docker restart').
#
# 1. Copies the host SSH key and config (./openclaw/ssh) into the openclaw_ssh
#    volume owned by node. On the host the key stays with root / the installing
#    user, never uid 1000; the volume copy lives under /var/lib/docker, which
#    only root can enter.
# 2. Enforces the gateway keys below with 'config set' as node. Everything else
#    in openclaw.json (models, channel policies, agents...) stays under the
#    user's control in the dashboard. The config schema is strict: an unknown
#    key stops the gateway, so check the upstream schema before adding keys.
#
# A failed 'config set' (e.g. upstream renamed a key) is reported but does not
# fail this container: that would abort 'docker compose up' for the whole stack.
# 'make doctor' reports it.
set -e

if [ -f /ssh-src/id_ed25519 ] && [ -f /ssh-src/config ]; then
    install -d -o node -g node -m 700 /home/node/.ssh
    install -o node -g node -m 600 /ssh-src/id_ed25519 /ssh-src/config /home/node/.ssh/
else
    echo "openclaw-init: WARNING: no SSH key in ./openclaw/ssh; a copy already in the volume is kept, otherwise 'ssh host' will not work until the installer or 'make update' creates it" >&2
fi

# Telegram is only switched on here; with an empty .env token the channel is
# left as configured in the dashboard (the token may live in openclaw.json).
telegram_entry=""
if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    telegram_entry=', {"path": "channels.telegram.enabled", "value": true}'
fi

# ${OPENCLAW_HOSTNAME} stays literal (single quotes) and is substituted by
# OpenClaw at load time, so a hostname change in .env only needs 'make restart'.
if ! runuser -u node -- node dist/index.js config set --batch-json '[
  {"path": "gateway.mode", "value": "local"},
  {"path": "gateway.bind", "value": "lan"},
  {"path": "gateway.auth.mode", "value": "password"},
  {"path": "gateway.controlUi.allowedOrigins", "value": ["https://${OPENCLAW_HOSTNAME}"]},
  {"path": "gateway.trustedProxies", "value": ["172.16.0.0/12", "10.0.0.0/8", "192.168.0.0/16"]}'"$telegram_entry"'
]'; then
    echo "openclaw-init: ERROR: 'config set' failed (see above). The gateway keeps its existing config; on a fresh install it will not start until this is fixed." >&2
fi
