# openchamber-coolify

A Coolify-compatible Docker image that builds and serves
[OpenChamber](https://github.com/openchamber/openchamber) — the web UI for
[opencode](https://github.com/sst/opencode) — with first-class support for
using the **opencode binary already installed on your Coolify host**.

The image is published automatically to the GitHub Container Registry on every
push to `main`:

```
ghcr.io/nathanjgaul/openchamber-coolify:latest
```

---

## Table of Contents

- [How it works](#how-it-works)
- [Prerequisites](#prerequisites)
- [Deploying with Coolify](#deploying-with-coolify)
  - [Option A — mount the host opencode binary (recommended)](#option-a--mount-the-host-opencode-binary-recommended)
  - [Option B — connect to a running opencode server](#option-b--connect-to-a-running-opencode-server)
- [Environment variables](#environment-variables)
- [Persistent volumes](#persistent-volumes)
- [Building the image locally](#building-the-image-locally)
- [Pinning to a specific OpenChamber version](#pinning-to-a-specific-openchamber-version)
- [How the image is published](#how-the-image-is-published)
- [Repository layout](#repository-layout)

---

## How it works

The multi-stage `Dockerfile`:

1. **Clones** `openchamber/openchamber` from GitHub (branch/tag controlled by
   the `OPENCHAMBER_VERSION` build-arg, default `main`).
2. **Installs dependencies** with `bun install`.
3. **Builds** the `packages/web` package (`bun run build:web`).
4. **Assembles a lean runtime image** from `oven/bun:1` that contains only the
   compiled web server, its `node_modules`, and the `opencode-ai` npm package
   as a bundled fallback.

`entrypoint.sh` (our thin wrapper around the upstream
`scripts/docker-entrypoint.sh`) checks for a host-mounted opencode binary at
`/opt/host-opencode/opencode`.  If it is executable it is prepended to `PATH`,
so it silently wins over the bundled `opencode-ai`.  If the mount is absent the
bundled copy is used with no other changes needed.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| [Coolify v4+](https://coolify.io) | Self-hosted or Coolify Cloud |
| opencode installed on the Coolify host | `npm i -g opencode-ai` or direct binary |
| Port `3000` reachable inside the Coolify network | Coolify's reverse-proxy handles TLS termination |

---

## Deploying with Coolify

### 1 — Create a new service in Coolify

1. Open your Coolify dashboard → **Projects** → select your project → **+ New
   Resource**.
2. Choose **Docker Compose**.
3. Paste the contents of [`docker-compose.yml`](./docker-compose.yml) from this
   repository (or point Coolify at this GitHub repo directly).
4. Configure the environment variables described below.
5. Click **Deploy**.

Coolify will pull `ghcr.io/nathanjgaul/openchamber-coolify:latest`, start the
container, and assign it a domain through its built-in reverse proxy.

---

### Option A — mount the host opencode binary (recommended)

This is the default configuration in `docker-compose.yml`.  The container
mounts the host binary read-only and uses it directly, so it always runs the
**same version** you have on the host and shares its downloaded model cache.

Find the binary's path on your Coolify host:

```bash
which opencode
# e.g. /usr/local/bin/opencode
# or   /home/myuser/.local/bin/opencode
# or   /root/.local/bin/opencode  (if you installed as root)
```

Update the volume mount in `docker-compose.yml`:

```yaml
volumes:
  - /usr/local/bin/opencode:/opt/host-opencode/opencode:ro   # ← adjust left side
```

When the container starts, `entrypoint.sh` detects the mount and logs:

```
[entrypoint] using host-mounted opencode: /opt/host-opencode/opencode
```

No other configuration is required.

---

### Option B — connect to a running opencode server

If opencode is already running as a server on the host (e.g. managed by
systemd), you can tell OpenChamber to connect to it over HTTP instead of
launching its own process.

1. Remove (or comment out) the host-binary volume mount.
2. Set the following environment variables:

```yaml
environment:
  OPENCODE_HOST: "http://host.docker.internal:4096"
  OPENCODE_SKIP_START: "true"
```

`host.docker.internal` resolves to the Docker host gateway and is already
configured via `extra_hosts` in `docker-compose.yml`.

---

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `OPENCHAMBER_HOST` | `0.0.0.0` | Bind address for the OpenChamber web server. The default is required for Docker port-mapping to work. |
| `UI_PASSWORD` | *(unset)* | When set, the web UI requires this password before granting access. |
| `OPENCODE_HOST` | *(unset)* | URL of an external opencode server. Use with Option B. |
| `OPENCODE_SKIP_START` | *(unset)* | Set to `"true"` to prevent OpenChamber from starting its own opencode process. Use with `OPENCODE_HOST`. |
| `OPENCHAMBER_TUNNEL_PROVIDER` | *(unset)* | Set to `cloudflare` to enable tunnel support. |
| `OPENCHAMBER_TUNNEL_MODE` | *(unset)* | `quick`, `managed-remote`, or `managed-local`. |
| `OPENCHAMBER_TUNNEL_HOSTNAME` | *(unset)* | Required for `managed-remote` tunnel mode. |
| `OPENCHAMBER_TUNNEL_TOKEN` | *(unset)* | Cloudflare token for `managed-remote` tunnel mode. |
| `OH_MY_OPENCODE` | *(unset)* | Set to `"true"` to install and enable [oh-my-opencode](https://github.com/tluyben/oh-my-opencode). |

---

## Persistent volumes

The compose file declares named volumes for all state that should survive
container restarts or image updates:

| Volume | Container path | Contents |
|---|---|---|
| `openchamber-config` | `/home/openchamber/.config/openchamber` | OpenChamber application settings |
| `openchamber-ssh` | `/home/openchamber/.ssh` | SSH keys (auto-generated on first start if absent) |
| `openchamber-workspaces` | `/home/openchamber/workspaces` | Cloned repositories / working directories |
| `opencode-config` | `/home/openchamber/.config/opencode` | opencode configuration (API keys, providers, etc.) |
| `opencode-share` | `/home/openchamber/.local/share/opencode` | Conversation history, model cache |
| `opencode-state` | `/home/openchamber/.local/state/opencode` | opencode runtime state |

> **Tip:** When using Option A, `opencode-config` / `opencode-share` /
> `opencode-state` can be replaced with bind-mounts pointing directly at the
> host user's opencode directories so the container and the host share a single
> set of configuration and history:
>
> ```yaml
> volumes:
>   - /home/myuser/.config/opencode:/home/openchamber/.config/opencode
>   - /home/myuser/.local/share/opencode:/home/openchamber/.local/share/opencode
>   - /home/myuser/.local/state/opencode:/home/openchamber/.local/state/opencode
> ```

---

## Building the image locally

```bash
# Clone this repo
git clone https://github.com/NathanJGaul/openchamber-coolify.git
cd openchamber-coolify

# Build (defaults to OpenChamber main branch)
docker build -t openchamber-coolify .

# Run locally
docker run -p 3000:3000 \
  -v /usr/local/bin/opencode:/opt/host-opencode/opencode:ro \
  openchamber-coolify
```

Then open `http://localhost:3000`.

---

## Pinning to a specific OpenChamber version

Pass `OPENCHAMBER_VERSION` as a build-arg to target a specific branch or tag:

```bash
docker build --build-arg OPENCHAMBER_VERSION=v1.10.4 -t openchamber-coolify .
```

To publish a pinned version via GitHub Actions, trigger the workflow manually
with the `workflow_dispatch` event and override the build-arg, or push a tag
that matches `v*`.

---

## How the image is published

The [`.github/workflows/docker-publish.yml`](.github/workflows/docker-publish.yml)
workflow runs on every push to `main` and on `v*` tags.  It:

1. Logs in to `ghcr.io` using `GITHUB_TOKEN` (no secrets to configure).
2. Tags the image as:
   - `latest` (on `main`)
   - The git tag (e.g. `v1.10.4`) when a version tag is pushed
   - `sha-<short-sha>` for every run
3. Pushes to `ghcr.io/nathanjgaul/openchamber-coolify`.

Layer caching via GitHub Actions cache keeps subsequent builds fast.

---

## Repository layout

```
.
├── Dockerfile                        # Multi-stage build (clone → deps → build → runtime)
├── entrypoint.sh                     # Wrapper: prefer host opencode, then delegate to upstream entrypoint
├── docker-compose.yml                # Coolify deployment configuration
└── .github/
    └── workflows/
        └── docker-publish.yml        # Build and push to ghcr.io
```

---

## License

This repository contains only build and deployment tooling.  OpenChamber itself
is licensed under the [MIT License](https://github.com/openchamber/openchamber/blob/main/LICENSE).
