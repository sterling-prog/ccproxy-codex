"""Rate limiting middleware for ccproxy.

Implements a simple sliding-window rate limiter. Default: 60 requests/minute
as required by P124 spec (matches current codex-proxy behavior).
"""

import time
from collections import deque

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

from ccproxy.core.logging import get_logger

logger = get_logger(__name__)


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Sliding-window rate limiter.

    Applies a global rate limit across all incoming requests.
    Health/metrics endpoints are excluded to avoid interfering with monitoring.
    """

    EXCLUDED_PREFIXES = ("/health", "/ready", "/metrics")

    def __init__(self, app, max_requests: int = 60, window_seconds: int = 60):
        super().__init__(app)
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self._timestamps: deque[float] = deque()

    async def dispatch(self, request: Request, call_next) -> Response:
        # Skip rate limiting for health/metrics endpoints
        path = request.url.path
        if any(path.startswith(p) for p in self.EXCLUDED_PREFIXES):
            return await call_next(request)

        now = time.monotonic()

        # Evict expired entries
        cutoff = now - self.window_seconds
        while self._timestamps and self._timestamps[0] < cutoff:
            self._timestamps.popleft()

        if len(self._timestamps) >= self.max_requests:
            retry_after = int(self._timestamps[0] + self.window_seconds - now) + 1
            request_id = getattr(getattr(request, "state", None), "request_id", "unknown")
            logger.warning(
                "rate_limit_exceeded",
                request_id=request_id,
                method=request.method,
                path=path,
                current_count=len(self._timestamps),
                max_requests=self.max_requests,
                window_seconds=self.window_seconds,
            )
            return JSONResponse(
                status_code=429,
                content={
                    "error": {
                        "message": f"Rate limit exceeded: {self.max_requests} requests per {self.window_seconds}s",
                        "type": "rate_limit_error",
                        "code": "rate_limit_exceeded",
                    }
                },
                headers={"Retry-After": str(retry_after)},
            )

        self._timestamps.append(now)
        response = await call_next(request)

        # Add rate limit headers
        remaining = self.max_requests - len(self._timestamps)
        response.headers["X-RateLimit-Limit"] = str(self.max_requests)
        response.headers["X-RateLimit-Remaining"] = str(max(0, remaining))
        response.headers["X-RateLimit-Reset"] = str(int(now + self.window_seconds))

        return response
