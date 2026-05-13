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
    git \
    less \
    nodejs \
    npm \
    openssh-client \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Replace the base image's 'bun' user (UID 1000) with 'openchamber'
# so mounted volumes with 1000:1000 ownership work correctly.
RUN userdel bun \
    && groupadd -g 1000 openchamber \
    && useradd -u 1000 -g 1000 -m -s /bin/bash openchamber \
    && chown -R openchamber:openchamber /home/openchamber

USER openchamber

ENV NPM_CONFIG_PREFIX=/home/openchamber/.npm-global
ENV PATH=${NPM_CONFIG_PREFIX}/bin:${PATH}

# Install opencode-ai as the bundled fallback when no host binary is mounted.
RUN npm config set prefix /home/openchamber/.npm-global \
    && mkdir -p /home/openchamber/.npm-global \
    && mkdir -p /home/openchamber/.local /home/openchamber/.config /home/openchamber/.ssh \
    && npm install -g opencode-ai

# Copy upstream entrypoint and our wrapper
COPY --chown=openchamber:openchamber --from=builder \
     /app/scripts/docker-entrypoint.sh /home/openchamber/openchamber-entrypoint.sh
COPY --chown=openchamber:openchamber entrypoint.sh /home/openchamber/entrypoint.sh

# Copy built application artifacts
COPY --from=deps    /app/node_modules                     ./node_modules
COPY --from=deps    /app/packages/web/node_modules        ./packages/web/node_modules
COPY --from=builder /app/package.json                     ./package.json
COPY --from=builder /app/packages/web/package.json        ./packages/web/package.json
COPY --from=builder /app/packages/web/bin                 ./packages/web/bin
COPY --from=builder /app/packages/web/server              ./packages/web/server
COPY --from=builder /app/packages/web/dist                ./packages/web/dist

ENV NODE_ENV=production
EXPOSE 3000

ENTRYPOINT ["sh", "/home/openchamber/entrypoint.sh"]
