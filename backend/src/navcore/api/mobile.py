"""Same-origin mobile page and browser WebSocket authentication before session access."""

import asyncio
import json
import re
from pathlib import Path
from uuid import UUID

from fastapi import APIRouter, HTTPException, WebSocket
from fastapi.responses import FileResponse
from starlette.websockets import WebSocketDisconnect

from navcore.api.auth import authenticate
from navcore.api.errors import ApiError
from navcore.api.stream import StreamIdentity, serve_stream

router = APIRouter()
ASSETS = Path(__file__).resolve().parents[1] / "web"
HEADERS = {
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Permissions-Policy": "camera=(self), microphone=()",
    "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self'; "
    "connect-src 'self'; media-src 'self' blob:; img-src 'self' data:; "
    "object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
}


@router.get("/mobile", include_in_schema=False)
async def page():
    return FileResponse(ASSETS / "index.html", headers=HEADERS)


@router.get("/mobile/{asset}", include_in_schema=False)
async def asset(asset: str):
    if asset not in {"client.js", "guard.js", "style.css", "corridor-guide.html", "corridor-start.jpg", "corridor-end.jpg"}:
        raise HTTPException(404)
    return FileResponse(ASSETS / asset, headers=HEADERS)


@router.websocket("/v1/mobile/sessions/{session_id}/stream")
async def browser_stream(session_id: UUID, websocket: WebSocket):
    scheme = "https" if websocket.url.scheme == "wss" else "http"
    if websocket.headers.get("origin") != f"{scheme}://{websocket.url.netloc}":
        await websocket.close(code=1008)
        return
    await websocket.accept()
    try:
        # The browser cannot set Authorization headers; no credential enters a URL.
        incoming = await asyncio.wait_for(websocket.receive(), 3)
        raw = incoming.get("text")
        if not isinstance(raw, str) or len(raw.encode()) > 512:
            raise ValueError
        value = json.loads(raw)
        if (
            not isinstance(value, dict)
            or set(value) != {"type", "token"}
            or value["type"] != "auth"
            or not isinstance(value["token"], str)
            or not re.fullmatch(r"navdev_[A-Za-z0-9_-]{43}", value["token"])
        ):
            raise ValueError
        token = value["token"]
        owner = await asyncio.wait_for(authenticate(websocket.app, token), 3)
        if owner.role != "device":
            raise ValueError
    except (TimeoutError, ValueError, ApiError, WebSocketDisconnect, RuntimeError):
        await websocket.close(code=1008)
        return

    async def revalidate():
        current = await authenticate(websocket.app, token)
        return current.role == "device" and current.device_id == owner.device_id

    await serve_stream(session_id, websocket, StreamIdentity(owner, revalidate), accepted=True)
