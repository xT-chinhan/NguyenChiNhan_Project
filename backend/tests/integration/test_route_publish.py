from sqlalchemy import select

from navcore.storage.database import transaction
from navcore.storage.models import ReferenceImage
from tests.integration.test_catalog_api import new_route, upload


def test_publish_diagnostics_immutable_and_idempotent_without_models(vision_client, admin_headers):
    route = new_route(vision_client, admin_headers)
    route_id = route["id"]
    assert upload(vision_client, admin_headers, route_id, 0, "straight").status_code == 201
    response = vision_client.post(
        f"/v1/admin/routes/{route_id}/publish", json={}, headers=admin_headers
    )
    assert response.status_code == 422 and response.json()["error"]["code"] == "ROUTE_INVALID"
    assert upload(vision_client, admin_headers, route_id, 1, "arrive").status_code == 201
    response = vision_client.post(
        f"/v1/admin/routes/{route_id}/publish", json={}, headers=admin_headers
    )
    assert response.status_code == 200
    published = response.json()
    assert len(published["route_fingerprint"]) == 64
    vision_client.app.state.vision = None
    repeated = vision_client.post(
        f"/v1/admin/routes/{route_id}/publish", json={}, headers=admin_headers
    )
    assert repeated.status_code == 200 and repeated.json() == published
    assert upload(vision_client, admin_headers, route_id, 2, "arrive").status_code == 409


def test_stored_nan_and_fingerprint_mismatch_have_contract_errors(
    vision_client, admin_headers, engine
):
    route = new_route(vision_client, admin_headers)
    assert upload(vision_client, admin_headers, route["id"], 0, "straight").status_code == 201
    assert upload(vision_client, admin_headers, route["id"], 1, "arrive").status_code == 201
    with transaction(engine) as session:
        reference = session.scalar(select(ReferenceImage))
        reference.embedding = b"\x00\x00\xc0\x7f" + b"\x00" * 3068
    response = vision_client.post(
        f"/v1/admin/routes/{route['id']}/publish", json={}, headers=admin_headers
    )
    assert response.status_code == 422 and response.json()["error"]["code"] == "ROUTE_INVALID"


def test_fingerprint_mismatch_is_conflict(vision_client, admin_headers):
    route = new_route(vision_client, admin_headers)
    assert upload(vision_client, admin_headers, route["id"], 0, "straight").status_code == 201
    vision_client.app.state.vision.encoder_fingerprint = "e" * 64
    try:
        response = vision_client.post(
            f"/v1/admin/routes/{route['id']}/publish", json={}, headers=admin_headers
        )
        assert response.status_code == 409
        assert response.json()["error"]["code"] == "MODEL_FINGERPRINT_MISMATCH"
    finally:
        vision_client.app.state.vision.encoder_fingerprint = "f" * 64
