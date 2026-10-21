from dataclasses import replace

from fastapi.testclient import TestClient

from navcore.app import create_app


def test_missing_models_live_but_not_ready_and_metadata_works(client, admin_headers):
    assert client.get("/health/live").json() == {"status": "alive"}
    response = client.get("/health/ready")
    assert response.status_code == 503 and response.json() == {"status": "not_ready"}
    assert (
        client.post("/v1/admin/maps", json={"name": "Map"}, headers=admin_headers).status_code
        == 201
    )


def test_database_down_does_not_break_liveness(settings):
    settings = replace(
        settings, db_url="postgresql+psycopg://user:private@127.0.0.1:1/navcore_test"
    )
    with TestClient(create_app(settings)) as client:
        assert client.get("/health/live").status_code == 200
        response = client.get("/health/ready")
        assert response.status_code == 503
        assert "private" not in response.text


def test_slow_startup_model_load_does_not_latch_runtime_inference_fault(
    engine, settings, monkeypatch
):
    from fastapi.testclient import TestClient

    from navcore.app import create_app
    from navcore.vision.pipeline import VisionPipeline
    from tests.runtime_support import FakeClock, FixtureVision

    clock = FakeClock()

    def load(*args, **kwargs):
        clock.advance(11)
        return FixtureVision()

    monkeypatch.setattr(VisionPipeline, "from_model_dir", load)
    with TestClient(create_app(settings, clock=clock)) as client:
        assert client.get("/health/ready").status_code == 200
        assert not client.app.state.worker.faulted
