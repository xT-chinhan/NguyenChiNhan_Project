from uuid import UUID, uuid4

import pytest
from starlette.websockets import WebSocketDisconnect

from tests.runtime_support import answer, create_wire_session, receive_kind, wire_client


def test_stream_welcome_request_result_and_only_one_ws():
    with wire_client() as (client, _, route):
        session = create_wire_session(client, route)
        with client.websocket_connect(session["stream_path"]) as ws:
            assert ws.receive_json()["type"] == "welcome"
            capture = ws.receive_json()
            assert capture["seq"] == 1
            with pytest.raises(WebSocketDisconnect):
                with client.websocket_connect(session["stream_path"]):
                    pass
            ws.send_json(answer(capture))
            result = receive_kind(ws, "frame_result")
            assert result["movement_held"] and result["hold_reason"] == "LOCALIZING"
            assert "event_loop_lag_ms" in result["timing"]


@pytest.mark.parametrize(
    "headers", [{"Authorization": "Bearer invalid"}, {"Authorization": "Bearer outsider"}]
)
def test_auth_and_ownership_are_rejected_before_accept(headers):
    with wire_client() as (client, _, route):
        session = create_wire_session(client, route)
        with pytest.raises(WebSocketDisconnect) as error:
            with client.websocket_connect(session["stream_path"], headers=headers):
                pass
        assert error.value.code == 1008


def test_three_protocol_violations_close_without_progress():
    with wire_client() as (client, _, route):
        session = create_wire_session(client, route)
        with client.websocket_connect(session["stream_path"]) as ws:
            receive_kind(ws, "capture_request")
            for _ in range(3):
                ws.send_json({"type": "unknown"})
            with pytest.raises(WebSocketDisconnect) as error:
                while True:
                    ws.receive_json()
            assert error.value.code == 1008
        state = client.app.state.sessions.sessions[UUID(session["id"])]
        assert state.core.navigation.last_confirmed_seq == -1


def test_oversized_text_and_binary_close_1009():
    with wire_client() as (client, _, route):
        session = create_wire_session(client, route)
        for binary in (False, True):
            with client.websocket_connect(session["stream_path"]) as ws:
                receive_kind(ws, "welcome")
                if binary:
                    ws.send_bytes(b"x" * 1_100_001)
                else:
                    ws.send_text("x" * 1_100_001)
                with pytest.raises(WebSocketDisconnect) as error:
                    while True:
                        ws.receive_json()
                assert error.value.code == 1009


def test_disconnect_reconnect_stays_paused_until_resume_and_new_token():
    with wire_client() as (client, _, route):
        session = create_wire_session(client, route)
        with client.websocket_connect(session["stream_path"]) as ws:
            old = receive_kind(ws, "capture_request")
        with client.websocket_connect(session["stream_path"]) as ws:
            assert receive_kind(ws, "welcome")["state"] == "paused"
            ws.send_json({"type": "control", "command": "resume"})
            assert receive_kind(ws, "control_result")["state"] == "localizing"
            # Advance request rate using a fresh clock tick in this explicit test seam.
            client.app.state.clock.advance(0.2)
            new = receive_kind(ws, "capture_request")
            assert new["frame_token"] != old["frame_token"] and new["seq"] > old["seq"]
            ws.send_json(answer({**new, "frame_token": str(uuid4())}))
            assert receive_kind(ws, "frame_rejected")["code"] == "FRAME_TOKEN_INVALID"


def test_terminal_session_accepts_error_then_closes_1008():
    with wire_client() as (client, _, route):
        session = create_wire_session(client, route)
        client.delete(f"/v1/sessions/{session['id']}")
        with client.websocket_connect(session["stream_path"]) as ws:
            assert ws.receive_json()["code"] == "SESSION_TERMINAL"
            with pytest.raises(WebSocketDisconnect) as error:
                ws.receive_json()
            assert error.value.code == 1008
