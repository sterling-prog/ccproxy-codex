# CCProxy Codex Fork — P124 Module 1: Fork & Reduction

Forked from: `CaddyGlow/ccproxy-api` at tag `v0.2.6`
Fork target: `sterling-prog/ccproxy-codex`
Branch: `build/P124-ccproxy-codex`
Date: 2026-03-26

## Purpose

Stripped-down proxy for OpenAI Codex API access via claude-code OAuth.
Runs on port 3462. Phase 1 has only the Codex provider active;
Claude Code adapter is present but disabled for Phase 2 enablement.

---

## Plugins Removed

| Plugin | Reason |
|---|---|
| `copilot` | GitHub Copilot provider — not needed for this deployment |
| `credential_balancer` | Multi-credential rotation — single-account setup |
| `analytics` | DuckDB-backed request analytics — operational overhead not needed |
| `dashboard` | Web UI dashboard — not needed |
| `duckdb_storage` | DuckDB storage backend — removed with analytics/dashboard |
| `pricing` | Token pricing calculator — not needed |
| `docker` | Docker container routing for Claude — not needed |

---

## Plugins Retained

### Primary Provider
- `codex` — OpenAI Codex API proxy (Phase 1 active)
- `oauth_codex` — OAuth token management for Codex

### Claude Code Adapter (Phase 2, disabled in config)
- `claude_api` — Claude API provider
- `claude_sdk` — Claude SDK provider
- `claude_shared` — Shared Claude utilities
- `oauth_claude` — OAuth token management for Claude

### Operational
- `access_log` — Structured HTTP access logging
- `request_tracer` — JSON request/response traces for debugging
- `max_tokens` — Token limit enforcement
- `permissions` — Permission/scope enforcement
- `metrics` — Prometheus metrics endpoint
- `command_replay` — Generates curl replay commands for debugging

---

## Code Changes Made During Reduction

1. **`ccproxy/plugins/access_log/plugin.py`** — Moved hard import of
   `ccproxy.plugins.analytics.ingest.AnalyticsIngestService` to a lazy
   import inside a `try/except ImportError` block. The analytics integration
   was already optional at runtime; now the import is also optional.

2. **`ccproxy/testing/endpoints/config.py`** — Removed hard import of
   `ccproxy.plugins.copilot` and the `copilot` entries in `PROVIDER_CONFIGS`
   and `PROVIDER_TOOL_ACCUMULATORS`. This file is only used by the endpoint
   testing harness.

3. **`ccproxy/config/settings.py`** — Removed `"copilot"` from
   `DEFAULT_ENABLED_PLUGINS` (the fallback list used when no config file exists).

4. **`pyproject.toml`** — Removed entry points for the 7 deleted plugins.

All `pricing` imports in `codex/hooks.py`, `codex/plugin.py`,
`claude_api/hooks.py`, and `claude_api/plugin.py` were already lazy
(inside `try/except` blocks) — no changes needed there.

---

## Deployment Config

`config.toml` (not tracked in git) is the deployment config for port 3462.
Key settings:

- Port: 3462, host: 127.0.0.1
- `enabled_plugins`: codex, oauth_codex, access_log, request_tracer,
  max_tokens, permissions, metrics, command_replay
- Claude Code plugins explicitly disabled: `enabled = false`
- Scheduler pricing updates disabled
- HTTP: timeout=900s, max_concurrent=5, queue_depth=20, queue_timeout=120
- Rate: scheduler max_concurrent_tasks=5

To start (dev only, do not start in production without PM2 setup):
```
uv run ccproxy serve --config config.toml
```

---

## Upstream Compatibility

The upstream plugin registry uses filesystem discovery — it finds plugins
by scanning `ccproxy/plugins/*/plugin.py`. Removing the directories is
sufficient; no central registry file needed updating beyond `pyproject.toml`
entry points (which are used for installed-package mode).
