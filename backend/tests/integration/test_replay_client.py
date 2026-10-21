"""A real loopback WS with a REST transport adapter; no DB or models are started."""

import asyncio
import json
import time
from uuid import UUID

import httpx
import pytest
from PIL import Image
from websockets.asyncio.client import connect as real_connect
from websockets.asyncio.server import serve

from navcore.cli.bundle import file_sha256
from navcore.cli.replay import replay_session
from navcore.vision.images import decode_image


def prepared_frames(root):
    root.mkdir()
    rows = []
    for index in range(3):
        path = root / f"frame-{index:06d}.jpg"
        Image.new("RGB", (64, 48), (index * 50, 70, 100)).save(path)
        rows.append(
            {
                "sample_index": index,
                "pts_ms": index * 200,
                "relative_path": path.name,
                "pixel_sha256": decode_image(path.read_bytes()).pixel_sha256,
            }
        )
    path = root / "frames.jsonl"
    path.write_text("".join(json.dumps(row) + "\n" for row in rows))
    (root / "source-manifest.json").write_text(
        json.dumps(
            {
                "schema_version": 1,
                "fps": 5,
                "source_sha256": "c" * 64,
                "frames_sha256": file_sha256(path),
                "duration_ms": 600,
            }
        )
    )
    return path


@pytest.mark.asyncio
async def test_replay_actual_challenges_owned_stop_and_private_trace(tmp_path, monkeypatch):
    frames = prepared_frames(tmp_path / "frames")
    output = tmp_path / "replay.jsonl"
    session_id = str(UUID(int=10))
    private_token = "test-private-token-never-in-trace"
    seen, deleted = [], []

    def rest(request):
        assert request.headers["authorization"] == "Bearer " + private_token
        if request.method == "POST":
            assert request.url.path == "/v1/sessions"
            return httpx.Response(
                201,
                json={
                    "id": session_id,
                    "stream_path": f"/v1/sessions/{session_id}/stream",
                },
            )
        deleted.append(request.url.path)
        return httpx.Response(204)

    original_client = httpx.AsyncClient

    def client(**kwargs):
        return original_client(**kwargs, transport=httpx.MockTransport(rest))

    monkeypatch.setattr("navcore.cli.replay.httpx.AsyncClient", client)

    async def server(ws):
        assert ws.request.headers["Authorization"] == "Bearer " + private_token
        for seq in range(1, 5):
            requested = time.monotonic_ns() // 1_000_000
            await ws.send(
                json.dumps(
                    {
                        "type": "capture_request",
                        "seq": seq,
                        "frame_token": str(UUID(int=seq)),
                        "deadline_ms": 1000,
                    }
                )
            )
            frame = json.loads(await ws.recv())
            if frame["type"] == "control":
                assert frame["command"] == "stop"
                break
            assert frame["capture_monotonic_ms"] >= requested
            assert "video_pts_ms" not in frame
            assert set(frame) == {
                "type",
                "seq",
                "frame_token",
                "capture_monotonic_ms",
                "heading_deg",
                "heading_accuracy_deg",
                "image_b64",
                "depth",
            }
            seen.append(frame)
            await ws.send(
                json.dumps(
                    {
                        "type": "frame_result",
                        "seq": seq,
                        "capture_monotonic_ms": frame["capture_monotonic_ms"],
                        "movement_held": True,
                        "hold_reason": "LOCALIZING",
                        "instruction": None,
                        "obstacles": [],
                        "timing": {"event_loop_lag_ms": 1.5},
                    }
                )
            )
            await asyncio.sleep(0.2)

    async with serve(server, "127.0.0.1", 0) as service:
        port = service.sockets[0].getsockname()[1]

        def connector(url, **kwargs):
            assert url == f"ws://unit.invalid/v1/sessions/{session_id}/stream"
            return real_connect(f"ws://127.0.0.1:{port}/v1/sessions/{session_id}/stream", **kwargs)

        monkeypatch.setattr("navcore.cli.replay.connect", connector)
        await replay_session(
            "http://unit.invalid",
            private_token,
            str(UUID(int=20)),
            frames,
            output,
            "query-1",
        )
    text = output.read_text()
    assert private_token not in text and "image_b64" not in text and "frame_token" not in text
    events = [json.loads(line) for line in text.splitlines()]
    assert len(seen) == 3
    assert [e["video_pts_ms"] for e in events if e["type"] == "frame_sent"] == [
        0,
        200,
        400,
    ]
    assert deleted == [f"/v1/sessions/{session_id}"]
    assert events[-1]["route_success_asserted"] is False
