"""Validated metric depth and foreground estimates, adapted from BlindNav (MIT).

Copyright (c) 2026 Anthonyiswhy. See THIRD_PARTY_NOTICES.md for the MIT notice.
"""

import math
from dataclasses import dataclass

import numpy as np

from .types import BBox, DepthStatus, Mode, SensorProfile


@dataclass(frozen=True)
class DepthFrame:
    raw: np.ndarray
    capture_ms: int
    aligned_to_color: bool
    calibration_id: str


@dataclass(frozen=True)
class DepthEstimate:
    distance_m: float | None
    valid_samples: int
    quality: str
    peak_count: int = 0


def validate_depth(
    depth: DepthFrame | None,
    sensor: SensorProfile,
    capture_ms: int,
    image_size: tuple[int, int],
) -> tuple[DepthStatus, np.ndarray | None]:
    """image_size is (width, height); scale conversion happens only here."""
    if sensor.mode == Mode.RGB:
        return DepthStatus.NOT_SUPPORTED, None
    scale = sensor.depth_scale_m
    if scale is None or not math.isfinite(scale) or not 0.000001 <= scale <= 0.01:
        return DepthStatus.INVALID, None
    if not sensor.calibration_id or not 1 <= len(sensor.calibration_id) <= 80:
        return DepthStatus.INVALID, None
    if depth is None:
        return DepthStatus.MISSING, None
    width, height = image_size
    if (
        not isinstance(depth.raw, np.ndarray)
        or depth.raw.dtype != np.uint16
        or depth.raw.shape != (height, width)
        or depth.aligned_to_color is not True
        or depth.calibration_id != sensor.calibration_id
        or isinstance(depth.capture_ms, bool)
        or not isinstance(depth.capture_ms, int)
        or depth.capture_ms < 0
        or abs(depth.capture_ms - capture_ms) > 50
    ):
        return DepthStatus.INVALID, None
    return DepthStatus.VALID, depth.raw.astype(np.float64) * scale


def estimate_bbox_distance(depth_m: np.ndarray, bbox: BBox) -> DepthEstimate:
    height, width = depth_m.shape
    if len(bbox) != 4 or not all(math.isfinite(value) for value in bbox):
        return DepthEstimate(None, 0, "insufficient")
    x1, y1, x2, y2 = bbox
    if x2 <= x1 or y2 <= y1:
        return DepthEstimate(None, 0, "insufficient")
    left, right = max(0, int(x1 + 0.2 * (x2 - x1))), min(width, int(x2 - 0.2 * (x2 - x1)))
    top, bottom = max(0, int(y1 + 0.2 * (y2 - y1))), min(height, int(y2 - 0.2 * (y2 - y1)))
    if right <= left or bottom <= top:
        return DepthEstimate(None, 0, "insufficient")
    stride = max(2, math.floor(math.sqrt((right - left) * (bottom - top) / 4000)))
    samples = depth_m[top:bottom:stride, left:right:stride]
    valid = samples[np.isfinite(samples) & (samples > 0) & (samples < 8)]
    if valid.size < 30:
        return DepthEstimate(None, int(valid.size), "insufficient")
    low, high = np.percentile(valid, [10, 90])
    trimmed = valid[(valid >= low) & (valid <= high)]
    if trimmed.size < 20:
        trimmed = valid
    quartiles = np.percentile(trimmed, [25, 75])
    if quartiles[1] - quartiles[0] < 0.45:
        return DepthEstimate(float(np.median(trimmed)), int(valid.size), "compact")
    bins = np.floor(trimmed / 0.30).astype(np.int64)
    counts = np.bincount(bins, minlength=27)
    peaks = [
        index
        for index, count in enumerate(counts)
        if count > 0
        and count >= 0.18 * trimmed.size
        and (index == 0 or count >= counts[index - 1])
        and (index == len(counts) - 1 or count >= counts[index + 1])
    ]
    if peaks:
        return DepthEstimate(
            float(np.median(trimmed[bins == peaks[0]])), int(valid.size), "peak", len(peaks)
        )
    return DepthEstimate(float(np.median(trimmed)), int(valid.size), "median")


def estimate_center_distance(depth_m: np.ndarray) -> DepthEstimate:
    height, width = depth_m.shape
    samples = depth_m[
        int(0.25 * height) : int(0.95 * height), int(0.35 * width) : int(0.65 * width)
    ]
    valid = samples[np.isfinite(samples) & (samples > 0) & (samples < 8)]
    if valid.size < 200 or valid.size < 0.60 * samples.size:
        return DepthEstimate(None, int(valid.size), "insufficient")
    return DepthEstimate(float(np.percentile(valid, 10)), int(valid.size), "percentile10")
