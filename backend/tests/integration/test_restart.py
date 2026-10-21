"""Restart persistence against real DB and a fresh app factory."""

from fastapi.testclient import TestClient

from navcore.app import create_app
from tests.integration.test_catalog_api import FixtureEncoder
from tests.integration.test_runtime_postgres import published_route, token


def test_restart_keeps_catalog_but_ram_session_disappears(
    vision_client, engine, settings, tmp_path, admin_headers
):
    route = published_route(vision_client, admin_headers)
    _, headers = token(engine, tmp_path, "restart")
    response = vision_client.post(
        "/v1/sessions",
        headers=headers,
        json={"route_id": route["id"], "sensor": {"mode": "rgb"}, "language": "vi-VN"},
    )
    path = f"/v1/sessions/{response.json()['id']}"
    with TestClient(create_app(settings, vision=FixtureEncoder())) as restarted:
        assert restarted.get(path, headers=headers).status_code == 404
        routes = restarted.get(
            "/v1/routes",
            headers=headers,
            params={key: route[key] for key in ("map_id", "from_place_id", "to_place_id")},
        )
        assert routes.status_code == 200 and routes.json()["items"][0]["id"] == route["id"]
