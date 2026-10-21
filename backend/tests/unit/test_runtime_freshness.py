import asyncio
import threading
from copy import deepcopy

import pytest

from navcore.core.types import Detection, State
from navcore.runtime import processing
from navcore.runtime.coordinator import Coordinator
from navcore.runtime.processing import FrameError
from navcore.runtime.worker import ModelWorker, WorkerBusy
from tests.runtime_support import FixtureVision, frame, session


@pytest.mark.asyncio
@pytest.mark.parametrize("age,accepted", [(0.999, True), (1.0, False)])
async def test_final_guard_999_ms_accepts_1000_ms_has_zero_core_mutations(age, accepted):
    current = session()
    worker = ModelWorker(current.clock)

    class AdvanceVision(FixtureVision):
        def infer(self, rgb):
            current.clock.advance(age)
            return super().infer(rgb)

    coordinator = Coordinator(
        current, worker, AdvanceVision(detections=(Detection(0, "person", (10, 10, 30, 50), 0.9),))
    )
    coordinator.issue()
    incoming = frame(current.challenge)
    coordinator.consume(incoming)
    original = deepcopy(current.core)
    result = await coordinator.process(incoming, current.challenge)
    assert (result is not None) is accepted
    if accepted:
        assert len(current.core.navigation.candidate.frames) == 1
        assert current.core.tracker.next_id == 2
    else:
        assert current.core.navigation == original.navigation
        assert vars(current.core.tracker) == vars(original.tracker)
        assert vars(current.core.assessor) == vars(original.assessor)
        assert current.instruction is None
    await worker.close()


@pytest.mark.asyncio
async def test_processing_token_is_retained_duplicate_is_rejected_and_one_job_only():
    current = session()
    worker = ModelWorker(current.clock)
    coordinator = Coordinator(current, worker, FixtureVision())
    request = coordinator.issue()
    incoming = frame(current.challenge)
    challenge = coordinator.consume(incoming)
    assert challenge.state == "processing" and coordinator.issue() is None
    with pytest.raises(FrameError, match="FRAME_DUPLICATE"):
        coordinator.consume(incoming)
    assert await coordinator.process(incoming, challenge)
    assert challenge.state == "finished"
    assert coordinator.issue() is None
    current.clock.advance(0.2)
    assert coordinator.issue()["seq"] == request["seq"] + 1
    await worker.close()


@pytest.mark.asyncio
@pytest.mark.parametrize("command", ["pause", "stop"])
async def test_control_during_blocked_inference_prevents_all_late_mutation(command):
    current = session()
    worker = ModelWorker(current.clock)
    entered, release = threading.Event(), threading.Event()

    class BlockingVision(FixtureVision):
        def infer(self, rgb):
            entered.set()
            assert release.wait(3)
            return super().infer(rgb)

    coordinator = Coordinator(current, worker, BlockingVision())
    coordinator.issue()
    incoming = frame(current.challenge)
    challenge = coordinator.consume(incoming)
    pending = asyncio.create_task(coordinator.process(incoming, challenge))
    assert await asyncio.to_thread(entered.wait, 1)
    current.control(command)
    after_control = deepcopy(current.core)
    release.set()
    assert await pending is None
    assert current.core.navigation == after_control.navigation
    assert vars(current.core.tracker) == vars(after_control.tracker)
    assert vars(current.core.assessor) == vars(after_control.assessor)
    await worker.close()


@pytest.mark.asyncio
async def test_cancellation_does_not_release_actual_model_slot():
    worker = ModelWorker()
    entered, release = threading.Event(), threading.Event()
    calls = 0

    def blocked():
        nonlocal calls
        calls += 1
        entered.set()
        assert release.wait(3)

    pending = asyncio.create_task(worker.run(blocked))
    assert await asyncio.to_thread(entered.wait, 1)
    pending.cancel()
    with pytest.raises(asyncio.CancelledError):
        await pending
    with pytest.raises(WorkerBusy):
        await worker.run(blocked, wait_ms=1)
    assert calls == 1
    release.set()
    await worker.close()


@pytest.mark.asyncio
async def test_three_model_failures_pause_until_manual_resume():
    current = session()
    worker = ModelWorker(current.clock)

    class BrokenVision(FixtureVision):
        def infer(self, rgb):
            raise RuntimeError("test fixture failure")

    coordinator = Coordinator(current, worker, BrokenVision())
    for capture in (100, 300, 500):
        coordinator.issue()
        incoming = frame(current.challenge, capture=capture)
        challenge = coordinator.consume(incoming)
        result = await coordinator.process(incoming, challenge)
        assert result["code"] == "VISION_UNAVAILABLE"
        current.clock.advance(0.2)
    assert current.state == State.PAUSED and coordinator.issue() is None
    current.control("resume")
    assert current.state == State.LOCALIZING and current.model_failures == 0
    await worker.close()


@pytest.mark.asyncio
async def test_mutated_staged_core_is_discarded_if_pause_arrives_before_final_commit(monkeypatch):
    current = session()
    worker = ModelWorker(current.clock)
    entered, release = threading.Event(), threading.Event()
    original = processing.propose

    def blocked_after_real_core(*args):
        result = original(*args)
        entered.set()
        assert release.wait(3)
        return result

    monkeypatch.setattr(processing, "propose", blocked_after_real_core)
    coordinator = Coordinator(
        current, worker, FixtureVision(detections=(Detection(0, "person", (10, 10, 30, 50), 0.9),))
    )
    coordinator.issue()
    incoming = frame(current.challenge)
    challenge = coordinator.consume(incoming)
    pending = asyncio.create_task(coordinator.process(incoming, challenge))
    assert await asyncio.to_thread(entered.wait, 1)
    assert not current.core.tracker.tracks
    current.control("pause")
    paused = deepcopy(current.core)
    release.set()
    assert await pending is None
    assert current.core.navigation == paused.navigation
    assert vars(current.core.tracker) == vars(paused.tracker)
    assert vars(current.core.assessor) == vars(paused.assessor)
    await worker.close()


@pytest.mark.asyncio
async def test_resume_clears_motion_without_reopening_older_capture_timestamps():
    current = session()
    worker = ModelWorker(current.clock)
    coordinator = Coordinator(current, worker, FixtureVision())
    coordinator.issue()
    incoming = frame(current.challenge, capture=500)
    challenge = coordinator.consume(incoming)
    assert await coordinator.process(incoming, challenge)
    current.control("pause")
    current.control("resume")
    current.clock.advance(0.2)
    coordinator.issue()
    with pytest.raises(FrameError, match="CAPTURE_TIME_INVALID"):
        coordinator.consume(frame(current.challenge, capture=499))
    await worker.close()
