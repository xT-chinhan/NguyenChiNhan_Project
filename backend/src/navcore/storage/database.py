import asyncio
from contextlib import contextmanager
from functools import partial
from urllib.parse import urlsplit

from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session


def make_engine(url: str):
    return create_engine(
        url,
        pool_size=5,
        max_overflow=0,
        pool_pre_ping=True,
        connect_args={"connect_timeout": 2},
        hide_parameters=True,
    )


@contextmanager
def transaction(engine):
    with Session(engine, expire_on_commit=False) as session:
        with session.begin():
            yield session


def ping(engine) -> bool:
    try:
        with engine.connect() as connection:
            return connection.execute(text("SELECT 1")).scalar_one() == 1
    except Exception:
        return False


def require_test_database(url: str) -> str:
    parsed = urlsplit(url)
    if parsed.scheme != "postgresql+psycopg" or not parsed.path[1:].endswith("_test"):
        raise ValueError("Destructive integration checks require a PostgreSQL *_test database")
    return url


async def complete_thread(function, *args, **kwargs):
    """Retain caller locks until the real DB operation ends, including cancellation."""
    task = asyncio.create_task(asyncio.to_thread(partial(function, *args, **kwargs)))
    cancelled = False
    while True:
        try:
            result = await asyncio.shield(task)
            break
        except asyncio.CancelledError:
            if task.cancelled():
                raise
            cancelled = True
        except Exception:
            if cancelled:
                raise asyncio.CancelledError from None
            raise
    if cancelled:
        raise asyncio.CancelledError
    return result
