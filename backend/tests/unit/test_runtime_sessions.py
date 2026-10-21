import asyncio
import gc
import weakref
from uuid import uuid4

import pytest

from navcore.api.errors import ApiError
from navcore.core.types import Mode, SensorProfile, State
from navcore.runtime.sessions import SessionRegistry
from tests.runtime_support import FakeClock, route


async def create(registry, owner=None):
    snapshot = route()
    return await registry.create(
        owner or uuid4(), snapshot.id, SensorProfile(Mode.RGB), lambda _: snapshot
    )


@pytest.mark.asyncio
async def test_ownership_capacity_and_ram_only_restart():
    registry = SessionRegistry(FakeClock())
    first = await create(registry)
    with pytest.raises(ApiError, match="DEVICE_SESSION_EXISTS"):
        await create(registry, first.device_id)
    with pytest.raises(ApiError, match="SESSION_NOT_FOUND"):
        registry.owned(first.id, uuid4())
    assert registry.owned(first.id, first.device_id) is first
    for _ in range(3):
        await create(registry)
    with pytest.raises(ApiError, match="SESSION_CAPACITY"):
        await create(registry)
    assert registry.active_count() == 4
    with pytest.raises(ApiError, match="SESSION_NOT_FOUND"):
        SessionRegistry().owned(first.id, first.device_id)


@pytest.mark.asyncio
async def test_idle_terminal_tombstone_and_idempotent_stop():
    clock = FakeClock()
    registry = SessionRegistry(clock)
    first = await create(registry)
    clock.advance(299.999)
    await registry.expire()
    assert first.state == State.LOCALIZING
    clock.advance(0.001)
    await registry.expire()
    assert first.state == State.STOPPED and first.route is None
    first.control("stop")
    clock.advance(299.999)
    await registry.expire()
    assert registry.owned(first.id, first.device_id) is first
    clock.advance(0.001)
    await registry.expire()
    assert first.id not in registry.sessions


@pytest.mark.asyncio
async def test_controls_refresh_idle_but_absolute_expiry_is_30_minutes():
    clock = FakeClock()
    registry = SessionRegistry(clock)
    first = await create(registry)
    for _ in range(8):
        clock.advance(200)
        first.control("repeat")
        await registry.expire()
        assert first.state != State.STOPPED
    clock.advance(200)
    first.control("repeat")
    await registry.expire()
    assert first.state == State.STOPPED


@pytest.mark.asyncio
async def test_shared_admission_serializes_snapshot_and_catalog_mutation():
    registry = SessionRegistry(FakeClock(), admission_lock=asyncio.Lock())
    async with registry.admission_lock:
        pending = asyncio.create_task(create(registry))
        await asyncio.sleep(0)
        assert not pending.done() and registry.active_count() == 0
    result = await pending
    assert registry.active_count() == 1 and result.route is not None


@pytest.mark.asyncio
async def test_cleanup_500_sessions_releases_routes_and_registry_entries():
    clock = FakeClock()
    registry = SessionRegistry(clock)
    sessions, routes = [], []
    for _ in range(500):
        current = await create(registry)
        sessions.append(weakref.ref(current))
        routes.append(weakref.ref(current.route))
        current.control("stop")
        assert current.route is None and not current.core.tracker.tracks
    assert registry.active_count() == 0
    clock.advance(300)
    await registry.expire()
    assert not registry.sessions
    del current
    await asyncio.sleep(0)
    gc.collect()
    assert all(reference() is None for reference in sessions + routes)
