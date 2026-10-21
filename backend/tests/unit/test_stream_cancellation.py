import asyncio

import anyio
import pytest

from navcore.runtime.streaming import StreamConnection
from navcore.runtime.worker import ModelWorker
from tests.runtime_support import FixtureVision, session


@pytest.mark.asyncio
@pytest.mark.parametrize("phase", ["receiving", "cleanup"])
async def test_asgi_cancel_scope_drains_connection_tasks_and_releases_owner(phase):
    current = session()
    receiving = asyncio.Event()
    disconnect = asyncio.Event()
    cleanup = asyncio.Event()
    stopped = []

    class Socket:
        async def send_json(self, payload):
            pass

        async def receive(self):
            receiving.set()
            try:
                await disconnect.wait()
                return {"type": "websocket.disconnect"}
            finally:
                stopped.append("receiver")

    async def authorized():
        return True

    class Connection(StreamConnection):
        async def tick(self):
            try:
                await asyncio.Future()
            finally:
                cleanup.set()
                await asyncio.sleep(0)
                stopped.append("watchdog")

    worker = ModelWorker(current.clock)
    connection = Connection(Socket(), current, worker, FixtureVision(), authorized)
    current.connection = connection
    with anyio.CancelScope() as scope:

        async def cancel():
            await receiving.wait()
            if phase == "cleanup":
                disconnect.set()
                await cleanup.wait()
            scope.cancel()

        cancellation = asyncio.create_task(cancel())
        await connection.run()
    await cancellation
    assert sorted(stopped) == ["receiver", "watchdog"]
    assert current.connection is None
    assert current.state.value == "paused"
    await worker.close()
