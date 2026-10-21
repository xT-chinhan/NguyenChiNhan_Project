import hashlib
import logging
import uuid
from datetime import UTC, datetime

from sqlalchemy import select

from navcore.storage.database import transaction
from navcore.storage.models import Device


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def authenticate_device(engine, token: str, now: datetime | None = None) -> uuid.UUID | None:
    if not token.startswith("navdev_") or not 40 <= len(token) <= 100:
        return None
    with transaction(engine) as session:
        device = session.scalar(select(Device).where(Device.token_sha256 == token_hash(token)))
        if (
            device is None
            or device.revoked_at is not None
            or device.expires_at <= (now or datetime.now(UTC))
        ):
            return None
        return device.id


def revoke(engine, device_id: uuid.UUID) -> bool:
    with transaction(engine) as session:
        device = session.get(Device, device_id, with_for_update=True)
        if device is None:
            return False
        if device.revoked_at is None:
            device.revoked_at = datetime.now(UTC)
            logging.getLogger("navcore").info(
                "token_revoked", extra={"fields": {"device_id": str(device.id)}}
            )
        return True
