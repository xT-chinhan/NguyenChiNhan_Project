from uuid import UUID

import pytest

from navcore.cli.replay import PresentationGuard


def instruction(seq=1, capture=100, ttl=600, identity=1, code="TURN_LEFT", priority="guidance"):
    return {
        "id": str(UUID(int=identity)),
        "code": code,
        "text_vi": "Rẽ trái.",
        "priority": priority,
        "valid_for_ms": ttl,
        "frame_seq": seq,
        "capture_monotonic_ms": capture,
        "replace_pending": True,
    }


def result(raw=None, held=False):
    return {
        "type": "frame_result",
        "seq": 1,
        "capture_monotonic_ms": 100,
        "movement_held": held,
        "hold_reason": "WARNING" if held else None,
        "instruction": raw,
        "timing": {},
        "obstacles": [],
    }


@pytest.mark.parametrize(
    "now,ttl,present,expected",
    [
        (1099, 600, 1099, True),
        (1100, 600, 1100, False),
        (200, 10, 209, True),
        (200, 10, 210, False),
        (200, 0, 200, False),
    ],
)
def test_both_ttl_bounds_are_strict(now, ttl, present, expected):
    guard = PresentationGuard(0)
    guard.capture(1, 100, 400, 90)
    guard.handle(result(instruction(ttl=ttl)), now)
    event = guard.present(present)
    assert (event is not None and event["type"] == "instruction_presented") is expected


def test_hold_null_status_and_warning_cancel_pending():
    guard = PresentationGuard(0)
    guard.capture(1, 100, 0, 90)
    guard.handle(result(instruction()), 200)
    assert guard.pending is not None
    guard.handle(result(None, held=True), 210)
    assert guard.present(210) is None
    guard.handle(result(instruction(identity=2)), 220)
    guard.handle({"type": "status", "code": "WORKER_BUSY"}, 230)
    assert guard.present(230) is None
    guard.handle(result(instruction(identity=3)), 240)
    guard.handle(
        result(instruction(identity=4, code="EMERGENCY_STOP", priority="emergency"), True),
        250,
    )
    assert guard.present(250)["code"] == "EMERGENCY_STOP"


def test_heartbeat_does_not_refresh_watchdog_and_dedupe_is_bounded():
    guard = PresentationGuard(0, max_ids=2)
    guard.capture(1, 100, 0, 90)
    guard.handle(result(instruction()), 200)
    assert guard.present(201)["presentation_kind"] == "stdout_simulation"
    guard.handle(result(instruction()), 300)
    assert guard.present(300) is None
    guard.handle({"type": "heartbeat"}, 1699)
    assert guard.watchdog(1699) is None
    assert guard.watchdog(1700)["code"] == "STREAM_STALE"
    assert guard.watchdog(1800) is None
    for identity in (2, 3):
        guard.handle(result(instruction(identity=identity)), 400)
    assert len(guard.seen) == 2


def test_unknown_capture_cannot_present_and_missing_lag_is_null():
    guard = PresentationGuard(0)
    assert guard.handle(result(instruction()), 200)[0]["code"] == "UNKNOWN_FRAME_IDENTITY"
    guard.capture(1, 100, 0, 90)
    events = guard.handle(result(instruction(capture=999)), 200)
    assert guard.present(200) is None
    assert events[0]["timing"]["event_loop_lag_ms"] is None


def test_manual_repeat_allows_current_id_but_keeps_original_capture_expiry():
    guard = PresentationGuard(0)
    guard.capture(1, 100, 0, 90)
    raw = instruction(ttl=600)
    guard.handle(result(raw), 200)
    assert guard.present(201)["type"] == "instruction_presented"
    repeat = {"type": "control_result", "command": "repeat", "instruction": raw}
    guard.handle(repeat, 300)
    assert guard.present(301)["instruction_id"] == raw["id"]
    guard.handle(repeat, 700)
    assert guard.present(800)["type"] == "instruction_dropped"
    guard.handle(repeat, 1100)
    assert guard.present(1100) is None
