#!/bin/sh
set -e

PULL_INTERVAL="${DOLT_PULL_INTERVAL:-30}"

# Bootstrap the database if no .beads/ directory exists yet.
# When a volume with an existing DB is mounted, bootstrap validates and skips.
if [ -x "$(command -v bd)" ]; then
  echo "beads-ui: running bd bootstrap..."
  bd bootstrap --yes -C /data 2>&1 || echo "beads-ui: bd bootstrap failed (continuing with mounted volume)"
fi

# Start a background sync loop if DOLT_REMOTE is set (replica mode).
if [ -n "${DOLT_REMOTE:-}" ]; then
  echo "beads-ui: starting dolt pull loop (interval=${PULL_INTERVAL}s)"
  (
    while true; do
      sleep "$PULL_INTERVAL"
      bd dolt pull -C /data 2>&1 || echo "beads-ui: dolt pull failed (will retry)"
    done
  ) &
fi

exec node /opt/beads-ui/server/index.js "$@"
