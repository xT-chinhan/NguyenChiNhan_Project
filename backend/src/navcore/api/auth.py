import asyncio
import hmac
from dataclasses import dataclass
from uuid import UUID

from fastapi import Request

from navcore.api.errors import ApiError
from navcore.storage.devices import authenticate_device


@dataclass(frozen=True)
class Principal:
    role: str
    device_id: UUID | None = None


def bearer(headers) -> str:
    authorization = headers.get("authorization", "")
    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise ApiError("AUTH_REQUIRED", 401, "Bearer authentication required")
    if len(parts[1]) > 256:
        raise ApiError("AUTH_INVALID", 401, "Invalid credentials")
    return parts[1]


async def authenticate(app, token: str) -> Principal:
    if hmac.compare_digest(token.encode(), app.state.settings.admin_token.encode()):
        return Principal("admin")
    device_id = await asyncio.to_thread(authenticate_device, app.state.engine, token)
    if device_id is None:
        raise ApiError("AUTH_INVALID", 401, "Invalid credentials")
    return Principal("device", device_id)


async def principal(request: Request) -> Principal:
    return await authenticate(request.app, bearer(request.headers))


async def admin(request: Request) -> Principal:
    value = await principal(request)
    if value.role != "admin":
        raise ApiError("ROLE_FORBIDDEN", 403, "Administrator access required")
    return value


async def device(request: Request) -> Principal:
    value = await principal(request)
    if value.role != "device":
        raise ApiError("ROLE_FORBIDDEN", 403, "Device access required")
    return value
