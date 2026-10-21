"""Structured logs without credentials or camera payloads."""

import json
import logging
import re
from datetime import UTC, datetime

_PRIVATE = re.compile(
    r"authorization|token|password|secret|image_b64|png_b64|embedding|jpeg_bytes", re.I
)
_BEARER = re.compile(r"Bearer\s+[^\s\"',}]+", re.I)
_DB_URL = re.compile(r"postgres(?:ql)?(?:\+psycopg)?://[^\s\"']+", re.I)
_DEVICE = re.compile(r"navdev_[A-Za-z0-9_-]+")


class JsonFormatter(logging.Formatter):
    def __init__(self, secrets: tuple[str, ...] = ()) -> None:
        super().__init__()
        self.secrets = tuple(value for value in secrets if value)

    def scrub(self, value):
        if isinstance(value, dict):
            return {
                str(k): "[REDACTED]" if _PRIVATE.search(str(k)) else self.scrub(v)
                for k, v in value.items()
            }
        if isinstance(value, (list, tuple)):
            return [self.scrub(item) for item in value]
        if isinstance(value, str):
            for secret in self.secrets:
                value = value.replace(secret, "[REDACTED]")
            value = _BEARER.sub("Bearer [REDACTED]", value)
            value = _DB_URL.sub("[REDACTED_DB_URL]", value)
            return _DEVICE.sub("[REDACTED]", value)
        return value

    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "timestamp": datetime.now(UTC).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "event": record.getMessage(),
        }
        entry.update(getattr(record, "fields", {}))
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(self.scrub(entry), ensure_ascii=False, default=str, allow_nan=False)


def configure_logging(level: str, secrets: tuple[str, ...] = ()) -> None:
    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter(secrets))
    logging.basicConfig(level=level, handlers=[handler], force=True)
