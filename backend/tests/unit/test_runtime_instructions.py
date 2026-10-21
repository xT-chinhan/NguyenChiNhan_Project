import pytest

from navcore.core.types import Detection, Mode, State
from navcore.runtime.coordinator import Coordinator
from navcore.runtime.worker import ModelWorker
from tests.runtime_support import FixtureVision, frame, png_b64, session


async def observe(coordinator, capture, color, depth=None):
    coordinator.issue()
    incoming = frame(coordinator.session.challenge, capture, color, depth)
    challenge = coordinator.consume(incoming)
    result = await coordinator.process(incoming, challenge)
    coordinator.session.clock.advance(0.2)
    return result


@pytest.mark.asyncio
async def test_only_current_unexpired_presented_ack_unlocks_departure_and_repeat_keeps_id():
    current = session()
    worker = ModelWorker(current.clock)
    vision = FixtureVision()
    coordinator = Coordinator(current, worker, vision)
    result = None
    for capture, color in ((100, 10), (300, 80), (500, 150)):
        result = await observe(coordinator, capture, color)
    instruction = result["instruction"]
    assert instruction["code"] == "CONTINUE_STRAIGHT"
    assert current.core.navigation.pending_departure_seq == 0
    repeated = coordinator.repeat()
    assert repeated["id"] == instruction["id"]
    assert repeated["valid_for_ms"] < instruction["valid_for_ms"]
    coordinator.acknowledge(instruction["id"], "received")
    assert current.core.navigation.pending_departure_seq == 0
    coordinator.acknowledge("00000000-0000-0000-0000-000000000000", "presented")
    assert current.core.navigation.pending_departure_seq == 0
    coordinator.acknowledge(instruction["id"], "presented")
    assert current.core.navigation.pending_departure_seq is None
    coordinator.acknowledge(instruction["id"], "presented")
    assert current.core.navigation.last_confirmed_seq == 0
    await worker.close()


@pytest.mark.asyncio
async def test_expired_departure_requires_three_fresh_current_checkpoint_frames():
    current = session()
    worker = ModelWorker(current.clock)
    vision = FixtureVision()
    coordinator = Coordinator(current, worker, vision)
    for capture, color in ((100, 10), (300, 80), (500, 150)):
        original = await observe(coordinator, capture, color)
    original_id = original["instruction"]["id"]
    current.clock.advance(0.8)  # exact request deadline, ACK is already too late
    coordinator.acknowledge(original_id, "presented")
    assert current.core.navigation.pending_departure_seq == 0
    assert coordinator.repeat() is None
    # Next checkpoint images cannot confirm before current departure is delivered.
    vision.index = 1
    for capture, color in ((700, 20), (900, 90), (1100, 160)):
        result = await observe(coordinator, capture, color)
        assert result["instruction"] is None
    assert current.core.navigation.last_confirmed_seq == 0
    vision.index = 0
    for index, (capture, color) in enumerate(((1300, 30), (1500, 100), (1700, 170))):
        result = await observe(coordinator, capture, color)
        assert (result["instruction"] is not None) == (index == 2)
    assert current.core.navigation.last_confirmed_seq == 0
    assert result["instruction"]["id"] != original_id
    coordinator.acknowledge(original_id, "presented")
    assert current.core.navigation.pending_departure_seq == 0
    await worker.close()


@pytest.mark.asyncio
async def test_obstacle_hold_invalidates_departure_even_when_voice_is_in_cooldown():
    current = session()
    worker = ModelWorker(current.clock)
    vision = FixtureVision()
    coordinator = Coordinator(current, worker, vision)
    for capture, color in ((100, 10), (300, 80), (500, 150)):
        original = await observe(coordinator, capture, color)
    old = original["instruction"]["id"]
    vision.detections = (Detection(0, "person", (15, 10, 50, 63), 0.9),)
    for capture, color in ((700, 20), (900, 90), (1100, 160), (1300, 30)):
        held = await observe(coordinator, capture, color)
    assert held["movement_held"] and held["instruction"] is None
    assert current.core.navigation.pending_instruction_id is None
    coordinator.acknowledge(old, "presented")
    assert current.core.navigation.pending_departure_seq == 0
    assert current.core.navigation.candidate is None
    await worker.close()


@pytest.mark.asyncio
async def test_rgbd_latch_survives_resume_while_tracker_motion_resets():
    current = session(mode=Mode.RGBD)
    worker = ModelWorker(current.clock)
    coordinator = Coordinator(current, worker, FixtureVision())

    def depth(capture, distance):
        return {
            "png_b64": png_b64(distance),
            "capture_monotonic_ms": capture,
            "aligned_to_color": True,
            "calibration_id": "test-calibration",
        }

    near = await observe(coordinator, 100, 10, depth(100, 300))
    assert near["instruction"]["code"] == "EMERGENCY_STOP"
    latch = current.core.assessor._latch
    current.control("pause")
    current.control("resume")
    assert current.core.assessor._latch == latch
    assert current.core.last_capture_ms == 100 and not current.core.tracker.tracks
    for index, capture in enumerate((300, 500, 700)):
        result = await observe(coordinator, capture, 80 + index * 40, depth(capture, 2000))
        if index < 2:
            assert result["movement_held"] and current.core.assessor._latch is not None
    assert current.core.assessor._latch is None
    await worker.close()


@pytest.mark.asyncio
async def test_lost_observes_without_progress_until_manual_resume():
    current = session()
    current.core.navigation.state = State.LOST
    worker = ModelWorker(current.clock)
    coordinator = Coordinator(current, worker, FixtureVision())
    for index, (capture, color) in enumerate(((100, 10), (300, 80), (500, 150))):
        result = await observe(coordinator, capture, color)
        assert result["state"] == "lost" and result["movement_held"]
        assert (result["instruction"] is not None) == (index == 0)
    assert current.core.navigation.last_confirmed_seq == -1
    current.clock.advance(5)
    repeated = await observe(coordinator, 700, 20)
    assert repeated["instruction"]["code"] == "HOLD_POSITION"
    current.control("resume")
    assert current.state == State.LOCALIZING
    assert current.core.last_lost_notice_ms is None
    await worker.close()
