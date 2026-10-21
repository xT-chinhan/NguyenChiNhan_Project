import stat
import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select

from navcore.cli.devices import create_device
from navcore.storage.database import transaction
from navcore.storage.devices import revoke, token_hash
from navcore.storage.models import Device


def issue(engine, tmp_path):
    path = tmp_path / "client.env"
    result = create_device(engine, "replay-01", path, "http://127.0.0.1:8095")
    values = dict(line.split("=", 1) for line in path.read_text().splitlines())
    return result, path, values["NAV_DEVICE_TOKEN"]


def test_tokens_private_hashed_revoked_and_role_limited(client, engine, tmp_path, capsys):
    result, path, token = issue(engine, tmp_path)
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
    assert token not in capsys.readouterr().out
    headers = {"Authorization": f"Bearer {token}"}
    assert client.get("/v1/maps", headers=headers).status_code == 200
    assert (
        client.post("/v1/admin/maps", json={"name": "Forbidden"}, headers=headers).status_code
        == 403
    )
    with transaction(engine) as session:
        device = session.get(Device, uuid.UUID(result["id"]))
        assert device.token_sha256 == token_hash(token) and device.token_sha256 != token
    assert revoke(engine, uuid.UUID(result["id"]))
    assert revoke(engine, uuid.UUID(result["id"]))
    assert client.get("/v1/maps", headers=headers).status_code == 401


def test_invalid_missing_and_expired_tokens(client, engine):
    assert client.get("/v1/maps").status_code == 401
    assert client.get("/v1/maps", headers={"Authorization": "Bearer invalid"}).status_code == 401
    token = "navdev_" + "a" * 43
    with transaction(engine) as session:
        session.add(
            Device(
                name="expired",
                token_sha256=token_hash(token),
                expires_at=datetime.now(UTC) - timedelta(seconds=1),
            )
        )
    assert client.get("/v1/maps", headers={"Authorization": f"Bearer {token}"}).status_code == 401


def test_create_refuses_overwrite_and_failed_file_does_not_commit(engine, tmp_path):
    import pytest

    _, path, _ = issue(engine, tmp_path)
    initial = path.read_bytes()
    with pytest.raises(FileExistsError):
        create_device(engine, "duplicate", path, "http://127.0.0.1:8095")
    assert path.read_bytes() == initial
    directory = tmp_path / "directory.env"
    directory.mkdir()
    with pytest.raises(OSError):
        create_device(engine, "invalid", directory, "http://127.0.0.1:8095")
    with transaction(engine) as session:
        assert session.scalar(select(func.count()).select_from(Device)) == 1


def test_db_commit_failure_removes_only_newly_published_private_file(engine, tmp_path, monkeypatch):
    from contextlib import contextmanager

    import pytest

    import navcore.cli.devices as devices

    original = devices.transaction

    @contextmanager
    def failed_commit(db):
        with original(db) as session:
            yield session
            raise RuntimeError("Injected database commit failure")

    monkeypatch.setattr(devices, "transaction", failed_commit)
    output = tmp_path / "failed.env"
    with pytest.raises(RuntimeError):
        create_device(engine, "commit-failed", output, "http://127.0.0.1:8095")
    assert not output.exists()
    assert list(tmp_path.iterdir()) == []
    with transaction(engine) as session:
        assert session.scalar(select(func.count()).select_from(Device)) == 0
