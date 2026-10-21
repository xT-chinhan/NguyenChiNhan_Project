import pytest

from navcore.runtime.coordinator import Coordinator
from navcore.runtime.sessions import InstructionRecord
from navcore.runtime.streaming import StreamConnection
from navcore.runtime.worker import ModelWorker
from tests.runtime_support import FixtureVision, session
from tests.unit.test_runtime_output import Socket, valid


@pytest.mark.asyncio
async def test_repeated_status_coalesces_without_filling_output_queue():
    current = session()
    worker = ModelWorker(current.clock)
    connection = StreamConnection(Socket(), current, worker, FixtureVision(), valid)
    for _ in range(100):
        connection.status("MOVEMENT_HELD")
    assert connection.outbound.qsize() == 1 and not connection.closing
    current.invalidate("PAUSE")
    connection.status("PAUSE")
    assert connection.outbound.qsize() == 2
    await worker.close()


@pytest.mark.asyncio
async def test_old_ack_cannot_unlock_departure_after_silent_model_hold():
    current = session()
    worker = ModelWorker(current.clock)
    navigation = current.core.navigation
    navigation.state = type(navigation.state).NAVIGATING
    navigation.last_confirmed_seq, navigation.target_seq = 0, 1
    navigation.pending_departure_seq = 0
    navigation.pending_instruction_id = "old-id"
    navigation.pending_instruction_deadline_ms = current.now_ms() + 1000
    current.instruction = InstructionRecord(
        {"id": "old-id"}, current.epoch, current.now_ms() + 1000
    )
    coordinator = Coordinator(current, worker, FixtureVision())
    coordinator.issue()
    current.challenge.state = "processing"
    await coordinator.failure("WORKER_BUSY", current.challenge, current.epoch)
    coordinator.acknowledge("old-id", "presented")
    navigation = current.core.navigation
    assert navigation.pending_departure_seq == 0
    assert navigation.pending_instruction_id is None and current.movement_held
    await worker.close()
