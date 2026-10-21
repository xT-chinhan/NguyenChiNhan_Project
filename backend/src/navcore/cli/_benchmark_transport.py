"""Actual HTTP/WS challenge traffic and optional read-only backend process sampling."""

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
from websockets.exceptions import WebSocketException

from navcore.cli._benchmark_inputs import process_identity
from navcore.cli._benchmark_metrics import InstructionGuard, Metrics


class ResourceSampler:
    def __init__(self, pid: int | None):
        self.pid = pid
        self.rss: list[int] = []
        self.vram: list[int] = []
        self.failures = 0
        try:
            self.identity = process_identity(pid) if pid is not None else None
        except (OSError, ValueError, IndexError):
            self.identity = None
            self.failures += 1

    def sample_rss(self) -> None:
        if self.pid is None:
            return
        try:
            if process_identity(self.pid) != self.identity:
                raise ValueError("Backend process identity changed")
            for line in (Path("/proc") / str(self.pid) / "status").read_text().splitlines():
                if line.startswith("VmRSS:"):
                    value = int(line.split()[1]) * 1024
                    if value <= 0:
                        raise ValueError("Invalid process RSS")
                    self.rss.append(value)
                    return
            raise ValueError("Process RSS unavailable")
        except (OSError, ValueError, IndexError):
            self.failures += 1

    async def sample_vram(self) -> None:
        if self.pid is None or self.identity is None:
            return
        process = None
        try:
            if process_identity(self.pid) != self.identity:
                return
            process = await asyncio.create_subprocess_exec(
                "nvidia-smi",
                "--query-compute-apps=pid,used_memory",
                "--format=csv,noheader,nounits",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL,
            )
            output, _ = await asyncio.wait_for(process.communicate(), 1)
            if process.returncode:
                return
            values = []
            for line in output.decode().splitlines():
                pid, memory = (value.strip() for value in line.split(","))
                if int(pid) == self.pid and memory.isdigit():
                    values.append(int(memory) * 1024 * 1024)
            if values:
                self.vram.append(sum(values))
        except (OSError, ValueError, UnicodeError, TimeoutError):
            pass
        finally:
            if process is not None and process.returncode is None:
                process.kill()
                await process.wait()

    def summary(self) -> dict:
        return {
            "backend_process": self.identity,
            "rss_peak_bytes": max(self.rss) if self.rss else None,
            "rss_samples": len(self.rss),
            "vram_peak_bytes": max(self.vram) if self.vram else None,
            "vram_samples": len(self.vram),
            "rss_read_failures": self.failures,
            "sampling_interval_ms": 500,
        }


async def sample_resources(sampler, stats, stop):
    while not stop.is_set():
        if stats.measured(time.monotonic()):
            await asyncio.to_thread(sampler.sample_rss)
            await sampler.sample_vram()
        try:
            await asyncio.wait_for(stop.wait(), 0.5)
        except TimeoutError:
            pass


async def ping_health(http, stats: Metrics, stop: asyncio.Event):
    """HTTP health request RTT is measured, not inferred from WS frame latency."""
    while not stop.is_set() and time.monotonic() < stats.measurement_end:
        started = time.monotonic()
        try:
            response = await http.get("/health/live")
            if response.status_code != 200 or response.json() != {"status": "alive"}:
                raise ValueError("Health probe failed")
            if stats.measured(started):
                stats.rtt_ms.append((time.monotonic() - started) * 1000)
        except (httpx.HTTPError, ValueError):
            if stats.measured(started):
                stats.counts["http_ping_failures"] += 1
        try:
            await asyncio.wait_for(stop.wait(), max(0.01, 1 - (time.monotonic() - started)))
        except TimeoutError:
            pass


async def _present(ws, guard, instruction, req, received_at, held, stats, clock):
    if instruction is None:
        return
    if (
        not isinstance(instruction, dict)
        or instruction.get("frame_seq") != req.seq
        or instruction.get("capture_monotonic_ms") != req.capture_ms
    ):
        raise ValueError("Instruction does not match frame")
    if req.measured:
        stats.counts["instructions_received"] += 1
    if not guard.remember(instruction):
        if req.measured:
            stats.counts["instructions_dropped"] += 1
        return
    ack = {"type": "ack", "instruction_id": instruction["id"], "stage": "received"}
    await ws.send(json.dumps(ack))
    now_ms = clock() * 1000
    fresh = guard.fresh(instruction, received_at * 1000, now_ms)
    suppressed = held and instruction.get("priority") == "guidance"
    if not fresh or suppressed:
        if req.measured:
            stats.counts["instructions_dropped"] += 1
            stats.counts["stale_instruction_proposals"] += not fresh
        return
    # Presentation is this immediate client event, not completion of real speech.
    if req.measured:
        stats.counts["instructions_presented"] += 1
        stats.counts["stale_instructions_presented"] += not guard.fresh(
            instruction, received_at * 1000, now_ms
        )
    await ws.send(json.dumps({**ack, "stage": "presented"}))


async def drive_stream(
    ws, session_id: str, dataset, stats: Metrics, *, clock=time.monotonic
) -> bool:
    """Exactly one outstanding challenge; client transmission is capped at 5 Hz."""
    guard = InstructionGuard()
    pending = None
    last_seq, last_capture, last_sent = 0, -1, float("-inf")
    welcomed = False
    while True:
        now = clock()
        if now >= stats.measurement_end and pending is None:
            return True
        receive_until = pending.requested_at + 1.5 if pending else stats.measurement_end
        try:
            raw = await asyncio.wait_for(ws.recv(), max(0.001, receive_until - now))
        except TimeoutError:
            if pending is None and clock() >= stats.measurement_end:
                return True
            stats.errors["result_timeout"] += 1
            return False
        received = clock()
        if not isinstance(raw, str) or len(raw.encode()) > 1_100_000:
            raise ValueError("Invalid server WS message size")
        message = json.loads(raw)
        if not isinstance(message, dict):
            raise TypeError("Invalid server WS message")
        kind = message.get("type")
        if kind == "welcome":
            if (
                welcomed
                or message.get("protocol_version") != 1
                or message.get("session_id") != session_id
                or message.get("mode") != "rgb"
                or message.get("max_result_age_ms") != 1000
            ):
                raise ValueError("Invalid stream welcome")
            welcomed = True
        elif kind == "capture_request":
            seq = message.get("seq")
            if (
                not welcomed
                or pending is not None
                or type(seq) is not int
                or seq <= last_seq
                or message.get("deadline_ms") != 1000
            ):
                raise ValueError("Invalid capture challenge")
            token = str(UUID(message["frame_token"]))
            pending = stats.request(session_id, seq, received)
            if pending is None:
                return True
            last_seq = seq
            delay = last_sent + 0.2 - clock()
            if delay > 0:
                await asyncio.sleep(delay)
            jpeg = await asyncio.to_thread(dataset.jpeg, (clock() - stats.started_at) * 1000)
            capture = max(last_capture + 1, int(clock() * 1000))
            await ws.send(
                json.dumps(
                    {
                        "type": "frame",
                        "seq": seq,
                        "frame_token": token,
                        "capture_monotonic_ms": capture,
                        "heading_deg": None,
                        "heading_accuracy_deg": None,
                        "image_b64": base64.b64encode(jpeg).decode("ascii"),
                        "depth": None,
                    },
                    allow_nan=False,
                )
            )
            last_capture, last_sent = capture, clock()
            stats.sent(pending, capture)
        elif kind in {"frame_result", "frame_rejected"}:
            if pending is None or message.get("seq") != pending.seq:
                raise ValueError("Unmatched frame outcome")
            if kind == "frame_rejected":
                code = message.get("code")
                if not isinstance(code, str) or not code.isupper() or len(code) > 80:
                    raise ValueError("Invalid rejection code")
                stats.reject(pending, code)
            else:
                if message.get("capture_monotonic_ms") != pending.capture_ms:
                    raise ValueError("Result capture timestamp differs")
                stats.result(pending, received, message)
                if pending.measured and received * 1000 - pending.capture_ms >= 1000:
                    stats.counts["stale_results_received"] += 1
                await _present(
                    ws,
                    guard,
                    message.get("instruction"),
                    pending,
                    received,
                    message.get("movement_held", True),
                    stats,
                    clock,
                )
            pending = None
        elif kind in {"heartbeat", "status", "control_result"}:
            continue
        elif kind == "error":
            stats.errors["server_error"] += 1
            return False
        else:
            raise ValueError("Unknown server message")


async def run_stream(session: dict, device, dataset, stats, ready, started: asyncio.Event) -> bool:
    parsed = urlsplit(device.api_url)
    url = urlunsplit(
        (
            "wss" if parsed.scheme == "https" else "ws",
            parsed.netloc,
            f"/v1/sessions/{session['id']}/stream",
            "",
            "",
        )
    )
    # websockets DEBUG otherwise logs handshake Authorization and raw frame payloads.
    wire_logger = logging.getLogger("navcore.benchmark.wire")
    wire_logger.setLevel(logging.CRITICAL + 1)
    wire_logger.propagate = False
    try:
        async with connect(
            url,
            additional_headers={"Authorization": f"Bearer {device.token}"},
            max_size=1_100_000,
            max_queue=1,
            open_timeout=5,
            close_timeout=1,
            proxy=None,
            logger=wire_logger,
        ) as ws:
            await asyncio.wait_for(ready.wait(), 6)
            if not started.is_set():
                stats.begin(time.monotonic())
                started.set()
            return await drive_stream(ws, session["id"], dataset, stats)
    except (
        OSError,
        ValueError,
        KeyError,
        TypeError,
        WebSocketException,
        TimeoutError,
        asyncio.BrokenBarrierError,
    ):
        stats.errors["stream_or_protocol_failure"] += 1
        await ready.abort()
        return False
