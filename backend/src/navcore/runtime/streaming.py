"""One receiver, one bounded sender and an independent freshness watchdog."""

import asyncio
import json
from copy import deepcopy
from dataclasses import dataclass
from uuid import uuid4

from anyio import CancelScope
from pydantic import ValidationError
from starlette.websockets import WebSocketDisconnect

from navcore.runtime.coordinator import Coordinator
from navcore.runtime.processing import FrameError
from navcore.runtime.sessions import TERMINAL
from navcore.schemas.stream import Ack, Control, Frame


def reject_nonfinite(value):
    raise ValueError("Non-finite JSON number")


@dataclass
class Outbound:
    payload: dict
    epoch: int
    deadline_ms: float | None = None


class StreamConnection:
    def __init__(self, websocket, session, worker, vision, revalidate):
        self.websocket, self.session = websocket, session
        self.coordinator = Coordinator(session, worker, vision)
        self.revalidate = revalidate
        self.outbound = asyncio.Queue(maxsize=8)
        self.closing = False
        self.violations = 0
        self.last_status = None

    def enqueue(self, payload, deadline_ms=None):
        if self.closing:
            return
        try:
            self.outbound.put_nowait(
                Outbound(payload, getattr(payload, "epoch", self.session.epoch), deadline_ms)
            )
        except asyncio.QueueFull:
            self.session.invalidate("OUTPUT_BACKPRESSURE")
            while not self.outbound.empty():
                self.outbound.get_nowait()
            self.status("OUTPUT_BACKPRESSURE")
            self.terminate(1013, "OUTPUT_BACKPRESSURE", discard=False)

    def status(self, code):
        key = (code, self.session.state, self.session.epoch)
        if key == self.last_status:
            return
        self.last_status = key
        self.enqueue(
            {
                "type": "status",
                "code": code,
                "state": self.session.state.value,
                "text_vi": "Hướng dẫn đã tạm dừng vì thiếu hình ảnh mới."
                if code == "STREAM_STALE"
                else "Hướng dẫn di chuyển đang tạm dừng.",
                "movement_held": True,
                "hold_reason": code,
            }
        )

    def terminate(self, code, reason, discard=True):
        if self.closing:
            return
        self.closing = True
        if discard or self.outbound.full():
            while not self.outbound.empty():
                self.outbound.get_nowait()
        self.outbound.put_nowait((code, reason))

    async def deliver(self, item):
        # This guard runs in the timed send task, immediately before its network call.
        async with self.session.lock:
            payload = deepcopy(item.payload)
            instruction = payload.get("instruction")
            now = self.session.now_ms()
            if payload["type"] == "capture_request":
                challenge = self.session.challenge
                if (
                    challenge is None
                    or challenge.seq != payload["seq"]
                    or challenge.epoch != self.session.epoch
                    or now >= challenge.deadline_ms
                ):
                    return
            if payload["type"] == "frame_result" and (
                item.epoch != self.session.epoch
                or (item.deadline_ms is not None and now >= item.deadline_ms)
            ):
                return
            if instruction is not None:
                current = self.session.instruction
                if (
                    item.epoch != self.session.epoch
                    or current is None
                    or current.payload["id"] != instruction["id"]
                    or now >= current.deadline_ms
                ):
                    if payload["type"] == "control_result":
                        payload["instruction"] = None
                        payload["code"] = "WAIT_FOR_FRESH_FRAME"
                    else:
                        return
                else:
                    instruction["valid_for_ms"] = current.deadline_ms - now
        await self.websocket.send_json(payload)

    async def send(self):
        while True:
            item = await self.outbound.get()
            if isinstance(item, tuple):
                await asyncio.wait_for(self.websocket.close(code=item[0]), 0.25)
                return
            try:
                await asyncio.wait_for(self.deliver(item), 0.25)
            except TimeoutError:
                async with self.session.lock:
                    self.session.invalidate("OUTPUT_BACKPRESSURE")
                # Sender alone owns all network sends, including the final close.
                await asyncio.wait_for(self.websocket.close(code=1013), 0.25)
                return

    async def protocol_error(self, code, seq=None):
        self.violations += 1
        if type(seq) is not int or not 0 < seq < 2**63:
            seq = None
        self.enqueue({"type": "frame_rejected", "seq": seq, "code": code})
        if self.violations >= 3:
            self.session.invalidate("PROTOCOL_ERROR")
            self.terminate(1008, "PROTOCOL_ERROR")

    async def frame(self, value):
        session = self.session
        async with session.lock:
            if session.state in TERMINAL:
                self.enqueue(
                    {
                        "type": "error",
                        "code": "SESSION_TERMINAL",
                        "message": "Session is terminal",
                        "request_id": str(uuid4()),
                    }
                )
                return
            try:
                frame = Frame.model_validate(value)
            except ValidationError as error:
                # A malformed frame still spends a matching challenge.
                challenge = session.challenge
                if (
                    challenge is not None
                    and value.get("seq") == challenge.seq
                    and value.get("frame_token") == challenge.token
                    and challenge.state == "awaiting"
                ):
                    challenge.state = "finished"
                    session.core.navigation.candidate = None
                locations = {entry["loc"][0] for entry in error.errors() if entry["loc"]}
                code = (
                    "DEPTH_INVALID"
                    if "depth" in locations
                    else ("IMAGE_INVALID" if "image_b64" in locations else "PROTOCOL_ERROR")
                )
                await self.protocol_error(code, value.get("seq"))
                return
            try:
                challenge = self.coordinator.consume(frame)
            except FrameError as error:
                code = str(error)
                if code == "FRAME_EXPIRED":
                    session.invalidate("STREAM_STALE")
                    self.status("STREAM_STALE")
                elif code == "CAPTURE_TIME_INVALID":
                    self.coordinator.reject(code, session.challenge)
                await self.protocol_error(code, frame.seq)
                return
            session.job = asyncio.create_task(self.job(frame, challenge))

    async def job(self, frame, challenge):
        try:
            result = await self.coordinator.process(frame, challenge)
            if result is not None:
                self.enqueue(result, challenge.deadline_ms)
                if self.session.movement_held:
                    self.status(self.session.hold_reason or "MOVEMENT_HELD")
        finally:
            if self.session.job is asyncio.current_task():
                self.session.job = None

    async def control(self, value):
        session = self.session
        command = Control.model_validate(value).command
        async with session.lock:
            try:
                session.control(command)
            except ValueError:
                self.enqueue(
                    {
                        "type": "error",
                        "code": "SESSION_TERMINAL",
                        "message": "Session is terminal",
                        "request_id": str(uuid4()),
                    }
                )
                return
            instruction = self.coordinator.repeat() if command == "repeat" else None
            payload = {
                "type": "control_result",
                "command": command,
                "state": session.state.value,
                "instruction": instruction,
                "movement_held": session.movement_held,
                "hold_reason": session.hold_reason,
            }
            if command == "repeat" and instruction is None:
                payload["code"] = "WAIT_FOR_FRESH_FRAME"
            self.enqueue(payload)
            if command in {"pause", "stop"}:
                self.status(command.upper())
            if command == "stop":
                self.terminate(1000, "STOP", discard=False)

    async def receive(self):
        while not self.closing:
            incoming = await self.websocket.receive()
            if incoming["type"] == "websocket.disconnect":
                return
            raw = incoming.get("text")
            if raw is None:
                if len(incoming.get("bytes", b"")) > 1_100_000:
                    self.session.invalidate("PAYLOAD_TOO_LARGE")
                    self.terminate(1009, "PAYLOAD_TOO_LARGE")
                    return
                await self.protocol_error("PROTOCOL_ERROR")
                continue
            if len(raw.encode("utf-8")) > 1_100_000:
                self.session.invalidate("PAYLOAD_TOO_LARGE")
                self.terminate(1009, "PAYLOAD_TOO_LARGE")
                return
            try:
                value = json.loads(raw, parse_constant=reject_nonfinite)
                if not isinstance(value, dict):
                    raise ValueError
                kind = value.get("type")
                if kind == "frame":
                    await self.frame(value)
                elif kind == "control":
                    await self.control(value)
                elif kind == "ack":
                    ack = Ack.model_validate(value)
                    async with self.session.lock:
                        self.coordinator.acknowledge(ack.instruction_id, ack.stage)
                else:
                    raise ValueError
            except (ValidationError, ValueError, TypeError):
                await self.protocol_error("PROTOCOL_ERROR")

    async def tick(self):
        session = self.session
        heartbeat = recheck = session.clock()
        expected = session.clock() + session.policy.watchdog_interval_ms / 1000
        while not self.closing:
            await asyncio.sleep(session.policy.watchdog_interval_ms / 1000)
            now = session.clock()
            async with session.lock:
                session.event_loop_lag_ms = max(0.0, (now - expected) * 1000)
                expected = now + session.policy.watchdog_interval_ms / 1000
                challenge = session.challenge
                if (
                    challenge is not None
                    and challenge.state != "finished"
                    and session.now_ms() >= challenge.deadline_ms
                ):
                    session.invalidate("STREAM_STALE")
                    self.status("STREAM_STALE")
                if now - session.created_at >= 1800 or now - session.last_activity_at >= 300:
                    session.invalidate("SESSION_EXPIRED", stop=True)
                    self.terminate(1008, "SESSION_EXPIRED")
                if (
                    self.coordinator.worker.check_fault()
                    and session.state not in TERMINAL
                    and session.hold_reason != "VISION_UNAVAILABLE"
                ):
                    session.invalidate("VISION_UNAVAILABLE")
                    self.status("VISION_UNAVAILABLE")
                if not self.closing:
                    request = self.coordinator.issue()
                    if request is not None:
                        self.enqueue(request)
                    if now - heartbeat >= 2:
                        heartbeat = now
                        self.enqueue({"type": "heartbeat", "state": session.state.value})
            if now - recheck >= 9.9:
                recheck = now
                try:
                    authorized = await asyncio.wait_for(self.revalidate(), 0.1)
                except Exception:
                    authorized = False  # Authentication rechecks fail closed.
                if not authorized:
                    async with session.lock:
                        session.invalidate("AUTH_INVALID")
                        self.terminate(1008, "AUTH_INVALID")

    async def run(self):
        session = self.session
        self.enqueue(
            {
                "type": "welcome",
                "protocol_version": 1,
                "session_id": str(session.id),
                "mode": session.sensor.mode.value,
                "state": session.state.value,
                "max_result_age_ms": 1000,
                "heartbeat_interval_ms": 2000,
            }
        )
        request = self.coordinator.issue()
        if request is not None:
            self.enqueue(request)
        tasks = [
            asyncio.create_task(function()) for function in (self.send, self.receive, self.tick)
        ]
        try:
            done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            if self.closing and not tasks[0].done():
                await asyncio.wait_for(asyncio.shield(tasks[0]), 0.6)
            for task in done:
                if not task.cancelled():
                    task.result()
        except (WebSocketDisconnect, RuntimeError, OSError, TimeoutError):
            pass
        finally:
            # ASGI cancellation scopes may cancel repeatedly at every await.
            # Drain our tasks once before returning ownership to the registry.
            with CancelScope(shield=True):
                async with session.lock:
                    if session.connection is self:
                        if session.state not in TERMINAL:
                            session.invalidate("DISCONNECTED")
                        session.connection = None
                for task in tasks:
                    task.cancel()
                if session.job is not None:
                    session.job.cancel()
                    tasks.append(session.job)
                    session.job = None
                await asyncio.gather(*tasks, return_exceptions=True)
