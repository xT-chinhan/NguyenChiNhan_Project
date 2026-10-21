"""Validate causal replay observations before treating client fields as evidence."""

import math


def finite(value):
    return type(value) in {int, float} and math.isfinite(value) and value >= 0


def validate_trace(events: list[dict]) -> list[dict]:
    requested, sent, results, last_seq, last_capture = {}, {}, set(), 0, -1
    for event in events:
        kind = event.get("type")
        seq = event.get("seq")
        if kind == "capture_request":
            if type(seq) is not int or seq <= last_seq:
                raise ValueError("Replay challenge sequence is not strictly increasing")
            now = event.get("requested_monotonic_ms")
            if not finite(now):
                raise ValueError("Replay challenge timestamp missing")
            requested[seq], last_seq = now, seq
        elif kind == "frame_sent":
            capture, pts = event.get("capture_monotonic_ms"), event.get("video_pts_ms")
            if (
                seq not in requested
                or seq in sent
                or type(capture) is not int
                or capture <= last_capture
                or capture < requested[seq]
                or not finite(pts)
            ):
                raise ValueError("Replay frame does not follow a fresh challenge")
            sent[seq], last_capture = event, capture
        elif kind == "frame_result":
            original = sent.get(seq)
            received = event.get("received_monotonic_ms")
            if (
                original is None
                or seq in results
                or not finite(received)
                or received < original["capture_monotonic_ms"]
                or any(
                    event.get(key) != original[key]
                    for key in ("capture_monotonic_ms", "video_pts_ms")
                )
            ):
                raise ValueError("Replay outcome does not match its captured frame")
            results.add(seq)
            age = received - original["capture_monotonic_ms"]
            if event.get("accepted_fresh") is not (age < 1000):
                raise ValueError("Replay freshness claim contradicts capture timestamps")
        elif kind == "instruction_presented":
            original = sent.get(event.get("frame_seq"))
            if (
                original is None
                or event.get("frame_seq") not in results
                or any(
                    event.get(key) != original[key]
                    for key in ("capture_monotonic_ms", "video_pts_ms")
                )
            ):
                raise ValueError("Replay instruction lacks an observed matching frame")
    return events


def coverage_missing(events: list[dict], duration_ms: float | None) -> bool:
    """Require end-of-source and distinct observations at both ends of a negative clip."""
    if not finite(duration_ms) or duration_ms <= 0:
        return True
    if events[0].get("source_duration_ms") != duration_ms:
        return True
    endings = [event for event in events if event.get("type") == "run_end"]
    if (
        len(endings) != 1
        or endings[0].get("source_exhausted") is not True
        or not finite(endings[0].get("elapsed_ms"))
        or endings[0]["elapsed_ms"] < duration_ms
    ):
        return True
    points = {
        e["video_pts_ms"]
        for e in events
        if e.get("type") == "frame_result" and e.get("accepted_fresh")
    }
    return len(points) < 3 or min(points) > 200 or max(points) < duration_ms - 1000
