"""Explicit vision/clock seams for runtime tests; never an application mode."""

import base64
import io
from contextlib import asynccontextmanager, contextmanager
from uuid import uuid4

import numpy as np
from PIL import Image

from navcore.core.policy import BASELINE
from navcore.core.types import Action, Checkpoint, Mode, Reference, RouteSnapshot, SensorProfile
from navcore.runtime.sessions import RuntimeSession
from navcore.schemas.stream import Frame
from navcore.vision.pipeline import VisionResult


class FakeClock:
    def __init__(self):
        self.value = 100.0

    def __call__(self):
        return self.value

    def advance(self, seconds):
        self.value += seconds


def vector(index=0):
    result = np.zeros(768, dtype=np.float32)
    result[index] = 1
    return result


def route():
    points = []
    for seq, action in enumerate((Action.STRAIGHT, Action.LEFT, Action.ARRIVE)):
        refs = tuple(
            Reference(str(uuid4()), str(uuid4()), tuple(vector(seq)), "a" * 64) for _ in range(3)
        )
        points.append(Checkpoint(str(uuid4()), seq, action, "Test landmark", references=refs))
    return RouteSnapshot(str(uuid4()), 1, "a" * 64, "b" * 64, tuple(points))


def session(clock=None, mode=Mode.RGB):
    sensor = SensorProfile(
        mode,
        0.001 if mode == Mode.RGBD else None,
        "test-calibration" if mode == Mode.RGBD else None,
    )
    return RuntimeSession(uuid4(), route(), sensor, clock or FakeClock(), BASELINE)


def jpeg_b64(color=1):
    buffer = io.BytesIO()
    Image.new("RGB", (64, 64), (color, 40, 50)).save(buffer, "JPEG")
    return base64.b64encode(buffer.getvalue()).decode()


def png_b64(distance=2000, bits=16):
    buffer = io.BytesIO()
    pixels = np.full((64, 64), distance, dtype=np.uint16 if bits == 16 else np.uint8)
    Image.fromarray(pixels).save(buffer, "PNG")
    return base64.b64encode(buffer.getvalue()).decode()


def frame(challenge, capture=100, color=1, depth=None):
    return Frame.model_validate(
        {
            "type": "frame",
            "seq": challenge.seq,
            "frame_token": challenge.token,
            "capture_monotonic_ms": capture,
            "image_b64": jpeg_b64(color),
            "depth": depth,
        }
    )


class FixtureVision:
    encoder_fingerprint = "a" * 64

    def __init__(self, index=0, detections=()):
        self.index, self.detections = index, detections

    def infer(self, rgb):
        return VisionResult(vector(self.index), tuple(self.detections), {"vision_ms": 0.1})


@contextmanager
def wire_client(vision=None, clock=None):
    from fastapi import FastAPI, Request, WebSocket, WebSocketException
    from fastapi.testclient import TestClient

    from navcore.api.auth import Principal, device
    from navcore.api.errors import ApiError, install_handlers
    from navcore.api.sessions import route_loader
    from navcore.api.sessions import router as sessions_router
    from navcore.api.stream import StreamIdentity, stream_identity
    from navcore.api.stream import router as stream_router
    from navcore.runtime.sessions import SessionRegistry
    from navcore.runtime.worker import ModelWorker

    clock, owner, outsider, snapshot = clock or FakeClock(), uuid4(), uuid4(), route()

    @asynccontextmanager
    async def lifespan(app):
        app.state.clock, app.state.vision = clock, vision or FixtureVision()
        app.state.worker = ModelWorker(clock)
        app.state.sessions = SessionRegistry(clock, worker=app.state.worker)
        app.state.sessions.start()
        yield
        await app.state.sessions.close()
        await app.state.worker.close()

    app = FastAPI(lifespan=lifespan)
    install_handlers(app)
    app.include_router(sessions_router)
    app.include_router(stream_router)

    async def device_override(request: Request):
        token = request.headers.get("authorization")
        if token not in {"Bearer owner", "Bearer outsider"}:
            raise ApiError("AUTH_REQUIRED", 401, "Test credentials required")
        return Principal("device", owner if token == "Bearer owner" else outsider)

    async def stream_override(websocket: WebSocket):
        token = websocket.headers.get("authorization")
        if token not in {"Bearer owner", "Bearer outsider"}:
            raise WebSocketException(1008)

        async def revalidate():
            return getattr(app.state, "token_valid", True)

        return StreamIdentity(
            Principal("device", owner if token == "Bearer owner" else outsider), revalidate
        )

    app.dependency_overrides[device] = device_override
    app.dependency_overrides[stream_identity] = stream_override
    app.dependency_overrides[route_loader] = lambda: lambda _: snapshot
    with TestClient(app) as client:
        client.headers["Authorization"] = "Bearer owner"
        yield client, clock, snapshot


def create_wire_session(client, snapshot, sensor=None):
    response = client.post(
        "/v1/sessions",
        json={
            "route_id": snapshot.id,
            "sensor": sensor or {"mode": "rgb"},
            "language": "vi-VN",
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def receive_kind(websocket, kind, limit=20):
    for _ in range(limit):
        message = websocket.receive_json()
        if message["type"] == kind:
            return message
    raise AssertionError(f"Expected message type {kind}")


def answer(request, capture=100, color=1, depth=None):
    return {
        "type": "frame",
        "seq": request["seq"],
        "frame_token": request["frame_token"],
        "capture_monotonic_ms": capture,
        "image_b64": jpeg_b64(color),
        "depth": depth,
    }
