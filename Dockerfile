# syntax=docker/dockerfile:1
# Builds OpenChamber (https://github.com/openchamber/openchamber) for Coolify deployment.
#   ARG OPENCHAMBER_VERSION – branch/tag of openchamber/openchamber to clone (default: main)
#   ARG OPENCODE_VERSION    – npm version of opencode-ai to install (default: latest)

# ── Stage 1: clone source ────────────────────────────────────────────────────
FROM oven/bun:1 AS source
WORKDIR /app
# Set to a release tag (e.g. v0.5.2) to download a release tarball,
# or any branch name (e.g. main, dev) to git clone.
ARG OPENCHAMBER_VERSION=1.11.2
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && case "${OPENCHAMBER_VERSION}" in \
        v[0-9]*.[0-9]*.[0-9]*) \
            echo "Downloading release ${OPENCHAMBER_VERSION}..."; \
            curl -sL "https://github.com/openchamber/openchamber/archive/refs/tags/${OPENCHAMBER_VERSION}.tar.gz" \
                | tar xz --strip-components=1 \
            ;; \
        [0-9]*.[0-9]*.[0-9]*) \
            echo "Downloading release v${OPENCHAMBER_VERSION}..."; \
            curl -sL "https://github.com/openchamber/openchamber/archive/refs/tags/v${OPENCHAMBER_VERSION}.tar.gz" \
                | tar xz --strip-components=1 \
            ;; \
        *) \
            echo "Cloning branch/tag ${OPENCHAMBER_VERSION}..."; \
            git clone --depth 1 --branch "${OPENCHAMBER_VERSION}" \
                https://github.com/openchamber/openchamber.git . \
            ;; \
    esac

# ── Stage 2: install dependencies ────────────────────────────────────────────
FROM source AS deps
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 make gcc g++ nodejs npm \
    && rm -rf /var/lib/apt/lists/* \
    && bun install --frozen-lockfile --ignore-scripts \
    && (npm rebuild node-pty || echo "[build] node-pty rebuild skipped (prebuilt unavailable)") \
    && (npm rebuild bun-pty 2>/dev/null || echo "[build] bun-pty rebuild skipped (Rust not available)")

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
    # Chromium system dependencies (required by Playwright headless browser)
    libnss3 \
    libnspr4 \
    libatk-bridge2.0-0 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2 \
    libatspi2.0-0 \
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

ARG OPENCODE_VERSION=latest

# Install opencode-ai at the specified version (defaults to latest).
RUN npm config set prefix /home/openchamber/.npm-global \
    && mkdir -p /home/openchamber/.npm-global \
    && mkdir -p /home/openchamber/.local/share/opencode \
                /home/openchamber/.local/state/opencode \
                /home/openchamber/.config/openchamber \
                /home/openchamber/.config/opencode \
                /home/openchamber/.ssh \
                /home/openchamber/workspaces \
    && npm install -g "opencode-ai@${OPENCODE_VERSION}"

# Install Playwright + Chromium for headless browser automation (used by OpenCode).
# The browser binary is baked into the image (~120 MB) so it's always available.
RUN mkdir -p /home/openchamber/.cache/ms-playwright \
    && npm install -g playwright \
    && playwright install chromium \
    && CHROMIUM_PATH=$(find /home/openchamber/.cache/ms-playwright -name "chrome" -type f 2>/dev/null | head -1) \
    && if [ -n "${CHROMIUM_PATH}" ]; then \
         echo "[build] Chromium installed at ${CHROMIUM_PATH}"; \
       else \
         echo "[build] WARNING: Chromium binary not found after playwright install"; \
       fi

ENV PLAYWRIGHT_BROWSERS_PATH=/home/openchamber/.cache/ms-playwright

# Copy upstream entrypoint to the path our wrapper expects
COPY --chown=openchamber:openchamber --from=builder \
     /app/scripts/docker-entrypoint.sh /home/openchamber/openchamber-entrypoint.sh

# Copy our entrypoint wrapper
COPY --chown=openchamber:openchamber entrypoint.sh /home/openchamber/entrypoint.sh

# Copy the built OpenChamber source tree into the image.
COPY --chown=openchamber:openchamber --from=builder /app /home/openchamber/openchamber

# Record the baked-in version for runtime reference.
RUN python3 -c "import json; print(json.load(open('/home/openchamber/openchamber/packages/web/package.json'))['version'])" \
    > /home/openchamber/.openchamber_version

ENV NODE_ENV=production
WORKDIR /home/openchamber/openchamber
EXPOSE 3000

ENTRYPOINT ["sh", "/home/openchamber/entrypoint.sh"]
