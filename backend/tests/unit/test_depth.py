"""Deterministic metric cases; nearest foreground deliberately differs from BlindNav."""

import numpy as np
import pytest

from navcore.core.depth import (
    DepthFrame,
    estimate_bbox_distance,
    estimate_center_distance,
    validate_depth,
)
from navcore.core.types import DepthStatus, Mode, SensorProfile

SENSOR = SensorProfile(Mode.RGBD, 0.001, "aligned")


def test_scale_is_explicit_and_registration_must_match():
    raw = np.full((100, 100), 1200, dtype=np.uint16)
    status, metres = validate_depth(DepthFrame(raw, 50, True, "aligned"), SENSOR, 0, (100, 100))
    assert status == DepthStatus.VALID
    assert estimate_bbox_distance(metres, (0, 0, 100, 100)).distance_m == pytest.approx(1.2)
    for depth in [
        DepthFrame(raw, 51, True, "aligned"),
        DepthFrame(raw, 0, False, "aligned"),
        DepthFrame(raw, 0, True, "other"),
        DepthFrame(raw[:, :99], 0, True, "aligned"),
        DepthFrame(raw.astype(np.uint8), 0, True, "aligned"),
    ]:
        assert validate_depth(depth, SENSOR, 0, (100, 100)) == (DepthStatus.INVALID, None)


def test_missing_rgb_and_bad_scale_are_explicit():
    assert validate_depth(None, SENSOR, 0, (100, 100)) == (DepthStatus.MISSING, None)
    assert validate_depth(None, SensorProfile(Mode.RGB), 0, (100, 100)) == (
        DepthStatus.NOT_SUPPORTED,
        None,
    )
    for scale in [None, 0, float("nan"), 0.1]:
        assert validate_depth(None, SensorProfile(Mode.RGBD, scale, "aligned"), 0, (100, 100)) == (
            DepthStatus.INVALID,
            None,
        )


@pytest.mark.parametrize("value", [0, 8, 9, float("nan"), float("inf"), -1])
def test_invalid_samples_and_tiny_roi_have_no_distance(value):
    metres = np.full((100, 100), value)
    assert estimate_bbox_distance(metres, (0, 0, 100, 100)).distance_m is None
    assert estimate_bbox_distance(np.ones((100, 100)), (0, 0, 5, 5)).distance_m is None


def test_only_center_sixty_percent_of_bbox_is_used():
    metres = np.full((100, 100), 7.0)
    metres[20:80, 20:80] = 1.2
    assert estimate_bbox_distance(metres, (0, 0, 100, 100)).distance_m == 1.2


def test_nearer_supported_peak_wins_over_larger_background_peak():
    metres = np.full((100, 100), 4.1)
    metres[20:38, 20:80] = 1.1
    result = estimate_bbox_distance(metres, (0, 0, 100, 100))
    assert result.peak_count == 2 and result.quality == "peak"
    assert result.distance_m == 1.1


def test_peak_zero_origin_and_bin_sample_median_not_bin_center():
    metres = np.full((100, 100), 3.1)
    metres[20:38, 20:80] = 0.12
    assert estimate_bbox_distance(metres, (0, 0, 100, 100)).distance_m == 0.12


def test_equal_neighbor_peak_counts_are_supported_local_maxima():
    metres = np.full((100, 100), 3.1)
    metres[20:40, 20:80] = 0.9
    metres[40:60, 20:80] = 1.2
    assert estimate_bbox_distance(metres, (0, 0, 100, 100)).distance_m == 0.9


def test_support_denominator_is_after_trim():
    # 900 samples:90 low,135 near,135 middle,450 far,90 high. Trim leaves720;
    # near support is18.75%, although it was only15% before trimming.
    values = np.concatenate(
        [
            np.full(90, 0.1),
            np.full(135, 1.1),
            np.full(135, 2.1),
            np.full(450, 3.1),
            np.full(90, 7.9),
        ]
    )
    metres = np.zeros((100, 100))
    metres[20:80:2, 20:80:2] = values.reshape(30, 30)
    result = estimate_bbox_distance(metres, (0, 0, 100, 100))
    assert result.distance_m == 1.1 and result.peak_count == 3


def test_center_requires_two_hundred_samples_and_sixty_percent_coverage():
    metres = np.zeros((100, 100))
    region = metres[25:95, 35:65]
    region.flat[:1259] = 1.0
    assert estimate_center_distance(metres).distance_m is None
    region.flat[1259] = 1.0
    assert estimate_center_distance(metres).distance_m == 1.0
    assert estimate_center_distance(np.ones((20, 20))).distance_m is None


def test_center_uses_percentile_ten_not_median():
    metres = np.full((100, 100), 2.0)
    metres[25:39, 35:65] = 0.3
    assert estimate_center_distance(metres).distance_m == 0.3
