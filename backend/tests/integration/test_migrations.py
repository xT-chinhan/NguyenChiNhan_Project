import pytest
from alembic import command
from sqlalchemy import inspect

from navcore.storage.database import require_test_database


def test_upgrade_downgrade_upgrade_only_isolated_database(engine, migration_config):
    expected = {"maps", "places", "routes", "checkpoints", "reference_images", "devices"}
    assert expected <= set(inspect(engine).get_table_names())
    command.downgrade(migration_config, "base")
    assert not expected.intersection(inspect(engine).get_table_names())
    command.upgrade(migration_config, "head")
    assert expected <= set(inspect(engine).get_table_names())
    assert {"heading_accuracy_deg"} <= {
        c["name"] for c in inspect(engine).get_columns("checkpoints")
    }


@pytest.mark.parametrize(
    "url",
    [
        "postgresql+psycopg://user:secret@localhost/navcore",
        "sqlite:///navcore_test",
        "postgresql+psycopg://localhost/navcore_test_other",
    ],
)
def test_destructive_test_guard_rejects_non_test_database(url):
    with pytest.raises(ValueError):
        require_test_database(url)
