"""Client instruction TTL, bounded deduplication and watchdog state."""

from collections import OrderedDict

from navcore.schemas.events import Instruction

MOVEMENT = {"CONTINUE_STRAIGHT", "TURN_LEFT", "TURN_RIGHT", "ARRIVED"}


class PresentationGuard:
    """No heartbeat can renew capture age, instruction TTL, or freshness watchdog."""

    def __init__(self, started_ms: int, max_ids: int = 4096):
        self.captures: OrderedDict[int, dict] = OrderedDict()
        self.seen: OrderedDict[str, float] = OrderedDict()
        self.results: OrderedDict[int, None] = OrderedDict()
        self.max_ids = max_ids
        self.last_fresh_ms = started_ms
        self.stale_announced = False
        self.pending = None

    def capture(self, seq: int, capture_ms: int, pts_ms: float, requested_ms: int) -> None:
        self.captures[seq] = {
            "capture_monotonic_ms": capture_ms,
            "video_pts_ms": pts_ms,
            "requested_monotonic_ms": requested_ms,
        }
        while len(self.captures) > 256:
            self.captures.popitem(last=False)

    def watchdog(self, now_ms: int) -> dict | None:
        if now_ms - self.last_fresh_ms >= 1500 and not self.stale_announced:
            self.pending = None
            self.stale_announced = True
            return {
                "type": "client_status",
                "code": "STREAM_STALE",
                "monotonic_ms": now_ms,
                "presentation_kind": "stdout_simulation",
            }
        return None

    def handle(self, message: dict, received_ms: int) -> list[dict]:
        kind = message.get("type")
        result = []
        capture = None
        if kind == "frame_result":
            capture = self.captures.get(message.get("seq"))
            if (
                capture is None
                or message.get("capture_monotonic_ms") != capture["capture_monotonic_ms"]
            ):
                return [{"type": "client_rejected", "code": "UNKNOWN_FRAME_IDENTITY"}]
            age = received_ms - capture["capture_monotonic_ms"]
            duplicate_result = message["seq"] in self.results
            self.results[message["seq"]] = None
            while len(self.results) > 256:
                self.results.popitem(last=False)
            fresh = 0 <= age < 1000 and not duplicate_result
            if fresh:
                self.last_fresh_ms, self.stale_announced = received_ms, False
            timing = message.get("timing", {})
            result.append(
                {
                    "type": "frame_result",
                    "seq": message["seq"],
                    **capture,
                    "received_monotonic_ms": received_ms,
                    "capture_age_ms": age,
                    "request_to_receive_ms": received_ms - capture["requested_monotonic_ms"],
                    "accepted_fresh": fresh,
                    "state": message.get("state"),
                    "last_confirmed_seq": message.get("last_confirmed_seq"),
                    "target_seq": message.get("target_seq"),
                    "movement_held": message.get("movement_held"),
                    "hold_reason": message.get("hold_reason"),
                    "localization": {
                        key: message.get("localization", {}).get(key)
                        for key in (
                            "confirmed",
                            "candidate_seq",
                            "orientation_verified",
                            "similarity",
                            "margin",
                        )
                    },
                    "obstacles": [
                        {
                            key: obstacle.get(key)
                            for key in (
                                "track_id",
                                "class_name",
                                "bbox",
                                "confidence",
                                "position",
                                "distance_m",
                                "ttc_s",
                            )
                        }
                        for obstacle in message.get("obstacles", [])[:100]
                    ],
                    "timing": {
                        key: timing.get(key)
                        for key in (
                            "decode_ms",
                            "queue_ms",
                            "inference_ms",
                            "core_ms",
                            "request_to_result_ms",
                            "event_loop_lag_ms",
                        )
                    },
                }
            )
            if message.get("movement_held") is not False or not fresh:
                self.pending = None
        if kind in {"status", "error"} or (
            kind == "control_result" and message.get("command") in {"pause", "stop"}
        ):
            self.pending = None
            result.append(
                {
                    "type": kind,
                    "code": str(message.get("code", ""))[:80],
                    "state": message.get("state"),
                }
            )
        raw = message.get("instruction") if kind in {"frame_result", "control_result"} else None
        if raw is None:
            return result
        try:
            instruction = Instruction.model_validate(raw).model_dump(mode="json")
        except ValueError:
            return result + [{"type": "client_rejected", "code": "INVALID_INSTRUCTION"}]
        identity = instruction["id"]
        duplicate = identity in self.seen
        result.append(
            {
                "type": "instruction_received",
                "instruction_id": identity,
                "duplicate": duplicate,
                "received_monotonic_ms": received_ms,
            }
        )
        manual_repeat = kind == "control_result" and message.get("command") == "repeat"
        if duplicate and not manual_repeat:
            return result
        previous_deadline = self.seen.get(identity, float("inf"))
        self.seen[identity] = min(previous_deadline, received_ms + instruction["valid_for_ms"])
        while len(self.seen) > self.max_ids:
            self.seen.popitem(last=False)
        if instruction["priority"] in {"warning", "emergency"}:
            self.pending = None
        local = self.captures.get(instruction["frame_seq"])
        capture_ms = instruction["capture_monotonic_ms"]
        age = received_ms - capture_ms
        valid = (
            local is not None
            and local["capture_monotonic_ms"] == capture_ms
            and 0 <= age < 1000
            and instruction["valid_for_ms"] > 0
            and received_ms < self.seen[identity]
        )
        held = kind == "frame_result" and (
            message.get("movement_held") is not False or duplicate_result
        )
        if not valid or (held and instruction["code"] in MOVEMENT):
            return result + [
                {
                    "type": "instruction_dropped",
                    "instruction_id": identity,
                    "code": instruction["code"],
                    "reason": "HELD" if held else "EXPIRED_OR_UNKNOWN_CAPTURE",
                }
            ]
        self.pending = {
            "instruction": instruction,
            "received_ms": received_ms,
            "deadline_ms": min(
                capture_ms + 1000, received_ms + instruction["valid_for_ms"], self.seen[identity]
            ),
            "video_pts_ms": local["video_pts_ms"],
        }
        return result

    def present(self, now_ms: int) -> dict | None:
        pending, self.pending = self.pending, None
        if pending is None:
            return None
        instruction = pending["instruction"]
        if not now_ms < pending["deadline_ms"]:
            return {
                "type": "instruction_dropped",
                "instruction_id": instruction["id"],
                "code": instruction["code"],
                "reason": "EXPIRED_BEFORE_PRESENTATION",
            }
        return {
            "type": "instruction_presented",
            "instruction_id": instruction["id"],
            "code": instruction["code"],
            "text_vi": instruction["text_vi"],
            "frame_seq": instruction["frame_seq"],
            "video_pts_ms": pending["video_pts_ms"],
            "capture_monotonic_ms": instruction["capture_monotonic_ms"],
            "received_monotonic_ms": pending["received_ms"],
            "presented_monotonic_ms": now_ms,
            "valid_until_monotonic_ms": pending["deadline_ms"],
            "presentation_kind": "stdout_simulation",
        }
