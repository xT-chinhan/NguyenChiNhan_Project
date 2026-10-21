"""One real model call at a time, including after an awaiting task is cancelled."""

import asyncio
import time
from concurrent.futures import ThreadPoolExecutor
from functools import partial


class WorkerBusy(Exception):
    pass


class WorkerFault(Exception):
    pass


class ModelWorker:
    def __init__(self, clock=None):
        self.clock = clock or time.monotonic
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="navcore-model")
        self.slot = asyncio.Lock()
        self.future = None
        self.started_at = None
        self.faulted = False
        self.closed = False

    def check_fault(self) -> bool:
        if self.started_at is not None and self.clock() - self.started_at > 10:
            self.faulted = True
        return self.faulted

    def _finished(self, future):
        if self.started_at is not None and self.clock() - self.started_at > 10:
            self.faulted = True
        self.future = None
        self.started_at = None
        if self.slot.locked():
            self.slot.release()
        if not future.cancelled():
            future.exception()

    async def run(self, function, *args, wait_ms=100, **kwargs):
        if self.closed or self.check_fault():
            raise WorkerFault("Model worker requires restart")
        try:
            await asyncio.wait_for(self.slot.acquire(), timeout=wait_ms / 1000)
        except TimeoutError:
            raise WorkerBusy("Model slot unavailable") from None
        if self.closed or self.check_fault():
            self.slot.release()
            raise WorkerFault("Model worker requires restart")
        self.started_at = self.clock()
        loop = asyncio.get_running_loop()
        try:
            future = loop.run_in_executor(self.executor, partial(function, *args, **kwargs))
        except BaseException:
            self.started_at = None
            self.slot.release()
            raise
        self.future = future
        future.add_done_callback(self._finished)
        return await asyncio.shield(future)

    async def close(self):
        self.closed = True
        if self.future is not None:
            try:
                await asyncio.wait_for(asyncio.shield(self.future), timeout=10)
            except Exception:
                pass
        self.executor.shutdown(wait=False, cancel_futures=False)
