"""Validated process configuration; no environment is read at import time."""

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Mapping
from urllib.parse import urlsplit


@dataclass(frozen=True)
class Settings:
    db_url: str = field(repr=False)
    admin_token: str = field(repr=False)
    model_dir: Path
    environment: str = "development"
    vision_device: str = "cpu"
    log_level: str = "DEBUG"
    host: str = "127.0.0.1"
    port: int = 8095
    worker_count: int = 1

    def __post_init__(self) -> None:
        parsed = urlsplit(self.db_url)
        if parsed.scheme != "postgresql+psycopg" or not parsed.hostname or not parsed.path[1:]:
            raise ValueError("NAV_DB_URL must identify a PostgreSQL psycopg database")
        if len(self.admin_token) < 32 or any(c.isspace() for c in self.admin_token):
            raise ValueError("NAV_ADMIN_TOKEN must contain at least 32 non-whitespace characters")
        if self.environment not in {"development", "test"}:
            raise ValueError("NAV_ENV must be development or test")
        if self.vision_device not in {"cpu", "cuda:0"}:
            raise ValueError("NAV_VISION_DEVICE must be cpu or cuda:0")
        if self.log_level not in {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}:
            raise ValueError("NAV_LOG_LEVEL is invalid")
        if not self.model_dir.is_absolute():
            raise ValueError("NAV_MODEL_DIR must be absolute")
        if type(self.port) is not int or not 1 <= self.port <= 65535:
            raise ValueError("NAV_HTTP_PORT is invalid")
        if self.worker_count != 1:
            raise ValueError("Only one backend worker is supported")

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> "Settings":
        values = os.environ if env is None else env
        missing = [
            key for key in ("NAV_DB_URL", "NAV_ADMIN_TOKEN", "NAV_MODEL_DIR") if not values.get(key)
        ]
        if missing:
            raise ValueError("Missing configuration: " + ", ".join(missing))
        try:
            port = int(values.get("NAV_HTTP_PORT", "8095"))
            workers = int(values.get("WEB_CONCURRENCY", "1"))
        except ValueError:
            raise ValueError("Port and worker count must be integers") from None
        return cls(
            db_url=values["NAV_DB_URL"],
            admin_token=values["NAV_ADMIN_TOKEN"],
            model_dir=Path(values["NAV_MODEL_DIR"]),
            environment=values.get("NAV_ENV", "development"),
            vision_device=values.get("NAV_VISION_DEVICE", "cpu"),
            log_level=values.get("NAV_LOG_LEVEL", "DEBUG"),
            host=values.get("NAV_HTTP_HOST", "127.0.0.1"),
            port=port,
            worker_count=workers,
        )
