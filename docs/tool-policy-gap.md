# Tool Execution Policy Gap Analysis

**Project:** P124 — Codex Subscription Proxy Re-Architecture
**Module:** 2 — Codex Integration & Hardening
**Date:** 2026-03-26

## Current Proxy (codex-proxy) — tool-policy.json

The old `codex-proxy` implements a static tool execution policy via `tool-policy.json` that gates all tool calls from the Codex CLI app-server. It evaluates:

- **Command execution** — deny patterns (regex blocklist for bash, sh, sudo, docker, ssh, curl, etc.) and allow prefixes (whitelist for ls, cat, git, npm, etc.)
- **File changes** — protected paths (~/.ssh, /etc, /var), protected files (openclaw.json, SOUL.md, etc.), and allowed write paths
- **Network access** — `denyNetwork: true` flag blocks all network operations
- **Fail-safe default** — if policy cannot be parsed, all operations are denied (ALL_DENY_CONFIG)
- **Hot reload** — policy file can be reloaded via SIGHUP without restart
- **Audit logging** — all policy decisions (APPROVED/DENIED) are logged with method, reason, and command

The policy is applied at the RPC layer in `app-server.ts`, intercepting `item/commandExecution/requestApproval` and `item/fileChange/requestApproval` messages from the Codex CLI.

## New Proxy (ccproxy-api) — permissions plugin

The `ccproxy-api` `permissions` plugin provides a different mechanism:

- **Interactive approval flow** — creates permission requests with auto-expiring timeouts (default 30s)
- **MCP integration** — `/permission/check` endpoint for Claude Code to query permissions
- **Three responses** — `allow`, `deny`, `pending` (awaits external UI confirmation)
- **SSE event streaming** — real-time permission events for external UI handlers
- **No static deny/allow lists** — no equivalent to `commandDenyPatterns` or `commandAllowPrefixes`
- **No file path protection** — no equivalent to `protectedPaths` or `protectedFiles`
- **No network blocking** — no equivalent to `denyNetwork`

## Gap Summary

| Capability | Old Proxy | New Proxy | Gap? |
|---|---|---|---|
| Command deny patterns (regex) | Yes | No | **GAP** |
| Command allow prefixes | Yes | No | **GAP** |
| Protected file paths | Yes | No | **GAP** |
| Protected file names | Yes | No | **GAP** |
| Network access blocking | Yes | No | **GAP** |
| Fail-safe default deny | Yes | No | **GAP** |
| Hot reload (SIGHUP) | Yes | No | **GAP** |
| Audit logging of decisions | Yes | Yes (via hooks) | Covered |
| Interactive approval | No | Yes | N/A (new feature) |
| MCP integration | No | Yes | N/A (new feature) |

## Assessment

The `ccproxy-api` permissions plugin is designed for **interactive human-in-the-loop approval**, not **static policy enforcement**. It does not replace the static deny/allow gate that `tool-policy.json` provides.

However, this gap has **limited impact in Phase 1** because:

1. The new proxy routes traffic via the **Chat Completions API surface**, not the Codex CLI app-server RPC protocol. Tool execution approval messages (`commandExecution/requestApproval`, `fileChange/requestApproval`) are app-server RPC concepts that do not appear in the Chat Completions or Responses API.

2. Tool execution gating in the Chat Completions flow is controlled by the **client** (Claude Code, Codex CLI), not the proxy. The proxy is a transparent relay for the LLM conversation; tool calls are executed by the client after receiving the model's response.

3. The old proxy's tool policy was specifically designed for the **app-server WebSocket** protocol where the proxy mediates between the client and a local Codex CLI process. The new proxy does not run a local Codex CLI process.

## Recommendation

1. **Phase 1:** Accept the gap. Tool execution gating is a client-side responsibility in the Chat Completions architecture. The proxy does not execute tools.

2. **If server-side tool gating is required in the future:** Implement a `tool_policy` plugin that reads a `tool-policy.json` configuration and intercepts tool-call content in chat completion responses before forwarding to the client. This would be a new plugin, not a modification to the existing permissions plugin.

3. **Flag for review:** This gap should be reviewed during Module 4 (Shadow Validation) to confirm that no tool execution control is lost during the migration.
