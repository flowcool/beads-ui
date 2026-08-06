# beads-ui — Docker image
# Bundles the Node.js UI server with the bd CLI binary (Go, from steveyegge/beads).
#
# Build:
#   docker build -t beads-ui .
#   docker build --build-arg BD_VERSION=1.1.2 -t beads-ui .
#
# Run:
#   docker run -d -p 3000:3000 -v ./my-project:/data beads-ui

# ---------------------------------------------------------------------------
# Stage 1: Download and verify the bd binary
# ---------------------------------------------------------------------------
FROM node:22-slim AS downloader

ARG BD_VERSION=1.1.2
ARG TARGETARCH

# Hardcoded checksums — update these when bumping BD_VERSION
ARG BD_SHA256_AMD64=a72d71ed374955dc9f83a0f90b54bd7b6a0016709dd1676ae2e368651ed401c2
ARG BD_SHA256_ARM64=a134015faf4be0a43f8681a8d602eaf0b7c255c957f09d3c933257c8c92fdd10

RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/bd

RUN set -eux; \
    TARBALL="beads_${BD_VERSION}_linux_${TARGETARCH}.tar.gz"; \
    URL="https://github.com/steveyegge/beads/releases/download/v${BD_VERSION}/${TARBALL}"; \
    curl -fsSL -o "${TARBALL}" "${URL}"; \
    # Select the correct checksum for this architecture
    if [ "${TARGETARCH}" = "amd64" ]; then \
      EXPECTED="${BD_SHA256_AMD64}"; \
    elif [ "${TARGETARCH}" = "arm64" ]; then \
      EXPECTED="${BD_SHA256_ARM64}"; \
    else \
      echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1; \
    fi; \
    echo "${EXPECTED}  ${TARBALL}" | sha256sum -c -; \
    tar xzf "${TARBALL}"; \
    mv bd /usr/local/bin/bd; \
    chmod +x /usr/local/bin/bd; \
    bd --version

# ---------------------------------------------------------------------------
# Stage 2: Build the frontend bundle and prune dev dependencies
# ---------------------------------------------------------------------------
FROM node:22-slim AS builder

WORKDIR /build

COPY package.json package-lock.json ./
RUN npm ci

COPY app/ ./app/
COPY server/ ./server/
COPY bin/ ./bin/
COPY scripts/ ./scripts/

RUN node scripts/build-frontend.js
RUN npm prune --omit=dev

# Remove test files from the production image
RUN find . -name '*.test.js' -delete \
    && find . -name '*.test.*.js' -delete

# ---------------------------------------------------------------------------
# Stage 3: Runtime image
# ---------------------------------------------------------------------------
FROM node:22-slim AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends git tini \
    && rm -rf /var/lib/apt/lists/*

# node:22-slim ships with user "node" (UID/GID 1000) — reuse it

COPY --from=downloader /usr/local/bin/bd /usr/local/bin/bd
COPY --from=builder /build/node_modules /opt/beads-ui/node_modules
COPY --from=builder /build/package.json /opt/beads-ui/package.json
COPY --from=builder /build/app /opt/beads-ui/app
COPY --from=builder /build/server /opt/beads-ui/server
COPY --from=builder /build/bin /opt/beads-ui/bin

ENV HOST=0.0.0.0
ENV PORT=3000
ENV BD_BIN=/usr/local/bin/bd
ENV NODE_ENV=production

WORKDIR /data

RUN chown node:node /data

USER node

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD node -e "fetch('http://localhost:${PORT}/healthz').then(r=>{if(!r.ok)throw 1}).catch(()=>process.exit(1))"

ENTRYPOINT ["tini", "--", "node", "/opt/beads-ui/server/index.js"]
