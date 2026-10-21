import os
import secrets
import tempfile
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path

from navcore.storage.database import transaction
from navcore.storage.devices import revoke, token_hash
from navcore.storage.models import Device


def create_device(engine, name: str, target: Path, api_url: str) -> dict:
    name = " ".join(name.split())
    if not 1 <= len(name) <= 80:
        raise ValueError("Device name must contain 1..80 characters")
    if "\n" in api_url or "\r" in api_url or not api_url.startswith(("http://", "https://")):
        raise ValueError("Invalid API URL")
    target = target.absolute()
    target.parent.mkdir(parents=True, exist_ok=True)
    token = "navdev_" + secrets.token_urlsafe(32)
    device_id, expires = uuid.uuid4(), datetime.now(UTC) + timedelta(days=90)
    created = False
    identity = None
    temporary = None
    try:
        with transaction(engine) as session:
            session.add(
                Device(id=device_id, name=name, token_sha256=token_hash(token), expires_at=expires)
            )
            fd, temporary = tempfile.mkstemp(prefix=".navcore-device-", dir=target.parent)
            identity = os.fstat(fd)
            with os.fdopen(fd, "w") as stream:
                stream.write(f"NAV_API_URL={api_url}\nNAV_DEVICE_TOKEN={token}\n")
                stream.flush()
                os.fsync(stream.fileno())
            session.flush()
            os.link(temporary, target, follow_symlinks=False)
            created = True
    except BaseException:
        if created:
            try:
                current = target.lstat()
                if (current.st_dev, current.st_ino) == (identity.st_dev, identity.st_ino):
                    target.unlink()
            except FileNotFoundError:
                pass
        raise
    finally:
        if temporary is not None:
            Path(temporary).unlink(missing_ok=True)
    return {"id": str(device_id), "expires_at": expires.isoformat(), "env_file": str(target)}


def revoke_device(engine, device_id: uuid.UUID) -> bool:
    return revoke(engine, device_id)
