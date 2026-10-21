"""Real PostgreSQL/auth/catalog + actual app routers, fixture vision explicitly injected."""

import base64
import io
import time
from uuid import UUID

from PIL import Image

from navcore.cli.devices import create_device
from navcore.storage.devices import revoke
from tests.integration.test_catalog_api import image_bytes, new_route, upload
from tests.runtime_support import receive_kind


def published_route(client, headers):
    route = new_route(client, headers)
    for seq, action in enumerate(("straight", "left", "right", "arrive")):
        assert upload(client, headers, route["id"], seq, action).status_code == 201
    response = client.post(f"/v1/admin/routes/{route['id']}/publish", json={}, headers=headers)
    assert response.status_code == 200
    return response.json()


def token(engine, tmp_path, name):
    output = tmp_path / f"{name}.env"
    result = create_device(engine, name, output, "http://127.0.0.1:8095")
    secret = dict(line.split("=", 1) for line in output.read_text().splitlines())[
        "NAV_DEVICE_TOKEN"
    ]
    return UUID(result["id"]), {"Authorization": "Bearer " + secret}


def test_database_auth_snapshot_stream_progress_and_catalog_lock(
    vision_client, engine, tmp_path, admin_headers
):
    route = published_route(vision_client, admin_headers)
    owner_id, headers = token(engine, tmp_path, "owner")
    _, outsider = token(engine, tmp_path, "outsider")
    response = vision_client.post(
        "/v1/sessions",
        headers=headers,
        json={"route_id": route["id"], "sensor": {"mode": "rgb"}, "language": "vi-VN"},
    )
    assert response.status_code == 201
    session = response.json()
    resource = f"/v1/sessions/{session['id']}"
    assert vision_client.get(resource, headers=outsider).status_code == 404
    assert vision_client.delete(resource, headers=outsider).status_code == 404
    assert (
        vision_client.post(
            "/v1/admin/maps", headers=admin_headers, json={"name": "Busy"}
        ).status_code
        == 409
    )
    with vision_client.websocket_connect(session["stream_path"], headers=headers) as ws:
        assert ws.receive_json()["type"] == "welcome"
        for seq in range(3):
            request = receive_kind(ws, "capture_request")
            pixels = Image.open(io.BytesIO(image_bytes(0, seq))).convert("RGB")
            buffer = io.BytesIO()
            pixels.save(buffer, "JPEG", quality=90)
            ws.send_json(
                {
                    "type": "frame",
                    "seq": request["seq"],
                    "frame_token": request["frame_token"],
                    "capture_monotonic_ms": time.monotonic_ns() // 1_000_000,
                    "image_b64": base64.b64encode(buffer.getvalue()).decode(),
                }
            )
            result = receive_kind(ws, "frame_result")
        assert result["last_confirmed_seq"] == 0
        assert result["instruction"]["code"] == "CONTINUE_STRAIGHT"
        ws.send_json(
            {"type": "ack", "instruction_id": result["instruction"]["id"], "stage": "presented"}
        )
        assert vision_client.get(resource, headers=headers).json()["last_confirmed_seq"] == 0
    assert vision_client.get(resource, headers=headers).json()["state"] == "paused"
    assert revoke(engine, owner_id)
    assert vision_client.get(resource, headers=headers).status_code == 401
