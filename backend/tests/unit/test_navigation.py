from copy import deepcopy
from dataclasses import replace

import pytest

from navcore.core.navigation import (
    ack_departure,
    advance_navigation,
    allowed_sequences,
    bind_instruction,
    check_timeout,
    control_navigation,
    start_capture,
)
from navcore.core.types import (
    Action,
    Checkpoint,
    FrameIdentity,
    InstructionCode,
    MatchResult,
    NavigationState,
    RouteSnapshot,
    State,
)

ROUTE = RouteSnapshot(
    "route",
    1,
    "a" * 64,
    None,
    tuple(
        Checkpoint(str(seq), seq, action, str(seq))
        for seq, action in enumerate((Action.STRAIGHT, Action.LEFT, Action.RIGHT, Action.ARRIVE))
    ),
)


def hit(state, seq, number, *, capture=None, image_hash=None, now=None):
    capture = number * 200 if capture is None else capture
    return advance_navigation(
        state,
        MatchResult(seq, 0.99, 0.1, True),
        FrameIdentity(number, capture, image_hash or f"pixels-{number}"),
        capture if now is None else now,
        ROUTE,
    )


def confirm(state, seq, first, *, start_ms=None):
    for number in range(first, first + 3):
        capture = None if start_ms is None else start_ms + (number - first) * 200
        proposal = hit(state, seq, number, capture=capture)
        state = proposal.next_state
    return proposal


def test_independent_twelve_frame_positive_timeline_and_input_immutability():
    state = NavigationState()
    expected = (
        InstructionCode.CONTINUE_STRAIGHT,
        InstructionCode.TURN_LEFT,
        InstructionCode.TURN_RIGHT,
        InstructionCode.ARRIVED,
    )
    for seq, code in enumerate(expected):
        for offset in range(3):
            number = seq * 3 + offset + 1
            before = deepcopy(state)
            proposal = hit(state, seq, number)
            assert state == before
            assert proposal.confirmed == (offset == 2)
            assert proposal.code == (code if offset == 2 else None)
            state = proposal.next_state
        assert state.last_confirmed_seq == seq
        if seq < 3:
            state = bind_instruction(state, f"departure-{seq}", number * 200 + 999)
            state = ack_departure(state, f"departure-{seq}", "presented", number * 200 + 1)
    assert state.state == State.COMPLETED
    with pytest.raises(ValueError, match="SESSION_TERMINAL"):
        hit(state, 3, 13)


def test_twenty_repeated_pixels_do_not_confirm_and_a_b_a_checks_full_set():
    state = NavigationState()
    for number in range(1, 21):
        proposal = hit(state, 0, number, image_hash="same")
        state = proposal.next_state
        assert not proposal.confirmed
    state = hit(NavigationState(), 0, 1, image_hash="A").next_state
    state = hit(state, 0, 2, image_hash="B").next_state
    repeated = hit(state, 0, 3, image_hash="A")
    assert not repeated.confirmed
    assert len(repeated.next_state.candidate.frames) == 2


def test_duplicate_capture_and_seq_do_not_count():
    state = hit(NavigationState(), 0, 1).next_state
    state = hit(state, 0, 2, capture=200).next_state
    assert len(state.candidate.frames) == 1
    assert not hit(state, 0, 1, capture=400).confirmed


def test_miss_resets_evidence_and_wrong_target_cannot_jump_to_arrival():
    state = hit(NavigationState(), 0, 1).next_state
    proposal = advance_navigation(
        state, MatchResult(0, 0.95, 0.01, False), FrameIdentity(2, 400, "miss"), 400, ROUTE
    )
    assert proposal.next_state.candidate is None
    assert not confirm(proposal.next_state, 3, 3).confirmed
    assert state.candidate is not None


def test_confirmation_window_and_capture_gap_reset_candidate():
    state = hit(NavigationState(), 0, 1, capture=0).next_state
    state = hit(state, 0, 2, capture=800).next_state
    result = hit(state, 0, 3, capture=1501)
    assert not result.confirmed
    assert len(result.next_state.candidate.frames) == 1
    state = hit(NavigationState(), 0, 1, capture=0).next_state
    result = hit(state, 0, 2, capture=1001)
    assert len(result.next_state.candidate.frames) == 1


def test_confirmation_at_exact_capture_window():
    state = hit(NavigationState(), 0, 1, capture=0).next_state
    state = hit(state, 0, 2, capture=750).next_state
    assert hit(state, 0, 3, capture=1500).confirmed


def test_ack_received_old_id_and_expiry_cannot_unlock_next():
    state = confirm(NavigationState(), 0, 1).next_state
    state = bind_instruction(state, "current", 1000)
    for instruction_id, stage, now in (
        ("current", "received", 700),
        ("old", "presented", 700),
        ("current", "presented", 1000),
    ):
        ignored = ack_departure(state, instruction_id, stage, now)
        assert ignored == state
        assert allowed_sequences(ignored, ROUTE) == (0,)
    accepted = ack_departure(state, "current", "presented", 999)
    assert allowed_sequences(accepted, ROUTE) == (1,)
    assert ack_departure(accepted, "current", "presented", 999) == accepted


def test_expired_departure_requires_three_new_frames_and_binding_a_new_id():
    state = confirm(NavigationState(), 0, 1).next_state
    state = bind_instruction(state, "old", 1000)
    assert hit(state, 0, 4).next_state.candidate is None
    assert not confirm(state, 1, 5).confirmed
    proposal = confirm(state, 0, 8, start_ms=1200)
    assert proposal.confirmed and proposal.code == InstructionCode.CONTINUE_STRAIGHT
    state = proposal.next_state
    assert state.last_confirmed_seq == 0 and state.target_seq == 1
    assert state.last_position_ms == 1600
    state = bind_instruction(state, "new", 2500)
    assert ack_departure(state, "old", "presented", 1700).pending_departure_seq == 0
    assert ack_departure(state, "new", "presented", 1700).pending_departure_seq is None


def test_pause_resume_relocalizes_only_last_or_next_and_invalidates_old_id():
    state = confirm(NavigationState(), 0, 1).next_state
    state = bind_instruction(state, "old", 1500)
    state = control_navigation(state, "pause", 700, ROUTE)
    assert state.state == State.PAUSED and state.pending_instruction_id is None
    state = control_navigation(state, "resume", 100_000, ROUTE)
    assert state.state == State.LOCALIZING
    assert allowed_sequences(state, ROUTE) == (0, 1)
    assert check_timeout(state, 114_999).next_state.state == State.LOCALIZING
    assert not confirm(state, 3, 10, start_ms=100_200).confirmed
    revalidated = confirm(state, 0, 13, start_ms=100_800)
    assert revalidated.confirmed
    assert revalidated.next_state.last_confirmed_seq == 0
    assert revalidated.next_state.pending_departure_seq == 0
    assert revalidated.next_state.last_position_ms == 101_200


def test_resume_may_confirm_next_but_cannot_skip_checkpoint():
    state = NavigationState(state=State.PAUSED, last_confirmed_seq=1, target_seq=2)
    state = control_navigation(state, "resume", 0, ROUTE)
    assert allowed_sequences(state, ROUTE) == (1, 2)
    result = confirm(state, 2, 1)
    assert result.next_state.last_confirmed_seq == 2
    assert result.code == InstructionCode.TURN_RIGHT


def test_initial_clock_starts_at_capture_and_lost_requires_manual_resume():
    state = NavigationState()
    assert check_timeout(state, 50_000).next_state.state == State.LOCALIZING
    state = start_capture(state, 50_000)
    assert check_timeout(state, 64_999).code is None
    expired = check_timeout(state, 65_000)
    assert expired.code == InstructionCode.HOLD_POSITION
    state = expired.next_state
    assert state.state == State.LOST
    assert not confirm(state, 0, 1, start_ms=65_100).confirmed
    resumed = control_navigation(state, "resume", 70_000, ROUTE)
    assert allowed_sequences(resumed, ROUTE) == (0,)


def test_timeout_pending_departure_and_stop_clear_instruction_state():
    state = bind_instruction(confirm(NavigationState(), 0, 1).next_state, "id", 1000)
    expired = check_timeout(state, 15_600).next_state
    assert expired.state == State.LOST and expired.pending_instruction_id is None
    stopped = control_navigation(state, "stop", 700, ROUTE)
    assert stopped.state == State.STOPPED and stopped.pending_departure_seq is None
    assert control_navigation(stopped, "stop", 800, ROUTE) == stopped
    with pytest.raises(ValueError, match="SESSION_TERMINAL"):
        control_navigation(stopped, "resume", 900, ROUTE)


def test_repeat_does_not_mutate_navigation_or_instruction_deadline():
    state = bind_instruction(confirm(NavigationState(), 0, 1).next_state, "id", 1000)
    assert control_navigation(state, "repeat", 900, ROUTE) == state
    assert control_navigation(state, "repeat", 1000, ROUTE) == state
    completed = replace(state, state=State.COMPLETED)
    assert control_navigation(completed, "repeat", 900, ROUTE) == completed
