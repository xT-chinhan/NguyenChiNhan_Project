import os

from alembic import context

from navcore.storage.database import make_engine
from navcore.storage.models import Base


def run():
    url = os.environ.get("NAV_DB_URL")
    if not url:
        raise ValueError("NAV_DB_URL is required for migration")
    if context.is_offline_mode():
        context.configure(
            url=url,
            target_metadata=Base.metadata,
            literal_binds=True,
            dialect_opts={"paramstyle": "named"},
        )
        with context.begin_transaction():
            context.run_migrations()
    else:
        engine = make_engine(url)
        try:
            with engine.connect() as connection:
                context.configure(connection=connection, target_metadata=Base.metadata)
                with context.begin_transaction():
                    context.run_migrations()
        finally:
            engine.dispose()


run()
