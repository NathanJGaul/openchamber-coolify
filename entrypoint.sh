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

# Initialize a minimal git repo in the home directory so simple-git (used by
# OpenChamber for git status/branch info) does not throw repeated
# "not a git repository" errors when the frontend polls the current directory.
if [ ! -d "/home/openchamber/.git" ]; then
    echo "[entrypoint] initializing git repo in home directory"
    cd /home/openchamber && git init --quiet
fi

# On first startup (no existing settings), initialize lastDirectory to the git
# repository so the frontend does not poll for git info on the home directory
# (which is not a git repo), avoiding repeated "not a git repository" errors.
SETTINGS_DIR="/home/openchamber/.config/openchamber"
SETTINGS_FILE="${SETTINGS_DIR}/settings.json"
if [ ! -f "${SETTINGS_FILE}" ]; then
    echo "[entrypoint] initializing settings with lastDirectory pointing to OpenChamber source"
    mkdir -p "${SETTINGS_DIR}"
    cat > "${SETTINGS_FILE}" <<'EOF'
{
  "lastDirectory": "/home/openchamber/openchamber",
  "homeDirectory": "/home/openchamber",
  "version": 1
}
EOF
fi

exec sh /home/openchamber/openchamber-entrypoint.sh "$@"
