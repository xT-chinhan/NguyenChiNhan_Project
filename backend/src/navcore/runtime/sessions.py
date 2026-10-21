"""RAM-only session ownership, admission and deterministic expiry."""

import asyncio
import time
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from navcore.api.errors import ApiError
from navcore.core.navigation import control_navigation
from navcore.core.obstacles import ObstacleAssessor
from navcore.core.policy import BASELINE, PolicyConfig
from navcore.core.tracking import ObjectTracker
from navcore.core.types import NavigationState, RouteSnapshot, SensorProfile, State
from navcore.runtime.telemetry import event

TERMINAL = {State.COMPLETED, State.STOPPED}
CAPTURING = {State.LOCALIZING, State.NAVIGATING, State.LOST}


@dataclass
class Challenge:
    seq: int
    token: str
    epoch: int
    issued_ms: float
    deadline_ms: float
    state: str = "awaiting"


@dataclass
class InstructionRecord:
    payload: dict
    epoch: int
    deadline_ms: float


@dataclass
class CoreState:
    navigation: NavigationState
    tracker: ObjectTracker
    assessor: ObstacleAssessor
    last_capture_ms: int | None = None
    last_lost_notice_ms: float | None = None


@dataclass
class RuntimeSession:
    device_id: UUID
    route: RouteSnapshot | None
    sensor: SensorProfile
    clock: object
    policy: PolicyConfig = BASELINE
    id: UUID = field(default_factory=uuid4)
    created_at: float = field(init=False)
    last_activity_at: float = field(init=False)
    expires_at: datetime = field(init=False)
    route_id: str = field(init=False)
    route_revision: int = field(init=False)
    checkpoint_count: int = field(init=False)
    core: CoreState = field(init=False)
    epoch: int = 0
    seq: int = 0
    challenge: Challenge | None = None
    instruction: InstructionRecord | None = None
    connection: object | None = None
    job: asyncio.Task | None = None
    terminal_at: float | None = None
    model_failures: int = 0
    event_loop_lag_ms: float = 0.0
    movement_held: bool = True
    hold_reason: str | None = "LOCALIZING"
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)

    def __post_init__(self):
        self.created_at = self.last_activity_at = self.clock()
        self.expires_at = datetime.now(UTC) + timedelta(minutes=30)
        self.route_id, self.route_revision = self.route.id, self.route.revision
        self.checkpoint_count = len(self.route.checkpoints)
        self.core = CoreState(
            NavigationState(), ObjectTracker(self.policy), ObstacleAssessor(self.policy)
        )

    @property
    def state(self):
        return self.core.navigation.state

    def now_ms(self):
        return self.clock() * 1000

    def snapshot(self):
        return {
            "id": str(self.id),
            "state": self.state.value,
            "mode": self.sensor.mode.value,
            "route_id": self.route_id,
            "route_revision": self.route_revision,
            "last_confirmed_seq": self.core.navigation.last_confirmed_seq,
            "target_seq": self.core.navigation.target_seq,
            "checkpoint_count": self.checkpoint_count,
            "stream_path": f"/v1/sessions/{self.id}/stream",
            "expires_at": self.expires_at.isoformat(),
        }

    def invalidate(self, reason: str, *, stop: bool = False):
        """Caller holds lock, or is the sole event-loop admission owner."""
        self.epoch += 1
        self.instruction = None
        if self.challenge is not None:
            self.challenge.state = "finished"
        navigation = self.core.navigation
        navigation.candidate = None
        navigation.pending_instruction_id = None
        navigation.pending_instruction_deadline_ms = None
        # Keep departure position evidence requirement after a hold.
        self.movement_held, self.hold_reason = True, reason
        if stop:
            navigation.state = State.STOPPED
            navigation.pending_departure_seq = None
            self.finish()
        elif self.state not in TERMINAL:
            navigation.state = State.PAUSED
        event(self, "session_stopped" if stop else "session_paused", code=reason)

    def finish(self):
        if self.terminal_at is None:
            self.terminal_at = self.clock()
        self.route = None
        self.core.tracker.reset()
        self.core.assessor = ObstacleAssessor(self.policy)
        self.core.navigation.candidate = None

    def control(self, command: str):
        if command in {"pause", "stop"}:
            if self.state in TERMINAL and command != "stop":
                raise ValueError("SESSION_TERMINAL")
            self.invalidate(command.upper(), stop=command == "stop")
        elif command == "resume":
            if self.state in TERMINAL:
                raise ValueError("SESSION_TERMINAL")
            if self.state in {State.PAUSED, State.LOST}:
                self.invalidate("LOCALIZING")
                self.core.navigation = control_navigation(
                    self.core.navigation, command, self.now_ms(), self.route
                )
                # Assessor latch survives reconnect/resume; motion histories do not.
                self.core.tracker.reset()
                self.core.last_lost_notice_ms = None
                self.model_failures = 0
        self.last_activity_at = self.clock()


class SessionRegistry:
    def __init__(self, clock=None, policy=BASELINE, admission_lock=None, worker=None):
        self.clock = clock or time.monotonic
        self.policy = policy
        self.admission_lock = admission_lock or asyncio.Lock()
        self.worker = worker
        self.sessions: dict[UUID, RuntimeSession] = {}
        self.maintenance_task = None
        self.closed = False

    def active_count(self):
        return sum(session.state not in TERMINAL for session in self.sessions.values())

    async def create(self, device_id, route_id, sensor, loader, *loader_args):
        async with self.admission_lock:
            await self.expire()
            if any(
                s.device_id == device_id and s.state not in TERMINAL for s in self.sessions.values()
            ):
                raise ApiError("DEVICE_SESSION_EXISTS", 409, "Device already has an active session")
            if self.active_count() >= self.policy.max_active_sessions:
                raise ApiError("SESSION_CAPACITY", 503, "Session capacity reached")
            if self.worker is not None and self.worker.check_fault():
                raise ApiError("VISION_UNAVAILABLE", 503, "Vision is unavailable")
            route = await asyncio.to_thread(loader, *loader_args, route_id)
            session = RuntimeSession(device_id, route, sensor, self.clock, self.policy)
            self.sessions[session.id] = session
            event(session, "session_create", route_id=session.route_id)
            return session

    def owned(self, session_id, device_id):
        session = self.sessions.get(session_id)
        if session is None or session.device_id != device_id:
            raise ApiError("SESSION_NOT_FOUND", 404, "Session not found")
        return session

    async def expire(self):
        now = self.clock()
        for session in tuple(self.sessions.values()):
            async with session.lock:
                if session.state not in TERMINAL and (
                    now - session.created_at >= 1800 or now - session.last_activity_at >= 300
                ):
                    session.invalidate("SESSION_EXPIRED", stop=True)
                    if session.connection is not None:
                        session.connection.terminate(1008, "SESSION_EXPIRED")
                elif session.terminal_at is not None and now - session.terminal_at >= 300:
                    if session.connection is not None:
                        session.connection.terminate(1000, "SESSION_EXPIRED")
                    self.sessions.pop(session.id, None)

    async def maintenance(self):
        expected = self.clock() + self.policy.watchdog_interval_ms / 1000
        while not self.closed:
            await asyncio.sleep(self.policy.watchdog_interval_ms / 1000)
            now = self.clock()
            lag = max(0.0, (now - expected) * 1000)
            expected = now + self.policy.watchdog_interval_ms / 1000
            await self.expire()
            faulted = self.worker is not None and self.worker.check_fault()
            for session in tuple(self.sessions.values()):
                async with session.lock:
                    session.event_loop_lag_ms = lag
                    if (
                        faulted
                        and session.state not in TERMINAL
                        and session.hold_reason != "VISION_UNAVAILABLE"
                    ):
                        session.invalidate("VISION_UNAVAILABLE")
                        if session.connection is not None:
                            session.connection.status("VISION_UNAVAILABLE")

    def start(self):
        if self.maintenance_task is None:
            self.maintenance_task = asyncio.create_task(self.maintenance())

    async def close(self):
        self.closed = True
        if self.maintenance_task is not None:
            self.maintenance_task.cancel()
            await asyncio.gather(self.maintenance_task, return_exceptions=True)
        for session in tuple(self.sessions.values()):
            async with session.lock:
                session.invalidate("SERVER_SHUTDOWN", stop=True)
                if session.connection is not None:
                    session.connection.terminate(1001, "SERVER_SHUTDOWN")
        self.sessions.clear()
