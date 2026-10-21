"""Pure proposals: runtime applies obstacle priority and final freshness guards."""

from dataclasses import replace
from math import isfinite

from .policy import BASELINE, PolicyConfig
from .types import (
    Action,
    Candidate,
    FrameIdentity,
    InstructionCode,
    MatchResult,
    NavigationProposal,
    NavigationState,
    RouteSnapshot,
    State,
)

_DEPARTURE_CODES = {
    Action.STRAIGHT: InstructionCode.CONTINUE_STRAIGHT,
    Action.LEFT: InstructionCode.TURN_LEFT,
    Action.RIGHT: InstructionCode.TURN_RIGHT,
    Action.ARRIVE: InstructionCode.ARRIVED,
}


def clone_navigation(state: NavigationState) -> NavigationState:
    candidate = state.candidate
    return replace(
        state, candidate=Candidate(candidate.seq, list(candidate.frames)) if candidate else None
    )


def _clear_pending(state: NavigationState) -> None:
    state.pending_departure_seq = None
    state.pending_instruction_id = None
    state.pending_instruction_deadline_ms = None


def allowed_sequences(state: NavigationState, route: RouteSnapshot) -> tuple[int, ...]:
    if state.state not in (State.LOCALIZING, State.NAVIGATING):
        return ()
    if state.state == State.LOCALIZING:
        allowed = state.resume_allowed_seqs if state.resume_allowed_seqs is not None else (0,)
    elif state.pending_departure_seq is not None:
        allowed = (state.pending_departure_seq,)
    else:
        allowed = (state.target_seq,)
    existing = {checkpoint.seq for checkpoint in route.checkpoints}
    return tuple(seq for seq in allowed if seq in existing)


def start_capture(state: NavigationState, now_ms: float) -> NavigationState:
    """Start initial localization time at capture, rather than REST creation."""
    result = clone_navigation(state)
    if result.state in (State.LOCALIZING, State.NAVIGATING) and result.last_position_ms is None:
        result.last_position_ms = now_ms
    return result


def check_timeout(
    state: NavigationState, now_ms: float, policy: PolicyConfig = BASELINE
) -> NavigationProposal:
    result = clone_navigation(state)
    timeout = (
        policy.initial_localization_timeout_ms
        if result.last_confirmed_seq < 0
        else policy.localization_lost_ms
    )
    if (
        result.state in (State.LOCALIZING, State.NAVIGATING)
        and result.last_position_ms is not None
        and now_ms - result.last_position_ms >= timeout
    ):
        result.state = State.LOST
        result.candidate = None
        _clear_pending(result)
        return NavigationProposal(result, InstructionCode.HOLD_POSITION)
    return NavigationProposal(result)


def control_navigation(
    state: NavigationState, command: str, now_ms: float, route: RouteSnapshot
) -> NavigationState:
    """Resume grants a fresh 15s localization window, excluding paused time."""
    result = clone_navigation(state)
    if command not in ("pause", "resume", "stop", "repeat"):
        raise ValueError("PROTOCOL_ERROR")
    if command == "repeat":
        return result
    if command == "stop":
        result.state = State.STOPPED
    elif result.state in (State.COMPLETED, State.STOPPED):
        raise ValueError("SESSION_TERMINAL")
    elif command == "pause":
        result.state = State.PAUSED
    elif command == "resume":
        if result.state not in (State.PAUSED, State.LOST):
            return result
        result.state = State.LOCALIZING
        result.last_position_ms = now_ms
        existing = {checkpoint.seq for checkpoint in route.checkpoints}
        result.resume_allowed_seqs = tuple(
            seq
            for seq in (result.last_confirmed_seq, result.last_confirmed_seq + 1)
            if seq in existing
        )
        result.candidate = None
        _clear_pending(result)
        return result
    result.candidate = None
    result.resume_allowed_seqs = None
    _clear_pending(result)
    return result


def bind_instruction(
    state: NavigationState, instruction_id: str, deadline_ms: float
) -> NavigationState:
    """Bind only an emitted departure proposal, after the decision accepts it."""
    result = clone_navigation(state)
    if result.state != State.NAVIGATING or result.pending_departure_seq is None:
        raise ValueError("NO_PENDING_DEPARTURE")
    if not instruction_id or not isfinite(deadline_ms):
        raise ValueError("INSTRUCTION_INVALID")
    result.pending_instruction_id = instruction_id
    result.pending_instruction_deadline_ms = deadline_ms
    result.candidate = None
    return result


def ack_departure(
    state: NavigationState, instruction_id: str, stage: str, now_ms: float
) -> NavigationState:
    """Runtime must check connection epoch before calling; late ACKs do nothing."""
    result = clone_navigation(state)
    if stage not in ("received", "presented"):
        raise ValueError("PROTOCOL_ERROR")
    if (
        stage == "presented"
        and result.state == State.NAVIGATING
        and result.pending_departure_seq is not None
        and result.pending_instruction_id == instruction_id
        and result.pending_instruction_deadline_ms is not None
        and now_ms < result.pending_instruction_deadline_ms
    ):
        _clear_pending(result)
        result.candidate = None
    return result


def advance_navigation(
    state: NavigationState,
    match: MatchResult,
    frame: FrameIdentity,
    now_ms: float,
    route: RouteSnapshot,
    policy: PolicyConfig = BASELINE,
) -> NavigationProposal:
    if state.state in (State.COMPLETED, State.STOPPED):
        raise ValueError("SESSION_TERMINAL")
    timeout = check_timeout(start_capture(state, now_ms), now_ms, policy)
    result = timeout.next_state
    if result.state not in (State.LOCALIZING, State.NAVIGATING):
        return replace(timeout, match=match)
    if not match.accepted or match.candidate_seq not in allowed_sequences(result, route):
        result.candidate = None
        return NavigationProposal(result, match=match)
    if (
        result.pending_instruction_deadline_ms is not None
        and now_ms < result.pending_instruction_deadline_ms
    ):
        result.candidate = None
        return NavigationProposal(result, match=match)
    result.pending_instruction_id = None
    result.pending_instruction_deadline_ms = None
    candidate = result.candidate
    if candidate is None or candidate.seq != match.candidate_seq:
        candidate = Candidate(match.candidate_seq)
    if any(
        previous.seq == frame.seq
        or previous.capture_ms == frame.capture_ms
        or previous.image_hash == frame.image_hash
        for previous in candidate.frames
    ):
        result.candidate = candidate
        return NavigationProposal(result, match=match)
    if candidate.frames:
        previous = candidate.frames[-1]
        if frame.seq <= previous.seq or frame.capture_ms <= previous.capture_ms:
            result.candidate = None
            return NavigationProposal(result, match=match)
        if (
            frame.capture_ms - candidate.frames[0].capture_ms > policy.waypoint_confirm_window_ms
            or frame.capture_ms - previous.capture_ms > policy.track_max_age_ms
        ):
            candidate = Candidate(match.candidate_seq)
    candidate.frames.append(frame)
    result.candidate = candidate
    if len(candidate.frames) < policy.waypoint_confirm_hits:
        return NavigationProposal(result, match=match)
    checkpoint = next(
        checkpoint for checkpoint in route.checkpoints if checkpoint.seq == candidate.seq
    )
    result.last_confirmed_seq = checkpoint.seq
    result.last_position_ms = now_ms
    result.candidate = None
    result.resume_allowed_seqs = None
    _clear_pending(result)
    if checkpoint.depart_action == Action.ARRIVE:
        result.state = State.COMPLETED
        result.target_seq = checkpoint.seq
    else:
        result.state = State.NAVIGATING
        result.target_seq = checkpoint.seq + 1
        result.pending_departure_seq = checkpoint.seq
    return NavigationProposal(result, _DEPARTURE_CODES[checkpoint.depart_action], True, match)
