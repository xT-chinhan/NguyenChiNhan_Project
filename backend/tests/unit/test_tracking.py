"""Numeric core cases ported from BlindNav tracker/motion tests, with v1 changes."""

import pytest

from navcore.core.tracking import (
    ObjectTracker,
    intersection_over_union,
    update_position,
    update_range_motion,
)
from navcore.core.types import Detection, TrackState


def detection(box=(20, 20, 80, 80), cls=0, confidence=0.8):
    return Detection(cls, "person" if cls == 0 else "chair", box, confidence)


def track(cls=0):
    return TrackState(1, cls, "person" if cls == 0 else "chair", (20, 20, 80, 80), 0.8, 3, 0)


def test_iou_and_strict_threshold():
    assert intersection_over_union((0, 0, 10, 10), (0, 0, 3, 10)) == 0.30
    tracker = ObjectTracker()
    tracker.update([detection((0, 0, 10, 10))], 0)
    assert tracker.update([detection((0, 0, 3, 10))], 1)[0].track_id == 2


def test_new_and_existing_tracks_match_only_once():
    tracker = ObjectTracker()
    initial = tracker.update([detection(), detection(confidence=0.7)], 0)
    assert [(item.track_id, item.hits) for item in initial] == [(1, 1), (2, 1)]
    updated = tracker.update([detection(), detection(confidence=0.7)], 100)
    assert [(item.track_id, item.hits) for item in updated] == [(1, 2), (2, 2)]


def test_confidence_class_bbox_order_and_class_isolation():
    tracker = ObjectTracker()
    result = tracker.update([detection(cls=1), detection((30, 20, 90, 80)), detection()], 0)
    assert [(item.track_id, item.class_id, item.bbox[0]) for item in result] == [
        (1, 0, 20),
        (2, 0, 30),
        (3, 1, 20),
    ]
    assert ObjectTracker().update([detection()], 0)[0].track_id == 1


def test_second_hit_already_smooths_and_same_frame_does_not_increment():
    tracker = ObjectTracker()
    tracker.update([detection()], 0)
    item = tracker.update([detection((30, 20, 90, 80))], 100, frame_seq=2)[0]
    assert item.bbox == (26, 20, 86, 80)
    assert tracker.update([detection()], 100, frame_seq=2)[0].hits == 2


@pytest.mark.parametrize(("age", "expected"), [(1000, 1), (1001, 2)])
def test_expiry_boundary(age, expected):
    tracker = ObjectTracker()
    tracker.update([detection()], 0)
    assert tracker.update([detection()], age)[0].track_id == expected


def test_unseen_tracks_retained_for_matching_but_not_observation_or_motion():
    tracker = ObjectTracker()
    item = tracker.update([detection()], 0)[0]
    update_range_motion(item, 2, 0)
    assert tracker.update([], 100) == []
    assert len(tracker.tracks) == 1 and item.distance_history == []
    assert tracker.update([detection()], 200)[0].track_id == 1


def test_position_margin_needs_distinct_frames_and_caches_reads():
    item = track()
    item.bbox = (20, 0, 40, 80)
    assert update_position(item, 100, 0) == "left"
    item.bbox = (31, 0, 51, 80)
    assert update_position(item, 100, 1) == "left"
    item.bbox = (35, 0, 55, 80)
    assert update_position(item, 100, 2) == "left"
    assert update_position(item, 100, 2) == "left"
    assert update_position(item, 100, 3) == "ahead"
    item.bbox = (54, 0, 74, 80)
    assert update_position(item, 100, 4) == "ahead"
    assert update_position(item, 100, 5) == "right"


def test_capture_time_ols_and_ema_include_user_approach_to_wall():
    item = track(cls=1)
    for ms, distance in [(0, 3.0), (100, 2.9), (200, 2.8)]:
        update_range_motion(item, distance, ms)
    assert item.range_velocity_mps == pytest.approx(-1)
    assert item.ttc_s == pytest.approx(2.8)
    update_range_motion(item, 2.4, 300)
    # OLS slope of [3,2.9,2.8,2.4] at [0,.1,.2,.3] is -1.9; EMA gives -1.45.
    assert item.range_velocity_mps == pytest.approx(-1.45)
    assert item.ttc_s == pytest.approx(2.4 / 1.45)


def test_motion_minimum_span_noise_and_missing_reset():
    item = track()
    for ms, distance in [(0, 2), (50, 1.9), (100, 1.8)]:
        update_range_motion(item, distance, ms)
    assert item.range_velocity_mps is None and item.ttc_s is None
    update_range_motion(item, None, 125)
    for ms, distance in [(200, 4.0), (300, 3.96), (400, 3.92)]:
        update_range_motion(item, distance, ms)
    assert item.range_velocity_mps == 0 and item.ttc_s is None
    update_range_motion(item, None, 500)
    assert item.distance_m is None and item.distance_history == []


@pytest.mark.parametrize("gap", [501, 1001])
def test_clock_gap_resets_velocity(gap):
    item = track()
    for ms, distance in [(0, 2), (100, 1.9), (200, 1.8)]:
        update_range_motion(item, distance, ms)
    update_range_motion(item, 1.7, 200 + gap)
    assert item.range_velocity_mps is None and item.ttc_s is None


def test_jump_requires_two_agreeing_measurements_and_restarts_history():
    item = track()
    update_range_motion(item, 2, 0)
    update_range_motion(item, 5, 100)
    assert item.distance_m is None and item.ttc_s is None
    update_range_motion(item, 5.3, 200)
    assert item.distance_m == 5.3 and item.distance_history == [(200, 5.3)]
    assert item.range_velocity_mps is None


def test_jump_confirmation_includes_exact_point_four_boundary():
    item = track()
    for ms, distance in [(0, 2), (100, 5), (200, 5.4)]:
        update_range_motion(item, distance, ms)
    assert item.distance_m == 5.4 and item.distance_history == [(200, 5.4)]


def test_exact_one_point_five_change_is_not_a_pending_jump():
    item = track()
    update_range_motion(item, 0.6, 0)
    update_range_motion(item, 2.1, 100)
    assert item.distance_m == 2.1 and item.pending_jump_m is None


def test_approach_beyond_twelve_second_ttc_is_not_used():
    item = track()
    for ms, distance in [(0, 4), (250, 3.95), (500, 3.9)]:
        update_range_motion(item, distance, ms)
    assert item.ttc_s is None


def test_person_unphysical_slope_has_unknown_ttc_and_away_motion_has_no_ttc():
    item = track()
    for ms, distance in [(0, 5), (75, 4.3), (150, 3.6)]:
        update_range_motion(item, distance, ms)
    assert item.range_velocity_mps is None and item.ttc_s is None
    item = track()
    for ms, distance in [(0, 2), (100, 2.1), (200, 2.2)]:
        update_range_motion(item, distance, ms)
    assert item.range_velocity_mps == pytest.approx(1) and item.ttc_s is None
