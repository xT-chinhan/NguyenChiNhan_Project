import threading
from uuid import UUID

import pytest
from starlette.websockets import WebSocketDisconnect

from tests.runtime_support import (
    FixtureVision,
    answer,
    create_wire_session,
    receive_kind,
    wire_client,
)


class BlockingVision(FixtureVision):
    def __init__(self):
        super().__init__()
        self.entered, self.release = threading.Event(), threading.Event()

    def infer(self, rgb):
        self.entered.set()
        assert self.release.wait(3)
        return super().infer(rgb)


def test_watchdog_expires_processing_request_while_model_thread_is_blocked():
    vision = BlockingVision()
    try:
        with wire_client(vision=vision) as (client, clock, route):
            session = create_wire_session(client, route)
            with client.websocket_connect(session["stream_path"]) as ws:
                capture = receive_kind(ws, "capture_request")
                ws.send_json(answer(capture))
                assert vision.entered.wait(1)
                clock.advance(1)
                stale = receive_kind(ws, "status")
                assert stale["code"] == "STREAM_STALE" and stale["state"] == "paused"
                state = client.app.state.sessions.sessions[UUID(session["id"])]
                assert state.core.navigation.last_confirmed_seq == -1
                assert not state.core.tracker.tracks
                assert state.core.navigation.candidate is None
                assert client.app.state.worker.slot.locked()
                vision.release.set()
                ws.send_json({"type": "control", "command": "repeat"})
                repeated = receive_kind(ws, "control_result")
                assert repeated["code"] == "WAIT_FOR_FRESH_FRAME"
                assert state.core.navigation.last_confirmed_seq == -1
    finally:
        vision.release.set()


def test_pause_control_is_received_and_answered_during_blocked_inference():
    vision = BlockingVision()
    try:
        with wire_client(vision=vision) as (client, _, route):
            session = create_wire_session(client, route)
            with client.websocket_connect(session["stream_path"]) as ws:
                ws.send_json(answer(receive_kind(ws, "capture_request")))
                assert vision.entered.wait(1)
                ws.send_json({"type": "control", "command": "pause"})
                result = receive_kind(ws, "control_result")
                assert result["state"] == "paused"
                assert client.app.state.worker.slot.locked()
                vision.release.set()
                current = client.app.state.sessions.sessions[UUID(session["id"])]
                assert current.core.navigation.last_confirmed_seq == -1
    finally:
        vision.release.set()


def test_revocation_checked_at_ten_seconds_and_closes_1008():
    with wire_client() as (client, clock, route):
        session = create_wire_session(client, route)
        with client.websocket_connect(session["stream_path"]) as ws:
            receive_kind(ws, "capture_request")
            client.app.state.token_valid = False
            clock.advance(10)
            with pytest.raises(WebSocketDisconnect) as error:
                while True:
                    ws.receive_json()
            assert error.value.code == 1008
        assert client.get(f"/v1/sessions/{session['id']}").json()["state"] == "paused"


def test_heartbeat_does_not_refresh_idle_or_instruction_deadline():
    with wire_client() as (client, clock, route):
        session = create_wire_session(client, route)
        with client.websocket_connect(session["stream_path"]) as ws:
            receive_kind(ws, "capture_request")
            clock.advance(2)
            assert receive_kind(ws, "heartbeat")["state"] == "paused"
            clock.advance(298)
            with pytest.raises(WebSocketDisconnect) as error:
                while True:
                    ws.receive_json()
            assert error.value.code == 1008
        assert client.get(f"/v1/sessions/{session['id']}").json()["state"] == "stopped"


def test_malformed_image_spends_challenge_then_new_request_has_new_token():
    with wire_client() as (client, clock, route):
        session = create_wire_session(client, route)
        with client.websocket_connect(session["stream_path"]) as ws:
            first = receive_kind(ws, "capture_request")
            ws.send_json({**answer(first), "image_b64": "not-valid-base64"})
            assert receive_kind(ws, "frame_rejected")["code"] == "IMAGE_INVALID"
            clock.advance(0.2)
            second = receive_kind(ws, "capture_request")
            assert second["frame_token"] != first["frame_token"]
            ws.send_json(answer(first))
            assert receive_kind(ws, "frame_rejected")["code"] == "FRAME_TOKEN_INVALID"


def test_nonfinite_json_is_rejected_without_changing_candidate():
    with wire_client() as (client, _, route):
        session = create_wire_session(client, route)
        with client.websocket_connect(session["stream_path"]) as ws:
            receive_kind(ws, "capture_request")
            ws.send_text('{"type":"control","command":"repeat","invalid":NaN}')
            assert receive_kind(ws, "frame_rejected")["code"] == "PROTOCOL_ERROR"
