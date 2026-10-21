"""Versioned prototype thresholds; clients cannot override these."""

import hashlib
import json
import math
from dataclasses import asdict, dataclass


@dataclass(frozen=True)
class PolicyConfig:
    request_deadline_ms: int = 1000
    watchdog_interval_ms: int = 100
    max_request_rate_hz: int = 5
    model_slot_wait_ms: int = 100
    max_active_sessions: int = 4
    track_max_age_ms: int = 1000
    track_iou_threshold: float = 0.30
    track_confirm_hits: int = 3
    waypoint_confirm_hits: int = 3
    waypoint_confirm_window_ms: int = 1500
    match_threshold_straight: float = 0.88
    match_threshold_turn_or_final: float = 0.92
    match_margin: float = 0.04
    reference_ambiguity_limit: float = 0.97
    heading_max_error_deg: float = 25
    heading_max_accuracy_deg: float = 20
    localization_lost_ms: int = 15000
    initial_localization_timeout_ms: int = 15000
    detection_confidence_min: float = 0.38
    rgb_notice_confidence_min: float = 0.50
    obstacle_notice_cooldown_ms: int = 3000
    navigation_repeat_cooldown_ms: int = 5000

    def __post_init__(self) -> None:
        for name, value in asdict(self).items():
            if (
                isinstance(value, bool)
                or not isinstance(value, (int, float))
                or not math.isfinite(value)
                or value <= 0
            ):
                raise ValueError(f"Invalid policy field: {name}")
            if name.endswith(("_ms", "_hits", "_sessions", "_hz")) and type(value) is not int:
                raise ValueError(f"Integer policy field required: {name}")
        for name in (
            "track_iou_threshold",
            "match_threshold_straight",
            "match_threshold_turn_or_final",
            "match_margin",
            "reference_ambiguity_limit",
            "detection_confidence_min",
            "rgb_notice_confidence_min",
        ):
            if not 0 < getattr(self, name) <= 1:
                raise ValueError(f"Invalid ratio: {name}")

    @property
    def fingerprint(self) -> str:
        data = json.dumps(asdict(self), sort_keys=True, separators=(",", ":"), allow_nan=False)
        return hashlib.sha256(data.encode()).hexdigest()


BASELINE = PolicyConfig()
