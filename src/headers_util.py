"""Hop-by-hop and proxy-control header helpers."""

from __future__ import annotations

# RFC 7230 hop-by-hop headers — must not be forwarded.
HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "host",
    "content-length",  # fetch recalculates from body
}

# Headers consumed by this gateway; never forward upstream.
GATEWAY_HEADERS = {
    "x-forward-to",
    "x-forward-host",
    "x-target-url",
    "x-route",
    "x-gateway-key",
    "x-gateway-token",
}

# Query params consumed by this gateway.
GATEWAY_QUERY_KEYS = {
    "__target",
    "__url",
    "__route",
    "__host",
}


def is_forwardable_request_header(name: str) -> bool:
    lower = name.lower()
    if lower in HOP_BY_HOP or lower in GATEWAY_HEADERS:
        return False
    # Strip Authorization only when it is used as gateway auth —
    # handled separately by the caller when GATEWAY_TOKEN is set.
    return True


def is_forwardable_response_header(name: str) -> bool:
    return name.lower() not in HOP_BY_HOP
