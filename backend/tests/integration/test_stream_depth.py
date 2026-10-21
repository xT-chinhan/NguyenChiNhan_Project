import pytest

from tests.runtime_support import (
    answer,
    create_wire_session,
    png_b64,
    receive_kind,
    wire_client,
)


def depth(**changes):
    return {
        "png_b64": png_b64(),
        "capture_monotonic_ms": 100,
        "aligned_to_color": True,
        "calibration_id": "test-calibration",
        **changes,
    }


def test_rgb_depth_is_rejected_and_rgbd_missing_depth_holds():
    with wire_client() as (client, _, route):
        session = create_wire_session(client, route)
        with client.websocket_connect(session["stream_path"]) as ws:
            capture = receive_kind(ws, "capture_request")
            ws.send_json(answer(capture, depth=depth()))
            assert receive_kind(ws, "frame_rejected")["code"] == "DEPTH_INVALID"
        client.delete(f"/v1/sessions/{session['id']}")
        session = create_wire_session(
            client,
            route,
            sensor={"mode": "rgbd", "depth_scale_m": 0.001, "calibration_id": "test-calibration"},
        )
        with client.websocket_connect(session["stream_path"]) as ws:
            capture = receive_kind(ws, "capture_request")
            ws.send_json(answer(capture))
            result = receive_kind(ws, "frame_result")
            assert result["depth_status"] == "missing" and result["movement_held"]
            assert result["instruction"]["code"] == "DEPTH_UNAVAILABLE"


@pytest.mark.parametrize(
    "changes",
    [
        {"calibration_id": "wrong-calibration"},
        {"capture_monotonic_ms": 151},
        {"png_b64": png_b64(distance=200, bits=8)},
        {"aligned_to_color": False},
    ],
)
def test_rgbd_invalid_calibration_timestamp_format_or_alignment_rejects(changes):
    with wire_client() as (client, _, route):
        session = create_wire_session(
            client,
            route,
            sensor={"mode": "rgbd", "depth_scale_m": 0.001, "calibration_id": "test-calibration"},
        )
        with client.websocket_connect(session["stream_path"]) as ws:
            capture = receive_kind(ws, "capture_request")
            ws.send_json(answer(capture, depth=depth(**changes)))
            assert receive_kind(ws, "frame_rejected")["code"] == "DEPTH_INVALID"
