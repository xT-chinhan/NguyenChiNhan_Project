import asyncio
import threading

import pytest

from navcore.runtime.worker import ModelWorker, WorkerBusy, WorkerFault


@pytest.mark.asyncio
async def test_cancelled_waiter_never_releases_running_call_slot():
    entered, release = threading.Event(), threading.Event()
    running = 0
    maximum = 0

    def blocked():
        nonlocal running, maximum
        running += 1
        maximum = max(maximum, running)
        entered.set()
        release.wait(3)
        running -= 1
        return "done"

    worker = ModelWorker()
    task = asyncio.create_task(worker.run(blocked))
    try:
        assert await asyncio.to_thread(entered.wait, 1)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
        with pytest.raises(WorkerBusy):
            await worker.run(blocked, wait_ms=10)
        assert running == 1 and maximum == 1
    finally:
        release.set()
        await worker.close()
    assert running == 0


@pytest.mark.asyncio
async def test_fault_is_sticky_after_call_returns():
    now = [0.0]
    worker = ModelWorker(lambda: now[0])
    entered, release = threading.Event(), threading.Event()

    def blocked():
        entered.set()
        release.wait(3)

    task = asyncio.create_task(worker.run(blocked))
    try:
        assert await asyncio.to_thread(entered.wait, 1)
        now[0] = 10.001
        assert worker.check_fault()
        release.set()
        await task
        with pytest.raises(WorkerFault):
            await worker.run(lambda: 1)
    finally:
        release.set()
        await worker.close()


@pytest.mark.asyncio
async def test_finished_call_records_deadline_fault_even_without_watchdog_poll():
    now = [0.0]
    worker = ModelWorker(lambda: now[0])

    def late_call():
        now[0] = 10.001
        return "late"

    try:
        assert await worker.run(late_call) == "late"
        assert worker.faulted
        with pytest.raises(WorkerFault):
            await worker.run(lambda: "must not run")
    finally:
        await worker.close()
