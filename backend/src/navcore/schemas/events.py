from typing import Annotated, Literal
from uuid import UUID

from pydantic import Field, StrictInt

from navcore.core.types import DepthStatus, InstructionCode, Priority, State
from navcore.schemas.catalog import Contract


class Instruction(Contract):
    id: UUID
    code: InstructionCode
    text_vi: str
    priority: Priority
    valid_for_ms: Annotated[float, Field(ge=0, le=1000, strict=True)]
    frame_seq: StrictInt
    capture_monotonic_ms: StrictInt
    replace_pending: Literal[True] = True


class LocalizationView(Contract):
    candidate_seq: int | None
    similarity: Annotated[float, Field(ge=-1, le=1)]
    margin: Annotated[float, Field(ge=0, le=2)]
    confirmed: bool
    orientation_verified: bool


class ObstacleView(Contract):
    track_id: int
    class_name: str
    bbox: tuple[float, float, float, float]
    confidence: Annotated[float, Field(ge=0, le=1)]
    position: Literal["left", "ahead", "right"]
    distance_m: Annotated[float, Field(gt=0)] | None
    ttc_s: Annotated[float, Field(ge=0)] | None


class Timing(Contract):
    decode_ms: Annotated[float, Field(ge=0)]
    queue_ms: Annotated[float, Field(ge=0)]
    inference_ms: Annotated[float, Field(ge=0)]
    core_ms: Annotated[float, Field(ge=0)]
    request_to_result_ms: Annotated[float, Field(ge=0)]
    event_loop_lag_ms: Annotated[float, Field(ge=0)] = 0.0


class FrameResult(Contract):
    type: Literal["frame_result"] = "frame_result"
    seq: int
    capture_monotonic_ms: int
    state: State
    last_confirmed_seq: int
    target_seq: int
    localization: LocalizationView
    obstacles: list[ObstacleView]
    depth_status: DepthStatus
    movement_held: bool
    hold_reason: str | None
    instruction: Instruction | None
    timing: Timing
