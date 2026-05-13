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
- [Domain assignment](#domain-assignment)
- [Environment variables](#environment-variables)
- [Host opencode integration](#host-opencode-integration)
  - [Option A — mount the host binary (recommended)](#option-a--mount-the-host-binary-recommended)
  - [Option B — connect to a running opencode server](#option-b--connect-to-a-running-opencode-server)
  - [Fallback — bundled opencode-ai](#fallback--bundled-opencode-ai)
- [Sharing host opencode config and history](#sharing-host-opencode-config-and-history)
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
4. **Assembles a lean runtime image** from `oven/bun:1` containing only the
   compiled web server, its `node_modules`, and the `opencode-ai` npm package
   as a bundled fallback.

`entrypoint.sh` (a thin wrapper around the upstream
`scripts/docker-entrypoint.sh`) checks for a host-mounted opencode binary at
`/opt/host-opencode/opencode`. If it is a regular executable file it is
prepended to `PATH`, silently winning over the bundled `opencode-ai`. If the
mount is absent the bundled copy is used automatically.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| [Coolify v4+](https://coolify.io) | Self-hosted or Coolify Cloud |
| opencode installed on the Coolify host | Required only for Options A & B below |

---

## Deploying with Coolify

> Coolify's Docker Compose deployment treats `docker-compose.yml` as the
> **single source of truth**. Settings that would normally live in the UI
> (environment variables, volumes, domains) are all defined in the compose
> file. See the
> [Coolify Docker Compose docs](https://coolify.io/docs/knowledge-base/docker/compose)
> for full details.

1. In your Coolify dashboard, go to **Projects → your project → + New Resource**.
2. Choose **Docker Compose**.
3. Select **Load from URL / Git** and point it at this repository, **or** paste
   the contents of [`docker-compose.yml`](./docker-compose.yml) directly into
   the editor.
4. Coolify automatically scans the file and surfaces every `${VAR}` reference
   as an editable field in the **Environment Variables** tab — no manual
   configuration required.
5. [Assign a domain](#domain-assignment) to the `openchamber` service.
6. Choose your [opencode integration method](#host-opencode-integration).
7. Click **Deploy**.

---

## Domain assignment

The compose file includes the Coolify magic variable `SERVICE_FQDN_OPENCHAMBER_3000`:

```yaml
environment:
  - SERVICE_FQDN_OPENCHAMBER_3000
```

This tells Coolify:

- **Register** the `openchamber` service with its built-in Traefik reverse proxy.
- **Route** all incoming HTTP/HTTPS traffic to **container port 3000**.
- **Provision** a TLS certificate automatically (if HTTPS is configured on your
  Coolify server).

After loading the compose file, open the **Domains** tab for the `openchamber`
service in Coolify and enter your desired domain, e.g. `https://code.example.com`.
Coolify handles the rest.

> **Note:** The compose file does **not** use a `ports:` mapping. A direct host
> port binding would bypass Coolify's proxy and expose the service outside of
> TLS/auth control. Use the domain approach above for all production deployments.

---

## Environment variables

All `${VAR:-default}` references in the compose file are automatically detected
by Coolify and displayed as editable fields in the UI. Hardcoded values (like
`OPENCHAMBER_HOST=0.0.0.0`) are passed directly to the container and do not
appear in the UI.

| Variable | Default | Coolify UI | Description |
|---|---|---|---|
| `UI_PASSWORD` | *(empty)* | ✅ editable | When non-empty, the web UI requires this password. Leave blank to disable authentication. |
| `OPENCODE_HOST` | *(empty)* | ✅ editable | URL of an external opencode server (Option B). Example: `http://host.docker.internal:4096` |
| `OPENCODE_SKIP_START` | `false` | ✅ editable | Set `true` when using `OPENCODE_HOST` so OpenChamber doesn't start its own opencode process. |
| `OPENCHAMBER_HOST` | `0.0.0.0` | ❌ hardcoded | Bind address. Must be `0.0.0.0` inside Docker for the proxy to reach the container. |

Additional variables supported by OpenChamber but not exposed in the default
compose file (add them manually in Coolify's Environment Variables UI if needed):

| Variable | Description |
|---|---|
| `OPENCHAMBER_TUNNEL_PROVIDER` | Set to `cloudflare` to enable tunnel support. |
| `OPENCHAMBER_TUNNEL_MODE` | `quick`, `managed-remote`, or `managed-local`. |
| `OPENCHAMBER_TUNNEL_HOSTNAME` | Required for `managed-remote` tunnel mode. |
| `OPENCHAMBER_TUNNEL_TOKEN` | Cloudflare token for `managed-remote` tunnel mode. |
| `OH_MY_OPENCODE` | Set `true` to install [oh-my-opencode](https://github.com/tluyben/oh-my-opencode). |

---

## Host opencode integration

### Option A — mount the host binary (recommended)

The container can run the exact opencode binary already on your Coolify host,
sharing its downloaded model cache and configuration.

**Step 1** — find the binary path on the host:

```bash
which opencode
# /usr/local/bin/opencode  — system-wide npm install
# /home/myuser/.local/bin/opencode  — user-local install
# /root/.local/bin/opencode  — root install
```

**Step 2** — uncomment and adjust the volume line in `docker-compose.yml`:

```yaml
volumes:
  # ...existing volumes...
  - /usr/local/bin/opencode:/opt/host-opencode/opencode:ro
```

> ⚠️ **The source path must already exist on the host before deploying.**
> Docker will not create the binary for you — and if the path is missing it
> creates an empty directory at that location, which the entrypoint guards
> against (`[ -f ]` check).

**Step 3** — deploy. When the container starts, `entrypoint.sh` detects the
mount and logs:

```
[entrypoint] using host-mounted opencode: /opt/host-opencode/opencode
```

---

### Option B — connect to a running opencode server

If opencode is already running as a server on the host (e.g. managed by
systemd or another process), OpenChamber can connect to it over HTTP without
needing the binary inside the container at all.

In Coolify's **Environment Variables** UI (or in the compose file), set:

| Variable | Value |
|---|---|
| `OPENCODE_HOST` | `http://host.docker.internal:4096` |
| `OPENCODE_SKIP_START` | `true` |

`host.docker.internal` resolves to the Docker host gateway and is already
configured via `extra_hosts` in the compose file.

Leave the Option A volume line commented out.

---

### Fallback — bundled opencode-ai

If neither option is configured, the `opencode-ai` npm package bundled in the
image is used automatically. No additional configuration is needed. This is a
good starting point if you want to try OpenChamber before installing opencode
on the host.

---

## Sharing host opencode config and history

When using Option A, you can additionally share the host user's opencode
configuration and conversation history with the container by replacing the
named volumes with host bind-mounts. In `docker-compose.yml`, swap:

```yaml
- opencode-config:/home/openchamber/.config/opencode
- opencode-share:/home/openchamber/.local/share/opencode
- opencode-state:/home/openchamber/.local/state/opencode
```

with:

```yaml
- /home/myuser/.config/opencode:/home/openchamber/.config/opencode
- /home/myuser/.local/share/opencode:/home/openchamber/.local/share/opencode
- /home/myuser/.local/state/opencode:/home/openchamber/.local/state/opencode
```

> **Note:** The container runs as UID/GID 1000. Ensure the host directories
> are readable by UID 1000, or adjust ownership: `chown -R 1000:1000 ~/.config/opencode`.

In Coolify's compose UI, Coolify treats bind-mount volumes the same as named
volumes — it will display them in the **Storages** tab but will not manage the
host path itself.

---

## Persistent volumes

The compose file declares named volumes for all state that should survive
container restarts or image updates:

| Volume | Container path | Contents |
|---|---|---|
| `openchamber-config` | `/home/openchamber/.config/openchamber` | OpenChamber application settings |
| `openchamber-ssh` | `/home/openchamber/.ssh` | SSH keys (auto-generated on first start if absent) |
| `openchamber-workspaces` | `/home/openchamber/workspaces` | Cloned repositories / working directories |
| `opencode-config` | `/home/openchamber/.config/opencode` | opencode config (API keys, providers, models) |
| `opencode-share` | `/home/openchamber/.local/share/opencode` | Conversation history, model cache |
| `opencode-state` | `/home/openchamber/.local/state/opencode` | opencode runtime state |

Coolify manages these volumes automatically and displays them in the
**Storages** tab of the service.

---

## Building the image locally

```bash
git clone https://github.com/NathanJGaul/openchamber-coolify.git
cd openchamber-coolify

# Build (pulls latest OpenChamber main branch)
docker build -t openchamber-coolify .

# Run with bundled opencode (no host binary needed)
docker run -p 3000:3000 openchamber-coolify

# Run with host opencode binary mounted
docker run -p 3000:3000 \
  -v /usr/local/bin/opencode:/opt/host-opencode/opencode:ro \
  openchamber-coolify
```

Open `http://localhost:3000`.

---

## Pinning to a specific OpenChamber version

Pass `OPENCHAMBER_VERSION` as a build-arg to target a specific branch or tag:

```bash
docker build --build-arg OPENCHAMBER_VERSION=v1.10.4 -t openchamber-coolify .
```

To publish a pinned version via GitHub Actions, push a tag matching `v*`:

```bash
git tag v1.10.4
git push origin v1.10.4
```

The workflow publishes `ghcr.io/nathanjgaul/openchamber-coolify:v1.10.4` alongside `latest`.

---

## How the image is published

[`.github/workflows/docker-publish.yml`](.github/workflows/docker-publish.yml)
runs on every push to `main` and on `v*` tags:

1. Authenticates to `ghcr.io` using `GITHUB_TOKEN` — no secrets to configure.
2. Tags the image as:
   - `latest` — on every `main` push
   - The git tag (e.g. `v1.10.4`) — when a version tag is pushed
   - `sha-<short-sha>` — on every run, for rollback pinning
3. Pushes to `ghcr.io/nathanjgaul/openchamber-coolify`.

Layer caching via GitHub Actions cache keeps subsequent builds fast.

---

## Repository layout

```
.
├── Dockerfile                        # Multi-stage: clone → deps → build → runtime
├── entrypoint.sh                     # Wrapper: prefer host opencode, then upstream entrypoint
├── docker-compose.yml                # Coolify deployment (SERVICE_FQDN, ${VAR} env syntax)
└── .github/
    └── workflows/
        └── docker-publish.yml        # Build and push to ghcr.io on main / v* tags
```

---

## License

This repository contains only build and deployment tooling. OpenChamber itself
is licensed under the [MIT License](https://github.com/openchamber/openchamber/blob/main/LICENSE).
