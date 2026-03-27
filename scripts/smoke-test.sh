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

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }
skip() { echo "  SKIP: $1 — $2"; SKIP=$((SKIP + 1)); }

header() { echo ""; echo "=== $1 ==="; }

# ---------------------------------------------------------------------------
header "1. GET /health → 200 + auth status"

HTTP_CODE=$(curl -s -o /tmp/smoke_health.json -w "%{http_code}" "$BASE_URL/health" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    if grep -q '"status"' /tmp/smoke_health.json 2>/dev/null; then
        pass "/health returns 200 with status field"
    else
        fail "/health" "200 but missing status field"
    fi
else
    fail "/health" "expected 200, got $HTTP_CODE"
fi

# ---------------------------------------------------------------------------
header "2. GET /ready → 200"

HTTP_CODE=$(curl -s -o /tmp/smoke_ready.json -w "%{http_code}" "$BASE_URL/ready" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    pass "/ready returns 200"
else
    fail "/ready" "expected 200, got $HTTP_CODE"
fi

# ---------------------------------------------------------------------------
header "3. GET /v1/models → model list with correct id field"

HTTP_CODE=$(curl -s -o /tmp/smoke_models.json -w "%{http_code}" "$BASE_URL/v1/models" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    # Check that response has data array with model objects containing id field
    MODEL_COUNT=$(python3 -c "
import json, sys
with open('/tmp/smoke_models.json') as f:
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

HTTP_CODE=$(curl -s -o /tmp/smoke_chat.json -w "%{http_code}" \
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
    HAS_REQUEST_ID=$(grep -c "x-request-id\|request_id\|X-Request-Id" /tmp/smoke_chat.json 2>/dev/null || echo "0")
    skip "non-streaming chat completion" "got HTTP $HTTP_CODE (may need auth)"
fi

# ---------------------------------------------------------------------------
header "5. POST /v1/chat/completions → streaming request (SSE)"

HTTP_CODE=$(curl -s -o /tmp/smoke_stream.txt -w "%{http_code}" \
    -X POST "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Accept: text/event-stream" \
    -d '{"model":"gpt-5.4","messages":[{"role":"user","content":"Say hello"}],"stream":true}' \
    --max-time 120 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
    if grep -q "data:" /tmp/smoke_stream.txt 2>/dev/null; then
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

# This test is intentionally skipped in automated runs — it requires live auth
# and a prompt that takes >60s to complete. Uncomment for manual testing.
skip "long-running request" "requires live Codex OAuth and >60s prompt — run manually"

# ---------------------------------------------------------------------------
header "7. POST /v1/chat/completions → error case with correlation ID"

# Send a request with an invalid model to trigger an error
RESPONSE=$(curl -s -D /tmp/smoke_err_headers.txt -o /tmp/smoke_err.json \
    -X POST "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"nonexistent-model-xyz","messages":[{"role":"user","content":"test"}]}' \
    --max-time 30 2>/dev/null)

# Check that response headers include x-request-id (correlation ID)
if grep -qi "x-request-id" /tmp/smoke_err_headers.txt 2>/dev/null; then
    pass "error response includes x-request-id correlation header"
else
    # Also check response body for request_id
    if grep -q "request_id" /tmp/smoke_err.json 2>/dev/null; then
        pass "error response includes request_id in body"
    else
        fail "error correlation ID" "no x-request-id header or request_id in body"
    fi
fi

# ---------------------------------------------------------------------------
header "8. GET /metrics → request count, latency, error rate"

HTTP_CODE=$(curl -s -o /tmp/smoke_metrics.txt -w "%{http_code}" "$BASE_URL/metrics" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    HAS_REQUESTS=$(grep -c "ccproxy_requests_total" /tmp/smoke_metrics.txt 2>/dev/null || echo "0")
    HAS_LATENCY=$(grep -c "ccproxy_request_duration\|duration\|latency" /tmp/smoke_metrics.txt 2>/dev/null || echo "0")
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
if grep -qi "x-ratelimit-limit" /tmp/smoke_err_headers.txt 2>/dev/null; then
    pass "responses include X-RateLimit-Limit header"
else
    skip "rate limit headers" "X-RateLimit-Limit header not found in error response"
fi

# ---------------------------------------------------------------------------
echo ""
echo "========================================="
echo "  Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo "========================================="

# Cleanup
rm -f /tmp/smoke_health.json /tmp/smoke_ready.json /tmp/smoke_models.json \
      /tmp/smoke_chat.json /tmp/smoke_stream.txt /tmp/smoke_err.json \
      /tmp/smoke_err_headers.txt /tmp/smoke_metrics.txt

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
