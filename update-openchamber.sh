#!/usr/bin/env sh
set -eu

cd /home/openchamber/openchamber

echo "[update] fetching latest OpenChamber source..."
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
git fetch --depth=1 origin "${BRANCH}"
git reset --hard "origin/${BRANCH}"

echo "[update] installing dependencies..."
bun install --frozen-lockfile --ignore-scripts

echo "[update] building web UI..."
bun run build:web

echo ""
echo "[update] OpenChamber updated successfully."
echo "[update] Restart the container (or restart the openchamber process) for changes to take effect."
