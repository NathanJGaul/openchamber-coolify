# syntax=docker/dockerfile:1
# Builds OpenChamber (https://github.com/openchamber/openchamber) for Coolify deployment.
# Supports using the host's opencode binary via a volume mount at /opt/host-opencode/opencode.

# ── Stage 1: clone source ────────────────────────────────────────────────────
FROM oven/bun:1 AS source
WORKDIR /app
ARG OPENCHAMBER_VERSION=main
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && git clone --depth 1 --branch "${OPENCHAMBER_VERSION}" \
         https://github.com/openchamber/openchamber.git .

# ── Stage 2: install dependencies ────────────────────────────────────────────
FROM source AS deps
RUN bun install --frozen-lockfile --ignore-scripts

# ── Stage 3: build web package ───────────────────────────────────────────────
FROM deps AS builder
RUN bun run build:web

# ── Stage 4: runtime ─────────────────────────────────────────────────────────
FROM oven/bun:1 AS runtime
WORKDIR /home/openchamber

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    less \
    nodejs \
    npm \
    openssh-client \
    python3 \
    gh \
    && rm -rf /var/lib/apt/lists/*

# Replace the base image's 'bun' user (UID 1000) with 'openchamber'
# so mounted volumes with 1000:1000 ownership work correctly.
RUN getent passwd bun >/dev/null 2>&1 && userdel bun || true \
    && getent group bun >/dev/null 2>&1 && groupdel bun || true \
    && groupadd -g 1000 openchamber 2>/dev/null || true \
    && id -u openchamber >/dev/null 2>&1 || useradd -u 1000 -g 1000 -m -s /bin/bash openchamber \
    && chown -R openchamber:openchamber /home/openchamber

USER openchamber

ENV NPM_CONFIG_PREFIX=/home/openchamber/.npm-global
ENV PATH=${NPM_CONFIG_PREFIX}/bin:${PATH}

# Install opencode-ai as the bundled fallback when no host binary is mounted.
RUN npm config set prefix /home/openchamber/.npm-global \
    && mkdir -p /home/openchamber/.npm-global \
    && mkdir -p /home/openchamber/.local/share/opencode \
                /home/openchamber/.local/state/opencode \
                /home/openchamber/.config/openchamber \
                /home/openchamber/.config/opencode \
                /home/openchamber/.ssh \
                /home/openchamber/workspaces \
    && npm install -g opencode-ai

# Copy upstream entrypoint to the path our wrapper expects
COPY --chown=openchamber:openchamber --from=builder \
     /app/scripts/docker-entrypoint.sh /home/openchamber/openchamber-entrypoint.sh

# Copy our entrypoint wrapper
COPY --chown=openchamber:openchamber entrypoint.sh /home/openchamber/entrypoint.sh

# Copy full OpenChamber source tree (with .git history) into a subdirectory
# that can be mounted on a named volume.  This allows git pull, bun install,
# and bun run build:web to be run from inside the container and have the
# results persist across restarts.
COPY --chown=openchamber:openchamber --from=builder /app /home/openchamber/openchamber

# Record the source version at build time so the entrypoint can detect
# if the source has been updated in-container without rebuilding the web.
RUN python3 -c "import json; print(json.load(open('/home/openchamber/openchamber/packages/web/package.json'))['version'])" \
    > /home/openchamber/openchamber/.source_version

# Copy update scripts
COPY --chown=openchamber:openchamber update-openchamber.sh /home/openchamber/update-openchamber.sh
RUN chmod +x /home/openchamber/update-openchamber.sh

ENV NODE_ENV=production
WORKDIR /home/openchamber/openchamber
EXPOSE 3000

ENTRYPOINT ["sh", "/home/openchamber/entrypoint.sh"]
