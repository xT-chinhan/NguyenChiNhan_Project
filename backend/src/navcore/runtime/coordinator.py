"""Challenge lifecycle, off-loop work and atomic final freshness commit."""

import asyncio
from copy import deepcopy
from time import perf_counter
from uuid import uuid4

from navcore.core.messages import message
from navcore.core.navigation import ack_departure, bind_instruction, start_capture
from navcore.runtime import processing
from navcore.runtime.sessions import CAPTURING, TERMINAL, Challenge, InstructionRecord
from navcore.runtime.telemetry import event
from navcore.runtime.worker import WorkerBusy, WorkerFault
from navcore.vision.images import ImageError


class CommittedResult(dict):
    """Carry the commit epoch outside the wire payload across task scheduling."""

    def __init__(self, payload, epoch):
        super().__init__(payload)
        self.epoch = epoch


class Coordinator:
    def __init__(self, session, worker, vision):
        self.session, self.worker, self.vision = session, worker, vision

    def issue(self):
        session = self.session
        if session.state not in CAPTURING or session.route is None:
            return None
        previous = session.challenge
        if previous is not None and previous.state != "finished":
            return None
        now = session.now_ms()
        if (
            previous is not None
            and now - previous.issued_ms < 1000 / session.policy.max_request_rate_hz
        ):
            return None
        if session.job is not None and not session.job.done():
            return None
        session.seq += 1
        session.challenge = Challenge(
            session.seq,
            str(uuid4()),
            session.epoch,
            now,
            now + session.policy.request_deadline_ms,
        )
        session.core.navigation = start_capture(session.core.navigation, now)
        event(session, "frame_requested", seq=session.seq)
        return {
            "type": "capture_request",
            "seq": session.seq,
            "frame_token": session.challenge.token,
            "deadline_ms": session.policy.request_deadline_ms,
            "preferred_width": 640,
            "preferred_height": 480,
        }

    def valid(self, challenge, epoch):
        session = self.session
        return (
            session.challenge is challenge
            and challenge.state == "processing"
            and challenge.epoch == epoch == session.epoch
            and session.state in CAPTURING
            and session.route is not None
            and session.now_ms() < challenge.deadline_ms
        )

    def consume(self, frame):
        session = self.session
        challenge = session.challenge
        if (
            challenge is None
            or frame.seq != challenge.seq
            or str(frame.frame_token) != challenge.token
            or challenge.epoch != session.epoch
        ):
            raise processing.FrameError("FRAME_TOKEN_INVALID")
        if challenge.state != "awaiting":
            raise processing.FrameError("FRAME_DUPLICATE")
        challenge.state = "processing"  # retained through inference and completion
        if session.now_ms() >= challenge.deadline_ms:
            raise processing.FrameError("FRAME_EXPIRED")
        previous = session.core.last_capture_ms
        if previous is not None and frame.capture_monotonic_ms <= previous:
            raise processing.FrameError("CAPTURE_TIME_INVALID")
        session.last_activity_at = session.clock()
        return challenge

    def reject(self, code, challenge=None):
        session = self.session
        if challenge is None or session.challenge is challenge:
            if challenge is not None:
                challenge.state = "finished"
            session.core.navigation.candidate = None
        event(session, "frame_rejected", code=code, seq=challenge.seq if challenge else session.seq)
        return {
            "type": "frame_rejected",
            "seq": challenge.seq if challenge else session.seq,
            "code": code,
        }

    async def process(self, frame, challenge):
        session = self.session
        epoch = challenge.epoch
        try:
            image, depth, decode_ms = await asyncio.to_thread(
                processing.decode, frame, session.sensor
            )
        except processing.FrameError as error:
            return await self.failure(str(error), challenge, epoch)
        except (ImageError, ValueError, OSError):
            return await self.failure("IMAGE_INVALID", challenge, epoch)
        async with session.lock:
            if not self.valid(challenge, epoch):
                return None
        queued = perf_counter()
        try:
            vision = await self.worker.run(
                self.vision.infer, image.rgb, wait_ms=session.policy.model_slot_wait_ms
            )
        except WorkerBusy:
            return await self.failure("WORKER_BUSY", challenge, epoch)
        except WorkerFault:
            return await self.failure("VISION_UNAVAILABLE", challenge, epoch, model_error=True)
        except Exception:
            return await self.failure("VISION_UNAVAILABLE", challenge, epoch, model_error=True)
        elapsed = (perf_counter() - queued) * 1000
        inference_ms = max(0.0, float(vision.timings_ms.get("vision_ms", elapsed)))
        async with session.lock:
            if not self.valid(challenge, epoch):
                return None
            staged, route = deepcopy(session.core), session.route
            now_ms = session.now_ms()
        try:
            proposed = await asyncio.to_thread(
                processing.propose,
                staged,
                frame,
                image,
                depth,
                vision,
                route,
                session.sensor,
                session.policy,
                now_ms,
            )
        except Exception:
            return await self.failure("VISION_UNAVAILABLE", challenge, epoch, model_error=True)
        async with session.lock:
            # No await between this guard and complete swap of every mutable component.
            if not self.valid(challenge, epoch):
                return None
            staged, decision, proposal, obstacles, held, reason, core_ms = proposed
            now = session.now_ms()
            if now >= challenge.deadline_ms:
                return None
            instruction = None
            if held:
                if session.instruction is not None:
                    session.epoch += 1
                session.instruction = None
            if decision.code is not None:
                text, priority = message(decision.code)
                instruction = {
                    "id": str(uuid4()),
                    "code": decision.code.value,
                    "text_vi": text,
                    "priority": priority.value,
                    "valid_for_ms": max(0.0, challenge.deadline_ms - now),
                    "frame_seq": frame.seq,
                    "capture_monotonic_ms": frame.capture_monotonic_ms,
                    "replace_pending": True,
                }
                session.instruction = InstructionRecord(
                    instruction, session.epoch, challenge.deadline_ms
                )
                if (
                    priority.value == "guidance"
                    and staged.navigation.pending_departure_seq is not None
                ):
                    staged.navigation = bind_instruction(
                        staged.navigation, instruction["id"], challenge.deadline_ms
                    )
            session.core = staged
            event(
                session,
                "inference_complete",
                seq=frame.seq,
                inference_ms=inference_ms,
                core_ms=core_ms,
                decode_ms=decode_ms,
            )
            if proposal.confirmed and not decision.hold:
                event(
                    session,
                    "checkpoint_confirmed",
                    seq=frame.seq,
                    checkpoint_seq=staged.navigation.last_confirmed_seq,
                )
            if instruction is not None:
                event(
                    session,
                    "instruction_created",
                    seq=frame.seq,
                    code=instruction["code"],
                    instruction_id=instruction["id"],
                )
            session.model_failures = 0
            session.movement_held, session.hold_reason = held, reason
            challenge.state = "finished"
            result = CommittedResult(
                {
                    "type": "frame_result",
                    "seq": frame.seq,
                    "capture_monotonic_ms": frame.capture_monotonic_ms,
                    "state": session.state.value,
                    "last_confirmed_seq": staged.navigation.last_confirmed_seq,
                    "target_seq": staged.navigation.target_seq,
                    "localization": {
                        "candidate_seq": proposal.match.candidate_seq,
                        "similarity": proposal.match.similarity,
                        "margin": proposal.match.margin,
                        "confirmed": proposal.confirmed and not decision.hold,
                        "orientation_verified": proposal.match.orientation_verified,
                    },
                    "obstacles": [
                        {
                            "track_id": t.track_id,
                            "class_name": t.class_name,
                            "bbox": list(t.bbox),
                            "confidence": t.confidence,
                            "position": t.position,
                            "distance_m": t.distance_m,
                            "ttc_s": t.ttc_s,
                        }
                        for t in obstacles.observations
                    ],
                    "depth_status": obstacles.depth_status.value,
                    "movement_held": held,
                    "hold_reason": reason,
                    "instruction": instruction,
                    "timing": {
                        "decode_ms": decode_ms,
                        "queue_ms": max(0.0, elapsed - inference_ms),
                        "inference_ms": inference_ms,
                        "core_ms": core_ms,
                        "request_to_result_ms": max(0.0, now - challenge.issued_ms),
                        "event_loop_lag_ms": session.event_loop_lag_ms,
                    },
                },
                session.epoch,
            )
            if session.state in TERMINAL:
                session.finish()
            return result

    async def failure(self, code, challenge, epoch, model_error=False):
        session = self.session
        async with session.lock:
            if not self.valid(challenge, epoch):
                return None
            result = self.reject(code, challenge)
            if model_error:
                session.model_failures += 1
            if code == "WORKER_BUSY" or model_error:
                session.movement_held, session.hold_reason = True, code
                session.instruction = None
                session.core.navigation.pending_instruction_id = None
                session.core.navigation.pending_instruction_deadline_ms = None
                session.epoch += 1
                if session.model_failures >= 3 or self.worker.check_fault():
                    session.invalidate("VISION_UNAVAILABLE")
            return result

    def acknowledge(self, instruction_id, stage):
        session = self.session
        record = session.instruction
        if (
            record is not None
            and record.epoch == session.epoch
            and record.payload["id"] == str(instruction_id)
            and session.now_ms() < record.deadline_ms
        ):
            session.core.navigation = ack_departure(
                session.core.navigation, str(instruction_id), stage, session.now_ms()
            )

    def repeat(self):
        record, session = self.session.instruction, self.session
        if (
            record is None
            or record.epoch != session.epoch
            or session.now_ms() >= record.deadline_ms
        ):
            return None
        return {**record.payload, "valid_for_ms": record.deadline_ms - session.now_ms()}
