# beads-ui — Docker image
# Bundles the Node.js UI server with the bd CLI binary (Go, from gastownhall/beads).
#
# Build:
#   docker build -t beads-ui .
#   docker build --build-arg BD_VERSION=1.3.2 -t beads-ui .
#
# Run:
#   docker run -d -p 3000:3000 -v ./my-project:/data beads-ui

# ---------------------------------------------------------------------------
# Stage 1: Download and verify the bd binary
# ---------------------------------------------------------------------------
FROM node:22-slim AS downloader

ARG BD_VERSION=1.3.2
ARG TARGETARCH

# Hardcoded checksums — update these when bumping BD_VERSION
ARG BD_SHA256_AMD64=c6ea3281f6ff82628351b2d0967c9eb85862c8a0ec0ebc24e63e645c8b02462e
ARG BD_SHA256_ARM64=39b34a1246b7216031a98ae838c785a7dbba29cf9f50f109114ac462a4b85e7c

RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/bd

RUN set -eux; \
    TARBALL="beads_${BD_VERSION}_linux_${TARGETARCH}.tar.gz"; \
    URL="https://github.com/gastownhall/beads/releases/download/v${BD_VERSION}/${TARBALL}"; \
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

# The runtime starts Node directly. Package managers are build-only tools.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
    && rm -f /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
        /usr/local/bin/yarn /usr/local/bin/yarnpkg /usr/local/bin/pnpm /usr/local/bin/pnpx

# node:22-slim ships with user "node" (UID/GID 1000) — reuse it

COPY --from=downloader /usr/local/bin/bd /usr/local/bin/bd
COPY --from=builder /build/node_modules /opt/beads-ui/node_modules
COPY --from=builder /build/package.json /opt/beads-ui/package.json
COPY --from=builder /build/app /opt/beads-ui/app
COPY --from=builder /build/server /opt/beads-ui/server
COPY --from=builder /build/bin /opt/beads-ui/bin

COPY docker-entrypoint.sh /opt/beads-ui/docker-entrypoint.sh

ENV HOST=0.0.0.0
ENV PORT=3000
ENV BD_BIN=/usr/local/bin/bd
ENV NODE_ENV=production
ENV DOLT_PULL_INTERVAL=30

WORKDIR /data

RUN chown node:node /data

USER node

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD node -e "fetch('http://localhost:${PORT}/healthz').then(r=>{if(!r.ok)throw 1}).catch(()=>process.exit(1))"

ENTRYPOINT ["tini", "--", "/opt/beads-ui/docker-entrypoint.sh"]
