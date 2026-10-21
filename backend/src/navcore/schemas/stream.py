from typing import Annotated, Literal
from uuid import UUID

from pydantic import Field, StrictInt, model_validator

from navcore.schemas.catalog import Accuracy, Contract, Heading

Timestamp = Annotated[StrictInt, Field(ge=0)]
ImageData = Annotated[str, Field(min_length=1, max_length=524288, strict=True)]


class DepthFrame(Contract):
    png_b64: ImageData
    capture_monotonic_ms: Timestamp
    aligned_to_color: Literal[True]
    calibration_id: Annotated[str, Field(min_length=1, max_length=80, strict=True)]

    @model_validator(mode="before")
    @classmethod
    def boolean_alignment(cls, value):
        if isinstance(value, dict) and value.get("aligned_to_color") is not True:
            raise ValueError("Depth alignment must be true")
        return value


class Frame(Contract):
    type: Literal["frame"]
    seq: Annotated[StrictInt, Field(ge=1)]
    frame_token: UUID
    capture_monotonic_ms: Timestamp
    heading_deg: Heading | None = None
    heading_accuracy_deg: Accuracy | None = None
    image_b64: ImageData
    depth: DepthFrame | None = None


class Control(Contract):
    type: Literal["control"]
    command: Literal["pause", "resume", "repeat", "stop"]


class Ack(Contract):
    type: Literal["ack"]
    instruction_id: UUID
    stage: Literal["received", "presented"]
