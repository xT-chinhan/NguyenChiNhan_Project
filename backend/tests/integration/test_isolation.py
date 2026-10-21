import asyncio
import threading
from uuid import uuid4

import pytest

from navcore.core.types import Detection, Mode, SensorProfile, State
from navcore.runtime.coordinator import Coordinator
from navcore.runtime.sessions import SessionRegistry
from navcore.runtime.worker import ModelWorker
from tests.runtime_support import FakeClock, FixtureVision, frame, route


@pytest.mark.asyncio
async def test_four_sessions_own_candidates_trackers_cooldowns_progress_and_instructions():
    clock = FakeClock()
    worker = ModelWorker(clock)
    registry = SessionRegistry(clock, worker=worker)
    coordinators = []
    for index in range(4):
        snapshot = route()
        current = await registry.create(
            uuid4(), snapshot.id, SensorProfile(Mode.RGB), lambda _, snapshot=snapshot: snapshot
        )
        # Every session gets a different route, even when visual fixture vectors agree.
        vision = FixtureVision(
            detections=(Detection(index, f"object-{index}", (1, 1, 15, 15), 0.9),)
        )
        coordinators.append(Coordinator(current, worker, vision))
    for capture, color in ((100, 10), (300, 80), (500, 150)):
        for index, coordinator in enumerate(coordinators):
            coordinator.issue()
            incoming = frame(coordinator.session.challenge, capture, color + index * 5)
            challenge = coordinator.consume(incoming)
            assert await coordinator.process(incoming, challenge)
        clock.advance(0.2)
    sessions = [coordinator.session for coordinator in coordinators]
    assert len({current.route_id for current in sessions}) == 4
    assert len({id(current.core.tracker) for current in sessions}) == 4
    assert len({id(current.core.assessor) for current in sessions}) == 4
    assert len({id(current.core.assessor._spoken) for current in sessions}) == 4
    assert len({current.instruction.payload["id"] for current in sessions}) == 4
    assert all(current.core.navigation.last_confirmed_seq == 0 for current in sessions)
    assert all(list(current.core.tracker.tracks) == [1] for current in sessions)
    sessions[0].control("pause")
    assert all(current.state == State.NAVIGATING for current in sessions[1:])
    assert all(current.instruction is not None for current in sessions[1:])
    sessions[1].core.tracker.tracks[1].distance_history.append((500, 1.0))
    assert not sessions[2].core.tracker.tracks[1].distance_history
    await registry.close()
    await worker.close()


@pytest.mark.asyncio
async def test_global_sticky_worker_fault_pauses_all_sessions_without_spawning_replacement():
    clock = FakeClock()
    worker = ModelWorker(clock)
    registry = SessionRegistry(clock, worker=worker)
    for _ in range(4):
        snapshot = route()
        await registry.create(
            uuid4(), snapshot.id, SensorProfile(Mode.RGB), lambda _, snapshot=snapshot: snapshot
        )
    entered, release = threading.Event(), threading.Event()

    def blocked():
        entered.set()
        assert release.wait(3)

    pending = asyncio.create_task(worker.run(blocked))
    assert await asyncio.to_thread(entered.wait, 1)
    clock.advance(10.001)
    assert worker.check_fault()
    registry.start()
    # Wait for a watchdog event rather than relying on a long wall-clock sleep.
    async with asyncio.timeout(1):
        while any(current.state != State.PAUSED for current in registry.sessions.values()):
            await asyncio.sleep(0.01)
    assert worker.faulted
    release.set()
    await pending
    assert worker.check_fault()  # return/completion cannot reset sticky fault
    assert all(
        current.hold_reason == "VISION_UNAVAILABLE" for current in registry.sessions.values()
    )
    await registry.close()
    await worker.close()
