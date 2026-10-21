"""Pure, per-session navigation data. No framework or model imports."""

from dataclasses import dataclass, field
from enum import StrEnum

BBox = tuple[float, float, float, float]
Vector = tuple[float, ...]


class State(StrEnum):
    LOCALIZING = "localizing"
    NAVIGATING = "navigating"
    LOST = "lost"
    PAUSED = "paused"
    COMPLETED = "completed"
    STOPPED = "stopped"


class Mode(StrEnum):
    RGB = "rgb"
    RGBD = "rgbd"


class Action(StrEnum):
    STRAIGHT = "straight"
    LEFT = "left"
    RIGHT = "right"
    ARRIVE = "arrive"


class Priority(StrEnum):
    INFO = "info"
    GUIDANCE = "guidance"
    WARNING = "warning"
    EMERGENCY = "emergency"


class InstructionCode(StrEnum):
    CONTINUE_STRAIGHT = "CONTINUE_STRAIGHT"
    TURN_LEFT = "TURN_LEFT"
    TURN_RIGHT = "TURN_RIGHT"
    ARRIVED = "ARRIVED"
    HOLD_POSITION = "HOLD_POSITION"
    OBJECT_AHEAD = "OBJECT_AHEAD"
    EMERGENCY_STOP = "EMERGENCY_STOP"
    OBSTACLE_NEAR = "OBSTACLE_NEAR"
    OBSTACLE_NOTICE = "OBSTACLE_NOTICE"
    DEPTH_UNAVAILABLE = "DEPTH_UNAVAILABLE"
    WAIT_FOR_FRESH_FRAME = "WAIT_FOR_FRESH_FRAME"


class DepthStatus(StrEnum):
    NOT_SUPPORTED = "not_supported"
    VALID = "valid"
    MISSING = "missing"
    INVALID = "invalid"
    INSUFFICIENT = "insufficient"


@dataclass(frozen=True)
class SensorProfile:
    mode: Mode
    depth_scale_m: float | None = None
    calibration_id: str | None = None


@dataclass(frozen=True)
class Detection:
    class_id: int
    class_name: str
    bbox: BBox
    confidence: float


@dataclass
class TrackState:
    track_id: int
    class_id: int
    class_name: str
    bbox: BBox
    confidence: float
    hits: int
    last_seen_ms: int
    position: str = "ahead"
    position_candidate: str | None = None
    position_hits: int = 0
    position_frame_seq: int = -1
    distance_m: float | None = None
    ttc_s: float | None = None
    distance_history: list[tuple[int, float]] = field(default_factory=list)
    range_velocity_mps: float | None = None
    pending_jump_m: float | None = None


@dataclass(frozen=True)
class Reference:
    id: str
    pixel_sha256: str
    embedding: Vector
    encoder_fingerprint: str
    jpeg_bytes: bytes = b""
    source_group: str = "synthetic"


@dataclass(frozen=True)
class Checkpoint:
    id: str
    seq: int
    depart_action: Action
    landmark: str
    heading_deg: float | None = None
    heading_accuracy_deg: float | None = None
    references: tuple[Reference, ...] = ()


@dataclass(frozen=True)
class RouteSnapshot:
    id: str
    revision: int
    encoder_fingerprint: str
    route_fingerprint: str | None
    checkpoints: tuple[Checkpoint, ...]


@dataclass(frozen=True)
class MatchResult:
    candidate_seq: int | None
    similarity: float
    margin: float
    accepted: bool
    orientation_verified: bool = False


@dataclass(frozen=True)
class FrameIdentity:
    seq: int
    capture_ms: int
    image_hash: str


@dataclass
class Candidate:
    seq: int
    frames: list[FrameIdentity] = field(default_factory=list)


@dataclass
class NavigationState:
    state: State = State.LOCALIZING
    last_confirmed_seq: int = -1
    target_seq: int = 0
    candidate: Candidate | None = None
    last_position_ms: float | None = None
    resume_allowed_seqs: tuple[int, ...] | None = None
    pending_departure_seq: int | None = None
    pending_instruction_id: str | None = None
    pending_instruction_deadline_ms: float | None = None


@dataclass(frozen=True)
class NavigationProposal:
    next_state: NavigationState
    code: InstructionCode | None = None
    confirmed: bool = False
    match: MatchResult | None = None


@dataclass(frozen=True)
class ObstacleResult:
    observations: tuple[TrackState, ...]
    depth_status: DepthStatus
    hold: bool = False
    code: InstructionCode | None = None
    priority: Priority | None = None
    cooldown_key: tuple = ()


@dataclass(frozen=True)
class Decision:
    next_state: NavigationState
    code: InstructionCode | None
    priority: Priority | None
    hold: bool
    reason: str | None = None
