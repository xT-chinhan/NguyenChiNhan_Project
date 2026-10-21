"""Strict wire contracts. Persistence never accepts a client-supplied embedding."""

from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StrictInt, field_validator, model_validator

from navcore.core.types import Action

Name = Annotated[str, Field(min_length=1, max_length=120, strict=True)]
Heading = Annotated[float, Field(ge=0, lt=360, strict=True)]
Accuracy = Annotated[float, Field(ge=0, le=180, strict=True)]


class Contract(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class Named(Contract):
    name: Name

    @field_validator("name")
    @classmethod
    def clean_name(cls, value: str) -> str:
        value = " ".join(value.split())
        if not value:
            raise ValueError("Name must not be blank")
        return value


class MapView(Named):
    id: UUID
    created_at: datetime


class PlaceView(MapView):
    map_id: UUID


class RouteCreate(Named):
    map_id: UUID
    from_place_id: UUID
    to_place_id: UUID

    @model_validator(mode="after")
    def distinct_endpoints(self):
        if self.from_place_id == self.to_place_id:
            raise ValueError("Route endpoints must differ")
        return self


class RouteView(RouteCreate):
    id: UUID
    revision: Annotated[StrictInt, Field(ge=1)]
    status: Literal["draft", "published"]
    encoder_fingerprint: str | None
    route_fingerprint: str | None
    created_at: datetime
    published_at: datetime | None


class CheckpointMetadata(Contract):
    seq: Annotated[StrictInt, Field(ge=0, le=63)]
    depart_action: Action
    landmark: Annotated[str, Field(max_length=120, strict=True)]
    heading_deg: Heading | None = None
    heading_accuracy_deg: Accuracy | None = None
    source_group: Annotated[str, Field(min_length=1, max_length=80, strict=True)]

    @model_validator(mode="after")
    def heading_pair(self):
        if self.heading_accuracy_deg is not None and self.heading_deg is None:
            raise ValueError("Heading accuracy requires heading")
        if not self.source_group.strip():
            raise ValueError("source_group must not be blank")
        return self


class Empty(Contract):
    pass


class RGBSensor(Contract):
    mode: Literal["rgb"]


class RGBDSensor(Contract):
    mode: Literal["rgbd"]
    depth_scale_m: Annotated[float, Field(ge=0.000001, le=0.01, strict=True)]
    calibration_id: Annotated[str, Field(min_length=1, max_length=80, strict=True)]


class SessionCreate(Contract):
    route_id: UUID
    sensor: Annotated[RGBSensor | RGBDSensor, Field(discriminator="mode")]
    language: Literal["vi-VN"]
