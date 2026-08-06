# CLAUDE.md — beads-ui

Local web UI for the [beads](https://github.com/steveyegge/beads) CLI issue tracker.
Express + WebSocket server, lit-html SPA frontend. By [Maximilian Antoni](https://github.com/mantoni).

## Context

| Fact | Value |
|---|---|
| Stack | Node.js >=22, Express 5, WebSocket (ws), lit-html, esbuild |
| Entry point | `bin/bdui.js` → `server/cli/index.js` |
| Server | `server/index.js` — HTTP + WS on `HOST:PORT` (default `127.0.0.1:3000`) |
| Frontend | `app/` — SPA bundled by `scripts/build-frontend.js` via esbuild |
| DB resolution | `server/db.js` — walks up from cwd looking for `.beads/*.db` or `.beads/metadata.json` |
| Tests | vitest (`npm test`), extensive unit + integration coverage |
| Lint/format | eslint + prettier (`npm run all` for full check) |
| Remote | https://github.com/mantoni/beads-ui |

## Architecture

```
bin/bdui.js          CLI entry (start/stop/status/open)
server/
  cli/               CLI command parsing, daemon management
  index.js           HTTP server bootstrap, DB watcher setup
  app.js             Express app (serves static app/)
  db.js              .beads DB/metadata resolution (walk-up)
  ws.js              WebSocket server — issue CRUD, subscriptions, mutations
  watcher.js         fs.watch on .beads dir for live reload
  registry-watcher.js  global workspace registry (~/.beads-ui/)
  subscriptions.js   list subscription refresh engine
app/
  main.js            SPA entry, router, state management
  views/             lit-html view components (list, board, epics, detail, dialogs)
  data/              stores, subscriptions, providers
  utils/             badges, markdown, status helpers
  styles.css         global styles
  index.html         shell page
```

Key design: server watches `.beads/` for file changes → debounced WS push to connected clients.
Multi-workspace support via registry file at `~/.beads-ui/registry.json`.

## Development

```bash
npm install
npm run build          # bundle frontend
npm run start          # start server with --debug
npm test               # vitest run
npm run all            # lint + tsc + test + prettier
```

## Environment variables

- `BD_BIN` — path to `bd` binary
- `BEADS_DB` — explicit DB path override
- `HOST` / `PORT` — bind address/port (also via `--host`/`--port` CLI flags)
- `BDUI_RUNTIME_DIR` — PID/log directory override

## Project scope

Contribute Docker support to beads-ui for portable, containerized deployment.
Upstream proposal: https://github.com/mantoni/beads-ui/issues/107 (awaiting maintainer response).
Implementation proceeds on this repo. If accepted → PR to mantoni/beads-ui. If not → maintain our own image.

Deliverables: Dockerfile, docker-compose.yml, CI workflow, DOCKER.md, graceful shutdown handler.
Deployment (Traefik, volumes, auth) is out of scope — that's the infra project.
