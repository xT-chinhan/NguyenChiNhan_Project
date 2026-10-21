import uuid


def test_validation_and_http_errors_are_safe_envelopes(client, admin_headers, settings):
    for response in (
        client.get("/not-here"),
        client.get("/v1/maps"),
        client.post(
            "/v1/admin/maps", json={"name": " ", "token": "private"}, headers=admin_headers
        ),
    ):
        error = response.json()["error"]
        assert uuid.UUID(error["request_id"])
        assert response.headers["X-Request-ID"] == error["request_id"]
        assert settings.admin_token not in response.text and "private" not in response.text


def test_request_cap_runs_before_multipart_parse(client, admin_headers):
    response = client.post(
        "/v1/admin/routes/00000000-0000-4000-8000-000000000001/checkpoints",
        content=b"x" * (4 * 1024 * 1024 + 1),
        headers=admin_headers,
    )
    assert response.status_code == 413
    assert response.json()["error"]["code"] == "PAYLOAD_TOO_LARGE"
