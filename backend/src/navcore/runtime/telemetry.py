"""Allowlisted runtime metadata; camera payloads and challenge tokens never enter logs."""

import logging

LOGGER = logging.getLogger("navcore.runtime")


def event(session, name: str, *, level=logging.DEBUG, **fields):
    LOGGER.log(
        level,
        name,
        extra={
            "fields": {
                "session_id": str(session.id),
                "epoch": session.epoch,
                "state": session.state.value,
                **fields,
            }
        },
    )
