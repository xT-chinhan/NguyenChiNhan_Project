import os
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy import text

from navcore.app import create_app
from navcore.settings import Settings
from navcore.storage.database import make_engine, require_test_database

BACKEND = Path(__file__).resolve().parents[2]


@pytest.fixture(scope="session")
def test_url():
    value = os.environ.get("NAV_TEST_DB_URL")
    if not value:
        pytest.skip("NAV_TEST_DB_URL required; use isolated PostgreSQL compose.test.yaml")
    return require_test_database(value)


@pytest.fixture(scope="session")
def migration_config(test_url):
    config = Config(str(BACKEND / "config" / "alembic.ini"))
    previous = os.environ.get("NAV_DB_URL")
    os.environ["NAV_DB_URL"] = test_url
    command.upgrade(config, "head")
    yield config
    if previous is not None:
        os.environ["NAV_DB_URL"] = previous
    else:
        os.environ.pop("NAV_DB_URL", None)


@pytest.fixture
def engine(test_url, migration_config):
    engine = make_engine(test_url)
    with engine.begin() as connection:
        connection.execute(
            text("TRUNCATE reference_images,checkpoints,routes,places,maps,devices CASCADE")
        )
    yield engine
    engine.dispose()


@pytest.fixture
def settings(test_url, tmp_path):
    return Settings(
        db_url=test_url,
        admin_token="test-admin-" + "x" * 40,
        model_dir=tmp_path / "models",
        environment="test",
        log_level="INFO",
    )


@pytest.fixture
def client(engine, settings):
    with TestClient(create_app(settings)) as client:
        yield client


@pytest.fixture
def admin_headers(settings):
    return {"Authorization": f"Bearer {settings.admin_token}"}


@pytest.fixture
def vision_client(engine, settings):
    from tests.integration.test_catalog_api import FixtureEncoder

    with TestClient(create_app(settings, vision=FixtureEncoder())) as client:
        yield client
