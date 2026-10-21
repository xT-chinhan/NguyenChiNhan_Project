"""Device-owned REST sessions; catalog snapshots are loaded off the event loop."""

from datetime import datetime
from functools import partial
from uuid import UUID

from fastapi import APIRouter, Depends, Request, Response

from navcore.api.auth import Principal, device
from navcore.api.catalog import require_vision
from navcore.core.types import Mode, SensorProfile, State
from navcore.schemas.catalog import Contract, SessionCreate
from navcore.storage.catalog import load_published

router = APIRouter(prefix="/v1/sessions")


class SessionView(Contract):
    id: UUID
    state: State
    mode: Mode
    route_id: UUID
    route_revision: int
    last_confirmed_seq: int
    target_seq: int
    checkpoint_count: int
    stream_path: str
    expires_at: datetime


def route_loader(request: Request):
    vision = require_vision(request.app)
    return partial(
        load_published, request.app.state.engine, encoder_fingerprint=vision.encoder_fingerprint
    )


@router.post("", status_code=201, response_model=SessionView)
async def create_session(
    values: SessionCreate,
    request: Request,
    owner: Principal = Depends(device),
    loader=Depends(route_loader),
):
    app = request.app
    sensor = SensorProfile(
        Mode(values.sensor.mode),
        getattr(values.sensor, "depth_scale_m", None),
        getattr(values.sensor, "calibration_id", None),
    )
    session = await app.state.sessions.create(owner.device_id, values.route_id, sensor, loader)
    return session.snapshot()


@router.get("/{session_id}", response_model=SessionView)
async def get_session(session_id: UUID, request: Request, owner: Principal = Depends(device)):
    registry = request.app.state.sessions
    await registry.expire()
    session = registry.owned(session_id, owner.device_id)
    async with session.lock:
        return session.snapshot()


@router.delete("/{session_id}", status_code=204)
async def delete_session(session_id: UUID, request: Request, owner: Principal = Depends(device)):
    registry = request.app.state.sessions
    await registry.expire()
    session = registry.owned(session_id, owner.device_id)
    async with session.lock:
        session.invalidate("STOP", stop=True)
        if session.connection is not None:
            session.connection.terminate(1000, "STOP")
    return Response(status_code=204)
