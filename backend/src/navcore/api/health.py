import asyncio
import logging

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

from navcore.storage.database import ping

router = APIRouter()


@router.get("/health/live")
async def live():
    return {"status": "alive"}


@router.get("/health/ready")
async def ready(request: Request):
    state = request.app.state
    models_ready = state.vision is not None and not state.worker.check_fault()
    ready = await asyncio.to_thread(ping, state.engine) and models_ready
    if getattr(state, "last_readiness", None) is not ready:
        state.last_readiness = ready
        logging.getLogger("navcore").info("readiness", extra={"fields": {"ready": ready}})
    return JSONResponse(
        {"status": "ready" if ready else "not_ready"}, status_code=200 if ready else 503
    )
