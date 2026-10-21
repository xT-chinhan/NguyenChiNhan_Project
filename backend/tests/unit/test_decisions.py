from navcore.core.decisions import decide
from navcore.core.types import (
    Decision,
    DepthStatus,
    NavigationProposal,
    NavigationState,
    ObstacleResult,
    Priority,
    State,
)
from navcore.core.types import (
    InstructionCode as Code,
)


def test_emergency_blocks_arrival_without_mutating_original():
    original = NavigationState(state=State.NAVIGATING, last_confirmed_seq=2, target_seq=3)
    arrival = NavigationProposal(
        NavigationState(state=State.COMPLETED, last_confirmed_seq=3), Code.ARRIVED, True
    )
    hazard = ObstacleResult((), DepthStatus.VALID, True, Code.EMERGENCY_STOP, Priority.EMERGENCY)
    decision = decide(original, arrival, hazard)
    assert isinstance(decision, Decision)
    assert decision.next_state.last_confirmed_seq == 2
    assert decision.next_state.state == State.NAVIGATING
    assert decision.code == Code.EMERGENCY_STOP and decision.hold
    assert original.last_confirmed_seq == 2


def test_silent_cooldown_and_info_notice_still_defer_progress():
    original = NavigationState(last_confirmed_seq=-1)
    proposal = NavigationProposal(NavigationState(last_confirmed_seq=0), Code.CONTINUE_STRAIGHT)
    for obstacle in (
        ObstacleResult((), DepthStatus.NOT_SUPPORTED, True),
        ObstacleResult((), DepthStatus.VALID, False, Code.OBSTACLE_NOTICE, Priority.INFO),
    ):
        result = decide(original, proposal, obstacle)
        assert result.hold and result.next_state.last_confirmed_seq == -1


def test_current_request_expiry_pauses_until_manual_resume():
    state = NavigationState(state=State.NAVIGATING, last_confirmed_seq=1, target_seq=2)
    proposal = NavigationProposal(
        NavigationState(state=State.COMPLETED, last_confirmed_seq=3), Code.ARRIVED, True
    )
    result = decide(state, proposal, ObstacleResult((), DepthStatus.VALID), fresh=False)
    assert result.hold and result.next_state.state == State.PAUSED
    assert result.next_state.last_confirmed_seq == 1


def test_lost_timeout_commits_without_progress_even_under_silent_obstacle_hold():
    state = NavigationState(state=State.NAVIGATING, last_confirmed_seq=1, target_seq=2)
    proposal = NavigationProposal(
        NavigationState(state=State.LOST, last_confirmed_seq=1, target_seq=2), Code.HOLD_POSITION
    )
    for code in (None, Code.OBSTACLE_NEAR):
        result = decide(
            state, proposal, ObstacleResult((), DepthStatus.VALID, True, code, Priority.WARNING)
        )
        assert result.next_state.state == State.LOST and result.next_state.last_confirmed_seq == 1
