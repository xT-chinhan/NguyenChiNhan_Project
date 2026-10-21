import importlib
import json
import logging
import socket
import stat
from pathlib import Path

import pytest

from navcore.cli.bootstrap import bootstrap
from navcore.logging import JsonFormatter
from navcore.settings import Settings


def config(**changes):
    values = dict(
        db_url="postgresql+psycopg://user:private@localhost/navcore_test",
        admin_token="a" * 40,
        model_dir=Path("/tmp/navcore-models"),
    )
    return Settings(**(values | changes))


def test_import_has_no_network_side_effects(monkeypatch):
    def fail(*args, **kwargs):
        raise AssertionError("Unexpected network access")

    monkeypatch.setattr(socket.socket, "connect", fail)
    import navcore.app

    importlib.reload(navcore.app)
    app = navcore.app.create_app()
    assert app.title == "Navigation Core"


@pytest.mark.parametrize(
    "changes",
    [
        {"db_url": "sqlite:///tmp/test.db"},
        {"admin_token": "short"},
        {"model_dir": Path("relative")},
        {"worker_count": 2},
        {"port": True},
        {"port": 65536},
        {"vision_device": "auto"},
        {"log_level": "garbage"},
    ],
)
def test_settings_reject_invalid_configuration(changes):
    with pytest.raises(ValueError):
        config(**changes)


def test_secrets_do_not_appear_in_repr_or_logs():
    settings = config()
    assert "private" not in repr(settings) and settings.admin_token not in repr(settings)
    record = logging.LogRecord(
        "test", logging.ERROR, "", 0, f"Bearer {settings.admin_token} {settings.db_url}", (), None
    )
    record.fields = {
        "authorization": "Bearer abc",
        "nested": {"image_b64": "private-frame"},
        "message": "navdev_secret",
        "seq": 1,
    }
    value = JsonFormatter((settings.admin_token,)).format(record)
    assert all(secret not in value for secret in ("private", "navdev_secret", settings.admin_token))
    assert json.loads(value)["seq"] == 1


def test_bootstrap_private_idempotent_and_complete(tmp_path, capsys):
    path = bootstrap(tmp_path)
    initial = path.read_bytes()
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
    assert bootstrap(tmp_path).read_bytes() == initial
    assert capsys.readouterr().out == ""
    values = dict(line.split("=", 1) for line in initial.decode().splitlines())
    assert Settings.from_env(values).port == 8095
    assert values["NAV_TEST_DB_URL"].endswith("/navcore_test")
    path.chmod(0o644)
    with pytest.raises(ValueError, match="0600"):
        bootstrap(tmp_path)


def test_settings_missing_environment_is_explicit():
    with pytest.raises(ValueError, match="NAV_DB_URL"):
        Settings.from_env({})
