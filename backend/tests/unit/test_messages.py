from navcore.core.messages import MESSAGES
from navcore.core.types import InstructionCode as Code


def test_messages_complete_fixed_and_never_claim_path_clear():
    assert set(MESSAGES) == set(Code)
    assert "PATH_CLEAR" not in {item.value for item in Code}
    assert all("mét" not in text for text, _ in MESSAGES.values())
