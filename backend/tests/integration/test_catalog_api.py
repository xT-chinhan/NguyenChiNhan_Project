import io
import json

import numpy as np
from PIL import Image, ImageDraw


class FixtureEncoder:
    """Synthetic adapter for catalog/protocol tests; never real AI accuracy evidence."""

    encoder_fingerprint = "f" * 64

    def encode(self, rgb):
        vector = np.zeros(768, dtype=np.float32)
        index = round(float(np.median(rgb[:, :, 0])) / 32) - 1
        vector[max(0, min(767, index))] = 1
        return vector

    def infer(self, rgb):
        from navcore.vision.pipeline import VisionResult

        return VisionResult(self.encode(rgb), (), {"vision_ms": 0.1})


def image_bytes(point=0, reference=0):
    image = Image.new("RGB", (64, 64), ((point + 1) * 32, 20, 20))
    ImageDraw.Draw(image).rectangle((0, 0, 10, 10), fill=(0, reference * 70, 0))
    stream = io.BytesIO()
    image.save(stream, format="PNG")
    return stream.getvalue()


def new_route(client, headers):
    map_response = client.post("/v1/admin/maps", json={"name": "Map"}, headers=headers)
    assert map_response.status_code == 201
    map_id = map_response.json()["id"]
    places = [
        client.post(f"/v1/admin/maps/{map_id}/places", json={"name": name}, headers=headers).json()[
            "id"
        ]
        for name in ("A", "B")
    ]
    response = client.post(
        "/v1/admin/routes",
        headers=headers,
        json={
            "name": "Route",
            "map_id": map_id,
            "from_place_id": places[0],
            "to_place_id": places[1],
        },
    )
    assert response.status_code == 201
    return response.json()


def upload(client, headers, route_id, point, action, images=None):
    metadata = {
        "seq": point,
        "depart_action": action,
        "landmark": f"Point {point}",
        "source_group": "synthetic-reference",
    }
    images = [image_bytes(point, index) for index in range(3)] if images is None else images
    files = [("images", ("arbitrary-name.png", value, "image/png")) for value in images]
    return client.post(
        f"/v1/admin/routes/{route_id}/checkpoints",
        headers=headers,
        data={"metadata": json.dumps(metadata)},
        files=files,
    )


def test_metadata_catalog_pagination_and_unbound_drafts(client, admin_headers):
    route = new_route(client, admin_headers)
    assert route["encoder_fingerprint"] is None
    response = client.get(f"/v1/admin/routes/{route['id']}", headers=admin_headers)
    assert response.json()["publish_errors"]
    response = client.get(
        "/v1/routes",
        headers=admin_headers,
        params={key: route[key] for key in ("map_id", "from_place_id", "to_place_id")},
    )
    assert response.json() == {"items": []}
    for name in ("Second", "Third"):
        client.post("/v1/admin/maps", headers=admin_headers, json={"name": name})
    first = client.get("/v1/maps?limit=2", headers=admin_headers).json()
    second = client.get(
        "/v1/maps", headers=admin_headers, params={"cursor": first["next_cursor"], "limit": 2}
    ).json()
    ids = [row["id"] for row in first["items"] + second["items"]]
    assert len(ids) == len(set(ids)) == 3 and ids == sorted(ids)
    assert second["next_cursor"] is None
    assert (
        client.patch(f"/v1/admin/routes/{route['id']}", headers=admin_headers, json={}).status_code
        == 405
    )


def test_unicode_casefold_can_expand_beyond_original_name_limit(client, admin_headers):
    route = new_route(client, admin_headers)
    response = client.post(
        f"/v1/admin/maps/{route['map_id']}/places", headers=admin_headers, json={"name": "ß" * 120}
    )
    assert response.status_code == 201


def test_checkpoint_upload_is_atomic_and_does_not_accept_vectors(vision_client, admin_headers):
    route = new_route(vision_client, admin_headers)
    bad_images = [image_bytes(0, 0), image_bytes(0, 1), b"not-an-image"]
    assert (
        upload(vision_client, admin_headers, route["id"], 0, "straight", bad_images).status_code
        == 422
    )
    detail = vision_client.get(f"/v1/admin/routes/{route['id']}", headers=admin_headers).json()
    assert detail["checkpoints"] == []
    assert upload(vision_client, admin_headers, route["id"], 0, "straight").status_code == 201
    assert upload(vision_client, admin_headers, route["id"], 0, "straight").status_code == 422
    assert (
        upload(vision_client, admin_headers, route["id"], 1, "arrive", [image_bytes()]).status_code
        == 422
    )
