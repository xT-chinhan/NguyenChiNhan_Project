from tests.integration.test_runtime_postgres import published_route, token


def test_real_database_four_device_admission_and_published_retry_while_active(
    vision_client, engine, tmp_path, admin_headers
):
    route = published_route(vision_client, admin_headers)
    for index in range(5):
        _, headers = token(engine, tmp_path, f"capacity-{index}")
        response = vision_client.post(
            "/v1/sessions",
            headers=headers,
            json={"route_id": route["id"], "sensor": {"mode": "rgb"}, "language": "vi-VN"},
        )
        if index < 4:
            assert response.status_code == 201
            duplicate = vision_client.post(
                "/v1/sessions",
                headers=headers,
                json={"route_id": route["id"], "sensor": {"mode": "rgb"}, "language": "vi-VN"},
            )
            assert duplicate.status_code == 409
        else:
            assert response.status_code == 503
            assert response.headers["Retry-After"] == "1"
    vision_client.app.state.vision = None
    repeated = vision_client.post(
        f"/v1/admin/routes/{route['id']}/publish", headers=admin_headers, json={}
    )
    assert repeated.status_code == 200 and repeated.json() == route
