import asyncio

import pytest

from navcore.runtime.coordinator import CommittedResult
from navcore.runtime.sessions import InstructionRecord
from navcore.runtime.streaming import StreamConnection
from navcore.runtime.worker import ModelWorker
from tests.runtime_support import FixtureVision, session


class Socket:
    def __init__(self, blocked=False):
        self.sent, self.closed = [], []
        self.blocked = blocked
        self.entered = asyncio.Event()
        self.release = asyncio.Event()

    async def send_json(self, payload):
        self.entered.set()
        if self.blocked:
            await self.release.wait()
        self.sent.append(payload)

    async def close(self, code):
        self.closed.append(code)


async def valid():
    return True


@pytest.mark.asyncio
@pytest.mark.parametrize("untrusted", [True, -1, 2**64, "raw-payload", {"image_b64": "raw"}])
async def test_protocol_error_never_reflects_unvalidated_sequence_payload(untrusted):
    current = session()
    worker = ModelWorker(current.clock)
    connection = StreamConnection(Socket(), current, worker, FixtureVision(), valid)
    await connection.protocol_error("PROTOCOL_ERROR", untrusted)
    assert connection.outbound.get_nowait().payload == {
        "type": "frame_rejected",
        "seq": None,
        "code": "PROTOCOL_ERROR",
    }
    await worker.close()


@pytest.mark.asyncio
async def test_bounded_output_queue_full_pauses_and_closes_1013():
    current, socket = session(), Socket()
    worker = ModelWorker(current.clock)
    connection = StreamConnection(socket, current, worker, FixtureVision(), valid)
    for _ in range(9):
        connection.enqueue({"type": "heartbeat", "state": "localizing"})
    assert current.state.value == "paused" and connection.outbound.qsize() <= 8
    await connection.send()
    assert socket.closed == [1013]
    assert [payload["type"] for payload in socket.sent] == ["status"]
    assert socket.sent[0]["movement_held"]
    await worker.close()


@pytest.mark.asyncio
async def test_slow_sender_timeout_pauses_and_closes_1013():
    current, socket = session(), Socket(blocked=True)
    worker = ModelWorker(current.clock)
    connection = StreamConnection(socket, current, worker, FixtureVision(), valid)
    connection.enqueue({"type": "heartbeat", "state": "localizing"})
    await connection.send()
    assert current.state.value == "paused" and socket.closed == [1013]
    assert not socket.sent
    await worker.close()


@pytest.mark.asyncio
@pytest.mark.parametrize("invalidation", ["epoch", "deadline", "identity"])
async def test_sender_rechecks_queued_movement_epoch_deadline_and_current_identity(invalidation):
    current, socket = session(), Socket()
    worker = ModelWorker(current.clock)
    connection = StreamConnection(socket, current, worker, FixtureVision(), valid)
    instruction = {"id": "movement-id", "valid_for_ms": 1000}
    current.instruction = InstructionRecord(instruction, current.epoch, current.now_ms() + 1000)
    result = CommittedResult({"type": "frame_result", "instruction": instruction}, current.epoch)
    connection.enqueue(result, current.now_ms() + 1000)
    if invalidation == "epoch":
        current.invalidate("PAUSE")
    elif invalidation == "deadline":
        current.clock.advance(1)
    else:
        current.instruction.payload = {"id": "new-movement-id"}
    connection.terminate(1000, "test", discard=False)
    await connection.send()
    assert not socket.sent and socket.closed == [1000]
    await worker.close()
