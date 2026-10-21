"""Challenge-driven 1x RGB replay and an independently clocked client guard."""

import asyncio
import base64
import json
import logging
import time
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit
from uuid import UUID

import httpx
from websockets.asyncio.client import connect

from navcore.cli.evidence import local_inputs
from navcore.cli.presentation import PresentationGuard
from navcore.cli.video import load_frames


def monotonic_ms() -> int:
    return time.monotonic_ns() // 1_000_000


async def replay_session(
    api_url: str,
    token: str,
    route_id: str,
    frames_path: Path,
    output: Path,
    clip_id: str | None = None,
) -> None:
    frames = load_frames(frames_path)
    if output.exists():
        raise ValueError("Replay output already exists")
    output.parent.mkdir(parents=True, exist_ok=True)
    headers = {"Authorization": f"Bearer {token}"}
    async with httpx.AsyncClient(
        base_url=api_url, headers=headers, timeout=30, follow_redirects=False, trust_env=False
    ) as http:
        response = await http.post(
            "/v1/sessions",
            json={"route_id": route_id, "sensor": {"mode": "rgb"}, "language": "vi-VN"},
        )
        response.raise_for_status()
        session = response.json()
        session_id = str(UUID(session["id"]))
        stream_path = f"/v1/sessions/{session_id}/stream"
        if session.get("stream_path") != stream_path:
            await http.delete(f"/v1/sessions/{session_id}")
            raise ValueError("Unexpected session stream path")
        parsed = urlsplit(api_url)
        ws_url = urlunsplit(
            (
                "wss" if parsed.scheme == "https" else "ws",
                parsed.netloc,
                stream_path,
                "",
                "",
            )
        )
        started = monotonic_ms()
        guard = PresentationGuard(started)
        last_index, last_seq, last_capture = -1, 0, -1
        try:
            trace_file = output.open("x", encoding="utf-8")
        except OSError:
            await http.delete(f"/v1/sessions/{session_id}")
            raise
        with trace_file as trace:

            def record(event):
                trace.write(json.dumps(event, allow_nan=False) + "\n")
                trace.flush()

            record(
                {
                    "type": "run_start",
                    "schema_version": 1,
                    "clip_id": clip_id or frames.root.name,
                    "evidence_kind": "network_replay",
                    "adapter_kind": "unverified_server",
                    "presentation_kind": "stdout_simulation",
                    "inputs": local_inputs(),
                    "query_source_sha256": frames.source_manifest["source_sha256"],
                    "frames_manifest_sha256": frames.source_manifest["frames_sha256"],
                    "source_duration_ms": frames.source_manifest["duration_ms"],
                }
            )
            watchdog = None
            wire_logger = logging.getLogger("navcore.replay.wire")
            wire_logger.setLevel(logging.CRITICAL + 1)
            wire_logger.propagate = False
            try:
                async with connect(
                    ws_url,
                    additional_headers=headers,
                    max_size=1_100_000,
                    max_queue=1,
                    open_timeout=10,
                    proxy=None,
                    logger=wire_logger,
                ) as ws:
                    send_lock = asyncio.Lock()
                    source_ended = False

                    async def send(payload):
                        async with send_lock:
                            if not source_ended:
                                await ws.send(payload)

                    async def end_source():
                        nonlocal source_ended
                        async with send_lock:
                            if source_ended:
                                return
                            source_ended = True
                            guard.pending = None
                            await ws.send(json.dumps({"type": "control", "command": "stop"}))
                            await ws.close()

                    async def watch():
                        while True:
                            await asyncio.sleep(0.05)
                            now = monotonic_ms()
                            if now - started >= frames.source_manifest["duration_ms"]:
                                await end_source()
                                return
                            event = guard.watchdog(now)
                            if event:
                                record(event)
                                print(json.dumps(event), flush=True)

                    watchdog = asyncio.create_task(watch())
                    async for payload in ws:
                        if source_ended:
                            break
                        received = monotonic_ms()
                        if not isinstance(payload, str):
                            raise ValueError("Server must send JSON text")  # noqa: TRY004 - wire validation
                        message = json.loads(payload)
                        kind = message.get("type")
                        if kind == "capture_request":
                            seq, frame_token = (
                                message.get("seq"),
                                message.get("frame_token"),
                            )
                            if (
                                type(seq) is not int
                                or seq <= last_seq
                                or not 0 < message.get("deadline_ms", 0) <= 1000
                            ):
                                raise ValueError("Invalid server capture request")
                            UUID(frame_token)
                            last_seq = seq
                            record(
                                {
                                    "type": "capture_request",
                                    "seq": seq,
                                    "requested_monotonic_ms": received,
                                }
                            )
                            elapsed = received - started
                            if elapsed >= frames.source_manifest["duration_ms"]:
                                await send(json.dumps({"type": "control", "command": "stop"}))
                                break
                            sample = frames.choose(elapsed, last_index)
                            if sample is None:
                                next_index = last_index + 1
                                if next_index >= len(frames.samples):
                                    await send(json.dumps({"type": "control", "command": "stop"}))
                                    break
                                delay = max(0, frames.samples[next_index].pts_ms - elapsed)
                                await asyncio.sleep(delay / 1000)
                                sample = frames.choose(monotonic_ms() - started, last_index)
                            if sample is None:
                                raise ValueError("Playback clock did not reach a new sample")
                            capture_ms = monotonic_ms()
                            while capture_ms <= last_capture:
                                await asyncio.sleep(0.001)
                                capture_ms = monotonic_ms()
                            jpeg = await asyncio.to_thread(frames.decode, sample)
                            last_index, last_capture = sample.sample_index, capture_ms
                            guard.capture(seq, capture_ms, sample.pts_ms, received)
                            record(
                                {
                                    "type": "frame_sent",
                                    "seq": seq,
                                    "sample_index": sample.sample_index,
                                    "video_pts_ms": sample.pts_ms,
                                    "capture_monotonic_ms": capture_ms,
                                    "pixel_sha256": sample.pixel_sha256,
                                    "sent_monotonic_ms": monotonic_ms(),
                                }
                            )
                            await send(
                                json.dumps(
                                    {
                                        "type": "frame",
                                        "seq": seq,
                                        "frame_token": frame_token,
                                        "capture_monotonic_ms": capture_ms,
                                        "heading_deg": None,
                                        "heading_accuracy_deg": None,
                                        "image_b64": base64.b64encode(jpeg).decode("ascii"),
                                        "depth": None,
                                    }
                                )
                            )
                        else:
                            for event in guard.handle(message, received):
                                record(event)
                                if event["type"] == "instruction_received":
                                    await send(
                                        json.dumps(
                                            {
                                                "type": "ack",
                                                "instruction_id": event["instruction_id"],
                                                "stage": "received",
                                            }
                                        )
                                    )
                            shown = guard.present(monotonic_ms())
                            if shown:
                                print(json.dumps(shown, ensure_ascii=False), flush=True)
                                record(shown)
                                if shown["type"] == "instruction_presented":
                                    await send(
                                        json.dumps(
                                            {
                                                "type": "ack",
                                                "instruction_id": shown["instruction_id"],
                                                "stage": "presented",
                                            }
                                        )
                                    )
                            if kind == "frame_rejected":
                                record(
                                    {
                                        "type": kind,
                                        "seq": message.get("seq"),
                                        "code": str(message.get("code", ""))[:80],
                                    }
                                )
                    record(
                        {
                            "type": "run_end",
                            "reason": "stream_ended",
                            "route_success_asserted": False,
                            "elapsed_ms": monotonic_ms() - started,
                            "source_exhausted": monotonic_ms() - started
                            >= frames.source_manifest["duration_ms"],
                        }
                    )
            finally:
                guard.pending = None
                if watchdog:
                    watchdog.cancel()
                    await asyncio.gather(watchdog, return_exceptions=True)
                stopped = await http.delete(f"/v1/sessions/{session_id}")
                if stopped.status_code not in {204, 404}:
                    stopped.raise_for_status()
