# openchamber-coolify

A Coolify-compatible Docker image for OpenChamber.

Builds `openchamber/openchamber` from source and serves the web UI on port `3000`.
Supports host-mounted `opencode`, host `opencode` servers, or the bundled `opencode-ai` fallback.

Published image:

```bash
ghcr.io/nathanjgaul/openchamber-coolify:latest
```

## Deploy in Coolify

1. Create a Docker Compose resource in Coolify.
2. Load this repo or paste `docker-compose.yml`.
3. Assign a domain to the `openchamber` service.
4. Set `UI_PASSWORD` to enable web UI authentication.
5. Choose one of the following:
   - mount host `opencode`: set `HOST_OPENCODE_PATH`
   - use host opencode server: set `OPENCODE_HOST` and `OPENCODE_SKIP_START=true`
   - no host binary: use bundled `opencode-ai`

## Environment

The compose file requires `GH_TOKEN` to be set in the deployment environment.
If you do not need GitHub authentication in the container, remove or adjust
that variable in `docker-compose.yml` before deploying.

## Local build

```bash
docker build --no-cache -t openchamber-coolify-test .
```

The `OPENCHAMBER_VERSION` build arg accepts either a **release tag** (downloads a tarball from GitHub releases) or a **branch name** (git clones):

| Example | Behavior |
|---------|----------|
| `main` (default) | git clone the `main` branch |
| `v0.5.2` | Download release v0.5.2 tarball |
| `0.5.2` | Same as above (auto-prepends `v`) |
| `dev` | git clone the `dev` branch |

```bash
# Build from a specific release (immutable, cache-friendly)
docker build --no-cache --build-arg OPENCHAMBER_VERSION=v0.5.2 -t openchamber-coolify-test .

# Build from a branch
docker build --no-cache --build-arg OPENCHAMBER_VERSION=main -t openchamber-coolify-test .
```

Releases are downloaded as tarballs (no git history), so the layer is immutable and Docker cache never becomes stale. Branches are still git cloned for flexibility.

## Notes

- `docker-compose.yml` is the deployment entrypoint for Coolify.
- The Dockerfile now replaces the base `bun` user/group cleanly and creates the runtime user as UID/GID 1000.
