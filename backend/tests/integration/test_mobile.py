import json

import pytest
from starlette.websockets import WebSocketDisconnect

from tests.integration.test_runtime_postgres import published_route, token
from tests.runtime_support import answer, receive_kind


def test_mobile_assets_public_but_no_secrets_and_no_arbitrary_files(client, settings):
    response = client.get("/mobile")
    assert response.status_code == 200 and '<html lang="vi">' in response.text
    assert settings.admin_token not in response.text
    assert "no-store" in response.headers["cache-control"]
    assert "frame-ancestors 'none'" in response.headers["content-security-policy"]
    for name in ("client.js", "guard.js", "style.css"):
        response = client.get("/mobile/" + name)
        assert response.status_code == 200
    assert client.get("/mobile/.env").status_code == 404
    assert client.get("/mobile/unknown.js").status_code == 404


@pytest.fixture
def mobile_session(vision_client, engine, tmp_path, admin_headers):
    route = published_route(vision_client, admin_headers)
    _, headers = token(engine, tmp_path, "mobile-owner")
    response = vision_client.post(
        "/v1/sessions",
        headers=headers,
        json={"route_id": route["id"], "sensor": {"mode": "rgb"}, "language": "vi-VN"},
    )
    assert response.status_code == 201
    session = response.json()
    return (
        f"/v1/mobile/sessions/{session['id']}/stream",
        headers["Authorization"].removeprefix("Bearer "),
    )


def test_browser_auth_then_frame_and_existing_header_path_still_work(
    vision_client, mobile_session, caplog
):
    path, secret = mobile_session
    with vision_client.websocket_connect(path, headers={"origin": "http://testserver"}) as ws:
        ws.send_json({"type": "auth", "token": secret})
        assert receive_kind(ws, "welcome")["protocol_version"] == 1
        capture = receive_kind(ws, "capture_request")
        ws.send_json(answer(capture))
        assert receive_kind(ws, "frame_result")["seq"] == capture["seq"]
        ws.send_json({"type": "control", "command": "pause"})
        assert receive_kind(ws, "control_result")["state"] == "paused"
    original = path.replace("/v1/mobile/sessions/", "/v1/sessions/")
    with vision_client.websocket_connect(
        original, headers={"Authorization": "Bearer " + secret}
    ) as ws:
        assert receive_kind(ws, "welcome")["state"] == "paused"
    assert secret not in caplog.text


@pytest.mark.parametrize("origin", [None, "https://evil.example", "http://testserver.evil"])
def test_browser_requires_same_origin(vision_client, mobile_session, origin):
    path, _ = mobile_session
    with pytest.raises(WebSocketDisconnect) as error:
        with vision_client.websocket_connect(path, headers={"origin": origin} if origin else {}):
            pass
    assert error.value.code == 1008


@pytest.mark.parametrize("kind", ["invalid", "extra", "large", "binary", "admin", "other"])
def test_browser_auth_rejects_before_session_disclosure(
    vision_client, mobile_session, settings, engine, tmp_path, kind
):
    path, secret = mobile_session
    payload = {"type": "auth", "token": secret}
    if kind == "invalid":
        payload["token"] = "navdev_" + "x" * 43
    elif kind == "extra":
        payload["extra"] = True
    elif kind == "large":
        payload["token"] = "x" * 600
    elif kind == "admin":
        payload["token"] = settings.admin_token
    elif kind == "other":
        _, headers = token(engine, tmp_path, "mobile-other")
        payload["token"] = headers["Authorization"].removeprefix("Bearer ")
    with vision_client.websocket_connect(path, headers={"origin": "http://testserver"}) as ws:
        if kind == "binary":
            ws.send_bytes(json.dumps(payload).encode())
        else:
            ws.send_json(payload)
        with pytest.raises(WebSocketDisconnect) as error:
            ws.receive_json()
        assert error.value.code == 1008
