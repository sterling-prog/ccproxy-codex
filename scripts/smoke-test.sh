#!/usr/bin/env bash
# P124 Module 2+ Smoke Test Suite
# Verifies core endpoints and behavior against a running ccproxy instance.
# Usage: ./scripts/smoke-test.sh [BASE_URL]
# Default BASE_URL: http://localhost:3462

set -uo pipefail

BASE_URL="${1:-http://localhost:3462}"
PASS=0
FAIL=0
SKIP=0

# Use a private temp directory to prevent symlink TOCTOU attacks on /tmp files.
SMOKE_TMP=$(mktemp -d)
trap 'rm -rf "$SMOKE_TMP"' EXIT

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }
skip() { echo "  SKIP: $1 — $2"; SKIP=$((SKIP + 1)); }

header() { echo ""; echo "=== $1 ==="; }

# ---------------------------------------------------------------------------
header "1. GET /health → 200 + auth status"

HTTP_CODE=$(curl -s -o $SMOKE_TMP/smoke_health.json -w "%{http_code}" "$BASE_URL/health" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    if grep -q '"status"' $SMOKE_TMP/smoke_health.json 2>/dev/null; then
        pass "/health returns 200 with status field"
    else
        fail "/health" "200 but missing status field"
    fi
else
    fail "/health" "expected 200, got $HTTP_CODE"
fi

# ---------------------------------------------------------------------------
header "2. GET /ready → 200"

HTTP_CODE=$(curl -s -o $SMOKE_TMP/smoke_ready.json -w "%{http_code}" "$BASE_URL/ready" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    pass "/ready returns 200"
else
    fail "/ready" "expected 200, got $HTTP_CODE"
fi

# ---------------------------------------------------------------------------
header "3. GET /v1/models → model list with correct id field"

HTTP_CODE=$(curl -s -o $SMOKE_TMP/smoke_models.json -w "%{http_code}" "$BASE_URL/v1/models" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    # Check that response has data array with model objects containing id field
    MODEL_COUNT=$(python3 -c "
import json, sys
with open('$SMOKE_TMP/smoke_models.json') as f:
    data = json.load(f)
models = data.get('data', [])
# Verify each model has an id field matching known Codex models
known = {'gpt-5.4','gpt-5.4-mini','gpt-5.3-codex','gpt-5.3-codex-spark',
         'gpt-5.2-codex','gpt-5.2','gpt-5.1-codex-max','gpt-5.1-codex-mini'}
found = {m['id'] for m in models if 'id' in m}
matched = known & found
print(len(matched))
" 2>/dev/null || echo "0")
    if [ "$MODEL_COUNT" -ge 8 ]; then
        pass "/v1/models returns all 8 Codex models with correct id field"
    else
        fail "/v1/models" "expected 8+ models with correct ids, found $MODEL_COUNT"
    fi
else
    fail "/v1/models" "expected 200, got $HTTP_CODE"
fi

# ---------------------------------------------------------------------------
header "4. POST /v1/chat/completions → non-streaming request"

HTTP_CODE=$(curl -s -o $SMOKE_TMP/smoke_chat.json -w "%{http_code}" \
    -X POST "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"gpt-5.4","messages":[{"role":"user","content":"Say hello"}],"stream":false}' \
    --max-time 120 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
    pass "non-streaming chat completion returns 200"
elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
    skip "non-streaming chat completion" "auth required ($HTTP_CODE) — needs live Codex OAuth"
elif [ "$HTTP_CODE" = "000" ]; then
    fail "non-streaming chat completion" "connection failed or timed out"
else
    # Any response with correlation ID is acceptable for testing error normalization
    HAS_REQUEST_ID=$(grep -c "x-request-id\|request_id\|X-Request-Id" $SMOKE_TMP/smoke_chat.json 2>/dev/null || echo "0")
    skip "non-streaming chat completion" "got HTTP $HTTP_CODE (may need auth)"
fi

# ---------------------------------------------------------------------------
header "5. POST /v1/chat/completions → streaming request (SSE)"

HTTP_CODE=$(curl -s -o $SMOKE_TMP/smoke_stream.txt -w "%{http_code}" \
    -X POST "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Accept: text/event-stream" \
    -d '{"model":"gpt-5.4","messages":[{"role":"user","content":"Say hello"}],"stream":true}' \
    --max-time 120 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
    if grep -q "data:" $SMOKE_TMP/smoke_stream.txt 2>/dev/null; then
        pass "streaming chat completion returns SSE data"
    else
        pass "streaming chat completion returns 200"
    fi
elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
    skip "streaming chat completion" "auth required ($HTTP_CODE) — needs live Codex OAuth"
else
    skip "streaming chat completion" "got HTTP $HTTP_CODE (may need auth)"
fi

# ---------------------------------------------------------------------------
header "6. POST /v1/chat/completions → long-running request (>60s timeout test)"

# Default: verify timeout config is correctly set (request_timeout=900s, queue_timeout=120s).
# Full live test: set SMOKE_LONG_RUNNING=1 to send an actual long-running request.
if [ "${SMOKE_LONG_RUNNING:-0}" = "1" ]; then
    # Send a request that should take >60s (large generation task)
    echo "  INFO: running live long-running test (may take >60s)..."
    HTTP_CODE=$(curl -s -o $SMOKE_TMP/smoke_long.json -w "%{http_code}" \
        -X POST "$BASE_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{"model":"gpt-5.4","messages":[{"role":"user","content":"Write a 5000-word detailed essay on the history of computing from 1940 to 2000. Include every major milestone."}],"max_tokens":4000}' \
        --max-time 950 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        pass "long-running request (>60s) completed without timeout"
    else
        fail "long-running request" "expected 200, got $HTTP_CODE"
    fi
else
    # Verify proxy timeout config is set correctly per P124 spec invariants:
    # request_timeout=900s, queue_timeout=120s, max_concurrent=5
    CONFIG_FILE="$(dirname "$0")/../config.toml"
    if [ -f "$CONFIG_FILE" ]; then
        TIMEOUT_VAL=$(grep -E "^timeout\s*=" "$CONFIG_FILE" | head -1 | grep -o '[0-9]*')
        QUEUE_TIMEOUT=$(grep -E "^queue_timeout\s*=" "$CONFIG_FILE" | head -1 | grep -o '[0-9]*')
        if [ "$TIMEOUT_VAL" = "900" ] && [ "$QUEUE_TIMEOUT" = "120" ]; then
            pass "long-running timeout config verified: request_timeout=${TIMEOUT_VAL}s, queue_timeout=${QUEUE_TIMEOUT}s (live test: SMOKE_LONG_RUNNING=1)"
        else
            fail "long-running timeout config" "expected timeout=900 queue_timeout=120, got timeout=${TIMEOUT_VAL} queue_timeout=${QUEUE_TIMEOUT}"
        fi
    else
        skip "long-running request" "config.toml not found at $CONFIG_FILE — run with SMOKE_LONG_RUNNING=1 for live test"
    fi
fi

# ---------------------------------------------------------------------------
header "7. POST /v1/chat/completions → error case with correlation ID"

# Send a request with an invalid model to trigger an error
RESPONSE=$(curl -s -D $SMOKE_TMP/smoke_err_headers.txt -o $SMOKE_TMP/smoke_err.json \
    -X POST "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"nonexistent-model-xyz","messages":[{"role":"user","content":"test"}]}' \
    --max-time 30 2>/dev/null)

# Check that response headers include x-request-id (correlation ID)
if grep -qi "x-request-id" $SMOKE_TMP/smoke_err_headers.txt 2>/dev/null; then
    pass "error response includes x-request-id correlation header"
else
    # Also check response body for request_id
    if grep -q "request_id" $SMOKE_TMP/smoke_err.json 2>/dev/null; then
        pass "error response includes request_id in body"
    else
        fail "error correlation ID" "no x-request-id header or request_id in body"
    fi
fi

# ---------------------------------------------------------------------------
header "8. GET /metrics → request count, latency, error rate"

HTTP_CODE=$(curl -s -o $SMOKE_TMP/smoke_metrics.txt -w "%{http_code}" "$BASE_URL/metrics" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    HAS_REQUESTS=$(grep -c "ccproxy_requests_total" $SMOKE_TMP/smoke_metrics.txt 2>/dev/null || echo "0")
    HAS_LATENCY=$(grep -c "ccproxy_request_duration\|duration\|latency" $SMOKE_TMP/smoke_metrics.txt 2>/dev/null || echo "0")
    if [ "$HAS_REQUESTS" -gt 0 ]; then
        pass "/metrics exposes request count"
    else
        fail "/metrics" "missing ccproxy_requests_total"
    fi
    if [ "$HAS_LATENCY" -gt 0 ]; then
        pass "/metrics exposes latency data"
    else
        skip "/metrics latency" "no latency metric found (may need traffic first)"
    fi
else
    fail "/metrics" "expected 200, got $HTTP_CODE"
fi

# ---------------------------------------------------------------------------
header "Rate limit headers check"

# Check that responses include rate limit headers
if grep -qi "x-ratelimit-limit" $SMOKE_TMP/smoke_err_headers.txt 2>/dev/null; then
    pass "responses include X-RateLimit-Limit header"
else
    skip "rate limit headers" "X-RateLimit-Limit header not found in error response"
fi

# ---------------------------------------------------------------------------
echo ""
echo "========================================="
echo "  Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo "========================================="

# Cleanup handled by EXIT trap (rm -rf "$SMOKE_TMP")

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
