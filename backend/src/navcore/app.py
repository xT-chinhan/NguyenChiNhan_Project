"""ASGI application factory. External resources belong to lifespan, never import."""

import asyncio
import logging
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI

from navcore.api.catalog import router as catalog_router
from navcore.api.fast import router as fast_router
from navcore.api.errors import RequestLimits, install_handlers
from navcore.api.health import router as health_router
from navcore.api.mobile import router as mobile_router
from navcore.api.sessions import router as sessions_router
from navcore.api.stream import router as stream_router
from navcore.logging import configure_logging
from navcore.runtime.sessions import SessionRegistry
from navcore.runtime.worker import ModelWorker
from navcore.settings import Settings
from navcore.storage.database import make_engine


def create_app(settings: Settings | None = None, vision=None, clock=None) -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        config = settings or Settings.from_env()
        configure_logging(config.log_level, (config.admin_token, config.db_url))
        logging.getLogger("navcore").info("startup")
        app.state.settings = config
        app.state.clock = clock or time.monotonic
        app.state.engine = make_engine(config.db_url)
        app.state.worker = ModelWorker(app.state.clock)
        app.state.admission_lock = asyncio.Lock()
        app.state.sessions = SessionRegistry(
            clock=app.state.clock, admission_lock=app.state.admission_lock, worker=app.state.worker
        )
        app.state.sessions.start()
        app.state.vision = vision
        try:
            if vision is None:
                try:
                    from navcore.vision.pipeline import VisionPipeline

                    # Startup admits no requests; loading is not a timed inference job.
                    app.state.vision = await asyncio.to_thread(
                        VisionPipeline.from_model_dir, config.model_dir, device=config.vision_device
                    )
                    logging.getLogger("navcore").info("model_load")
                except (ImportError, ValueError, OSError, RuntimeError):
                    logging.getLogger("navcore").warning("vision_not_ready")
            yield
        finally:
            await app.state.sessions.close()
            await app.state.worker.close()
            app.state.engine.dispose()
            logging.getLogger("navcore").info("shutdown")

    app = FastAPI(
        title="Navigation Core",
        version="0.1.0",
        lifespan=lifespan,
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
    )

    app.add_middleware(RequestLimits)
    install_handlers(app)
    app.include_router(health_router)
    app.include_router(catalog_router)
    app.include_router(sessions_router)
    app.include_router(stream_router)
    app.include_router(mobile_router)
    app.include_router(fast_router)
    return app
