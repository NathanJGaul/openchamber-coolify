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

echo "[update] recording source version..."
python3 -c "
import json
v = json.load(open('packages/web/package.json'))['version']
with open('.source_version', 'w') as f:
    f.write(v + chr(10))
print(v)
"

echo ""
echo "[update] OpenChamber updated successfully to version $(cat .source_version)."
echo "[update] Restart the container (or restart the openchamber process) for changes to take effect."
