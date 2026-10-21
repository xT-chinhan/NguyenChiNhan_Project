import asyncio
import json
from uuid import UUID

import httpx
import pytest
from websockets.asyncio.client import connect as real_connect
from websockets.asyncio.server import serve

from navcore.cli.replay import replay_session
from tests.integration.test_replay_client import prepared_frames


@pytest.mark.asyncio
async def test_video_end_stops_even_when_server_is_paused_without_capture(tmp_path, monkeypatch):
    frames = prepared_frames(tmp_path / "frames")
    session_id = str(UUID(int=100))
    deleted, controls = [], []

    def rest(request):
        if request.method == "POST":
            return httpx.Response(
                201, json={"id": session_id, "stream_path": f"/v1/sessions/{session_id}/stream"}
            )
        deleted.append(request.url.path)
        return httpx.Response(204)

    original = httpx.AsyncClient
    monkeypatch.setattr(
        "navcore.cli.replay.httpx.AsyncClient",
        lambda **kwargs: original(**kwargs, transport=httpx.MockTransport(rest)),
    )

    async def server(ws):
        await ws.send(json.dumps({"type": "welcome", "state": "paused"}))
        controls.append(json.loads(await ws.recv()))
        await ws.wait_closed()

    async with serve(server, "127.0.0.1", 0) as service:
        port = service.sockets[0].getsockname()[1]
        monkeypatch.setattr(
            "navcore.cli.replay.connect",
            lambda url, **kwargs: real_connect(f"ws://127.0.0.1:{port}", **kwargs),
        )
        await asyncio.wait_for(
            replay_session(
                "http://unit.invalid",
                "private-test-token",
                str(UUID(int=20)),
                frames,
                tmp_path / "trace.jsonl",
            ),
            timeout=3,
        )
    assert controls == [{"type": "control", "command": "stop"}]
    assert deleted == [f"/v1/sessions/{session_id}"]
