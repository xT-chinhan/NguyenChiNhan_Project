"""Authenticated single-owner WebSocket admission before accept."""

from dataclasses import dataclass
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, WebSocket, WebSocketException

from navcore.api.auth import Principal, authenticate, bearer
from navcore.api.errors import ApiError
from navcore.runtime.sessions import TERMINAL
from navcore.runtime.streaming import StreamConnection

router = APIRouter(prefix="/v1/sessions")


@dataclass(frozen=True)
class StreamIdentity:
    principal: Principal
    revalidate: object


async def stream_identity(websocket: WebSocket):
    try:
        token = bearer(websocket.headers)
        owner = await authenticate(websocket.app, token)
        if owner.role != "device":
            raise ApiError("ROLE_FORBIDDEN", 403, "Device access required")
    except ApiError:
        raise WebSocketException(code=1008) from None

    async def revalidate():
        try:
            current = await authenticate(websocket.app, token)
            return current.role == "device" and current.device_id == owner.device_id
        except ApiError:
            return False

    return StreamIdentity(owner, revalidate)


@router.websocket("/{session_id}/stream")
async def stream(
    session_id: UUID, websocket: WebSocket, identity: StreamIdentity = Depends(stream_identity)
):
    await serve_stream(session_id, websocket, identity)


async def serve_stream(session_id, websocket, identity, *, accepted=False):
    app = websocket.app
    registry = app.state.sessions
    await registry.expire()
    try:
        session = registry.owned(session_id, identity.principal.device_id)
    except ApiError:
        await websocket.close(code=1008)
        return
    async with session.lock:
        if session.connection is not None:
            await websocket.close(code=1008)
            return
        if not accepted:
            await websocket.accept()
        if session.state in TERMINAL:
            await websocket.send_json(
                {
                    "type": "error",
                    "code": "SESSION_TERMINAL",
                    "message": "Session is terminal",
                    "request_id": str(uuid4()),
                }
            )
            await websocket.close(code=1008)
            return
        connection = StreamConnection(
            websocket, session, app.state.worker, app.state.vision, identity.revalidate
        )
        session.connection = connection
    await connection.run()
