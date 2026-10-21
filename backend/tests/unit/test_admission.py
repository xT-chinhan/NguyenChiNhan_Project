import asyncio
import threading
from types import SimpleNamespace

import pytest

from navcore.api.catalog import mutation


@pytest.mark.asyncio
async def test_cancellation_retains_admission_until_actual_db_mutation_finishes():
    started, release = threading.Event(), threading.Event()
    app = SimpleNamespace(state=SimpleNamespace(admission_lock=asyncio.Lock(), engine=None))

    def blocked(engine):
        started.set()
        release.wait(3)

    task = asyncio.create_task(mutation(app, blocked))
    assert await asyncio.to_thread(started.wait, 1)
    task.cancel()
    await asyncio.sleep(0)
    assert app.state.admission_lock.locked()
    assert not task.done()
    release.set()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert not app.state.admission_lock.locked()
