import pytest

from navcore.cli.dataset import ClipLabel
from navcore.cli.metrics import navigation_metrics
from navcore.cli.trace_validation import coverage_missing, validate_trace


def clip():
    return {
        "clip_id": "p",
        "file": "q.mp4",
        "split": "test",
        "capture_group": "q",
        "expected_completion": True,
        "checkpoints": [
            {
                "seq": 0,
                "visible_start_ms": 200,
                "visible_end_ms": 500,
                "expected_code": "CONTINUE_STRAIGHT",
            }
        ],
    }


def test_repeating_two_labels_cannot_count_as_sixty_independent_frames():
    labels = [{"pts_ms": 0, "objects": []}] * 30
    with pytest.raises(ValueError, match="unique"):
        ClipLabel.model_validate(clip() | {"perception_frames": labels})


def test_actual_transition_before_window_fails_even_when_later_instruction_is_in_window():
    label = ClipLabel.model_validate(clip())
    events = [
        {
            "type": "frame_result",
            "seq": 1,
            "accepted_fresh": True,
            "last_confirmed_seq": 0,
            "video_pts_ms": 0,
        }
    ]
    result = navigation_metrics(label, events)
    assert result["wrong_window_progress"] == 1 and not result["completed"]


def observations():
    events = [{"type": "run_start", "source_duration_ms": 2000}]
    for seq, pts in enumerate((0, 800, 1800), start=1):
        capture = seq * 1000
        events += [
            {"type": "capture_request", "seq": seq, "requested_monotonic_ms": capture - 1},
            {
                "type": "frame_sent",
                "seq": seq,
                "capture_monotonic_ms": capture,
                "video_pts_ms": pts,
            },
            {
                "type": "frame_result",
                "seq": seq,
                "capture_monotonic_ms": capture,
                "received_monotonic_ms": capture + 100,
                "video_pts_ms": pts,
                "accepted_fresh": True,
            },
        ]
    events += [{"type": "run_end", "source_exhausted": True, "elapsed_ms": 2000}]
    return events


def test_empty_negative_is_missing_coverage_and_full_distinct_observations_are_accepted():
    empty = [
        {"type": "run_start", "source_duration_ms": 2000},
        {"type": "run_end", "source_exhausted": True, "elapsed_ms": 2000},
    ]
    assert coverage_missing(empty, 2000)
    complete = validate_trace(observations())
    assert not coverage_missing(complete, 2000)


def test_trace_freshness_and_pts_claims_must_follow_challenge_capture_evidence():
    for key, value in (
        ("capture_monotonic_ms", 999),
        ("video_pts_ms", 999),
        ("received_monotonic_ms", 2000),
    ):
        events = observations()
        events[3][key] = value
        with pytest.raises(ValueError):
            validate_trace(events)
