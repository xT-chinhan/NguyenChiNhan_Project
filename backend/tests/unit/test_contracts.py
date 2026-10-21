import math
import uuid

import pytest
from pydantic import ValidationError

from navcore.schemas.catalog import CheckpointMetadata, SessionCreate
from navcore.schemas.stream import DepthFrame, Frame


def frame_values(**changes):
    return (
        dict(
            type="frame",
            seq=1,
            frame_token=str(uuid.uuid4()),
            capture_monotonic_ms=0,
            image_b64="AA==",
        )
        | changes
    )


@pytest.mark.parametrize(
    "changes",
    [
        {"seq": True},
        {"seq": 0},
        {"seq": 1.2},
        {"capture_monotonic_ms": -1},
        {"capture_monotonic_ms": False},
        {"heading_deg": math.nan},
        {"heading_deg": 360},
        {"heading_accuracy_deg": math.inf},
        {"vector": [1]},
        {"image_b64": "a" * 524289},
    ],
)
def test_bad_frames_rejected(changes):
    with pytest.raises(ValidationError):
        Frame.model_validate(frame_values(**changes))


def test_frame_round_trip_retains_unknown_values():
    frame = Frame.model_validate(frame_values())
    assert Frame.model_validate_json(frame.model_dump_json()) == frame
    assert frame.heading_deg is None and frame.depth is None


def test_rgbd_requires_explicit_calibration_and_scale():
    values = dict(route_id=str(uuid.uuid4()), language="vi-VN")
    for sensor in (
        {"mode": "rgbd"},
        {"mode": "rgbd", "calibration_id": "x", "depth_scale_m": True},
        {"mode": "rgb", "depth_scale_m": 0.001},
    ):
        with pytest.raises(ValidationError):
            SessionCreate.model_validate(values | {"sensor": sensor})
    assert SessionCreate.model_validate(values | {"sensor": {"mode": "rgb"}}).sensor.mode == "rgb"


@pytest.mark.parametrize("alignment", [1, False, "true"])
def test_depth_requires_real_boolean_alignment(alignment):
    with pytest.raises(ValidationError):
        DepthFrame(
            png_b64="AA==",
            capture_monotonic_ms=1,
            aligned_to_color=alignment,
            calibration_id="cal-01",
        )


def test_reference_accuracy_is_optional_but_requires_heading():
    values = dict(seq=0, depart_action="straight", landmark="Cửa", source_group="ref-01")
    assert CheckpointMetadata(**values).heading_accuracy_deg is None
    with pytest.raises(ValidationError):
        CheckpointMetadata(**values, heading_accuracy_deg=10)
