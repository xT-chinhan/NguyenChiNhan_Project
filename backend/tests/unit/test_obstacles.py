"""Policy truth tables use independently chosen metric scenes, not model fixtures."""

import numpy as np
import pytest

from navcore.core.depth import DepthFrame
from navcore.core.obstacles import ObstacleAssessor
from navcore.core.types import (
    DepthStatus,
    InstructionCode,
    Mode,
    Priority,
    SensorProfile,
    TrackState,
)

Code = InstructionCode


RGB = SensorProfile(Mode.RGB)
RGBD = SensorProfile(Mode.RGBD, 0.001, "aligned")


def item(ms=0, hits=3, confidence=0.8, bbox=(20, 20, 80, 90)):
    return TrackState(1, 0, "person", bbox, confidence, hits, ms)


def assess(assessor, raw=None, tracks=(), ms=0, sensor=RGBD, seq=None):
    frame = None if raw is None else DepthFrame(raw, ms, True, "aligned")
    return assessor.assess(
        list(tracks),
        frame,
        sensor,
        ms,
        image_size=(100, 100),
        frame_seq=ms if seq is None else seq,
    )


def uniform(distance):
    return np.full((100, 100), round(distance * 1000), dtype=np.uint16)


def test_rgb_notice_requires_hits_and_has_no_fabricated_metrics():
    result = assess(ObstacleAssessor(), tracks=[item(hits=2)], sensor=RGB)
    assert not result.hold
    result = assess(ObstacleAssessor(), tracks=[item()], sensor=RGB)
    assert result.hold and result.code == Code.OBJECT_AHEAD
    assert result.depth_status == DepthStatus.NOT_SUPPORTED
    assert result.observations[0].distance_m is None and result.observations[0].ttc_s is None


@pytest.mark.parametrize(
    "kwargs",
    [
        {"confidence": 0.49},
        {"bbox": (0, 0, 20, 90)},
        {"bbox": (20, 20, 80, 64)},
        {"bbox": (45, 60, 55, 90)},
    ],
)
def test_rgb_heuristic_rejects_confidence_side_high_or_small_boxes(kwargs):
    assert not assess(ObstacleAssessor(), tracks=[item(**kwargs)], sensor=RGB).hold


def test_rgb_cooldown_suppresses_only_voice_and_is_per_session():
    assessor = ObstacleAssessor()
    assert assess(assessor, tracks=[item()], sensor=RGB).code == Code.OBJECT_AHEAD
    repeated = assess(assessor, tracks=[item(100)], ms=100, sensor=RGB)
    assert repeated.code is None and repeated.hold and repeated.priority == Priority.WARNING
    isolated = assess(ObstacleAssessor(), tracks=[item(100)], ms=100, sensor=RGB)
    assert isolated.code == Code.OBJECT_AHEAD
    assert assess(assessor, tracks=[item(3000)], ms=3000, sensor=RGB).code == Code.OBJECT_AHEAD
    assert not assess(assessor, tracks=[], ms=3100, sensor=RGB).hold


@pytest.mark.parametrize(
    ("distance", "code"),
    [
        (0.399, Code.EMERGENCY_STOP),
        (0.4, Code.OBSTACLE_NEAR),
        (0.799, Code.OBSTACLE_NEAR),
        (0.8, None),
    ],
)
def test_center_distance_strict_thresholds_without_detection(distance, code):
    result = assess(ObstacleAssessor(), uniform(distance))
    assert result.code == code and result.hold == (code is not None)


@pytest.mark.parametrize(
    ("distance", "code"),
    [
        (0.399, Code.EMERGENCY_STOP),
        (0.4, Code.OBSTACLE_NEAR),
        (0.699, Code.OBSTACLE_NEAR),
        (0.7, None),
    ],
)
def test_bbox_distance_does_not_wait_for_track_confirmation(distance, code):
    raw = uniform(2)
    raw[2:18, 2:18] = round(distance * 1000)
    result = assess(ObstacleAssessor(), raw, [item(hits=1, bbox=(0, 0, 20, 20))])
    assert result.code == code


def test_missing_and_invalid_depth_remove_previous_distance_and_velocity():
    assessor, target = ObstacleAssessor(), item()
    assert assess(assessor, uniform(2), [target]).observations[0].distance_m == 2
    target.last_seen_ms = 100
    result = assess(assessor, tracks=[target], ms=100)
    assert result.depth_status == DepthStatus.MISSING and result.code == Code.DEPTH_UNAVAILABLE
    assert target.distance_m is None and target.ttc_s is None and target.distance_history == []
    target.last_seen_ms = 200
    result = assess(assessor, np.ones((99, 100), dtype=np.uint16), [target], ms=200)
    assert result.depth_status == DepthStatus.INVALID and result.hold


def test_insufficient_center_holds_but_keeps_valid_bbox_distance():
    raw = np.zeros((100, 100), dtype=np.uint16)
    raw[:20, :20] = 1200
    result = assess(ObstacleAssessor(), raw, [item(hits=1, bbox=(0, 0, 20, 20))])
    assert result.depth_status == DepthStatus.INSUFFICIENT
    assert result.code == Code.DEPTH_UNAVAILABLE and result.hold
    assert result.observations[0].distance_m == 1.2


def test_measured_emergency_retains_priority_when_center_is_insufficient():
    raw = np.zeros((100, 100), dtype=np.uint16)
    raw[:20, :20] = 300
    result = assess(ObstacleAssessor(), raw, [item(hits=1, bbox=(0, 0, 20, 20))])
    assert result.depth_status == DepthStatus.INSUFFICIENT and result.hold
    assert result.code == Code.EMERGENCY_STOP and result.priority == Priority.EMERGENCY


def test_latch_needs_three_distinct_valid_center_frames_and_missing_resets_count():
    assessor = ObstacleAssessor()
    assert assess(assessor, uniform(0.5)).hold
    assert assess(assessor, uniform(1), ms=100).hold
    assert assess(assessor, uniform(1), ms=100).hold
    assert assess(assessor, uniform(1), ms=200).hold
    assert assess(assessor, ms=300).hold
    assert assess(assessor, uniform(1), ms=400).hold
    assert assess(assessor, uniform(1), ms=500).hold
    result = assess(assessor, uniform(1), ms=600)
    assert not result.hold and result.code is None


def test_below_clear_range_retains_latch_and_emergency_escalates_immediately():
    assessor = ObstacleAssessor()
    assert assess(assessor, uniform(0.5)).code == Code.OBSTACLE_NEAR
    assert assess(assessor, uniform(0.3), ms=100).code == Code.EMERGENCY_STOP
    for ms in [200, 300, 400]:
        assert assess(assessor, uniform(0.899), ms=ms).hold
    for ms in [500, 600, 700]:
        result = assess(assessor, uniform(0.9), ms=ms)
    assert not result.hold
    assert assess(assessor, uniform(0.3), ms=800).code == Code.EMERGENCY_STOP


def test_ttc_uses_approach_and_beats_distance_notice():
    assessor, target = ObstacleAssessor(), item()
    for ms, distance in [(0, 2.25), (125, 2.125), (250, 2.0)]:
        target.last_seen_ms = ms
        result = assess(assessor, uniform(distance), [target], ms=ms)
    assert target.ttc_s == pytest.approx(2.0)
    assert result.code == Code.OBSTACLE_NEAR and result.hold
    target.last_seen_ms = 375
    result = assess(assessor, uniform(1.875), [target], ms=375)
    assert result.code == Code.EMERGENCY_STOP


def test_unseen_track_never_generates_new_obstacle():
    result = assess(ObstacleAssessor(), tracks=[item(ms=0)], ms=100, sensor=RGB)
    assert result.observations == () and not result.hold
