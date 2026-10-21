from uuid import UUID

from tests.runtime_support import create_wire_session, wire_client


def test_device_rest_creation_ownership_idempotent_delete_and_tombstone():
    with wire_client() as (client, clock, route):
        session = create_wire_session(client, route)
        path = f"/v1/sessions/{session['id']}"
        assert session["last_confirmed_seq"] == -1 and session["target_seq"] == 0
        assert client.get(path).json()["state"] == "localizing"
        assert client.get(path, headers={"Authorization": "Bearer outsider"}).status_code == 404
        assert client.delete(path, headers={"Authorization": "Bearer outsider"}).status_code == 404
        assert (
            client.post(
                "/v1/sessions",
                json={"route_id": route.id, "sensor": {"mode": "rgb"}, "language": "vi-VN"},
            ).status_code
            == 409
        )
        assert client.delete(path).status_code == 204
        assert client.delete(path).status_code == 204
        assert client.get(path).json()["state"] == "stopped"
        assert client.app.state.sessions.sessions[UUID(session["id"])].route is None
        clock.advance(300)
        assert client.get(path).status_code == 404


def test_session_schema_rejects_client_device_and_invalid_sensor():
    with wire_client() as (client, _, route):
        value = {"route_id": route.id, "sensor": {"mode": "rgb"}, "language": "vi-VN"}
        assert client.post("/v1/sessions", json={**value, "device_id": route.id}).status_code == 422
        assert (
            client.post(
                "/v1/sessions",
                json={
                    **value,
                    "sensor": {
                        "mode": "rgbd",
                        "depth_scale_m": 0,
                        "calibration_id": "test",
                    },
                },
            ).status_code
            == 422
        )


def test_get_does_not_extend_idle_ttl():
    with wire_client() as (client, clock, route):
        session = create_wire_session(client, route)
        path = f"/v1/sessions/{session['id']}"
        clock.advance(299)
        assert client.get(path).json()["state"] == "localizing"
        clock.advance(1)
        assert client.get(path).json()["state"] == "stopped"
