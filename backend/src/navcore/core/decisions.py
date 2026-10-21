from copy import deepcopy

from navcore.core.messages import message
from navcore.core.types import (
    Decision,
    InstructionCode,
    NavigationProposal,
    NavigationState,
    ObstacleResult,
    State,
)


def decide(
    state: NavigationState,
    proposal: NavigationProposal,
    obstacles: ObstacleResult,
    *,
    fresh: bool = True,
    vision_ok: bool = True,
) -> Decision:
    current = deepcopy(proposal.next_state if proposal.next_state.state == State.LOST else state)
    reason = None
    code = None
    if not fresh or state.state in {State.PAUSED, State.STOPPED, State.COMPLETED}:
        reason = "STREAM_STALE" if not fresh else state.state.value.upper()
        if not fresh and state.state not in {State.STOPPED, State.COMPLETED}:
            current.state = State.PAUSED
    elif not vision_ok:
        reason, code = "VISION_UNAVAILABLE", InstructionCode.WAIT_FOR_FRESH_FRAME
    elif obstacles.hold or obstacles.code is not None:
        reason = obstacles.code.value if obstacles.code else "OBSTACLE_HOLD"
        code = obstacles.code
    elif state.state == State.LOST or proposal.next_state.state == State.LOST:
        current = deepcopy(proposal.next_state)
        reason, code = "LOCALIZATION_LOST", InstructionCode.HOLD_POSITION
    else:
        return Decision(
            proposal.next_state,
            proposal.code,
            message(proposal.code)[1] if proposal.code else None,
            False,
        )
    current.candidate = None
    current.pending_instruction_id = None
    current.pending_instruction_deadline_ms = None
    return Decision(current, code, message(code)[1] if code else None, True, reason)
