"""Session tracking and range motion, adapted from BlindNav (MIT).

Copyright (c) 2026 Anthonyiswhy. See THIRD_PARTY_NOTICES.md for the MIT notice.
"""

import math
from collections.abc import Iterable

from .policy import BASELINE, PolicyConfig
from .types import BBox, Detection, TrackState


def intersection_over_union(a: BBox, b: BBox) -> float:
    overlap = max(0.0, min(a[2], b[2]) - max(a[0], b[0])) * max(
        0.0, min(a[3], b[3]) - max(a[1], b[1])
    )
    union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - overlap
    return overlap / union if union > 0 else 0.0


def update_position(track: TrackState, image_width: int, frame_seq: int) -> str:
    """Cache each frame; changing a zone needs two observations beyond its margin."""
    if image_width <= 0:
        raise ValueError("image_width must be positive")
    if track.position_frame_seq == frame_seq:
        return track.position
    x = (track.bbox[0] + track.bbox[2]) / (2 * image_width)
    raw = "left" if x < 0.4 else "right" if x > 0.6 else "ahead"
    if track.position_frame_seq == -1:
        track.position = raw
    else:
        target = track.position
        if x < 0.37:
            target = "left"
        elif x > 0.63:
            target = "right"
        elif (track.position == "left" and x > 0.43) or (track.position == "right" and x < 0.57):
            target = "ahead"
        if target == track.position:
            track.position_candidate, track.position_hits = None, 0
        else:
            track.position_hits = (
                track.position_hits + 1 if target == track.position_candidate else 1
            )
            track.position_candidate = target
            if track.position_hits >= 2:
                track.position = target
                track.position_candidate, track.position_hits = None, 0
    track.position_frame_seq = frame_seq
    return track.position


class ObjectTracker:
    def __init__(self, policy: PolicyConfig = BASELINE) -> None:
        self.policy = policy
        self.tracks: dict[int, TrackState] = {}
        self.next_id = 1
        self._last_capture_ms: int | None = None
        self._last_frame_seq: int | None = None
        self._current: list[TrackState] = []

    def reset(self) -> None:
        self.tracks.clear()
        self._current = []
        self._last_capture_ms = self._last_frame_seq = None

    def update(
        self,
        detections: Iterable[Detection],
        capture_ms: int,
        *,
        frame_seq: int | None = None,
        image_width: int | None = None,
    ) -> list[TrackState]:
        """Return current tracks, retaining unseen tracks only for subsequent matching."""
        if capture_ms < 0:
            raise ValueError("capture_ms must be nonnegative")
        seq = capture_ms if frame_seq is None else frame_seq
        if self._last_capture_ms == capture_ms and self._last_frame_seq == seq:
            return self._current.copy()
        if self._last_capture_ms is not None and capture_ms <= self._last_capture_ms:
            raise ValueError("capture time must increase")
        self.tracks = {
            key: track
            for key, track in self.tracks.items()
            if capture_ms - track.last_seen_ms <= self.policy.track_max_age_ms
        }
        matched: set[int] = set()
        current = []
        for detection in sorted(detections, key=lambda d: (-d.confidence, d.class_id, d.bbox)):
            candidates = [
                (intersection_over_union(track.bbox, detection.bbox), -track.track_id, track)
                for track in self.tracks.values()
                if track.track_id not in matched and track.class_id == detection.class_id
            ]
            best = max(candidates, key=lambda candidate: candidate[:2], default=None)
            if best is not None and best[0] > self.policy.track_iou_threshold:
                track = best[2]
                track.bbox = tuple(
                    0.6 * new + 0.4 * old for new, old in zip(detection.bbox, track.bbox)
                )
                track.confidence = detection.confidence
                track.hits += 1
                track.last_seen_ms = capture_ms
            else:
                track = TrackState(
                    self.next_id,
                    detection.class_id,
                    detection.class_name,
                    detection.bbox,
                    detection.confidence,
                    1,
                    capture_ms,
                )
                self.tracks[self.next_id] = track
                self.next_id += 1
            matched.add(track.track_id)
            if image_width is not None:
                update_position(track, image_width, seq)
            current.append(track)
        for track_id, track in self.tracks.items():
            if track_id not in matched:
                update_range_motion(track, None, capture_ms)
        self._last_capture_ms, self._last_frame_seq = capture_ms, seq
        self._current = current
        return current.copy()


def update_range_motion(track: TrackState, distance_m: float | None, capture_ms: int) -> None:
    """Use capture-time range closing, including a user's approach to a stationary wall."""
    track.ttc_s = None
    if distance_m is None or not math.isfinite(distance_m) or not 0 < distance_m < 8:
        track.distance_m = track.range_velocity_mps = track.pending_jump_m = None
        track.distance_history.clear()
        return
    history = track.distance_history
    if history and not 0 < capture_ms - history[-1][0] <= 500:
        history.clear()
        track.range_velocity_mps = track.pending_jump_m = None
    jump = abs(distance_m - history[-1][1]) if history else 0.0
    if jump > 1.5 and not math.isclose(jump, 1.5, rel_tol=0, abs_tol=1e-12):
        track.distance_m = track.range_velocity_mps = None
        disagrees = track.pending_jump_m is None or (
            abs(distance_m - track.pending_jump_m) > 0.4
            and not math.isclose(
                abs(distance_m - track.pending_jump_m), 0.4, rel_tol=0, abs_tol=1e-12
            )
        )
        if disagrees:
            track.pending_jump_m = distance_m
            return
        history.clear()
    track.pending_jump_m = None
    track.distance_m = distance_m
    history.append((capture_ms, distance_m))
    history[:] = [(time, distance) for time, distance in history if capture_ms - time <= 1000]
    if len(history) < 3 or history[-1][0] - history[0][0] < 150:
        track.range_velocity_mps = None
        return
    distances = [distance for _, distance in history]
    times = [(time - history[0][0]) / 1000 for time, _ in history]
    mean_time, mean_distance = sum(times) / len(times), sum(distances) / len(distances)
    if abs(distances[-1] - distances[0]) < max(0.08, 0.03 * max(distances)):
        velocity = 0.0
    else:
        velocity = sum(
            (time - mean_time) * (distance - mean_distance)
            for time, distance in zip(times, distances)
        ) / sum((time - mean_time) ** 2 for time in times)
    if abs(velocity) > (8 if track.class_id == 0 else 20):
        track.range_velocity_mps = None
        return
    previous = track.range_velocity_mps
    track.range_velocity_mps = velocity if previous is None else 0.5 * velocity + 0.5 * previous
    closing_speed = -track.range_velocity_mps
    if closing_speed > 0.03 and distance_m / closing_speed <= 12:
        track.ttc_s = distance_m / closing_speed
