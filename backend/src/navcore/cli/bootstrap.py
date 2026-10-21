"""Create private development secrets once, without starting services."""

import os
import secrets
import stat
from pathlib import Path

from navcore.settings import Settings

BACKEND = Path(__file__).resolve().parents[3]


def bootstrap(backend: Path = BACKEND) -> Path:
    backend = backend.resolve()
    target = backend / "config" / ".env"
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() or target.is_symlink():
        if target.is_symlink() or not target.is_file():
            raise ValueError("Configuration must be a regular private file")
        if stat.S_IMODE(target.stat().st_mode) & 0o077:
            raise ValueError("Existing configuration must have mode 0600")
        existing = dict(
            line.split("=", 1)
            for line in target.read_text().splitlines()
            if line and not line.startswith("#")
        )
        Settings.from_env(existing)
        for key in ("POSTGRES_USER", "POSTGRES_PASSWORD", "POSTGRES_DB", "NAV_TEST_DB_URL"):
            if not existing.get(key):
                raise ValueError(f"Missing configuration: {key}")
        return target
    password, admin = secrets.token_urlsafe(32), secrets.token_urlsafe(48)
    values = {
        "NAV_ENV": "development",
        "NAV_API_URL": "http://127.0.0.1:8095",
        "POSTGRES_USER": "navcore",
        "POSTGRES_PASSWORD": password,
        "POSTGRES_DB": "navcore",
        "NAV_DB_URL": f"postgresql+psycopg://navcore:{password}@127.0.0.1:55439/navcore",
        "NAV_TEST_DB_URL": f"postgresql+psycopg://navcore:{password}@127.0.0.1:55440/navcore_test",
        "NAV_ADMIN_TOKEN": admin,
        "NAV_MODEL_DIR": str(backend / "models"),
        "NAV_VISION_DEVICE": "cpu",
        "NAV_LOG_LEVEL": "DEBUG",
        "NAV_HTTP_HOST": "127.0.0.1",
        "NAV_HTTP_PORT": "8095",
    }
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write("".join(f"{key}={value}\n" for key, value in values.items()))
            stream.flush()
            os.fsync(stream.fileno())
    except BaseException:
        target.unlink(missing_ok=True)
        raise
    return target
