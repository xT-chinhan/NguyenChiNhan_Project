"""Per-session obstacle hold, latch and voice cooldown; no camera or audio imports."""

import math
from dataclasses import replace

from .depth import DepthFrame, estimate_bbox_distance, estimate_center_distance, validate_depth
from .policy import BASELINE, PolicyConfig
from .tracking import update_position, update_range_motion
from .types import (
    DepthStatus,
    InstructionCode,
    Mode,
    ObstacleResult,
    Priority,
    SensorProfile,
    TrackState,
)


class ObstacleAssessor:
    def __init__(self, policy: PolicyConfig = BASELINE) -> None:
        self.policy = policy
        self.reset()

    def reset(self) -> None:
        self._latch: tuple[InstructionCode, Priority, tuple] | None = None
        self._clear_frames = 0
        self._spoken: dict[tuple, int] = {}
        self._last_frame: tuple[int, int] | None = None
        self._last_result: ObstacleResult | None = None

    def assess(
        self,
        tracks: list[TrackState],
        depth: DepthFrame | None,
        sensor: SensorProfile,
        capture_ms: int,
        *,
        image_size: tuple[int, int],
        frame_seq: int,
    ) -> ObstacleResult:
        """Assess accepted frames only; (width,height), seq and capture clock are device values.

        A null code can mean cooldown: hold remains authoritative for movement.
        On reconnect reset tracker motion; retain this assessor's session latch.
        """
        frame = frame_seq, capture_ms
        if frame == self._last_frame and self._last_result is not None:
            return self._last_result
        width, height = image_size
        if width <= 0 or height <= 0:
            raise ValueError("image dimensions must be positive")
        current = sorted(
            (track for track in tracks if track.last_seen_ms == capture_ms),
            key=lambda track: track.track_id,
        )
        for track in current:
            update_position(track, width, frame_seq)
        status, metres = validate_depth(depth, sensor, capture_ms, image_size)
        candidates: list[tuple[int, InstructionCode, Priority, tuple]] = []

        def add(
            code: InstructionCode,
            priority: Priority,
            track: TrackState | None,
            distance: float | None,
        ) -> None:
            key = (
                code,
                track.position if track else "ahead",
                track.class_name if track else "depth",
                math.floor(distance / 0.3) if distance is not None else "unknown",
            )
            rank = {Priority.EMERGENCY: 0, Priority.WARNING: 1, Priority.INFO: 2}[priority]
            candidates.append((rank, code, priority, key))

        if sensor.mode == Mode.RGB:
            for track in current:
                update_range_motion(track, None, capture_ms)
                x1, y1, x2, y2 = track.bbox
                if (
                    track.hits >= self.policy.track_confirm_hits
                    and track.confidence >= self.policy.rgb_notice_confidence_min
                    and 0.30 * width <= (x1 + x2) / 2 <= 0.70 * width
                    and y2 >= 0.65 * height
                    and (x2 - x1) * (y2 - y1) >= 0.08 * width * height
                ):
                    add(InstructionCode.OBJECT_AHEAD, Priority.WARNING, track, None)
        elif metres is None:
            for track in current:
                update_range_motion(track, None, capture_ms)
            self._clear_frames = 0
            add(InstructionCode.DEPTH_UNAVAILABLE, Priority.WARNING, None, None)
        else:
            center = estimate_center_distance(metres).distance_m
            if center is None:
                status = DepthStatus.INSUFFICIENT
            elif center < 0.4:
                add(InstructionCode.EMERGENCY_STOP, Priority.EMERGENCY, None, center)
            elif center < 0.8:
                add(InstructionCode.OBSTACLE_NEAR, Priority.WARNING, None, center)
            for track in current:
                estimate = estimate_bbox_distance(metres, track.bbox)
                measured_distance = estimate.distance_m
                update_range_motion(track, measured_distance, capture_ms)
                if measured_distance is not None and measured_distance < 0.4:
                    add(
                        InstructionCode.EMERGENCY_STOP, Priority.EMERGENCY, track, measured_distance
                    )
                elif measured_distance is not None and measured_distance < 0.7:
                    add(InstructionCode.OBSTACLE_NEAR, Priority.WARNING, track, measured_distance)
                if track.hits >= self.policy.track_confirm_hits and track.ttc_s is not None:
                    if track.ttc_s < 2:
                        add(
                            InstructionCode.EMERGENCY_STOP,
                            Priority.EMERGENCY,
                            track,
                            track.distance_m,
                        )
                    elif track.ttc_s < 4:
                        add(
                            InstructionCode.OBSTACLE_NEAR, Priority.WARNING, track, track.distance_m
                        )
                    elif track.ttc_s < 8:
                        add(InstructionCode.OBSTACLE_NOTICE, Priority.INFO, track, track.distance_m)
            hazards = [candidate for candidate in candidates if candidate[0] <= 1]
            if hazards:
                _, code, priority, key = min(hazards, key=lambda candidate: candidate[0])
                if (
                    self._latch is None
                    or priority == Priority.EMERGENCY
                    or self._latch[1] != Priority.EMERGENCY
                ):
                    self._latch = code, priority, key
                self._clear_frames = 0
            elif center is not None and center >= 0.9:
                self._clear_frames += 1
                if self._clear_frames >= 3:
                    self._latch = None
            else:
                self._clear_frames = 0
            # A measured bbox hazard retains severity even when center coverage is insufficient.
            if status == DepthStatus.INSUFFICIENT:
                add(InstructionCode.DEPTH_UNAVAILABLE, Priority.WARNING, None, None)
            if self._latch is not None:
                code, priority, key = self._latch
                candidates.append((0 if priority == Priority.EMERGENCY else 1, code, priority, key))

        hold = bool(candidates)
        code = priority = None
        key: tuple = ()
        if candidates:
            _, code, priority, key = min(candidates, key=lambda candidate: candidate[0])
            last = self._spoken.get(key)
            escalated = priority == Priority.EMERGENCY and (
                self._last_result is None or self._last_result.priority != Priority.EMERGENCY
            )
            if (
                not escalated
                and last is not None
                and capture_ms - last < self.policy.obstacle_notice_cooldown_ms
            ):
                code = None
            else:
                self._spoken[key] = capture_ms
        self._spoken = {
            key: timestamp
            for key, timestamp in self._spoken.items()
            if capture_ms - timestamp < self.policy.obstacle_notice_cooldown_ms
        }
        observations = tuple(
            replace(track, distance_history=track.distance_history.copy()) for track in current
        )
        result = ObstacleResult(observations, status, hold, code, priority, key)
        self._last_frame, self._last_result = frame, result
        return result
