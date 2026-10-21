"""Off-loop image validation and isolated mutable-core proposals."""

from dataclasses import replace
from time import perf_counter

from navcore.core.decisions import decide
from navcore.core.depth import DepthFrame
from navcore.core.localization import match_checkpoint
from navcore.core.navigation import advance_navigation, allowed_sequences
from navcore.core.types import FrameIdentity, Mode, State
from navcore.vision.images import ImageError, decode_depth_png, decode_ws_image


class FrameError(ValueError):
    pass


def decode(frame, sensor):
    start = perf_counter()
    image = decode_ws_image(frame.image_b64)
    depth = None
    if frame.depth is not None:
        if sensor.mode == Mode.RGB:
            raise FrameError("DEPTH_INVALID")
        incoming = frame.depth
        if (
            incoming.calibration_id != sensor.calibration_id
            or abs(incoming.capture_monotonic_ms - frame.capture_monotonic_ms) > 50
        ):
            raise FrameError("DEPTH_INVALID")
        try:
            raw = decode_depth_png(incoming.png_b64)
        except ImageError:
            raise FrameError("DEPTH_INVALID") from None
        if raw.shape != image.rgb.shape[:2]:
            raise FrameError("DEPTH_INVALID")
        depth = DepthFrame(raw, incoming.capture_monotonic_ms, True, incoming.calibration_id)
    return image, depth, (perf_counter() - start) * 1000


def propose(core, frame, image, depth, vision, route, sensor, policy, now_ms):
    start = perf_counter()
    if core.last_capture_ms is not None and (
        frame.capture_monotonic_ms - core.last_capture_ms > policy.track_max_age_ms
    ):
        core.tracker.reset()
        core.navigation.candidate = None
    width, height = image.rgb.shape[1], image.rgb.shape[0]
    tracks = core.tracker.update(
        vision.detections,
        frame.capture_monotonic_ms,
        frame_seq=frame.seq,
        image_width=width,
    )
    obstacles = core.assessor.assess(
        tracks,
        depth,
        sensor,
        frame.capture_monotonic_ms,
        image_size=(width, height),
        frame_seq=frame.seq,
    )
    match = match_checkpoint(
        vision.embedding,
        route,
        allowed_sequences(core.navigation, route),
        frame.heading_deg,
        frame.heading_accuracy_deg,
        policy,
    )
    proposal = advance_navigation(
        core.navigation,
        match,
        FrameIdentity(frame.seq, frame.capture_monotonic_ms, image.pixel_sha256),
        now_ms,
        route,
        policy,
    )
    decision = decide(core.navigation, proposal, obstacles)
    if decision.reason == "LOCALIZATION_LOST":
        previous = core.last_lost_notice_ms
        if previous is not None and now_ms - previous < policy.navigation_repeat_cooldown_ms:
            decision = replace(decision, code=None, priority=None)
        else:
            core.last_lost_notice_ms = now_ms
    core.navigation = decision.next_state
    core.last_capture_ms = frame.capture_monotonic_ms
    held = decision.hold or core.navigation.state == State.LOCALIZING
    reason = decision.reason or ("LOCALIZING" if held else None)
    return core, decision, proposal, obstacles, held, reason, (perf_counter() - start) * 1000
