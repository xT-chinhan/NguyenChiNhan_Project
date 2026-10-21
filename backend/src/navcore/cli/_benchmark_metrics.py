"""Measured-window statistics and acceptance decisions, without invented observations."""

import math
from collections import Counter, deque
from dataclasses import dataclass
from uuid import UUID

TIMING_FIELDS = (
    "decode_ms",
    "queue_ms",
    "inference_ms",
    "core_ms",
    "request_to_result_ms",
    "event_loop_lag_ms",
)


def finite_number(value) -> bool:
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def quantiles(values: list[float]) -> dict:
    """Nearest-rank percentiles; accepted results include measurement-window tails."""
    if any(not finite_number(value) for value in values):
        raise ValueError("Invalid metric sample")
    ordered = sorted(values)
    return {
        "count": len(ordered),
        **{
            name: ordered[math.ceil(q * len(ordered)) - 1] if ordered else None
            for name, q in (("p50", 0.50), ("p95", 0.95), ("p99", 0.99))
        },
    }


@dataclass
class Request:
    session: str
    seq: int
    requested_at: float
    measured: bool
    capture_ms: int | None = None
    sent: bool = False
    completed: bool = False


class Metrics:
    def __init__(self, started_at: float, warmup: float, duration: float, sessions: int):
        self.started_at = started_at
        self.warmup, self.duration = warmup, duration
        self.measurement_start = started_at + warmup
        self.measurement_end = self.measurement_start + duration
        self.sessions = sessions
        self.pending: dict[tuple[str, int], Request] = {}
        self.counts = Counter(
            {
                key: 0
                for key in (
                    "frames_requested",
                    "frames_sent",
                    "frames_received",
                    "frames_rejected",
                    "frames_expired",
                    "frames_unresolved",
                    "instructions_received",
                    "instructions_presented",
                    "instructions_dropped",
                    "stale_instruction_proposals",
                    "stale_instructions_presented",
                    "stale_results_received",
                    "http_ping_failures",
                )
            }
        )
        self.per_session: Counter = Counter()
        self.rejection_codes: Counter = Counter()
        self.errors: Counter = Counter()
        self.client_ms: list[float] = []
        self.rtt_ms: list[float] = []
        self.timing: dict[str, list] = {key: [] for key in TIMING_FIELDS}

    def begin(self, started_at: float) -> None:
        self.started_at = started_at
        self.measurement_start = started_at + self.warmup
        self.measurement_end = self.measurement_start + self.duration

    def measured(self, now: float) -> bool:
        return self.measurement_start <= now < self.measurement_end

    def request(self, session: str, seq: int, now: float) -> Request | None:
        if now >= self.measurement_end:
            return None
        key = (session, seq)
        if key in self.pending:
            raise ValueError("Duplicate capture challenge")
        req = Request(session, seq, now, self.measured(now))
        self.pending[key] = req
        if req.measured:
            self.counts["frames_requested"] += 1
            self.per_session[session] += 1
        return req

    def sent(self, req: Request, capture_ms: int) -> None:
        req.capture_ms, req.sent = capture_ms, True
        if req.measured:
            self.counts["frames_sent"] += 1

    def _complete(self, req: Request) -> bool:
        if req.completed:
            raise ValueError("Duplicate frame outcome")
        req.completed = True
        self.pending.pop((req.session, req.seq), None)
        return req.measured

    def result(self, req: Request, now: float, payload: dict) -> None:
        if not self._complete(req):
            return
        self.counts["frames_received"] += 1
        self.client_ms.append(max(0, (now - req.requested_at) * 1000))
        timing = payload.get("timing")
        if isinstance(timing, dict):
            for key in TIMING_FIELDS:
                if finite_number(timing.get(key)):
                    self.timing[key].append(timing[key])

    def reject(self, req: Request, code: str) -> None:
        if self._complete(req):
            self.counts["frames_rejected"] += 1
            self.counts["frames_expired"] += code == "FRAME_EXPIRED"
            self.rejection_codes[code] += 1

    def finish_pending(self, now: float) -> None:
        for req in list(self.pending.values()):
            if self._complete(req):
                self.counts["frames_unresolved"] += 1

    def summary(self) -> dict:
        requested, received = self.counts["frames_requested"], self.counts["frames_received"]
        return {
            "counts": dict(self.counts),
            "requests_per_session": dict(self.per_session),
            "rejection_codes": dict(self.rejection_codes),
            "runtime_errors": dict(self.errors),
            "rejection_fraction": (
                (self.counts["frames_rejected"] + self.counts["frames_unresolved"]) / requested
                if requested
                else None
            ),
            "latency_ms": quantiles(self.client_ms),
            "server_timing_ms": {key: quantiles(values) for key, values in self.timing.items()},
            "http_health_rtt_ms": quantiles(self.rtt_ms),
            "timing_complete": bool(received)
            and all(len(values) == received for values in self.timing.values()),
        }


class InstructionGuard:
    """Immediate client presentation simulation with both protocol freshness bounds."""

    def __init__(self):
        self.seen: set[str] = set()
        self.order: deque[str] = deque()

    def fresh(self, instruction: dict, received_ms: float, now_ms: float) -> bool:
        capture, ttl = instruction.get("capture_monotonic_ms"), instruction.get("valid_for_ms")
        return (
            type(capture) is int
            and capture >= 0
            and finite_number(ttl)
            and ttl <= 1000
            and 0 <= now_ms - capture < 1000
            and received_ms <= now_ms < received_ms + ttl
        )

    def remember(self, instruction: dict) -> bool:
        try:
            identity = str(UUID(instruction["id"]))
        except (KeyError, TypeError, ValueError, AttributeError):
            raise ValueError("Invalid instruction identity") from None
        if identity in self.seen:
            return False
        if len(self.order) == 4096:
            self.seen.remove(self.order.popleft())
        self.order.append(identity)
        self.seen.add(identity)
        return True


def _at_most(value, limit):
    return value <= limit if finite_number(value) else None


def performance_decision(
    summary: dict,
    *,
    sessions: int,
    warmup: float,
    duration: float,
    completed: bool,
    attested: bool,
    real_models: bool,
    standard_frames: bool,
    standard_route: bool = True,
) -> dict:
    timings = summary["server_timing_ms"]
    checks = {
        "server_p95_at_most_700ms": _at_most(timings["request_to_result_ms"]["p95"], 700),
        "client_p95_at_most_900ms": _at_most(summary["latency_ms"]["p95"], 900),
        "client_p99_at_most_1000ms": _at_most(summary["latency_ms"]["p99"], 1000),
        "rejected_or_unresolved_at_most_1pct": _at_most(summary["rejection_fraction"], 0.01),
        "loop_lag_p95_at_most_50ms": _at_most(timings["event_loop_lag_ms"]["p95"], 50),
        "http_health_rtt_p95_at_most_100ms": _at_most(summary["http_health_rtt_ms"]["p95"], 100),
        "zero_stale_instructions_presented": summary["counts"]["stale_instructions_presented"] == 0,
    }
    if not attested:
        status = "BLOCKED_ATTESTATION"
    elif not real_models:
        status = "BLOCKED_MODEL"
    elif (warmup, duration) != (30, 300) or not standard_frames or not standard_route:
        status = "BLOCKED_PROFILE"
    elif not completed or summary["runtime_errors"] or summary["counts"]["http_ping_failures"]:
        status = "FAIL_RUNTIME"
    elif not summary["timing_complete"] or any(value is None for value in checks.values()):
        status = "BLOCKED_METRICS"
    elif sessions == 4:
        status = (
            "MEASURED_CAPACITY"
            if checks["zero_stale_instructions_presented"]
            and summary["counts"]["stale_results_received"] == 0
            and len(summary["requests_per_session"]) == 4
            else "FAIL_FRESHNESS"
        )
    else:
        status = "PASS" if all(checks.values()) else "FAIL_PERFORMANCE"
    return {
        "status": status,
        "scope": "one_session_latency" if sessions == 1 else "four_session_capacity_freshness",
        "checks": checks
        if sessions == 1
        else {
            "zero_stale_instructions_presented": checks["zero_stale_instructions_presented"],
            "all_sessions_measured": len(summary["requests_per_session"]) == 4,
            "zero_stale_results": summary["counts"]["stale_results_received"] == 0,
            "server_queue_concurrency_invariants": None,
        },
        "throughput_guarantee": False,
    }
