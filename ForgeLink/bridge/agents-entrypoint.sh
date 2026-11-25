#!/bin/sh
set -eu
# The private keyring password is generated on the NAS and mounted read-only.
# Keep the same user D-Bus address for docker exec login sessions.
export XDG_RUNTIME_DIR=/tmp/forgelink-runtime
export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
rm -f "$XDG_RUNTIME_DIR/bus"
dbus-daemon --session --address="$DBUS_SESSION_BUS_ADDRESS" --fork
if [ -f /run/secrets/keyring-password ]; then
    gnome-keyring-daemon --unlock --components=secrets < /run/secrets/keyring-password >/dev/null
fi
exec "$@"
