#!/bin/sh
set -e

PULL_INTERVAL="${DOLT_PULL_INTERVAL:-30}"

# Configure git auth if a token is provided (for private repos).
if [ -n "${GITHUB_TOKEN:-}" ]; then
  git config --global url."https://${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
fi

# Fix permissions on .beads directory if it exists with wrong mode.
if [ -d /data/.beads ]; then
  PERMS=$(stat -c '%a' /data/.beads 2>/dev/null || true)
  if [ -n "$PERMS" ] && [ "$PERMS" != "700" ]; then
    chmod 700 /data/.beads
    echo "beads-ui: fixed /data/.beads permissions ($PERMS -> 700)"
  fi
fi

# On an empty volume, bd bootstrap needs a git repo with an origin that
# contains Dolt data (refs/dolt/data). BEADS_GIT_REMOTE tells us where
# to point it. We fetch refs/dolt/* explicitly because git fetch only
# grabs refs/heads/* by default.
if [ -n "${BEADS_GIT_REMOTE:-}" ] && [ ! -d /data/.git ]; then
  echo "beads-ui: initializing git repo with remote ${BEADS_GIT_REMOTE}"
  git init /data
  git -C /data remote add origin "${BEADS_GIT_REMOTE}"
  git -C /data fetch origin 2>&1 | sed "s|${GITHUB_TOKEN:-__NOTOKEN__}|***|g"
  git -C /data fetch origin '+refs/dolt/*:refs/dolt/*' 2>&1 | sed "s|${GITHUB_TOKEN:-__NOTOKEN__}|***|g"
fi

# Bootstrap: only needed on first start (no DB yet). On subsequent starts
# the DB already exists in the mounted volume — skip bootstrap to avoid
# a misleading "clone failed: database exists" error from Dolt.
if [ -x "$(command -v bd)" ]; then
  if [ -f /data/.beads/metadata.json ]; then
    echo "beads-ui: database already present, skipping bootstrap"
  else
    echo "beads-ui: running bd bootstrap..."
    bd bootstrap --yes 2>&1 | sed "s|${GITHUB_TOKEN:-__NOTOKEN__}|***|g" || echo "beads-ui: bd bootstrap failed (continuing with mounted volume)"
  fi
fi

# Start a background sync loop if DOLT_REMOTE is set (replica mode).
if [ -n "${DOLT_REMOTE:-}" ]; then
  echo "beads-ui: starting dolt pull loop (interval=${PULL_INTERVAL}s)"
  (
    while true; do
      sleep "$PULL_INTERVAL"
      bd dolt pull 2>&1 | sed "s|${GITHUB_TOKEN:-__NOTOKEN__}|***|g" || echo "beads-ui: dolt pull failed (will retry)"
    done
  ) &
fi

exec node /opt/beads-ui/server/index.js "$@"
