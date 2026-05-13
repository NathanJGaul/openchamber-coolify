#!/usr/bin/env sh
set -eu

# Prefer the host's opencode binary if it has been volume-mounted at
# /opt/host-opencode/opencode.  This lets the container share the exact
# opencode version and configuration already installed on the Coolify host
# without bundling its own copy.
#
# If the mount is absent, the bundled opencode-ai npm package is used instead
# (it is already on PATH via NPM_CONFIG_PREFIX/bin).
HOST_OPENCODE="/opt/host-opencode/opencode"
# Use [ -f ] to confirm it is a regular file, not an empty directory that Docker
# may create when the source path is absent on the host at deploy time.
if [ -f "${HOST_OPENCODE}" ] && [ -x "${HOST_OPENCODE}" ]; then
    echo "[entrypoint] using host-mounted opencode: ${HOST_OPENCODE}"
    # Prepend the directory so it shadows the bundled opencode-ai binary.
    HOST_BIN_DIR="$(dirname "${HOST_OPENCODE}")"
    export PATH="${HOST_BIN_DIR}:${PATH}"
fi

exec sh /home/openchamber/openchamber-entrypoint.sh "$@"
