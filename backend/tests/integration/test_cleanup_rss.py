import asyncio
import gc
import json
from pathlib import Path
from uuid import uuid4

import pytest

from navcore.core.types import Mode, SensorProfile
from navcore.runtime.sessions import SessionRegistry
from tests.runtime_support import FakeClock, route


def rss():
    return (
        int(
            next(
                line.split()[1]
                for line in Path("/proc/self/status").read_text().splitlines()
                if line.startswith("VmRSS:")
            )
        )
        * 1024
    )


@pytest.mark.asyncio
async def test_500_session_cleanup_rss_stays_within_100_mib(tmp_path):
    clock = FakeClock()
    registry = SessionRegistry(clock)

    async def cycle(count):
        for _ in range(count):
            snapshot = route()
            session = await registry.create(
                uuid4(), snapshot.id, SensorProfile(Mode.RGB), lambda _: snapshot
            )
            session.control("stop")
        clock.advance(300)
        await registry.expire()
        await asyncio.sleep(0)
        gc.collect()
        assert not registry.sessions

    await cycle(50)
    before = rss()
    await cycle(500)
    after = rss()
    assert after - before <= 100 * 1024**2
    report = {
        "evidence_kind": "synthetic_runtime_cleanup",
        "warmup_sessions": 50,
        "measured_sessions": 500,
        "rss_before_bytes": before,
        "rss_after_bytes": after,
        "rss_increase_bytes": after - before,
        "registry_entries_after": 0,
        "limitations": ["No model allocator/WS traffic in this focused RSS check"],
    }
    (tmp_path / "cleanup-rss.json").write_text(json.dumps(report, indent=2) + "\n")
