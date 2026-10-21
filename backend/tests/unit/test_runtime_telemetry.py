import logging

from navcore.runtime.coordinator import Coordinator
from tests.runtime_support import FixtureVision, session


def test_challenge_log_records_context_without_private_token_or_pixels(caplog):
    current = session()
    with caplog.at_level(logging.DEBUG, logger="navcore.runtime"):
        request = Coordinator(current, None, FixtureVision()).issue()
    record = next(record for record in caplog.records if record.message == "frame_requested")
    assert record.fields["session_id"] == str(current.id)
    assert record.fields["seq"] == request["seq"]
    assert request["frame_token"] not in str(record.fields)
    assert "image_b64" not in str(record.fields)
