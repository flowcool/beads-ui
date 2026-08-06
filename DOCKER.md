# Docker

Run beads-ui in a container — no local Node.js install required.

## Quick start

```bash
# In your project directory (containing .beads/):
docker run -d -p 3000:3000 --init -v ./:/data ghcr.io/mantoni/beads-ui:latest
```

Or with Docker Compose:

```bash
docker compose up -d
```

Then open http://localhost:3000.

## Build args

| Arg | Default | Description |
|---|---|---|
| `BD_VERSION` | `1.1.2` | Version of the `bd` CLI to bundle (from [steveyegge/beads](https://github.com/steveyegge/beads/releases)) |
| `BD_SHA256_AMD64` | *(hardcoded)* | SHA256 checksum for the linux/amd64 tarball |
| `BD_SHA256_ARM64` | *(hardcoded)* | SHA256 checksum for the linux/arm64 tarball |

To use a different `bd` version:

```bash
docker build \
  --build-arg BD_VERSION=1.1.2 \
  --build-arg BD_SHA256_AMD64=<sha256> \
  --build-arg BD_SHA256_ARM64=<sha256> \
  -t beads-ui .
```

Get checksums from the release's `checksums.txt` file, then verify independently.

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `HOST` | `0.0.0.0` | Bind address (set in image, override if needed) |
| `PORT` | `3000` | Listen port |
| `BD_BIN` | `/usr/local/bin/bd` | Path to `bd` binary (set in image) |
| `BDUI_BD_SANDBOX` | *(unset)* | Set to `0` to disable sandbox mode (enables Dolt sync/autopush) |
| `BEADS_DB` | *(unset)* | Explicit database path override |

## Volumes

Mount your project directory to `/data`:

```bash
docker run -v /path/to/my-project:/data beads-ui
```

The `bd` CLI resolves the `.beads/` directory by walking up from `/data`. Your project must contain a `.beads/` directory with either a SQLite database (`*.db`) or Dolt metadata (`metadata.json`).

### Permissions

The container runs as user `node` (UID/GID 1000, built into the Node.js base image). The `bd` binary needs write access to `.beads/` for CRUD operations. If your host files use a different UID, override the container user:

```bash
docker run --user "$(id -u):$(id -g)" -v ./:/data beads-ui
```

### Dolt lock file recovery

If the container exits ungracefully (crash, `docker kill`), Dolt may leave stale lock files that prevent the next start. To recover:

```bash
find .beads/ -name '*.lock' -delete
```

## Multi-arch

Pre-built images support `linux/amd64` and `linux/arm64`.

## Building locally

```bash
docker build -t beads-ui .
docker run -d -p 3000:3000 --init -v ./:/data beads-ui
```

## Security

- Runs as non-root user `node` (UID 1000)
- `bd` is invoked with `--sandbox` by default (no Dolt sync/autopush)
- No shell used for child process spawning (`shell: false`)
- `bd` binary integrity verified via hardcoded SHA256 checksums at build time
- `tini` as PID 1 for proper signal handling
